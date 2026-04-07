#!/usr/bin/env python
import base64
import json
import logging
import time
import re
from datetime import datetime
from urllib.parse import urlparse, parse_qs, urlencode, quote_plus
import argparse
import asyncio
import ipaddress

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import HttpUrl

# Set up colored logging using Uvicorn's formatter
import uvicorn.logging

console_formatter = uvicorn.logging.DefaultFormatter("%(levelprefix)s %(message)s")
console_handler = logging.StreamHandler()
console_handler.setFormatter(console_formatter)
logging.basicConfig(level=logging.INFO, handlers=[console_handler])
logger = logging.getLogger(__name__)

# Suppress detailed logs from libraries
logging.getLogger("httpx").setLevel(logging.WARNING)

app = FastAPI()

HEADERS = {"User-Agent": "ProxySubscriber/0.6.0 Shadowrocket/2070"}
PROXY_URL = "http://127.0.0.1:2080"
DOH_URL = None  # Will be set from args
CACHE_TTL = 30  # Seconds, 0 to disable
SUBSCRIPTION_CACHE = {}  # {url: (timestamp, content)}


class SimpleTTLCache:
    def get(self, key):
        if key not in SUBSCRIPTION_CACHE:
            return None
        timestamp, content = SUBSCRIPTION_CACHE[key]
        if time.time() - timestamp > CACHE_TTL:
            del SUBSCRIPTION_CACHE[key]
            return None
        return content

    def set(self, key, content):
        SUBSCRIPTION_CACHE[key] = (time.time(), content)


cache = SimpleTTLCache()


class CustomSNITransport(httpx.AsyncHTTPTransport):
    """
    A transport that allows manually setting the SNI hostname,
    enabling connection to a specific IP while verifying the SSL certificate against the original hostname.
    """

    def __init__(self, sni, **kwargs):
        self.sni = sni
        super().__init__(**kwargs)

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        request.extensions["sni_hostname"] = self.sni
        return await super().handle_async_request(request)


async def resolve_doh(hostname: str, doh_url: str) -> str | None:
    """
    Resolves a hostname to an IP address using DNS-over-HTTPS.
    Returns the first A record found.
    """
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Using Google/Cloudflare style DoH JSON API
            resp = await client.get(
                doh_url,
                params={"name": hostname, "type": "A"},
                headers={"Accept": "application/dns-json"},
            )
            resp.raise_for_status()
            data = resp.json()

            if "Answer" in data:
                for answer in data["Answer"]:
                    if answer["type"] == 1:  # A record
                        return answer["data"]

            # If no A record, maybe CNAME? But we usually want IP.
            # Allow fallback if no A record found.
            logger.warning(f"No A record found for {hostname} via DoH")
            return None
    except Exception as e:
        logger.error(f"DoH resolution failed for {hostname}: {e}")
        return None


def robust_base64_decode(content: bytes) -> str:
    """Decodes base64 content with robust padding handling."""
    padding = len(content) % 4
    if padding:
        content += b"=" * (4 - padding)
    return base64.b64decode(content).decode("utf-8")


def process_ss_url(url: str) -> str:
    """Standardizes SS URLs."""
    content = url.removeprefix("ss://")
    if "#" in content:
        content, comment = content.split("#", 1)
        return "ss://" + robust_base64_decode(content.encode()) + "#" + comment
    return url


def process_trojan_url(url: str) -> str:
    """Fixes Trojan URLs by moving 'peer' to 'sni'."""
    content = url.removeprefix("trojan://")
    parse = urlparse(content)
    # parse_qs returns a dictionary where values are lists
    query = parse_qs(parse.query)

    if "peer" in query:
        # Move peer[0] to sni
        query["sni"] = query["peer"]
        query.pop("peer")

        # Re-encode query ensuring lists are handled correctly (doseq=True)
        # Note: parse_qs values are lists, so we use doseq=True to encode them back properly
        new_query = urlencode(query, doseq=True)
        new_url = parse._replace(query=new_query).geturl()
        return "trojan://" + new_url
    return url


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
    """Standardizes VMess URLs."""
    content = url.removeprefix("vmess://")

    # Detect Shadowrocket format: vmess://B64(method:uuid@host:port)?remark=...&alterId=...
    # The base64 part decodes to a plain string, NOT JSON.
    # qjebbs/sing-box supports this format but expects `remarks` (plural).
    # Many airports incorrectly write `remark` (singular), so rename it.
    b64_part, sep, query_part = content.partition("?")
    if sep:
        try:
            decoded = robust_base64_decode(b64_part.encode())
            json.loads(decoded)
            # It IS valid JSON — fall through to normal processing below
        except (ValueError, UnicodeDecodeError):
            # Not JSON: it's Shadowrocket format (method:uuid@host:port)
            # Just fix the remark → remarks typo and leave everything else alone
            from urllib.parse import parse_qs, urlencode

            qs = parse_qs(query_part, keep_blank_values=True)
            if "remark" in qs and "remarks" not in qs:
                logger.info("Shadowrocket vmess: renaming 'remark' → 'remarks'")
                qs["remarks"] = qs.pop("remark")
            fixed_query = urlencode(qs, doseq=True)
            return f"vmess://{b64_part}?{fixed_query}"

    try:
        content = robust_base64_decode(content.encode())
        data = json.loads(content)
    except Exception as e:
        logger.error(f"Failed to parse vmess content: {e}")
        return url

    if data.get("net") == "tcp":
        # Convert TCP vmess to Xray scheme
        uuid = data.get("id", "")
        domain = data.get("add", "")
        port = data.get("port", "")
        comment = data.get("ps", "")
        return f"vmess://{uuid}@{domain}:{port}?encryption=auto#{comment}"
    elif data.get("net") == "grpc":
        # This fork reads `host` as gRPC service_name, `sni` as TLS SNI.
        # Standard vmess JSON is the opposite: path=service_name, host=SNI.
        # Swap them so the fork gets what it needs.
        sni = data.get("host", data.get("add", ""))
        service_name = data.get("path", "")
        data["sni"] = sni
        data["host"] = service_name
        data["alpn"] = "h2"
        data["scy"] = "auto"

        updated_content = json.dumps(data).encode()
        return "vmess://" + base64.b64encode(updated_content).decode()
    else:
        # Standardize other vmess (WS, h2, etc.)
        if not data.get("host"):
            data["host"] = data.get("add", "")
        data["scy"] = "auto"

        updated_content = json.dumps(data).encode()
        return "vmess://" + base64.b64encode(updated_content).decode()


def inject_usage_stats(
    processed_urls: list[str],
    resp_headers: httpx.Headers,
    total_gb_param: int | None = None,
):
    """
    Injects a fake VMess node "STATUS=..." if traffic info is found
    in headers or node names.
    """
    # Check if status line already exists to avoid duplication and extra work
    if any("STATUS=" in u for u in processed_urls):
        return

    # Try to get info from headers first
    user_info = resp_headers.get("Subscription-Userinfo")
    info_data = {}
    if user_info:
        try:
            # Parse upload=11; download=22; total=33; expire=44
            pairs = user_info.split(";")
            for pair in pairs:
                if "=" in pair:
                    k, v = pair.strip().split("=")
                    info_data[k] = int(v)
        except Exception:
            pass

    used_gb = 0.0
    total_gb = 0.0
    expire_str = "Unknown"

    # Logics to fallback to node scraping if header is empty
    extracted_expire = None
    extracted_remain = None
    extracted_used = None

    # Helper regexes for node names
    # Common patterns: "剩余流量: 50.5G", "Expire: 2024-01-01", "到期: 2024"
    re_remain = re.compile(
        r"(?:剩余|Remai|Lef)(?:.*?)(\d+(?:\.\d+)?)\s*(G|M|T)", re.IGNORECASE
    )
    re_used = re.compile(
        r"(?:已用|Used)(?:.*?)(\d+(?:\.\d+)?)\s*(G|M|T)", re.IGNORECASE
    )
    re_expire = re.compile(
        r"(?:到期|过期|Exp)(?:.*?)(\d{4}[-./]\d{1,2}[-./]\d{1,2})", re.IGNORECASE
    )

    # Scan processed urls for info nodes
    # We don't remove them, just read them
    for line in processed_urls:
        name = ""
        try:
            if line.startswith("ss://"):
                if "#" in line:
                    name = line.split("#")[-1]
            elif line.startswith("vmess://"):
                # Check if it's a standard link (contains @ or # not at end, or just not base64)
                # Simple heuristic: JSON usually starts with ey
                clean_line = line.removeprefix("vmess://")
                if not clean_line.startswith("ey"):
                    # Assume standard link format: vmess://...#remark
                    if "#" in clean_line:
                        name = clean_line.split("#")[-1]
                else:
                    # Legacy Base64 JSON
                    try:
                        meta = json.loads(robust_base64_decode(clean_line.encode()))
                        name = meta.get("ps", "")
                    except Exception:
                        pass
            elif line.startswith("trojan://"):
                if "#" in line:
                    name = line.split("#")[-1]
        except:
            continue

        if not name:
            continue

        # Check for Remainder
        m_remain = re_remain.search(name)
        if m_remain:
            val = float(m_remain.group(1))
            unit = m_remain.group(2).upper()
            if unit == "M":
                val /= 1024
            elif unit == "T":
                val *= 1024
            extracted_remain = val

        # Check for Used
        m_used = re_used.search(name)
        if m_used:
            val = float(m_used.group(1))
            unit = m_used.group(2).upper()
            if unit == "M":
                val /= 1024
            elif unit == "T":
                val *= 1024
            extracted_used = val

        # Check for Date
        m_expire = re_expire.search(name)
        if m_expire:
            extracted_expire = m_expire.group(1)

    # Final Calculation
    if info_data:
        # Use Header if available (Most accurate)
        upload = info_data.get("upload", 0)
        download = info_data.get("download", 0)
        total_bytes = info_data.get("total", 0)
        expire_ts = info_data.get("expire", 0)

        used_gb = (upload + download) / 1073741824
        total_gb = total_bytes / 1073741824
        if expire_ts:
            expire_str = datetime.fromtimestamp(expire_ts).strftime("%Y-%m-%d")
    else:
        # Fallback to scraped data
        if total_gb_param:
            total_gb = float(total_gb_param)
            if extracted_remain is not None:
                used_gb = total_gb - extracted_remain
            elif extracted_used is not None:
                used_gb = extracted_used

            # If we only found "Remaining", and user provided Total, we derive Used

        if extracted_expire:
            expire_str = extracted_expire

    # Construct Status Line if we have at least Total or Expire info
    # STATUS=🚀↑:0GB,↓:12.3GB,TOT:50GB💡Expires:2026-04-06
    # Note: We don't distinguish Up/Down in scrape mode, so we put all in Down

    if total_gb > 0 or expire_str != "Unknown":
        # Construct
        status_line = f"STATUS=🚀↑:0GB,↓:{used_gb:.2f}GB,TOT:{total_gb:.2f}GB💡Expires:{expire_str}"
        # Use plain text as requested by user
        processed_urls.insert(0, status_line)


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

    resp = None
    last_exception = None

    # DoH Resolution logic
    parsed_url = urlparse(target_url)
    resolved_ip = None
    hostname = parsed_url.hostname

    if DOH_URL and hostname:
        # Simple check if host is IP
        try:
            ipaddress.ip_address(hostname)
        except ValueError:
            # Hostname is not an IP, try DoH
            # logger.info(f"Resolving {hostname} via DoH...")
            resolved_ip = await resolve_doh(hostname, DOH_URL)
            if resolved_ip:
                logger.info(f"Resolved {hostname} to {resolved_ip}")

    # Retry loop: 3 attempts total
    # Each attempt tries Direct first, then Proxy.
    for attempt in range(3):
        try:
            # Direct Access Attempt
            if resolved_ip and hostname:
                # Use CustomSNITransport to perform DoH-based direct access
                transport = CustomSNITransport(sni=hostname)

                # Reconstruct URL with IP
                # We need to preserve path, query, scheme, port, etc.
                # Just replace netloc with resolved_ip:port
                netloc = resolved_ip
                if parsed_url.port:
                    netloc += f":{parsed_url.port}"

                direct_url = parsed_url._replace(netloc=netloc).geturl()

                async with httpx.AsyncClient(
                    transport=transport,
                    headers={**HEADERS, "Host": hostname},
                    timeout=3.0,
                    follow_redirects=True,
                    verify=True,  # Explicitly verify SSL
                ) as client:
                    try:
                        resp = await client.get(direct_url)
                    except (
                        httpx.TimeoutException,
                        httpx.ConnectError,
                        httpx.ReadTimeout,
                        httpx.ConnectTimeout,
                    ) as e:
                        logger.warning(
                            f"Direct connection (DoH) failed (attempt {attempt+1}/3): {e}, trying proxy..."
                        )
                        # Fallback to local proxy below
                        raise e
            else:
                # Standard Direct Access
                async with httpx.AsyncClient(
                    headers=HEADERS, timeout=3.0, follow_redirects=True
                ) as client:
                    try:
                        resp = await client.get(target_url)
                    except (
                        httpx.TimeoutException,
                        httpx.ConnectError,
                        httpx.ReadTimeout,
                        httpx.ConnectTimeout,
                    ) as e:
                        # Fallback to local proxy below
                        raise e

        # Catch specific httpx exclusions to trigger proxy fallback
        except (
            httpx.TimeoutException,
            httpx.ConnectError,
            httpx.ReadTimeout,
            httpx.ConnectTimeout,
        ):
            # Proxy Access Attempt (Fallback)
            try:
                async with httpx.AsyncClient(
                    headers=HEADERS,
                    proxy=PROXY_URL,
                    timeout=10.0,
                    follow_redirects=True,
                ) as proxy_client:
                    resp = await proxy_client.get(target_url)
            except Exception as e:
                logger.warning(f"Proxy connection failed (attempt {attempt+1}/3): {e}")
                last_exception = e

        except Exception as e:
            logger.warning(f"Attempt {attempt+1}/3 failed completely: {e}")
            last_exception = e

        # Check if we got a valid response
        if resp is not None:
            break

        # Retry logic
        if attempt < 2:
            await asyncio.sleep(1)

    if resp is None:
        if last_exception:
            logger.error(f"All retries failed. Last error: {last_exception}")
            raise HTTPException(status_code=500, detail=str(last_exception))
        else:
            raise HTTPException(status_code=500, detail="Unknown failure")

    try:
        resp.raise_for_status()

        if resp.text.startswith("vmess://"):
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
                line = line.strip()
                if line.startswith("ss://"):
                    line = process_ss_url(line)
                elif line.startswith("trojan://"):
                    line = process_trojan_url(line)
                elif line.startswith("vmess://"):
                    line = process_vmess_url(line)
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
    import uvicorn
    import argparse

    parser = argparse.ArgumentParser()
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
