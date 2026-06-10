#!/usr/bin/env python3
"""Recapture the README illustration screenshots for the macOS app.

What it does, per shot:
  1. Kills any running instance.
  2. Presets the right-panel tab (SharedPreferences via `defaults`).
  3. Launches the *built* .app binary with automation env vars:
       BCDCNT_INITIAL_ROUTE   deep-link straight to the screen
       BCDCNT_SHOT_SIZE       pin window to 1280x820, centered (reproducible frame)
       BCDCNT_OPEN_FULLPLAYER open the full-screen player once a track plays
     (all are no-ops in normal use — see lib/main.dart)
  4. Waits for the screen to settle, finds the app window via Quartz,
     captures it shadow-free with `screencapture -x -o -l<id>`.
  5. Squares off the rounded-corner transparency (edge-extend per row) and
     flattens to RGB so there are no white corner artifacts.

Prereqs:
  - The app must be built first:  flutter build macos --debug
  - Run with the venv that has Quartz (pyobjc) + Pillow:
        ~/.venvs/cadquery/bin/python docs/capture_screenshots.py
  - Be logged in (favorites / settings / stats / my-uploads need a session).
    The screen-recording permission must be granted to the terminal/IDE.

Usage:
    ~/.venvs/cadquery/bin/python docs/capture_screenshots.py                  # all (dark)
    ~/.venvs/cadquery/bin/python docs/capture_screenshots.py --theme light    # all (light → light/)
    ~/.venvs/cadquery/bin/python docs/capture_screenshots.py --theme light 03 04
"""
import os
import subprocess
import sys
import time
from pathlib import Path

import Quartz
from PIL import Image

APP_DIR = Path(__file__).resolve().parent.parent          # bcdcnt-app/
APP = APP_DIR / "build/macos/Build/Products/Debug/Bài ca đi cùng năm tháng.app"
BIN = APP / "Contents/MacOS/bcdcnt"
OUT = APP_DIR / "docs/screenshots"
BUNDLE = "net.bcdcnt.app"
WINDOW_OWNER_MATCH = "năm tháng"      # kCGWindowOwnerName of the app window
# "max" maximizes the window to the screen's visible frame — the largest size
# this display supports (a true 1920x1080 can't fit a 1728x1080-logical panel).
# Capture is retina (2x); we downscale by half to logical points.
SHOT_SIZE = "max"

# Theme to capture. `--theme light` flips the app to the light palette and
# writes into docs/screenshots/light/; dark goes to docs/screenshots/.
THEME = "dark"
_THEME_PREF = {"dark": "classic", "light": "light"}  # -> flutter.app_theme_name


def out_dir():
    return OUT / "light" if THEME == "light" else OUT

# (filename, route, panel_tab, extra_env, settle_seconds[, logout])
#   panel_tab: 'comments' | 'queue' | 'activity'  -> right sidebar tab
#   logout (optional, default False): clear the auth prefs before launch so the
#     app boots logged out — used for the login/register dialog shots.
SHOTS = [
    ("01-home.png",           "/",                                 "comments", {}, 6),
    ("02-artists.png",        "/nghe-si",                          "comments", {}, 5),
    ("03-artist-detail.png",  "/nghe-si/thanh-huyen",              "comments", {}, 6),  # Thanh Huyền
    ("04-song-detail.png",    "/song/446",                         "queue",    {}, 7),  # Rặng trâm bầu (Thanh Huyền · Kiều Hưng)
    ("05-search.png",         "/search",                           "comments", {}, 5),
    ("06-activity.png",       "/cong-dong/hoat-dong-thanh-vien",   "comments", {}, 6),
    ("07-comments.png",       "/binh-luan",                        "comments", {}, 6),
    ("08-category.png",       "/the-loai/tan-nhac",                "comments", {}, 6),
    ("09-library.png",        "/library",                          "comments", {}, 6),
    ("10-player.png",         "/song/446",                         "queue",    {"BCDCNT_OPEN_FULLPLAYER": "1"}, 9),
    ("11-favorites.png",      "/yeu-thich",                        "comments", {}, 6),
    ("12-playlists.png",      "/playlist-cua-toi",                 "comments", {}, 6),
    ("13-my-uploads.png",     "/bai-gui-cua-toi",                  "comments", {}, 6),
    ("14-settings.png",       "/cai-dat",                          "comments", {}, 6),
    ("15-stats.png",          "/thong-ke",                         "comments", {}, 7),
    ("16-search-results.png", "/search?q=Tình ca",                 "comments", {}, 6),
    ("17-composers.png",      "/nhac-si",                          "comments", {}, 5),
    ("18-recent.png",         "/nghe-gan-day",                     "comments", {}, 6),
    ("19-user-detail.png",    "/user/1858",                        "comments", {}, 6),  # Lão Nông
    ("20-playlist-detail.png","/playlist/1572",                    "comments", {}, 6),  # Kỷ niệm ngày giải phóng tỉnh Thừa Thiên - Huế
    ("21-docs-images.png",    "/tu-lieu/hinh-anh",                 "comments", {}, 6),  # Tư liệu: Hình ảnh
    ("22-docs-audio.png",     "/tu-lieu/am-thanh",                 "comments", {}, 6),  # Tư liệu: Âm thanh
    ("23-docs-video.png",     "/tu-lieu/video",                    "comments", {}, 6),  # Tư liệu: Video
    ("24-docs-articles.png",  "/tu-lieu/bai-viet",                 "comments", {}, 6),  # Tư liệu: Bài viết
    ("25-login.png",          "/profile",      "comments", {"BCDCNT_OPEN_AUTH": "login"},    6, True),   # Đăng nhập (logged out)
    ("26-register.png",       "/profile",      "comments", {"BCDCNT_OPEN_AUTH": "register"}, 6, True),   # Đăng ký (logged out)
]


def app_windows():
    opts = (Quartz.kCGWindowListOptionOnScreenOnly |
            Quartz.kCGWindowListExcludeDesktopElements)
    out = []
    for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID):
        owner = w.get("kCGWindowOwnerName", "") or ""
        if WINDOW_OWNER_MATCH in owner and w.get("kCGWindowLayer", 0) == 0:
            out.append(w)
    return out


def kill_app():
    # -9 against the Mach-O name; pkill on the localized path alone proved
    # flaky (left stale instances whose window then got captured).
    for _ in range(5):
        subprocess.run(["pkill", "-9", "-f", "MacOS/bcdcnt"], capture_output=True)
        time.sleep(0.8)
        if not app_windows():
            return
    time.sleep(0.5)


def set_panel_tab(tab):
    # SharedPreferences on macOS = NSUserDefaults under the bundle id, keys
    # prefixed `flutter.`. Set while the app is dead so it isn't overwritten.
    subprocess.run(["defaults", "write", BUNDLE, "flutter.desktop_panel_tab", "-string", tab],
                   capture_output=True)


def set_theme(theme):
    subprocess.run(["defaults", "write", BUNDLE, "flutter.app_theme_name",
                    "-string", _THEME_PREF.get(theme, "classic")], capture_output=True)


def clear_auth():
    # Wipe the session so the app boots logged out (for login/register shots).
    # Re-login afterwards with docs/login_seed if you need the authed shots.
    for k in ("access_token", "refresh_token", "user"):
        subprocess.run(["defaults", "delete", BUNDLE, f"flutter.{k}"], capture_output=True)


def launch(route, extra_env):
    env = dict(os.environ)
    env["BCDCNT_INITIAL_ROUTE"] = route
    env["BCDCNT_SHOT_SIZE"] = SHOT_SIZE
    env.update(extra_env)
    subprocess.Popen([str(BIN)], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def window_id():
    # Largest layer-0 window owned by the app (the maximized content window;
    # ignores the small title-bar fragment windows macOS also reports).
    cands = app_windows()
    if not cands:
        return None
    cands.sort(key=lambda w: w["kCGWindowBounds"]["Width"] * w["kCGWindowBounds"]["Height"])
    return int(cands[-1]["kCGWindowNumber"])


def clean_corners(path):
    """Square off rounded-corner transparency: per row, edge-extend the
    outermost opaque pixel outward, then flatten to RGB."""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        x = 0
        while x < w and px[x, y][3] < 250:
            x += 1
        if 0 < x < w:
            edge = px[x, y]
            for xx in range(x):
                px[xx, y] = edge
        x = w - 1
        while x >= 0 and px[x, y][3] < 250:
            x -= 1
        if 0 <= x < w - 1:
            edge = px[x, y]
            for xx in range(x + 1, w):
                px[xx, y] = edge
    im = im.convert("RGB")
    # screencapture is retina (2x); downscale by half to logical points so the
    # PNG isn't a 3456px monster while staying crisp.
    im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    im.save(path)


def capture_one(filename, route, tab, extra_env, settle, logout=False):
    print(f"  → {filename}  [{route}]  tab={tab}{'  (logged out)' if logout else ''}")
    kill_app()
    set_panel_tab(tab)
    set_theme(THEME)
    if logout:
        clear_auth()
    launch(route, extra_env)
    time.sleep(settle)
    wid = window_id()
    if wid is None:
        print(f"    !! window not found — skipped {filename}")
        return False
    out_dir().mkdir(parents=True, exist_ok=True)
    dest = out_dir() / filename
    r = subprocess.run(["screencapture", "-x", "-o", f"-l{wid}", str(dest)],
                       capture_output=True)
    if r.returncode != 0 or not dest.exists():
        print(f"    !! screencapture failed: {r.stderr.decode().strip()}")
        return False
    clean_corners(dest)
    print(f"    ✓ {dest}  {Image.open(dest).size}")
    return True


def main():
    global THEME
    if not BIN.exists():
        sys.exit(f"App binary not found: {BIN}\nRun: flutter build macos --debug")
    args = sys.argv[1:]
    if "--theme" in args:
        i = args.index("--theme")
        THEME = args[i + 1]
        del args[i:i + 2]
    out_dir().mkdir(parents=True, exist_ok=True)
    wanted = args
    shots = [s for s in SHOTS if not wanted or s[0][:2] in wanted]
    print(f"Capturing {len(shots)} screenshot(s)  theme={THEME} → {out_dir()}")
    ok = 0
    did_logout = False
    for shot in shots:
        filename, route, tab, extra_env, settle = shot[:5]
        logout = shot[5] if len(shot) > 5 else False
        did_logout = did_logout or logout
        if capture_one(filename, route, tab, extra_env, settle, logout):
            ok += 1
    kill_app()
    print(f"\nDone: {ok}/{len(shots)} captured.")
    if did_logout:
        print("NOTE: auth prefs were cleared for login/register shots — the app "
              "is now logged out. Re-run the login seed if you need authed shots.")


if __name__ == "__main__":
    main()
