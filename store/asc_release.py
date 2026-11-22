"""App Store Connect: tạo version, ghi "Có gì mới", gắn build, nộp duyệt.

    ~/.venvs/cadquery/bin/python store/asc_release.py <IOS|MAC_OS> <version> <build> [status|submit]

Khoá API V866A924D3 (~/.appstoreconnect/private_keys). "Có gì mới" lấy từ
store/whatsnew-vi.txt. Phát hành tự động sau khi duyệt.
"""
import sys, time, pathlib, json
import jwt, requests

KEY_ID = "V866A924D3"
ISSUER = "69a6de95-6e8d-47e3-e053-5b8c7c11a4d1"
APP_ID = "6830481981"
API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = (pathlib.Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8").read_text()
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, key, algorithm="ES256", headers={"kid": KEY_ID})


S = requests.Session()
S.headers["Authorization"] = f"Bearer {token()}"


def call(method, path, body=None, **params):
    r = S.request(method, path if path.startswith("http") else API + path, json=body, params=params or None)
    if r.status_code >= 400:
        raise SystemExit(f"{method} {path} → {r.status_code}\n{r.text}")
    return r.json() if r.text else {}


def main():
    platform, ver, build = sys.argv[1], sys.argv[2], sys.argv[3]
    action = sys.argv[4] if len(sys.argv) > 4 else "status"
    whats_new = (pathlib.Path(__file__).parent / "whatsnew-vi.txt").read_text().strip()

    # Build
    b = call("GET", "/builds", **{"filter[app]": APP_ID, "filter[version]": build, "filter[preReleaseVersion.platform]": platform})["data"]
    if not b:
        print(f"build {build} ({platform}) chưa có trên ASC (đang xử lý?)")
        return
    b = b[0]
    st = b["attributes"]["processingState"]
    print("build", build, st, "encryption:", b["attributes"].get("usesNonExemptEncryption"))
    if action != "submit":
        return
    if st != "VALID":
        raise SystemExit("build chưa VALID, thử lại sau")
    if b["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})

    # Version
    v = call("GET", f"/apps/{APP_ID}/appStoreVersions", **{"filter[platform]": platform, "filter[versionString]": ver})["data"]
    if v:
        v = v[0]
    else:
        v = call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
            "attributes": {"platform": platform, "versionString": ver, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    vid = v["id"]
    print("version", ver, vid, v["attributes"]["appStoreState"])

    for loc in call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": whats_new}}})
        print("whatsNew", loc["attributes"]["locale"])

    call("PATCH", f"/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    print("gắn build", build)

    # Review submission (reuse an open one)
    subs = call("GET", "/reviewSubmissions", **{"filter[app]": APP_ID, "filter[platform]": platform, "filter[state]": "READY_FOR_REVIEW"})["data"]
    sub = subs[0] if subs else call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions",
        "attributes": {"platform": platform}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    items = call("GET", f"/reviewSubmissions/{sub['id']}/items")["data"]
    if not items:
        call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    r = call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("nộp duyệt:", r["data"]["attributes"]["state"])


main()
