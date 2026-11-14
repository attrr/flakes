#!/usr/bin/env python3
import json
import os
import re
import urllib.request

DIR = os.path.dirname(os.path.abspath(__file__))
SOURCES = os.path.join(DIR, "sources.json")
REA_SOURCES = os.path.join(DIR, "..", "rea", "sources.json")

with open(REA_SOURCES, encoding="utf-8") as f:
    rea_version = json.load(f)["version"]

with urllib.request.urlopen(
    f"https://raw.githubusercontent.com/morluto/rea/rea-agents-{rea_version}/src/android/JadxRelease.ts"
) as r:
    js = r.read().decode("utf-8")

block = re.search(r"JADX_RELEASE\s*=\s*Object\.freeze\(\{(.*?)\}\)", js, re.S)
assert block is not None, "JADX_RELEASE block not found"
body = block.group(1)


def field(name: str) -> str:
    m = re.search(rf'{name}:\s*"([^"]+)"', body)
    assert m is not None, f"{name} not found in JADX_RELEASE"
    return m.group(1)


version = field("version")
url = field("url")
sha256 = field("sha256")

with open(SOURCES, "w", encoding="utf-8") as f:
    json.dump({"version": version, "url": url, "sha256": sha256}, f, indent=2)
    f.write("\n")

print(f"[update] jadx-headless-mcp -> {version} (from rea {rea_version})")
