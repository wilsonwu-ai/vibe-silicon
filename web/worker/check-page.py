#!/usr/bin/env python3
"""Syntax-check the JS the BROWSER actually receives, not just worker.js.

`node --check src/worker.js` validates the worker. It does NOT validate the page
inside the PAGE template literal, because at that level the page is just a
string. The template literal also EATS BACKSLASHES before the browser sees them,
so a regex like /^\\s*$/ written in worker.js arrives as /^s*$/ and /\\r\\n/g
arrives containing a literal newline -- "Invalid regular expression: missing /",
and the entire page script dies silently.

That shipped once. This script exists so it cannot ship again.
"""
import os, re, subprocess, sys, tempfile

src = open(os.path.join(os.path.dirname(__file__), "src/worker.js"), encoding="utf-8").read()
m = re.search(r"const PAGE = `(.*)`;\s*$", src, re.S)
if not m:
    sys.exit("could not find the PAGE template literal")

page = m.group(1)
# Resolve the template literal the way the JS engine will: unescape \` and \$,
# and stand in a harmless literal for every ${...} interpolation.
page = page.replace("\\`", "`").replace("\\$", "$")
page = re.sub(r"\$\{[^}]*\}", '"__interp__"', page)

blocks = re.findall(r"<script>(.*?)</script>", page, re.S)
if not blocks:
    sys.exit("no inline <script> found in the page")

bad = 0
for i, b in enumerate(blocks):
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as t:
        t.write(b)
        path = t.name
    r = subprocess.run(["node", "--check", path], capture_output=True, text=True)
    if r.returncode != 0:
        bad += 1
        print(f"  block {i}: SYNTAX ERROR")
        print("   ", r.stderr.strip().split("\n")[0][:200])
    os.unlink(path)

if bad:
    print(f"\nFAILED -- {bad} block(s) would not parse in a browser. Do not deploy.")
    sys.exit(1)
print(f"  generated page JS: OK ({len(blocks)} block(s))")
