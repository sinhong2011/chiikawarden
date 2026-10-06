#!/usr/bin/env python3
"""Turns one version's section of CHANGELOG.md (as release-please writes it) into the HTML Sparkle shows in its
update window. No DOCTYPE or <body>, so generate_appcast embeds it in the appcast item.

    scripts/release-notes.py 0.2.0 [CHANGELOG.md] > Triwarden-0.2.0.html

Commit links are dropped (readers want what changed, not hashes); with no section for the version, a short
pointer to the GitHub release is written instead.
"""
import html
import re
import sys

STYLE = """<meta charset="utf-8">
<style>
  :root { color-scheme: light dark; }
  body, div { font: 13px -apple-system, system-ui, sans-serif; line-height: 1.45; }
  h3 { font-size: 13px; font-weight: 600; margin: 14px 0 4px; }
  h3:first-child { margin-top: 0; }
  ul { margin: 0; padding-left: 18px; }
  li { margin: 3px 0; }
  .breaking { color: #c2410c; }
  code { font: 12px ui-monospace, SFMono-Regular, monospace; }
  a { color: inherit; }
</style>"""


def section(changelog: str, version: str) -> list[str]:
    """The lines under `## [version]` (or `## version`), up to the next version heading."""
    lines, inside = [], False
    heading = re.compile(r"^##\s+\[?v?" + re.escape(version) + r"\]?(\s|\(|$)")
    for line in changelog.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = bool(heading.match(line))
            continue
        if inside:
            lines.append(line)
    return lines


def inline(text: str) -> str:
    """Escapes, then keeps `code` and **bold**, drops commit links like ([abc1234](…)) and plain issue links."""
    text = re.sub(r"\s*\(\[[0-9a-f]{7,40}\]\([^)]*\)\)", "", text)  # (commit hash link)
    text = re.sub(r"\[(#\d+)\]\([^)]*\)", r"\1", text)              # [#21](…) -> #21
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)            # other links -> their text
    out = html.escape(text.strip(), quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    return out


def render(lines: list[str]) -> str:
    parts, in_list, breaking = [], False, False
    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("### "):
            if in_list:
                parts.append("</ul>")
                in_list = False
            title = line[4:].strip()
            breaking = "BREAKING" in title.upper()
            title = "Breaking changes" if breaking else title
            attr = ' class="breaking"' if breaking else ""
            parts.append(f"<h3{attr}>{html.escape(title)}</h3>")
        elif re.match(r"^\s*[*-]\s+", line):
            if not in_list:
                parts.append("<ul>")
                in_list = True
            item = re.sub(r"^\s*[*-]\s+", "", line)
            item = item[:1].upper() + item[1:]  # commit subjects start lower-case; entries read as sentences
            parts.append(f"<li>{inline(item)}</li>")
        else:
            if in_list:
                parts.append("</ul>")
                in_list = False
            parts.append(f"<p>{inline(line)}</p>")
    if in_list:
        parts.append("</ul>")
    return "\n".join(parts)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: release-notes.py VERSION [CHANGELOG.md]")
    version = sys.argv[1].lstrip("v")
    path = sys.argv[2] if len(sys.argv) > 2 else "CHANGELOG.md"
    try:
        changelog = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        changelog = ""
    body = render(section(changelog, version))
    if not body:
        url = f"https://github.com/sinhong2011/triwarden/releases/tag/v{version}"
        body = f'<p>What\'s new in {html.escape(version)}: <a href="{url}">see the release on GitHub</a>.</p>'
    print(STYLE + "\n<div>\n" + body + "\n</div>")


if __name__ == "__main__":
    main()
