/* Made-up example for the README picture. No real project, person or company. */
const TITLE = "Version 2 release";
const RULER = "";
const STATE = {status: "live"};
const BRIEF = {
  date: "14 November 2026",
  lede: "Three choices before version 2 of the command-line tool ships. My pick is selected on each one, so most take a single click.",
  body: "Version 2 renames two commands and drops support for the oldest config format. About 3,400 people installed version 1 last month. A made-up example.",
  decided: [
    ["Version 1 gets security fixes for six months", "Anyone who cannot move yet stays safe."],
    ["The new config format is the default", "New installs never see the old one."]
  ],
  source: ["Read the release plan", "plan.html"]
};
const D = [
  {"id": "R1", "group": "Release", "title": "How the renamed commands behave", "q": "What should happen when someone types an old command name in version 2?", "opts": [["Run it, with a warning", "Old scripts keep working; the warning names the new command."], ["Stop with an error", "Clear, but every old script breaks on upgrade.", "Breaks scripts in CI on the day people upgrade."], ["Run it silently", "Nothing changes for anyone."]], "pick": 0, "why": "Most version 1 installs run inside scripts, and a warning moves people without breaking them.", "flip": "the warnings turn out to break tools that read the output.", "ev": "Last month 71% of runs came from scripts, read from the anonymous usage counts."},
  {"id": "R2", "group": "Release", "title": "Where the upgrade guide lives", "q": "Where should the guide for moving from version 1 to version 2 go?", "opts": [["A page on the docs site", "Searchable, and linked from the warning."], ["The release notes", "One place, but long and hard to find later."], ["Both", "Two copies to keep the same.", "They drift apart within a release."]], "pick": 0, "why": "The warning can link one stable page, and the release notes can point to it.", "ev": "Two of the last three releases changed their notes after shipping."},
  {"id": "R3", "group": "Release", "title": "When version 2 ships", "q": "When should version 2 go out?", "opts": [["Next Tuesday", "The guide and the warnings are ready."], ["After a two-week beta", "Early users find problems first.", "Two more weeks on two branches."]], "pick": 1, "why": "The config change is the riskiest part, and a beta is the cheapest way to see it in real setups.", "flip": "the beta has fewer than 50 people sign up in its first two days.", "ev": "The config reader has 14 open edge cases in the tracker."}
];
