"""Writes the README's generated regions and .claude-plugin/marketplace.json from each plugin's own files.

Usage, from anywhere in the repository (standard library only, no network):

  python3 -I scripts/readme/build.py            rewrite the generated regions and marketplace.json
  python3 -I scripts/readme/build.py --check    write nothing; exit 1 naming the file and the fix if anything is stale
  python3 -I scripts/readme/build.py --accept <plugin|banner> --reason "<why the picture still holds>"
                                                record that a picture still holds at the current version and inputs
  python3 -I scripts/readme/build.py --record <plugin|banner>
                                                record a fresh render (scripts/media/render.sh calls this)

One source per fact:
  plugins/<name>/.claude-plugin/plugin.json   name, version, description (description feeds marketplace.json only)
  scripts/readme/cards/<name>.toml            the README card (kept outside plugins/: the plugin directory takes only
                                              Markdown, text, JSON, YAML and images from an unverified organisation)
  CHANGELOG.md                                the history; the README shows the three newest heads
  docs/examples/<name>/                       the made-up inputs the pictures are rendered from
  docs/media/manifest.json                    the fingerprint of every picture and every file its render read
"""
import argparse
import fcntl
import hashlib
import json
import os
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
MARKET = ROOT / ".claude-plugin" / "marketplace.json"
MANIFEST = ROOT / "docs" / "media" / "manifest.json"
PREREQ = ROOT / "docs" / "cards" / "gauntlet-prerequisites.md"
PLUGINS = ROOT / "plugins"
CARDS = ROOT / "scripts" / "readme" / "cards"

GROUPS = ("pages", "reviews", "writing")
KINDS = ("page", "gif", "terminal", "text")
PICTURE_KINDS = ("page", "gif", "terminal")
# The [visual] fields each kind must name. A terminal is dark in both themes, so its light and dark are one file.
VISUAL_FIELDS = {
    "page": ("light", "dark", "light_phone", "dark_phone", "alt", "sources"),
    "gif": ("gif", "gif_phone", "light", "light_phone", "alt", "sources"),
    "terminal": ("light", "light_phone", "alt", "sources"),
    "text": ("label",),
}
CARD_FIELDS = ("group", "order", "tagline", "gets", "try", "runs_in", "needs", "scan_needs")
# Every render reads these, so a change to any of them makes every picture stale.
RENDER_FILES = ("scripts/media/render.sh", "scripts/media/fill.py", "scripts/media/freeze.js")
BANNER = {
    "inputs": ("docs/media/banner/banner.html", "docs/media/banner/traction-studio-logo-white-transparent.png",
               "docs/media/fonts/spectral-300.woff2", "docs/media/fonts/spectral-300-italic.woff2",
               "docs/media/fonts/inter-400.woff2", "docs/media/fonts/jetbrains-mono-400.woff2"),
    "outputs": ("docs/media/banner.webp", "docs/media/banner-phone.webp"),
}
# Shapes a token takes, and home-directory paths: none may appear in a card, an example or a generated region.
LEAKS = (
    (re.compile(r"/home/|/Users/"), "a home-directory path"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"), "an API key shape (sk-)"),
    (re.compile(r"\bghp_[A-Za-z0-9]{20,}"), "a GitHub token shape (ghp_)"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "a Slack token shape (xox)"),
)
REGIONS = ("install:others", "plugins:list", "cards:pages", "cards:reviews", "cards:writing", "changes:latest")
PAGE_CAPTION = "<sub>Made-up example, rendered from the plugin's own template by a script.</sub>"
TERMINAL_CAPTION = ("<sub>Made-up example: a scripted replay of one round, the runner's own lines and then the summary "
                    "the skill writes.</sub>")
WORDS = ("no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve")


class Stale(Exception):
    """One problem --check reports: what is wrong, in which file, and the fix."""


def rel(p):
    return Path(p).resolve().relative_to(ROOT).as_posix()


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def version_key(v):
    if not re.fullmatch(r"\d+\.\d+\.\d+", v):
        raise Stale(f"version {v!r} is not x.y.z")
    return tuple(int(x) for x in v.split("."))


# ---------- reading the sources ----------

def load_plugins(problems, files=True):
    plugins = {}
    for d in sorted(p for p in PLUGINS.iterdir() if p.is_dir()):
        manifest = d / ".claude-plugin" / "plugin.json"
        if not manifest.is_file():
            problems.append(f"{rel(d)}: no .claude-plugin/plugin.json. Fix: add one, or remove the folder.")
            continue
        try:
            meta = json.loads(manifest.read_text())
        except json.JSONDecodeError as e:
            problems.append(f"{rel(manifest)}: not valid JSON ({e}).")
            continue
        if not isinstance(meta, dict) or not all(isinstance(meta.get(k), str) for k in ("name", "version", "description")):
            problems.append(f"{rel(manifest)}: needs string fields name, version and description.")
            continue
        if meta.get("name") != d.name:
            problems.append(f"{rel(manifest)}: name {meta.get('name')!r} is not the folder name {d.name!r}.")
            continue
        card_path = CARDS / f"{d.name}.toml"
        if not card_path.is_file():
            problems.append(f"{rel(d)}: no card ({rel(card_path)}). Fix: add {rel(card_path)} (copy another plugin's and edit it), "
                            "then run python3 -I scripts/readme/build.py.")
            continue
        try:
            card = tomllib.loads(card_path.read_text())
        except tomllib.TOMLDecodeError as e:
            problems.append(f"{rel(card_path)}: not valid TOML ({e}).")
            continue
        errs, missing = check_card(d.name, card, card_path, files)
        problems.extend(errs + missing)
        if errs:
            continue
        plugins[d.name] = {"meta": meta, "card": card, "card_path": card_path}
    return plugins


def check_card(name, card, path, files=True):
    """Returns (errors that make the card unusable, picture files it names that do not exist)."""
    errs, missing = [], []
    where = rel(path)
    for f in ("group", "tagline", "gets", "try", "needs", "scan_needs"):
        if f in card and not isinstance(card[f], str):
            errs.append(f"{where}: {f} must be text.")
    for f in CARD_FIELDS:
        v = card.get(f)
        if v is None or (isinstance(v, str) and not v.strip()) or (isinstance(v, list) and not v):
            errs.append(f"{where}: the card lacks {f!r}. Fix: add it.")
    if card.get("group") not in GROUPS + (None,):
        errs.append(f"{where}: group {card.get('group')!r} is not one of {', '.join(GROUPS)}.")
    if "runs_in" in card and not (isinstance(card["runs_in"], list) and all(isinstance(x, str) and x for x in card["runs_in"])):
        errs.append(f"{where}: runs_in must be a list of names.")
    if "order" in card and not isinstance(card["order"], int):
        errs.append(f"{where}: order must be a whole number.")
    vis = card.get("visual")
    if not isinstance(vis, dict):
        return errs + [f"{where}: the card lacks its [visual] table. Fix: add one (kind = page, gif, terminal or text)."], missing
    kind = vis.get("kind")
    if kind not in KINDS:
        return errs + [f"{where}: [visual] kind {kind!r} is not one of {', '.join(KINDS)}."], missing
    for f, v in vis.items():
        if f == "sources":
            if not (isinstance(v, list) and all(isinstance(x, str) for x in v)):
                errs.append(f"{where}: [visual] sources must be a list of paths.")
        elif not isinstance(v, str):
            errs.append(f"{where}: [visual] {f} must be text.")
    if errs:
        return errs, missing
    for f in VISUAL_FIELDS[kind]:
        v = vis.get(f)
        if v is None or (isinstance(v, str) and not v.strip()) or (isinstance(v, list) and not v):
            errs.append(f"{where}: [visual] kind {kind} needs {f!r}. Fix: add it.")
    if kind in PICTURE_KINDS and files:
        for f in ("light", "dark", "light_phone", "dark_phone", "gif", "gif_phone"):
            if vis.get(f) and not (ROOT / vis[f]).is_file():
                missing.append(f"{where}: [visual] {f} names {vis[f]}, which does not exist. "
                            f"Fix: scripts/media/render.sh {name}.")
    if kind in PICTURE_KINDS:
        for s in vis.get("sources") or []:
            if not (ROOT / s).is_file():
                errs.append(f"{where}: [visual] sources names {s}, which does not exist.")
        examples = ROOT / "docs" / "examples" / name
        if not examples.is_dir() or not any(p.is_file() for p in examples.rglob("*")):
            errs.append(f"{where}: a picture card needs its made-up input under docs/examples/{name}/.")
        alt = vis.get("alt") or ""
        if len(alt.split()) < 8:
            errs.append(f"{where}: [visual] alt must say what the picture shows, in at least 8 words.")
    else:
        if not str(vis.get("label", "")).startswith("Made-up example."):
            errs.append(f"{where}: [visual] label must start \"Made-up example.\"")
        if not (vis.get("text") or (vis.get("before") and vis.get("after"))):
            errs.append(f"{where}: a text card needs [visual] text, or before and after.")
    if card.get("prerequisites") and card.get("group") != "reviews":
        errs.append(f"{where}: prerequisites = true belongs to a review card only.")
    return errs, missing


def ordered(plugins):
    return sorted(plugins, key=lambda n: (GROUPS.index(plugins[n]["card"]["group"]), plugins[n]["card"]["order"], n))


def changelog_heads():
    heads = re.findall(r"^- (\*\*(.+?)\*\* \(([^)]+)\))", CHANGELOG.read_text(), re.M)
    return [(full, bold) for full, bold, _ in heads]


# ---------- writing ----------

def picture(vis):
    alt = vis["alt"].replace('"', "&quot;")
    k = vis["kind"]
    if k == "page":
        return ("<picture>\n"
                f'  <source media="(max-width: 767px) and (prefers-color-scheme: dark)" srcset="{vis["dark_phone"]}">\n'
                f'  <source media="(max-width: 767px)" srcset="{vis["light_phone"]}">\n'
                f'  <source media="(prefers-color-scheme: dark)" srcset="{vis["dark"]}">\n'
                f'  <img alt="{alt}" src="{vis["light"]}" width="100%">\n</picture>')
    if k == "gif":
        return ("<picture>\n"
                f'  <source media="(max-width: 767px) and (prefers-reduced-motion: reduce)" srcset="{vis["light_phone"]}">\n'
                f'  <source media="(prefers-reduced-motion: reduce)" srcset="{vis["light"]}">\n'
                f'  <source media="(max-width: 767px)" srcset="{vis["gif_phone"]}">\n'
                f'  <img alt="{alt}" src="{vis["gif"]}" width="100%">\n</picture>')
    return ("<picture>\n"
            f'  <source media="(max-width: 767px)" srcset="{vis["light_phone"]}">\n'
            f'  <img alt="{alt}" src="{vis["light"]}" width="100%">\n</picture>')


def quote(s):
    return "\n".join("> " + line if line else ">" for line in s.strip("\n").split("\n"))


def text_example(vis):
    label = vis["label"][len("Made-up example."):].strip()
    if vis.get("text"):
        return f"<sub>Made-up example.</sub> {label}:\n\n```text\n{vis['text'].strip(chr(10))}\n```"
    return (f"<sub>Made-up example.</sub> {label}.\n\n**Before**\n\n{quote(vis['before'])}\n\n"
            f"**After**\n\n{quote(vis['after'])}")


def prerequisites():
    paras = [p for p in PREREQ.read_text().strip("\n").split("\n\n")]
    note = [p for p in paras if "--authorize-provider" in p]
    if len(note) != 1:
        raise Stale(f"{rel(PREREQ)}: exactly one paragraph must name --authorize-provider (the unfolded note).")
    rest = "\n\n".join(p for p in paras if p is not note[0])
    return ("> [!IMPORTANT]\n" + quote(note[0]) + "\n\n<details>\n<summary>Before you run it</summary>\n\n"
            + rest + "\n\n</details>")


def card_md(name, p):
    c, vis = p["card"], p["card"]["visual"]
    parts = [f"### {name}", c["tagline"]]
    if vis["kind"] == "text":
        parts.append(text_example(vis))
    else:
        parts += [picture(vis), PAGE_CAPTION if vis["kind"] == "page" else TERMINAL_CAPTION]
    parts += [f"**What you get:** {c['gets']}",
              f"**Install:**\n\n```text\n/plugin install {name}@traction\n```",
              f"**Try it:** ask Claude\n\n> {c['try']}",
              f"**Runs in:** {', '.join(c['runs_in'])}  \n**Needs:** {c['needs']}"]
    if c.get("prerequisites"):
        parts.append(prerequisites())
    parts.append(f"Version {p['meta']['version']} · [Plugin README](plugins/{name}/README.md) · [Changelog](CHANGELOG.md)")
    return "\n\n".join(parts)


REGION_RX = re.compile(r"<!-- (?P<name>[a-z:]+):start -->\n(?P<body>(?:.*?\n)?)<!-- (?P=name):end -->", re.S)


def outside_regions(text):
    return REGION_RX.sub("", text)


def regions(plugins, readme):
    names = ordered(plugins)
    main_installs = set(re.findall(r"^/plugin install ([a-z0-9-]+)@traction$", outside_regions(readme), re.M))
    others = [n for n in names if n not in main_installs]
    word = WORDS[len(others)] if len(others) < len(WORDS) else str(len(others))
    heads = changelog_heads()
    out = {
        "install:others": (f"<details>\n<summary>Install the other {word}</summary>\n\n```text\n"
                           + "\n".join(f"/plugin install {n}@traction" for n in others) + "\n```\n\n</details>"),
        "plugins:list": "\n".join(
            f"- [**{n}**](#{n}) {plugins[n]['meta']['version']}: {plugins[n]['card']['tagline']} "
            f"{plugins[n]['card']['scan_needs']}" for n in names),
        "changes:latest": "\n".join(f"- {full}" for full, _ in heads[:3]) + "\n\nFull history: [CHANGELOG.md](CHANGELOG.md)",
    }
    for g in GROUPS:
        out[f"cards:{g}"] = "\n\n".join(card_md(n, plugins[n]) for n in names if plugins[n]["card"]["group"] == g)
    return out


def region_problems(readme):
    errs = []
    for name in REGIONS:
        starts, ends = readme.count(f"<!-- {name}:start -->"), readme.count(f"<!-- {name}:end -->")
        if starts == 0 and ends == 0:
            errs.append(f"README.md: the generated region {name} is missing. Fix: add "
                        f"<!-- {name}:start --> and <!-- {name}:end --> where it belongs.")
        elif starts != 1 or ends != 1 or len([m for m in REGION_RX.finditer(readme) if m.group("name") == name]) != 1:
            errs.append(f"README.md: the generated region {name} must appear exactly once, start and end "
                        f"(found {starts} start and {ends} end markers). Fix: keep one of each.")
    return errs


def render_readme(readme, gen, problems):
    problems += region_problems(readme)
    return REGION_RX.sub(lambda m: (f"<!-- {m.group('name')}:start -->\n{gen[m.group('name')]}\n<!-- {m.group('name')}:end -->"
                                    if m.group("name") in gen else m.group(0)), readme)


PINNED_OWNER = {"name": "Traction Studio", "url": "https://github.com/Traction-AI-Labs"}


def marketplace(plugins, current):
    order = []
    listed = current.get("plugins") if isinstance(current.get("plugins"), list) else []
    for e in listed:
        if isinstance(e, dict) and isinstance(e.get("name"), str) and e["name"] in plugins and e["name"] not in order:
            order.append(e["name"])
    order += sorted(n for n in plugins if n not in order)
    metadata = current.get("metadata") if isinstance(current.get("metadata"), dict) else {}
    data = {"name": "traction", "owner": PINNED_OWNER, "metadata": metadata,
            "plugins": [{"name": n, "source": f"./plugins/{n}", "description": plugins[n]["meta"]["description"],
                         "version": plugins[n]["meta"]["version"]} for n in order]}
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def marketplace_shape(current):
    errs = []
    if not isinstance(current, dict):
        return ["it must be a JSON object"]
    if not isinstance(current.get("plugins"), list) or not all(isinstance(e, dict) for e in current["plugins"]):
        return ["plugins must be a list of objects"]
    if not all(isinstance(e.get(k), str) for e in current["plugins"] for k in ("name", "source", "description", "version")):
        return ["every plugins[] entry needs string name, source, description and version"]
    names = [e.get("name") for e in current["plugins"]]
    for n in sorted({n for n in names if names.count(n) > 1}, key=str):
        errs.append(f"plugin {n!r} is listed {names.count(n)} times; each plugin is listed once")
    if set(current) != {"name", "owner", "metadata", "plugins"}:
        errs.append("top-level keys must be exactly name, owner, metadata, plugins")
    if current.get("name") != "traction":
        errs.append("name must stay \"traction\" (installs resolve <plugin>@traction)")
    if current.get("owner") != PINNED_OWNER:
        errs.append("owner changed")
    for e in current.get("plugins", []):
        if set(e) != {"name", "source", "description", "version"}:
            errs.append(f"plugin entry {e.get('name')!r} must have exactly name, source, description, version")
        elif e["source"] != f"./plugins/{e['name']}":
            errs.append(f"plugin entry {e['name']!r} source must be ./plugins/{e['name']}")
    return errs


# ---------- the picture manifest ----------

def picture_entry_files(name, plugins):
    """The files a render of <name> reads and writes, as repository paths."""
    if name == "banner":
        return list(RENDER_FILES) + list(BANNER["inputs"]), list(BANNER["outputs"])
    vis = plugins[name]["card"]["visual"]
    examples = sorted(rel(p) for p in (ROOT / "docs" / "examples" / name).rglob("*") if p.is_file())
    inputs = examples + list(vis["sources"]) + list(RENDER_FILES)
    outputs = []
    for f in ("light", "dark", "light_phone", "dark_phone", "gif", "gif_phone"):
        if vis.get(f) and vis[f] not in outputs:
            outputs.append(vis[f])
    return inputs, outputs


def picture_names(plugins):
    return [n for n in ordered(plugins) if plugins[n]["card"]["visual"]["kind"] in PICTURE_KINDS] + ["banner"]


def load_manifest():
    if not MANIFEST.is_file():
        return {}
    try:
        m = json.loads(MANIFEST.read_text())
    except json.JSONDecodeError as e:
        raise Stale(f"docs/media/manifest.json: not valid JSON ({e}). Fix: git checkout -- docs/media/manifest.json, then scripts/media/render.sh <name> for any picture it names as stale.")
    ok = isinstance(m, dict) and all(
        isinstance(e, dict) and isinstance(e.get("inputs"), dict) and isinstance(e.get("outputs"), dict)
        and all(isinstance(v, str) for v in list(e["inputs"].values()) + list(e["outputs"].values()))
        and isinstance(e.get("reason", ""), str)
        and (k == "banner" or re.fullmatch(r"\d+\.\d+\.\d+", str(e.get("checked_at_version"))))
        for k, e in m.items())
    if not ok:
        raise Stale("docs/media/manifest.json: each entry needs inputs and outputs objects of path to SHA-256, and "
                    "each plugin entry a checked_at_version of the form x.y.z. Fix: git checkout -- docs/media/manifest.json, then scripts/media/render.sh <name> for any picture it names as stale.")
    return m


def write_manifest(m):
    tmp = MANIFEST.with_name(f".manifest.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(dict(sorted(m.items())), indent=2) + "\n")
    os.replace(tmp, MANIFEST)


def manifest_problems(plugins, manifest):
    errs = []
    for name in picture_names(plugins):
        e = manifest.get(name)
        fix = f"scripts/media/render.sh {name}, or build.py --accept {name} --reason \"...\""
        if e is None:
            errs.append(f"docs/media/manifest.json: no entry for {name}. Fix: scripts/media/render.sh {name}.")
            continue
        if name != "banner":
            v = plugins[name]["meta"]["version"]
            seen = e.get("checked_at_version")
            if not seen or version_key(v) > version_key(seen):
                errs.append(f"{name} picture checked at {seen}, plugin at {v}. Fix: {fix}.")
        inputs, outputs = picture_entry_files(name, plugins)
        recorded_in, recorded_out = e.get("inputs", {}), e.get("outputs", {})
        for f in inputs:
            if f not in recorded_in:
                errs.append(f"{name}: input {f} is not in the manifest. Fix: {fix}.")
        for f in recorded_in:
            if not (ROOT / f).is_file():
                errs.append(f"{name}: input {f} is missing. Fix: {fix}.")
            elif sha(f) != recorded_in[f]:
                errs.append(f"{name}: input {f} changed since the picture was made. Fix: {fix}.")
        for f in outputs:
            if f not in recorded_out:
                errs.append(f"{name}: picture {f} is not in the manifest. Fix: scripts/media/render.sh {name}.")
        for f in recorded_out:
            if not (ROOT / f).is_file():
                errs.append(f"{name}: picture {f} is missing. Fix: scripts/media/render.sh {name}.")
            elif sha(f) != recorded_out[f]:
                errs.append(f"{name}: picture {f} no longer matches its fingerprint. Fix: scripts/media/render.sh {name}.")
    for name in manifest:
        if name not in picture_names(plugins):
            errs.append(f"docs/media/manifest.json: entry {name} has no picture card. Fix: remove it.")
    return errs


def record(name, plugins, reason):
    if name not in picture_names(plugins):
        raise SystemExit(f"build.py: {name} has no picture (its card's kind is text, or it is not a plugin).")
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST.with_name(".manifest.lock"), "w") as lock:
        try:  # one writer at a time, so two renders or accepts never drop each other's entry
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(f"build.py: another render or accept is recording in docs/media/manifest.json; "
                             f"nothing was recorded for {name}. Run the same command again when it has finished.")
        try:
            m = load_manifest()
        except Stale as e:
            raise SystemExit(f"build.py: {e} Nothing was recorded.")
        record_entry(name, plugins, reason, m)


def record_entry(name, plugins, reason, m):
    inputs, outputs = picture_entry_files(name, plugins)
    entry = {}
    if name != "banner":
        entry["checked_at_version"] = plugins[name]["meta"]["version"]
    entry["reason"] = reason
    entry["inputs"] = {f: sha(f) for f in inputs}
    if reason:  # an accept leaves the picture as it is, so its recorded fingerprints stay
        entry["outputs"] = m.get(name, {}).get("outputs", {})
        if not entry["outputs"]:
            raise SystemExit(f"build.py: {name} has never been rendered; run scripts/media/render.sh {name}.")
    else:
        entry["outputs"] = {f: sha(f) for f in outputs}
    m[name] = entry
    write_manifest(m)
    print(f"build.py: recorded {name} in docs/media/manifest.json")


# ---------- the checks ----------

def leak_problems(plugins, gen):
    errs = []
    texts = [(rel(p["card_path"]), p["card_path"].read_text()) for p in plugins.values()]
    texts += [(rel(f), f.read_text(errors="replace")) for f in sorted((ROOT / "docs" / "examples").rglob("*")) if f.is_file()]
    texts += [(f"README.md region {k}", v) for k, v in gen.items()]
    for where, text in texts:
        for rx, what in LEAKS:
            if rx.search(text):
                errs.append(f"{where}: holds {what}. Fix: take it out.")
    return errs


def changelog_problems(plugins):
    bolds = [b for _, b in changelog_heads()]
    errs = []
    for n, p in plugins.items():
        v = p["meta"]["version"]
        rx = re.compile(rf"(?<![\w-]){re.escape(n)} {re.escape(v)}(?![\w.])")
        if not any(rx.search(b) for b in bolds):
            errs.append(f"CHANGELOG.md: no entry head names {n} {v}. Fix: add an entry at the top for {n} {v}.")
    return errs


def build(check):
    problems = []
    plugins = load_plugins(problems, files=check)
    readme = README.read_text()
    try:
        gen = regions(plugins, readme) if plugins else {}
        new_readme = render_readme(readme, gen, problems)
    except Stale as e:
        problems.append(str(e))
        gen, new_readme = {}, readme
    try:
        current = json.loads(MARKET.read_text())
    except json.JSONDecodeError as e:
        problems.append(f".claude-plugin/marketplace.json: not valid JSON ({e}). Fix: restore it from git, then run "
                        "python3 -I scripts/readme/build.py.")
        current = {}
    shape = marketplace_shape(current)
    new_market = marketplace(plugins, current if isinstance(current, dict) else {})
    unusable = sorted(d.name for d in PLUGINS.iterdir()
                      if d.is_dir() and (CARDS / f"{d.name}.toml").is_file() and d.name not in plugins)
    if check and unusable:
        problems.append("Fix the card above first (" + ", ".join(unusable) + "): README.md, marketplace.json and the "
                        "manifest were not compared while a card is unusable.")
    elif check:
        have = {m.group("name"): m.group("body") for m in REGION_RX.finditer(readme)}
        for name, body in gen.items():
            if name in have and have[name] != body + "\n":
                problems.append(f"README.md: generated region {name} is stale. Fix: python3 -I scripts/readme/build.py.")
        if MARKET.read_text() != new_market:
            problems.append(".claude-plugin/marketplace.json differs from what the generator writes from each "
                            "plugin.json. Fix: python3 -I scripts/readme/build.py (never edit it by hand).")
        problems += [f".claude-plugin/marketplace.json: {e}." for e in shape]
        try:
            problems += manifest_problems(plugins, load_manifest())
        except Stale as e:
            problems.append(str(e))
        problems += changelog_problems(plugins)
        committed = {f"{m.group('name')} (as committed, occurrence {i})": m.group("body")
                     for i, m in enumerate(REGION_RX.finditer(readme), 1)}
        problems += leak_problems(plugins, {**gen, **committed})
    if check:
        if problems:
            for p in problems:
                print("STALE: " + p)
            print(f"build.py --check: {len(problems)} problem(s)")
            return 1
        print(f"build.py --check: ok ({len(plugins)} plugins, {len(picture_names(plugins))} pictures)")
        return 0
    if problems:
        for p in problems:
            print("ERROR: " + p)
        return 1
    README.write_text(new_readme)
    MARKET.write_text(new_market)
    print("build.py: wrote README.md regions and .claude-plugin/marketplace.json")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true", help="write nothing; exit 1 if anything is stale")
    g.add_argument("--accept", metavar="NAME", help="record that NAME's picture still holds (needs --reason)")
    g.add_argument("--record", metavar="NAME", help="record a fresh render of NAME (render.sh calls this)")
    ap.add_argument("--reason", default="")
    a = ap.parse_args()
    if a.accept or a.record:
        problems = []
        plugins = load_plugins(problems, files=False)
        if problems:
            for p in problems:
                print("ERROR: " + p)
            return 1
        if a.accept:
            if not a.reason.strip():
                ap.error("--accept needs --reason \"<why the picture still holds>\"")
            record(a.accept, plugins, a.reason.strip())
        else:
            record(a.record, plugins, "")
        return 0
    return build(a.check)


if __name__ == "__main__":
    sys.exit(main())
