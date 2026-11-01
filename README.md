# HyperX Cloud III sound modes

EasyEffects presets for the wired HyperX Cloud III, with bass inspired by small
2.1 desktop speakers, plus keyboard shortcuts and a terminal dashboard.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/AbdallahxAhmed/hyperx-cloud3-sound/main/install.sh | bash
```

Needs EasyEffects 8 or newer (not the Flatpak) with the Calf, LSP and MDA LV2
plugins. On Arch-based systems the installer offers to install what's missing.
Shortcuts need KDE Plasma 6. Everywhere else, `ee-mode` works in a terminal.

Developed on CachyOS with KDE Plasma 6.

To remove it:

```sh
curl -fsSL https://raw.githubusercontent.com/AbdallahxAhmed/hyperx-cloud3-sound/main/uninstall.sh | bash
```

## Use

Hold Windows + Alt and tap a number:

| Key | Action |
|---|---|
| `0` | Effects off / on |
| `1` | Daily: anime, rap, pop |
| `2` | Tarab: tarab and old recordings |
| `3` | Cinema: series and movies |
| `4` | Test: Punch, Daily + bass harmonics |
| `5` | Test: Speakers, Daily + speaker-like room |
| `6` | Test: AutoLevel, Daily + evened-out volume |
| `7` | Help page |
| `8` | Dashboard |
| `9` | Popup with the current mode |

Or run `ee-mode` for the dashboard, and `ee-mode help` for every command.

Modes only apply to the HyperX. Any other output plays clean with no effects.

## How the presets work

Each preset has two equalizers. `equalizer#0` is the measured headset correction,
the same in every mode. `equalizer#1` is the taste layer, so that's the one to tune.

The correction is AutoEq's parametric profile for the wired Cloud III.

## Tests

```sh
bats tests/
```

System commands are stubbed, so the tests don't touch live audio.

## Credits

- [AutoEq](https://github.com/jaakkopasanen/AutoEq) (MIT): headset correction, from
  commit `7ae0f56`, based on [Rtings](https://www.rtings.com/) measurements
- [EasyEffects](https://github.com/wwmm/easyeffects)

## Licence

MIT
