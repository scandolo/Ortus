#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Renders background.html to background.png (600x340) and background@2x.png (1200x680)
# with headless Chrome. The images are committed, so this only runs when the design
# changes. Override the browser with CHROME=/path/to/chrome.
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}

render() { # <scale> <out>
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --force-device-scale-factor="$1" --window-size=600,340 \
        --virtual-time-budget=2000 --screenshot="$PWD/$2" "file://$PWD/background.html" >/dev/null 2>&1
}
render 1 background.png
render 2 background@2x.png
sips -g pixelWidth -g pixelHeight background.png background@2x.png | grep -E "png|pixel"
