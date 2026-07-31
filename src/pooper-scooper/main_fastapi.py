#!/usr/bin/env python
"""pooper-scooper: A proxy subscription cleaner and normalizer.

Fetches upstream proxy subscriptions, fixes malformed URLs produced by
broken airport generators, injects usage statistics, and serves the
cleaned result.  Supports Shadowsocks, Trojan, VMess, and VLESS.

Endpoints
---------
GET /cleaner?url=<encoded_url>
    Fetch, clean, and return a normalized subscription.
GET /helper?url=<raw_url>
    Generate the /cleaner URL for a given raw airport URL.
"""
import argparse
import asyncio
import base64
import ipaddress
import json
import logging
import re
import time
from datetime import datetime
from urllib.parse import urlparse, parse_qs, urlencode, quote_plus

import httpx
import uvicorn
import uvicorn.logging
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import HttpUrl

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_console_formatter = uvicorn.logging.DefaultFormatter("%(levelprefix)s %(message)s")
_console_handler = logging.StreamHandler()
_console_handler.setFormatter(_console_formatter)
logging.basicConfig(level=logging.INFO, handlers=[_console_handler])
logger = logging.getLogger(__name__)
logging.getLogger("httpx").setLevel(logging.WARNING)

# ---------------------------------------------------------------------------
# Application & configuration
# ---------------------------------------------------------------------------

app = FastAPI()

#: HTTP headers sent when fetching upstream subscriptions.
HEADERS: dict[str, str] = {"User-Agent": "Shadowrocket/3378"}
#: Local HTTP proxy used as fallback when direct access fails.
PROXY_URL: str = "http://127.0.0.1:2080"
#: DNS-over-HTTPS resolver URL; populated at startup via ``--doh_url``.
DOH_URL: str | None = None
#: Subscription cache TTL in seconds; 0 disables caching.
CACHE_TTL: int = 30

# Protocols whose subscriptions arrive as plain text (not base64-encoded).
# Any response whose first line starts with one of these prefixes is used
# verbatim; everything else is assumed to be a base64-encoded blob.
_PLAIN_PREFIXES: tuple[str, ...] = (
    "vmess://",
    "vless://",
    "trojan://",
    "ss://",
    "STATUS=",
)


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------


class SimpleTTLCache:
    """In-memory TTL cache for subscription responses.

    Each entry expires after *ttl* seconds and is evicted lazily on the
    next :py:meth:`get` for the same key.
    """

    def __init__(self, ttl: int) -> None:
        self._ttl = ttl
        self._store: dict[str, tuple[float, str]] = {}

    def get(self, key: str) -> str | None:
        """Return the cached value for *key*, or ``None`` if absent/expired."""
        entry = self._store.get(key)
        if entry is None:
            return None
        timestamp, content = entry
        if time.time() - timestamp > self._ttl:
            del self._store[key]
            return None
        return content

    def set(self, key: str, content: str) -> None:
        """Store *content* under *key* with the current timestamp."""
        self._store[key] = (time.time(), content)


cache = SimpleTTLCache(ttl=CACHE_TTL)


class CustomSNITransport(httpx.AsyncHTTPTransport):
    """Async transport that overrides the TLS SNI hostname.

    Allows connecting to a specific IP while verifying the server's SSL
    certificate against the original domain name — useful when using
    DoH-resolved IPs directly.
    """

    def __init__(self, sni: str, **kwargs) -> None:
        self.sni = sni
        super().__init__(**kwargs)

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        request.extensions["sni_hostname"] = self.sni
        return await super().handle_async_request(request)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


async def resolve_doh(hostname: str, doh_url: str) -> str | None:
    """Resolve *hostname* to an IPv4 address via DNS-over-HTTPS.

    Uses the Google/Cloudflare JSON DoH API.  Returns the first A record
    found, or ``None`` on failure or when no A record exists.
    """
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(
                doh_url,
                params={"name": hostname, "type": "A"},
                headers={"Accept": "application/dns-json"},
            )
            resp.raise_for_status()
            for answer in resp.json().get("Answer", []):
                if answer["type"] == 1:  # A record
                    return answer["data"]
        logger.warning(f"No A record found for {hostname} via DoH")
        return None
    except Exception as e:
        logger.error(f"DoH resolution failed for {hostname}: {e}")
        return None


def robust_base64_decode(content: bytes) -> str:
    """Decode *content* as base64, auto-correcting missing ``=`` padding."""
    padding = len(content) % 4
    if padding:
        content += b"=" * (4 - padding)
    return base64.b64decode(content).decode("utf-8")


async def _fetch_with_retry(
    target_url: str,
    resolved_ip: str | None,
    hostname: str | None,
) -> httpx.Response:
    """Fetch *target_url* directly, then retry through a local proxy.

    The direct path is attempted once, via the DoH-resolved IP and
    :class:`CustomSNITransport` when *resolved_ip* is available.  On a
    transport failure, the request is retried up to three times through
    :data:`PROXY_URL`, reusing the same proxy connection pool.

    The proxy gets a longer read timeout because subscription generators
    can take a while to produce their response.
    """
    direct_timeout = httpx.Timeout(
        connect=3.0,
        read=3.0,
        write=3.0,
        pool=3.0,
    )
    proxy_timeout = httpx.Timeout(
        connect=10.0,
        read=60.0,
        write=10.0,
        pool=10.0,
    )
    parsed_url = urlparse(target_url)

    try:
        if resolved_ip and hostname:
            # Connect to the DoH-resolved IP while preserving the original
            # hostname for HTTP routing and TLS certificate verification.
            netloc = resolved_ip
            if parsed_url.port:
                netloc += f":{parsed_url.port}"
            direct_url = parsed_url._replace(netloc=netloc).geturl()
            transport = CustomSNITransport(sni=hostname)
            direct_headers = {**HEADERS, "Host": hostname}
        else:
            direct_url = target_url
            transport = None
            direct_headers = HEADERS

        async with httpx.AsyncClient(
            transport=transport,
            headers=direct_headers,
            timeout=direct_timeout,
            follow_redirects=True,
            verify=True,
        ) as client:
            return await client.get(direct_url)
    except httpx.TransportError as e:
        logger.warning(
            "Direct fetch failed (%s): %s; trying proxy…",
            type(e).__name__,
            str(e) or "<no details>",
        )

    last_exception: Exception | None = None
    async with httpx.AsyncClient(
        headers=HEADERS,
        proxy=PROXY_URL,
        timeout=proxy_timeout,
        follow_redirects=True,
    ) as proxy_client:
        for attempt in range(3):
            try:
                return await proxy_client.get(target_url)
            except Exception as e:
                last_exception = e
                logger.warning(
                    "Proxy fallback failed (attempt %d/3, %s): %s",
                    attempt + 1,
                    type(e).__name__,
                    str(e) or "<no details>",
                )
                if attempt < 2:
                    await asyncio.sleep(1)

    assert last_exception is not None
    error_detail = f"{type(last_exception).__name__}: {last_exception}"
    logger.error("All proxy retries exhausted. Last error: %s", error_detail)
    raise HTTPException(status_code=500, detail=error_detail)


def process_ss_url(url: str) -> str:
    """Decode the base64-encoded section of a Shadowsocks URL.

    Legacy SS URLs encode ``method:password@host:port`` as a single base64
    blob directly after ``ss://``.  This decodes that blob so downstream
    clients can parse the individual fields.
    """
    content = url.removeprefix("ss://")
    if "#" in content:
        content, comment = content.split("#", 1)
        return "ss://" + robust_base64_decode(content.encode()) + "#" + comment
    return url


def process_trojan_url(url: str) -> str:
    """Fix Trojan URLs that use the non-standard ``peer`` param for SNI.

    Some generators write ``?peer=example.com`` instead of the standard
    ``?sni=example.com``.  This renames the parameter so Xray can find it.
    """
    content = url.removeprefix("trojan://")
    parsed = urlparse(content)
    qs = parse_qs(parsed.query)

    if "peer" in qs:
        qs["sni"] = qs.pop("peer")
        new_url = parsed._replace(query=urlencode(qs, doseq=True)).geturl()
        return "trojan://" + new_url
    return url


def process_vless_url(url: str) -> str:
    """Sanitizes VLESS URLs from broken airport generators.

    Fixes two known patterns:
    1. Base64-encoded userinfo: some generators encode the entire
       ``user@host:port`` block as base64 and stuff it in the URL authority,
       leaving no ``@host:port`` suffix for Xray to parse — causing
       ``invalid port: parsing "": invalid syntax``.
    2. ``headerType`` on TCP transport: ``headerType`` is only meaningful for
       HTTP transport; passing it with ``type=tcp`` (or no type) makes Xray
       reject the node with ``headerType is not supported in tcp``.
    """
    content = url.removeprefix("vless://")
    # Split off fragment (#remark) early so it doesn't confuse urlparse
    fragment = ""
    if "#" in content:
        content, fragment = content.split("#", 1)

    parsed = urlparse("vless://" + content)

    # --- Fix 1: base64-encoded userinfo with no host/port ---
    # Symptom: the netloc has no '@' because the whole auth section is a bare
    # base64 blob (urlparse treats it as hostname, so parsed.hostname is NOT
    # None — the only reliable signal is the absence of '@' in netloc).
    if "@" not in parsed.netloc:
        # The authority is the raw base64 string; query is already separated.
        b64_part = parsed.netloc  # everything between // and ?
        try:
            decoded = robust_base64_decode(b64_part.encode())
            # Expected format after decode: "flow:uuid@host:port"
            # or just "uuid@host:port"
            if "@" in decoded:
                userinfo, hostport = decoded.rsplit("@", 1)
                # userinfo may be "flow:uuid" or just "uuid"
                if ":" in userinfo:
                    _flow, uuid = userinfo.split(":", 1)
                else:
                    uuid = userinfo
                logger.debug(
                    f"vless: decoded base64 userinfo → uuid={uuid[:8]}… host={hostport}"
                )
                # Rebuild a clean URL and re-parse
                clean = f"vless://{uuid}@{hostport}"
                if parsed.query:
                    clean += "?" + parsed.query
                parsed = urlparse(clean)
            else:
                logger.warning(
                    "vless: base64 userinfo decoded but no '@' found; skipping fix"
                )
                return url + ("#" + fragment if fragment else "")
        except Exception as e:
            logger.warning(f"vless: base64 userinfo decode failed: {e}")
            return url + ("#" + fragment if fragment else "")

    # --- Fix 2, 3 & 4: query-string cleanup ---
    qs = parse_qs(parsed.query, keep_blank_values=True)
    changed = False

    # Fix 2: headerType not supported on TCP transport
    transport = qs.get("type", ["tcp"])[0].lower()
    if transport == "tcp" and "headerType" in qs:
        logger.debug("vless: removing unsupported 'headerType' from TCP transport")
        qs.pop("headerType")
        changed = True

    # Fix 3: 'remark' in query params → move to #fragment
    # Some airport generators put the node name in ?remark= instead of #fragment.
    if not fragment and "remark" in qs:
        fragment = qs.pop("remark")[0]
        logger.debug(f"vless: promoted 'remark' param to fragment: {fragment}")
        changed = True

    # Fix 4: Reality param normalization
    # If 'pbk' (public key) is present this is definitively a VLESS-Reality node.
    # Set canonical params and strip legacy/conflicting ones that Xray rejects.
    if "pbk" in qs:
        # Required Reality params
        if qs.get("security", [""])[0] != "reality":
            qs["security"] = ["reality"]
            changed = True
        if not qs.get("flow"):
            qs["flow"] = ["xtls-rprx-vision"]
            changed = True
        if not qs.get("type"):
            qs["type"] = ["tcp"]
            changed = True
        # Strip params that conflict with or are meaningless for Reality
        for junk in ("xtls", "tls", "alterId", "tfo"):
            if junk in qs:
                logger.debug(f"vless: stripping junk Reality param '{junk}'")
                qs.pop(junk)
                changed = True

    if changed:
        parsed = parsed._replace(query=urlencode(qs, doseq=True))

    result = parsed.geturl()
    if fragment:
        result += "#" + fragment
    return result


def normalize_status_line(line: str) -> str:
    """Normalize a STATUS= line to the format qjebbs/sing-box expects.

    English (pass-through):
        STATUS=🚀↑:0GB,↓:14.07GB,TOT:160GB💡Expires:2026-05-03
    Chinese airports (converted):
        STATUS=🚀 已用流量:0.84GB, 总流量:100GB 💡 到期时间:2026-05-03
    """
    if not line.startswith("STATUS="):
        return line
    # Already English format — contains arrow keys or TOT keyword
    if "↑" in line or "↓" in line or "TOT" in line:
        return line

    def _parse_size(s: str) -> float:
        """Return size in GB."""
        m = re.search(r"(\d+(?:\.\d+)?)\s*(GB|MB|TB)", s, re.IGNORECASE)
        if not m:
            return 0.0
        val, unit = float(m.group(1)), m.group(2).upper()
        return val / 1024 if unit == "MB" else val * 1024 if unit == "TB" else val

    used_gb = remain_gb = total_gb = 0.0
    expire_str = ""

    m = re.search(r"已用流量[:：]\s*(\S+)", line)
    if m:
        used_gb = _parse_size(m.group(1))

    m = re.search(r"剩余流量[:：]\s*(\S+)", line)
    if m:
        remain_gb = _parse_size(m.group(1))

    m = re.search(r"总流量[:：]\s*(\S+)", line)
    if m:
        total_gb = _parse_size(m.group(1))

    # Derive used from remaining if direct used is absent
    if used_gb == 0.0 and remain_gb > 0.0 and total_gb > 0.0:
        used_gb = total_gb - remain_gb

    m = re.search(
        r"(?:到期时间|到期|过期)[:：]\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})", line
    )
    if m:
        expire_str = re.sub(r"[./]", "-", m.group(1))

    logger.info("Normalized Chinese STATUS line → Shadowrocket format")
    return (
        f"STATUS=🚀↑:0GB,↓:{used_gb:.2f}GB,TOT:{total_gb:.2f}GB💡Expires:{expire_str}"
    )


def process_vmess_url(url: str) -> str:
    """Normalize a VMess URL to a form Xray/qjebbs-sing-box can consume.

    Handles three sub-formats:

    - **Shadowrocket** (``vmess://BASE64(method:uuid@host:port)?remark=…``):
      Renames the ``remark`` query param to ``remarks`` (the spelling
      expected by qjebbs/sing-box).
    - **TCP JSON**: Converts to the compact Xray URI
      ``vmess://uuid@host:port?encryption=auto``.
    - **gRPC JSON**: Swaps ``host``/``path`` fields to match the fork's
      convention (``host`` = service name, ``sni`` = TLS SNI).
    - **Other JSON** (WS, h2, …): Ensures ``host`` is set and forces
      ``scy=auto``.
    """
    content = url.removeprefix("vmess://")

    # Shadowrocket format: base64 decodes to a plain string, not JSON.
    # qjebbs/sing-box expects `remarks` (plural); many airports write `remark`.
    b64_part, sep, query_part = content.partition("?")
    if sep:
        try:
            decoded = robust_base64_decode(b64_part.encode())
            json.loads(decoded)
            # Valid JSON — fall through to standard JSON processing.
        except (ValueError, UnicodeDecodeError):
            # Not JSON → Shadowrocket format.  Fix remark → remarks typo.
            qs = parse_qs(query_part, keep_blank_values=True)
            if "remark" in qs and "remarks" not in qs:
                logger.info("Shadowrocket vmess: renaming 'remark' → 'remarks'")
                qs["remarks"] = qs.pop("remark")
            return f"vmess://{b64_part}?{urlencode(qs, doseq=True)}"

    try:
        data = json.loads(robust_base64_decode(content.encode()))
    except Exception as e:
        logger.error(f"Failed to parse vmess content: {e}")
        return url

    net = data.get("net")
    if net == "tcp":
        return (
            f"vmess://{data.get('id', '')}@{data.get('add', '')}:"
            f"{data.get('port', '')}?encryption=auto#{data.get('ps', '')}"
        )

    if net == "grpc":
        # Standard vmess JSON: path=service_name, host=SNI.
        # This fork expects the reverse: host=service_name, sni=SNI.
        data["sni"] = data.get("host", data.get("add", ""))
        data["host"] = data.get("path", "")
        data["alpn"] = "h2"
    else:
        # WS, h2, and other transports.
        if not data.get("host"):
            data["host"] = data.get("add", "")

    data["scy"] = "auto"
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()


# ---------------------------------------------------------------------------
# Usage stats injection
# ---------------------------------------------------------------------------


def _extract_node_name(line: str) -> str:
    """Extract the display name from a single proxy URL line.

    Returns an empty string when the name cannot be determined.
    """
    try:
        if line.startswith(("ss://", "trojan://", "vless://")):
            return line.split("#", 1)[-1] if "#" in line else ""
        if line.startswith("vmess://"):
            body = line.removeprefix("vmess://")
            if body.startswith("ey"):  # base64-JSON; name is in the "ps" field
                try:
                    return json.loads(robust_base64_decode(body.encode())).get("ps", "")
                except Exception:
                    return ""
            return body.split("#", 1)[-1] if "#" in body else ""
    except Exception:
        pass
    return ""


def inject_usage_stats(
    processed_urls: list[str],
    resp_headers: httpx.Headers,
    total_gb_param: int | None = None,
) -> None:
    """Prepend a ``STATUS=…`` traffic line to *processed_urls* if data is available.

    Data sources, in priority order:

    1. ``Subscription-Userinfo`` HTTP response header (most accurate).
    2. Traffic/expiry info scraped from individual node names, combined with
       the *total_gb_param* hint provided by the caller.

    No-op when a ``STATUS=`` line is already present.
    """
    if any("STATUS=" in u for u in processed_urls):
        return

    # --- Source 1: Subscription-Userinfo header ---
    # Format: "upload=<bytes>; download=<bytes>; total=<bytes>; expire=<unix_ts>"
    info_data: dict[str, int] = {}
    user_info = resp_headers.get("Subscription-Userinfo")
    if user_info:
        try:
            for pair in user_info.split(";"):
                if "=" in pair:
                    k, v = pair.strip().split("=", 1)
                    info_data[k.strip()] = int(v.strip())
        except Exception:
            pass

    used_gb = 0.0
    total_gb = 0.0
    expire_str = "Unknown"

    # --- Source 2: Scrape node names ---
    re_remain = re.compile(
        r"(?:剩余|Remai|Lef)(?:.*?)(\d+(?:\.\d+)?)\s*(G|M|T)", re.IGNORECASE
    )
    re_used_pat = re.compile(
        r"(?:已用|Used)(?:.*?)(\d+(?:\.\d+)?)\s*(G|M|T)", re.IGNORECASE
    )
    re_expire = re.compile(
        r"(?:到期|过期|Exp)(?:.*?)(\d{4}[-./]\d{1,2}[-./]\d{1,2})", re.IGNORECASE
    )

    extracted_remain: float | None = None
    extracted_used: float | None = None
    extracted_expire: str | None = None

    def _to_gb(val: float, unit: str) -> float:
        u = unit.upper()
        return val / 1024 if u == "M" else val * 1024 if u == "T" else val

    for line in processed_urls:
        name = _extract_node_name(line)
        if not name:
            continue
        m = re_remain.search(name)
        if m:
            extracted_remain = _to_gb(float(m.group(1)), m.group(2))
        m = re_used_pat.search(name)
        if m:
            extracted_used = _to_gb(float(m.group(1)), m.group(2))
        m = re_expire.search(name)
        if m:
            extracted_expire = m.group(1)

    # --- Aggregate ---
    if info_data:
        used_gb = (
            info_data.get("upload", 0) + info_data.get("download", 0)
        ) / 1073741824
        total_gb = info_data.get("total", 0) / 1073741824
        if ts := info_data.get("expire"):
            expire_str = datetime.fromtimestamp(ts).strftime("%Y-%m-%d")
    else:
        if total_gb_param:
            total_gb = float(total_gb_param)
            if extracted_remain is not None:
                used_gb = total_gb - extracted_remain
            elif extracted_used is not None:
                used_gb = extracted_used
        if extracted_expire:
            expire_str = extracted_expire

    if total_gb > 0 or expire_str != "Unknown":
        status = f"STATUS=🚀↑:0GB,↓:{used_gb:.2f}GB,TOT:{total_gb:.2f}GB💡Expires:{expire_str}"
        processed_urls.insert(0, status)


@app.get("/cleaner", response_class=PlainTextResponse)
async def cleaner(
    url: list[HttpUrl] = Query(...),
    no_cache: bool = False,
    total: int = Query(None, description="Total traffic in GB"),
):
    if len(url) > 1:
        raise HTTPException(status_code=404, detail="One shit a day")

    target_url = str(url[0])

    # Cache key includes total to ensure stats are injected correctly based on params
    cache_key = f"{target_url}|{total}"

    # Check cache
    if CACHE_TTL > 0 and not no_cache:
        cached = cache.get(cache_key)
        if cached:
            logger.info(f"Serving from cache: {target_url} (total={total})")
            return cached

    logger.info(f"Fetching subscription from: {target_url}")

    # --- DoH pre-resolution ---
    parsed_url = urlparse(target_url)
    hostname = parsed_url.hostname
    resolved_ip: str | None = None
    if DOH_URL and hostname:
        try:
            ipaddress.ip_address(hostname)  # raises if not already an IP
        except ValueError:
            resolved_ip = await resolve_doh(hostname, DOH_URL)
            if resolved_ip:
                logger.info(f"Resolved {hostname} → {resolved_ip}")

    resp = await _fetch_with_retry(target_url, resolved_ip, hostname)

    try:
        resp.raise_for_status()

        if resp.text.startswith(_PLAIN_PREFIXES):
            text_content = resp.text
        else:
            text_content = robust_base64_decode(resp.content)

        lines = text_content.splitlines()
        processed_urls = []

        for line in lines:
            line = line.strip()
            if not line:
                continue

            try:
                if line.startswith("ss://"):
                    line = process_ss_url(line)
                elif line.startswith("trojan://"):
                    line = process_trojan_url(line)
                elif line.startswith("vmess://"):
                    line = process_vmess_url(line)
                elif line.startswith("vless://"):
                    line = process_vless_url(line)
                elif line.startswith("STATUS="):
                    line = normalize_status_line(line)

                processed_urls.append(line)
            except Exception as e:
                logger.error(f"Error processing URL line '{line[:20]}...': {e}")
                # Keep original if processing fails
                processed_urls.append(line)

        # Inject usage stats
        inject_usage_stats(processed_urls, resp.headers, total)

        result_content = "\n".join(processed_urls)

        # Save to cache
        if CACHE_TTL > 0:
            cache.set(cache_key, result_content)

        return result_content

    except httpx.HTTPStatusError as e:
        logger.error(f"HTTP error occurred: {e}")
        raise HTTPException(
            status_code=e.response.status_code, detail="Failed to fetch subscription"
        )
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/helper", response_class=PlainTextResponse)
async def helper(
    request: Request,
    url: str = Query(..., description="The raw upstream subscription URL"),
    no_cache: bool = False,
    total: int | None = None,
):
    """
    Lazy Helper: Generates the full subscription URL for you.
    Input your raw airport URL, get back the cleaner URL.

    WARNING: If your upstream subscription URL contains parameters named 'no_cache' or 'total',
    they will be consumed by this helper and NOT passed to the upstream URL.
    In that case, please manually URL-encode your link instead of using this helper.
    """
    # Construct the base URL of this server (e.g., http://1.2.3.4:8000)
    base_url = str(request.base_url).rstrip("/")

    # Reconstruct the full target URL by grabbing parameters
    # Ignoring url, no_cache, total, no matter wether they append to url
    extra_params = []
    for key, value in request.query_params.multi_items():
        if key in ["url", "no_cache", "total"]:
            continue
        extra_params.append((key, value))

    full_target_url = url
    if extra_params:
        # Heuristic: if 'url' param already has query string, append with &, else ?
        separator = "&" if "?" in full_target_url else "?"
        encoded_extras = urlencode(extra_params)
        full_target_url += separator + encoded_extras

    # Manually encode the target URL

    encoded_target = quote_plus(full_target_url)
    final_link = f"{base_url}/cleaner?url={encoded_target}"

    if no_cache:
        final_link += "&no_cache=true"
    if total:
        final_link += f"&total={total}"
    return final_link + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="pooper-scooper subscription cleaner")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--ttl",
        type=int,
        default=CACHE_TTL,
        help=f"Cache TTL in seconds (default {CACHE_TTL})",
    )
    parser.add_argument(
        "--doh_url", default=None, help="DNS-over-HTTPS URL for resolution"
    )
    args = parser.parse_args()

    CACHE_TTL = args.ttl
    DOH_URL = args.doh_url
    logger.info(f"Cache TTL set to {CACHE_TTL} seconds")
    if DOH_URL:
        logger.info(f"DoH Enabled: {DOH_URL}")

    uvicorn.run(app, host=args.host, port=args.port)
