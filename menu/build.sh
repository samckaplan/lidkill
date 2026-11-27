#!/bin/bash
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
output="${1:?app bundle output path required}"
mkdir -p "$(dirname "$output")"
stage="$(mktemp -d "$(dirname "$output")/.lidkill-menu.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
contents="$stage/Lidkill.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp -X "$src/Info.plist" "$contents/Info.plist"
cp -X "$src/Lidkill.png" "$contents/Resources/Lidkill.png"

# Terminal scripts for the password prompts: arm, arm for a while, disarm.
for entry in "on:on" "off:off" "on-1h:on --for 1h" "on-4h:on --for 4h" "on-8h:on --for 8h"; do
    printf '#!/bin/bash\nexec "$HOME/.local/bin/lidkill" %s\n' "${entry#*:}" \
        >"$contents/Resources/${entry%%:*}.command"
    chmod 0755 "$contents/Resources/${entry%%:*}.command"
done

/usr/bin/xcrun --sdk macosx swiftc -swift-version 5 -O \
    -target "$(/usr/bin/uname -m)-apple-macos12.0" \
    -module-cache-path "$stage/module-cache" \
    "$src/MenuApp.swift" "$src/MenuBar.swift" "$src/LidPage.swift" -o "$contents/MacOS/Lidkill"
/usr/bin/codesign --sign - "$stage/Lidkill.app"

if [ -e "$output" ]; then mv "$output" "$stage/previous.app"; fi
if ! mv "$stage/Lidkill.app" "$output"; then
    if [ -e "$stage/previous.app" ]; then mv "$stage/previous.app" "$output"; fi
    exit 1
fi
