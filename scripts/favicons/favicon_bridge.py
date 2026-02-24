import sqlite3
import os
import json
import shutil
import tempfile
from pathlib import Path
import re
import sys
import traceback

"""
You may read this script to understand how it works
while it is not priority to understand this script
since this just going to blast your browser history to a json file
and the FaviconService.qml is going to do the heavy lifting
"""

def get_browser_history_paths():
    """Finds where your browsers hide their history files."""
    home = str(Path.home())
    paths = []
    
    # Common places where browsers live
    bases = [
        os.path.join(home, ".config"),
        os.path.join(home, ".mozilla"),
        os.path.join(home, "snap"),
        os.path.join(home, ".var/app")
    ]
    
    for base in bases:
        if not os.path.exists(base):
            continue
            
        for root, dirs, files in os.walk(base):
            # Chromium-based (Chrome, Brave, Edge, etc.)
            if "History" in files:
                p = os.path.join(root, "History")
                parent = root.lower()
                if any(x in parent for x in ["chrome", "brave", "chromium", "edge", "vivaldi", "thorium", "opera", "yandex"]):
                    paths.append(("chromium", p))
            
            # Firefox-based (Firefox, Zen, Librewolf, etc.)
            if "places.sqlite" in files:
                p = os.path.join(root, "places.sqlite")
                parent = root.lower()
                if any(x in parent for x in ["firefox", "mozilla", "zen", "floorp", "waterfox", "librewolf"]):
                    paths.append(("firefox", p))
                    
            # Speed boost: Don't dig too deep into random folders
            if len(root.split(os.sep)) - len(base.split(os.sep)) > 5:
                del dirs[:]

    return list(set(paths))

# We need to strip browser names from titles so they match what QML's FaviconService expects
BROWSER_SUFFIX = re.compile(
    r"\s*[-|—|·]\s*(Mozilla Firefox|Brave|Google Chrome|Chromium|Vivaldi|Edge|"
    r"Zen|Floorp|LibreWolf|Thorium|Waterfox|Mullvad|Tor Browser|"
    r"Chrome|Firefox|Web Browser|Browser|Quickshell|Antigravity)\s*$",
    re.IGNORECASE
)

# Strips unread/notification counters that apps prepend to titles.
# e.g. "(3) Final Exam Discussion" -> "Final Exam Discussion"
# e.g. "* Editing: notes.md" -> "Editing: notes.md"
NOISE_PREFIX = re.compile(r"^\s*[\[(]\d+[\])]\s*|^\s*\*\s*")

def clean_title(raw_title):
    """Turns 'YouTube - Mozilla Firefox' into just 'YouTube'."""
    if not raw_title:
        return None
    clean = BROWSER_SUFFIX.sub("", raw_title).strip()
    return clean if clean else None

def normalize_title(title):
    """Strips dynamic noise prefixes. '(1) Meeting' -> 'Meeting'."""
    if not title:
        return title
    return NOISE_PREFIX.sub("", title).strip()

def extract_exact_mappings():
    """The heavy lifting: mapping your window titles to actual URLs from your history."""
    title_to_url = {}
    history_paths = get_browser_history_paths()
    
    if not history_paths:
        return title_to_url

    for db_type, path in history_paths:
        tmp_path = None
        try:
            # We copy the database to a temp file so we don't lock your browser if it's open
            with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as tmp:
                tmp_path = tmp.name
            shutil.copy2(path, tmp_path)
            
            # Firefox is picky and needs its sidecar files to read the latest data
            for sidecar_suffix in ["-wal", "-shm"]:
                sidecar_path = path + sidecar_suffix
                if os.path.exists(sidecar_path):
                    shutil.copy2(sidecar_path, tmp_path + sidecar_suffix)
            
            # Open the temp database
            conn = sqlite3.connect(f"file:{tmp_path}?mode=ro", uri=True)
            cursor = conn.cursor()
            
            # Grab the last 5000 sites you visited
            if db_type == "chromium":
                cursor.execute("SELECT title, url FROM urls ORDER BY last_visit_time DESC LIMIT 5000")
            else:
                cursor.execute("SELECT title, url FROM moz_places WHERE title IS NOT NULL ORDER BY last_visit_date DESC LIMIT 5000")
            
            rows = cursor.fetchall()
            
            for title, url in rows:
                cleaned = clean_title(title)
                if cleaned and cleaned not in title_to_url:
                    title_to_url[cleaned] = url
                # Also store the normalized version so FaviconService can
                # fuzzy-match even if page titles have changed slightly
                normalized = normalize_title(cleaned) if cleaned else None
                if normalized and normalized != cleaned and normalized not in title_to_url:
                    title_to_url[normalized] = url
            
            conn.close()
            
        except Exception as e:
            # If something breaks, we'll see it in the terminal
            traceback.print_exc(file=sys.stderr)
        finally:
            # Clean up our temp files so we don't leave a mess behind
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                    for sidecar_suffix in ["-wal", "-shm"]:
                        sidecar_to_rm = tmp_path + sidecar_suffix
                        if os.path.exists(sidecar_to_rm):
                            os.unlink(sidecar_to_rm)
                except:
                    pass

    return title_to_url

if __name__ == "__main__":
    # Extraction brrrr
    mappings = extract_exact_mappings()
    
    # If you changed the cache directory in FaviconService.qml, change it here too
    cache_dir = os.path.expanduser("~/.cache/quickshell/favicons")
    os.makedirs(cache_dir, exist_ok=True)
    
    out_path = os.path.join(cache_dir, "exact_title_to_url.json")
    with open(out_path, "w") as f:
        json.dump(mappings, f, indent=2)
