#!/usr/bin/env python3
"""記吧（JustAdd）網路搜尋服務：只聽 127.0.0.1，經 Cloudflare 隧道的 /v1/search 進來。

- 身分：用閘道（LiteLLM）的邀請金鑰，向本機閘道 /v1/models 驗證，金鑰無效就拒絕。
- Brave 金鑰只存在這台機器（.brave_key），不經手機。
- 次數：每把金鑰每天 PER_KEY 次、全部合計每天 GLOBAL 次（Brave 每月約 1000 次免費）。
- 不記錄查詢內容與網頁內容，只記每把金鑰（雜湊）當天用了幾次。
"""
import hashlib, html, json, os, re, threading, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BRAVE_KEY = open(os.path.join(HERE, ".brave_key")).read().strip()
USAGE = os.path.join(HERE, "search-usage.json")
PER_KEY, GLOBAL = int(os.environ.get("SEARCH_PER_KEY", 10)), int(os.environ.get("SEARCH_GLOBAL", 30))
lock = threading.Lock()

def key_ok(key):
    req = urllib.request.Request("http://127.0.0.1:4000/v1/models", headers={"Authorization": "Bearer " + key})
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status == 200
    except Exception: return False

def take_quota(key):
    day = time.strftime("%Y-%m-%d"); h = hashlib.sha256(key.encode()).hexdigest()[:16]
    with lock:
        try: u = json.load(open(USAGE))
        except Exception: u = {}
        if u.get("day") != day: u = {"day": day, "total": 0, "keys": {}}
        if u["total"] >= GLOBAL: return "今天的搜尋次數已達上限，明天再試"
        if u["keys"].get(h, 0) >= PER_KEY: return f"每天最多搜尋 {PER_KEY} 次，明天再試"
        u["total"] += 1; u["keys"][h] = u["keys"].get(h, 0) + 1
        json.dump(u, open(USAGE, "w"))
    return None

def brave(q):
    url = "https://api.search.brave.com/res/v1/web/search?" + urllib.parse.urlencode(
        {"q": q, "count": 6, "country": "tw", "search_lang": "zh-hant", "extra_snippets": "true"})
    req = urllib.request.Request(url, headers={"Accept": "application/json", "X-Subscription-Token": BRAVE_KEY})
    with urllib.request.urlopen(req, timeout=20) as r: d = json.load(r)
    return [{"title": i.get("title", ""), "url": i.get("url", ""),
             "description": " ".join([i.get("description", "")] + i.get("extra_snippets", [])[:3])}
            for i in (d.get("web") or {}).get("results", [])]

def page_text(url, limit=6000):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (JustAdd calendar assistant)",
                                                    "Accept-Language": "zh-TW,zh;q=0.9,en;q=0.8"})
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read(2_000_000); cs = r.headers.get_content_charset() or "utf-8"
        s = raw.decode(cs, "replace")
        s = re.sub(r"(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\1>", " ", s)
        s = re.sub(r"(?s)<[^>]+>", " ", s); s = html.unescape(s)
        s = re.sub(r"[ \t\r\f\v]+", " ", s); s = re.sub(r"\s*\n\s*", "\n", s).strip()
        return s[:limit]
    except Exception: return ""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass            # 不記錄任何請求內容
    def send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        if self.path != "/v1/search": return self.send(404, {"error": "not found"})
        auth = self.headers.get("Authorization", "")
        key = auth[7:].strip() if auth.startswith("Bearer ") else ""
        if not key or not key_ok(key): return self.send(401, {"error": "金鑰無效"})
        try:
            body = json.loads(self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 4000)) or b"{}")
            q = str(body.get("query", "")).strip()[:200]
        except Exception: return self.send(400, {"error": "格式錯誤"})
        if not q: return self.send(400, {"error": "沒有查詢內容"})
        err = take_quota(key)
        if err: return self.send(429, {"error": err})
        try: results = brave(q)
        except Exception: return self.send(502, {"error": "搜尋服務暫時無法使用"})
        # 有些網站會擋，前 5 個一起抓，保留前 3 個抓得到的
        with ThreadPoolExecutor(5) as ex:
            texts = list(ex.map(page_text, [r["url"] for r in results[:5]]))
        pages = [{"url": r["url"], "text": t} for r, t in zip(results, texts) if len(t) > 200][:3]
        self.send(200, {"results": results, "pages": pages})

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 4100), H).serve_forever()
