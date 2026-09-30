#!/usr/bin/env python3
"""Disable Roblox's startup render throttle.

The macOS client registers a slow render frequency during startup and
re-applies it when the RenderJob is created, expecting to lift it when the
preRenderJob reports back. Under Darling the preRenderJob is never created
("setStartupThrottle: preRenderJob is null"), so the menu renders at ~3 FPS
until the throttle's 10-second safety timeout fires. (On real Macs the Metal
path compiles shaders on two threads, which wins that race; the GL path we
use compiles for ~850 ms on one thread and loses it.)

The patch makes the throttle argument read as false inside
RenderJob::setStartupThrottle, so the slow frequency is never applied:

    mov ebx, esi   ->   xor ebx, ebx

The site is located by pattern on every run, so a client update just needs
the same code shape; when the shape is not found the patch is skipped. Two
log calls of that function must both match around the site (the throttle
value at Warning level and the null preRenderJob at Error level), which
keeps look-alike compiler idioms elsewhere in the binary from matching.
"""

import re
import sys
from pathlib import Path

BUNDLE = Path(sys.argv[1]) if len(sys.argv) > 1 else (
    Path(__file__).parent / "RobloxPlayer.app" / "Contents" / "MacOS" / "RobloxPlayer")

# mov ebx, esi; mov r14, rdi — the throttle argument and this-pointer move
# right after RenderJob::setStartupThrottle's prologue.
ARG_MOVES = re.compile(rb"\x89\xf3\x49\x89\xfe")
ALREADY_PATCHED = re.compile(rb"\x31\xdb\x49\x89\xfe")
PROLOGUE = re.compile(rb"\x55\x48\x89\xe5")
# Inside the same function: the "RenderJob::setStartupThrottle: {}" log call
# (r8d = 0x4e characters, edx = 3, Warning) ...
VALUE_LOG = re.compile(
    rb"\x41\xb8\x4e\x00\x00\x00\xba\x03\x00\x00\x00\x41\xb9\x01\x00\x00\x00")
# ... and the "preRenderJob is null" one (r8d = 0x55, edx = 2, Error).
NULL_LOG = re.compile(
    rb"\x41\xb8\x55\x00\x00\x00\xba\x02\x00\x00\x00\x41\xb9\x01\x00\x00\x00")
SEARCH_BACK = 0x600


def find_patch_offset(data: bytes):
    """Offset of the mov ebx, esi pair in RenderJob::setStartupThrottle.

    A candidate pair of argument moves only counts when a function prologue
    precedes it and both log calls of setStartupThrottle follow within the
    function."""
    for site in NULL_LOG.finditer(data):
        start = site.start()
        window_start = max(0, start - SEARCH_BACK)
        window = data[window_start:start]
        moves = [m.start() for m in ARG_MOVES.finditer(window)
                 if PROLOGUE.search(window[max(0, m.start() - 0x20):m.start()])]
        for move in reversed(moves):
            body = data[window_start + move:start + 64]
            if VALUE_LOG.search(body) and NULL_LOG.search(body):
                return window_start + move
    return None


def main() -> int:
    if not BUNDLE.exists():
        print(f"no client at {BUNDLE}, nothing to patch")
        return 0
    data = bytearray(BUNDLE.read_bytes())
    offset = find_patch_offset(bytes(data))
    if offset is None:
        # The argument moves may already read xor ebx, ebx from an earlier run.
        blob = bytes(data)
        for site in NULL_LOG.finditer(blob):
            start = site.start()
            window_start = max(0, start - SEARCH_BACK)
            window = blob[window_start:start]
            moves = [m.start() for m in ALREADY_PATCHED.finditer(window)
                     if PROLOGUE.search(window[max(0, m.start() - 0x20):m.start()])]
            for move in reversed(moves):
                body = blob[window_start + move:start + 64]
                if VALUE_LOG.search(body) and NULL_LOG.search(body):
                    print("startup render throttle already disabled")
                    return 0
        print("startup throttle pattern not found in this client, skipping")
        return 0
    data[offset:offset + 2] = b"\x31\xdb"  # mov ebx, esi -> xor ebx, ebx
    BUNDLE.write_bytes(bytes(data))
    print(f"startup render throttle disabled (patched at 0x{offset:x})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
