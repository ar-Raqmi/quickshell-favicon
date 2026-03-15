import sqlite3
import os
import json
import shutil
import tempfile
from pathlib import Path
import re
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor

HOME = Path.home()

BROWSER_PATHS = [
    ("chromium", HOME / ".config/google-chrome/Default/History"),
    ("chromium", HOME / ".config/chromium/Default/History"),
    ("chromium", HOME / ".config/BraveSoftware/Brave-Browser/Default/History"),
    ("chromium", HOME / ".config/microsoft-edge/Default/History"),
    ("chromium", HOME / ".config/vivaldi/Default/History"),
    ("chromium", HOME / ".config/opera/History"),
    ("chromium", HOME / ".config/thorium/Default/History"),
    ("chromium", HOME / ".config/yandex-browser/Default/History"),
    ("firefox", HOME / ".mozilla/firefox"),
]

CACHE_DIR = Path("~/.cache/quickshell/favicons").expanduser()
CACHE_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FILE = CACHE_DIR / "exact_title_to_url.json"

BROWSER_SUFFIX = re.compile(
    r"\s*[-|—|·]\s*(Mozilla Firefox|Brave|Google Chrome|Chromium|Vivaldi|Edge|"
    r"Zen|Floorp|LibreWolf|Thorium|Waterfox|Mullvad|Tor Browser|"
    r"Chrome|Firefox|Web Browser|Browser|Quickshell|Antigravity)\s*$",
    re.IGNORECASE
)

NOISE_PREFIX = re.compile(r"^\s*[\[(]\d+[\])]\s*|^\s*\*\s*")


def clean_title(title):
    if not title:
        return None

    title = BROWSER_SUFFIX.sub("", title).strip()
    return title or None


def normalize_title(title):
    if not title:
        return None
    return NOISE_PREFIX.sub("", title).strip()


def copy_db(path: Path):
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
        tmp.close()

        shutil.copy2(path, tmp.name)

        for suffix in ("-wal", "-shm"):
            sidecar = path.with_suffix(path.suffix + suffix)
            if sidecar.exists():
                shutil.copy2(sidecar, tmp.name + suffix)

        return tmp.name

    except Exception:
        return None


def extract_chromium(path: Path):
    mappings = {}

    tmp = copy_db(path)
    if not tmp:
        return mappings

    try:
        conn = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        cur = conn.cursor()

        cur.execute("""
            SELECT title, url
            FROM urls
            WHERE title IS NOT NULL
            ORDER BY last_visit_time DESC
            LIMIT 5000
        """)

        for title, url in cur.fetchall():

            cleaned = clean_title(title)
            if cleaned and cleaned not in mappings:
                mappings[cleaned] = url

            normalized = normalize_title(cleaned)
            if normalized and normalized != cleaned and normalized not in mappings:
                mappings[normalized] = url

        conn.close()

    except Exception:
        traceback.print_exc(file=sys.stderr)

    finally:
        try:
            os.unlink(tmp)
        except:
            pass

    return mappings


def extract_firefox(profile_dir: Path):
    mappings = {}

    for profile in profile_dir.glob("*.default*"):
        db = profile / "places.sqlite"
        if not db.exists():
            continue

        tmp = copy_db(db)
        if not tmp:
            continue

        try:
            conn = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
            cur = conn.cursor()

            cur.execute("""
                SELECT title, url
                FROM moz_places
                WHERE title IS NOT NULL
                ORDER BY last_visit_date DESC
                LIMIT 5000
            """)

            for title, url in cur.fetchall():

                cleaned = clean_title(title)
                if cleaned and cleaned not in mappings:
                    mappings[cleaned] = url

                normalized = normalize_title(cleaned)
                if normalized and normalized != cleaned and normalized not in mappings:
                    mappings[normalized] = url

            conn.close()

        except Exception:
            traceback.print_exc(file=sys.stderr)

        finally:
            try:
                os.unlink(tmp)
            except:
                pass

    return mappings


def extract_all():
    mappings = {}

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = []

        for t, p in BROWSER_PATHS:
            if t == "chromium" and p.exists():
                futures.append(executor.submit(extract_chromium, p))

            elif t == "firefox" and p.exists():
                futures.append(executor.submit(extract_firefox, p))

        for f in futures:
            try:
                mappings.update(f.result())
            except Exception:
                pass

    return mappings


def main():
    mappings = extract_all()

    with open(OUTPUT_FILE, "w") as f:
        json.dump(mappings, f, indent=2)

    print(f"Saved {len(mappings)} mappings → {OUTPUT_FILE}")


if __name__ == "__main__":
    main()import sqlite3
import os
import json
import shutil
import tempfile
from pathlib import Path
import re
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor

HOME = Path.home()

# Known browser history locations (fast, no filesystem crawling)
BROWSER_PATHS = [
    ("chromium", HOME / ".config/google-chrome/Default/History"),
    ("chromium", HOME / ".config/chromium/Default/History"),
    ("chromium", HOME / ".config/BraveSoftware/Brave-Browser/Default/History"),
    ("chromium", HOME / ".config/microsoft-edge/Default/History"),
    ("chromium", HOME / ".config/vivaldi/Default/History"),
    ("chromium", HOME / ".config/opera/History"),
    ("chromium", HOME / ".config/thorium/Default/History"),
    ("chromium", HOME / ".config/yandex-browser/Default/History"),

    ("firefox", HOME / ".mozilla/firefox"),
]

CACHE_DIR = Path("~/.cache/quickshell/favicons").expanduser()
CACHE_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FILE = CACHE_DIR / "exact_title_to_url.json"


# Remove browser suffixes from titles
BROWSER_SUFFIX = re.compile(
    r"\s*[-|—|·]\s*(Mozilla Firefox|Brave|Google Chrome|Chromium|Vivaldi|Edge|"
    r"Zen|Floorp|LibreWolf|Thorium|Waterfox|Mullvad|Tor Browser|"
    r"Chrome|Firefox|Web Browser|Browser|Quickshell|Antigravity)\s*$",
    re.IGNORECASE
)


def clean_title(title: str | None):
    if not title:
        return None

    title = BROWSER_SUFFIX.sub("", title).strip()

    # remove counters like "(3)"
    title = re.sub(r"\(\d+\)$", "", title).strip()

    return title or None


def copy_db(path: Path):
    """Copy DB safely to temp file."""
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
        tmp.close()

        shutil.copy2(path, tmp.name)

        for suffix in ("-wal", "-shm"):
            sidecar = path.with_suffix(path.suffix + suffix)
            if sidecar.exists():
                shutil.copy2(sidecar, tmp.name + suffix)

        return tmp.name

    except Exception:
        return None


def extract_chromium(path: Path):
    mappings = {}

    tmp = copy_db(path)
    if not tmp:
        return mappings

    try:
        conn = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        cur = conn.cursor()

        cur.execute("""
            SELECT title, url
            FROM urls
            WHERE title IS NOT NULL
            ORDER BY last_visit_time DESC
            LIMIT 5000
        """)

        for title, url in cur.fetchall():
            t = clean_title(title)
            if t and t not in mappings:
                mappings[t] = url

        conn.close()

    except Exception:
        traceback.print_exc(file=sys.stderr)

    finally:
        try:
            os.unlink(tmp)
        except:
            pass

    return mappings


def extract_firefox(profile_dir: Path):
    mappings = {}

    for profile in profile_dir.glob("*.default*"):
        db = profile / "places.sqlite"
        if not db.exists():
            continue

        tmp = copy_db(db)
        if not tmp:
            continue

        try:
            conn = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
            cur = conn.cursor()

            cur.execute("""
                SELECT title, url
                FROM moz_places
                WHERE title IS NOT NULL
                ORDER BY last_visit_date DESC
                LIMIT 5000
            """)

            for title, url in cur.fetchall():
                t = clean_title(title)
                if t and t not in mappings:
                    mappings[t] = url

            conn.close()

        except Exception:
            traceback.print_exc(file=sys.stderr)

        finally:
            try:
                os.unlink(tmp)
            except:
                pass

    return mappings


def extract_all():
    mappings = {}

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = []

        for t, p in BROWSER_PATHS:
            if t == "chromium" and p.exists():
                futures.append(executor.submit(extract_chromium, p))

            elif t == "firefox" and p.exists():
                futures.append(executor.submit(extract_firefox, p))

        for f in futures:
            try:
                mappings.update(f.result())
            except Exception:
                pass

    return mappings


def main():
    mappings = extract_all()

    with open(OUTPUT_FILE, "w") as f:
        json.dump(mappings, f, indent=2)

    print(f"Saved {len(mappings)} mappings → {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
