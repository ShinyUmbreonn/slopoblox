"""Run: PYTHONPATH=launcher python3 -m unittest discover -s tests -p '*_test.py'."""
import json
import subprocess
import unittest
from unittest.mock import patch

from macoblox import core, graphics


class GraphicsTests(unittest.TestCase):
    def test_default_preserves_host_driver_selection(self):
        self.assertEqual(graphics.renderer_environment("opengl"), {})
        self.assertEqual(core.DEFAULT_SETTINGS["renderer"], "opengl")

    def test_vulkan_selects_mesa_egl_and_keeps_metal_disabled(self):
        with patch.object(graphics.Path, "is_file", return_value=True):
            env = graphics.renderer_environment("vulkan")
        self.assertEqual(env["MESA_LOADER_DRIVER_OVERRIDE"], "zink")
        self.assertEqual(env["MACOBLOX_METAL"], "0")
        self.assertEqual(env["EGL_PLATFORM"], "x11")
        self.assertTrue(env["__EGL_VENDOR_LIBRARY_FILENAMES"].endswith("50_mesa.json"))

    def test_missing_mesa_is_actionable(self):
        with patch.object(graphics.Path, "is_file", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "Install them or select OpenGL"):
                graphics.renderer_environment("vulkan")

    def test_software_fallback_is_rejected(self):
        for name in ("llvmpipe", "zink Vulkan (lavapipe)", "zink Vulkan (llvmpipe)",
                     "NVIDIA GeForce RTX 5070 Ti"):
            with self.subTest(name=name), patch.object(graphics.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], 0, json.dumps({"renderer": name}))):
                with self.assertRaisesRegex(RuntimeError, "Select OpenGL"):
                    graphics.validate_vulkan({})

    def test_hardware_and_driver_failure(self):
        name = "zink Vulkan 1.4 (NVIDIA GeForce RTX 5070 Ti)"
        with patch.object(graphics.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 0, json.dumps({"renderer": name}))):
            self.assertEqual(graphics.validate_vulkan({}), name)
        for result in (subprocess.CompletedProcess([], -11, ""),
                       subprocess.CompletedProcess([], 1, '{"error":"no X11 display"}')):
            with patch.object(graphics.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(RuntimeError, "Select OpenGL"):
                    graphics.validate_vulkan({})
        with patch.object(graphics.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 20)):
            with self.assertRaisesRegex(RuntimeError, "Select OpenGL"):
                graphics.validate_vulkan({})

    def test_renderer_reaches_guest_and_nvidia_cache_uses_host_path(self):
        session = object.__new__(core.RobloxSession)
        session.settings = dict(core.DEFAULT_SETTINGS, renderer="vulkan")
        session.web_socket = session.dns = session.audio = None
        with patch.object(graphics.Path, "is_file", return_value=True), \
                patch.object(core, "host_vram_bytes", return_value=0), \
                patch.dict(core.os.environ, {"MANGOHUD": "1", "MANGOHUD_CONFIG": "fps,frametime,gpu_name", "MANGOHUD_CONFIGFILE": "/tmp/hud config.conf"}), \
                patch.object(core, "icon_argb_file", side_effect=OSError):
            env = dict(item.split("=", 1) for item in session.shim_variables())
        self.assertEqual(env["MESA_LOADER_DRIVER_OVERRIDE"], "zink")
        self.assertEqual(env["MACOBLOX_METAL"], "0")
        self.assertEqual(env["__GL_SHADER_DISK_CACHE_PATH"], str(core.CACHE_DIR / "nvidia-shader-cache"))
        self.assertEqual(env["MANGOHUD"], "1")
        self.assertEqual(env["MANGOHUD_CONFIG"], "fps,frametime,gpu_name")
        self.assertEqual(env["MANGOHUD_CONFIGFILE"], "/tmp/hud config.conf")


if __name__ == "__main__":
    unittest.main()
