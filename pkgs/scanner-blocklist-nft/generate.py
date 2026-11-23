#!/usr/bin/env python3
"""Parse MISP warninglists for scanner CIDRs and render an nftables table body."""

import ipaddress
import json
import pathlib
import sys
import textwrap

type IPNetwork = ipaddress.IPv4Network | ipaddress.IPv6Network


def is_scanner_list(name: str) -> bool:
    return (
        name.endswith("-scanning")
        or name.endswith("-scanner")
        or name in ("shadowserver", "driftnet")
    )


def collect_networks(lists_dir: pathlib.Path) -> tuple[list[str], list[str]]:
    v4_nets: list[ipaddress.IPv4Network] = []
    v6_nets: list[ipaddress.IPv6Network] = []

    for entry in sorted(lists_dir.iterdir()):
        if not entry.is_dir() or not is_scanner_list(entry.name):
            continue
        list_file = entry / "list.json"
        if not list_file.is_file():
            continue

        data = json.loads(list_file.read_text(encoding="utf-8"))
        for item in data.get("list", []):
            raw = str(item).strip()
            try:
                net: IPNetwork = ipaddress.ip_network(raw, strict=False)
            except ValueError:
                continue

            if (
                net.is_private
                or net.is_loopback
                or net.is_link_local
                or net.is_multicast
                or net.is_unspecified
            ):
                continue

            if isinstance(net, ipaddress.IPv4Network) and net.prefixlen >= 8:
                v4_nets.append(net)
            elif isinstance(net, ipaddress.IPv6Network) and net.prefixlen >= 16:
                v6_nets.append(net)

    collapsed_v4 = [str(n) for n in ipaddress.collapse_addresses(v4_nets)]
    collapsed_v6 = [str(n) for n in ipaddress.collapse_addresses(v6_nets)]
    return collapsed_v4, collapsed_v6


def render_nft(v4_cidrs: list[str], v6_cidrs: list[str]) -> str:
    v4_elems = ",\n    ".join(v4_cidrs)
    v6_elems = ",\n    ".join(v6_cidrs)
    template = textwrap.dedent("""\
        set scanners-v4 {{
          type ipv4_addr
          flags interval
          auto-merge
          elements = {{
            {v4_elems}
          }}
        }}

        set scanners-v6 {{
          type ipv6_addr
          flags interval
          auto-merge
          elements = {{
            {v6_elems}
          }}
        }}

        chain input {{
          type filter hook input priority filter - 10; policy accept;
          ip saddr @scanners-v4 drop
          ip6 saddr @scanners-v6 drop
        }}
    """)
    return template.format(v4_elems=v4_elems, v6_elems=v6_elems)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} <misp-lists-dir> <out-file>")

    lists_dir = pathlib.Path(sys.argv[1])
    out_path = pathlib.Path(sys.argv[2])

    v4_cidrs, v6_cidrs = collect_networks(lists_dir)
    out_path.write_text(render_nft(v4_cidrs, v6_cidrs), encoding="utf-8")


if __name__ == "__main__":
    main()
