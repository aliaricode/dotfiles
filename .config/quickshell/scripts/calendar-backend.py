#!/usr/bin/env python3
"""
Calendar + weather backend for the Quickshell bar.

Usage:
    calendar-backend.py [lat] [lon]     fetch weather + events, JSON on stdout
    calendar-backend.py add "<text>"    create an event via Google quickAdd

This script NEVER runs an interactive OAuth flow -- it is spawned headlessly by
the bar, where a browser prompt would hang forever. Run calendar-auth.py once by
hand to mint token.json; after that this refreshes the token silently.
"""

import datetime
import json
import os
import os.path
import sys
import urllib.parse
import urllib.request

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/calendar.events"]

# Secrets live outside the dotfiles checkout so they can never be committed or stowed
CONFIG_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "quickshell", "secrets")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")
CACHE_FILE = os.path.expanduser("~/.cache/quickshell/calendar.json")

DAYS_BACK = 190
DAYS_FORWARD = 400
MAX_RESULTS = 250

DEFAULT_LAT = "41.02"
DEFAULT_LON = "28.58"


def load_credentials():
    """Return valid credentials, or None. Never prompts."""
    if not os.path.exists(TOKEN_FILE):
        return None

    try:
        creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)
    except Exception:
        return None

    if creds and creds.valid:
        return creds

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except Exception:
            return None
        try:
            with open(TOKEN_FILE, "w") as f:
                f.write(creds.to_json())
        except OSError:
            pass
        return creds

    return None


def weather_icon(code, is_day):
    """WMO weather code -> Nerd Font glyph."""
    if code == 0:
        return "\U000f0599" if is_day else "\U000f0594"
    if code in (1, 2):
        return "\U000f0595"
    if code == 3:
        return "\U000f0590"
    if code in (45, 48):
        return "\U000f0591"
    if code in (51, 53, 55, 56, 57, 61, 63, 80, 81):
        return "\U000f0597"
    if code in (65, 82):
        return "\U000f0596"
    if code in (66, 67):
        return "\U000f0592"
    if code in (71, 73, 75, 77, 85, 86):
        return "\U000f0598"
    if code in (95, 96, 99):
        return "\U000f0593"
    return "\U000f0590"


def get_weather(lat, lon):
    params = urllib.parse.urlencode(
        {
            "latitude": lat,
            "longitude": lon,
            "current_weather": "true",
            "daily": "temperature_2m_max,temperature_2m_min",
            "timezone": "auto",
            "forecast_days": 1,
        }
    )
    url = "https://api.open-meteo.com/v1/forecast?" + params

    try:
        with urllib.request.urlopen(url, timeout=5) as req:
            data = json.loads(req.read())
    except Exception:
        return {
            "temp": "--",
            "icon": "\U000f0590",
            "high": None,
            "low": None,
            "error": "unreachable",
        }

    current = data.get("current_weather") or {}
    daily = data.get("daily") or {}
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []

    return {
        "temp": round(current.get("temperature", 0)),
        "icon": weather_icon(
            int(current.get("weathercode", 0)),
            bool(current.get("is_day", 1)),
        ),
        "high": round(highs[0]) if highs else None,
        "low": round(lows[0]) if lows else None,
        "error": None,
    }


def get_events(creds):
    """Return (events, error). error is None on success."""
    if creds is None:
        return [], "no-auth"

    now = datetime.datetime.now().astimezone()
    start = (now - datetime.timedelta(days=DAYS_BACK)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    end = now + datetime.timedelta(days=DAYS_FORWARD)

    try:
        service = build("calendar", "v3", credentials=creds, cache_discovery=False)
        result = (
            service.events()
            .list(
                calendarId="primary",
                timeMin=start.isoformat(),
                timeMax=end.isoformat(),
                maxResults=MAX_RESULTS,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )
    except Exception:
        return [], "fetch-failed"

    events = []
    for event in result.get("items", []):
        raw = event["start"].get("dateTime") or event["start"].get("date")
        if not raw:
            continue
        all_day = "T" not in raw
        events.append(
            {
                "date": raw[:10],
                "title": event.get("summary", "Busy"),
                "time": "All Day" if all_day else raw[11:16],
                "allDay": all_day,
                "id": event.get("id", ""),
            }
        )

    return events, None


def add_event(text):
    """Create an event from natural language via Google's quickAdd."""
    creds = load_credentials()
    if creds is None:
        return {"ok": False, "error": "no-auth"}

    try:
        service = build("calendar", "v3", credentials=creds, cache_discovery=False)
        event = service.events().quickAdd(calendarId="primary", text=text).execute()
    except Exception as exc:
        return {"ok": False, "error": str(exc)[:200]}

    return {"ok": True, "id": event.get("id", ""), "title": event.get("summary", "")}


def write_cache(payload):
    """Atomic write, so a crash mid-write can't leave a corrupt cache."""
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def read_cache():
    try:
        with open(CACHE_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def main():
    args = sys.argv[1:]

    if args and args[0] == "add":
        text = args[1] if len(args) > 1 else ""
        if not text.strip():
            print(json.dumps({"ok": False, "error": "empty"}))
            return 0
        print(json.dumps(add_event(text)))
        return 0

    lat = args[0] if len(args) > 0 else DEFAULT_LAT
    lon = args[1] if len(args) > 1 else DEFAULT_LON

    weather = get_weather(lat, lon)
    events, error = get_events(load_credentials())

    if error and not events:
        cached = read_cache()
        if cached and cached.get("events"):
            events = cached["events"]

    payload = {"weather": weather, "events": events, "error": error}
    write_cache(payload)
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
