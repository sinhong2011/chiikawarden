#!/usr/bin/env python3
"""Decrypts a password-protected Bitwarden export with an implementation independent of the app
(seed.py's crypto), the way Bitwarden's clients do: makePinKey(password, salt, kdf) → stretch → EncString.

    python3 DevServer/verify_export.py export.json file-password
"""
import hashlib
import json
import sys

from argon2.low_level import Type, hash_secret_raw

from seed import decrypt, stretch


def main():
    path, password = sys.argv[1], sys.argv[2]
    doc = json.load(open(path))
    assert doc["encrypted"] and doc["passwordProtected"], "not a password-protected export"
    salt = doc["salt"].encode()  # used as written, not decoded
    if doc["kdfType"] == 0:
        raw = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, doc["kdfIterations"], 32)
    else:
        raw = hash_secret_raw(password.encode(), hashlib.sha256(salt).digest(), time_cost=doc["kdfIterations"],
                              memory_cost=doc["kdfMemory"] * 1024, parallelism=doc["kdfParallelism"], hash_len=32, type=Type.ID)
    key = stretch(raw)
    decrypt(doc["encKeyValidation_DO_NOT_EDIT"], key)
    vault = json.loads(decrypt(doc["data"], key))
    assert vault["encrypted"] is False
    print(f"OK {len(vault['items'])} items, {len(vault['folders'])} folders:",
          ", ".join(sorted(item["name"] for item in vault["items"])))


if __name__ == "__main__":
    main()
