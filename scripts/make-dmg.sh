#!/bin/bash
#
# make-dmg.sh — build a macOS disk image (.dmg) with a custom background,
# custom window geometry and hand-placed icons.
#
# This script is the build engine used by the DMG Creator app. It is also a
# perfectly good standalone CLI tool; the app simply shells out to it.
#
# Requires: macOS (hdiutil, osascript, ditto). Tested against bash 3.2,
# the /bin/bash that ships with macOS.
#
# Usage: see --help.
#

set -eu

PROGRAM="$(basename "$0")"
VERSION="1.0.0"

# ----------------------------------------------------------------------------
# defaults
# ----------------------------------------------------------------------------
VOLNAME=""
OUTPUT=""
BACKGROUND=""
BACKGROUND_2X=""
VOLUME_ICON=""
WINDOW_X=200
WINDOW_Y=140
WINDOW_W=640
WINDOW_H=420
ICON_SIZE=128
TEXT_SIZE=12
FORMAT="UDZO"
FS="HFS+"
ADD_APPLICATIONS_LINK=0
REQUIRE_LAYOUT=0
SKIP_LAYOUT=0
CODESIGN_IDENTITY=""
QUIET=0
EXTRA_SIZE_KB=0

ITEM_PATHS=()
ITEM_NAMES=()
POS_NAMES=()
POS_X=()
POS_Y=()

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
log()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
step() { [ "$QUIET" -eq 1 ] || printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<HELPTEXT
$PROGRAM $VERSION — build a .dmg with a custom background and icon layout

USAGE
    $PROGRAM --volname NAME --output OUT.dmg [options] --add PATH [--add PATH ...]

REQUIRED
    --volname NAME          Volume name shown when the image is mounted.
    --output PATH           Destination .dmg file (overwritten if it exists).
    --add PATH              File, folder or .app to place in the image.
                            Repeat for several items.

LAYOUT
    --background PATH       Background image (png, jpg, tiff, gif).
    --background-2x PATH    Optional Retina (@2x) variant of the background.
                            Combined with --background into a multi-resolution
                            TIFF so the image stays crisp on Retina displays.
    --window X,Y            Top-left corner of the Finder window. Default $WINDOW_X,$WINDOW_Y
    --window-size W,H       Size of the Finder window in points. Default ${WINDOW_W}x${WINDOW_H}
    --icon-size N           Finder icon size, 16-512. Default $ICON_SIZE
    --text-size N           Finder label size, 10-16. Default $TEXT_SIZE
    --pos NAME:X,Y          Position of an item, measured from the top-left of
                            the window content area. NAME is the item's name
                            inside the image (e.g. "My App.app"). Repeatable.
    --applications-link     Add a symlink to /Applications (named "Applications").
    --volume-icon PATH      .icns file to use as the mounted volume's icon.

OUTPUT
    --format FORMAT         UDZO (zlib, default), UDBZ (bzip2), ULFO (lzfse),
                            ULMO (lzma) or UDRO (uncompressed read-only).
    --codesign IDENTITY     Code-sign the finished .dmg with this identity.
    --extra-size-kb N       Extra slack to add to the writable staging image.

BEHAVIOUR
    --require-layout        Fail if the Finder layout step cannot run
                            (default: warn and ship an unstyled image).
    --skip-layout           Do not touch the Finder at all.
    --quiet                 Only print warnings and errors.
    -h, --help              Show this help.
    --version               Show version.

EXAMPLE
    $PROGRAM \\
        --volname "My App" \\
        --output ~/Desktop/MyApp.dmg \\
        --background assets/background.png \\
        --window-size 660,400 \\
        --icon-size 128 \\
        --add build/My\\ App.app \\
        --pos "My App.app:165,185" \\
        --applications-link \\
        --pos "Applications:495,185"
HELPTEXT
}

# Split "A,B" into two globals SPLIT_1 / SPLIT_2.
split_pair() {
    case "$1" in
        *,*) ;;
        *) die "expected two comma-separated values, got '$1'" ;;
    esac
    SPLIT_1="${1%%,*}"
    SPLIT_2="${1#*,}"
}

require_int() {
    case "$1" in
        ''|*[!0-9-]*) die "'$1' is not a number ($2)" ;;
    esac
}

# Escape a string for safe inclusion inside an AppleScript double-quoted
# literal: backslashes first, then double quotes.
applescript_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ----------------------------------------------------------------------------
# argument parsing
# ----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --volname)        [ $# -ge 2 ] || die "--volname needs a value";        VOLNAME="$2"; shift 2 ;;
        --output)         [ $# -ge 2 ] || die "--output needs a value";         OUTPUT="$2"; shift 2 ;;
        --background)     [ $# -ge 2 ] || die "--background needs a value";     BACKGROUND="$2"; shift 2 ;;
        --background-2x)  [ $# -ge 2 ] || die "--background-2x needs a value";  BACKGROUND_2X="$2"; shift 2 ;;
        --volume-icon)    [ $# -ge 2 ] || die "--volume-icon needs a value";    VOLUME_ICON="$2"; shift 2 ;;
        --format)         [ $# -ge 2 ] || die "--format needs a value";         FORMAT="$2"; shift 2 ;;
        --codesign)       [ $# -ge 2 ] || die "--codesign needs a value";       CODESIGN_IDENTITY="$2"; shift 2 ;;
        --icon-size)      [ $# -ge 2 ] || die "--icon-size needs a value";      ICON_SIZE="$2"; shift 2 ;;
        --text-size)      [ $# -ge 2 ] || die "--text-size needs a value";      TEXT_SIZE="$2"; shift 2 ;;
        --extra-size-kb)  [ $# -ge 2 ] || die "--extra-size-kb needs a value";  EXTRA_SIZE_KB="$2"; shift 2 ;;
        --window)
            [ $# -ge 2 ] || die "--window needs X,Y"
            split_pair "$2"; WINDOW_X="$SPLIT_1"; WINDOW_Y="$SPLIT_2"; shift 2 ;;
        --window-size)
            [ $# -ge 2 ] || die "--window-size needs W,H"
            split_pair "$2"; WINDOW_W="$SPLIT_1"; WINDOW_H="$SPLIT_2"; shift 2 ;;
        --add)
            [ $# -ge 2 ] || die "--add needs a path"
            ITEM_PATHS[${#ITEM_PATHS[@]}]="$2"; shift 2 ;;
        --pos)
            [ $# -ge 2 ] || die "--pos needs NAME:X,Y"
            case "$2" in
                *:*) ;;
                *) die "--pos expects NAME:X,Y, got '$2'" ;;
            esac
            _pname="${2%:*}"
            _pcoords="${2##*:}"
            split_pair "$_pcoords"
            require_int "$SPLIT_1" "--pos x for $_pname"
            require_int "$SPLIT_2" "--pos y for $_pname"
            POS_NAMES[${#POS_NAMES[@]}]="$_pname"
            POS_X[${#POS_X[@]}]="$SPLIT_1"
            POS_Y[${#POS_Y[@]}]="$SPLIT_2"
            shift 2 ;;
        --applications-link) ADD_APPLICATIONS_LINK=1; shift ;;
        --require-layout)    REQUIRE_LAYOUT=1; shift ;;
        --skip-layout)       SKIP_LAYOUT=1; shift ;;
        --quiet)             QUIET=1; shift ;;
        --version)           printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
        -h|--help)           usage; exit 0 ;;
        *) die "unknown option '$1' (try --help)" ;;
    esac
done

# ----------------------------------------------------------------------------
# validation
# ----------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "$PROGRAM builds Apple disk images and only runs on macOS."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found."

[ -n "$VOLNAME" ] || die "--volname is required."
[ -n "$OUTPUT" ] || die "--output is required."

case "$VOLNAME" in
    *:*) die "volume names cannot contain a colon." ;;
esac
# HFS+ volume names are limited to 27 characters.
if [ "${#VOLNAME}" -gt 27 ]; then
    die "volume name is ${#VOLNAME} characters; the limit is 27."
fi

case "$OUTPUT" in
    *.dmg) ;;
    *) OUTPUT="$OUTPUT.dmg" ;;
esac

if [ ${#ITEM_PATHS[@]} -eq 0 ] && [ "$ADD_APPLICATIONS_LINK" -eq 0 ]; then
    die "nothing to put in the image: pass at least one --add PATH."
fi

require_int "$WINDOW_X" "--window x"
require_int "$WINDOW_Y" "--window y"
require_int "$WINDOW_W" "--window-size width"
require_int "$WINDOW_H" "--window-size height"
require_int "$ICON_SIZE" "--icon-size"
require_int "$TEXT_SIZE" "--text-size"
require_int "$EXTRA_SIZE_KB" "--extra-size-kb"

[ "$WINDOW_W" -ge 200 ] || die "--window-size width must be at least 200."
[ "$WINDOW_H" -ge 150 ] || die "--window-size height must be at least 150."
[ "$ICON_SIZE" -ge 16 ] && [ "$ICON_SIZE" -le 512 ] || die "--icon-size must be between 16 and 512."
[ "$TEXT_SIZE" -ge 10 ] && [ "$TEXT_SIZE" -le 16 ] || die "--text-size must be between 10 and 16."

case "$FORMAT" in
    UDZO|UDBZ|ULFO|ULMO|UDRO) ;;
    *) die "unsupported --format '$FORMAT' (use UDZO, UDBZ, ULFO, ULMO or UDRO)." ;;
esac

if [ -n "$BACKGROUND" ]; then
    [ -f "$BACKGROUND" ] || die "background image not found: $BACKGROUND"
fi
if [ -n "$BACKGROUND_2X" ]; then
    [ -f "$BACKGROUND_2X" ] || die "@2x background image not found: $BACKGROUND_2X"
    [ -n "$BACKGROUND" ] || die "--background-2x needs --background as well."
fi
if [ -n "$VOLUME_ICON" ]; then
    [ -f "$VOLUME_ICON" ] || die "volume icon not found: $VOLUME_ICON"
fi

# Resolve items, check for duplicates and derive the name each one will have
# inside the image.
_i=0
while [ "$_i" -lt ${#ITEM_PATHS[@]} ]; do
    _src="${ITEM_PATHS[$_i]}"
    [ -e "$_src" ] || die "item not found: $_src"
    _name="$(basename "$_src")"
    _j=0
    while [ "$_j" -lt ${#ITEM_NAMES[@]} ]; do
        [ "${ITEM_NAMES[$_j]}" != "$_name" ] || die "two items would both be named '$_name' inside the image."
        _j=$((_j + 1))
    done
    ITEM_NAMES[${#ITEM_NAMES[@]}]="$_name"
    _i=$((_i + 1))
done
if [ "$ADD_APPLICATIONS_LINK" -eq 1 ]; then
    _j=0
    while [ "$_j" -lt ${#ITEM_NAMES[@]} ]; do
        [ "${ITEM_NAMES[$_j]}" != "Applications" ] || die "an item is already named 'Applications'; drop --applications-link."
        _j=$((_j + 1))
    done
fi

# Every --pos must refer to something that will actually be in the image.
_i=0
while [ "$_i" -lt ${#POS_NAMES[@]} ]; do
    _pn="${POS_NAMES[$_i]}"
    _found=0
    _j=0
    while [ "$_j" -lt ${#ITEM_NAMES[@]} ]; do
        if [ "${ITEM_NAMES[$_j]}" = "$_pn" ]; then _found=1; fi
        _j=$((_j + 1))
    done
    if [ "$_pn" = "Applications" ] && [ "$ADD_APPLICATIONS_LINK" -eq 1 ]; then _found=1; fi
    [ "$_found" -eq 1 ] || die "--pos refers to '$_pn', which is not in the image."
    _i=$((_i + 1))
done

# ----------------------------------------------------------------------------
# workspace
# ----------------------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/make-dmg.XXXXXXXX")"
STAGING="$WORK/volume"
TEMP_DMG="$WORK/writable.dmg"
DEVICE=""
MOUNTPOINT=""

cleanup() {
    _status=$?
    if [ -n "$DEVICE" ]; then
        hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || \
            hdiutil detach "$DEVICE" -force -quiet >/dev/null 2>&1 || true
    fi
    [ -n "$WORK" ] && rm -rf "$WORK"
    exit $_status
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGING"

# ----------------------------------------------------------------------------
# stage the contents
# ----------------------------------------------------------------------------
step "Staging contents"
_i=0
while [ "$_i" -lt ${#ITEM_PATHS[@]} ]; do
    _src="${ITEM_PATHS[$_i]}"
    _name="${ITEM_NAMES[$_i]}"
    log "    + $_name"
    # ditto keeps resource forks, extended attributes and bundle bits intact.
    ditto "$_src" "$STAGING/$_name"
    _i=$((_i + 1))
done

if [ "$ADD_APPLICATIONS_LINK" -eq 1 ]; then
    log "    + Applications (symlink)"
    ln -s /Applications "$STAGING/Applications"
fi

BG_NAME=""
if [ -n "$BACKGROUND" ]; then
    mkdir -p "$STAGING/.background"
    if [ -n "$BACKGROUND_2X" ] && command -v tiffutil >/dev/null 2>&1; then
        step "Building multi-resolution background"
        BG_NAME="background.tiff"
        if ! tiffutil -cathidpicheck "$BACKGROUND" "$BACKGROUND_2X" \
                -out "$STAGING/.background/$BG_NAME" >/dev/null 2>&1; then
            warn "tiffutil could not combine the 1x and 2x backgrounds; using the 1x image."
            BG_NAME=""
        fi
    fi
    if [ -z "$BG_NAME" ]; then
        _ext="${BACKGROUND##*.}"
        case "$_ext" in
            "$BACKGROUND") BG_NAME="background" ;;
            *) BG_NAME="background.$(printf '%s' "$_ext" | tr '[:upper:]' '[:lower:]')" ;;
        esac
        cp "$BACKGROUND" "$STAGING/.background/$BG_NAME"
    fi
    log "    + .background/$BG_NAME"
fi

if [ -n "$VOLUME_ICON" ]; then
    cp "$VOLUME_ICON" "$STAGING/.VolumeIcon.icns"
    log "    + .VolumeIcon.icns"
fi

# ----------------------------------------------------------------------------
# create a writable image big enough for the contents plus Finder metadata
# ----------------------------------------------------------------------------
CONTENT_KB="$(du -sk "$STAGING" | awk '{print $1}')"
SIZE_KB=$(( CONTENT_KB + CONTENT_KB / 3 + 20480 + EXTRA_SIZE_KB ))
step "Creating ${SIZE_KB}KB writable image for ${CONTENT_KB}KB of content"

rm -f "$TEMP_DMG"
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLNAME" \
    -fs "$FS" \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${SIZE_KB}k" \
    -quiet \
    "$TEMP_DMG" || die "hdiutil create failed."

# ----------------------------------------------------------------------------
# mount it
# ----------------------------------------------------------------------------
step "Mounting image"
ATTACH_OUT="$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen)" \
    || die "hdiutil attach failed."
DEVICE="$(printf '%s\n' "$ATTACH_OUT" | awk '/^\/dev\//{print $1; exit}')"
[ -n "$DEVICE" ] || die "could not work out which device the image was attached to."

# Derive the mount point from `mount` rather than guessing /Volumes/$VOLNAME:
# macOS appends a suffix when a volume of that name is already mounted.
MOUNTPOINT="$(mount | sed -n "s|^${DEVICE}[s0-9]* on \(.*\) (.*|\1|p" | head -1)"
if [ -z "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then
    die "the image attached as $DEVICE but no mount point could be found."
fi
log "    mounted at $MOUNTPOINT"

# ----------------------------------------------------------------------------
# tell the Finder how the window should look
# ----------------------------------------------------------------------------
if [ "$SKIP_LAYOUT" -eq 1 ]; then
    step "Skipping Finder layout (--skip-layout)"
else
    step "Applying window layout"
    SCRIPT_FILE="$WORK/layout.applescript"
    _volume_as="$(applescript_escape "$(basename "$MOUNTPOINT")")"

    {
        printf 'tell application "Finder"\n'
        printf '  tell disk "%s"\n' "$_volume_as"
        printf '    open\n'
        printf '    delay 1\n'
        printf '    set current view of container window to icon view\n'
        printf '    set toolbar visible of container window to false\n'
        printf '    set statusbar visible of container window to false\n'
        printf '    set the bounds of container window to {%d, %d, %d, %d}\n' \
            "$WINDOW_X" "$WINDOW_Y" "$((WINDOW_X + WINDOW_W))" "$((WINDOW_Y + WINDOW_H))"
        printf '    set theViewOptions to the icon view options of container window\n'
        printf '    set arrangement of theViewOptions to not arranged\n'
        printf '    set icon size of theViewOptions to %d\n' "$ICON_SIZE"
        printf '    set text size of theViewOptions to %d\n' "$TEXT_SIZE"
        printf '    set label position of theViewOptions to bottom\n'
        printf '    set shows item info of theViewOptions to false\n'
        printf '    set shows icon preview of theViewOptions to true\n'
        if [ -n "$BG_NAME" ]; then
            printf '    set background picture of theViewOptions to file ".background:%s"\n' \
                "$(applescript_escape "$BG_NAME")"
        fi
        _i=0
        while [ "$_i" -lt ${#POS_NAMES[@]} ]; do
            printf '    set position of item "%s" of container window to {%d, %d}\n' \
                "$(applescript_escape "${POS_NAMES[$_i]}")" "${POS_X[$_i]}" "${POS_Y[$_i]}"
            _i=$((_i + 1))
        done
        printf '    close\n'
        printf '    open\n'
        printf '    update without registering applications\n'
        printf '    delay 2\n'
        printf '  end tell\n'
        printf 'end tell\n'
    } > "$SCRIPT_FILE"

    set +e
    LAYOUT_OUT="$(osascript "$SCRIPT_FILE" 2>&1)"
    LAYOUT_STATUS=$?
    set -e
    if [ "$LAYOUT_STATUS" -ne 0 ]; then
        printf '%s\n' "$LAYOUT_OUT" >&2
        MSG="the Finder refused the layout, so the image has no background or icon placement.
      macOS asks for permission the first time an app automates the Finder. Allow it in
      System Settings > Privacy & Security > Automation, then build again."
        if [ "$REQUIRE_LAYOUT" -eq 1 ]; then
            die "$MSG"
        fi
        warn "$MSG"
    else
        log "    layout applied"
    fi
fi

if [ -n "$VOLUME_ICON" ]; then
    if [ -x /usr/bin/SetFile ]; then
        /usr/bin/SetFile -a C "$MOUNTPOINT" || warn "could not set the custom-icon bit on the volume."
    else
        warn "SetFile is not installed (it comes with the Xcode command line tools), so the volume icon may not show."
    fi
fi

chmod -Rf go-w "$MOUNTPOINT" >/dev/null 2>&1 || true
sync

# ----------------------------------------------------------------------------
# unmount, with retries: the Finder often still holds the volume briefly
# ----------------------------------------------------------------------------
step "Unmounting image"
_tries=0
while [ "$_tries" -lt 10 ]; do
    if hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1; then
        DEVICE=""
        break
    fi
    _tries=$((_tries + 1))
    sleep 2
done
if [ -n "$DEVICE" ]; then
    warn "the volume was busy; forcing it to unmount."
    hdiutil detach "$DEVICE" -force -quiet >/dev/null 2>&1 || die "could not unmount $DEVICE."
    DEVICE=""
fi

# ----------------------------------------------------------------------------
# compress into the final image
# ----------------------------------------------------------------------------
step "Compressing to $FORMAT"
OUT_DIR="$(dirname "$OUTPUT")"
[ -d "$OUT_DIR" ] || mkdir -p "$OUT_DIR"
rm -f "$OUTPUT"

if [ "$FORMAT" = "UDZO" ]; then
    hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" -quiet \
        || die "hdiutil convert failed."
else
    hdiutil convert "$TEMP_DMG" -format "$FORMAT" -o "$OUTPUT" -quiet \
        || die "hdiutil convert failed."
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
    step "Signing with '$CODESIGN_IDENTITY'"
    codesign --sign "$CODESIGN_IDENTITY" --timestamp "$OUTPUT" \
        || die "codesign failed."
fi

FINAL_SIZE="$(du -h "$OUTPUT" | awk '{print $1}')"
step "Done: $OUTPUT ($FINAL_SIZE)"
printf 'DMG_PATH=%s\n' "$OUTPUT"
