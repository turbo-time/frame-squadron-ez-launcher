#!/usr/bin/env bash
set -euo pipefail

readonly repository="https://raw.githubusercontent.com/turbo-time/frame-squadron-ez-launcher/main"
readonly bin_dir="$HOME/.local/bin"
readonly applications_dir="$HOME/.local/share/applications"
readonly temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

say() { printf '%s\n' "$*"; }
fail() { say "Install stopped: $*" >&2; exit 1; }

architecture=$(uname -m)
if [[ $architecture == aarch64 || $architecture == arm64 ]]; then
    say 'This is an ARM Steam Frame. No install is needed here.'
    say 'Use the Machine library in Steam and choose Stream for the Squadrons shortcut.'
    exit 0
fi
[[ $architecture == x86_64 ]] || fail "Unsupported architecture: $architecture."

[[ -r /etc/os-release ]] || fail 'Could not identify this operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == steamos ]] || fail 'Install this on the Steam Machine running SteamOS.'

command -v curl >/dev/null || fail 'curl is required.'
command -v python3 >/dev/null || fail 'Python 3 is required.'
python3 -c 'import aiohttp' >/dev/null 2>&1 || \
    fail 'Python package aiohttp is missing. No files were installed.'

files=(
    'squadrons-machine-vr.sh'
    'squadrons-steam-request.sh'
    'squadrons-select-controller.py'
    'squadrons-game-quit.py'
    'squadrons-native-frame.desktop'
    'squadrons-native-steam.desktop'
)

say 'Downloading the Squadrons launcher files from GitHub…'
for file in "${files[@]}"; do
    curl --fail --location --silent --show-error "$repository/$file" -o "$temporary_dir/$file" ||
        fail "Could not download $file. No installed files were changed."
done

for file in "${files[@]}"; do
    [[ -s $temporary_dir/$file ]] || fail "Downloaded file is empty: $file."
done

install -d "$bin_dir" "$applications_dir"
install -m 755 "$temporary_dir/squadrons-machine-vr.sh" "$bin_dir/squadrons-vr"
install -m 755 "$temporary_dir/squadrons-steam-request.sh" "$bin_dir/squadrons-steam-request"
install -m 755 "$temporary_dir/squadrons-select-controller.py" "$bin_dir/squadrons-select-controller"
install -m 755 "$temporary_dir/squadrons-game-quit.py" "$bin_dir/squadrons-game-quit"
install -m 644 "$temporary_dir/squadrons-native-frame.desktop" "$applications_dir/squadrons-native-frame.desktop"
install -m 644 "$temporary_dir/squadrons-native-steam.desktop" "$applications_dir/squadrons-native-steam.desktop"

if command -v steamos-add-to-steam >/dev/null; then
    steamos-add-to-steam "$applications_dir/squadrons-native-frame.desktop"
    steamos-add-to-steam "$applications_dir/squadrons-native-steam.desktop"
    say 'Added both controller choices to your Steam library.'
else
    say 'Launcher files are installed. Add these two applications to Steam manually:'
    say "  $applications_dir/squadrons-native-frame.desktop"
    say "  $applications_dir/squadrons-native-steam.desktop"
fi

say 'Done. On the Frame, open the Machine library and choose Stream.'
