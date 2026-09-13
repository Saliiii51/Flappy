#!/usr/bin/env python3
"""Godot Web export sonrasi yayin yamalarini uygular (idempotent).

Yaptiklari:
  1. web/Flappy Bird.html dosyasina WS adresi + FlappyVoice.js ekler (yoksa).
  2. web/index.html dosyasini onunla birebir esitler.
Kullanim:  python tools/patch_export.py   (proje kokunden)
"""
import os
import sys

WS_URL = "wss://flappy-ws.onrender.com"
HOOK = (
    "\t\t<script>\n"
    "\t\t\t// Internet yayini: backend WS adresi.\n"
    f'\t\t\twindow.FLAPPY_WS_URL = "{WS_URL}";\n'
    "\t\t</script>\n"
)
VOICE_TAG = '\t\t<script src="FlappyVoice.js"></script>\n'
GAME_TAG = '\t\t<script src="Flappy Bird.js"></script>\n'


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    web = os.path.join(root, "web")
    export_html = os.path.join(web, "Flappy Bird.html")
    index_html = os.path.join(web, "index.html")
    voice_js = os.path.join(web, "FlappyVoice.js")

    if not os.path.exists(export_html):
        print("HATA: export bulunamadi:", export_html)
        return 1
    if not os.path.exists(voice_js):
        print("UYARI: FlappyVoice.js yok:", voice_js)

    with open(export_html, encoding="utf-8") as f:
        html = f.read()

    changed = False
    if "FLAPPY_WS_URL" not in html and GAME_TAG in html:
        html = html.replace(GAME_TAG, HOOK + GAME_TAG, 1)
        changed = True
    if "FlappyVoice.js" not in html and GAME_TAG in html:
        html = html.replace(GAME_TAG, VOICE_TAG + GAME_TAG, 1)
        changed = True

    with open(export_html, "w", encoding="utf-8", newline="") as f:
        f.write(html)
    with open(index_html, "w", encoding="utf-8", newline="") as f:
        f.write(html)

    a = open(export_html, "rb").read()
    b = open(index_html, "rb").read()
    print("HTML SYNC", "OK" if a == b else "BOZUK!")
    print("yama uygulandi" if changed else "zaten yamaliydi")
    return 0 if a == b else 2


if __name__ == "__main__":
    sys.exit(main())
