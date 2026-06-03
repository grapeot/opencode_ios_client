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
