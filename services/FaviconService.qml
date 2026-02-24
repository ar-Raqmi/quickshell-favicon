pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import QtCore

Singleton {
    id: root
    
    // ─── Where things live ───────────────────────────
    readonly property string homeDir: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "").replace(/\/$/, "")
    // Update this if you want to cache icons somewhere else (CHANGE IN favicon_bridge.py TOO!)
    readonly property string rawCacheDir: homeDir + "/.cache/quickshell/favicons"
    // We use Qt.resolvedUrl so we don't have to worry about where the project is moved
    readonly property string shellDir: Qt.resolvedUrl("..").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string bridgePath: rawCacheDir + "/exact_title_to_url.json"
    
    Component.onCompleted: {
        loadBridge();    // Load what we already know
        startupScan();   // See what icons we already have in cache
        triggerBridge(); // Go grab the latest browser history
        
        // Keep the browser history fresh so new tabs get icons quickly
        bridgeRefreshTimer.running = true;
    }
    
    Timer {
        id: bridgeRefreshTimer
        interval: 5000 // Refresh every 5 seconds. Change this if you feel it making your memory usage go up.
        repeat: true
        onTriggered: {
            triggerBridge();
            
            // Self-healing: If a download gets stuck, clear it after 40 seconds
            const now = Date.now();
            let newDown = Object.assign({}, root.downloading);
            let changed = false;
            for (const d in newDown) {
                if (now - newDown[d] > 40000) { delete newDown[d]; changed = true; }
            }
            if (changed) root.downloading = newDown;
            
            // Give failed domains another chance after 30 seconds
            let newFailed = Object.assign({}, root.failedDomains);
            let failChanged = false;
            for (const d in newFailed) {
                if (now - newFailed[d] > 30000) { delete newFailed[d]; failChanged = true; }
            }
            if (failChanged) root.failedDomains = newFailed;
        }
    }
    
    property var readyDomains: ({})  // The "I have this icon" list
    property var urlMap: ({})        // The "This title = This URL" dictionary
    property var downloading: ({})   // Keep track of what we're currently fetching
    property var failedDomains: ({}) // Let's not bang our head against a wall if a site is down
    property int cacheCounter: 0     // A little poke to tell the UI to refresh
 
    signal faviconDownloaded(string domain)

    /**
     * This is the brain. It figures out what icon goes with which window.
     * 1. Normalize title (strip unread counters like "(3) ", "* ")
     * 2. Exact history match ("YouTube" -> youtube.com from your browser history)
     * 3. Fuzzy history match ("(1) Final Exam" matches "Final Exam" -> zoom.us)
     * 4. Brand name map ("Teams" -> teams.microsoft.com, "Zoom" -> zoom.us etc.)
     * 5. Domain regex (looks for things like "github.com" in the title itself)
     * 6. Fallback Google-service keyword map
     * If we've got a domain but no icon yet -> kick off a download!
     */
    function getFavicon(window) {
        if (!window || !window.title) return "";
        
        const title = window.title;
        const cleanRef = cleanTitle(title);
        const normRef = normalizeTitle(cleanRef);
        
        // Tier 1: Look at the browser history we scanned earlier (Best accuracy!)
        let fullUrl = root.urlMap[cleanRef];
        let domain = "";
        
        if (fullUrl) {
            domain = extractDomain(fullUrl);
        }

        // Tier 2: Fuzzy history lookup - handles dynamic titles like "(3) Final Exam"
        // that were recorded as "Final Exam" in history
        if (!domain) {
            const normKeys = Object.keys(root.urlMap);
            for (let i = 0; i < normKeys.length; i++) {
                const key = normKeys[i];
                const normKey = normalizeTitle(key);
                // Title contains the history key, or vice versa (minimum 5 chars to avoid noise)
                if (normKey.length >= 5 && (normRef.includes(normKey) || normKey.includes(normRef))) {
                    fullUrl = root.urlMap[key];
                    domain = extractDomain(fullUrl);
                    break;
                }
            }
        }
        
        // Tier 3: Brand name map - catches "Teams", "Zoom", "Slack" etc.
        // I'm too lazy, this is completly Gemini-generated
        if (!domain) {
            const brandMap = {
                // --- Microsoft ---
                "microsoft teams": "teams.microsoft.com",
                "teams":           "teams.microsoft.com",
                // --- Conferencing ---
                "zoom":            "zoom.us",
                "google meet":     "meet.google.com",
                "meet":            "meet.google.com",
                "webex":           "webex.com",
                "gotomeeting":     "gotomeeting.com",
                // --- Comms & Productivity ---
                "slack":           "slack.com",
                "discord":         "discord.com",
                "telegram":        "web.telegram.org",
                "whatsapp":        "web.whatsapp.com",
                "notion":          "notion.so",
                "trello":          "trello.com",
                "linear":          "linear.app",
                "jira":            "jira.atlassian.com",
                "confluence":      "confluence.atlassian.com",
                "figma":           "figma.com",
                "miro":            "miro.com",
                // --- Google ---
                "gmail":           "mail.google.com",
                "google calendar": "calendar.google.com",
                "google drive":    "drive.google.com",
                "google docs":     "docs.google.com",
                "google sheets":   "sheets.google.com",
                "google slides":   "slides.google.com",
                "google meet":     "meet.google.com",
                "google maps":     "maps.google.com",
                "gemini":          "gemini.google.com",
                "youtube":         "youtube.com",
                "google ai studio":"aistudio.google.com",
                "notebooklm":      "notebooklm.google.com",
                "google photos":   "photos.google.com",
            };

            const lowerTitle = normRef.toLowerCase();
            // Sort by key length descending so "microsoft teams" beats "teams"
            const brandKeys = Object.keys(brandMap).sort((a, b) => b.length - a.length);
            for (const kw of brandKeys) {
                if (lowerTitle.includes(kw)) {
                    domain = brandMap[kw];
                    break;
                }
            }
        }

        // Tier 4: Try to extract a domain directly from the title (e.g. "github.com · Pull Request")
        if (!domain) {
            domain = extractDomainFromTitle(cleanRef);
        }

        if (!domain) return "";

        // Canonical alias cleanup
        if (domain === "gmail.com") domain = "mail.google.com";
        if (domain === "gemini.ai") domain = "gemini.google.com";
        if (domain === "google.com") domain = ""; // generic G, not useful
        if (!domain) return "";
        
        // Priority 1: Do we have it cached already?
        if (readyDomains[domain]) {
            const ext = readyDomains[domain + "_svg"] ? ".svg" : ".png";
            return "file://" + rawCacheDir + "/" + domain + ext;
        }
        
        // Priority 2: If we have a domain but no icon, go pull it from the web
        if (!downloading[domain] && !failedDomains[domain]) {
            downloadFavicon(domain, fullUrl);
        }

        // Bonus: If it's a subdomain, try the main domain icon (e.g. blog.github.com -> github.com)
        const parts = domain.split(".");
        if (parts.length > 2) {
            const parent = parts.slice(-2).join(".");
            if (parent !== domain && readyDomains[parent]) {
                const parentExt = readyDomains[parent + "_svg"] ? ".svg" : ".png";
                return "file://" + rawCacheDir + "/" + parent + parentExt;
            }
        }
        
        return "";
    }

    // Strip browser names and clutter from window titles
    function cleanTitle(title) {
        if (!title) return "";
        return title.replace(/\s*[-|—|·]\s*(Mozilla Firefox|Brave|Google Chrome|Chromium|Vivaldi|Edge|Zen|Floorp|LibreWolf|Thorium|Waterfox|Mullvad|Tor Browser|Chrome|Firefox|Web Browser|Browser|Quickshell|Antigravity)\s*$/i, "").trim();
    }

    // Strips dynamic noise that apps add to titles:
    // "(3) Final Exam" -> "Final Exam"
    // "* Editing: notes" -> "Editing: notes"
    // "[2] Chat room" -> "Chat room"
    function normalizeTitle(title) {
        if (!title) return "";
        return title
            .replace(/^\s*[\[(]\d+[\])]\s*/g, "") // leading (3) or [3]
            .replace(/^\s*\*\s*/g, "")             // leading *
            .trim();
    }

    // Grab "teams.microsoft.com" from "https://teams.microsoft.com/page"
    function extractDomain(url) {
        if (!url) return "";
        const match = url.match(/https?:\/\/(?:www\.)?([^\/]+)/i);
        return match ? match[1].toLowerCase() : "";
    }

    // Look for things like "github.com" or "user/repo" in a title
    function extractDomainFromTitle(cleanTitle) {
        // Special case for GitHub "user/repo" style titles
        // In Brave, it will show "user/repo" in the title only. I don't know why
        if (/^[\w][\w.-]*\/[\w][\w.-]+([\s:]|$)/.test(cleanTitle)) {
            return "github.com";
        }
        
        // Upgraded regex: now correctly handles subdomains like "teams.microsoft.com"
        // Groups: (subdomain.parts.)? (second-level) . (tld)
        const domainMatch = cleanTitle.match(
            /(?:https?:\/\/)?(?:www\.)?((?:[a-z0-9-]{2,}\.)+)?([a-z0-9-]{2,})\.(com|net|org|edu|gov|io|co|us|uk|de|fr|jp|au|ca|app|dev|ai|me|ly|so|icu|xyz|top|info|site|online|land|nz)/i
        );
        if (domainMatch) {
            const prefix = domainMatch[1] || "";
            return (prefix + domainMatch[2] + "." + domainMatch[3]).toLowerCase();
        }
        return "";
    }

    // Start the background process to download an icon
    function downloadFavicon(domain, scrapeUrl) {
        if (downloading[domain]) return;
        let newDown = Object.assign({}, root.downloading);
        newDown[domain] = Date.now();
        root.downloading = newDown;
        
        const scriptPath = shellDir + "/scripts/favicons/download_favicon.sh"; // You may change as the way you want
        const targetUrl = scrapeUrl || "";
        
        const download = downloadProcess.createObject(null, {
            command: ["bash", scriptPath, domain, rawCacheDir, targetUrl]
        });
        
        download.onExited.connect((exitCode, exitStatus) => {
            if (exitCode === 0) {
                updateReady(domain);
            } else {
                let newDown = Object.assign({}, root.downloading);
                delete newDown[domain];
                root.downloading = newDown;
                let newFailed = Object.assign({}, root.failedDomains);
                newFailed[domain] = Date.now();
                root.failedDomains = newFailed;
            }
            download.destroy();
        });
        download.running = true;
    }

    // Check what format we got (PNG vs SVG) and update the list
    function updateReady(domain) {
        const checkSvg = checkProcess.createObject(null, {
            command: ["bash", "-c", `[ -f "${rawCacheDir}/${domain}.svg" ] && echo svg || echo png`]
        });
        checkSvg.stdout.onStreamFinished.connect(() => {
            const format = checkSvg.stdout.text.trim();
            let newReady = Object.assign({}, root.readyDomains);
            newReady[domain] = true;
            if (format === "svg") {
                newReady[domain + "_svg"] = true;
            }
            root.readyDomains = newReady;
            
            let newDown = Object.assign({}, root.downloading);
            delete newDown[domain];
            root.downloading = newDown;
            
            root.cacheCounter++; // Poke!
            root.faviconDownloaded(domain);
            checkSvg.destroy();
        });
        checkSvg.running = true;
    }

    // Read the title->URL map file generated by the Python script
    function loadBridge() {
        if (bridgePath === "") return;
        const check = checkProcess.createObject(null, {
            command: ["bash", "-c", `[ -f "${bridgePath}" ] && echo yes || echo no`]
        });
        check.stdout.onStreamFinished.connect(() => {
            if (check.stdout.text.trim() !== "yes") {
                check.destroy();
                return;
            }
            const reader = readFileProcess.createObject(null, {
                path: bridgePath
            });
            reader.onTextChanged.connect(() => {
                try {
                    const raw = reader.text();
                    root.urlMap = JSON.parse(raw);
                } catch(e) {}
            });
            check.destroy();
        });
        check.running = true;
    }

    // Clean up old crap and see what's currently in the cache
    function startupScan() {
        const cleanup = cleanupProcess.createObject(null, {
            command: ["bash", "-c", `find "${rawCacheDir}" -name "*.png" -not -name ".tmp_*" -type f | while read f; do head -c 5 "$f" | grep -qiE "^(<svg|<\\?xml)" && rm -f "$f" && continue; fsize=$(stat -c%s "$f" 2>/dev/null || echo 0); [ "$fsize" -le 400 ] && rm -f "$f"; done`]
        });
        cleanup.onExited.connect(() => {
            const scan = scanProcess.createObject(null, {
                command: ["bash", "-c", `ls "${rawCacheDir}" 2>/dev/null`]
            });
            scan.stdout.onStreamFinished.connect(() => {
                const output = scan.stdout.text.trim();
                if (!output) return;
                
                const lines = output.split("\n");
                let temp = {};
                for (const line of lines) {
                    const f = line.trim();
                    if (!f) continue;
                    
                    if (f.endsWith(".png") && f.length > 4) {
                        const domain = f.replace(".png", "");
                        temp[domain] = true;
                    } else if (f.endsWith(".svg") && f.length > 4) {
                        const domain = f.replace(".svg", "");
                        temp[domain] = true;
                        temp[domain + "_svg"] = true; 
                    }
                }
                root.readyDomains = temp;
                root.cacheCounter++;
            });
            scan.running = true;
        });
        cleanup.running = true;
    }

    // Fire off the Python script to scan browser history
    function triggerBridge() {
        const bridge = bridgeProcess.createObject(null, {
            command: ["python3", shellDir + "/scripts/favicons/favicon_bridge.py"] // Change this directory also if you did change the download_favicon.sh directory to make things organized
        });
        bridge.onExited.connect(() => {
            loadBridge();
        });
        bridge.running = true;
    }

    Component { id: downloadProcess; Process { stdout: StdioCollector {} } }
    Component { id: scanProcess; Process { stdout: StdioCollector {} } }
    Component { id: cleanupProcess; Process {} }
    Component { id: bridgeProcess; Process {} }
    Component { id: checkProcess; Process { stdout: StdioCollector {} } }
    Component { id: readFileProcess; FileView {} }
}
