#!/usr/bin/env python3
import json
import os
import subprocess
import urllib.request

DIR = os.path.dirname(os.path.abspath(__file__))
SOURCES = os.path.join(DIR, "sources.json")

with urllib.request.urlopen(
    "https://api.github.com/repos/1013503897/jadx-headless-mcp/releases/latest"
) as r:
    rel = json.loads(r.read().decode("utf-8"))

version = rel["tag_name"].lstrip("v")
jar = next(a for a in rel["assets"] if a["name"].endswith("-all.jar"))
url = jar["browser_download_url"]
sha256 = subprocess.check_output(["nix-prefetch-url", url], text=True).strip()

with open(SOURCES, "w", encoding="utf-8") as f:
    json.dump({"version": version, "url": url, "sha256": sha256}, f, indent=2)
    f.write("\n")

print(f"[update] jadx-headless-mcp -> {version}")
