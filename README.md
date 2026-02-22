<h1 align="center">quickshell-favicon</h1>
<p align="center">
  <img src=".github/preview.png" alt="quickshell-favicon preview">
</p>

<p align="center">
  <video src="https://github.com/user-attachments/assets/dd6ab24f-04b2-4472-95a0-041aed496d44" controls muted width="100%"></video>
</p>

Favicons in your Quickshell bar or dock.

## Why this exists

I get confused when I have 10 browser tabs open in different workspaces.<br>*Is this workspace for YouTube, Zoom, X or random websites? lol.*

PWAs are okay but making one for every site is a bloated solution. This project just guesses what website you're looking at and grabs the icon for you.

## How it works (the magic part)

It uses a few Tiers to make sure you get the right icon:

1. **Official Assets**: Hardcoded icons for stuff like Gmail, Drive, YouTube. 100% accurate. (you can add your own things)
2. **Browser History**: A python script scans your browser history and maps window titles to real URLs.
3. **Regex Fallback**: If history fails, it looks for domain names directly in the window title.
   - *Note: This is where "hallucinations" can happen. If a title is "meeting.notes", the regex might think "notes.com" is the domain. It's not perfect but I think it should be good enough for most cases.*
4. **Local Cache**: If we found a domain in Tier 2 or 3, we download the icon and stash it in `~/.cache/quickshell/favicons` for next time.

*Sometimes it takes a few seconds to fetch the icon for a new website.*

## Dependencies

You're gonna need these to make it work:

- **Quickshell**: Obviously.
- **Any Wayland Compositor**: The core service works anywhere Quickshell does. 
- **Hyprland** (Optional): Only required if you want to run the included `FaviconDock.qml` demo.
- **Python 3**: For digging through your history files.
- **Curl**: To download the icons.
- **Bash**: To run the downloader script.

## How to use

Just clone it and run:

```bash
qs -p /path/to/quickshell-favicon
```

> The included dock (`FaviconDock.qml`) is strictly a **demo** unless you use this as a base.

## Integration

1.  **Copy the folders**: Grab `services/`, `scripts/`, and `assets/` and put them in your project.
2.  **Import**: `import "./services" as Services`
3.  **The Property**: Add this to your bar or dock item. We use `cacheCounter` to make the UI update instantly when a new icon is downloaded!
    ```qml
    readonly property string faviconPath: {
        const _ = Services.FaviconService.cacheCounter; // This logic triggers a refresh
        return Services.FaviconService.getFavicon(toplevel);
    }
    ```
4.  **Display it**:
    ```qml
    Image {
        width: 24; height: 24
        source: faviconPath !== "" ? faviconPath : "your-fallback-icon"
    }
    ```

*Check out `components/FaviconDockItem.qml` for a full example including system icon fallbacks and browser detection.*

## Customize 

### Adding your own Official Assets
If you want to use your own high-quality icons and skip the download process:

1.  **Drop your icon**: Put a `.png` file named exactly after the domain (e.g. `github.com.png`) into a folder. You can use any folder, it doesn't have to be `assets/google/`.
2.  **Define your path** (Optional): In `services/FaviconService.qml`, you can add your own property to point to your new folder:
    ```qml
    readonly property string myIcons: "file://" + shellDir + "/your-custom-folder/"
    ```
3.  **Blacklist the domain**: Add the domain to the `officialDomains` list in `FaviconService.qml`. This tells the service: *"I have this locally, don't try to download it."*
    ```qml
    readonly property var officialDomains: [
        "github.com", "your-other-site.com",
        "mail.google.com", "calendar.google.com", ...
    ]
    ```
4.  **Update the Logic**: In the `getFavicon` function, point the `officialPath` to your new folder:
    ```qml
    const officialPath = root.myIcons + domain + ".png"; // or root.shellDir + "/assets/google/" 
    if (root.officialDomains.includes(domain)) {
         return officialPath;
    }
    ```

### Changing the Cache Folder
By default, downloaded icons and search maps are stored in `~/.cache/quickshell/favicons`. If you want to move this:

1.  **In `services/FaviconService.qml`**: Update the `rawCacheDir` property.
2.  **In `scripts/favicons/favicon_bridge.py`**: Update the `cache_dir` variable (at the bottom of the file).

> Make sure both paths match exactly, otherwise the service won't be able to find the icons the python script downloads!

## The Downsides (Cons)

Nothing is perfect! Here is why you might NOT want this:

- **Delayed**: It can take a few seconds to fetch an icon for a new website. It's not instant because it has to wait for history to sync.
- **Title Based**: It relies on window titles. If a website has a weird title that doesn't include the name or domain, it might fail or show a generic icon.
- **Local Cache**: Icons are stored doesn't auto-delete.
  - *Note: On startup, the service automatically purges broken, empty or placeholder icons to keep the data clean, but it won't delete old icons just because they are old. You can wipe this folder safely anytime.*

## Contributing & Testing

This has been primarily tested on **Google Chrome**, **Brave**, and **Firefox**. 
If you use other browsers (Edge, Vivaldi, Opera, etc.) or have improvements to the logic, **PRs are highly encouraged!**