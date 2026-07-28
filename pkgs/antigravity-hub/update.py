#!/usr/bin/env python3
import json
import urllib.request
import re
import sys
import os
import subprocess

MANIFEST_BASE_URL = "https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest"
DOWNLOAD_BASE_URL = "https://storage.googleapis.com/antigravity-public/antigravity-hub"

def resolve_platform(channel_arch):
    url = f"{MANIFEST_BASE_URL}/latest-{channel_arch}-linux.yml"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            yaml_data = response.read().decode('utf-8')
    except Exception as e:
        print(f"Error: Failed to fetch manifest from {url}\n{e}", file=sys.stderr)
        sys.exit(1)

    version_match = re.search(r'^version:\s*([^\s]+)', yaml_data, re.MULTILINE)
    url_match = re.search(r'url:\s*(https://[^\s]+)', yaml_data)

    if not version_match or not url_match:
        print(f"Error: Failed to parse version or url from {url}", file=sys.stderr)
        sys.exit(1)

    ver = version_match.group(1).strip()
    download_url = url_match.group(1).strip()

    exec_id_match = re.search(r'/[\d.]+?-(\d+)/', download_url)
    if not exec_id_match:
        print(f"Error: Failed to parse execution ID from {download_url}", file=sys.stderr)
        sys.exit(1)

    exec_id = exec_id_match.group(1)
    return ver, exec_id

def prefetch(url):
    print(f"Prefetching {url}...", file=sys.stderr)
    result = subprocess.run(["nix", "store", "prefetch-file", "--json", url], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error prefetching {url}:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    data = json.loads(result.stdout)
    return data["hash"]

def version_tuple(v):
    return tuple(map(int, v.split('.')))

print("Checking latest releases...")
x64_version, x64_exec_id = resolve_platform("x64")
arm64_version, arm64_exec_id = resolve_platform("arm64")

if x64_version == arm64_version:
    target_version = x64_version
    target_exec_id = x64_exec_id
else:
    if version_tuple(x64_version) < version_tuple(arm64_version):
        target_version = x64_version
        target_exec_id = x64_exec_id
    else:
        target_version = arm64_version
        target_exec_id = arm64_exec_id
    print(f"Warning: Platform version mismatch detected (x64: {x64_version}, arm64: {arm64_version}).", file=sys.stderr)
    print(f"Enforcing same version across platforms by aligning to the lower version: {target_version}", file=sys.stderr)

x64_url = f"{DOWNLOAD_BASE_URL}/{target_version}-{target_exec_id}/linux-x64/Antigravity.tar.gz"
arm64_url = f"{DOWNLOAD_BASE_URL}/{target_version}-{target_exec_id}/linux-arm/Antigravity.tar.gz"

current_dir = os.path.dirname(os.path.abspath(__file__))
source_json = os.path.join(current_dir, "sources.json")

if os.path.exists(source_json):
    with open(source_json, "r", encoding="utf-8") as f:
        try:
            current_data = json.load(f)
            current_version = current_data.get("version")
            current_x64_url = current_data.get("sources", {}).get("x86_64-linux", {}).get("url")
            current_arm_url = current_data.get("sources", {}).get("aarch64-linux", {}).get("url")

            if current_x64_url == x64_url and current_arm_url == arm64_url:
                print(f"Antigravity Hub is already up to date (version: {target_version})")
                sys.exit(0)

            if current_version == target_version:
                print(f"Version is the same ({target_version}), but URLs have changed. Updating to fresh URLs...")
        except json.JSONDecodeError:
            pass

print("Updating Antigravity Hub...")
print(f"  Target Version: {target_version}")
print(f"  Target Exec ID: {target_exec_id}")
print(f"  x64 URL:        {x64_url}")
print(f"  arm64 URL:      {arm64_url}")

new_data = {
    "version": target_version,
    "sources": {
        "x86_64-linux": {
            "url": x64_url,
            "sha256": prefetch(x64_url),
            "sourceRoot": "Antigravity-x64"
        },
        "aarch64-linux": {
            "url": arm64_url,
            "sha256": prefetch(arm64_url),
            "sourceRoot": "Antigravity-arm64"
        }
    }
}

with open(source_json, "w", encoding="utf-8") as f:
    json.dump(new_data, f, indent=2)
    f.write("\n")

print(f"Successfully updated sources.json to {target_version}.")
