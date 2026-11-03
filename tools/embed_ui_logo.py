#!/usr/bin/env python3
"""Embed assets/jb-logo.png (the plain Jailbreak icon shown inside the UI) as a data URI.

The UI pages are cached offline and the autoloader pages are standalone, so the logo is
inlined rather than served as a file. The line between the JB-LOGO-START / JB-LOGO-END
markers is regenerated in:

    frontend/autoloader/theme-x.css        (loader header, .x-logo background)
    frontend/installer-page/index.html     (installer header, <img class="logo">)

Run after replacing assets/jb-logo.png (square, ~192x192):

    python3 tools/embed_ui_logo.py

The homescreen tile keeps its own icon (assets/icon.png, with the variant badge).
"""
import base64
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PNG = os.path.join(ROOT, "assets", "jb-logo.png")

# (file, start marker, end marker, line template)
TARGETS = [
    (
        os.path.join(ROOT, "frontend", "autoloader", "theme-x.css"),
        "/* JB-LOGO-START */", "/* JB-LOGO-END */",
        '#xHeader .x-logo {{ background-image: url("{uri}"); background-size: cover; }}',
    ),
    (
        os.path.join(ROOT, "frontend", "installer-page", "index.html"),
        "<!-- JB-LOGO-START -->", "<!-- JB-LOGO-END -->",
        '<img class="logo" src="{uri}" alt="Jailbreak" />',
    ),
]


def main():
    with open(PNG, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("Error: assets/jb-logo.png is not a PNG")
    uri = "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    for path, start, end, template in TARGETS:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
        found = pattern.findall(text)
        if len(found) != 1:
            sys.exit(f"Error: expected one {start} ... {end} block in "
                     f"{os.path.relpath(path, ROOT)}, found {len(found)}")
        block = start + template.format(uri=uri) + end
        new = pattern.sub(lambda m: block, text)
        if new != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
        print(f"{os.path.relpath(path, ROOT)}: logo embedded ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
