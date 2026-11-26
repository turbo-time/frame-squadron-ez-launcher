#!/usr/bin/env python3
import argparse
import asyncio
import json
import sys
from urllib.parse import urlsplit

import aiohttp


CONTROLLERS = {"frame": "Steam Frame Controllers", "steam": "Steam Controller"}
STEAM_UI = "http://127.0.0.1:8080"


async def select_controller(name):
    # Use the same Steam Input operation as the Reorder Controllers dialog.
    expression = """
        (async (name) => {
            const deadline = Date.now() + 15000;
            let nextSwap = 0;
            while (Date.now() < deadline) {
                const controller = ControllerStore.GetControllers().find(c => c.strName === name);
                const slot = controller?.nXInputIndex;
                if (slot === 0) return true;
                if (Number.isInteger(slot) && slot > 0 && slot <= 15 && Date.now() >= nextSwap) {
                    SteamClient.Input.SwapControllerOrder(slot, 0);
                    nextSwap = Date.now() + 1500;
                }
                await new Promise(resolve => setTimeout(resolve, 250));
            }
            return false;
        })(%s)
    """ % json.dumps(name)

    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as session:
        async with session.get(f"{STEAM_UI}/json/list") as response:
            response.raise_for_status()
            targets = await response.json(content_type=None)
        context = next((target for target in targets if target.get("title") == "SharedJSContext"), None)
        if context is None:
            raise RuntimeError("Steam's shared UI context is unavailable.")
        socket_path = urlsplit(context["webSocketDebuggerUrl"]).path
        async with session.ws_connect(f"{STEAM_UI}{socket_path}") as socket:
            await socket.send_json({
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {"expression": expression, "awaitPromise": True, "returnByValue": True},
            })
            async for message in socket:
                reply = message.json()
                if reply.get("id") != 1:
                    continue
                data = reply.get("result", {})
                if "error" in reply or "exceptionDetails" in data:
                    raise RuntimeError("Steam could not change the controller order.")
                return data.get("result", {}).get("value") is True
    raise RuntimeError("Steam closed the controller connection.")


def main():
    parser = argparse.ArgumentParser(description="Select player one for Squadrons in Steam Input.")
    parser.add_argument("controller", choices=CONTROLLERS)
    name = CONTROLLERS[parser.parse_args().controller]
    try:
        ready = asyncio.run(asyncio.wait_for(select_controller(name), timeout=22))
    except (aiohttp.ClientError, RuntimeError, TimeoutError) as error:
        print(f"Could not select {name}. {error}", file=sys.stderr)
        return 1
    if not ready:
        print(f"Wake the {name} and choose the launcher again.", file=sys.stderr)
        return 1
    print(f"Player one is now {name}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
