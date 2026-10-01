# MacOBlox

Roblox Client for macOS (x86_64) on Linux via Darling. As of
2026-09-23: The main menu, login (Quick Login), avatar, and games are working.

## Launch

Launcher: `launcher/install.sh` adds the “Mac O Blox” entry to the Applications menu
and the `macoblox` command. That includes game launching, fast flags, and DNS specifically for Roblox,
Camera sensitivity, client update, diagnostics. The settings are located in
`~/.config/macoblox/settings.json`, logs in `logs/`.

Priorities: Darling runs with a nice value of −4, while darlingserver, the Darling daemons, and
pw-cat inherits the launcher's nice value (+10 if the desktop launches it that way) and
They remain idle while the game uses all the cores. The launcher starts darlingserver with
daemons to -5 and pw-cat to -11, as far as RLIMIT_NICE allows.

## What does the shim (build/libMacOBloxShims.dylib) do?

`build_debug_shim.sh` is built from:

- `libMacOBloxShims.m` — AppKit/GL/input: returns the GL context after
  CALayerContext, macOS-style mouse button numbers, mouse capture for the camera,
  cursors, missing methods for NSEvent/NSTextView/NSButton/CNContactStore,
  a cookie saved to disk (`~/Library/MacOBlox/Cookies.plist` inside
  the Darling prefix), hiding the menu bar, window icon.
- `missing_symbols.c` — functions that Roblox imports but Darling does not.
- `net_trace.c` — reliable UDP reception and a watchdog for frozen RakNet threads.
- `darling_fixes.c` — mutexes without Darling wake-up losses; `usleep` and
  `nanosleep` run directly on Linux (in Darling, each one involves two requests to `darlingserver`).
- `memory_stats.c` — system and game memory (`phys_footprint` for “Mem”).
- `thread_kick.c` — “kick” (SIGURG) for threads stuck waiting for Darling:
  UDP watchdog and long mutex waits; the location of the deadlock is logged.
- `xfixes_raw.c` — hiding the cursor via XFixes over its own X11 socket.
- `dns_override.c` — DNS for Roblox via the launcher’s local proxy.
- `xattr_compat.c`, `exit_compat.c` — from previous stages.

The `MACOBLOX_*` variables (tracing, DNS, sensitivity) are set by
the launcher. `run_debug.sh` is still there for manual debugging.

## Important Note About Darling

Do not delete or modify files in `~/.darling` from the host while
darlingserver is running: the Darling overlay will stop showing new files to the host.
Delete files from within the shell (`darling shell rm ...`) or while the server is stopped.

## History

## Diagnostic Run

From a regular Linux terminal:

```bash
cd MacOBlox
./run_debug.sh
```

The script compiles the library from `libMacOBloxShims.m` in `build/`, launches
the client from the project folder within an existing Darling prefix, and writes
the output to a separate file in `logs/launch-*.log`. Arguments are passed to the client.
The launch itself requires a running Darling outside the restricted Codex environment.
The launch script has not yet been tested in a running Darling instance.

Build only: `./build_debug_shim.sh`. You can set `DARLING_SYSROOT`.
The old libraries in the root directory and inside `.app` are preserved; the new one is selected
via `DYLD_INSERT_LIBRARIES` and `DYLD_LIBRARY_PATH`.

## Changes 2026-09-21

- Fixed the signature for intercepting `NSWindow initWithContentRect:…`:
  the rectangle is passed by value, and the flag uses the x86_64 BOOL ABI.
  Signature: https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:)
- Removed the call to the assumed `what()` method for arbitrary C++ exceptions.
  A discarded object does not necessarily have a virtual function table.
- Separate scripts for building and diagnostic runs have been added.
- The source code and old library are stored in `backups/before-codex-20260921/`.
- Cross-compilation was successful; shell script syntax has been verified.
- The Codex environment launch test stops in Darling before Roblox starts:
  `binary is not setuid root, which is mandatory`. In this environment, the owner
  of the system binary is listed as nobody. This does not prove that the
  installation on the host is broken and is not a reason to change system permissions.

## Changes 2026-09-26

Verified using a test suite under Darling (network, mutexes, waits, sound,
cookies); the old build fails the new tests, while the new one passes them all.

- Timeout waits in Darling return 0 instead of ETIMEDOUT (100 ms
  wait — 0 after 100 ms). Therefore, the wait intervals in `darling_fixes.c`
  never increased (each 50-ms interval — a request to darlingserver), and
  the caller never saw a timeout. Now, the elapsed time is determined by the clock;
  for `pthread_cond_timedwait_relative_np` (which Roblox imports), the time
  of segments already waited out is subtracted; otherwise, waits longer than a second
  would never end.
- kqueue: Roblox closes sockets using `close$NOCANCEL` without EV_DELETE, and
  the socket entry remained: the next socket with the same number received
  events from the old owner (the thread loops, a use-after-free is possible in
  Asio). `close`/`close$NOCANCEL` have been intercepted; entries are checked against the inode.
- The “is there data” check is now done via `poll` instead of `recv(MSG_PEEK)`:
  any receive operation, even a peek, triggers a socket error (ICMP “port unreachable”),
  and after that, `recv(MSG_DONTWAIT)` on a blocking socket would hang indefinitely.
- UDP watchdog ping—only for network sockets (AF_INET/AF_INET6), not for
  local pairs where threads wake each other up; a thread waiting on a mutex
  is checked again before the ping.
- Cookies: `cookiesForURL:` Darling ignores the URL, and `setCookies:forURL:…`
  does nothing. Storage is now managed internally: domain, path, Secure, and expiration
  are checked (login credentials no longer leak to third-party hosts or via HTTP), the new
  value replaces the old one, file writing is atomic, set to 0600 immediately; session
  cookies are in memory only; a foreign domain in Set-Cookie is rejected.
- Event queue: “no event” — type 100, same as in Darling (NSApplication
  compares it to 0x64). Type 13 was a real event at point (0,0).
- Keys: On FocusOut, the table of pressed keys is reset (Alt+Tab with
  W held down no longer leaves it “pressed” for CGEventSourceKeyState).
- Mouse capture: while our warp is running, movement events are not merged; if
  movement from the warp never arrives, centering resumes after 8
  events (previously it was disabled until the end of capture).
- The XFixes stream sleeps on the pipe instead of polling every 5 ms via usleep
  Darling (400 requests to darlingserver per second); it starts at launch.
- getaddrinfo: pause between attempts without blocking, retry only in case of
  temporary errors, waiting via direct Linux sleeps.
- Exception handlers, `makeCurrentContext`, `flushBuffer`: `getenv` and `dlsym` are called once,
  rather than for every `throw` or frame (Lua errors in games are C++ exceptions).
- Shaders: the Mesa fix applies to all shaders (not just the
  first 8192); source code is stored only with `MACOBLOX_TRACE_GL=1`.
- `fast_libc.c`: SSE loops instead of `rep movsb/stosb` where those are slower
  (short copies, 4K aliasing, more L2), fast memchr/strlen/strcmp,
  memset_pattern4/8/16 have been reimplemented.
- `MACOBLOX_*=0` flags now mean “disabled.”

## Changes September 26, 2026, evening: locks without darlingserver

- In Darling, mutexes and conditional variables (psynch) are waited on via
  darlingserver: every capture under load, every wait, and every signal is
  a request to the server (40% of the game’s CPU usage); wake-ups are lost, and conditional
  variables break (the timeout arrives as a wake-up, the counters
  diverging, followed by “psync_cvwait; invalid sequence numbers” and EINVAL on
  every wait—12,874 times in 7 minutes in the server log).
- Now, in `darling_fixes.c`, a busy mutex waits on a Linux futex (the table
  at the mutex’s address, woken by `pthread_mutex_unlock`), while the condition variables
  are separate: a queue of waiters, each with its own futex; a signal wakes exactly one,
  a broadcast wakes exactly the number of waiters, and process signals do not interrupt the wait.
  Conditional variables created by Darling itself (tag ‘COND’/0x434F4E45,
  process-shared) remain its own. “Queue” test: 13.6 s and 18.5 s CPU
  darlingserver → 0.13 s and 0.04 s.
- `PTHREAD_MUTEX_USE_ULOCK=1` (libpthread mode using ulock) is not suitable:
  its condition variables call `__ulock_wait2` (syscall 544), which is not
  present in Darling—the process crashes on the first wait.
- Launcher: “Restart Darling” stops the entire container (launchd and
  daemons—which are not children of darlingserver and remained orphaned with ~250 MB), and upon
  startup, it terminates Darling processes without a running server and waits until
  the previous game closes (otherwise, both would share the same server and crash together).

## Changes 2026-09-27

- New launcher interface (PR #1 by TinyTosha) with refinements: a sidebar
  with a fallback option for libadwaita < 1.9, an FPS limit as a launcher setting
  (the launch script writes FramerateCap to GlobalBasicSettings_13.xml already inside
  Darling before the game starts), and launcher updates are now fast-forward only.
- Thread stacks (`darling_fixes.c`): Darling allocates 512 KB to a thread if the creator
  did not request more; the NVIDIA shader compiler used to overflow such a stack. Now
  the minimum is 8 MB, as in Linux, including threads without attributes and GCD worker threads
  (Darling creates them via `darling_thread_create` from the elfcalls table, which is
  wrapped). GCD worker threads did not reset the stack upon reuse
  (Darling jumps into `_start_wqthread` with the old stack pointer: +140 KB for
  every 250 tasks); the `start_wqthread` pointer in `__common` libsystem_kernel
  has been replaced with a jump that starts at the top of the stack.
- `CGDisplayScreenSize` (`gpu_info.c`): Darling returned the size in pixels as
  millimeters, and 0x0 for an unknown display ID; Roblox divides the width in pixels
  by it without checking (DPI = infinity), which caused
  infinite recursion in `updateSurfaceLuaApp` for a user on Fedora KDE. The size is now set to 96 DPI.
- Embedded Roblox web pages (password login with CAPTCHA, purchases, links):
  `web_bridge.m` replaces WKWebView with placeholders that use a Unix socket
  (`MACOBLOX_WEB_SOCKET`, JSON line-by-line) to the launcher window running
  WebKitGTK 6.0 (`launcher/macoblox/web.py`). Cookies are passed back and forth, so
  the client remains logged in after signing in on the page. The protocol and some of the code are from the
  spidercraft port (Roblox Mac Linux Port), with their permission. The replacement is applied only
  when the launcher is listening on the socket; without WebKitGTK, everything works as before. Site data is stored in
  `~/.config/macoblox/web`; clicking “Log Out” deletes it.
- New application ID `wtf.aubree.MacOBlox` (Flatpak, .desktop, MIME, launcher,
  packages); installers remove the old `xyz.narez.*` files. Version 0.15.
- Microphone for voice chat (`audio_hal.c`): Roblox treats the AUHAL unit as
  WebRTC—enables input on bus 1 (`kAudioOutputUnitProperty_EnableIO`),
  sets the client format (scope 2, element 1, typically 48 kHz mono float32), and
  the input callback (2005), within which `AudioUnitRender` retrieves frames.
  The shim reads float32 from the second FIFO (`MACOBLOX_AUDIO_INPUT_FIFO`, in 10 ms blocks
  into a ring buffer) and calls the callback for each block; `AudioUnitRender` on bus 1 outputs
  frames in the client’s format (float32/int16, interleaved or not). Recording on the host
  continues only as long as the game is listening: at startup, the shim writes the file `<fifo>.request`
  (“frequency, channels”), and the launcher (`HostAudio._keep_recording`, once per tick
  keep_playing) launches `pw-cat --record` (or `pacat`) with the Communication role;
  when stopped, the file is deleted and recording ends. `AVCaptureDevice
  authorizationStatusForMediaType:` and `requestAccessForMediaType:` (not present in Darling)
  return “allowed.” Verified by a test client in Darling: 290 callbacks in
  3 seconds, RMS 0.353 from a tone of 0.5 (0.354 was expected). In Darling, the process with the shim
  crashes after returning from `main` (and in the build before the microphone as well)—a separate
  exit issue that does not affect gameplay.
- Raw mouse motion for the lock (`raw_mouse.c`, "Raw motion" in the shim): the
  camera deltas during mouse lock come from XInput 2 raw events (device
  counts, before pointer acceleration, at the mouse's report rate; warps make
  none) instead of Darling's position-based deltas. Selected on the event
  loop's connection at the first X event after the lock (XISelectEvents from
  the host libXi through elfcalls), one mouse event per raw event merged with
  the last queued one; MotionNotify only keeps the pointer within 100 px of
  its anchor and is not delivered. Falls back to pointer deltas when XI2 is
  missing or no raw event arrives while the pointer moves. Launcher switch
  "Raw mouse input" (MACOBLOX_RAW_MOUSE=0). After spidercraft's RbxRawMotion.
  Verified in Darling against Xvfb: raw deltas equal the xdotool moves; the
  in-game camera is to be checked by hand. MACOBLOX_TRACE_XEVENTS=1 logs the
  first 80 X events reaching postXEvent:.
- Flatpak: “Cannot determine your user name” on startup. `darling` retrieves the
  username via `getpwuid(geteuid())`, and darling-noroot.so returns
  euid 0; there is no root entry in the Flatpak sandbox’s /etc/passwd, and the fallback
  `getlogin()` requires a loginuid, which some display managers do not set
  (darling#715). Now `getpwuid(0)` in darling/darlingserver returns the entry
  for the actual user.

## Changes 2026-10-01: the launcher as a desktop

The launcher's interface is redone after aubree.wtf (`launcher/macoblox/theme.py`
holds the look, `app.py` the new shell; every settings page keeps its widgets):

- Dark monochrome, square corners, no hue: state is filled against hollow,
  brightness, and a text label. Archivo for the interface, JetBrains Mono for
  titles and small facts; both ship in `launcher/macoblox/assets/fonts`
  (SIL OFL, cut down to the weights used) and are registered with Pango at
  start, so nothing is installed on the system.
- A top bar (`macoblox@darling`, the game's state, the time in the running
  game, a clock, the window buttons) over a "desktop": the play window and
  the menu window on the left, the open page in a window on the right
  (console, settings with its three tabs, mods, logs, info). Below 860 px
  the windows stack in one scrolling column, as on the site.
- The console replaces the old status page: each line is a check made just
  now (tools, Roblox, shim, Darling, sound, sign-in window, account), set as
  the unit lines of a boot console.
- The backdrop (`theme.Backdrop`) is a line field in the manner of the
  site's topology wallpaper: points follow a smooth flow field and leave
  marks in a grey bitmap shown as a texture. It draws in for about eight
  seconds (2 ms per 40 ms tick) and then stops; with animations turned off
  in the system it appears finished.
- The log viewer's highlighting is monochrome too (level by brightness and
  weight). The old sidebar and its `show_sidebar` setting are gone.
- For screenshots: `MACOBLOX_PAGE` (play, env, roblox, flags, mods, logs,
  info) and `MACOBLOX_WINDOW_SIZE=WxH`.

## What to Check Next

We need a recent startup log from a regular terminal. This will help determine where
the client is hanging: the loader, NIB loading, window creation, or rendering.
According to the owner’s recollection, the engine used to start up, but there was no image;
an old log confirming this has not yet been found.

There are still potential issues in the old code: some fatal signals
are suppressed, and the error handler manually parses the context and stack. These areas
require separate verification. Cocoa string constants have been updated to NSString.
`build_shims.py` is an old script that directly modifies the frameworks
in `~/.darling`; the new scripts do not run it automatically.
In `ffmpeg_compat/`, there are links between different ABI versions; compatibility
has not been verified, and a new build does not add this folder to the library path.

Accessing host files via `/Volumes/SystemRoot` is described in the documentation: 
https://docs.darlinghq.org/internals/basics/containerization.html

## Blocker on the host after lifting Codex restrictions

2026-09-21: The kernel was updated at 16:12 to 7.2.6-1-cachyos, but 7.2.0-1-cachyos is running. The module directory for the running kernel is missing; OverlayFS
is not registered in /proc/filesystems, and `modinfo overlay` fails.
This explains the `Cannot mount overlay: No such device` error before Roblox starts.
The update log confirms that the new kernel’s initramfs was successfully generated.
The next step is a normal reboot into the installed kernel, followed by running
`run_debug.sh`. An automatic reboot did not occur.
The script now detects this situation before Darling starts.

## Post-reboot check, September 21, 2026, 4:21–4:29 PM

Confirmed by log: MainMenu.nib loaded, RBXWindow created,
RobloxPlayerAppDelegate assigned, NSApplication run called.
Window/image display and game engine functionality NOT confirmed.

Next blocker: `Failed to initialize crash reporter`, std::runtime_error
from RobloxPlayer at return address 0x105606b21, called from 0x10002f4aa.
This was initially preceded by getxattr/setxattr errors. In xattr_compat.c
an adapter has been added only for org.chromium.crashpad.* and com.googlecode.crashpad.*:
Linux namespace user., access via fd, ENODATA is converted to ENOATTR.
Other names and non-zero position/options remain with Darling.
Data is actually written to the attributes; success is not faked.
After applying the adapter, xattr messages have disappeared, but the reporter initialization still
fails with an unspecified error. The cause of the subsequent crash has not been determined.
RobloxCrashHandler, using the same library, reaches the argument parsing stage
(`--crashCounter must be specified` when running --help); it does not load without the shim.

Logs: logs/touch-types.log (xattr errors), logs/xattr-compat.log (after the fix),
logs/crash-handler-with-shim.log. The launch time and exit code are also recorded
in separate logs/launch-*.log files.

The xattr test for a separate dylib and tests/xattr_compat_probe.c in Darling passed:
missing attribute, write/read, size query, small buffer,
missing path, passing an arbitrary name to the source function.
The original Roblox binary has not been modified. The libraries in the root directory and the .app file have been preserved;
the active build is located in build/.
