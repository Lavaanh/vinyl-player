#!/bin/bash
set -e
cd "$(dirname "$0")"
FLAG="$HOME/.cache/vinyl-visible"
mkdir -p ~/.local/bin ~/.cache ~/.config/plasma-workspace/env
install -m 755 vinyl-toggle ~/.local/bin/vinyl-toggle
echo 'export QML_XHR_ALLOW_FILE_READ=1' > ~/.config/plasma-workspace/env/vinyl.sh
echo 0 > "$FLAG"
tmp=$(mktemp -d)
cp -r package/. "$tmp/"
sed -i "s|__FLAG_FILE__|$FLAG|g" "$tmp/contents/ui/main.qml"
kpackagetool6 --type Plasma/Applet --upgrade "$tmp" 2>/dev/null || kpackagetool6 --type Plasma/Applet --install "$tmp"
rm -rf "$tmp"
echo "Done. LOG OUT AND BACK IN (needed once), then add 'Vinyl Player' from the widget list."
echo "Bind ~/.local/bin/vinyl-toggle to a key in System Settings > Keyboard > Shortcuts > Add New > Command or Script."
