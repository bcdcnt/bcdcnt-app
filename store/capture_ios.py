#!/usr/bin/env python3
"""Ảnh chụp màn hình cho App Store (iPhone 6.9" 1320x2868, iPad 13" 2064x2752).
Chụp cửa sổ app macOS (build --debug) ở đúng tỉ lệ thiết bị rồi phóng lên kích thước Apple yêu cầu.
    ~/.venvs/cadquery/bin/python store/capture_ios.py
"""
import subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "docs"))
import capture_screenshots as cs
from PIL import Image

ROOT = Path(__file__).resolve().parent / "assets"
# window logical size includes the 32pt macOS title bar (cropped afterwards)
DEVICES = {
    "iphone": ("440x988", (1320, 2868)),   # 880x1912 @2x → 1.5x
    "ipad":   ("716x987", (2064, 2752)),   # 1432x1910 @2x (màn hình chỉ cao tới ~955pt) → 1.44x
}
SHOTS = [
    ("01-home.png",    "/",                    {}, 7),
    ("02-song.png",    "/song/446",            {}, 7),
    ("03-player.png",  "/song/446",            {"BCDCNT_OPEN_FULLPLAYER": "1"}, 9),
    ("04-artist.png",  "/nghe-si/thanh-huyen", {}, 6),
    ("05-search.png",  "/search?q=Tình ca",    {}, 6),
    ("06-library.png", "/library",             {}, 6),
]

def main():
    only = sys.argv[1:] or list(DEVICES)
    for dev in only:
        size, target = DEVICES[dev]
        cs.SHOT_SIZE = size
        out = ROOT / dev
        out.mkdir(parents=True, exist_ok=True)
        for name, route, env, settle in SHOTS:
            cs.kill_app(); cs.set_theme("light")
            cs.launch(route, env); time.sleep(settle)
            wid = cs.window_id()
            if wid is None:
                print("!! no window", dev, name); continue
            dest = out / name
            subprocess.run(["screencapture", "-x", "-o", f"-l{wid}", str(dest)])
            im = Image.open(dest).convert("RGB")
            im = im.crop((0, 64, im.width, im.height))  # bỏ thanh tiêu đề macOS
            raw = im.size
            im = im.resize(target, Image.LANCZOS)
            im.save(dest)
            print("✓", dest, raw, "→", im.size)
    cs.kill_app()

if __name__ == "__main__":
    main()
