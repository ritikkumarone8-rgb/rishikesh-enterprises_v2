#!/usr/bin/env python3
"""Patches the platform files that `flutter create --platforms=android .`
generates, so the scaffolded Android project matches what this app actually
needs — without hand-maintaining a full hand-written Gradle/Manifest tree
that could drift out of sync with whatever Flutter/AGP version generated it.

Run this AFTER `flutter create --platforms=android .` (from the mobile/
directory) and BEFORE `flutter build`. CI does this automatically — see
.github/workflows/build.yml. A developer setting up the project locally for
the first time should run it once too (see docs/BACKEND_SETUP.md).

What it does, and why it's safe to automate (pure string/XML edits, not
Gradle syntax which changes between Flutter versions):
  1. Adds the location permissions the `geolocator`/`geocoding` packages
     need for "use my current location" on the address form. (INTERNET is
     already included by the default Flutter template.)
  2. Sets the app's display label to "Rishikesh Enterprises" instead of the
     generated placeholder.

It is idempotent — safe to run more than once.
"""
import re
import sys
from pathlib import Path

MOBILE_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATHS = [
    MOBILE_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
]

REQUIRED_PERMISSIONS = [
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]

APP_LABEL = "Rishikesh Enterprises"


def patch_manifest(path: Path) -> None:
    if not path.exists():
        print(f"  (skip) {path} does not exist yet — run `flutter create --platforms=android .` first.")
        return

    xml = path.read_text()
    original = xml

    for permission in REQUIRED_PERMISSIONS:
        tag = f'<uses-permission android:name="{permission}"/>'
        if permission not in xml:
            # Insert right before <application ...> so it lives alongside
            # any other <uses-permission> tags the template already added.
            xml = re.sub(
                r"(\s*)(<application)",
                rf"\1{tag}\1\2",
                xml,
                count=1,
            )
            print(f"  + added permission {permission}")

    # Replace the generated android:label="..." on the <application> tag.
    new_xml, n = re.subn(
        r'(<application[^>]*\bandroid:label=")[^"]*(")',
        rf'\g<1>{APP_LABEL}\g<2>',
        xml,
        count=1,
    )
    if n:
        xml = new_xml
        print(f'  + set android:label="{APP_LABEL}"')

    if xml != original:
        path.write_text(xml)
        print(f"  saved {path}")
    else:
        print(f"  (no changes needed) {path}")


def main() -> int:
    print("Patching Android platform files…")
    for manifest in MANIFEST_PATHS:
        patch_manifest(manifest)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
