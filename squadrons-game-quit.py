#!/usr/bin/env python3
"""Send the normal window-close message to Squadrons in Gaming Mode."""

import ctypes as c
from pathlib import Path
import re
import subprocess
import sys


class ClientMessage(c.Structure):
    _fields_ = [
        ("type", c.c_int), ("serial", c.c_ulong), ("send_event", c.c_int),
        ("display", c.c_void_p), ("window", c.c_ulong),
        ("message_type", c.c_ulong), ("format", c.c_int), ("data", c.c_long * 5),
    ]


class XEvent(c.Union):
    _fields_ = [("client", ClientMessage), ("padding", c.c_long * 24)]


def request_close(display_name, window):
    xlib = c.CDLL("libX11.so.6")
    xlib.XOpenDisplay.argtypes = (c.c_char_p,)
    xlib.XOpenDisplay.restype = c.c_void_p
    xlib.XInternAtom.argtypes = (c.c_void_p, c.c_char_p, c.c_int)
    xlib.XInternAtom.restype = c.c_ulong
    xlib.XSendEvent.argtypes = (c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(XEvent))
    xlib.XCloseDisplay.argtypes = (c.c_void_p,)

    display = xlib.XOpenDisplay(display_name.encode())
    if not display:
        return False
    try:
        event = XEvent()
        protocols = xlib.XInternAtom(display, b"WM_PROTOCOLS", 0)
        event.client = ClientMessage(33, 0, 1, display, window, protocols, 32)
        event.client.data[0] = xlib.XInternAtom(display, b"WM_DELETE_WINDOW", 0)
        return bool(xlib.XSendEvent(display, window, 0, 0, c.byref(event)))
    finally:
        xlib.XCloseDisplay(display)


def main():
    window_property = subprocess.run(
        ["xprop", "-root", "GAMESCOPE_FOCUSABLE_WINDOWS"], capture_output=True, text=True,
    ).stdout
    fields = re.split(r",\s*", window_property.partition(" = ")[2].strip())
    windows = [
        int(window) for window, app, _ in zip(fields[::3], fields[1::3], fields[2::3])
        if app == "1222730" and window.isdecimal()
    ]
    displays = [f":{path.name[1:]}" for path in Path("/tmp/.X11-unix").glob("X*")
                if path.name[1:].isdecimal()]
    for window in windows:
        for display in displays:
            properties = subprocess.run(
                ["xprop", "-display", display, "-id", str(window), "STEAM_GAME", "WM_PROTOCOLS"],
                capture_output=True, text=True,
            ).stdout
            if (re.search(r"^STEAM_GAME\(CARDINAL\) = 1222730$", properties, re.MULTILINE)
                    and "WM_DELETE_WINDOW" in properties and request_close(display, window)):
                return 0
    print("Couldn't find a Squadrons window that accepts a normal quit request.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
