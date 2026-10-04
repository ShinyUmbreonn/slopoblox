"""Optional host OpenGL-over-Vulkan rendering through Mesa Zink.

Roblox still uses its macOS OpenGL renderer. Zink translates that renderer
to Vulkan on Linux; Darling's incomplete Metal path stays disabled.
"""
import ctypes
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import threading

RENDERERS = ("opengl", "vulkan")
_dependency_lock = threading.Lock()


def mesa_egl_manifest():
    return next((Path(root) / "glvnd/egl_vendor.d/50_mesa.json"
                 for root in ("/usr/share", "/usr/local/share", "/etc", "/app/share")
                 if (Path(root) / "glvnd/egl_vendor.d/50_mesa.json").is_file()), None)


def missing_vulkan_dependencies():
    missing = []
    if mesa_egl_manifest() is None:
        missing.append("Mesa EGL")
    roots = ("/usr/lib", "/usr/lib64", "/usr/lib/x86_64-linux-gnu", "/usr/local/lib",
             "/usr/local/lib64", "/app/lib", "/app/lib/x86_64-linux-gnu",
             "/usr/lib/x86_64-linux-gnu/GL/default/lib", "/usr/lib/GL/default/lib")
    extra = os.environ.get("LIBGL_DRIVERS_PATH", "").split(":")
    paths = [Path(root) / "dri/zink_dri.so" for root in roots]
    paths.extend(Path(root) / "zink_dri.so" for root in extra if root)
    if not any(path.is_file() for path in paths):
        missing.append("Zink")
    return missing


def _system_program(name):
    # Package managers execute as root: use system directories rather than a
    # launcher process's possibly customized PATH.
    return next((str(Path(root) / name) for root in ("/usr/bin", "/bin", "/usr/sbin", "/sbin")
                 if (Path(root) / name).is_file() and os.access(Path(root) / name, os.X_OK)), None)


def _askpass_program():
    configured = os.environ.get("SUDO_ASKPASS", "")
    if os.path.isabs(configured) and Path(configured).is_file() and os.access(configured, os.X_OK):
        return configured
    for name in ("ksshaskpass", "ssh-askpass"):
        executable = _system_program(name)
        if executable:
            return executable
    return next((path for path in ("/usr/lib/ssh/ssh-askpass", "/usr/libexec/openssh/ssh-askpass",
                                  "/usr/lib/openssh/gnome-ssh-askpass", "/usr/lib/gcr-ssh-askpass",
                                  "/usr/lib/gcr4-ssh-askpass", "/usr/lib/git-core/git-gui--askpass")
                 if Path(path).is_file() and os.access(path, os.X_OK)), None)


def _authenticated_install_command(command):
    """Choose one available prompt. Never retry after denied authentication."""
    run0 = _system_program("run0")
    if run0:
        # Default interactive polkit authentication enables the desktop prompt.
        return [run0, "--description=Install Mac O' Blox Vulkan dependencies", "--", *command], {}
    pkexec = _system_program("pkexec")
    if pkexec:
        return [pkexec, *command], {}
    sudo = _system_program("sudo")
    if sudo:
        askpass = _askpass_program()
        if askpass:
            # sudo reads the helper's output directly; the launcher never sees
            # or stores the password.
            return [sudo, "-A", "--", *command], {"SUDO_ASKPASS": askpass}
        terminals = (("gnome-terminal", ["--wait", "--"]),
                     ("konsole", ["--separate", "-e"]),
                     ("xfce4-terminal", ["--disable-server", "--execute"]),
                     ("kitty", ["--"]), ("alacritty", ["-e"]),
                     ("foot", ["--"]), ("xterm", ["-e"]))
        for name, arguments in terminals:
            terminal = _system_program(name)
            if terminal:
                return [terminal, *arguments, sudo, "--", *command], {}
    raise RuntimeError("No administrator prompt is available. Install run0 or pkexec, or sudo with a graphical askpass helper or terminal, then select Vulkan again. You can also install Mesa EGL and Zink manually.")


def vulkan_install_command():
    """Return (argv, environment overrides), using fixed package arguments."""
    if Path("/.flatpak-info").is_file():
        raise RuntimeError("Mesa EGL and Zink come from the Flatpak graphics runtime. Update the Flatpak runtime and try again.")
    try:
        release = platform.freedesktop_os_release()
    except OSError:
        release = {}
    family = {release.get("ID", ""), *release.get("ID_LIKE", "").split()}
    choices = (({"arch"}, "pacman", ["-S", "--needed", "--noconfirm", "mesa", "vulkan-icd-loader"]),
               ({"debian", "ubuntu"}, "apt-get", ["install", "-y", "--no-install-recommends", "libegl-mesa0", "libgl1-mesa-dri", "libvulkan1"]),
               ({"fedora", "rhel"}, "dnf", ["install", "-y", "mesa-libEGL", "mesa-dri-drivers", "vulkan-loader"]))
    identified = any(family & ids for ids, _manager, _arguments in choices)
    for ids, manager, arguments in choices:
        executable = _system_program(manager)
        if executable and (family & ids or not identified):
            return _authenticated_install_command([executable, *arguments])
    raise RuntimeError("Automatic Vulkan dependency installation supports Arch, Debian/Ubuntu and Fedora. Install Mesa EGL and Zink with your package manager.")


def ensure_vulkan_dependencies():
    """Install only when files are missing; check again after authentication."""
    with _dependency_lock:
        if not missing_vulkan_dependencies():
            return False
        command, auth_environment = vulkan_install_command()
        result = subprocess.run(command, env={**os.environ, **auth_environment},
                                stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if result.returncode:
            detail = "\n".join(part.strip() for part in (result.stderr, result.stdout) if part.strip())[-1500:]
            raise RuntimeError("Vulkan dependencies were not installed. Authentication may have been cancelled.\n" + detail)
        missing = missing_vulkan_dependencies()
        if missing:
            raise RuntimeError("Installation finished, but these dependencies are still missing: " + ", ".join(missing))
        return True


def mangohud_environment(renderer, enabled=False):
    """Enable the Vulkan layer or the shim's direct host EGL overlay hook.

    Avoid OpenGL LD_PRELOAD: Darling strips it from host commands, and
    forwarding MangoHud's dlsym hook to the guest can select software GL.
    Explicit terminal options remain available alongside the Settings switch.
    """
    variables = {name: os.environ[name] for name in
                 ("MANGOHUD", "MANGOHUD_CONFIG", "MANGOHUD_CONFIGFILE") if name in os.environ}
    if enabled:
        variables["MANGOHUD"] = "1"
    if variables.get("MANGOHUD") == "1" and renderer == "opengl":
        roots = ("/usr/lib/mangohud", "/usr/lib64/mangohud",
                 "/usr/lib/x86_64-linux-gnu/mangohud", "/usr/local/lib/mangohud",
                 "/usr/local/lib64/mangohud", "/app/lib/mangohud",
                 "/app/lib/x86_64-linux-gnu/mangohud",
                 "/usr/lib/extensions/vulkan/MangoHud/lib/mangohud",
                 "/usr/lib/extensions/vulkan/MangoHud/lib/x86_64-linux-gnu",
                 str(Path.home() / ".local/share/MangoHud/usr/lib/mangohud"))
        libraries = [Path(root) / "libMangoHud_opengl.so" for root in roots]
        custom = os.environ.get("MANGOHUD_OPENGL_LIBS")
        if custom:
            libraries[:0] = [Path(path) for path in custom.split(":") if path]
        library = next((path for path in libraries if path.is_file()), None)
        if library is None:
            raise RuntimeError("MangoHud's OpenGL library is missing. Install MangoHud or turn it off in Settings.")
        variables["MACOBLOX_MANGOHUD_OPENGL"] = str(library)
    return variables


def renderer_environment(renderer):
    if renderer == "opengl":
        return {}
    if renderer != "vulkan":
        raise ValueError(f"Unknown renderer: {renderer}")
    # GLVND would otherwise choose NVIDIA's EGL implementation, ignoring
    # Mesa's driver override entirely. These are host paths, also in Flatpak.
    manifest = mesa_egl_manifest()
    if manifest is None:
        raise RuntimeError("Vulkan (Zink) needs Mesa EGL and Zink. Install them or select OpenGL in Settings.")
    return {
        "MESA_LOADER_DRIVER_OVERRIDE": "zink",
        "GALLIUM_DRIVER": "zink",
        "__EGL_VENDOR_LIBRARY_FILENAMES": str(manifest),
        "EGL_PLATFORM": "x11",
        "MACOBLOX_METAL": "0",
    }


def validate_vulkan(environment):
    """Keep driver initialization (and a possible driver crash) out of GTK."""
    try:
        result = subprocess.run([sys.executable, str(Path(__file__)), "--probe"],
                                env=environment, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError("Vulkan (Zink) could not initialize. Select OpenGL in Settings.") from error
    try:
        data = json.loads(result.stdout)
    except ValueError:
        data = {}
    renderer = data.get("renderer", "")
    if result.returncode or not hardware_zink(renderer):
        reason = data.get("error") or renderer or "no working hardware Zink context"
        raise RuntimeError(f"Vulkan (Zink) is unavailable: {reason}. Select OpenGL in Settings.")
    return renderer


def hardware_zink(renderer):
    name = renderer.lower()
    return "zink" in name and not any(software in name for software in
                                      ("llvmpipe", "lavapipe", "softpipe", "software", "swiftshader"))


def _probe():
    """Exercise a real screen-visual window, core/compat and shared threads.

    Pbuffers can succeed when an EGL config cannot present to the X11 visual
    Darling uses. The worker also starts with EGL's default ES API, as a new
    Roblox render thread does; bind desktop GL separately on each thread.
    """
    egl, xlib = ctypes.CDLL("libEGL.so.1"), ctypes.CDLL("libX11.so.6")
    ptr, integer, uint = ctypes.c_void_p, ctypes.c_int, ctypes.c_uint

    def function(library, name, result, *arguments):
        fn = getattr(library, name)
        fn.restype, fn.argtypes = result, arguments
        return fn

    open_display = function(xlib, "XOpenDisplay", ptr, ctypes.c_char_p)
    close_display = function(xlib, "XCloseDisplay", integer, ptr)
    default_screen = function(xlib, "XDefaultScreen", integer, ptr)
    default_visual = function(xlib, "XDefaultVisual", ptr, ptr, integer)
    visual_id = function(xlib, "XVisualIDFromVisual", ctypes.c_ulong, ptr)
    root_window = function(xlib, "XRootWindow", ctypes.c_ulong, ptr, integer)
    create_window = function(xlib, "XCreateSimpleWindow", ctypes.c_ulong,
                             ptr, ctypes.c_ulong, integer, integer, uint, uint,
                             uint, ctypes.c_ulong, ctypes.c_ulong)
    map_window = function(xlib, "XMapWindow", integer, ptr, ctypes.c_ulong)
    destroy_window = function(xlib, "XDestroyWindow", integer, ptr, ctypes.c_ulong)
    sync = function(xlib, "XSync", integer, ptr, integer)
    get_display = function(egl, "eglGetDisplay", ptr, ptr)
    initialize = function(egl, "eglInitialize", integer, ptr, ptr, ptr)
    bind = function(egl, "eglBindAPI", integer, uint)
    choose = function(egl, "eglChooseConfig", integer, ptr, ptr, ptr, integer, ptr)
    config_attr = function(egl, "eglGetConfigAttrib", integer, ptr, ptr, integer, ptr)
    create_surface = function(egl, "eglCreateWindowSurface", ptr, ptr, ptr, ctypes.c_ulong, ptr)
    create_context = function(egl, "eglCreateContext", ptr, ptr, ptr, ptr, ptr)
    make_current = function(egl, "eglMakeCurrent", integer, ptr, ptr, ptr, ptr)
    swap = function(egl, "eglSwapBuffers", integer, ptr, ptr)
    get_proc = function(egl, "eglGetProcAddress", ptr, ctypes.c_char_p)
    destroy_context = function(egl, "eglDestroyContext", integer, ptr, ptr)
    destroy_surface = function(egl, "eglDestroySurface", integer, ptr, ptr)
    terminate = function(egl, "eglTerminate", integer, ptr)
    wayland_window = None
    if os.environ.get("MACOBLOX_WAYLAND") == "1":
        try:
            from .display import WaylandProbeWindow
        except ImportError:  # this file runs directly in the probe subprocess
            from display import WaylandProbeWindow
        wayland_window = WaylandProbeWindow()
    native = wayland_window.native if wayland_window else open_display(None)
    if not native:
        raise RuntimeError("X11 display is unavailable")
    display = surface = context = None
    window = 0
    initialized = False
    try:
        display = get_display(native)
        if not display or not initialize(display, None, None):
            raise RuntimeError("EGL could not initialize the selected window backend")
        initialized = True
        if not bind(0x30A2):  # EGL_OPENGL_API
            raise RuntimeError("desktop OpenGL is unavailable")
        # Match the real default visual, which the guest GL subwindow uses.
        screen = default_screen(native) if not wayland_window else 0
        required_visual = visual_id(default_visual(native, screen)) if not wayland_window else None
        attrs = (integer * 9)(0x3033, 5, 0x3040, 8, 0x3024, 8, 0x3025, 0, 0x3038)
        configs, count = (ptr * 256)(), integer()
        if not choose(display, attrs, configs, len(configs), ctypes.byref(count)) or not count.value:
            raise RuntimeError("no desktop OpenGL window EGL configuration")
        config = None
        for candidate in configs[:min(count.value, len(configs))]:
            if wayland_window:
                config = candidate
                break
            value = integer()
            if config_attr(display, candidate, 0x302E, ctypes.byref(value)) and value.value == required_visual:
                config = candidate
                break
        if not config:
            raise RuntimeError("no EGL window config matches the X11 screen visual")
        window = wayland_window.surface if wayland_window else create_window(
            native, root_window(native, screen), 0, 0, 16, 16, 0, 0, 0)
        if not window:
            raise RuntimeError("could not create an X11 test window")
        if not wayland_window:
            map_window(native, window)
            sync(native, 0)
        surface = create_surface(display, config, window, None)
        if not surface:
            raise RuntimeError("could not create an EGL window surface for the screen visual")

        def gl_function(name, result, *arguments):
            address = get_proc(name.encode())
            if not address:
                raise RuntimeError(f"{name} is unavailable")
            return ctypes.CFUNCTYPE(result, *arguments)(address)

        get_string = gl_function("glGetString", ctypes.c_char_p, uint)
        clear_color = gl_function("glClearColor", None, ctypes.c_float, ctypes.c_float,
                                  ctypes.c_float, ctypes.c_float)
        clear = gl_function("glClear", None, uint)
        read_pixels = gl_function("glReadPixels", None, integer, integer, integer, integer, uint, uint, ptr)
        get_error = gl_function("glGetError", uint)
        gen_textures = gl_function("glGenTextures", None, integer, ptr)
        bind_texture = gl_function("glBindTexture", None, uint, uint)
        is_texture = gl_function("glIsTexture", ctypes.c_ubyte, uint)
        delete_textures = gl_function("glDeleteTextures", None, integer, ptr)
        core_attrs = (integer * 7)(0x3098, 4, 0x30FB, 1, 0x30FD, 1, 0x3038)
        renderer = ""

        def present():
            clear_color(0.25, 0.5, 0.75, 1.0)
            clear(0x4000)  # GL_COLOR_BUFFER_BIT
            pixel = (ctypes.c_ubyte * 4)()
            read_pixels(0, 0, 1, 1, 0x1908, 0x1401, pixel)  # RGBA/UNSIGNED_BYTE
            if get_error() or any(abs(pixel[i] - expected) > 2 for i, expected in enumerate((64, 128, 191))):
                raise RuntimeError("EGL window rendering/readback failed")
            if not swap(display, surface):
                raise RuntimeError("EGL window presentation failed")

        for attributes in (None, core_attrs):
            context = create_context(display, config, None, attributes)
            if not context or not make_current(display, surface, surface, context):
                raise RuntimeError("Darling needs compatibility and OpenGL 4.1 core window contexts")
            renderer = (get_string(0x1F01) or b"").decode(errors="replace")
            if not hardware_zink(renderer):
                raise RuntimeError(f"expected hardware Zink, got {renderer or 'no renderer'}")
            present()
            if attributes is None:
                make_current(display, None, None, None)
                destroy_context(display, context)
                context = None
        texture = uint()
        gen_textures(1, ctypes.byref(texture))
        bind_texture(0x0DE1, texture.value)
        make_current(display, None, None, None)
        failures = []

        def worker():
            shared = None
            try:
                if not bind(0x30A2):
                    raise RuntimeError("desktop OpenGL API could not be bound on the render thread")
                shared = create_context(display, config, context, core_attrs)
                if not shared or not make_current(display, surface, surface, shared):
                    raise RuntimeError("shared core context could not become current on the render thread")
                if not is_texture(texture.value):
                    raise RuntimeError("OpenGL objects were not shared with the render thread")
                present()
            except Exception as error:
                failures.append(error)
            finally:
                make_current(display, None, None, None)
                if shared:
                    destroy_context(display, shared)

        thread = threading.Thread(target=worker, name="MacOBlox EGL probe")
        thread.start()
        thread.join()  # the parent subprocess timeout covers driver hangs
        if failures:
            raise failures[0]
        if not bind(0x30A2) or not make_current(display, surface, surface, context):
            raise RuntimeError("main-thread core context could not be restored")
        delete_textures(1, ctypes.byref(texture))
        return {"renderer": renderer, "window_presentation": True, "shared_thread_context": True}
    finally:
        if initialized:
            make_current(display, None, None, None)
            if context:
                destroy_context(display, context)
            if surface:
                destroy_surface(display, surface)
            terminate(display)
        if wayland_window:
            wayland_window.close()
        else:
            if window:
                destroy_window(native, window)
            close_display(native)


if __name__ == "__main__":
    try:
        print(json.dumps(_probe()))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
