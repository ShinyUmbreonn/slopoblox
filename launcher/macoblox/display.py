"""Window backend selection; native Wayland remains an explicit experiment."""
import ctypes
import os
from pathlib import Path


def window_environment(settings, helper):
    backend = settings.get("display_backend", "x11")
    if os.environ.get("MACOBLOX_WAYLAND") == "1":
        backend = "wayland"
    if backend == "x11":
        return {"MACOBLOX_WAYLAND": "0", "EGL_PLATFORM": "x11"}
    if backend != "wayland":
        raise ValueError(f"Unknown window backend: {backend}")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Experimental Wayland requires a Wayland desktop session. Select X11 in Settings.")
    if not Path(helper).is_file():
        raise RuntimeError("The experimental Wayland helper is missing. Install SDL2/Wayland development libraries and rebuild, or select X11.")
    return {"MACOBLOX_WAYLAND": "1", "EGL_PLATFORM": "wayland",
            "MACOBLOX_WAYLAND_HELPER": str(helper)}


class WaylandProbeWindow:
    """The same Linux helper and EGL surface used by the experimental client."""
    def __init__(self):
        pointer, uint, integer = ctypes.c_void_p, ctypes.c_uint, ctypes.c_int
        display = ctypes.CFUNCTYPE(pointer)
        create = ctypes.CFUNCTYPE(uint, integer, integer)
        surface = ctypes.CFUNCTYPE(pointer, uint)
        action = ctypes.CFUNCTYPE(None, uint, integer, ctypes.c_double, ctypes.c_double, ctypes.c_char_p)
        error = ctypes.CFUNCTYPE(ctypes.c_char_p)

        class API(ctypes.Structure):
            _fields_ = [("version", uint), ("display", display), ("create", create),
                        ("surface", surface), ("action", action), ("poll", pointer),
                        ("screen", pointer), ("cursor", pointer), ("clipboard", pointer),
                        ("error", error)]

        self.library = ctypes.CDLL(os.environ["MACOBLOX_WAYLAND_HELPER"])
        get_api = self.library.macoblox_wayland_host_api
        get_api.restype = ctypes.POINTER(API)
        value = get_api()
        if not value or value.contents.version != 2:
            raise RuntimeError("Experimental Wayland helper failed to initialize or has an incompatible ABI")
        self.api = value.contents
        self.native = self.api.display()
        self.handle = self.api.create(16, 16)
        self.surface = self.api.surface(self.handle) if self.handle else None
        if not self.native or not self.surface:
            self.close()
            raise RuntimeError((self.api.error() or b"Wayland test window failed").decode(errors="replace"))

    def close(self):
        if self.handle:
            self.api.action(self.handle, 10, 0, 0, None)  # MW_DESTROY
            self.handle = 0
