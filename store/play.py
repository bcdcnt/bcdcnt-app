#!/usr/bin/env python3
"""Google Play Developer API helper for net.bcdcnt.music.

Key: service account play-publisher@single-inquiry-514908-c8 (JSON key at
~/.config/bcdcnt/play-service-account.json, or $PLAY_SA_JSON). Needs
google-auth + requests (~/.venvs/cadquery/bin/python has both).

  play.py status                         # tracks + releases
  play.py upload app.aab [--track alpha] [--notes "..."] [--draft]
  play.py promote alpha production [--fraction 0.2] [--notes "..."]
  play.py rollout production 0.5|1        # change staged rollout fraction
  play.py listing pull                    # Play → store/listing/vi/*.txt
  play.py listing push [--images]         # store/listing + store/assets → Play
  play.py testers alpha [group@googlegroups.com ...]   # show / set Google Groups

Every write goes through an "edit" that is committed at the end; Play then
sends the change for review like the Console's "Send for review".
"""
import argparse
import os
import pathlib
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PKG = "net.bcdcnt.music"
LANG = "vi"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}"
STORE = pathlib.Path(__file__).resolve().parent
LISTING_DIR = STORE / "listing" / LANG
LISTING_FIELDS = {"title": "title.txt", "shortDescription": "short_description.txt",
                  "fullDescription": "full_description.txt"}
IMAGES = {  # imageType → files (replaced wholesale on push --images)
    "icon": [STORE / "assets" / "icon-512.png"],
    "featureGraphic": [STORE / "assets" / "feature-1024x500.png"],
    "phoneScreenshots": sorted((STORE / "assets" / "phone").glob("*.png")),
}


def session():
    key = os.environ.get("PLAY_SA_JSON") or os.path.expanduser("~/.config/bcdcnt/play-service-account.json")
    cr = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return AuthorizedSession(cr)


class Edit:
    def __init__(self, s, commit=True):
        self.s, self.commit_on_exit = s, commit

    def __enter__(self):
        self.id = self.call("POST", "/edits", root=True)["id"]
        return self

    def __exit__(self, exc_type, *_):
        if exc_type or not self.commit_on_exit:
            self.s.delete(f"{BASE}/edits/{self.id}")
            return
        r = self.call("POST", ":commit")
        print("committed edit", r["id"])

    def call(self, method, path, root=False, **kw):
        url = f"{BASE}{path}" if root else f"{BASE}/edits/{self.id}{path}"
        r = self.s.request(method, url, **kw)
        if not r.ok:
            sys.exit(f"{method} {path} → {r.status_code}\n{r.text}")
        return r.json() if r.content else {}


def notes(text):
    return [{"language": LANG, "text": text}] if text else []


def cmd_status(a):
    with Edit(session(), commit=False) as e:
        for t in e.call("GET", "/tracks").get("tracks", []):
            rel = t.get("releases") or []
            if not rel:
                print(f"{t['track']:<12} —")
            for r in rel:
                frac = f" {r['userFraction']:.0%}" if "userFraction" in r else ""
                print(f"{t['track']:<12} {r.get('name', '')}  codes={r.get('versionCodes')}  {r['status']}{frac}")


def cmd_upload(a):
    with Edit(session()) as e:
        with open(a.aab, "rb") as f:
            r = e.s.post(f"{UPLOAD}/edits/{e.id}/bundles", data=f,
                         params={"uploadType": "media"},
                         headers={"Content-Type": "application/octet-stream"}, timeout=600)
        if not r.ok:
            sys.exit(f"upload → {r.status_code}\n{r.text}")
        code = r.json()["versionCode"]
        print("uploaded versionCode", code)
        e.call("PUT", f"/tracks/{a.track}", json={"track": a.track, "releases": [{
            "versionCodes": [str(code)],
            "status": "draft" if a.draft else "completed",
            "releaseNotes": notes(a.notes),
        }]})
        print(f"→ {a.track} ({'draft' if a.draft else 'completed'})")


def cmd_promote(a):
    with Edit(session()) as e:
        src = e.call("GET", f"/tracks/{a.src}")
        rel = next((r for r in src.get("releases", []) if r["status"] == "completed"), None)
        if not rel:
            sys.exit(f"no completed release on {a.src}")
        new = {"name": rel.get("name"), "versionCodes": rel["versionCodes"],
               "releaseNotes": notes(a.notes) or rel.get("releaseNotes", [])}
        if a.fraction and a.fraction < 1:
            new.update(status="inProgress", userFraction=a.fraction)
        else:
            new["status"] = "completed"
        e.call("PUT", f"/tracks/{a.dst}", json={"track": a.dst, "releases": [new]})
        print(f"{a.src} {rel.get('name')} → {a.dst} {new['status']}")


def cmd_rollout(a):
    with Edit(session()) as e:
        t = e.call("GET", f"/tracks/{a.track}")
        rel = next((r for r in t.get("releases", []) if r["status"] in ("inProgress", "halted")), None)
        if not rel:
            sys.exit(f"no staged rollout on {a.track}")
        if a.fraction >= 1:
            rel.pop("userFraction", None)
            rel["status"] = "completed"
        else:
            rel.update(status="inProgress", userFraction=a.fraction)
        e.call("PUT", f"/tracks/{a.track}", json={"track": a.track, "releases": [rel]})
        print(a.track, rel["status"], rel.get("userFraction", 1))


def cmd_listing(a):
    if a.action == "pull":
        with Edit(session(), commit=False) as e:
            l = e.call("GET", f"/listings/{LANG}")
        LISTING_DIR.mkdir(parents=True, exist_ok=True)
        for field, fn in LISTING_FIELDS.items():
            (LISTING_DIR / fn).write_text(l.get(field, "").rstrip() + "\n")
        print("wrote", LISTING_DIR)
        return
    body = {"language": LANG}
    for field, fn in LISTING_FIELDS.items():
        body[field] = (LISTING_DIR / fn).read_text().strip()
    with Edit(session()) as e:
        e.call("PUT", f"/listings/{LANG}", json=body)
        print("listing text updated")
        if a.images:
            for kind, files in IMAGES.items():
                e.call("DELETE", f"/listings/{LANG}/{kind}")
                for p in files:
                    with open(p, "rb") as f:
                        r = e.s.post(f"{UPLOAD}/edits/{e.id}/listings/{LANG}/{kind}", data=f,
                                     params={"uploadType": "media"}, headers={"Content-Type": "image/png"})
                    if not r.ok:
                        sys.exit(f"{kind} {p.name} → {r.status_code}\n{r.text}")
                print(f"{kind}: {len(files)} image(s)")


def cmd_testers(a):
    with Edit(session(), commit=bool(a.groups)) as e:
        if a.groups:
            e.call("PUT", f"/testers/{a.track}", json={"googleGroups": a.groups})
        print(e.call("GET", f"/testers/{a.track}"))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("status").set_defaults(fn=cmd_status)
    u = sp.add_parser("upload"); u.set_defaults(fn=cmd_upload)
    u.add_argument("aab"); u.add_argument("--track", default="alpha")
    u.add_argument("--notes"); u.add_argument("--draft", action="store_true")
    pr = sp.add_parser("promote"); pr.set_defaults(fn=cmd_promote)
    pr.add_argument("src"); pr.add_argument("dst")
    pr.add_argument("--fraction", type=float); pr.add_argument("--notes")
    ro = sp.add_parser("rollout"); ro.set_defaults(fn=cmd_rollout)
    ro.add_argument("track"); ro.add_argument("fraction", type=float)
    li = sp.add_parser("listing"); li.set_defaults(fn=cmd_listing)
    li.add_argument("action", choices=["pull", "push"]); li.add_argument("--images", action="store_true")
    te = sp.add_parser("testers"); te.set_defaults(fn=cmd_testers)
    te.add_argument("track"); te.add_argument("groups", nargs="*")
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
