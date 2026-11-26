#!/usr/bin/env bash
set -euo pipefail

readonly app=1222730 steamvr=250820 big_picture=769
readonly focus_order=GAMESCOPECTRL_BASELAYER_APPID
readonly vr_bin="$HOME/.local/share/Steam/steamapps/common/SteamVR/bin/linux64"
readonly link_log="$HOME/.local/share/Steam/logs/driver_vrlink.txt"
readonly disconnect_grace=15

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

wait_for() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@"; do
        (( SECONDS < deadline )) || return 1
        sleep 1
    done
}

root_property() {
    local value
    value=$(xprop -root "$1") || return 1
    [[ $value == *' = '* ]] || return 1
    printf '%s\n' "${value#* = }"
}

focusable() {
    local apps
    apps=$(root_property GAMESCOPE_FOCUSABLE_APPS) || return 1
    [[ ",${apps// /}," == *",$1,"* ]]
}

focus_is() {
    [[ $(root_property GAMESCOPE_FOCUSED_APP) == "$1" ]]
}

focus() {
    local target=$1 other=$2 value layer
    local -a layers
    value=$(root_property "$focus_order") || return 1
    IFS=', ' read -r -a layers <<< "$value"
    [[ ${layers[0]:-} == 413091 ]] || return 1
    value="413091, $target, $other"
    for layer in "${layers[@]:1}"; do
        [[ $layer == "$target" || $layer == "$other" ]] || value+=", $layer"
    done
    xprop -root -f "$focus_order" 32co -set "$focus_order" "$value" &&
        wait_for 5 focus_is "$target"
}

vrcmd() {
    timeout 4 env LD_LIBRARY_PATH="$vr_bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$vr_bin/vrcmd" "$@" 2>/dev/null
}

link_state() {
    local pid=$1
    [[ -r $link_log ]] || return 0
    awk -v pid="$pid" '
        / - vrserver .* startup with PID=/ {
            current = index($0, "startup with PID=" pid ",") > 0
            state = ""
        }
        current && / - Connection active at / { state = "active" }
        current && / - (Connection inactive at |SVLRoot::Shutdown\(\) start)/ { state = "inactive" }
        END { print state }
    ' "$link_log"
}

frame_connected() {
    local pid devices
    pid=$(pgrep -xo vrserver) || return 1
    [[ $(link_state "$pid") == active ]] || return 1
    devices=$(vrcmd --info) || return 1
    [[ $devices == *'Deckard MP by Valve driver SL'* ]]
}

squadrons_rendering() {
    local stats
    stats=$(vrcmd --stats) || return 1
    grep -Eq '"key"[[:space:]]*:[[:space:]]*"steam\.app\.1222730"' <<< "$stats" &&
        grep -Eq '"frame_submits"[[:space:]]*:[[:space:]]*[1-9]' <<< "$stats" &&
        focusable "$app"
}

game_exited() {
    ! pgrep -x starwarssquadro >/dev/null && ! focusable "$app"
}

squadrons_scope() {
    systemctl --user list-units --type=scope --state=running --plain --no-legend \
        "app-steam-app$app-*.scope" | awk '{ print $1 }'
}

return_to_tv() {
    local focused
    focused=$(root_property GAMESCOPE_FOCUSED_APP) || return 0
    if [[ $focused == "$app" || $focused == "$steamvr" ]]; then
        focus "$big_picture" "$steamvr"
    fi
}

end_session() {
    local pid=$1 apps id scope

    printf 'Steam Frame stream disconnected. Closing Squadrons.\n'
    if ! game_exited; then
        if ! "$HOME/.local/bin/squadrons-game-quit" || ! wait_for 15 game_exited; then
            return_to_tv || true
            fail 'Squadrons did not finish closing. Returned control to Steam Gaming Mode.'
        fi
    fi

    apps=$(root_property GAMESCOPE_FOCUSABLE_APPS) || return 0
    for id in ${apps//,/ }; do
        if [[ $id != "$app" && $id != "$steamvr" && $id != "$big_picture" ]]; then
            printf 'Another app is open. Leaving its SteamVR session available.\n'
            return 0
        fi
    done

    if [[ -r /proc/$pid/cgroup ]]; then
        scope=$(sed -nE 's|.*/(app-steam-app250820-[0-9]+\.scope)(/.*)?$|\1|p' "/proc/$pid/cgroup" 2>/dev/null || true)
        if [[ -n $scope ]] && ! systemctl --user stop "$scope"; then
            return_to_tv || true
            fail 'Squadrons closed, but SteamVR did not finish closing.'
        fi
    fi
    return_to_tv
    printf 'Squadrons closed and Steam Gaming Mode has focus.\n'
}

watch_session() {
    local pid=$1 scope=$2 current current_scope state disconnected_at=
    exec 9>"$XDG_RUNTIME_DIR/squadrons-vr.lock"
    while :; do
        current=$(pgrep -xo vrserver || true)
        [[ -z $current || $current == "$pid" ]] || return 0
        if [[ -z $current ]]; then
            game_exited && return 0
            state=inactive
        else
            state=$(link_state "$pid")
        fi

        case $state in
            active) disconnected_at= ;;
            inactive)
                if [[ -z $disconnected_at ]]; then
                    disconnected_at=$SECONDS
                elif (( SECONDS - disconnected_at >= disconnect_grace )) && flock -n 9; then
                    current=$(pgrep -xo vrserver || true)
                    if [[ -z $current || $current == "$pid" && $(link_state "$pid") == inactive ]]; then
                        current_scope=$(squadrons_scope)
                        [[ -z $current_scope || $current_scope == "$scope" ]] || return 0
                        end_session "$pid"
                        return
                    fi
                    flock -u 9
                fi
                ;;
        esac
        sleep 1
    done
}

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
display_config="$XDG_RUNTIME_DIR/gamescope-environment"
[[ -r $display_config ]] || fail 'Start Gaming Mode on the Steam Machine first.'
DISPLAY=$(sed -n 's/^DISPLAY=\(:[0-9][0-9]*\)$/\1/p' "$display_config")
[[ -n $DISPLAY ]] || fail 'Could not find the active Gamescope display.'
export DISPLAY
focusable "$big_picture" || fail 'Steam Gaming Mode is still starting.'
[[ -x $vr_bin/vrcmd ]] || fail 'SteamVR is missing from the default Steam library.'

if [[ ${1:-} == --watch ]]; then
    [[ $# -eq 3 && $2 =~ ^[1-9][0-9]*$ && $3 =~ ^app-steam-app1222730-[0-9]+\.scope$ ]] \
        || fail 'Expected a SteamVR process ID and a Squadrons app scope.'
    watch_session "$2" "$3"
    exit
fi

controller=${1:-auto}
[[ $# -le 1 && $controller =~ ^(auto|frame|steam)$ ]] || fail 'Choose auto, frame, or steam.'

exec 9>"$XDG_RUNTIME_DIR/squadrons-vr.lock"
flock -n 9 || fail 'A Squadrons VR launch is already in progress.'

if ! pgrep -x vrserver >/dev/null; then
    printf 'Starting SteamVR on the Steam Machine.\n'
    timeout 15 steam 'steam://run/250820'
fi
printf 'Waiting for the Steam Frame to connect.\n'
wait_for 45 frame_connected || fail 'SteamVR did not see the Frame. Wake the headset and try again.'

if ! focusable "$app" && ! pgrep -x starwarssquadro >/dev/null; then
    printf 'Launching Squadrons in SteamVR mode.\n'
    timeout 15 steam "steam://launch/$app/VR"
fi
wait_for 120 squadrons_rendering || fail 'Squadrons did not start rendering in VR.'

if ! focus_is "$app"; then
    wait_for 10 focusable "$steamvr" || fail 'The SteamVR window is unavailable.'
    focus "$steamvr" "$app" || fail 'Could not focus SteamVR in Gamescope.'
    focus "$app" "$steamvr" || fail 'Could not focus Squadrons in Gamescope.'
fi

vr_pid=$(pgrep -xo vrserver)
game_scope=$(squadrons_scope)
if [[ $game_scope =~ ^app-steam-app1222730-([0-9]+)\.scope$ ]]; then
    watch_unit="squadrons-vr-session-$vr_pid-${BASH_REMATCH[1]}"
    if ! systemctl --user is-active --quiet "$watch_unit.service"; then
        systemd-run --user --quiet --collect --no-block --unit="$watch_unit" \
            "$HOME/.local/bin/squadrons-vr" --watch "$vr_pid" "$game_scope"
    fi
else
    printf 'Could not identify the Squadrons app scope for automatic cleanup.\n' >&2
fi

if [[ $controller != auto ]]; then
    "$HOME/.local/bin/squadrons-select-controller" "$controller"
fi
printf 'Squadrons is rendering in VR and has game focus.\n'
