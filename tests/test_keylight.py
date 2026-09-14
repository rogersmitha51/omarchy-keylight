import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "keylight"


class KeylightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.sysfs = self.root / "leds"
        self.state = self.root / "state"
        self.bin = self.root / "bin"
        self.boot_id = self.root / "boot_id"
        self.sysfs.mkdir()
        self.bin.mkdir()
        self.boot_id.write_text("test-boot-id\n", encoding="utf-8")

        self.fake_brightnessctl = self.bin / "brightnessctl"
        self.fake_brightnessctl.write_text(
            """#!/usr/bin/env bash
set -eu
[[ ${1:-} == -q ]] && shift
[[ ${1:-} == -d ]] || exit 64
device=$2
shift 2
[[ ${1:-} == set ]] || exit 64
printf '%s\n' "$2" > "$FAKE_SYSFS_ROOT/$device/brightness"
""",
            encoding="utf-8",
        )
        self.fake_brightnessctl.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            {
                "KEYLIGHT_SYSFS_ROOT": str(self.sysfs),
                "KEYLIGHT_STATE_HOME": str(self.state),
                "KEYLIGHT_BOOT_ID_PATH": str(self.boot_id),
                "BRIGHTNESSCTL": str(self.fake_brightnessctl),
                "FAKE_SYSFS_ROOT": str(self.sysfs),
            }
        )

    def add_device(self, brightness=128, maximum=255):
        device = self.sysfs / "test::kbd_backlight"
        device.mkdir()
        (device / "brightness").write_text(f"{brightness}\n", encoding="utf-8")
        (device / "max_brightness").write_text(f"{maximum}\n", encoding="utf-8")
        return device

    def run_helper(self, action="status", check=True):
        return subprocess.run(
            [str(HELPER), action],
            env=self.env,
            check=check,
            text=True,
            capture_output=True,
            timeout=5,
        )

    @staticmethod
    def brightness(device):
        return int((device / "brightness").read_text(encoding="utf-8"))

    def test_idle_cycle_restores_exact_previous_brightness(self):
        device = self.add_device(brightness=87)

        off = self.run_helper("idle-off")
        self.assertEqual(self.brightness(device), 0)
        self.assertTrue(off.stdout.rstrip().endswith("\t1"))

        restored = self.run_helper("idle-restore")
        self.assertEqual(self.brightness(device), 87)
        self.assertTrue(restored.stdout.rstrip().endswith("\t0"))

    def test_manual_off_is_not_undone_by_activity_restore(self):
        device = self.add_device(brightness=87)

        self.run_helper("off")
        self.run_helper("idle-restore")

        self.assertEqual(self.brightness(device), 0)

    def test_manual_change_while_idle_cancels_automatic_restore(self):
        device = self.add_device(brightness=100)

        self.run_helper("idle-off")
        self.run_helper("up")
        changed = self.brightness(device)
        self.run_helper("idle-restore")

        self.assertEqual(self.brightness(device), changed)
        self.assertNotEqual(changed, 100)

    def test_idle_marker_does_not_cross_boots(self):
        device = self.add_device(brightness=73)
        self.run_helper("idle-off")
        self.boot_id.write_text("next-boot-id\n", encoding="utf-8")

        self.run_helper("idle-restore")

        self.assertEqual(self.brightness(device), 0)

    def test_status_reports_unavailable_without_a_device(self):
        result = self.run_helper(check=False)

        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "unavailable\n")

    def test_invalid_state_directory_fails_before_hardware_change(self):
        device = self.add_device(brightness=73)
        self.state.mkdir(mode=0o755)

        result = self.run_helper("idle-off", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.brightness(device), 73)


if __name__ == "__main__":
    unittest.main()
