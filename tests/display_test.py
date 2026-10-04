import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from macoblox import core, display


class DisplayTests(unittest.TestCase):
    def test_default_keeps_x11(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(display.window_environment({}, Path("missing")),
                             {"MACOBLOX_WAYLAND": "0", "EGL_PLATFORM": "x11"})
            self.assertEqual(core.DEFAULT_SETTINGS["display_backend"], "x11")

    def test_wayland_requires_session_and_helper(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "Wayland desktop"):
                display.window_environment({"display_backend": "wayland"}, Path("missing"))
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-0"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "helper is missing"):
                display.window_environment({"display_backend": "wayland"}, Path("missing"))

    def test_opt_in_changes_host_and_guest_platform(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "helper.so"
            helper.touch()
            with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-0", "MACOBLOX_WAYLAND": "1"}, clear=True):
                values = display.window_environment({}, helper)
                self.assertEqual(values["EGL_PLATFORM"], "wayland")
                self.assertEqual(values["MACOBLOX_WAYLAND_HELPER"], str(helper))

    def test_unknown_backend_is_rejected(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                display.window_environment({"display_backend": "invalid"}, Path("missing"))
