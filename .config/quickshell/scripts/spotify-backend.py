"""
Headless Spotify backend for the Quickshell bar.

Usage:
    spotify-backend.py search "<query>"
    spotify-backend.py playlists
    spotify-backend.py playlist <playlist_id>
    spotify-backend.py devices
    spotify-backend.py activate <device_id>
    spotify-backend.py queue <track_uri> [device_id]
    spotify-backend.py play <track_uri> [device_id]
    spotify-backend.py play_context <context_uri> [device_id]
    spotify-backend.py play_mix <context_uri> <track_count> [device_id]
    spotify-backend.py shuffle <true|false> [device_id]
    spotify-backend.py queue_state

device_id is a hint: the backend re-resolves the device on every playback
command (preferring "quickshell-player") and returns the one it used as
"deviceId", so a restarted player is picked up without restarting the bar.

Every command prints one JSON object. Errors use "ok": false and an "error"
string, one of:
    no-auth, reauth-required        -> run spotify-auth.py again
    dns-failure, network: <reason>  -> connectivity problem
    no-device                       -> no controllable Spotify Connect device
    playlist-not-browsable          -> followed playlist; play it, can't list it
    premium-required, rate-limited, quota-exceeded
    bad-args, no-command, unknown-command
    <HTTP status + message>         -> anything else from the API

Never runs an interactive flow. Run spotify-auth.py once by hand first.
Refresh tokens expire six months after the original authorization, at which
point this reports "reauth-required".
"""

import json
import os
import random
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_DIR = os.path.expanduser("~/.config/quickshell/scripts")
TOKEN_FILE = os.path.join(CONFIG_DIR, "spotify_token.json")

API_BASE = "https://api.spotify.com/v1"
TOKEN_URL = "https://accounts.spotify.com/api/token"

OWN_DEVICE_NAME = "quickshell-player"

TIMEOUT = 8
SEARCH_LIMIT = 10  # dev-mode maximum since Feb 2026
PAGE_LIMIT = 50  # playlist endpoints still allow 50 per page
MAX_ITEMS = 200
MAX_RETRY_WAIT = 5  # seconds; longer Retry-After values are reported instead


# ── ERRORS ────────────────────────────────────────────────────


class BackendError(Exception):
    """An error whose message is already a stable code for the frontend."""


class AuthError(BackendError):
    pass


class ApiError(RuntimeError):
    def __init__(self, code, reason, body):
        self.code = code
        self.body = body
        try:
            self.api_reason = (json.loads(body).get("error") or {}).get("reason", "")
        except (ValueError, AttributeError):
            self.api_reason = ""
        super().__init__(f"{code} {reason}: {body}")


# ── TOKEN ─────────────────────────────────────────────────────


def _save_token(data):
    """Write atomically with 0600 so concurrent processes never read a
    half-written file and the secret isn't world-readable."""
    tmp = f"{TOKEN_FILE}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp, TOKEN_FILE)


def load_token():
    """Return a valid access token, refreshing if needed. Never prompts.

    Raises AuthError when the user must re-run spotify-auth.py. Network
    errors propagate so main() can report them as such.
    """
    try:
        with open(TOKEN_FILE) as f:
            data = json.load(f)
        refresh_token = data["refresh_token"]
        client_id = data["client_id"]
        client_secret = data["client_secret"]
    except (OSError, ValueError, KeyError):
        raise AuthError("no-auth")

    if data.get("obtained_at", 0) + data.get("expires_in", 0) - 60 > time.time():
        return data["access_token"]

    req = urllib.request.Request(
        TOKEN_URL,
        data=urllib.parse.urlencode(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": client_id,
                "client_secret": client_secret,
            }
        ).encode(),
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            new_data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        # invalid_grant (expired/revoked refresh token) or bad client creds
        if e.code in (400, 401):
            raise AuthError("reauth-required") from None
        raise ApiError(e.code, e.reason, e.read().decode("utf-8", "replace")) from None

    data["access_token"] = new_data["access_token"]
    data["expires_in"] = new_data.get("expires_in", 3600)
    data["obtained_at"] = time.time()
    if "refresh_token" in new_data:
        data["refresh_token"] = new_data["refresh_token"]

    try:
        _save_token(data)
    except OSError:
        pass

    return data["access_token"]


# ── HTTP ──────────────────────────────────────────────────────


def _request(method, path, token, body=None, params=None, _retried=False):
    url = API_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)

    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif method in ("POST", "PUT"):
        data = b""
    else:
        data = None

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        err = ApiError(e.code, e.reason, e.read().decode("utf-8", "replace"))
        if e.code == 429 and err.api_reason != "QUOTA_EXCEEDED" and not _retried:
            try:
                wait = int(e.headers.get("Retry-After", "1"))
            except ValueError:
                wait = 1
            if wait <= MAX_RETRY_WAIT:
                time.sleep(max(wait, 1))
                return _request(method, path, token, body, params, _retried=True)
        raise err from None

    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


def api_get(path, token, params=None):
    return _request("GET", path, token, params=params) or {}


def api_post(path, token, params=None):
    return _request("POST", path, token, params=params)


def api_put(path, token, body=None, params=None):
    return _request("PUT", path, token, body=body, params=params)


def fetch_paged(path, token, extra_params=None, max_items=MAX_ITEMS):
    items = []
    offset = 0
    while len(items) < max_items:
        params = dict(extra_params or {})
        params.update({"limit": PAGE_LIMIT, "offset": offset})
        data = api_get(path, token, params)

        page = data.get("items") or []
        items.extend(page)

        if len(page) < PAGE_LIMIT or not data.get("next"):
            break
        offset += PAGE_LIMIT

    return items[:max_items]


# ── MAPPING ───────────────────────────────────────────────────


def to_track(t):
    """Normalise a track (or podcast episode) object. Returns None for
    missing items and local files, which the API can't play."""
    if not t or t.get("is_local"):
        return None

    uri = t.get("uri", "")
    if not uri or uri.startswith("spotify:local:"):
        return None

    if t.get("type") == "episode":
        show = t.get("show") or {}
        artist = show.get("name") or "Unknown show"
        images = t.get("images") or show.get("images") or []
    else:
        artists = t.get("artists") or []
        names = [a.get("name", "") for a in artists if a and a.get("name")]
        artist = ", ".join(names) if names else "Unknown artist"
        images = (t.get("album") or {}).get("images") or []

    return {
        "uri": uri,
        "title": t.get("name") or "Unknown title",
        "artist": artist,
        "durationMs": t.get("duration_ms", 0),
        "thumbnail": images[-1].get("url", "") if images else "",
    }


# ── COMMANDS ──────────────────────────────────────────────────


def search(token, query):
    data = api_get(
        "/search", token, {"q": query, "type": "track", "limit": SEARCH_LIMIT}
    )
    items = (data.get("tracks") or {}).get("items") or []
    return [t for t in (to_track(x) for x in items) if t]


def get_queue(token):
    data = api_get("/me/player/queue", token)
    return {
        "current": to_track(data.get("currently_playing")),
        "upcoming": [t for t in (to_track(x) for x in data.get("queue") or []) if t],
    }


def get_playlists(token):
    playlists = []
    for p in fetch_paged("/me/playlists", token):
        if not p:
            continue
        images = p.get("images") or []
        items = p.get("items")  # renamed from "tracks"; absent for followed playlists
        playlists.append(
            {
                "id": p.get("id", ""),
                "uri": p.get("uri", ""),
                "name": p.get("name") or "Untitled",
                "thumbnail": images[0].get("url", "") if images else "",
                "trackCount": (items or {}).get("total", 0),
                "browsable": items is not None,
            }
        )
    return playlists


def get_playlist_tracks(token, playlist_id):
    try:
        raw = fetch_paged(f"/playlists/{playlist_id}/items", token)
    except ApiError as e:
        if e.code in (403, 404):
            raise BackendError("playlist-not-browsable") from None
        raise

    tracks = []
    for entry in raw:
        if not entry or entry.get("is_local"):
            continue
        track = to_track(entry.get("item"))
        if track:
            tracks.append(track)
    return tracks


def get_devices(token):
    return api_get("/me/player/devices", token).get("devices") or []


def resolve_device(token, preferred_id=None):
    """Pick the device to control: our own player, then the caller's hint,
    then whatever is active, then anything controllable."""
    devices = [
        d for d in get_devices(token) if d.get("id") and not d.get("is_restricted")
    ]
    if not devices:
        raise BackendError("no-device")

    for d in devices:
        if d.get("name") == OWN_DEVICE_NAME:
            return d["id"]
    for d in devices:
        if d["id"] == preferred_id:
            return d["id"]
    for d in devices:
        if d.get("is_active"):
            return d["id"]
    return devices[0]["id"]


def transfer_playback(token, device_id, start_playing=True):
    api_put("/me/player", token, {"device_ids": [device_id], "play": start_playing})


def queue_track(token, uri, device_id):
    api_post("/me/player/queue", token, {"uri": uri, "device_id": device_id})


def play_track(token, uri, device_id):
    """Start playback of a single track immediately on the given device."""
    api_put("/me/player/play", token, {"uris": [uri]}, {"device_id": device_id})


def play_context(token, context_uri, device_id, offset_position=None):
    """Start playback of a playlist/album/artist as a context, in list order
    (or starting at offset_position if given)."""
    body = {"context_uri": context_uri}
    if offset_position is not None:
        body["offset"] = {"position": offset_position}
    api_put("/me/player/play", token, body, {"device_id": device_id})


def set_shuffle(token, state, device_id):
    api_put(
        "/me/player/shuffle",
        token,
        params={"state": "true" if state else "false", "device_id": device_id},
    )


def play_mix(token, context_uri, track_count, device_id):
    """Play a playlist shuffled, starting on a random track.

    Starting at a random offset avoids the old play -> wait -> shuffle ->
    skip dance. If the track count is unknown (followed playlists) or the
    offset is rejected, it starts from the top and skips once after
    shuffle is on. Returns whether shuffle was enabled; playback having
    started is the part that counts as success.
    """
    started_random = False
    if track_count > 0:
        try:
            play_context(token, context_uri, device_id, random.randrange(track_count))
            started_random = True
        except ApiError as e:
            if e.code not in (400, 404) or e.api_reason == "NO_ACTIVE_DEVICE":
                raise
    if not started_random:
        play_context(token, context_uri, device_id)

    shuffled = False
    for attempt in range(3):
        try:
            set_shuffle(token, True, device_id)
            shuffled = True
            break
        except ApiError as e:
            if e.code != 404:
                break
            time.sleep(0.5)

    if shuffled and not started_random:
        try:
            api_post("/me/player/next", token, {"device_id": device_id})
        except ApiError:
            pass

    return shuffled


# ── ENTRY POINT ───────────────────────────────────────────────


def _api_error_code(e):
    if e.code == 401:
        return "reauth-required"
    if e.api_reason == "NO_ACTIVE_DEVICE":
        return "no-device"
    if e.api_reason == "PREMIUM_REQUIRED":
        return "premium-required"
    if e.code == 429:
        return "quota-exceeded" if e.api_reason == "QUOTA_EXCEEDED" else "rate-limited"
    return str(e)[:200]


def _arg(args, i):
    return args[i] if len(args) > i and args[i] != "" else None


def run(args):
    if not args:
        raise BackendError("no-command")

    cmd = args[0]
    required = {
        "search": 1,
        "playlist": 1,
        "activate": 1,
        "queue": 1,
        "play": 1,
        "play_context": 1,
        "shuffle": 1,
        "play_mix": 2,
    }
    if len(args) - 1 < required.get(cmd, 0):
        raise BackendError("bad-args")

    known = {
        "search",
        "playlists",
        "playlist",
        "devices",
        "activate",
        "queue",
        "play",
        "play_context",
        "shuffle",
        "queue_state",
        "play_mix",
    }
    if cmd not in known:
        raise BackendError("unknown-command")

    token = load_token()

    if cmd == "search":
        return {"query": args[1], "results": search(token, args[1])}
    if cmd == "playlists":
        return {"playlists": get_playlists(token)}
    if cmd == "playlist":
        return {"playlistId": args[1], "tracks": get_playlist_tracks(token, args[1])}
    if cmd == "devices":
        return {"devices": get_devices(token)}
    if cmd == "queue_state":
        return get_queue(token)
    if cmd == "activate":
        transfer_playback(token, args[1], start_playing=False)
        return {}

    if cmd == "play_mix":
        try:
            count = int(args[2])
        except ValueError:
            count = 0
        device_id = resolve_device(token, _arg(args, 3))
        shuffled = play_mix(token, args[1], count, device_id)
        return {"deviceId": device_id, "shuffle": shuffled}

    device_id = resolve_device(token, _arg(args, 2))
    if cmd == "queue":
        queue_track(token, args[1], device_id)
    elif cmd == "play":
        play_track(token, args[1], device_id)
    elif cmd == "play_context":
        play_context(token, args[1], device_id)
    elif cmd == "shuffle":
        set_shuffle(token, args[1] == "true", device_id)
    return {"deviceId": device_id}


def main():
    try:
        result = {"ok": True, **run(sys.argv[1:])}
    except BackendError as exc:
        result = {"ok": False, "error": str(exc)}
    except ApiError as exc:
        result = {"ok": False, "error": _api_error_code(exc)}
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, socket.gaierror):
            result = {"ok": False, "error": "dns-failure"}
        else:
            result = {"ok": False, "error": f"network: {exc.reason}"}
    except (TimeoutError, socket.timeout):
        result = {"ok": False, "error": "network: timeout"}
    except Exception as exc:
        result = {"ok": False, "error": str(exc)[:200]}

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
