import os
import pathlib
import subprocess
import tempfile
import time
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
printf '%s\t%s\n' "$device" "$2" >> "$FAKE_CALL_LOG"
if [[ -n ${FAKE_BLOCK_ON_ZERO:-} && $2 == 0 ]]; then
  touch "$FAKE_BLOCK_ON_ZERO.started"
  while [[ ! -e $FAKE_BLOCK_ON_ZERO.release ]]; do sleep 0.01; done
fi
[[ -z ${FAKE_FAIL_SET:-} ]] || exit 1
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
                "FAKE_CALL_LOG": str(self.root / "brightnessctl.log"),
            }
        )

    def add_device(self, brightness=128, maximum=255, name="test::kbd_backlight"):
        device = self.sysfs / name
        device.mkdir()
        (device / "brightness").write_text(f"{brightness}\n", encoding="utf-8")
        (device / "max_brightness").write_text(f"{maximum}\n", encoding="utf-8")
        return device

    def run_helper(self, action="status", check=True, device=None, extra_env=None):
        command = [str(HELPER), action]
        if device is not None:
            command.append(device)
        environment = self.env.copy()
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            command,
            env=environment,
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

    def test_failed_idle_off_does_not_leave_restore_marker(self):
        device = self.add_device(brightness=87)

        result = self.run_helper(
            "idle-off", check=False, extra_env={"FAKE_FAIL_SET": "1"}
        )
        status = self.run_helper()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.brightness(device), 87)
        self.assertTrue(status.stdout.rstrip().endswith("\t0"))

    def test_noop_adjustment_preserves_idle_restore(self):
        device = self.add_device(brightness=87)

        self.run_helper("idle-off")
        self.run_helper("down")
        self.run_helper("idle-restore")

        self.assertEqual(self.brightness(device), 87)

    def test_brightness_read_failure_does_not_touch_hardware(self):
        device = self.add_device(brightness=87)
        brightness_path = device / "brightness"
        brightness_path.chmod(0)
        try:
            result = self.run_helper("up", check=False)
        finally:
            brightness_path.chmod(0o644)

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "brightnessctl.log").exists())
        self.assertEqual(self.brightness(device), 87)

    def test_explicit_device_is_selected_and_traversal_is_rejected(self):
        selected = self.add_device(name="vendor::kbd_backlight")
        self.add_device(name="other::kbd_backlight")

        result = self.run_helper(device="vendor::kbd_backlight")
        traversal = self.run_helper(device="..", check=False)

        self.assertIn("\tvendor::kbd_backlight\t", result.stdout)
        self.assertEqual(self.brightness(selected), 128)
        self.assertNotEqual(traversal.returncode, 0)

    def test_concurrent_manual_change_wins_over_idle_off(self):
        device = self.add_device(brightness=87)
        gate = self.root / "idle-gate"
        environment = self.env.copy()
        environment["FAKE_BLOCK_ON_ZERO"] = str(gate)

        idle = subprocess.Popen(
            [str(HELPER), "idle-off"],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while not gate.with_suffix(".started").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(gate.with_suffix(".started").exists())

        manual = subprocess.Popen(
            [str(HELPER), "up"],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        gate.with_suffix(".release").touch()
        idle.communicate(timeout=5)
        manual.communicate(timeout=5)
        self.assertEqual(idle.returncode, 0)
        self.assertEqual(manual.returncode, 0)

        changed = self.brightness(device)
        self.run_helper("idle-restore")
        self.assertGreater(changed, 0)
        self.assertEqual(self.brightness(device), changed)


if __name__ == "__main__":
    unittest.main()
