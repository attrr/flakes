#!/usr/bin/env python3
import json
import urllib.request
import re
import sys
import os

systems = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
    "x86_64-darwin": "darwin",
    "aarch64-darwin": "darwin-arm64"
}

version = ""
vscodeVersion = ""
sources = {}

def get_latest_information(target_system):
    global version, vscodeVersion
    url = f"https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/api/update/{target_system}/stable/latest"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req) as response:
        latest_info = json.loads(response.read().decode('utf-8'))

    match = re.search(r'/antigravity/stable/([\d.]+)-[\d]+', latest_info['url'])
    if not match:
        print(f"Could not parse Antigravity IDE version from {latest_info['url']}", file=sys.stderr)
        sys.exit(1)

    new_version = match.group(1)

    if version == "":
        version = new_version
    elif version != new_version:
        print(f"Version mismatch: {version} != {new_version}({target_system})", file=sys.stderr)
        sys.exit(1)

    if vscodeVersion == "":
        vscodeVersion = latest_info['productVersion']
    elif vscodeVersion != latest_info['productVersion']:
        print(f"VSCode version mismatch: {vscodeVersion} != {latest_info['productVersion']}({target_system})", file=sys.stderr)
        sys.exit(1)

    return {
        "url": latest_info['url'].replace(" ", "%20"),
        "sha256": latest_info['sha256hash']
    }

for nix_sys, api_sys in systems.items():
    sources[nix_sys] = get_latest_information(api_sys)

information = {
    "version": version,
    "vscodeVersion": vscodeVersion,
    "sources": sources
}

current_dir = os.path.dirname(os.path.abspath(__file__))
info_path = os.path.join(current_dir, "information.json")

with open(info_path, "w", encoding="utf-8") as f:
    json.dump(information, f, indent=2)
    f.write("\n")

print(f"[update] Updating Antigravity IDE complete, version: {version}, vscodeVersion: {vscodeVersion}")
