#!/usr/bin/env python3
"""
One-time Google Calendar authorisation for the Quickshell bar.

Run this by hand in a terminal:

    python3 ~/.config/quickshell/scripts/calendar-auth.py

It opens a browser, asks for consent, and writes token.json. calendar-backend.py
then refreshes that token silently forever after. Re-run this only if you revoke
access, delete token.json, or change SCOPES.
"""

import os
import os.path
import sys

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/calendar.events"]

# Secrets live outside the dotfiles checkout so they can never be committed or stowed
CONFIG_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "quickshell", "secrets")
CREDENTIALS_FILE = os.path.join(CONFIG_DIR, "credentials.json")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")


def main():
    if not os.path.exists(CREDENTIALS_FILE):
        print(f"missing OAuth client file: {CREDENTIALS_FILE}", file=sys.stderr)
        print(
            "download it from the Google Cloud console "
            "(APIs & Services -> Credentials -> OAuth client ID -> Desktop app)",
            file=sys.stderr,
        )
        return 1

    flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
    creds = flow.run_local_server(port=0)

    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    with open(TOKEN_FILE, "w") as f:
        f.write(creds.to_json())
    os.chmod(TOKEN_FILE, 0o600)

    print(f"wrote {TOKEN_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
