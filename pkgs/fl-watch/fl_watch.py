#!/usr/bin/env python3
import base64
import hashlib
import hmac
import html
import json
import os
import re
import struct
import sys
import tempfile
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://filelist.io"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"


def generate_totp(secret: str) -> str:
    cleaned = secret.replace(" ", "").upper()
    padding = "=" * ((8 - len(cleaned) % 8) % 8)
    key = base64.b32decode(cleaned + padding)
    counter = int(time.time()) // 30
    msg = struct.pack(">Q", counter)
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % 1000000
    return f"{code:06d}"


def load_cookies(sess: requests.Session, cookie_file: Path) -> None:
    if not cookie_file.exists():
        return
    try:
        data = json.loads(cookie_file.read_text(encoding="utf-8"))
        for item in data:
            sess.cookies.set(
                item["name"],
                item["value"],
                domain=item.get("domain", ""),
                path=item.get("path", "/"),
            )
    except Exception as exc:
        print(f"Warning: failed to load cookies: {exc}", file=sys.stderr)


def save_cookies(sess: requests.Session, cookie_file: Path) -> None:
    cookie_file.parent.mkdir(parents=True, exist_ok=True)
    items = [
        {
            "name": c.name,
            "value": c.value,
            "domain": c.domain,
            "path": c.path,
        }
        for c in sess.cookies
    ]
    atomic_write_json(cookie_file, items, mode=0o600)


def atomic_write_json(path: Path, data: object, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except Exception:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise


def is_login_page(resp: requests.Response) -> bool:
    if "login.php" in resp.url:
        return True
    soup = BeautifulSoup(resp.text, "html.parser")
    return soup.find("form", id="loginForm") is not None


def login(sess: requests.Session, cookie_file: Path) -> None:
    username = os.environ["FL_USERNAME"]
    password = os.environ["FL_PASS"]
    totp_secret = os.environ["FL_TOTP_SECRET"]

    r = sess.get(f"{BASE_URL}/login.php", timeout=20)
    r.raise_for_status()
    soup = BeautifulSoup(r.text, "html.parser")
    val_input = soup.find("input", {"name": "validator"})
    validator = val_input["value"] if val_input and val_input.has_attr("value") else ""

    payload = {
        "validator": validator,
        "username": username,
        "password": password,
        "code": generate_totp(totp_secret),
        "unlock": "1",
    }
    r_post = sess.post(f"{BASE_URL}/takelogin.php", data=payload, timeout=20)
    r_post.raise_for_status()

    if is_login_page(r_post):
        raise RuntimeError("FileList login failed (redirected back to login page)")

    save_cookies(sess, cookie_file)


def fetch_authed(sess: requests.Session, url: str, cookie_file: Path) -> BeautifulSoup:
    r = sess.get(url, timeout=20)
    r.raise_for_status()
    if is_login_page(r):
        print(f"Session expired while fetching {url}, logging in...", file=sys.stderr)
        sess.cookies.clear()
        login(sess, cookie_file)
        r = sess.get(url, timeout=20)
        r.raise_for_status()
        if is_login_page(r):
            raise RuntimeError(f"Still redirected to login page after login for {url}")
    return BeautifulSoup(r.text, "html.parser")


def clean_link(href: str) -> str:
    if href.startswith("redir.php?"):
        return href[len("redir.php?") :]
    if href.startswith("/"):
        return f"{BASE_URL}{href}"
    if not href.startswith("http"):
        return f"{BASE_URL}/{href}"
    return href


def parse_news(soup: BeautifulSoup) -> list[dict]:
    items = []
    for nb in soup.select("div.nblock"):
        title_el = nb.select_one(".nblock-header h4")
        title = title_el.get_text(" ", strip=True) if title_el else ""

        date_img = nb.select_one("img[alt='Date']")
        raw_date = (
            date_img.parent.get_text(" ", strip=True)
            if date_img and date_img.parent
            else ""
        )
        # Strip relative "(1 day ago)" suffix so timestamps remain stable
        date_ts = re.sub(r"\s*\([^)]*\)\s*$", "", raw_date).strip()

        links = []
        for a in nb.select(".nblock-innercontent a[href]"):
            href = clean_link(a["href"])
            if href not in links:
                links.append(href)

        colhead = nb.select_one(".nblock-innercontent .colhead")
        body_text = colhead.get_text(" ", strip=True) if colhead else ""
        if len(body_text) > 400:
            body_text = body_text[:397] + "..."

        item_id = f"{date_ts}|{title}"
        items.append(
            {
                "id": item_id,
                "title": title,
                "date": date_ts,
                "body": body_text,
                "links": links,
            }
        )
    return items


def parse_shop(soup: BeautifulSoup) -> dict[str, dict]:
    items = {}
    for form in soup.find_all("form", action="shop.php"):
        opt = form.find("input", {"name": "option"})
        if not opt or not opt.has_attr("value"):
            continue
        opt_id = opt["value"]

        card = form.select_one("div.colhead")
        if not card:
            continue

        title_div = card.find("div", recursive=False)
        name = title_div.get_text(" ", strip=True) if title_div else opt_id

        detail_lines = []
        price_text = ""
        for d in card.select("div"):
            t = d.get_text(" ", strip=True)
            if not t or t == name:
                continue
            if d.find("div"):
                continue
            detail_lines.append(t)
            if "You pay" in t:
                price_text = t

        items[opt_id] = {
            "name": name,
            "price": price_text,
            "details": detail_lines,
        }
    return items


def send_tg(token: str, chat_id: str, text: str) -> None:
    resp = requests.post(
        f"https://api.telegram.org/bot{token}/sendMessage",
        json={
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        },
        timeout=20,
    )
    resp.raise_for_status()


def format_news_msg(item: dict) -> str:
    lines = [
        f"📢 <b>FileList 主页公告: {html.escape(item['title'])}</b>",
        f"🕒 {html.escape(item['date'])}",
    ]
    if item["body"]:
        lines.append(f"\n{html.escape(item['body'])}")
    if item["links"]:
        lines.append("")
        for url in item["links"]:
            lines.append(f"🔗 {html.escape(url)}")
    return "\n".join(lines)


def format_shop_diff(old_shop: dict[str, dict], new_shop: dict[str, dict]) -> list[str]:
    changes = []
    for opt_id, new_item in new_shop.items():
        if opt_id not in old_shop:
            changes.append(
                f"🆕 <b>新增</b>: {html.escape(new_item['name'])} ({html.escape(new_item['price'])})"
            )
            continue
        old_item = old_shop[opt_id]
        if old_item.get("price") != new_item.get("price") or old_item.get(
            "details"
        ) != new_item.get("details"):
            old_desc = " / ".join(
                old_item.get("details") or [old_item.get("price", "")]
            )
            new_desc = " / ".join(
                new_item.get("details") or [new_item.get("price", "")]
            )
            changes.append(
                f"🔄 <b>{html.escape(new_item['name'])}</b>\n"
                f"  旧: {html.escape(old_desc)}\n"
                f"  新: {html.escape(new_desc)}"
            )
    for opt_id, old_item in old_shop.items():
        if opt_id not in new_shop:
            changes.append(f"❌ <b>下架</b>: {html.escape(old_item['name'])}")
    return changes


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    state_dir = Path(
        os.environ.get(
            "STATE_DIRECTORY", os.environ.get("STATE_DIR", "/var/lib/fl-watch")
        )
    )
    cookie_file = state_dir / "cookies.json"
    state_file = state_dir / "state.json"

    tg_token = os.environ.get("TG_BOT_TOKEN", "")
    tg_chat_id = os.environ.get("TG_CHAT_ID", "")
    if not dry_run and (not tg_token or not tg_chat_id):
        print("Error: TG_BOT_TOKEN and TG_CHAT_ID must be set", file=sys.stderr)
        return 1

    sess = requests.Session()
    sess.headers["User-Agent"] = USER_AGENT
    load_cookies(sess, cookie_file)

    try:
        soup_home = fetch_authed(sess, f"{BASE_URL}/index.php", cookie_file)
        soup_shop = fetch_authed(sess, f"{BASE_URL}/shop.php", cookie_file)
        news_items = parse_news(soup_home)
        shop_items = parse_shop(soup_shop)
        if not news_items or not shop_items:
            raise RuntimeError(
                f"Unexpected empty parse result (news={len(news_items)}, shop={len(shop_items)})"
            )
    except Exception as exc:
        err_msg = (
            f"⚠️ <b>FileList 监控抓取失败</b>\n<code>{html.escape(str(exc))}</code>"
        )
        print(err_msg, file=sys.stderr)
        if not dry_run and tg_token and tg_chat_id:
            try:
                send_tg(tg_token, tg_chat_id, err_msg)
            except Exception as tg_exc:
                safe_err = re.sub(r"bot[^/]+", "bot<REDACTED>", str(tg_exc))
                print(
                    f"Failed to send error alert to TG ({type(tg_exc).__name__}): {safe_err}",
                    file=sys.stderr,
                )
        return 1

    if dry_run:
        print(
            f"[dry-run] Parsed {len(news_items)} news items, {len(shop_items)} shop items"
        )
        for item in news_items:
            print("NEWS:", item["date"], "|", item["title"], "|", item["links"])
        for opt_id, item in shop_items.items():
            print("SHOP:", opt_id, "|", item["name"], "|", item["price"])
        return 0

    if not state_file.exists():
        state = {
            "seen_news": [item["id"] for item in news_items],
            "shop": shop_items,
        }
        shop_lines = [
            f"• {html.escape(item['name'])}: {html.escape(item['price'])}"
            for item in shop_items.values()
        ]
        startup_msg = (
            f"✅ <b>FileList 监控已启动</b>\n"
            f"已记录 {len(news_items)} 条首页公告、{len(shop_items)} 个商店商品。\n\n"
            f"<b>当前商店快照：</b>\n" + "\n".join(shop_lines)
        )
        send_tg(tg_token, tg_chat_id, startup_msg)
        send_tg(
            tg_token,
            tg_chat_id,
            "📌 <b>最新公告样例（用于核对解析）：</b>\n\n"
            + format_news_msg(news_items[0]),
        )
        atomic_write_json(state_file, state)
        return 0

    state = json.loads(state_file.read_text(encoding="utf-8"))
    seen_news = set(state.get("seen_news", []))
    old_shop = state.get("shop", {})

    new_news = [item for item in news_items if item["id"] not in seen_news]
    for item in reversed(new_news):
        send_tg(tg_token, tg_chat_id, format_news_msg(item))
        seen_news.add(item["id"])

    shop_changes = format_shop_diff(old_shop, shop_items)
    if shop_changes:
        msg = "🛒 <b>FileList 商店变动</b>\n\n" + "\n\n".join(shop_changes)
        send_tg(tg_token, tg_chat_id, msg)

    # Keep seen_news bounded to last 200 entries plus current page items
    ordered_seen = list(
        dict.fromkeys([item["id"] for item in news_items] + state.get("seen_news", []))
    )[:200]
    atomic_write_json(
        state_file,
        {
            "seen_news": ordered_seen,
            "shop": shop_items,
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
