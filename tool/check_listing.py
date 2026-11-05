"""Checks store/google-play/listing.md against Google Play's character limits.

Run from the builder-pro-mobile folder:  python tool/check_listing.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "store", "google-play", "listing.md")

LIMITS = {
    "App name": 30,
    "Short description": 80,
    "Full description": 4000,
    "What's new": 500,
    "Internal testing notes": 500,
}

text = open(PATH, encoding="utf-8").read().replace("\r\n", "\n")
sections = re.split(r"^## ", text, flags=re.M)[1:]
failed = False
for block in sections:
    title, _, body = block.partition("\n")
    for key, limit in LIMITS.items():
        if title.startswith(key):
            # The body up to the next heading, without the blank lines around it.
            n = len(body.strip())
            flag = "ok" if n <= limit else "TOO LONG"
            failed |= n > limit
            print(f"{key}: {n}/{limit} {flag}")
sys.exit(1 if failed else 0)
