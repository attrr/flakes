#!/usr/bin/env python3
"""Update pkgs/cloudflare-ips/sources.json when upstream Cloudflare IP lists change."""

import datetime
import ipaddress
import json
import pathlib
import subprocess
import tempfile
import urllib.request


def fetch_and_hash(url: str, expected_version: int) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = resp.read()
    lines = [line.strip() for line in data.decode("utf-8").splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"{url}: empty response")
    for line in lines:
        net = ipaddress.ip_network(line, strict=True)
        if net.version != expected_version:
            raise ValueError(f"{url}: expected IPv{expected_version}, got {line}")

    with tempfile.NamedTemporaryFile() as tmp:
        tmp.write(data)
        tmp.flush()
        return subprocess.check_output(
            ["nix", "hash", "file", "--type", "sha256", "--sri", tmp.name],
            text=True,
        ).strip()


def find_sources_json() -> pathlib.Path:
    local = pathlib.Path(__file__).with_name("sources.json")
    if local.exists() and not str(local).startswith("/nix/store/"):
        return local
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()
    return pathlib.Path(root) / "pkgs" / "cloudflare-ips" / "sources.json"


def main() -> None:
    sources_path = find_sources_json()
    sources = json.loads(sources_path.read_text(encoding="utf-8"))

    v4_hash = fetch_and_hash(sources["v4"]["url"], 4)
    v6_hash = fetch_and_hash(sources["v6"]["url"], 6)

    if v4_hash == sources["v4"]["hash"] and v6_hash == sources["v6"]["hash"]:
        return

    sources["version"] = datetime.date.today().isoformat()
    sources["v4"]["hash"] = v4_hash
    sources["v6"]["hash"] = v6_hash
    sources_path.write_text(json.dumps(sources, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
