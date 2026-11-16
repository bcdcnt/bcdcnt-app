#!/usr/bin/env python3
"""Ảnh chụp màn hình điện thoại cho Google Play (tỉ lệ 1:2, retina 2x).
Dùng lại hạ tầng của docs/capture_screenshots.py, cửa sổ 420x840 → layout mobile.
    ~/.venvs/cadquery/bin/python store/capture_phone.py
"""
import subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "docs"))
import capture_screenshots as cs
from PIL import Image

cs.SHOT_SIZE = "420x840"
OUT = Path(__file__).resolve().parent / "assets/phone"
SHOTS = [
    ("01-home.png",    "/",                    {}, 7),
    ("02-song.png",    "/song/446",            {}, 7),
    ("03-player.png",  "/song/446",            {"BCDCNT_OPEN_FULLPLAYER": "1"}, 9),
    ("04-artist.png",  "/nghe-si/thanh-huyen", {}, 6),
    ("05-search.png",  "/search?q=Tình ca",    {}, 6),
    ("06-library.png", "/library",             {}, 6),
]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, route, env, settle in SHOTS:
        cs.kill_app(); cs.set_theme("light")
        cs.launch(route, env); time.sleep(settle)
        wid = cs.window_id()
        if wid is None:
            print("!! no window", name); continue
        dest = OUT / name
        subprocess.run(["screencapture", "-x", "-o", f"-l{wid}", str(dest)])
        im = Image.open(dest).convert("RGB")
        im = im.crop((0, 64, im.width, im.height))  # bỏ thanh tiêu đề macOS (32pt @2x)
        print("✓", dest, im.size)
        im.save(dest)
    cs.kill_app()

if __name__ == "__main__":
    main()
