# Import samples

One file per format **File › Import…** reads, for trying imports by hand. Everything here is made up: usernames
are on `example.com` / `.test`, and the sites are real only so icons and site matching show. Regenerate (new SSH
key, dates relative to today) with:

```bash
python3 Samples/Import/generate.py
```

| File | Format | What's in it |
| --- | --- | --- |
| `bitwarden.json` | Bitwarden JSON | The full tour, below |
| `bitwarden.csv` | Bitwarden CSV | Logins with a folder, favourite, custom field and code; a note |
| `chrome.csv` | Chrome, Edge, Brave, Arc… | Two logins |
| `safari.csv` | Safari / Apple Passwords | A login with a one-time code, one with a note |
| `firefox.csv` | Firefox | One login |
| `lastpass.csv` | LastPass | A login with a code and folder; a secure note |
| `1password.csv` | 1Password CSV | A favourite; an archived item, which is skipped |
| `1password.1pux` | 1Password 1PUX | Two vaults (become folders), a code, a hidden field, a note, an archived item (skipped) |
| `keepassxc.csv` | KeePassXC CSV | Nested groups (become folders), a code |
| `keepass.xml` | KeePass 2 XML | A protected PIN field, a code; its history versions are not imported |
| `protonpass.csv` | Proton Pass | A login and a note |
| `dashlane.csv` | Dashlane | Second username as a field, a code, a category folder |

## What `bitwarden.json` shows

- **Folders:** Work, Work/Servers (nested), Personal, Finance, 家族.
- **Watchtower and the list's issue marks:** a weak password (pizza shop), two logins sharing a password
  (Netflix, Spotify), an `http://` site (old forum), two copies of one Amazon login, a bank password unchanged
  for four years, and a Visa that expires within 60 days. The NAS on `http://192.168.…` is not flagged.
- **Item history:** GitHub has two earlier passwords and a recent password change.
- **Custom fields:** GitHub has a text, a hidden and a boolean field.
- **One-time codes:** GitHub, Google and Cloudflare (all the same test secret).
- **Equivalent domains:** Google and YouTube.
- **Master password re-prompt:** Proxmox.
- **Other types:** two notes, two cards, an identity, and a real Ed25519 SSH key you can use with the SSH agent.
- **Text:** Chinese and Japanese names, emoji, and a note with quotes, commas and a second line.
