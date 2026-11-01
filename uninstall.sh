#!/usr/bin/env bash
# Remove what install.sh added. Other EasyEffects presets are left alone.

set -euo pipefail

readonly PRESETS=(Cloud3_Daily Cloud3_Tarab Cloud3_Cinema Test_Punch Test_Speakers Test_AutoLevel Flat)
readonly SHORTCUTS=(off daily tarab cinema punch speakers autolevel help dashboard status)

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
EE_RC=$CONFIG_HOME/easyeffects/db/easyeffectsrc
EE_DATA=$DATA_HOME/easyeffects

if pgrep -x easyeffects >/dev/null; then
    easyeffects -q >/dev/null 2>&1 || true
    sleep 2
fi

for name in "${SHORTCUTS[@]}"; do
    if command -v gdbus >/dev/null; then
        gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
            --method org.kde.KGlobalAccel.unregister "net.local.ee-mode-$name.desktop" _launch >/dev/null 2>&1 || true
    fi
    rm -f "$DATA_HOME/applications/net.local.ee-mode-$name.desktop"
done

for preset in "${PRESETS[@]}"; do
    rm -f "$EE_DATA/output/$preset.json"
done
rm -f "$EE_DATA"/autoload/output/*HyperX_Cloud_III*.json
rm -f "$HOME/.local/bin/ee-mode" "$CONFIG_HOME/autostart/com.github.wwmm.easyeffects.desktop"

if [ -f "$EE_RC.hyperx-backup" ]; then
    mv "$EE_RC.hyperx-backup" "$EE_RC"
fi

echo "Removed. EasyEffects itself is still installed and is not running now."
