#!/usr/bin/env python3
"""Writes one sample file per import format Triwarden reads, for trying File › Import by hand.

    python3 Samples/Import/generate.py

Every credential here is made up (usernames on example.com / .test); the sites are real so icons and
equivalent-domain matching show. The Bitwarden JSON file is the richest: it's built to light up Watchtower and
the list's issue marks, the item history card, custom fields, folders, cards, an identity and an SSH key.
"""
import csv
import io
import json
import os
import subprocess
import tempfile
import uuid
import zipfile
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
NOW = datetime.now(timezone.utc)
TOTP = "JBSWY3DPEHPK3PXP"  # a valid base32 secret: codes tick in the app


def iso(days_ago: float) -> str:
    return (NOW - timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def write(name: str, text: str) -> None:
    with open(os.path.join(HERE, name), "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("wrote", name)


def csv_text(header: list[str], rows: list[list]) -> str:
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(header)
    w.writerows(rows)
    return out.getvalue()


def ssh_key() -> tuple[str, str, str]:
    """A fresh, unencrypted Ed25519 key (private, public, fingerprint), so the SSH agent has something real."""
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "k")
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "sample@triwarden.test", "-f", path], check=True)
        private = open(path).read()
        public = open(path + ".pub").read().strip()
        fp = subprocess.run(["ssh-keygen", "-lf", path + ".pub"], capture_output=True, text=True).stdout.split()[1]
        return private, public, fp


# ---------------------------------------------------------------------------------------------------- Bitwarden JSON

def bitwarden_json() -> None:
    folders = {name: str(uuid.uuid4()) for name in ["Work", "Work/Servers", "Personal", "Finance", "家族"]}

    def login(name, uri, user, pw, folder=None, totp=None, fav=False, notes=None, fields=None, history=None,
              created=400, revised=30, pw_changed=None, uris=None, reprompt=0):
        item = {
            "id": str(uuid.uuid4()), "organizationId": None, "folderId": folders.get(folder), "type": 1,
            "reprompt": reprompt, "name": name, "notes": notes, "favorite": fav, "fields": fields or [],
            "login": {"uris": [{"match": None, "uri": u} for u in (uris or [uri])], "username": user, "password": pw,
                      "totp": totp, "passwordRevisionDate": iso(pw_changed) if pw_changed is not None else None},
            "passwordHistory": [{"lastUsedDate": iso(d), "password": p} for p, d in (history or [])] or None,
            "creationDate": iso(created), "revisionDate": iso(revised), "collectionIds": None,
        }
        return item

    def other(kind, name, folder=None, notes=None, fav=False, **parts):
        item = {"id": str(uuid.uuid4()), "organizationId": None, "folderId": folders.get(folder), "type": kind,
                "reprompt": 0, "name": name, "notes": notes, "favorite": fav, "fields": [],
                "creationDate": iso(200), "revisionDate": iso(10), "collectionIds": None}
        item.update(parts)
        return item

    private, public, fingerprint = ssh_key()
    expiry = NOW + timedelta(days=40)  # inside Watchtower's 60-day "expiring" window

    items = [
        # Healthy, rich logins.
        login("GitHub", "https://github.com/login", "usagi@example.com", "m7Kq#vR2!tLp9wZe$Hu4", "Work", totp=TOTP, fav=True,
              notes="Recovery codes are in the “GitHub recovery” note.",
              fields=[{"name": "Org", "value": "chiikawa-dev", "type": 0},
                      {"name": "Recovery PIN", "value": "0420", "type": 1},
                      {"name": "SSO enforced", "value": "true", "type": 2}],
              history=[("7m4Gv%Y6A56NAMPBz#aoTX", 12), ("OldGitHub!2023", 400)], pw_changed=12,
              uris=["https://github.com/login", "https://gist.github.com"]),
        login("Google", "https://accounts.google.com", "usagi.test@example.com", "q9!Rk2#Vw7@Lp4$Tz8", "Personal", totp=TOTP, fav=True),
        login("YouTube (shares Google's sign-in)", "https://www.youtube.com", "usagi.test@example.com", "q9!Rk2#Vw7@Lp4$Tz8-yt", "Personal"),
        login("Discord", "https://discord.com/login", "usagi#0420", "Dc$7mQ!x2Lp#9vWz", "Personal"),
        login("Cloudflare", "https://dash.cloudflare.com", "ops@example.com", "Cf@8nT!q3Zr#6wLm$2", "Work", totp=TOTP),
        login("Tailscale", "https://login.tailscale.com", "ops@example.com", "Ts!4xR#9mQ@2vLz$7k", "Work/Servers"),
        login("Synology NAS (LAN, http is fine)", "http://192.168.1.20:5000", "admin", "Nas#5tQ!8wRz@3mLp", "Work/Servers"),
        login("Proxmox", "https://pve.home.arpa:8006", "root@pam", "Px!9vT#3qR@7wLz$5m", "Work/Servers", reprompt=1,
              notes="Ask for the master password before showing this one."),
        # Watchtower problems, one of each.
        login("Old forum (http://, unencrypted)", "http://forum.example.org/login", "usagi", "Fx#8qL!2vR@6tZm$4w", "Personal"),
        login("Weak: pizza shop", "https://pizza.example.com", "usagi@example.com", "pizza123", "Personal"),
        login("Reused: Netflix", "https://www.netflix.com", "usagi@example.com", "Summer2024!", "Personal"),
        login("Reused: Spotify", "https://open.spotify.com", "usagi@example.com", "Summer2024!", "Personal"),
        login("Duplicate: Amazon", "https://www.amazon.com", "usagi@example.com", "Am$7qT!2vR#9wLz@4", "Finance"),
        login("Duplicate: Amazon (older copy)", "https://amazon.com", "usagi@example.com", "Am$7qT!2vR#9wLz@4-old", "Finance", revised=500),
        login("Not changed in years: bank", "https://bank.example.com", "88123456", "Bk#6vQ!9tR@2wLz$8m", "Finance",
              created=1600, revised=1500, pw_changed=1500),
        # Unicode and awkward text.
        login("樂天市場 🛍️", "https://www.rakuten.co.jp", "usagi@example.com", "楽天!Rk#7qT@2vLz$9", "家族",
              notes="日本語のメモ，中文備註，and a line with \"quotes\", commas, and\nsecond line."),
        login("ちいかわ ショップ", "https://chiikawamarket.jp", "usagi", "日本語パスワード🍓-R7#q", "家族"),
        # Other types.
        other(2, "Wi-Fi at home", "Personal", notes="SSID: pochi-net\nPassword: correct-horse-battery-staple", secureNote={"type": 0}),
        other(2, "GitHub recovery", "Work", notes="a1b2-c3d4\ne5f6-g7h8\ni9j0-k1l2", secureNote={"type": 0}),
        other(3, "Visa (expiring soon)", "Finance", fav=True, card={
            "cardholderName": "Usagi Test", "brand": "Visa", "number": "4111111111111111",
            "expMonth": str(expiry.month), "expYear": str(expiry.year), "code": "123"}),
        other(3, "Mastercard", "Finance", card={
            "cardholderName": "Usagi Test", "brand": "Mastercard", "number": "5555555555554444",
            "expMonth": "12", "expYear": str(NOW.year + 3), "code": "456"}),
        other(4, "Me", "Personal", identity={
            "title": "Ms", "firstName": "Usagi", "middleName": None, "lastName": "Test", "address1": "1-2-3 Shibuya",
            "address2": None, "address3": None, "city": "Tokyo", "state": "Tokyo", "postalCode": "150-0002",
            "country": "JP", "company": "Chiikawa Ltd.", "email": "usagi@example.com", "phone": "+81 90 1234 5678",
            "ssn": None, "username": "usagi", "passportNumber": None, "licenseNumber": None}),
        other(5, "Sample SSH key (Ed25519)", "Work/Servers", notes="Made by generate.py; safe to delete.",
              sshKey={"privateKey": private, "publicKey": public, "keyFingerprint": fingerprint}),
    ]
    data = {"encrypted": False,
            "folders": [{"id": i, "name": n} for n, i in folders.items()],
            "items": items}
    write("bitwarden.json", json.dumps(data, ensure_ascii=False, indent=2))


# ---------------------------------------------------------------------------------------------------------- CSVs

def csvs() -> None:
    write("bitwarden.csv", csv_text(
        ["folder", "favorite", "type", "name", "notes", "fields", "reprompt", "login_uri", "login_username", "login_password", "login_totp"],
        [["Work", "1", "login", "GitLab", "", "Team: platform", "0", "https://gitlab.com", "usagi@example.com", "Gl#7qT!2vR@9wLz", TOTP],
         ["Personal", "", "login", "Reddit", "", "", "0", "https://www.reddit.com", "usagi_test", "Rd!4xQ#8mT@2vLz", ""],
         ["", "", "note", "Locker code", "4-2-0-6", "", "0", "", "", "", ""]]))
    write("chrome.csv", csv_text(
        ["name", "url", "username", "password", "note"],
        [["github.com", "https://github.com/login", "usagi@example.com", "Ch#7qT!2vR@9wLz", "from Chrome"],
         ["notion.so", "https://www.notion.so/login", "usagi@example.com", "No!4xQ#8mT@2vLz", ""]]))
    write("safari.csv", csv_text(
        ["Title", "URL", "Username", "Password", "Notes", "OTPAuth"],
        [["Apple Developer", "https://developer.apple.com", "usagi@example.com", "Ap#7qT!2vR@9wLz", "",
          f"otpauth://totp/Apple:usagi?secret={TOTP}&issuer=Apple"],
         ["Figma", "https://www.figma.com", "usagi@example.com", "Fg!4xQ#8mT@2vLz", "design", ""]]))
    write("firefox.csv", csv_text(
        ["url", "username", "password", "httpRealm", "formActionOrigin", "guid", "timeCreated", "timeLastUsed", "timePasswordChanged"],
        [["https://www.mozilla.org", "usagi@example.com", "Mz#7qT!2vR@9wLz", "", "https://www.mozilla.org", "{" + str(uuid.uuid4()) + "}",
          "1700000000000", "1720000000000", "1710000000000"]]))
    write("lastpass.csv", csv_text(
        ["url", "username", "password", "totp", "extra", "name", "grouping", "fav"],
        [["https://www.dropbox.com/login", "usagi@example.com", "Db#7qT!2vR@9wLz", TOTP, "a note", "Dropbox", "Work", "1"],
         ["http://sn", "", "", "", "Wi-Fi: pochi-net, password correct-horse", "Wi-Fi (secure note)", "Personal", "0"]]))
    write("1password.csv", csv_text(
        ["Title", "Url", "Username", "Password", "OTPAuth", "Favorite", "Archived", "Tags", "Notes"],
        [["Slack", "https://app.slack.com", "usagi@example.com", "Sl#7qT!2vR@9wLz", "", "true", "false", "work", ""],
         ["Archived (skipped)", "https://old.example.com", "u", "p", "", "false", "true", "", ""]]))
    write("keepassxc.csv", csv_text(
        ["Group", "Title", "Username", "Password", "URL", "Notes", "TOTP", "Icon", "Last Modified", "Created"],
        [["Root/Work/Servers", "Grafana", "admin", "Gf#7qT!2vR@9wLz", "https://grafana.home.arpa", "", f"otpauth://totp/x?secret={TOTP}", "0", "", ""],
         ["Root/Personal", "Steam", "usagi_test", "St!4xQ#8mT@2vLz", "https://store.steampowered.com", "", "", "0", "", ""]]))
    write("protonpass.csv", csv_text(
        ["type", "name", "url", "email", "username", "password", "note", "totp", "createTime", "modifyTime", "vault"],
        [["login", "Proton Mail", "https://account.proton.me", "usagi@example.com", "", "Pm#7qT!2vR@9wLz", "", "", "1700000000", "1710000000", "Personal"],
         ["note", "Proton recovery phrase", "", "", "", "", "alpha bravo charlie delta", "", "1700000000", "1710000000", "Personal"]]))
    write("dashlane.csv", csv_text(
        ["username", "username2", "username3", "title", "password", "note", "url", "category", "otpSecret"],
        [["usagi@example.com", "usagi_alt", "", "Twitch", "Tw#7qT!2vR@9wLz", "", "https://www.twitch.tv", "Entertainment", TOTP]]))


# ------------------------------------------------------------------------------------------------- KeePass, 1Password

def keepass_xml() -> None:
    write("keepass.xml", f"""<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<KeePassFile><Root><Group><Name>Database</Name>
  <Group><Name>Work</Name>
    <Entry>
      <String><Key>Title</Key><Value>Jira</Value></String>
      <String><Key>UserName</Key><Value>usagi@example.com</Value></String>
      <String><Key>Password</Key><Value Protected="True">Ji#7qT!2vR@9wLz</Value></String>
      <String><Key>URL</Key><Value>https://example.atlassian.net</Value></String>
      <String><Key>PIN</Key><Value Protected="True">0420</Value></String>
      <String><Key>otp</Key><Value>otpauth://totp/Jira?secret={TOTP}</Value></String>
      <History><Entry><String><Key>Password</Key><Value>old-jira-pw</Value></String></Entry></History>
    </Entry>
  </Group>
  <Entry><String><Key>Title</Key><Value>Note only</Value></String><String><Key>Notes</Key><Value>Just a note from KeePass.</Value></String></Entry>
</Group></Root></KeePassFile>
""")


def one_password_1pux() -> None:
    export = {"accounts": [{"vaults": [
        {"attrs": {"name": "Personal"}, "items": [
            {"categoryUuid": "001", "favIndex": 1,
             "overview": {"title": "Linear", "urls": [{"url": "https://linear.app"}]},
             "details": {"loginFields": [{"designation": "username", "value": "usagi@example.com"},
                                         {"designation": "password", "value": "Ln#7qT!2vR@9wLz"}],
                         "notesPlain": "From 1Password (.1pux).",
                         "sections": [{"fields": [{"title": "one-time password", "value": {"totp": f"otpauth://totp/Linear?secret={TOTP}"}},
                                                  {"title": "Backup PIN", "value": {"concealed": "0420"}}]}]}},
            {"categoryUuid": "003", "overview": {"title": "Gym locker"}, "details": {"notesPlain": "Locker 42, code 1-9-8-4"}},
            {"categoryUuid": "001", "state": "archived", "overview": {"title": "Archived (skipped)"}, "details": {}},
        ]},
        {"attrs": {"name": "Work"}, "items": [
            {"categoryUuid": "001", "overview": {"title": "Vercel", "urls": [{"url": "https://vercel.com"}]},
             "details": {"loginFields": [{"designation": "username", "value": "ops@example.com"},
                                         {"designation": "password", "value": "Vc!4xQ#8mT@2vLz"}]}},
        ]},
    ]}]}
    path = os.path.join(HERE, "1password.1pux")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("export.attributes", json.dumps({"version": 3, "description": "1Password Unencrypted Export"}))
        z.writestr("export.data", json.dumps(export, ensure_ascii=False))
    print("wrote 1password.1pux")


if __name__ == "__main__":
    bitwarden_json()
    csvs()
    keepass_xml()
    one_password_1pux()
