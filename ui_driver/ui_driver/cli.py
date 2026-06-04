from __future__ import annotations

import argparse
import json
from typing import Any

from .driver import Driver


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ios-ui-driver")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("devices")

    launch = sub.add_parser("launch")
    _add_device_flags(launch)
    launch.add_argument("--bundle-id", required=True)
    launch.add_argument("args", nargs="*")

    screenshot = sub.add_parser("screenshot")
    _add_device_flags(screenshot)
    screenshot.add_argument("--output", required=True)

    tree = sub.add_parser("tree")
    _add_device_flags(tree)
    tree.add_argument("--screenshot")

    xcuitest = sub.add_parser("run-xcuitest")
    xcuitest.add_argument("--project", required=True)
    xcuitest.add_argument("--scheme", required=True)
    xcuitest.add_argument("--destination", required=True)
    xcuitest.add_argument("--only-testing", action="append", default=[])
    xcuitest.add_argument("--result-bundle")
    xcuitest.add_argument("--cwd")
    xcuitest.add_argument("--timeout", type=int, default=180)

    ns = parser.parse_args(argv)
    driver = Driver()
    out: dict[str, Any]

    if ns.command == "devices":
        out = driver.devices()
    elif ns.command == "launch":
        out = driver.launch(bundle_id=ns.bundle_id, udid=ns.udid, device=ns.device, args=ns.args)
    elif ns.command == "screenshot":
        out = driver.screenshot(output=ns.output, udid=ns.udid, device=ns.device)
    elif ns.command == "tree":
        out = driver.tree(screenshot=ns.screenshot, udid=ns.udid, device=ns.device)
    elif ns.command == "run-xcuitest":
        out = driver.run_xcuitest(
            project=ns.project,
            scheme=ns.scheme,
            destination=ns.destination,
            only_testing=ns.only_testing,
            result_bundle=ns.result_bundle,
            cwd=ns.cwd,
            timeout=ns.timeout,
        )
    else:
        parser.error(f"unknown command {ns.command}")

    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if out.get("ok") else 2


def _add_device_flags(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--udid")
    parser.add_argument("--device")
