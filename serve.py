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
