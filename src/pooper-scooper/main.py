#!/usr/bin/env python
import json
import base64
import argparse
import http.server
from urllib.parse import urlencode, urlparse, parse_qs
import httpx


class RequestHandler(http.server.BaseHTTPRequestHandler):
    def _set_response(self, content_type):
        self.send_response(200)
        self.send_header("Content-type", content_type)
        self.end_headers()

    def do_GET(self):
        parse = urlparse(self.path)
        if parse.path != "/cleaner":
            self.send_error(404)
        query = parse_qs(parse.query)

        target_url = query["url"]
        if len(target_url) > 1:
            self.send_error(404, "One shit a day")
        target_url = target_url[0]
        print(target_url)
        headers = {"User-Agent": "ProxySubscriber/0.6.0 Shadowrocket/2070"}
        try:
            resp = httpx.get(
                target_url, follow_redirects=True, headers=headers, timeout=3
            )
        except httpx.ConnectTimeout:
            with httpx.Client(
                follow_redirects=True, headers=headers, proxy="http://127.0.0.1:2080"
            ) as c:
                resp = c.get(target_url)
        self._set_response(resp.headers.get("Content-Type"))

        if resp.text.startswith("vmess://"):
            urls = resp.text
        else:
            content = resp.content
            # Correctly fix missing padding
            padding = len(content) % 4
            if padding:
                content += b'=' * (4 - padding)
            
            try:
                urls = base64.b64decode(content).decode()
            except Exception as e:
                print(f"Error decoding base64 content: {e}")
                self.send_error(500, "Failed to decode subscription content")
                return
        
        urls = urls.splitlines()

        for idx, url in enumerate(urls):
            # hotfix for base64ed ss url
            if url.startswith("ss://"):
                content = url.removeprefix("ss://")
                comment = content.split("#")[1]
                content = content.split("#")[0]
                urls[idx] = "ss://" + base64.b64decode(content).decode() + "#" + comment

            if url.startswith("trojan://"):
                content = url.removeprefix("trojan://")
                parse = urlparse(content)
                query = parse_qs(parse.query)
                if not "peer" in query:
                    continue
                
                query["sni"] =  query["peer"]
                query.pop("peer")
                new_url = parse._replace(query=urlencode(query, doseq=True)).geturl()
                urls[idx] = "trojan://" + new_url

            if not url.startswith("vmess://"):
                continue

            content = url.removeprefix("vmess://")
            content = base64.b64decode(content).decode()
            content = json.loads(content)

            # manually add support for tcp
            # by converting urls to xray scheme
            if content["net"] == "tcp":
                uuid = content["id"]
                domain = content["add"]
                port = content["port"]
                comment = content["ps"]
                urls[idx] = f"vmess://{uuid}@{domain}:{port}?encryption=auto#{comment}"
            else:
                if not content["host"]:
                    content["host"] = content["add"]
                content["scy"] = "auto"
                content = json.dumps(content).encode()
                urls[idx] = "vmess://" + base64.b64encode(content).decode()
            # print(urls)
        self.wfile.write("\n".join(urls).encode())


def main(listen, port):
    handler = RequestHandler
    server = http.server.HTTPServer((listen, port), handler)
    server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("address")
    parser.add_argument("port", type=int)
    args = parser.parse_args()
    main(args.address, args.port)
