from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from typing import Any


@dataclass
class SimctlResult:
    args: list[str]
    exit_code: int
    stdout: str
    stderr: str


class SimctlError(RuntimeError):
    def __init__(self, result: SimctlResult):
        super().__init__(result.stderr or result.stdout or "simctl command failed")
        self.result = result


class Simctl:
    def run(self, args: list[str]) -> SimctlResult:
        proc = subprocess.run(
            ["xcrun", "simctl", *args],
            text=True,
            capture_output=True,
            check=False,
        )
        result = SimctlResult(args=args, exit_code=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
        if proc.returncode != 0:
            raise SimctlError(result)
        return result

    def list_devices(self) -> dict[str, Any]:
        result = self.run(["list", "devices", "--json"])
        return json.loads(result.stdout)
