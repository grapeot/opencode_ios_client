from ui_driver.driver import Driver, WARNING_SCREENSHOT_ONLY
from ui_driver.simctl import SimctlError, SimctlResult
from ui_driver.xcodebuild import XcodebuildResult


class FakeSimctl:
    def __init__(self, fail_args=None):
        self.calls = []
        self.fail_args = fail_args or []

    def list_devices(self):
        self.calls.append(["list", "devices", "--json"])
        return {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
                    {"name": "iPhone 16", "udid": "SIM-1", "state": "Booted", "isAvailable": True},
                    {"name": "iPhone 15", "udid": "SIM-2", "state": "Shutdown", "isAvailable": True},
                ]
            }
        }

    def run(self, args):
        self.calls.append(args)
        if args in self.fail_args:
            raise SimctlError(SimctlResult(args=args, exit_code=1, stdout="", stderr="boom"))
        return SimctlResult(args=args, exit_code=0, stdout="ok", stderr="")


class FakeXcodebuild:
    def __init__(self, exit_code=0):
        self.calls = []
        self.exit_code = exit_code

    def run(self, args, cwd=None, timeout=180):
        self.calls.append((args, cwd, timeout))
        return XcodebuildResult(
            args=args,
            exit_code=self.exit_code,
            stdout="\n".join([
                "build noise",
                "** TEST SUCCEEDED **" if self.exit_code == 0 else "** TEST FAILED **",
                "Test Suite 'ToolCardsUITests' started",
                "Test Case 'ToolCardsUITests/testReadCard()' passed (1.0 seconds)",
            ]),
            stderr="",
        )


def test_devices_flattens_simctl_json():
    out = Driver(FakeSimctl()).devices()
    assert out["ok"] is True
    assert out["devices"][0]["name"] == "iPhone 16"
    assert out["devices"][0]["state"] == "Booted"


def test_launch_uses_first_booted_device():
    fake = FakeSimctl()
    out = Driver(fake).launch(bundle_id="com.example.App")
    assert out["ok"] is True
    assert out["device"]["udid"] == "SIM-1"
    assert ["launch", "SIM-1", "com.example.App"] in fake.calls


def test_screenshot_uses_simctl_io_screenshot():
    fake = FakeSimctl()
    out = Driver(fake).screenshot(output="artifacts/screen.png")
    assert out["ok"] is True
    assert ["io", "SIM-1", "screenshot", "artifacts/screen.png"] in fake.calls


def test_tree_is_honest_about_screenshot_only_observability():
    out = Driver(FakeSimctl()).tree()
    assert out["ok"] is True
    assert out["observability"] == "screenshot_only"
    assert out["nodes"] == []
    assert WARNING_SCREENSHOT_ONLY in out["warnings"]


def test_simctl_failure_preserves_raw_error():
    failing_args = ["launch", "SIM-1", "com.example.App"]
    out = Driver(FakeSimctl(fail_args=[failing_args])).launch(bundle_id="com.example.App")
    assert out["ok"] is False
    assert out["error"] == "simctl_command_failed"
    assert out["simctl_args"] == failing_args
    assert out["exit_code"] == 1
    assert out["stderr"] == "boom"


def test_run_xcuitest_builds_targeted_xcodebuild_command(tmp_path):
    fake_xcodebuild = FakeXcodebuild()
    out = Driver(FakeSimctl(), xcodebuild=fake_xcodebuild).run_xcuitest(
        project="OpenCodeClient.xcodeproj",
        scheme="OpenCodeClient",
        destination="platform=iOS Simulator,name=iPhone 16,OS=18.4",
        only_testing=["OpenCodeClientUITests/ToolCardsUITests/testReadCard"],
        result_bundle=str(tmp_path / "read-card.xcresult"),
        cwd="OpenCodeClient",
        timeout=30,
    )

    assert out["ok"] is True
    args, cwd, timeout = fake_xcodebuild.calls[0]
    assert args[:7] == [
        "test",
        "-project", "OpenCodeClient.xcodeproj",
        "-scheme", "OpenCodeClient",
        "-destination", "platform=iOS Simulator,name=iPhone 16,OS=18.4",
    ]
    assert "-only-testing:OpenCodeClientUITests/ToolCardsUITests/testReadCard" in args
    assert "-resultBundlePath" in args
    assert cwd == "OpenCodeClient"
    assert timeout == 30
    assert out["test_summaries"] == [
        "** TEST SUCCEEDED **",
        "Test Suite 'ToolCardsUITests' started",
        "Test Case 'ToolCardsUITests/testReadCard()' passed (1.0 seconds)",
    ]


def test_run_xcuitest_surfaces_failure_exit_code():
    out = Driver(FakeSimctl(), xcodebuild=FakeXcodebuild(exit_code=65)).run_xcuitest(
        project="OpenCodeClient.xcodeproj",
        scheme="OpenCodeClient",
        destination="platform=iOS Simulator,name=iPhone 16,OS=18.4",
    )

    assert out["ok"] is False
    assert out["exit_code"] == 65
    assert "** TEST FAILED **" in out["test_summaries"]
