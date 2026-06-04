from __future__ import annotations

import argparse
import json
import os
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
    _add_xcode_flags(tree, required=False)

    configure = sub.add_parser("configure-server")
    _add_xcode_flags(configure)
    configure.add_argument("--server-url", required=True)
    configure.add_argument("--username", default="")
    configure.add_argument("--password", default="")
    configure.add_argument("--password-env")

    prompt = sub.add_parser("send-prompt")
    _add_xcode_flags(prompt)
    prompt.add_argument("--prompt", required=True)
    prompt.add_argument("--server-url")
    prompt.add_argument("--username", default="")
    prompt.add_argument("--password", default="")
    prompt.add_argument("--password-env")

    xcuitest = sub.add_parser("run-xcuitest")
    _add_xcode_flags(xcuitest)
    xcuitest.add_argument("--only-testing", action="append", default=[])

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
        if ns.project and ns.scheme and ns.destination:
            out = driver.accessibility_observation(
                project=ns.project,
                scheme=ns.scheme,
                destination=ns.destination,
                result_bundle=ns.result_bundle,
                cwd=ns.cwd,
                timeout=ns.timeout,
            )
        else:
            out = driver.tree(screenshot=ns.screenshot, udid=ns.udid, device=ns.device)
    elif ns.command == "configure-server":
        password = _resolve_password(ns.password, ns.password_env)
        out = driver.configure_server(
            project=ns.project,
            scheme=ns.scheme,
            destination=ns.destination,
            server_url=ns.server_url,
            username=ns.username,
            password=password,
            result_bundle=ns.result_bundle,
            cwd=ns.cwd,
            timeout=ns.timeout,
        )
    elif ns.command == "send-prompt":
        password = _resolve_password(ns.password, ns.password_env)
        out = driver.send_prompt(
            project=ns.project,
            scheme=ns.scheme,
            destination=ns.destination,
            prompt=ns.prompt,
            server_url=ns.server_url,
            username=ns.username,
            password=password,
            result_bundle=ns.result_bundle,
            cwd=ns.cwd,
            timeout=ns.timeout,
        )
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


def _add_xcode_flags(parser: argparse.ArgumentParser, required: bool = True) -> None:
    parser.add_argument("--project", required=required)
    parser.add_argument("--scheme", required=required)
    parser.add_argument("--destination", required=required)
    parser.add_argument("--result-bundle")
    parser.add_argument("--cwd")
    parser.add_argument("--timeout", type=int, default=180)


def _resolve_password(password: str, password_env: str | None) -> str:
    if password_env:
        return os.environ.get(password_env, "")
    return password
