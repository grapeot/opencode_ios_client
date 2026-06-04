import json

import ui_driver.cli as cli


class StubDriver:
    def devices(self):
        return {"ok": True, "command": "devices", "devices": []}

    def launch(self, bundle_id, udid=None, device=None, args=None):
        return {"ok": True, "command": "launch", "bundle_id": bundle_id, "args": args or []}

    def screenshot(self, output, udid=None, device=None):
        return {"ok": True, "command": "screenshot", "screenshot": output}

    def tree(self, screenshot=None, udid=None, device=None):
        return {"ok": True, "command": "tree", "screenshot": screenshot, "nodes": [], "compact": []}

    def run_xcuitest(self, project, scheme, destination, only_testing=None, result_bundle=None, cwd=None, timeout=180):
        return {
            "ok": True,
            "command": "run-xcuitest",
            "project": project,
            "scheme": scheme,
            "destination": destination,
            "only_testing": only_testing or [],
            "result_bundle": result_bundle,
            "cwd": cwd,
            "timeout": timeout,
        }

    def configure_server(self, project, scheme, destination, server_url, username="", password="", result_bundle=None, cwd=None, timeout=180):
        return {
            "ok": True,
            "command": "configure-server",
            "project": project,
            "server_url": server_url,
            "username": username,
            "password": "***" if password else "",
        }

    def send_prompt(self, project, scheme, destination, prompt, server_url=None, username="", password="", result_bundle=None, cwd=None, timeout=240):
        return {
            "ok": True,
            "command": "send-prompt",
            "project": project,
            "prompt": prompt,
            "server_url": server_url,
        }

    def accessibility_observation(self, project, scheme, destination, result_bundle=None, cwd=None, timeout=180):
        return {"ok": True, "command": "tree", "observability": "xcuitest_accessibility_snapshot"}


def test_cli_devices_outputs_json(monkeypatch, capsys):
    monkeypatch.setattr(cli, "Driver", StubDriver)
    code = cli.main(["devices"])
    captured = capsys.readouterr()
    assert code == 0
    assert json.loads(captured.out)["command"] == "devices"


def test_cli_launch_passes_bundle_and_args(monkeypatch, capsys):
    monkeypatch.setattr(cli, "Driver", StubDriver)
    code = cli.main(["launch", "--bundle-id", "com.example.App", "ARG1"])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert code == 0
    assert payload["bundle_id"] == "com.example.App"
    assert payload["args"] == ["ARG1"]


def test_cli_run_xcuitest_passes_arguments(monkeypatch, capsys):
    monkeypatch.setattr(cli, "Driver", StubDriver)
    code = cli.main([
        "run-xcuitest",
        "--project", "App.xcodeproj",
        "--scheme", "App",
        "--destination", "platform=iOS Simulator,name=iPhone 16,OS=18.4",
        "--only-testing", "AppUITests/Flow/testThing",
        "--result-bundle", "artifacts/flow.xcresult",
        "--cwd", "ios",
        "--timeout", "30",
    ])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert code == 0
    assert payload["command"] == "run-xcuitest"
    assert payload["project"] == "App.xcodeproj"
    assert payload["only_testing"] == ["AppUITests/Flow/testThing"]
    assert payload["result_bundle"] == "artifacts/flow.xcresult"
    assert payload["cwd"] == "ios"
    assert payload["timeout"] == 30


def test_cli_configure_server_masks_password(monkeypatch, capsys):
    monkeypatch.setattr(cli, "Driver", StubDriver)
    monkeypatch.setenv("OPENCODE_PASSWORD", "secret")
    code = cli.main([
        "configure-server",
        "--project", "App.xcodeproj",
        "--scheme", "App",
        "--destination", "platform=iOS Simulator,name=iPhone 16,OS=18.4",
        "--server-url", "http://127.0.0.1:4096",
        "--username", "user",
        "--password-env", "OPENCODE_PASSWORD",
    ])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert code == 0
    assert payload["command"] == "configure-server"
    assert payload["password"] == "***"
    assert "secret" not in captured.out


def test_cli_tree_can_use_xcuitest_observation(monkeypatch, capsys):
    monkeypatch.setattr(cli, "Driver", StubDriver)
    code = cli.main([
        "tree",
        "--project", "App.xcodeproj",
        "--scheme", "App",
        "--destination", "platform=iOS Simulator,name=iPhone 16,OS=18.4",
    ])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert code == 0
    assert payload["observability"] == "xcuitest_accessibility_snapshot"
