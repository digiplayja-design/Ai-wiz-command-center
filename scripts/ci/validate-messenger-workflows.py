#!/usr/bin/env python3
"""Validate Messenger workflows with a checksum-pinned GitHub Actions linter."""

import hashlib
import io
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = "1.7.12"
SHA256 = "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
URL = f"https://github.com/rhysd/actionlint/releases/download/v{VERSION}/actionlint_{VERSION}_linux_amd64.tar.gz"


def main():
    root = Path(__file__).resolve().parents[2]
    paths = sorted((root / ".github/workflows").glob("korlix-messenger-*.yml"))
    if not paths:
        raise SystemExit("No Messenger workflows found.")
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit("Run this pinned validator on Linux x86-64.")
    with tempfile.TemporaryDirectory(prefix="korlix-actionlint-") as directory:
        with urllib.request.urlopen(URL, timeout=30) as response:
            archive = response.read(16 * 1024 * 1024)
        if hashlib.sha256(archive).hexdigest() != SHA256:
            raise SystemExit("Actionlint release checksum mismatch.")
        executable = Path(directory) / "actionlint"
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as bundle:
            member = bundle.getmember("actionlint")
            if not member.isfile() or member.size > 32 * 1024 * 1024:
                raise SystemExit("Unexpected actionlint release contents.")
            executable.write_bytes(bundle.extractfile(member).read())
        os.chmod(executable, 0o700)
        # The dedicated check covers GitHub expression/context semantics as well
        # as workflow structure; app tests validate the client configuration.
        subprocess.run([str(executable), "-shellcheck=", "-pyflakes=", *map(str, paths)], cwd=root, check=True)
    print(f"Validated {len(paths)} Messenger workflows with actionlint {VERSION}.")


if __name__ == "__main__":
    main()
