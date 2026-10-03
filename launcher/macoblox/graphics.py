"""Optional host OpenGL-over-Vulkan rendering through Mesa Zink.

Roblox still uses its macOS OpenGL renderer. Zink translates that renderer
to Vulkan on Linux; Darling's incomplete Metal path stays disabled.
"""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys

RENDERERS = ("opengl", "vulkan")


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
    manifests = [Path(root) / "glvnd/egl_vendor.d/50_mesa.json"
                 for root in ("/usr/share", "/usr/local/share", "/etc", "/app/share")]
    manifest = next((path for path in manifests if path.is_file()), None)
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
    """Check the X11 EGL path and both kinds of context Darling requires."""
    egl = ctypes.CDLL("libEGL.so.1")
    ptr, integer = ctypes.c_void_p, ctypes.c_int

    def function(name, result, *arguments):
        fn = getattr(egl, name)
        fn.restype, fn.argtypes = result, arguments
        return fn

    get_display = function("eglGetDisplay", ptr, ptr)
    initialize = function("eglInitialize", integer, ptr, ptr, ptr)
    bind = function("eglBindAPI", integer, ctypes.c_uint)
    choose = function("eglChooseConfig", integer, ptr, ptr, ptr, integer, ptr)
    create_surface = function("eglCreatePbufferSurface", ptr, ptr, ptr, ptr)
    create_context = function("eglCreateContext", ptr, ptr, ptr, ptr, ptr)
    make_current = function("eglMakeCurrent", integer, ptr, ptr, ptr, ptr)
    get_proc = function("eglGetProcAddress", ptr, ctypes.c_char_p)
    destroy_context = function("eglDestroyContext", integer, ptr, ptr)
    destroy_surface = function("eglDestroySurface", integer, ptr, ptr)
    terminate = function("eglTerminate", integer, ptr)
    display = get_display(None)
    if not display or not initialize(display, None, None):
        raise RuntimeError("EGL could not initialize the X11 display")
    surface = context = None
    try:
        if not bind(0x30A2):  # EGL_OPENGL_API
            raise RuntimeError("desktop OpenGL is unavailable")
        attrs = (integer * 9)(0x3033, 1, 0x3040, 8, 0x3024, 8, 0x3025, 0, 0x3038)
        config, count = ptr(), integer()
        if not choose(display, attrs, ctypes.byref(config), 1, ctypes.byref(count)) or not count.value:
            raise RuntimeError("no desktop OpenGL EGL configuration")
        size = (integer * 5)(0x3057, 16, 0x3056, 16, 0x3038)
        surface = create_surface(display, config, size)
        if not surface:
            raise RuntimeError("could not create an EGL test surface")
        address = get_proc(b"glGetString")
        if not address:
            raise RuntimeError("glGetString is unavailable")
        get_string = ctypes.CFUNCTYPE(ctypes.c_char_p, ctypes.c_uint)(address)
        renderer = ""
        for attrs in (None, (integer * 7)(0x3098, 4, 0x30FB, 1, 0x30FD, 1, 0x3038)):
            context = create_context(display, config, None, attrs)
            if not context or not make_current(display, surface, surface, context):
                raise RuntimeError("Darling needs both compatibility and OpenGL 4.1 core contexts")
            renderer = (get_string(0x1F01) or b"").decode(errors="replace")
            if not hardware_zink(renderer):
                raise RuntimeError(f"expected hardware Zink, got {renderer or 'no renderer'}")
            make_current(display, None, None, None)
            destroy_context(display, context)
            context = None
        return {"renderer": renderer}
    finally:
        make_current(display, None, None, None)
        if context:
            destroy_context(display, context)
        if surface:
            destroy_surface(display, surface)
        terminate(display)


if __name__ == "__main__":
    try:
        print(json.dumps(_probe()))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
