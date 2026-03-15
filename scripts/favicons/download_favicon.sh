#!/bin/bash
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
exit 1
