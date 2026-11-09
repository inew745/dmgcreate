#!/bin/bash
#
# build.sh — compile DMG Creator and assemble "DMG Creator.app".
#
# Run this on a Mac with the Xcode command line tools installed:
#
#     ./build.sh              build the app into ./build
#     ./build.sh --dmg        also package the app into build/DMG-Creator.dmg
#     ./build.sh --install    copy the app into /Applications
#     ./build.sh --run        build and launch it
#
set -eu

cd "$(dirname "$0")"
ROOT="$PWD"

APP_NAME="DMG Creator"
BUNDLE_ID="com.dmgcreate.dmgcreator"
VERSION="1.0.0"
EXECUTABLE="DMGCreator"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

MAKE_DMG=0
INSTALL=0
RUN=0
UNIVERSAL=0
CONFIG="release"
SIGN_IDENTITY="-"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dmg) MAKE_DMG=1; shift ;;
        --install) INSTALL=1; shift ;;
        --run) RUN=1; shift ;;
        --universal) UNIVERSAL=1; shift ;;
        --debug) CONFIG="debug"; shift ;;
        --sign) [ $# -ge 2 ] || die "--sign needs an identity"; SIGN_IDENTITY="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "unknown option '$1'" ;;
    esac
done

# ----------------------------------------------------------------------------
# prerequisites
# ----------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "DMG Creator is a Mac app; build it on macOS."

if ! command -v swift >/dev/null 2>&1; then
    cat >&2 <<'MSG'
ERROR: the Swift compiler was not found.

Install Apple's command line tools and try again:

    xcode-select --install

MSG
    exit 1
fi

# ----------------------------------------------------------------------------
# compile
# ----------------------------------------------------------------------------
step "Compiling ($CONFIG)"
if [ "$UNIVERSAL" -eq 1 ]; then
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
else
    swift build -c "$CONFIG"
fi

case "$CONFIG" in
    release) CONFIG_DIR="Release" ;;
    *) CONFIG_DIR="Debug" ;;
esac

BINARY=""
for candidate in \
    "$ROOT/.build/apple/Products/$CONFIG_DIR/$EXECUTABLE" \
    "$ROOT/.build/$CONFIG/$EXECUTABLE"
do
    [ -f "$candidate" ] && BINARY="$candidate" && break
done
[ -n "$BINARY" ] || BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$EXECUTABLE"
[ -f "$BINARY" ] || die "the compiled binary could not be found."

# ----------------------------------------------------------------------------
# assemble the bundle
# ----------------------------------------------------------------------------
step "Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

# The build engine travels with the app: this is what the GUI runs.
cp "$ROOT/scripts/make-dmg.sh" "$APP_BUNDLE/Contents/Resources/make-dmg.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/make-dmg.sh"

# The background every new project starts with.
cp "$ROOT/assets/default-background.png" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/assets/default-background@2x.png" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>           <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$VERSION</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>DMG Creator asks the Finder to set the background picture, window size and icon positions of the disk image it is building.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>         <string>DMG Creator Project</string>
            <key>CFBundleTypeRole</key>         <string>Editor</string>
            <key>LSHandlerRank</key>            <string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>dmgproj</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# ----------------------------------------------------------------------------
# icon
# ----------------------------------------------------------------------------
if [ -f "$ROOT/assets/appicon.png" ] && command -v iconutil >/dev/null 2>&1; then
    step "Building the app icon"
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"
    do
        px="${spec%% *}"; name="${spec##* }"
        sips -z "$px" "$px" "$ROOT/assets/appicon.png" --out "$ICONSET/$name.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# ----------------------------------------------------------------------------
# sign
# ----------------------------------------------------------------------------
if command -v codesign >/dev/null 2>&1; then
    step "Signing with identity '$SIGN_IDENTITY'"
    # An ad-hoc signature is enough for a locally built app, and it gives the
    # app a stable identity so macOS remembers the Finder automation approval.
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null \
        || printf 'WARNING: the app could not be signed; macOS may ask for Finder permission on every launch.\n' >&2
fi

step "Built $APP_BUNDLE"

# ----------------------------------------------------------------------------
# optional: wrap the app in its own disk image, built by its own engine
# ----------------------------------------------------------------------------
if [ "$MAKE_DMG" -eq 1 ]; then
    step "Packaging the app into a disk image"
    if [ -f "$ROOT/assets/default-background.png" ]; then
        set -- --background "$ROOT/assets/default-background.png"
        [ -f "$ROOT/assets/default-background@2x.png" ] && set -- "$@" --background-2x "$ROOT/assets/default-background@2x.png"
    else
        set --
    fi
    "$ROOT/scripts/make-dmg.sh" \
        --volname "$APP_NAME" \
        --output "$BUILD_DIR/DMG-Creator-$VERSION.dmg" \
        --window-size 660,400 \
        --icon-size 104 \
        --add "$APP_BUNDLE" \
        --pos "$APP_NAME.app:181,186" \
        --applications-link \
        --pos "Applications:471,186" \
        "$@"
    step "Disk image: $BUILD_DIR/DMG-Creator-$VERSION.dmg"
fi

# ----------------------------------------------------------------------------
# optional: install / run
# ----------------------------------------------------------------------------
if [ "$INSTALL" -eq 1 ]; then
    step "Installing into /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    step "Installed /Applications/$APP_NAME.app"
fi

if [ "$RUN" -eq 1 ]; then
    if [ "$INSTALL" -eq 1 ]; then
        open "/Applications/$APP_NAME.app"
    else
        open "$APP_BUNDLE"
    fi
fi

cat <<DONE

Next:
  open "$APP_BUNDLE"          launch it
  ./build.sh --install        put it in /Applications
  ./build.sh --dmg            wrap it in a disk image of its own

The first time you build an image, macOS asks for permission to control the
Finder. That is how the background picture and icon positions get set, so say
yes. If you miss the prompt: System Settings > Privacy & Security > Automation.
DONE
