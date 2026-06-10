#!/usr/bin/env python3
"""Seed a logged-in session into the app's prefs (macOS) without the UI.

Logs in against the live GraphQL API and writes access_token / refresh_token /
user into the `net.bcdcnt.app` NSUserDefaults domain (keys prefixed `flutter.`),
so the next app launch boots already authenticated. Used by the screenshot tool
to capture the authed screens, and to re-login after the login/register shots
(which clear the session).

Credentials are NOT stored here — pass them on the command line:

    python3 docs/login_seed.py <username> <password>
"""
import json
import subprocess
import sys

API = "https://api.bcdcnt.net/graphql"
ORIGIN = "https://bcdcnt.net"
BUNDLE = "net.bcdcnt.app"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"


def gql(query, variables=None, token=None):
    headers = [
        "-H", "Content-Type: application/json",
        "-H", f"Origin: {ORIGIN}",
        "-H", "X-Client-App: bcdcnt-flutter/macos",
        "-H", f"User-Agent: {UA}",
    ]
    if token:
        headers += ["-H", f"Authorization: Bearer {token}"]
    body = json.dumps({"query": query, "variables": variables or {}})
    out = subprocess.run(["curl", "-s", API, *headers, "--data", body],
                         capture_output=True, text=True).stdout
    return json.loads(out)


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: python3 docs/login_seed.py <username> <password>")
    identity, password = sys.argv[1], sys.argv[2]

    login_q = ("mutation($identity:String!,$password:String!)"
               "{ login(identity:$identity,password:$password)"
               "{ access_token refresh_token message code } }")
    res = (gql(login_q, {"identity": identity, "password": password})
           .get("data", {}) or {}).get("login") or {}
    tok, ref = res.get("access_token"), res.get("refresh_token")
    if not tok:
        sys.exit(f"login failed: {res.get('message') or res}")

    me_q = ("query{ me{ id username email avatar{url} background{url} unread "
            "permissions player_shuffle player_repeat show_comment_sidebar } }")
    me = (gql(me_q, None, tok).get("data", {}) or {}).get("me") or {}
    user = {
        "id": me.get("id"), "username": me.get("username"), "email": me.get("email"),
        "avatar": (me.get("avatar") or {}).get("url"),
        "background": (me.get("background") or {}).get("url"),
        "unread": me.get("unread") or 0,
        "permissions": [p for p in (me.get("permissions") or []) if isinstance(p, str)],
        "player_shuffle": me.get("player_shuffle"),
        "player_repeat": me.get("player_repeat"),
        "show_comment_sidebar": me.get("show_comment_sidebar") or False,
    }

    def dw(key, val):
        subprocess.run(["defaults", "write", BUNDLE, "flutter." + key, "-string", val],
                       check=True)

    dw("access_token", tok)
    dw("refresh_token", ref)
    dw("user", json.dumps(user, ensure_ascii=False))
    print(f"Seeded session for {user['username']} ({len(user['permissions'])} perms) into {BUNDLE}")


if __name__ == "__main__":
    main()
