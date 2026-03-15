#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# Favicon Downloader
# Fetches the best possible favicon for a domain and caches it.
#
# Usage:
#   download_favicon.sh <domain> <cache_dir> [scrape_url]
#
# Exit codes:
#   0 = success
#   1 = failed to fetch icon
# ────────────────────────────────────────────────────────────────

set -euo pipefail

DOMAIN="${1:-}"
CACHE_DIR="${2:-}"
SCRAPE_URL="${3:-}"

[ -z "$DOMAIN" ] && exit 1
[ -z "$CACHE_DIR" ] && exit 1

FINAL_PNG="${CACHE_DIR}/${DOMAIN}.png"
FINAL_SVG="${CACHE_DIR}/${DOMAIN}.svg"

mkdir -p "$CACHE_DIR"

# Already cached
[[ -f "$FINAL_PNG" || -f "$FINAL_SVG" ]] && exit 0

TMP_BASE=$(mktemp -p "$CACHE_DIR" ".tmp_${DOMAIN}_XXXX")

cleanup() {
    rm -f "${TMP_BASE}".*
}
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────
# Curl helper
# ────────────────────────────────────────────────────────────────

fetch() {
    curl -k -f -L -s --max-time 10 "$1" -o "$2" 2>/dev/null
}

# ────────────────────────────────────────────────────────────────
# Validators
# ────────────────────────────────────────────────────────────────

validate_png() {

    local f="$1"
    [[ ! -f "$f" ]] && return 1

    local size
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)

    (( size < 400 )) && return 1

    head -c 15 "$f" | grep -qiE "(^<!|^<html|^HTTP)" && return 1

    return 0
}

validate_svg() {

    local f="$1"
    [[ ! -f "$f" ]] && return 1

    local size
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)

    (( size < 50 )) && return 1

    head -c 10 "$f" | grep -qiE "^(<svg|<\?xml)" || return 1

    return 0
}

save_if_valid() {

    local src="$1"

    if validate_svg "$src"; then
        mv "$src" "$FINAL_SVG"
        exit 0
    fi

    if validate_png "$src"; then
        mv "$src" "$FINAL_PNG"
        exit 0
    fi

    return 1
}

# ────────────────────────────────────────────────────────────────
# Hardcoded Google Icons
# ────────────────────────────────────────────────────────────────

google_asset() {

    case "$DOMAIN" in
        mail.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/gmail_2020q4/v11/192px.svg"
        ;;
        calendar.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/calendar_2020q4/v13/192px.svg"
        ;;
        drive.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/drive_2020q4/v10/192px.svg"
        ;;
        docs.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/docs_2020q4/v12/192px.svg"
        ;;
        sheets.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/sheets_2020q4/v11/192px.svg"
        ;;
        slides.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/slides_2020q4/v12/192px.svg"
        ;;
        notebooklm.google.com)
            echo "https://www.gstatic.com/images/branding/productlogos/notebooklm/v1/192px.svg"
        ;;
    esac
}

if url=$(google_asset); then
    fetch "$url" "${TMP_BASE}.svg" && save_if_valid "${TMP_BASE}.svg"
fi

# ────────────────────────────────────────────────────────────────
# Source 1: Google S2 API
# ────────────────────────────────────────────────────────────────

fetch "https://www.google.com/s2/favicons?domain=${DOMAIN}&sz=128" "${TMP_BASE}.png"

if validate_png "${TMP_BASE}.png"; then

    size=$(stat -c%s "${TMP_BASE}.png")

    # Skip Google's generic globe icons
    if [[ "$size" != "1215" && "$size" != "529" ]]; then
        mv "${TMP_BASE}.png" "$FINAL_PNG"
        exit 0
    fi
fi

# ────────────────────────────────────────────────────────────────
# Source 2: Vemetric API
# ────────────────────────────────────────────────────────────────

fetch "https://favicon.vemetric.com/${DOMAIN}?size=128" "${TMP_BASE}.raw"

if [[ -f "${TMP_BASE}.raw" ]]; then

    if head -c 10 "${TMP_BASE}.raw" | grep -qiE "^(<svg|<\?xml)"; then

        if ! grep -qE "(world-question|icon-tabler-globe)" "${TMP_BASE}.raw"; then
            mv "${TMP_BASE}.raw" "${TMP_BASE}.svg"
            save_if_valid "${TMP_BASE}.svg"
        fi

    else
        mv "${TMP_BASE}.raw" "${TMP_BASE}.png"
        save_if_valid "${TMP_BASE}.png"
    fi
fi

# ────────────────────────────────────────────────────────────────
# Source 3: HTML Scraping
# ────────────────────────────────────────────────────────────────

TARGET_URL="${SCRAPE_URL:-https://${DOMAIN}}"

html=$(curl -k -f -L -s --max-time 10 "$TARGET_URL" 2>/dev/null || true)

icon=$(printf "%s" "$html" | python3 - <<'PY'
import sys
from html.parser import HTMLParser

class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.apple=None
        self.icon=None

    def handle_starttag(self, tag, attrs):
        if tag!="link":
            return
        d=dict(attrs)
        rel=d.get("rel","").lower()
        href=d.get("href")
        if not href:
            return
        if "apple-touch-icon" in rel:
            self.apple=href
        elif "icon" in rel:
            self.icon=href

p=P()
p.feed(sys.stdin.read())
print(p.apple or p.icon or "")
PY
)

if [[ -n "$icon" ]]; then

    case "$icon" in
        http*) url="$icon" ;;
        //*) url="https:$icon" ;;
        /*) url="https://${DOMAIN}$icon" ;;
        *) url="${TARGET_URL%/}/$icon" ;;
    esac

    fetch "$url" "${TMP_BASE}.raw"

    if [[ -f "${TMP_BASE}.raw" ]]; then
        save_if_valid "${TMP_BASE}.raw"
    fi
fi

# ────────────────────────────────────────────────────────────────
# Source 4: /favicon.ico
# ────────────────────────────────────────────────────────────────

fetch "https://${DOMAIN}/favicon.ico" "${TMP_BASE}.png"

validate_png "${TMP_BASE}.png" && mv "${TMP_BASE}.png" "$FINAL_PNG" && exit 0

exit 1#!/bin/bash
# ─── Favicon Downloader ──────────────────────────────────────────
# This script goes out and grabs the icon for a domain.
# Usage: download_favicon.sh <domain> <cache_dir> <scrape_url>
# Exit 0 means we got it, Exit 1 means we failed.
# ─────────────────────────────────────────────────────────────────

DOMAIN="$1"      # e.g. "google.com"
CACHE_DIR="$2"   # where we store the icons
SCRAPE_URL="$3"  # (optional) if we have the full URL, we can dig deeper

FINAL_PATH="${CACHE_DIR}/${DOMAIN}.png"
FINAL_SVG="${CACHE_DIR}/${DOMAIN}.svg"
TMP_PATH="${CACHE_DIR}/.tmp_${DOMAIN}"

mkdir -p "$CACHE_DIR"

# If we already have it, we're done here!
[ -f "$FINAL_PATH" ] && exit 0
[ -f "$FINAL_SVG" ] && exit 0

# Checks if the image is actually a valid PNG and not just an error page
validate_png() {
    local f="${TMP_PATH}.png"
    [ ! -f "$f" ] && return 1
    
    # Files too small are usually broken
    fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$fsize" -le 400 ] && rm -f "$f" && return 1
    
    # If it starts with HTML tags, it's a "Not Found" page disguised as an icon
    head -c 15 "$f" | grep -qiE "(^<!|^<html|^HTTP)" && rm -f "$f" && return 1
    return 0
}

# Checks if the SVG is legit
validate_svg() {
    local f="${TMP_PATH}.svg"
    [ ! -f "$f" ] && return 1
    
    # SVGs need to be at least a little bit big
    fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$fsize" -le 50 ] && rm -f "$f" && return 1
    
    # Must start with the right tags
    head -c 10 "$f" | grep -qiE "^(<svg|<\?xml)" || { rm -f "$f"; return 1; }
    return 0
}

# ─── Hardcoded Google Assets ─────────────────────────────────────
# We hardcode some mainstream Google sites so they never stray away
# from their official high-resolution branding
# this because sometime it fallback to random "G" icon
HQ_URL=""
case "$DOMAIN" in
    "mail.google.com")      HQ_URL="https://www.gstatic.com/images/branding/productlogos/gmail_2020q4/v11/192px.svg" ;;
    "calendar.google.com")  HQ_URL="https://www.gstatic.com/images/branding/productlogos/calendar_2020q4/v13/192px.svg" ;;
    "drive.google.com")     HQ_URL="https://www.gstatic.com/images/branding/productlogos/drive_2020q4/v10/192px.svg" ;;
    "docs.google.com")      HQ_URL="https://www.gstatic.com/images/branding/productlogos/docs_2020q4/v12/192px.svg" ;;
    "sheets.google.com")    HQ_URL="https://www.gstatic.com/images/branding/productlogos/sheets_2020q4/v11/192px.svg" ;;
    "slides.google.com")    HQ_URL="https://www.gstatic.com/images/branding/productlogos/slides_2020q4/v12/192px.svg" ;;
    "notebooklm.google.com") HQ_URL="https://www.gstatic.com/images/branding/productlogos/notebooklm/v1/192px.svg" ;;
esac

if [ -n "$HQ_URL" ]; then
    curl -f -L -s --max-time 10 "$HQ_URL" -o "${TMP_PATH}.svg" 2>/dev/null
    validate_svg && mv "${TMP_PATH}.svg" "$FINAL_SVG" && exit 0
    rm -f "${TMP_PATH}.svg"
fi

# ─── Source 1: Google's s2 Favicon API ───────────────────────────
# Super fast and covers 99% (made up number) of the web
curl -f -L -s --max-time 10 "https://www.google.com/s2/favicons?domain=${DOMAIN}&sz=128" -o "${TMP_PATH}.png" 2>/dev/null
if validate_png; then
    # Google likes to return a generic "globe" if it doesn't know the site.
    # We'd rather keep digging for a real icon if that happens.
    fsize=$(stat -c%s "${TMP_PATH}.png")
    if [ "$fsize" -ne 1215 ] && [ "$fsize" -ne 529 ]; then
        mv "${TMP_PATH}.png" "$FINAL_PATH" && exit 0
    fi
    rm -f "${TMP_PATH}.png"
fi

# ─── Source 2: Vemetric API ──────────────────────────────────────
# A great fallback that often has high-res SVGs
curl -f -L -s --max-time 10 "https://favicon.vemetric.com/${DOMAIN}?size=128" -o "${TMP_PATH}.raw" 2>/dev/null
if [ -f "${TMP_PATH}.raw" ]; then
    if head -c 10 "${TMP_PATH}.raw" | grep -qiE "^(<svg|<\?xml)"; then
        # Check if it's their generic "I don't know" icon
        if grep -qE "(world-question|icon-tabler-world|icon-tabler-globe|potrace)" "${TMP_PATH}.raw" 2>/dev/null; then
            rm -f "${TMP_PATH}.raw"
        else
            mv "${TMP_PATH}.raw" "${TMP_PATH}.svg"
            validate_svg && mv "${TMP_PATH}.svg" "$FINAL_SVG" && exit 0
            rm -f "${TMP_PATH}.svg"
        fi
    else
        mv "${TMP_PATH}.raw" "${TMP_PATH}.png"
        validate_png && mv "${TMP_PATH}.png" "$FINAL_PATH" && exit 0
        rm -f "${TMP_PATH}.png"
    fi
fi

# ─── Source 3: Digging through the page HTML ─────────────────────
# We look for <link rel="icon"...> tags
TARGET_URL="${SCRAPE_URL:-https://${DOMAIN}}"
html_icon=$(curl -k -f -L -s --max-time 10 "$TARGET_URL" 2>/dev/null | python3 -c "
import sys
from html.parser import HTMLParser

class IconParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.best_icon = None
        self.apple_icon = None
        
    def handle_starttag(self, tag, attrs):
        if tag == 'link':
            attrs_dict = dict(attrs)
            rel = attrs_dict.get('rel', '').lower()
            href = attrs_dict.get('href', '')
            if not href:
                return
                
            if 'mask-icon' in rel:
                return

            if 'apple-touch-icon' in rel:
                self.apple_icon = href
            elif 'icon' in rel or 'shortcut icon' in rel:
                self.best_icon = href

parser = IconParser()
try:
    parser.feed(sys.stdin.read())
except Exception:
    pass

icon = parser.best_icon or parser.apple_icon
if icon:
    print(icon.strip())
else:
    sys.exit(1)
" 2>/dev/null)

if [ -n "$html_icon" ]; then
    # Fix paths if they are relative (e.g. /favicon.png or portalassets/... can't they just be normal?)
    case "$html_icon" in
        http*) icon_url="$html_icon" ;;
        //*) icon_url="https:$html_icon" ;;
        /*) icon_url="https://${DOMAIN}$html_icon" ;;
        *) icon_url="${TARGET_URL%/}/${html_icon}" ;;
    esac
    
    curl -k -f -L -s --max-time 10 "$icon_url" -o "${TMP_PATH}.raw" 2>/dev/null
    if [ -f "${TMP_PATH}.raw" ]; then
        if head -c 10 "${TMP_PATH}.raw" | grep -qiE "^(<svg|<\?xml)"; then
            mv "${TMP_PATH}.raw" "${TMP_PATH}.svg"
            validate_svg && mv "${TMP_PATH}.svg" "$FINAL_SVG" && exit 0
        else
            mv "${TMP_PATH}.raw" "${TMP_PATH}.png"
            validate_png && mv "${TMP_PATH}.png" "$FINAL_PATH" && exit 0
        fi
    fi
fi

# ─── Source 3: Direct /favicon.ico guess ─────────────────────────
# One of the reason why we didn't prioritize this first because some stupid random website have a totally different favicon.ico in this path
curl -k -f -L -s --max-time 10 "https://${DOMAIN}/favicon.ico" -o "${TMP_PATH}.png" 2>/dev/null && validate_png && mv "${TMP_PATH}.png" "$FINAL_PATH" && exit 0

# Clean up any leftover mess if we failed
rm -f "${TMP_PATH}.raw" "${TMP_PATH}.png" "${TMP_PATH}.svg"
# ─── Final Failsafe ─────────────────────────────────────────────

# If nothing worked, generate a simple placeholder icon
if [ ! -f "$FINAL_PNG" ] && [ ! -f "$FINAL_SVG" ]; then
    echo "⚠ Failed to fetch favicon for $DOMAIN" >&2

    if command -v convert >/dev/null 2>&1; then
        # Create a small placeholder icon using ImageMagick
        convert -size 128x128 xc:"#dddddd" \
            -gravity center \
            -fill "#444444" \
            -pointsize 48 \
            -annotate 0 "${DOMAIN:0:1}" \
            "$FINAL_PNG"
        exit 0
    else
        # Ultra-safe fallback
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
        <rect width="128" height="128" fill="#dddddd"/>
        <text x="50%%" y="50%%" dominant-baseline="middle" text-anchor="middle"
        font-size="48" fill="#444444">%s</text></svg>' "${DOMAIN:0:1}" > "$FINAL_SVG"
        exit 0
    fi
fi

