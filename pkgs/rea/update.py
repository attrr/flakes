#!/usr/bin/env python3
import json
import os
import re
import subprocess
import urllib.request

DIR = os.path.dirname(os.path.abspath(__file__))
SOURCES = os.path.join(DIR, "sources.json")
DUMMY = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

def write_sources(data):
    with open(SOURCES, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

with urllib.request.urlopen("https://registry.npmjs.org/rea-agents/latest") as r:
    latest = json.loads(r.read().decode("utf-8"))

data = {
    "version": latest["version"],
    "url": latest["dist"]["tarball"],
    "hash": latest["dist"]["integrity"],
    "npmDepsHash": DUMMY,
}
write_sources(data)

proc = subprocess.run(["nix", "build", "--no-link", ".#rea"], cwd=os.path.join(DIR, "../.."), text=True, capture_output=True)
m = re.search(r"got:\s+(sha256-\S+)", proc.stderr)
if not m:
    raise SystemExit(proc.stderr)

data["npmDepsHash"] = m.group(1)
write_sources(data)
print(f"[update] rea -> {data['version']}")
