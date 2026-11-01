#!/usr/bin/env bash
# Install the HyperX Cloud III sound modes. Safe to run more than once.
#   curl -fsSL https://raw.githubusercontent.com/AbdallahxAhmed/hyperx-cloud3-sound/main/install.sh | bash

set -euo pipefail

readonly REPO=AbdallahxAhmed/hyperx-cloud3-sound
readonly BRANCH=main
readonly DEFAULT_SINK=alsa_output.usb-HP__Inc_HyperX_Cloud_III_000000000000-00.analog-stereo
readonly ARCH_PACKAGES=(easyeffects calf lsp-plugins-lv2 mda.lv2 pipewire-pulse wireplumber libnotify)

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
BIN_DIR=$HOME/.local/bin
EE_RC=$CONFIG_HOME/easyeffects/db/easyeffectsrc
EE_DATA=$DATA_HOME/easyeffects
APPS_DIR=$DATA_HOME/applications

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# The script's own path, empty when piped from curl.
readonly SCRIPT_PATH=${BASH_SOURCE[0]:-}

# Prints the checkout this script runs from, if there is one.
checkout_dir() {
    [ -f "$SCRIPT_PATH" ] || return 1
    local here
    here=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
    [ -f "$here/bin/ee-mode" ] || return 1
    echo "$here"
}

# Not called through $(...): a trap set in a subshell would delete the download on the way out.
download_repo() {
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" |
        tar -xz --strip-components=1 -C "$TMP_DIR"
}

install_arch_packages() {
    local missing=() package answer
    for package in "${ARCH_PACKAGES[@]}"; do
        pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    [ "${#missing[@]}" -eq 0 ] && return 0

    say "Missing packages: ${missing[*]}"
    # stdin is the curl pipe, so the answer has to come from the terminal.
    if ! { printf 'Install them with sudo pacman? [y/N] ' >/dev/tty; } 2>/dev/null; then
        die "no terminal to ask on. Run: sudo pacman -S --needed ${missing[*]}"
    fi
    read -r answer </dev/tty
    # shellcheck disable=SC2024  # the redirect is for pacman's own prompts
    case "$answer" in
        y | Y | yes) sudo pacman -S --needed "${missing[@]}" </dev/tty ;;
        *) die "cannot continue without: ${missing[*]}" ;;
    esac
}

check_requirements() {
    if command -v pacman >/dev/null; then
        install_arch_packages
    fi
    if ! command -v easyeffects >/dev/null; then
        if command -v flatpak >/dev/null && flatpak info com.github.wwmm.easyeffects >/dev/null 2>&1; then
            die "Flatpak EasyEffects is not supported. Install the distro package instead."
        fi
        die "EasyEffects is not installed. Install it with the calf, lsp-plugins and mda LV2 plugins."
    fi
    command -v pactl >/dev/null || die "pactl is missing. Install PipeWire's PulseAudio support."

    local version
    version=$(easyeffects --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    [ "${version%%.*}" -ge 8 ] 2>/dev/null ||
        die "EasyEffects 8 or newer is needed, found: ${version:-unknown}"
}

# Set one key in an INI file, adding the group if it isn't there.
ini_set() {
    local file=$1 group=$2 key=$3 value=$4
    awk -v group="[$group]" -v key="$key" -v value="$value" '
        $0 == group { in_group = 1; found = 1; print; next }
        in_group && /^\[/ {
            if (!done) { print key "=" value; done = 1 }
            in_group = 0
        }
        in_group && index($0, key "=") == 1 {
            if (!done) { print key "=" value; done = 1 }
            next
        }
        { print }
        END {
            if (!found) { print ""; print group }
            if (!done) print key "=" value
        }
    ' "$file" >"$file.tmp"
    mv "$file.tmp" "$file"
}

stop_easyeffects() {
    pgrep -x easyeffects >/dev/null || return 0
    easyeffects -q >/dev/null 2>&1 || true
    for _ in {1..10}; do
        pgrep -x easyeffects >/dev/null || return 0
        sleep 0.5
    done
    die "EasyEffects did not stop, so its settings can't be changed safely."
}

install_files() {
    local src=$1
    mkdir -p "$BIN_DIR" "$EE_DATA/output" "$EE_DATA/autoload/output" "$CONFIG_HOME/autostart" "$(dirname "$EE_RC")"
    install -m 755 "$src/bin/ee-mode" "$BIN_DIR/ee-mode"
    install -m 644 "$src"/presets/*.json "$EE_DATA/output/"
}

configure_easyeffects() {
    local sink
    sink=$(pactl list short sinks 2>/dev/null | awk '/HyperX_Cloud_III/ { print $2; exit }')
    sink=${sink:-$DEFAULT_SINK}

    # EasyEffects matches on the route description, not its name.
    cat >"$EE_DATA/autoload/output/$sink:Analog Output.json" <<EOF
{
    "device": "$sink",
    "device-description": "HyperX Cloud III Analog Stereo",
    "device-profile": "Analog Output",
    "preset-name": "Cloud3_Daily"
}
EOF

    [ -f "$EE_RC" ] || touch "$EE_RC"
    [ -f "$EE_RC.hyperx-backup" ] || cp "$EE_RC" "$EE_RC.hyperx-backup"
    ini_set "$EE_RC" Window outputAutoloadingUsesFallback true
    ini_set "$EE_RC" Window outputAutoloadingFallbackPreset Flat
    ini_set "$EE_RC" Window autostartOnLogin true

    # EasyEffects only writes this file when the setting changes inside the running app.
    cat >"$CONFIG_HOME/autostart/com.github.wwmm.easyeffects.desktop" <<'EOF'
[Desktop Entry]
Name=Easy Effects
Comment=Easy Effects Service
Exec=easyeffects --hide-window --service-mode
Icon=com.github.wwmm.easyeffects
StartupNotify=false
Terminal=false
Type=Application
X-GNOME-Autostart-Phase=Application
X-KDE-autostart-phase=2
EOF
}

terminal_command() {
    if command -v kitty >/dev/null; then
        echo "kitty --title Sound"
    elif command -v konsole >/dev/null; then
        echo "konsole -e"
    fi
}

write_shortcut_entry() {
    local name=$1 title=$2 exec_line=$3
    cat >"$APPS_DIR/net.local.ee-mode-$name.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Easy Effects: $title
Exec=$exec_line
Icon=com.github.wwmm.easyeffects
Terminal=false
NoDisplay=true
StartupNotify=false
EOF
}

register_shortcut() {
    local name=$1 title=$2 digit=$3 keycode id reply
    # Meta (0x10000000) + Alt (0x08000000) + the digit's Qt key code.
    keycode=$((0x18000030 + digit))
    id="['net.local.ee-mode-$name.desktop','_launch','Easy Effects: $title','Easy Effects: $title']"
    kglobalaccel doRegister "$id" >/dev/null
    # Flag 2 is SetPresent. Without it the key is saved but never grabbed.
    reply=$(kglobalaccel setShortcutKeys "$id" "[([$keycode,0,0,0],)]" 2)
    case "$reply" in
        *"$keycode"*) ;;
        *) say "  Windows+Alt+$digit is already in use, so $title has no shortcut." ;;
    esac
}

kglobalaccel() {
    local method=$1
    shift
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method "org.kde.KGlobalAccel.$method" "$@"
}

install_shortcuts() {
    if ! command -v gdbus >/dev/null ||
        ! gdbus introspect --session --dest org.kde.kglobalaccel --object-path /kglobalaccel >/dev/null 2>&1; then
        say "Not on KDE Plasma, so shortcuts were skipped. ee-mode still works in a terminal."
        return
    fi

    mkdir -p "$APPS_DIR"
    local term entry name title digit
    local shortcuts=(
        "off|Clear effects|0" "daily|Daily|1" "tarab|Tarab|2" "cinema|Cinema|3"
        "punch|Test Punch|4" "speakers|Test Speakers|5" "autolevel|Test AutoLevel|6" "status|Show current mode|9"
    )
    for entry in "${shortcuts[@]}"; do
        IFS='|' read -r name title digit <<<"$entry"
        write_shortcut_entry "$name" "$title" "$BIN_DIR/ee-mode $name"
    done

    term=$(terminal_command)
    if [ -n "$term" ]; then
        write_shortcut_entry help "Help" "$term $BIN_DIR/ee-mode help --wait"
        write_shortcut_entry dashboard "Dashboard" "$term $BIN_DIR/ee-mode"
        shortcuts+=("help|Help|7" "dashboard|Dashboard|8")
    else
        say "No Kitty or Konsole found, so the help and dashboard keys were skipped."
    fi

    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
    for entry in "${shortcuts[@]}"; do
        IFS='|' read -r name title digit <<<"$entry"
        register_shortcut "$name" "$title" "$digit"
    done
}

start_easyeffects() {
    setsid -f easyeffects --hide-window --service-mode >/dev/null 2>&1 </dev/null
    sleep 3
    case "$(pactl get-default-sink 2>/dev/null)" in
        *HyperX_Cloud_III*)
            if ! easyeffects -s 2>/dev/null | grep -q 'output: Cloud3_Daily'; then
                say "warning: the HyperX is the output, but Daily did not load. Run: ee-mode daily"
            fi
            ;;
        *) say "The HyperX isn't the default output, so effects stay off until you switch to it." ;;
    esac
}

main() {
    check_requirements
    local src
    if ! src=$(checkout_dir); then
        download_repo
        src=$TMP_DIR
    fi
    stop_easyeffects
    install_files "$src"
    configure_easyeffects
    install_shortcuts
    start_easyeffects

    say ""
    say "Done. Open the dashboard with: ee-mode"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) say "Add $BIN_DIR to your PATH to run ee-mode by name." ;;
    esac
}

main "$@"
