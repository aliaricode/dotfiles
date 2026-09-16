"""
One-time interactive Spotify OAuth setup.

Usage:
    spotify-auth.py

Run this by hand once. It opens a browser, you log in and approve, and it
mints spotify_token.json. After that, spotify-backend.py refreshes silently
and never opens a browser -- same split as calendar-auth.py/calendar-backend.py.

Refresh tokens expire six months after authorization. When the backend
reports "reauth-required", run this script again.
"""

import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

CONFIG_DIR = os.path.expanduser("~/.config/quickshell/scripts")
CREDENTIALS_FILE = os.path.join(CONFIG_DIR, "spotify_credentials.json")
TOKEN_FILE = os.path.join(CONFIG_DIR, "spotify_token.json")

REDIRECT_URI = "http://127.0.0.1:8888/callback"
SCOPES = "user-read-playback-state user-modify-playback-state playlist-read-private"
TIMEOUT = 15

_result = {}


def _save_token(data):
    """Write atomically with 0600 so the backend never reads a half-written
    file and the secret isn't world-readable. Same as the backend's."""
    tmp = f"{TOKEN_FILE}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp, TOKEN_FILE)


def make_handler(expected_state):
    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path != "/callback":
                self.send_response(404)
                self.end_headers()
                return

            params = urllib.parse.parse_qs(parsed.query)
            state = params.get("state", [""])[0]

            if state != expected_state:
                body = b"State mismatch, ignoring this request."
            elif "error" in params:
                _result["error"] = params["error"][0]
                body = b"Authorization was denied. You can close this tab."
            elif "code" in params:
                _result["code"] = params["code"][0]
                body = b"Done, you can close this tab."
            else:
                body = b"No code received."

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<html><body>" + body + b"</body></html>")

        def log_message(self, *args):
            pass

    return CallbackHandler


def main():
    try:
        with open(CREDENTIALS_FILE) as f:
            creds = json.load(f)
        client_id = creds["client_id"]
        client_secret = creds["client_secret"]
    except (OSError, ValueError, KeyError) as exc:
        print(f"Couldn't read client_id/client_secret from {CREDENTIALS_FILE}: {exc}")
        return 1

    state = secrets.token_urlsafe(16)
    auth_url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": REDIRECT_URI,
            "scope": SCOPES,
            "state": state,
        }
    )

    try:
        server = HTTPServer(("127.0.0.1", 8888), make_handler(state))
    except OSError as exc:
        print(f"Couldn't listen on 127.0.0.1:8888 ({exc}). Is something else using it?")
        return 1

    print("Opening browser for Spotify login...")
    print("If it doesn't open, visit:\n" + auth_url)
    webbrowser.open(auth_url)

    try:
        while "code" not in _result and "error" not in _result:
            server.handle_request()
    except KeyboardInterrupt:
        print("\nCancelled.")
        return 1
    finally:
        server.server_close()

    if "error" in _result:
        print("Spotify returned an error:", _result["error"])
        return 1

    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=urllib.parse.urlencode(
            {
                "grant_type": "authorization_code",
                "code": _result["code"],
                "redirect_uri": REDIRECT_URI,
                "client_id": client_id,
                "client_secret": client_secret,
            }
        ).encode(),
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            token_data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"Token exchange failed: {e.code} {e.reason}")
        print(e.read().decode("utf-8", "replace"))
        return 1
    except urllib.error.URLError as e:
        print(f"Token exchange failed, network error: {e.reason}")
        return 1

    if "refresh_token" not in token_data:
        print("Spotify didn't return a refresh token; the backend can't refresh without one.")
        return 1

    token_data["obtained_at"] = time.time()
    token_data["client_id"] = client_id
    token_data["client_secret"] = client_secret

    os.makedirs(CONFIG_DIR, exist_ok=True)
    _save_token(token_data)

    try:
        os.chmod(CREDENTIALS_FILE, 0o600)
    except OSError:
        pass

    print("Saved token to", TOKEN_FILE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
