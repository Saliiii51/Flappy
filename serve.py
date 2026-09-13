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
    try:
        await p1["ws"].send(json.dumps({
            "type": "game_start",
            "room_code": code,
            "seed": seed,
            "is_host": True,
            "my_name": p1["name"],
            "opponent_name": p2["name"]
        }))
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

            elif msg_type in ("sync", "flap", "died", "score_update"):
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
