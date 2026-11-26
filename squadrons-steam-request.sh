#!/usr/bin/env bash
set -euo pipefail

controller=${1:-auto}
if [[ $# -gt 1 || ! $controller =~ ^(auto|frame|steam)$ ]]; then
    printf 'Choose auto, frame, or steam.\n' >&2
    exit 2
fi

# Let the Steam shortcut finish before the host opens the VR session.
exec /usr/bin/systemd-run --user --no-block --collect --on-active=4s \
    --timer-property=AccuracySec=100ms \
    --unit=squadrons-steam-vr-launch "$HOME/.local/bin/squadrons-vr" "$controller"
