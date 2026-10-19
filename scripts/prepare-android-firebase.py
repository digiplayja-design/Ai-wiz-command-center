#!/usr/bin/env python3
"""Validate and copy optional public Firebase Android client configuration."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile


PACKAGE = "com.korlixdeveloper.korlixai"
CLIENT_PATH = Path("android/app/google-services.json")
MAX_BYTES = 1024 * 1024
SECRET_KEYS = {
    "privatekey", "privatekeyid", "clientemail", "clientsecret",
    "accesstoken", "refreshtoken", "serviceaccount", "serviceaccountkey",
    "password",
}


class ConfigError(ValueError):
    pass


def reject_secret_material(value):
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = re.sub(r"[^a-z0-9]", "", key.lower())
            if normalized in SECRET_KEYS or (
                normalized == "type" and item == "service_account"
            ):
                raise ConfigError(
                    "Firebase Android configuration must be the public google-services.json, "
                    "never a service-account file or private credential."
                )
            reject_secret_material(item)
    elif isinstance(value, list):
        for item in value:
            reject_secret_material(item)
    elif isinstance(value, str) and re.search(
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----", value, re.IGNORECASE
    ):
        raise ConfigError("Private keys must never be included in an Android client file.")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError("Firebase Android client JSON contains duplicate fields.")
        result[key] = value
    return result


def reject_constant(_):
    raise ConfigError("Firebase Android client JSON contains an invalid numeric value.")


def validate_bytes(data):
    if len(data) > MAX_BYTES:
        raise ConfigError("Firebase Android client configuration is too large.")
    try:
        config = json.loads(data, object_pairs_hook=unique_object, parse_constant=reject_constant)
    except (ValueError, UnicodeError) as error:
        if isinstance(error, ConfigError):
            raise
        raise ConfigError("Firebase Android configuration is not valid JSON.") from None
    reject_secret_material(config)
    if not isinstance(config, dict):
        raise ConfigError("Firebase Android client configuration must be a JSON object.")
    project = config.get("project_info")
    if not isinstance(project, dict):
        raise ConfigError("Firebase Android client configuration is missing project_info.")
    number, project_id = project.get("project_number"), project.get("project_id")
    if not isinstance(number, str) or not re.fullmatch(r"[0-9]{1,24}", number):
        raise ConfigError("Firebase Android client configuration needs its project_number.")
    if not isinstance(project_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", project_id):
        raise ConfigError("Firebase Android client configuration needs its project_id.")
    clients = config.get("client")
    if not isinstance(clients, list) or not clients:
        raise ConfigError("Firebase Android client configuration is missing its client list.")
    matching = []
    for client in clients:
        if not isinstance(client, dict):
            raise ConfigError("Firebase Android client configuration contains an invalid client.")
        info = client.get("client_info")
        android = info.get("android_client_info") if isinstance(info, dict) else None
        if isinstance(android, dict) and android.get("package_name") == PACKAGE:
            matching.append(client)
    if len(matching) != 1:
        raise ConfigError(f"Firebase Android client configuration must contain exactly one client for {PACKAGE}.")
    client = matching[0]
    app_id = client["client_info"].get("mobilesdk_app_id")
    if not isinstance(app_id, str) or not re.fullmatch(rf"1:{re.escape(number)}:android:[0-9a-fA-F]+", app_id):
        raise ConfigError("Firebase Android client app ID does not match its project number.")
    keys = client.get("api_key")
    if not isinstance(keys, list) or not any(
        isinstance(item, dict) and isinstance(item.get("current_key"), str)
        and re.fullmatch(r"[A-Za-z0-9_-]{20,128}", item["current_key"])
        for item in keys
    ):
        raise ConfigError("Firebase Android client configuration is missing its public API key.")
    return config


def prepare(source_root, build_root, explicit=None):
    source_root, build_root = Path(source_root).resolve(), Path(build_root).resolve()
    target = build_root / CLIENT_PATH
    if not target.parent.is_dir() or target.parent.resolve() != target.parent:
        raise ConfigError("The Android build app directory is missing or is a symbolic link.")
    if target.is_symlink():
        raise ConfigError("The Android Firebase target must not be a symbolic link.")
    source = Path(explicit).expanduser() if explicit else source_root / CLIENT_PATH
    if not explicit and not source.exists():
        # A resumed worktree can retain the validated client file copied by a
        # previous preparation even when the original source no longer has it.
        source = target
    if not source.exists():
        if explicit:
            raise ConfigError("KORLIX_FIREBASE_ANDROID_CONFIG does not name an existing client JSON file.")
        return False
    if not source.is_file():
        raise ConfigError("Firebase Android client configuration must be a regular JSON file.")
    try:
        with source.open("rb") as stream:
            data = stream.read(MAX_BYTES + 1)
    except OSError:
        raise ConfigError("Could not read the Firebase Android client JSON file.") from None
    validate_bytes(data)
    if source.resolve() == target.resolve():
        return True
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".firebase-client-", dir=target.parent, delete=False) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            stream.write(data)
        os.replace(temporary, target)
    except OSError:
        raise ConfigError("Could not copy the Firebase Android client file into the isolated build.") from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("build_root", type=Path)
    args = parser.parse_args()
    try:
        enabled = prepare(args.source_root, args.build_root,
                          os.environ.get("KORLIX_FIREBASE_ANDROID_CONFIG") or None)
    except (ConfigError, OSError) as error:
        # Error messages never include values from the client/provider JSON.
        print(f"Android Firebase setup: {error if isinstance(error, ConfigError) else 'Could not access the client configuration.'}", file=sys.stderr)
        return 1
    print("Validated public Firebase Android client configuration is ready."
          if enabled else "No Firebase Android client configuration found; FCM remains disabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
