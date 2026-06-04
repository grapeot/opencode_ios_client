from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
import os


@dataclass
class XcodebuildResult:
    args: list[str]
    exit_code: int
    stdout: str
    stderr: str


class Xcodebuild:
    def run(self, args: list[str], cwd: str | None = None, timeout: int = 180, env: dict[str, str] | None = None) -> XcodebuildResult:
        proc_env = os.environ.copy()
        if env:
            proc_env.update(env)
        try:
            proc = subprocess.run(
                ["xcodebuild", *args],
                cwd=Path(cwd) if cwd else None,
                env=proc_env,
                text=True,
                capture_output=True,
                check=False,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout if isinstance(exc.stdout, str) else ""
            stderr = exc.stderr if isinstance(exc.stderr, str) else ""
            message = f"xcodebuild timed out after {timeout} seconds"
            return XcodebuildResult(args=args, exit_code=124, stdout=stdout, stderr=stderr or message)

        return XcodebuildResult(args=args, exit_code=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
