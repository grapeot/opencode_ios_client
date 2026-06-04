from __future__ import annotations

from pathlib import Path
from typing import Any

from .simctl import Simctl, SimctlError
from .xcodebuild import Xcodebuild


WARNING_SCREENSHOT_ONLY = "iOS V1 driver does not provide an accessibility tree yet; use screenshot evidence or XCTest assertions for richer validation."


class Driver:
    def __init__(self, simctl: Simctl | None = None, xcodebuild: Xcodebuild | None = None):
        self.simctl = simctl or Simctl()
        self.xcodebuild = xcodebuild or Xcodebuild()

    def devices(self) -> dict[str, Any]:
        try:
            payload = self.simctl.list_devices()
            devices = self._flatten_devices(payload)
            return {"ok": True, "command": "devices", "devices": devices}
        except SimctlError as exc:
            return self._simctl_error(exc)

    def launch(self, bundle_id: str, udid: str | None = None, device: str | None = None, args: list[str] | None = None) -> dict[str, Any]:
        try:
            selected = self._select_device(udid=udid, device=device)
            result = self.simctl.run(["launch", selected["udid"], bundle_id, *(args or [])])
            return {
                "ok": True,
                "command": "launch",
                "device": selected,
                "bundle_id": bundle_id,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        except SimctlError as exc:
            return self._simctl_error(exc)
        except ValueError as exc:
            return self._selection_error(str(exc))

    def screenshot(self, output: str, udid: str | None = None, device: str | None = None) -> dict[str, Any]:
        try:
            selected = self._select_device(udid=udid, device=device)
            path = Path(output)
            path.parent.mkdir(parents=True, exist_ok=True)
            result = self.simctl.run(["io", selected["udid"], "screenshot", str(path)])
            return {
                "ok": True,
                "command": "screenshot",
                "device": selected,
                "screenshot": str(path.resolve()),
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        except SimctlError as exc:
            return self._simctl_error(exc)
        except ValueError as exc:
            return self._selection_error(str(exc))

    def tree(self, screenshot: str | None = None, udid: str | None = None, device: str | None = None) -> dict[str, Any]:
        shot_result = None
        if screenshot:
            shot_result = self.screenshot(output=screenshot, udid=udid, device=device)
            if not shot_result.get("ok"):
                return shot_result

        selected = shot_result.get("device") if shot_result else self._safe_select_device(udid=udid, device=device)
        return {
            "ok": True,
            "command": "tree",
            "device": selected,
            "observability": "screenshot_only",
            "nodes": [],
            "compact": [],
            "screenshot": shot_result.get("screenshot") if shot_result else None,
            "warnings": [WARNING_SCREENSHOT_ONLY],
        }

    def run_xcuitest(
        self,
        project: str,
        scheme: str,
        destination: str,
        only_testing: list[str] | None = None,
        result_bundle: str | None = None,
        cwd: str | None = None,
        timeout: int = 180,
    ) -> dict[str, Any]:
        args = [
            "test",
            "-project", project,
            "-scheme", scheme,
            "-destination", destination,
        ]
        for test_id in only_testing or []:
            args.append(f"-only-testing:{test_id}")
        resolved_bundle = None
        if result_bundle:
            bundle_path = Path(result_bundle).resolve()
            bundle_path.parent.mkdir(parents=True, exist_ok=True)
            resolved_bundle = str(bundle_path)
            args.extend(["-resultBundlePath", resolved_bundle])

        result = self.xcodebuild.run(args, cwd=cwd, timeout=timeout)
        return {
            "ok": result.exit_code == 0,
            "command": "run-xcuitest",
            "xcodebuild_args": result.args,
            "cwd": cwd,
            "exit_code": result.exit_code,
            "result_bundle": resolved_bundle,
            "test_summaries": self._test_summaries(result.stdout),
            "stdout_tail": self._tail(result.stdout),
            "stderr_tail": self._tail(result.stderr),
        }

    def _safe_select_device(self, udid: str | None, device: str | None) -> dict[str, Any] | None:
        try:
            return self._select_device(udid=udid, device=device)
        except Exception:
            return None

    def _select_device(self, udid: str | None = None, device: str | None = None) -> dict[str, Any]:
        devices = self._flatten_devices(self.simctl.list_devices())
        booted = [d for d in devices if d.get("state") == "Booted"]
        if udid:
            match = next((d for d in devices if d.get("udid") == udid), None)
            if not match:
                raise ValueError(f"No simulator with udid {udid}")
            return match
        if device:
            match = next((d for d in booted if d.get("name") == device), None)
            if not match:
                raise ValueError(f"No booted simulator named {device}")
            return match
        if booted:
            return booted[0]
        raise ValueError("No booted simulator found")

    @staticmethod
    def _flatten_devices(payload: dict[str, Any]) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for runtime, devices in payload.get("devices", {}).items():
            for device in devices:
                out.append({
                    "name": device.get("name"),
                    "udid": device.get("udid"),
                    "state": device.get("state"),
                    "runtime": runtime,
                    "isAvailable": device.get("isAvailable", True),
                })
        return out

    @staticmethod
    def _simctl_error(exc: SimctlError) -> dict[str, Any]:
        result = exc.result
        return {
            "ok": False,
            "error": "simctl_command_failed",
            "simctl_args": result.args,
            "exit_code": result.exit_code,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }

    def _selection_error(self, message: str) -> dict[str, Any]:
        return {
            "ok": False,
            "error": "device_selection_failed",
            "message": message,
            "devices": self._flatten_devices(self.simctl.list_devices()),
        }

    @staticmethod
    def _test_summaries(output: str) -> list[str]:
        markers = ("** TEST", "Test Suite '", "Test Case '", "Test suite '", "Test case '")
        return [line for line in output.splitlines() if line.startswith(markers)]

    @staticmethod
    def _tail(output: str, max_lines: int = 80) -> str:
        lines = output.splitlines()
        return "\n".join(lines[-max_lines:])
