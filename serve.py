import http.server
import socket
import socketserver
import os
import sys
import threading
import asyncio
import json
import random
import websockets

# Ensure UTF-8 output on Windows
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

HTTP_PORT = int(os.environ.get("HTTP_PORT", "8080"))
# Render/Railway gibi hostlar tek PORT verir -> onu WS için kullan.
# Yerelde: WS_PORT=8910, HTTP_PORT=8080 (eski davranış).
WS_PORT = int(os.environ.get("WS_PORT", os.environ.get("PORT", "8910")))
# Prod backend'de (Render) sadece WS çalışsın, HTTP'yi kapat: SERVE_HTTP=false
SERVE_HTTP = os.environ.get("SERVE_HTTP", "true").lower() in ("1", "true", "yes")
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")

# --- HTTP SERVER FOR WEB EXPORT ---
class GodotHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Critical headers for Godot 4 WebAssembly and SharedArrayBuffer
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        elif path.endswith(".pck"):
            return "application/octet-stream"
        elif path.endswith(".js"):
            return "application/javascript"
        return super().guess_type(path)

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/?"):
            self.path = "/index.html"
        # Render/UptimeRobot sağlık kontrolü için
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            try:
                self.wfile.write(b"ok")
            except Exception:
                pass
            return
        return super().do_GET()

    def log_message(self, format, *args):
        pass # Keep console output tidy

class ThreadedHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

# --- GLOBAL LEADERBOARD (kalıcı skor tablosu) ---
# ranks.json: { "all": {ad: {"best","games"}}, "weekly": {hafta_id: {ad: {...}}} }
RANKS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ranks.json")
ranks = {"all": {}, "weekly": {}}
last_submit_at = {}  # ws -> timestamp (spam koruması)

def current_week_id() -> str:
    import datetime as _dt
    y, w, _d = _dt.date.today().isocalendar()
    return f"{y}-W{w:02d}"

def previous_week_id() -> str:
    import datetime as _dt
    prev = _dt.date.today() - _dt.timedelta(days=7)
    y, w, _d = prev.isocalendar()
    return f"{y}-W{w:02d}"

def _board(scope: str, week: str = "") -> dict:
    if scope == "week":
        wid = week or current_week_id()
        return ranks.setdefault("weekly", {}).setdefault(wid, {})
    return ranks.setdefault("all", {})

def load_ranks():
    global ranks
    try:
        if os.path.exists(RANKS_PATH):
            with open(RANKS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                # Eski format ({ad: {...}}) -> "all" panosuna taşı
                if "all" in data or "weekly" in data:
                    ranks = {"all": data.get("all", {}), "weekly": data.get("weekly", {})}
                else:
                    ranks = {"all": data, "weekly": {}}
                total = len(ranks.get("all", {}))
                print(f"[Ranks] 🏆 {total} oyuncu yüklendi.")
    except Exception as e:
        print(f"[Ranks] yüklenemedi: {e}")

def save_ranks():
    try:
        with open(RANKS_PATH, "w", encoding="utf-8") as f:
            json.dump(ranks, f, ensure_ascii=False)
    except Exception as e:
        print(f"[Ranks] kaydedilemedi: {e}")

def get_rank_of(name: str, scope: str = "all") -> int:
    board = _board(scope)
    ordered = sorted(board.items(), key=lambda kv: kv[1].get("best", 0), reverse=True)
    for i, (n, _v) in enumerate(ordered, start=1):
        if n == name:
            return i
    return -1

def week_champion() -> dict:
    wid = previous_week_id()
    board = ranks.get("weekly", {}).get(wid, {})
    if not board:
        return {}
    name, entry = max(board.items(), key=lambda kv: kv[1].get("best", 0))
    return {"week": wid, "name": name, "best": int(entry.get("best", 0))}

# --- SUPABASE (kalıcı tablo; env yoksa dosya moduna düşer) ---
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
USE_DB = bool(SUPABASE_URL and SUPABASE_KEY)

def _db_req(method: str, path: str, params=None, body=None, timeout: int = 6):
    import urllib.request
    import urllib.parse
    url = SUPABASE_URL + "/rest/v1" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", SUPABASE_KEY)
    req.add_header("Authorization", "Bearer " + SUPABASE_KEY)
    req.add_header("Content-Type", "application/json")
    if method in ("POST", "PATCH"):
        req.add_header("Prefer", "resolution=merge-duplicates,return=representation")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else []

async def db_submit(name: str, score: int):
    def _do():
        cur = _db_req("GET", "/scores", {"name": "eq." + name, "select": "best,games"})
        best, games = score, 1
        if cur:
            best = max(int(cur[0].get("best", 0)), score)
            games = int(cur[0].get("games", 0)) + 1
        _db_req("POST", "/scores", {"on_conflict": "name"},
                {"name": name, "best": best, "games": games})
        wid = current_week_id()
        cur = _db_req("GET", "/weekly_scores",
                      {"week": "eq." + wid, "name": "eq." + name, "select": "best,games"})
        if cur:
            wbest = max(int(cur[0].get("best", 0)), score)
            wgames = int(cur[0].get("games", 0)) + 1
        else:
            wbest, wgames = score, 1
        _db_req("POST", "/weekly_scores", {"on_conflict": "week,name"},
                {"week": wid, "name": name, "best": wbest, "games": wgames})
        above = _db_req("GET", "/scores", {"best": "gt." + str(best), "select": "name"})
        return best, len(above) + 1
    return await asyncio.to_thread(_do)

async def db_top(scope: str, limit: int):
    def _do():
        if scope == "week":
            wid = current_week_id()
            rows = _db_req("GET", "/weekly_scores",
                           {"week": "eq." + wid, "select": "name,best,games",
                            "order": "best.desc", "limit": str(limit)})
            tot = _db_req("GET", "/weekly_scores",
                          {"week": "eq." + wid, "select": "name"})
            total = len(tot)
        else:
            rows = _db_req("GET", "/scores",
                           {"select": "name,best,games",
                            "order": "best.desc", "limit": str(limit)})
            tot = _db_req("GET", "/scores", {"select": "name"})
            total = len(tot)
        champ = {}
        try:
            crows = _db_req("GET", "/weekly_scores",
                            {"week": "eq." + previous_week_id(),
                             "select": "name,best", "order": "best.desc", "limit": "1"})
            if crows:
                champ = {"week": previous_week_id(), "name": crows[0]["name"],
                         "best": int(crows[0]["best"])}
        except Exception:
            pass
        entries = [{"name": r.get("name", "?"), "best": int(r.get("best", 0)),
                    "games": int(r.get("games", 0))} for r in rows]
        return entries, total, champ
    return await asyncio.to_thread(_do)

def local_bests(names) -> list:
    board = _board("all")
    out = []
    for n in names:
        e = board.get(n, {"best": 0, "games": 0})
        out.append({"name": n, "best": int(e.get("best", 0)),
                    "games": int(e.get("games", 0))})
    return out

async def db_bests(names) -> list:
    def _do():
        if not names:
            return []
        filt = "in.(" + ",".join(names) + ")"
        rows = _db_req("GET", "/scores",
                       {"name": filt, "select": "name,best,games"})
        by_name = {r.get("name"): r for r in rows}
        out = []
        for n in names:
            r = by_name.get(n, {})
            out.append({"name": n, "best": int(r.get("best", 0)),
                        "games": int(r.get("games", 0))})
        return out
    return await asyncio.to_thread(_do)

def local_submit(name: str, score: int):
    for scope in ("all", "week"):
        entry = _board(scope).get(name, {"best": 0, "games": 0})
        entry["games"] = int(entry.get("games", 0)) + 1
        if score > int(entry.get("best", 0)):
            entry["best"] = score
        _board(scope)[name] = entry
    save_ranks()
    return _board("all").get(name, {}).get("best", score), get_rank_of(name)

def local_top(scope: str, limit: int):
    board = _board(scope)
    ordered = sorted(board.items(), key=lambda kv: kv[1].get("best", 0), reverse=True)
    entries = [
        {"name": n, "best": int(v.get("best", 0)), "games": int(v.get("games", 0))}
        for n, v in ordered[:limit]
    ]
    return entries, len(board), week_champion()

# --- SOSYAL: sohbet/tepkiler (throttle) + online kaydı ---
last_chat_at = {}   # ws -> timestamp
last_taunt_at = {}  # ws -> timestamp
online_by_name = {}  # name -> ws (davet için)
name_by_ws = {}      # ws -> name

def _throttled(store, ws, seconds: float) -> bool:
    import time as _time
    now = _time.monotonic()
    if now - store.get(ws, 0.0) < seconds:
        return True
    store[ws] = now
    return False

def _register_online(ws, name: str):
    name = (name or "").strip()[:12]
    if not name:
        return
    old = name_by_ws.get(ws)
    if old and old != name and online_by_name.get(old) is ws:
        del online_by_name[old]
    # Aynı isimde başkası varsa son bağlanan kazanır (v1: isim tekilliği yok)
    name_by_ws[ws] = name
    online_by_name[name] = ws

def _unregister_online(ws):
    name = name_by_ws.pop(ws, None)
    if name and online_by_name.get(name) is ws:
        del online_by_name[name]
    last_chat_at.pop(ws, None)
    last_taunt_at.pop(ws, None)

def _room_partner(websocket):
    info = client_rooms.get(websocket)
    if not info or info["code"] not in rooms:
        return None, None
    room = rooms[info["code"]]
    partner = room["guest"] if info["role"] == "host" else room["host"]
    my_name = room["host_name"] if info["role"] == "host" else room["guest_name"]
    return partner, my_name

# --- ARKADAŞLAR (Supabase varsa kalıcı, yoksa bellek) ---
# NOT: DB çağrıları thread'de koşar, event loop asla bloklanmaz.
async def friends_op(op: str, owner: str, name: str = ""):
    def _do():
        if USE_DB:
            if op == "add":
                _db_req("POST", "/friends", {"on_conflict": "owner,name"},
                        {"owner": owner, "name": name})
            elif op == "remove":
                _db_req("DELETE", "/friends",
                        {"owner": "eq." + owner, "name": "eq." + name})
            rows = _db_req("GET", "/friends",
                           {"owner": "eq." + owner, "select": "name"})
            return sorted({r.get("name", "") for r in rows if r.get("name")})
        if op == "add":
            mem_friends.setdefault(owner, set()).add(name)
        elif op == "remove":
            mem_friends.get(owner, set()).discard(name)
        return sorted(mem_friends.get(owner, set()))
    return await asyncio.to_thread(_do)

mem_friends = {}

# --- QUICK MATCH (rastgele eşleşme kuyruğu) ---
# match_queue: [{"ws": ws, "name": str}]
match_queue = []

def _queue_remove(ws) -> bool:
    for i, entry in enumerate(match_queue):
        if entry["ws"] is ws:
            del match_queue[i]
            return True
    return False

def _queue_find(ws):
    for entry in match_queue:
        if entry["ws"] is ws:
            return entry
    return None

def _ws_alive(ws) -> bool:
    try:
        return bool(getattr(ws, "open", True))
    except Exception:
        return False

async def _begin_paired_match(p1, p2):
    while True:
        code = str(random.randint(1000, 9999))
        if code not in rooms:
            break
    seed = random.randint(100000, 999999)
    rooms[code] = {
        "host": p1["ws"],
        "guest": p2["ws"],
        "seed": seed,
        "host_name": p1["name"],
        "guest_name": p2["name"],
        "host_ready": False,
        "guest_ready": False
    }
    client_rooms[p1["ws"]] = {"code": code, "role": "host"}
    client_rooms[p2["ws"]] = {"code": code, "role": "guest"}
    print(f"[WebSocket] ⚡ Hızlı eşleşme: {code} ({p1['name']} vs {p2['name']})")
    ok1, ok2 = False, False
    try:
        await p1["ws"].send(json.dumps({
            "type": "game_start",
            "room_code": code,
            "seed": seed,
            "is_host": True,
            "my_name": p1["name"],
            "opponent_name": p2["name"]
        }))
        ok1 = True
    except Exception:
        pass
    try:
        await p2["ws"].send(json.dumps({
            "type": "game_start",
            "room_code": code,
            "seed": seed,
            "is_host": False,
            "my_name": p2["name"],
            "opponent_name": p1["name"]
        }))
        ok2 = True
    except Exception:
        pass
    if not (ok1 and ok2):
        # Biri ölü soketmiş: odayı dağıt, yaşayanı kuyruğa iade et
        print(f"[WebSocket] ⚠️ Eşleşme başarısız ({code}), yaşayan oyuncu kuyruğa iade edildi.")
        client_rooms.pop(p1["ws"], None)
        client_rooms.pop(p2["ws"], None)
        rooms.pop(code, None)
        for entry, ok in ((p1, ok1), (p2, ok2)):
            if ok and _ws_alive(entry["ws"]) and _queue_find(entry["ws"]) is None:
                match_queue.append(entry)
                try:
                    await entry["ws"].send(json.dumps({"type": "match_searching"}))
                except Exception:
                    pass

# --- VOICE SIGNALING (WebRTC P2P için, ses sunucudan geçmez) ---
# voice_rooms: oda kodu -> set(ws). En fazla 2 kişi.
voice_rooms = {}

def _voice_leave_all(ws):
    left = []
    for code in [c for c, members in voice_rooms.items() if ws in members]:
        members = voice_rooms[code]
        members.discard(ws)
        left.append(code)
        if not members:
            voice_rooms.pop(code, None)
    return left

async def _voice_relay(ws, code, payload):
    members = voice_rooms.get(code, set())
    for peer in list(members):
        if peer is not ws:
            try:
                await peer.send(json.dumps(payload))
            except Exception:
                pass

# --- WEBSOCKET ROOM RELAY SERVER ---
# rooms: code -> {"host": ws, "guest": ws, "seed": int}
rooms = {}
# client_rooms: ws -> {"code": code, "role": "host" | "guest"}
client_rooms = {}

async def handle_ws(websocket):
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
            except Exception:
                continue

            msg_type = data.get("type")

            if msg_type == "create_room":
                _queue_remove(websocket)
                _register_online(websocket, str(data.get("name", "Oyuncu 1")))
                # Generate unique 4-digit code (e.g. 4821)
                while True:
                    code = str(random.randint(1000, 9999))
                    if code not in rooms:
                        break
                seed = random.randint(100000, 999999)
                host_name = str(data.get("name", "Oyuncu 1")).strip() or "Oyuncu 1"
                rooms[code] = {
                    "host": websocket,
                    "guest": None,
                    "seed": seed,
                    "host_name": host_name,
                    "guest_name": "",
                    "host_ready": False,
                    "guest_ready": False
                }
                client_rooms[websocket] = {"code": code, "role": "host"}
                print(f"[WebSocket] 🏠 Yeni oda kuruldu: {code} (Kurucu: {host_name})")
                await websocket.send(json.dumps({
                    "type": "room_created",
                    "room_code": code
                }))

            elif msg_type == "join_room":
                _queue_remove(websocket)
                _register_online(websocket, str(data.get("name", "Oyuncu 2")))
                code = str(data.get("room_code", "")).strip()
                guest_name = str(data.get("name", "Oyuncu 2")).strip() or "Oyuncu 2"
                if code not in rooms:
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "Oda bulunamadı!"
                    }))
                elif rooms[code]["guest"] is not None:
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "Oda şu an dolu!"
                    }))
                else:
                    room = rooms[code]
                    room["guest"] = websocket
                    room["guest_name"] = guest_name
                    room["host_ready"] = False
                    room["guest_ready"] = False
                    client_rooms[websocket] = {"code": code, "role": "guest"}
                    seed = room["seed"]
                    print(f"[WebSocket] 👥 Odaya oyuncu katıldı: {code} ({guest_name})")

                    # Notify host
                    try:
                        await room["host"].send(json.dumps({
                            "type": "game_start",
                            "room_code": code,
                            "seed": seed,
                            "is_host": True,
                            "my_name": room["host_name"],
                            "opponent_name": guest_name
                        }))
                    except Exception:
                        pass

                    # Notify guest
                    await websocket.send(json.dumps({
                        "type": "game_start",
                        "room_code": code,
                        "seed": seed,
                        "is_host": False,
                        "my_name": guest_name,
                        "opponent_name": room["host_name"]
                    }))

            elif msg_type in ("rematch_ready", "rematch"):
                info = client_rooms.get(websocket)
                if info and info["code"] in rooms:
                    room = rooms[info["code"]]
                    role = info["role"]
                    partner = room["guest"] if role == "host" else room["host"]
                    
                    if role == "host":
                        room["host_ready"] = True
                    else:
                        room["guest_ready"] = True
                    
                    # Her iki oyuncu da hazırsa maçı başlat!
                    if room["host_ready"] and room["guest_ready"]:
                        room["host_ready"] = False
                        room["guest_ready"] = False
                        new_seed = random.randint(100000, 999999)
                        room["seed"] = new_seed
                        start_msg = json.dumps({
                            "type": "rematch_start",
                            "seed": new_seed
                        })
                        print(f"[WebSocket] 🔄 İki oyuncu da hazır! Yeni maç başlatılıyor: {info['code']} (Seed: {new_seed})")
                        if room["host"]:
                            try:
                                await room["host"].send(start_msg)
                            except Exception:
                                pass
                        if room["guest"]:
                            try:
                                await room["guest"].send(start_msg)
                            except Exception:
                                pass
                    else:
                        # Henüz sadece biri hazır; diğer oyuncuya 'rakibin hazır oldu' bilgisini ilet
                        if partner:
                            try:
                                await partner.send(json.dumps({
                                    "type": "opponent_ready"
                                }))
                            except Exception:
                                pass

            elif msg_type == "submit_score":
                # Global sıralama için tek oyunculu skor bildirimi
                import time as _time
                now = _time.monotonic()
                if now - last_submit_at.get(websocket, 0.0) < 5.0:
                    continue  # spam koruması: 5 sn'de bir
                last_submit_at[websocket] = now
                try:
                    name = str(data.get("name", "")).strip()[:12] or "Oyuncu"
                    score = int(data.get("score", 0))
                except Exception:
                    continue
                score = max(0, min(score, 9999))
                _register_online(websocket, name)
                try:
                    if USE_DB:
                        best, rank = await db_submit(name, score)
                    else:
                        best, rank = local_submit(name, score)
                except Exception as e:
                    print(f"[Ranks] DB hatası, dosya moduna düşüldü: {e}")
                    best, rank = local_submit(name, score)
                try:
                    await websocket.send(json.dumps({
                        "type": "rank_ok",
                        "best": best,
                        "rank": rank
                    }))
                except Exception:
                    pass

            elif msg_type == "get_top":
                try:
                    limit = int(data.get("limit", 10))
                except Exception:
                    limit = 10
                limit = max(5, min(limit, 50))
                scope = str(data.get("scope", "all")).strip().lower()
                if scope not in ("all", "week"):
                    scope = "all"
                try:
                    if USE_DB:
                        entries, total, champ = await db_top(scope, limit)
                    else:
                        entries, total, champ = local_top(scope, limit)
                except Exception as e:
                    print(f"[Ranks] DB hatası, dosya moduna düşüldü: {e}")
                    entries, total, champ = local_top(scope, limit)
                try:
                    await websocket.send(json.dumps({
                        "type": "top_ranks",
                        "scope": scope,
                        "week": current_week_id(),
                        "entries": entries,
                        "total": total,
                        "champ": champ
                    }))
                except Exception:
                    pass

            elif msg_type == "quick_match":
                # Zaten bir odadaysa eşleşmeye girme
                if websocket in client_rooms:
                    continue
                try:
                    qname = str(data.get("name", "Oyuncu")).strip()[:12] or "Oyuncu"
                except Exception:
                    qname = "Oyuncu"
                existing = _queue_find(websocket)
                if existing:
                    existing["name"] = qname
                else:
                    match_queue.append({"ws": websocket, "name": qname})
                _register_online(websocket, qname)
                # Ölü bağlantıları temizle
                for entry in match_queue[:]:
                    if not _ws_alive(entry["ws"]):
                        match_queue.remove(entry)
                # Kendinden farklı ilk bekleyeni bul
                partner = None
                for entry in match_queue:
                    if entry["ws"] is not websocket and _ws_alive(entry["ws"]):
                        partner = entry
                        break
                if partner:
                    match_queue.remove(partner)
                    _queue_remove(websocket)
                    await _begin_paired_match(partner, {"ws": websocket, "name": qname})
                else:
                    print(f"[WebSocket] 🔍 Eşleşme aranıyor: {qname} (kuyruk: {len(match_queue)})")
                    try:
                        await websocket.send(json.dumps({"type": "match_searching"}))
                    except Exception:
                        pass

            elif msg_type == "cancel_match":
                if _queue_remove(websocket):
                    print("[WebSocket] 🚫 Eşleşme araması iptal edildi.")
                try:
                    await websocket.send(json.dumps({"type": "match_cancelled"}))
                except Exception:
                    pass

            elif msg_type == "get_bests":
                raw_names = data.get("names", [])
                if not isinstance(raw_names, list):
                    raw_names = []
                names = []
                for n in raw_names[:5]:
                    clean = str(n).strip()[:12]
                    if clean and clean not in names:
                        names.append(clean)
                try:
                    if USE_DB:
                        entries = await db_bests(names)
                    else:
                        entries = local_bests(names)
                except Exception as e:
                    print(f"[Ranks] DB hatası, dosya moduna düşüldü: {e}")
                    entries = local_bests(names)
                try:
                    await websocket.send(json.dumps({
                        "type": "bests_info",
                        "entries": entries
                    }))
                except Exception:
                    pass

            elif msg_type == "chat":
                partner, my_name = _room_partner(websocket)
                if not partner:
                    continue
                if _throttled(last_chat_at, websocket, 1.2):
                    continue
                text = str(data.get("text", "")).strip()[:60]
                if not text:
                    continue
                try:
                    await partner.send(json.dumps({
                        "type": "chat", "text": text, "from": my_name
                    }))
                except Exception:
                    pass

            elif msg_type == "taunt":
                partner, my_name = _room_partner(websocket)
                if not partner:
                    continue
                if _throttled(last_taunt_at, websocket, 1.5):
                    continue
                icon = str(data.get("icon", "")).strip()[:8]
                if not icon:
                    continue
                try:
                    await partner.send(json.dumps({
                        "type": "taunt", "icon": icon, "from": my_name
                    }))
                except Exception:
                    pass

            elif msg_type in ("get_friends", "add_friend", "remove_friend"):
                me = name_by_ws.get(websocket, "")
                if not me:
                    me = str(data.get("name", "")).strip()[:12]
                    if me:
                        _register_online(websocket, me)
                if not me:
                    continue
                try:
                    op = {"get_friends": "get", "add_friend": "add",
                          "remove_friend": "remove"}[msg_type]
                    friend = ""
                    if msg_type in ("add_friend", "remove_friend"):
                        friend = str(data.get("friend", "")).strip()[:12]
                        if msg_type == "add_friend" and (not friend or friend == me):
                            op = "get"  # geçersiz ekleme -> sadece listele
                    friends = await friends_op(op, me, friend)
                except Exception as e:
                    print(f"[Friends] DB hatası: {e}")
                    friends = []
                try:
                    await websocket.send(json.dumps({
                        "type": "friends_list", "friends": friends
                    }))
                except Exception:
                    pass

            elif msg_type == "invite":
                info = client_rooms.get(websocket)
                if not info or info["code"] not in rooms:
                    try:
                        await websocket.send(json.dumps({
                            "type": "invite_failed", "to": "", "reason": "no_room"
                        }))
                    except Exception:
                        pass
                    continue
                code = info["code"]
                room = rooms[code]
                my_name = room["host_name"] if info["role"] == "host" else room["guest_name"]
                to = str(data.get("to", "")).strip()[:12]
                target = online_by_name.get(to) if to else None
                if not target or not _ws_alive(target):
                    try:
                        await websocket.send(json.dumps({
                            "type": "invite_failed", "to": to, "reason": "offline"
                        }))
                    except Exception:
                        pass
                    continue
                try:
                    await target.send(json.dumps({
                        "type": "invited", "from": my_name, "room_code": code
                    }))
                    await websocket.send(json.dumps({
                        "type": "invite_sent", "to": to
                    }))
                    print(f"[WebSocket] ✉️ Davet: {my_name} -> {to} (oda {code})")
                except Exception:
                    pass

            elif msg_type == "voice_join":
                code = str(data.get("room", "")).strip()[:8]
                if not code:
                    continue
                members = voice_rooms.setdefault(code, set())
                if websocket not in members:
                    if len(members) >= 2:
                        try:
                            await websocket.send(json.dumps({"type": "voice_full"}))
                        except Exception:
                            pass
                        continue
                    members.add(websocket)
                for peer in list(members):
                    if peer is not websocket:
                        try:
                            await peer.send(json.dumps({"type": "voice_hello"}))
                        except Exception:
                            pass
                try:
                    await websocket.send(json.dumps({
                        "type": "voice_roster",
                        "peers": max(0, len(members) - 1)
                    }))
                except Exception:
                    pass

            elif msg_type in ("voice_offer", "voice_answer", "voice_ice"):
                if len(message) > 16384:
                    continue
                code = str(data.get("room", "")).strip()[:8]
                if not code or websocket not in voice_rooms.get(code, set()):
                    continue
                await _voice_relay(websocket, code, data)

            elif msg_type == "voice_leave":
                code = str(data.get("room", "")).strip()[:8]
                if code and code in voice_rooms:
                    voice_rooms[code].discard(websocket)
                    if not voice_rooms[code]:
                        voice_rooms.pop(code, None)
                    else:
                        await _voice_relay(websocket, code, {"type": "voice_peer_left"})

            elif msg_type in ("sync", "flap", "died", "score_update", "badges"):
                # Fast relay to the opponent
                info = client_rooms.get(websocket)
                if info and info["code"] in rooms:
                    room = rooms[info["code"]]
                    partner = room["guest"] if info["role"] == "host" else room["host"]
                    if partner:
                        try:
                            await partner.send(message)
                        except Exception:
                            pass

    except (websockets.ConnectionClosed, Exception):
        pass
    finally:
        info = client_rooms.pop(websocket, None)
        _queue_remove(websocket)
        _unregister_online(websocket)
        for _code in _voice_leave_all(websocket):
            await _voice_relay(websocket, _code, {"type": "voice_peer_left"})
        last_submit_at.pop(websocket, None)
        if info:
            code = info["code"]
            if code in rooms:
                room = rooms[code]
                partner = room["guest"] if info["role"] == "host" else room["host"]
                if partner:
                    try:
                        await partner.send(json.dumps({"type": "opponent_left"}))
                    except Exception:
                        pass
                    client_rooms.pop(partner, None)
                del rooms[code]
                print(f"[WebSocket] 🚪 Oda kapandı: {code}")

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def start_http():
    with ThreadedHTTPServer(("0.0.0.0", HTTP_PORT), GodotHTTPRequestHandler) as httpd:
        httpd.serve_forever()

async def main():
    load_ranks()
    if USE_DB:
        print("[Ranks] 🗄️ Supabase modu (kalıcı tablo).")
    else:
        print("[Ranks] 📁 Dosya modu (SUPABASE_URL/KEY yok).")
    local_ip = get_local_ip()
    print("=" * 65)
    print(" 🎮 FLAPPY BIRD ODA KODLU MULTIPLAYER SUNUCUSU HAZIR!")
    print("=" * 65)
    if SERVE_HTTP:
        print(f" 🌐 Bilgisayarda oynamak için:      http://localhost:{HTTP_PORT}/")
        print(f" 📱 iPhone Safari'de oynamak için:  http://{local_ip}:{HTTP_PORT}/")
    else:
        print(f" 🌐 HTTP kapalı (SERVE_HTTP=false), sadece WebSocket çalışıyor.")
    print(f" ⚡ WebSocket Oda Sunucusu:         ws://{local_ip}:{WS_PORT}")
    print("=" * 65)
    print(" Kapatmak için Ctrl+C tuşlarına basabilirsiniz.\n")

    if SERVE_HTTP:
        http_thread = threading.Thread(target=start_http, daemon=True)
        http_thread.start()

    async with websockets.serve(handle_ws, "0.0.0.0", WS_PORT, ping_interval=10, ping_timeout=20):
        await asyncio.Future()

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nSunucu durduruldu.")
