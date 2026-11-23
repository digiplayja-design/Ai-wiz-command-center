"""Copy the registered iOS client configuration into this app's Xcode build."""
import base64
import os
from pathlib import Path
import plistlib
import sys

BUNDLE = "com.korlixdeveloper.korlixai"
PRODUCTION_APP = "1:830884744891:ios:9da9f4b49815da8de1e39e"


def prepare(env):
    if env["PRODUCT_BUNDLE_IDENTIFIER"] != BUNDLE:
        return
    target = Path(env["TARGET_BUILD_DIR"], env["UNLOCALIZED_RESOURCES_FOLDER_PATH"], "GoogleService-Info.plist")
    release = env["CONFIGURATION"] == "Release"
    local = Path(env["SRCROOT"], "Runner", "GoogleService-Info.plist")
    encoded = env.get("KORLIX_FIREBASE_IOS_PLIST_BASE64")
    if local.is_file():
        content = local.read_bytes()
    elif encoded:
        content = base64.b64decode(encoded.strip(), validate=True)
    elif release:
        raise ValueError("The release requires the registered client configuration")
    else:
        target.unlink(missing_ok=True)
        return
    config = plistlib.loads(content)
    if config.get("BUNDLE_ID") != BUNDLE or not all(config.get(k) for k in ("GOOGLE_APP_ID", "PROJECT_ID", "API_KEY")):
        raise ValueError("Unexpected client configuration")
    if release and (config["PROJECT_ID"] != "korlix-ai" or config["GOOGLE_APP_ID"] != PRODUCTION_APP):
        raise ValueError("Unexpected release project")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)


if __name__ == "__main__":
    try:
        prepare(os.environ)
    except Exception:
        sys.exit("KORLIX AI requires a valid Firebase Apple app configuration for this build.")
