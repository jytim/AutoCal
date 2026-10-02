#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KnowTree — 知識樹學習規劃（原型 / MVP）

用途：
    輸入一個學習目標（例如「造一台業餘固態火箭」），這支腳本會：
      1. 先反問你最多 3 個問題，把範圍縮準（AI 自己當場生問題）。
      2. 請家裡的 LLM 產出一棵「知識依賴圖」(DAG)：每個節點是一門要學的知識，
         並標好前置知識、預估時數、程度。
      3. 對每個節點用 Brave Search 真的去網路上搜學習資源（連結來自搜尋引擎，
         不是 LLM 編的），再請 LLM 從真實結果裡挑出有用的、標上語言/類型/難度、
         排好先後順序。
      4. 把整棵樹存成一個 JSON 檔，並在終端機印出縮排大綱。

設計理念（詳見同資料夾的「概念筆記.md」）：
    - 「要學什麼」交給 LLM；「去哪學」的連結一律來自真實搜尋，LLM 只負責挑與排。
    - 這是刻意做成「草稿」：AI 給起點，你可以直接改那個 JSON 檔。
    - 只用 Python 內建函式庫，不需要 pip install 任何東西。

如何執行：
    # 先設定 Brave 搜尋金鑰（和 AutoCal 用的同一把；不設也能跑，只是跳過找資源）
    export BRAVE_API_KEY="你的金鑰"

    python3 knowtree.py                      # 會問你想學什麼
    python3 knowtree.py "造一台業餘固態火箭"   # 直接給目標
    python3 knowtree.py "學賽車空氣力學" --no-search   # 只產樹、先不找資源（快）

連線設定沿用 AutoCal：預設連 192.168.0.45，連不到自動退回 192.168.2.230。
（若你在別的網路，可用環境變數 LLM_BASE_URL / LLM_MODEL 覆寫。）
"""

import os
import sys
import json
import time
import urllib.request
import urllib.parse
import urllib.error

# ── 後端設定（沿用 AutoCal 的 AppConfig）────────────────────────────────

# LLM 後端清單：依序嘗試，連不到就換下一台（和 AutoCal 的自動備援一樣）。
LLM_ENDPOINTS = [
    {
        "base_url": os.environ.get("LLM_BASE_URL", "http://192.168.0.45:8990/v1"),
        "model": os.environ.get("LLM_MODEL", "nvidia-Qwen3.6-35B-A3B-NVFP4"),
    },
    {
        "base_url": "http://192.168.2.230:8990/v1",
        "model": "/home/wahaha/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf",
    },
]

# Brave 搜尋金鑰從環境變數讀，不寫進版本庫。
BRAVE_API_KEY = os.environ.get("BRAVE_API_KEY", "")


# ── 低階工具：呼叫 LLM、呼叫 Brave ──────────────────────────────────────

def _post_json(url, payload, headers, timeout):
    """送一個 JSON POST，回傳解析後的 dict。失敗會丟例外。"""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    for k, v in headers.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def call_llm(messages, max_tokens=2000, temperature=0):
    """
    呼叫 LLM（OpenAI 相容端點），回傳模型的文字內容。
    依序試每個後端，連不到就換下一台。
    """
    last_error = None
    for ep in LLM_ENDPOINTS:
        url = ep["base_url"].rstrip("/") + "/chat/completions"
        payload = {
            "model": ep["model"],
            "temperature": temperature,
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},  # 關掉思考模式，快一點
            "messages": messages,
        }
        try:
            result = _post_json(url, payload, headers={}, timeout=120)
            content = result["choices"][0]["message"]["content"]
            if content and content.strip():
                return content
            last_error = RuntimeError("模型回傳空內容")
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            # 連不到這台 → 試下一台
            last_error = e
            continue
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            # 有連到但回應格式怪 → 直接報錯，不要無謂重試
            raise RuntimeError(f"LLM 回應格式異常：{e}")
    raise RuntimeError(f"所有後端都連不到：{last_error}")


def brave_search(query, count=5):
    """用 Brave 搜尋，回傳 [{title, url, description}, ...]。沒金鑰就回空清單。"""
    if not BRAVE_API_KEY:
        return []
    params = urllib.parse.urlencode({
        "q": query,
        "count": count,
        "country": "tw",
        "search_lang": "zh-hant",
    })
    url = "https://api.search.brave.com/res/v1/web/search?" + params
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/json")
    req.add_header("X-Subscription-Token", BRAVE_API_KEY)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        results = (data.get("web") or {}).get("results") or []
        return [
            {
                "title": r.get("title", ""),
                "url": r.get("url", ""),
                "description": r.get("description", ""),
            }
            for r in results
        ]
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
        print(f"    ⚠️ 搜尋「{query}」失敗：{e}")
        return []


def extract_json(text):
    """從模型輸出撈出 JSON（容忍 ```json 包裹或前後多餘文字）。"""
    t = text.strip()
    if "```" in t:
        t = t.split("```", 1)[1]
        if t.lstrip().lower().startswith("json"):
            t = t.lstrip()[4:]
        if "```" in t:
            t = t.split("```", 1)[0]
    t = t.strip()
    # 抓第一個 [ 或 { 到對應的最後一個 ] 或 }
    starts = [i for i in (t.find("["), t.find("{")) if i != -1]
    if not starts:
        raise ValueError(f"找不到 JSON：{text[:200]}")
    start = min(starts)
    end = max(t.rfind("]"), t.rfind("}"))
    return json.loads(t[start:end + 1])


# ── 第 1 步：反問使用者，把範圍縮準 ──────────────────────────────────────

def ask_clarifying_questions(goal):
    """請 LLM 針對目標生 2~3 個釐清問題，拿去問使用者，回傳問答字串。"""
    print("\n🤔 讓我先問你幾個問題，把範圍縮準……\n")
    messages = [
        {"role": "system", "content":
            "你是學習規劃助理。使用者想學某個主題，但你要先把範圍縮準，才能產出剛好大小的學習樹。\n"
            "請針對他的目標，提出『最多 3 個』最能縮小範圍的問題。好問題通常涵蓋：\n"
            "1) 具體目標或想做出的產出（有沒有比賽/發表/要做出的成品）\n"
            "2) 現有程度（讓你知道樹要停在哪，不要往下挖到太基礎）\n"
            "3) 偏好（偏動手做還是先懂原理、偏中文還是能接受英文資源）\n"
            "只輸出一個 JSON 字串陣列，每個元素是一個問題。不要有任何解釋。"},
        {"role": "user", "content": f"我想學：{goal}"},
    ]
    try:
        questions = extract_json(call_llm(messages, max_tokens=500))
    except Exception as e:
        print(f"（生問題失敗，跳過提問：{e}）")
        return ""

    answers = []
    for i, q in enumerate(questions[:3], 1):
        print(f"  {i}. {q}")
        ans = input("     > ").strip()
        answers.append(f"問：{q}\n答：{ans or '（沒特別想法，請你幫我用合理預設）'}")
    return "\n".join(answers)


# ── 第 2 步：產生知識樹（DAG）─────────────────────────────────────────

def generate_tree(goal, qa):
    """請 LLM 產出知識依賴圖，回傳節點清單。"""
    print("\n🌲 正在規劃知識樹……（這步最花時間，請稍等）")
    messages = [
        {"role": "system", "content":
            "你是資深學習路徑規劃師。使用者給一個學習目標，你要產出一棵『知識依賴圖』。\n"
            "輸出一個 JSON 陣列，每個元素是一個知識節點，欄位如下：\n"
            '  - id：短英文代號（kebab-case，例如 "fluid-dynamics"），同一棵樹內唯一\n'
            "  - name：知識名稱（中文簡短）\n"
            "  - summary：一兩句話說這是什麼、為什麼要學\n"
            '  - prerequisites：前置知識的 id 陣列（必須是本清單裡出現過的 id；最底層的就留空 []）\n'
            '  - level：\"入門\" / \"中階\" / \"進階\"\n'
            "  - estimatedHours：預估學習時數（整數，粗估即可）\n"
            "  - searchQuery：建議拿去搜尋學習資源的關鍵字（繁體中文為主，必要時可中英混合）\n\n"
            "重要規則：\n"
            "  - 這是『有向無環圖』：前置關係不可成環；一個節點可以有多個前置。\n"
            "  - 根據使用者的現有程度，『停在他已經會的地方』，不要一路往下挖到太基礎的東西。\n"
            "  - 總共約 10~18 個節點，由基礎到進階大致排序。寧可精簡也不要發散。\n"
            "  - 只輸出 JSON 陣列本身，不要 markdown、不要解釋。"},
        {"role": "user", "content":
            f"學習目標：{goal}\n\n"
            + (f"補充資訊（我的回答）：\n{qa}\n" if qa else "")},
    ]
    nodes = extract_json(call_llm(messages, max_tokens=3000))
    print(f"   ✓ 產生了 {len(nodes)} 個知識節點")
    return nodes


# ── 第 3 步：為每個節點找並篩選學習資源 ─────────────────────────────────

def find_resources(node):
    """對單一節點搜尋，再請 LLM 從真實結果挑出有用的、標註並排序。"""
    query = node.get("searchQuery") or node.get("name", "")
    raw = brave_search(query, count=5)
    if not raw:
        return []

    # 把真實搜到的結果丟回 LLM，只做『挑選/標註/排序』，不准它自己生連結。
    listing = "\n".join(
        f'{i+1}. {r["title"]}\n   {r["url"]}\n   {r["description"]}'
        for i, r in enumerate(raw)
    )
    messages = [
        {"role": "system", "content":
            "你是學習資源策展人。以下是針對某個知識點的『真實網路搜尋結果』。\n"
            "請從中挑出最多 4 個對『初學者系統性學習』最有用的，並排出建議的學習先後順序。\n"
            "輸出 JSON 陣列，每個元素欄位：\n"
            '  - title：標題\n'
            '  - url：網址（只能用下面清單裡實際出現的網址，絕對不可以自己編造或改寫）\n'
            '  - type："影片" / "文章" / "書" / "課程" / "論文" / "其他"\n'
            '  - language："中文" / "英文" / "其他"\n'
            '  - difficulty："入門" / "中階" / "進階"\n'
            '  - why：一句話說為什麼推薦、在學習順序中的定位\n'
            "若清單裡沒有值得推薦的，回空陣列 []。只輸出 JSON。"},
        {"role": "user", "content": f"知識點：{node.get('name','')}\n\n搜尋結果：\n{listing}"},
    ]
    try:
        picked = extract_json(call_llm(messages, max_tokens=1200))
        # 保險：只保留 url 真的出現在搜尋結果裡的（擋掉模型偷改網址）
        real_urls = {r["url"] for r in raw}
        return [p for p in picked if p.get("url") in real_urls]
    except Exception as e:
        print(f"    ⚠️ 篩選資源失敗，先放原始搜尋結果：{e}")
        return [{"title": r["title"], "url": r["url"], "type": "其他",
                 "language": "", "difficulty": "", "why": r["description"]}
                for r in raw[:3]]


# ── 排序與輸出 ─────────────────────────────────────────────────────────

def topological_order(nodes):
    """照前置關係做拓撲排序，讓印出來的大綱從基礎到進階。有環就退回原順序。"""
    by_id = {n["id"]: n for n in nodes if "id" in n}
    visited, order, temp = set(), [], set()

    def visit(nid):
        if nid in visited or nid not in by_id:
            return
        if nid in temp:  # 偵測到環，略過避免無限遞迴
            return
        temp.add(nid)
        for pre in by_id[nid].get("prerequisites", []):
            visit(pre)
        temp.discard(nid)
        visited.add(nid)
        order.append(by_id[nid])

    for n in nodes:
        if "id" in n:
            visit(n["id"])
    return order if len(order) == len(by_id) else nodes


def print_outline(goal, nodes):
    """在終端機印出好讀的大綱。"""
    print("\n" + "=" * 60)
    print(f"🎯 目標：{goal}")
    print("=" * 60)
    id2name = {n.get("id"): n.get("name") for n in nodes}
    for i, n in enumerate(topological_order(nodes), 1):
        pres = n.get("prerequisites", [])
        pre_str = ("　前置：" + "、".join(id2name.get(p, p) for p in pres)) if pres else ""
        print(f"\n{i}. 【{n.get('name','?')}】 "
              f"（{n.get('level','?')}・約 {n.get('estimatedHours','?')} 小時）{pre_str}")
        if n.get("summary"):
            print(f"   {n['summary']}")
        for r in n.get("resources", []):
            tags = " ".join(t for t in [r.get("type"), r.get("language"),
                                        r.get("difficulty")] if t)
            print(f"     • [{tags}] {r.get('title','')}")
            print(f"       {r.get('url','')}")
            if r.get("why"):
                print(f"       → {r['why']}")
    print("\n" + "=" * 60)


# ── 主流程 ─────────────────────────────────────────────────────────────

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}

    goal = args[0] if args else input("你想學什麼？（例如：造一台業餘固態火箭）\n> ").strip()
    if not goal:
        print("沒有輸入目標，結束。")
        return

    if not BRAVE_API_KEY and "--no-search" not in flags:
        print("（提示：沒設定 BRAVE_API_KEY，這次只會產樹、不找資源。"
              "要找資源請 export BRAVE_API_KEY=... 再跑一次。）")

    # 1. 反問
    qa = ask_clarifying_questions(goal)

    # 2. 產樹
    nodes = generate_tree(goal, qa)

    # 3. 找資源（除非 --no-search 或沒金鑰）
    if "--no-search" not in flags and BRAVE_API_KEY:
        print("\n🔎 正在為每個節點搜尋學習資源……")
        for n in nodes:
            print(f"   搜尋：{n.get('name','')}")
            n["resources"] = find_resources(n)
            time.sleep(0.3)  # 對搜尋 API 客氣一點
    else:
        for n in nodes:
            n["resources"] = []

    # 4. 輸出
    print_outline(goal, nodes)

    safe = "".join(c if c.isalnum() or c in "-_ " else "_" for c in goal).strip()[:40]
    out_path = f"{safe or 'knowtree'}.knowtree.json"
    doc = {"goal": goal, "generatedAt": time.strftime("%Y-%m-%d %H:%M"),
           "clarifications": qa, "nodes": nodes}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
    print(f"\n💾 已存成：{out_path}")
    print("   不滿意哪個節點或資源？直接用文字編輯器打開這個檔案改就行（這就是「人可調」）。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n已取消。")
    except Exception as e:
        print(f"\n❌ 出錯了：{e}")
        sys.exit(1)
