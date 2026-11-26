# Squadrons VR for Steam Machine + Steam Frame

Launch STAR WARS: Squadrons in SteamVR on a Steam Machine and stream it to a Steam Frame using Steam's built-in Remote Play. The two shortcuts select which controller is assigned to player one:

- **Squadrons VR (Frame Controllers)**
- **Squadrons VR (Steam Controller)**

The Frame connects through its Steam Frame adapter and streams from the Machine's Steam library. The launcher does not require SSH between the devices.

## Requirements

- Steam Machine running SteamOS in Gaming Mode, with Squadrons and SteamVR installed in the default Steam library.
- Steam Frame paired with the Machine in Steam Remote Play, and the Frame's VR streaming/link connection working.
- Python 3 and `aiohttp` available on the Machine for controller selection.
- A SteamOS account whose home directory is `/home/deck` (the desktop shortcuts use that standard SteamOS path).

## Install on the Steam Machine

Copy the four programs into the Machine user's local bin directory:

```sh
mkdir -p ~/.local/bin
install -m 755 squadrons-machine-vr.sh ~/.local/bin/squadrons-vr
install -m 755 squadrons-steam-request.sh ~/.local/bin/squadrons-steam-request
install -m 755 squadrons-select-controller.py ~/.local/bin/squadrons-select-controller
install -m 755 squadrons-game-quit.py ~/.local/bin/squadrons-game-quit
```

Add `squadrons-native-frame.desktop` and `squadrons-native-steam.desktop` to Steam as non-Steam games on the Machine. In Steam, use **Add a Game → Add a Non-Steam Game**, browse to each desktop file, and add them. The shortcuts use `/home/deck/.local/bin/squadrons-steam-request`.

On the Frame, open the Machine's library entry and choose **Stream** for the desired shortcut. This uses Steam's normal Remote Play controls and does not install a launcher on the Frame.

## How it works

The shortcut queues the VR launch a few seconds after Steam starts its non-Steam entry. The main launcher waits for the Frame's VR link, starts SteamVR if needed, launches Squadrons in VR, and focuses the game in Gamescope. The selected controller is moved to Steam Input player one. Wake the selected controller before starting if it has gone to sleep.

If the Frame link remains disconnected for 15 seconds, a session watcher asks Squadrons to close normally, closes the leftover SteamVR session when safe, and returns Gamescope to Steam. A brief disconnect that reconnects within that window does not end the session. Headset standby alone does not trigger cleanup.

The scripts target the tested SteamOS Gaming Mode setup. They use Gamescope properties and SteamVR's local `vrcmd` interface, so other SteamOS versions or library layouts may need adjustments.
