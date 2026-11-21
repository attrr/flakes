#!/usr/bin/env python3
"""Validate fetched Cloudflare IP lists and render Caddy / nftables outputs."""

import ipaddress
import pathlib
import sys


def load_cidrs(path: pathlib.Path, expected_version: int) -> list[str]:
    cidrs: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        net = ipaddress.ip_network(line, strict=True)
        if net.version != expected_version:
            raise ValueError(f"{path}: expected IPv{expected_version}, got {line}")
        cidrs.append(str(net))
    if not cidrs:
        raise ValueError(f"{path}: empty IP list")
    return cidrs


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} <ips-v4> <ips-v6> <out-dir>")

    v4 = load_cidrs(pathlib.Path(sys.argv[1]), 4)
    v6 = load_cidrs(pathlib.Path(sys.argv[2]), 6)
    all_ips = v4 + v6

    out = pathlib.Path(sys.argv[3])
    (out / "caddy").mkdir(parents=True, exist_ok=True)
    (out / "nftables").mkdir(parents=True, exist_ok=True)

    (out / "ips-v4").write_text("\n".join(v4) + "\n", encoding="utf-8")
    (out / "ips-v6").write_text("\n".join(v6) + "\n", encoding="utf-8")
    (out / "ips").write_text("\n".join(all_ips) + "\n", encoding="utf-8")

    joined = " ".join(all_ips)
    (out / "caddy" / "remote-ip.caddy").write_text(f"remote_ip {joined}\n", encoding="utf-8")
    (out / "caddy" / "trusted-proxies.caddy").write_text(
        f"trusted_proxies static {joined}\n", encoding="utf-8"
    )

    (out / "nftables" / "sets.nft").write_text(
        f"define cloudflare_v4 = {{ {', '.join(v4)} }}\n"
        f"define cloudflare_v6 = {{ {', '.join(v6)} }}\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
