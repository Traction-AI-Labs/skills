"""The shared parts of the house pages stay the same.

    python3 -I same.py <ruling.html> <threads.html> <reading.html> <prep.html>

Two checks, exit 1 on any difference:
  engine  the ruling and open-questions templates carry one engine: the script from the line
          "Ruling page engine. Authors never edit below this line." to its </script> is the same text in both
  tokens  a --tp-* token set in more than one template has one value, theme by theme: the light block
          (:where(.tp)), the dark block for the system setting (inside prefers-color-scheme: dark) and the dark
          block for the toggle (:where(.tp)[data-theme="dark"])
"""
import re
import sys

ENGINE = "/* Ruling page engine. Authors never edit below this line. */"
THEMES = {
    ("", ":where(.tp)"): "light",
    ("(prefers-color-scheme: dark)", ':where(.tp):not([data-theme="light"])'): "dark (system)",
    ("", ':where(.tp)[data-theme="dark"]'): "dark (toggle)",
}


def engine(text):
    i = text.find(ENGINE)
    return None if i < 0 else text[i:text.index("</script>", i)]


def rules(css):
    """Innermost rules as (media prelude or "", selector, body), ignoring @layer wrappers."""
    css = re.sub(r"/\*[\s\S]*?\*/", "", css)
    out, stack, start = [], [], 0
    for i, ch in enumerate(css):
        if ch == "{":
            stack.append(" ".join(css[start:i].split()))
            start = i + 1
        elif ch == "}":
            if stack:
                pre = stack.pop()
                body = css[start:i]
                if not pre.startswith("@") and "{" not in body:
                    media = [p for p in stack if p.startswith("@media")]
                    out.append((media[-1][len("@media"):].strip() if media else "", pre, body))
            start = i + 1
        elif ch == ";" and not stack:
            start = i + 1
    return out


def tokens(text):
    css = "".join(re.findall(r"<style[^>]*>([\s\S]*?)</style>", text))
    got = {}
    for media, sel, body in rules(css):
        theme = THEMES.get((media, sel))
        if theme:
            for k, v in re.findall(r"(--tp-[\w-]+)\s*:\s*([^;]+)", body):
                got.setdefault(theme, {})[k] = " ".join(v.split()).lower()
    return got


def main(paths):
    texts = {p: open(p, encoding="utf-8").read() for p in paths}
    bad = []
    a, b = engine(texts[paths[0]]), engine(texts[paths[1]])
    if a is None or b is None:
        bad.append("engine: marker line missing in %s" % (paths[0] if a is None else paths[1]))
    elif a != b:
        la, lb = a.splitlines(), b.splitlines()
        n = next((i for i, (x, y) in enumerate(zip(la, lb)) if x != y), min(len(la), len(lb)))
        bad.append("engine: %s and %s differ at engine line %d" % (paths[0], paths[1], n + 1))
    tok = {p: tokens(t) for p, t in texts.items()}
    for theme in THEMES.values():
        names = sorted({k for p in paths for k in tok[p].get(theme, {})})
        for k in names:
            vals = {p: tok[p][theme][k] for p in paths if k in tok[p].get(theme, {})}
            if len(set(vals.values())) > 1:
                bad.append("tokens: %s %s differs: %s" % (theme, k, ", ".join("%s=%s" % (p.split("/")[-1] if "threads" in p or "prep" in p else "/".join(p.split("/")[-3:]), v) for p, v in vals.items())))
        if not any(tok[p].get(theme) for p in paths):
            bad.append("tokens: no %s block found" % theme)
    for line in bad:
        print(line)
    n = sum(len(tok[p].get(t, {})) for p in paths for t in THEMES.values())
    print("%d differences (engine compared, %d token settings across %d pages)" % (len(bad), n, len(paths)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
