#!/usr/bin/env bats
# Every system command is stubbed, so these tests never touch live audio or the real desktop.

REPO="$BATS_TEST_DIRNAME/.."
HEADSET=alsa_output.usb-HP__Inc_HyperX_Cloud_III_000000000000-00.analog-stereo
SPEAKERS=alsa_output.pci-0000_08_00.4.analog-stereo

setup() {
    STUB=$(mktemp -d)
    export STUB HOME="$STUB/home" PATH="$STUB/bin:$PATH"
    unset XDG_CONFIG_HOME XDG_DATA_HOME
    mkdir -p "$STUB/bin" "$HOME"
    echo "$HEADSET" >"$STUB/default"
    echo Cloud3_Daily >"$STUB/preset"
    echo 2 >"$STUB/bypass"
    touch "$STUB/running"

    cat >"$STUB/bin/easyeffects" <<'EOF'
#!/bin/bash
echo "easyeffects $*" >>"$STUB/log"
case "$1" in
    --version) echo "Easy Effects 8.3.2" ;;
    -b) [ "$2" = 3 ] && cat "$STUB/bypass" || echo "$2" >"$STUB/bypass" ;;
    -s) printf '\noutput: %s\n' "$(cat "$STUB/preset")" ;;
    -l) echo "$2" >"$STUB/preset" ;;
    -q) rm -f "$STUB/running" ;;
    --bypass-toggle) [ "$(cat "$STUB/bypass")" = 1 ] && echo 2 >"$STUB/bypass" || echo 1 >"$STUB/bypass" ;;
    --hide-window) touch "$STUB/running" ;;
esac
EOF
    cat >"$STUB/bin/pactl" <<'EOF'
#!/bin/bash
case "$*" in
    get-default-sink) cat "$STUB/default" ;;
    "list short sinks") printf '52\talsa_output.usb-HP__Inc_HyperX_Cloud_III_000000000000-00.analog-stereo\tPipeWire\n' ;;
    "list sink-inputs") cat <<'BLOCK'
Sink Input #1
	Corked: no
	Properties:
		media.name = "شيرين SECRET-TITLE"
		application.name = "mpv"
Sink Input #2
	Corked: yes
	Properties:
		application.name = "PausedApp"
BLOCK
    ;;
esac
EOF
    cat >"$STUB/bin/pgrep" <<'EOF'
#!/bin/bash
[ -e "$STUB/running" ]
EOF
    cat >"$STUB/bin/wpctl" <<'EOF'
#!/bin/bash
echo "Volume: 0.80"
EOF
    cat >"$STUB/bin/notify-send" <<'EOF'
#!/bin/bash
echo "notify $*" >>"$STUB/log"
EOF
    cat >"$STUB/bin/gdbus" <<'EOF'
#!/bin/bash
echo "gdbus $*" >>"$STUB/log"
[ -e "$STUB/no-kde" ] && exit 1
case "$*" in
    *setShortcutKeys*) echo "$*" | grep -oE '\(\[[0-9]+,0,0,0\]' | sed 's/,0,0,0\]//; s/^(\[/([([/; s/$/, 0, 0, 0],)],)/' ;;
esac
exit 0
EOF
    for tool in kbuildsycoca6 kitty; do printf '#!/bin/bash\n' >"$STUB/bin/$tool"; done
    # Keep the tests independent of the machine's package manager.
    printf '#!/bin/bash\nexit 0\n' >"$STUB/bin/pacman"
    chmod +x "$STUB"/bin/*
    EE="$REPO/bin/ee-mode"
}

teardown() {
    rm -rf "$STUB"
}

@test "help lists every shortcut from 0 to 9" {
    run "$EE" help
    [ "$status" -eq 0 ]
    for digit in 0 1 2 3 4 5 6 7 8 9; do
        [[ "$output" == *"  $digit  "* ]]
    done
}

@test "status names the active mode" {
    run "$EE" status
    [ "$output" = "1: Daily" ]
}

@test "status reports effects off" {
    echo 1 >"$STUB/bypass"
    run "$EE" status
    [ "$output" = "0: Effects OFF" ]
}

@test "status does not call easyeffects when it isn't running" {
    rm "$STUB/running"
    run "$EE" status
    [ "$output" = "EasyEffects is not running" ]
    ! grep -q '^easyeffects' "$STUB/log"
}

@test "a mode turns effects back on and loads its preset" {
    echo 1 >"$STUB/bypass"
    run "$EE" tarab
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB/bypass")" = 2 ]
    [ "$(cat "$STUB/preset")" = Cloud3_Tarab ]
}

@test "a mode is refused on speakers" {
    echo "$SPEAKERS" >"$STUB/default"
    run "$EE" daily
    [ "$status" -eq 1 ]
    ! grep -q -- 'easyeffects -l' "$STUB/log"
}

@test "a mode starts easyeffects hidden when it isn't running" {
    rm "$STUB/running"
    run "$EE" cinema
    [ "$status" -eq 0 ]
    grep -q -- '--hide-window --service-mode' "$STUB/log"
}

@test "an unknown command is a usage error" {
    run "$EE" nonsense
    [ "$status" -eq 2 ]
}

@test "dashboard draws, switches, shows help and quits" {
    run bash -c "(sleep 0.6; printf 2; sleep 0.8; printf h; sleep 0.4; printf x; sleep 0.4; printf q) |
        TERM=xterm script -qec '$EE' /dev/null"
    [[ "$output" == *"HyperX Sound"* ]]
    [[ "$output" == *"80%"* ]]
    [[ "$output" == *"SHORTCUTS"* ]]
    [ "$(cat "$STUB/preset")" = Cloud3_Tarab ]
}

@test "dashboard shows app names but never media titles" {
    run bash -c "(sleep 0.6; printf q) | TERM=xterm script -qec '$EE' /dev/null"
    [[ "$output" == *"mpv"* ]]
    [[ "$output" != *"SECRET-TITLE"* ]]
    [[ "$output" != *"PausedApp"* ]]
}

@test "install works in an empty home" {
    run bash "$REPO/install.sh"
    [ "$status" -eq 0 ]
    [ -x "$HOME/.local/bin/ee-mode" ]
    [ -f "$HOME/.local/share/easyeffects/output/Cloud3_Daily.json" ]
    [ -f "$HOME/.local/share/easyeffects/autoload/output/$HEADSET:Analog Output.json" ]
    [ -f "$HOME/.config/autostart/com.github.wwmm.easyeffects.desktop" ]
    grep -q '^outputAutoloadingFallbackPreset=Flat$' "$HOME/.config/easyeffects/db/easyeffectsrc"
    grep -q '^outputAutoloadingUsesFallback=true$' "$HOME/.config/easyeffects/db/easyeffectsrc"
}

@test "install works piped from curl, away from any checkout" {
    cat >"$STUB/bin/curl" <<EOF
#!/bin/bash
tar -C "$(cd "$REPO/.." && pwd)" -czf - "$(basename "$(cd "$REPO" && pwd)")"
EOF
    chmod +x "$STUB/bin/curl"
    cd "$STUB"
    run bash -c "bash < '$REPO/install.sh'"
    [ "$status" -eq 0 ]
    [ -x "$HOME/.local/bin/ee-mode" ]
    [ -f "$HOME/.local/share/easyeffects/output/Cloud3_Daily.json" ]
}

@test "install registers all ten keys with the SetPresent flag" {
    run bash "$REPO/install.sh"
    [ "$(grep -c 'setShortcutKeys' "$STUB/log")" -eq 10 ]
    [ "$(grep -c 'setForeignShortcutKeys' "$STUB/log")" -eq 0 ]
    [ "$(grep 'setShortcutKeys' "$STUB/log" | grep -c ' 2$')" -eq 10 ]
    [ -f "$HOME/.local/share/applications/net.local.ee-mode-dashboard.desktop" ]
}

@test "install twice changes nothing and keeps the original backup" {
    mkdir -p "$HOME/.config/easyeffects/db"
    printf '[Window]\nkeepThis=yes\n' >"$HOME/.config/easyeffects/db/easyeffectsrc"
    bash "$REPO/install.sh" >/dev/null
    cp "$HOME/.config/easyeffects/db/easyeffectsrc" "$STUB/first"
    bash "$REPO/install.sh" >/dev/null
    cmp "$STUB/first" "$HOME/.config/easyeffects/db/easyeffectsrc"
    grep -q '^keepThis=yes$' "$STUB/first"
    ! grep -q 'autostartOnLogin' "$HOME/.config/easyeffects/db/easyeffectsrc.hyperx-backup"
}

@test "install skips shortcuts outside KDE" {
    touch "$STUB/no-kde"
    run bash "$REPO/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shortcuts were skipped"* ]]
    [ -x "$HOME/.local/bin/ee-mode" ]
}

@test "install stops on EasyEffects older than 8" {
    sed -i 's/Easy Effects 8.3.2/Easy Effects 7.2.5/' "$STUB/bin/easyeffects"
    run bash "$REPO/install.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"EasyEffects 8 or newer"* ]]
}

@test "uninstall removes ours and keeps other presets" {
    bash "$REPO/install.sh" >/dev/null
    touch "$HOME/.local/share/easyeffects/output/Mine.json"
    run bash "$REPO/uninstall.sh"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.local/share/easyeffects/output/Mine.json" ]
    [ ! -e "$HOME/.local/share/easyeffects/output/Cloud3_Daily.json" ]
    [ ! -e "$HOME/.local/bin/ee-mode" ]
    [ ! -e "$HOME/.config/autostart/com.github.wwmm.easyeffects.desktop" ]
}

@test "presets use the band labels EasyEffects 8 accepts" {
    ! grep -lE '"(Low|High)-shelf"' "$REPO"/presets/*.json
}
