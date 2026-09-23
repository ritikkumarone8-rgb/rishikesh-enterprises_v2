#!/usr/bin/env python3
"""Patches the platform files that `flutter create --platforms=android .`
generates, so the scaffolded Android project matches what this app actually
needs — without hand-maintaining a full hand-written Gradle/Manifest tree
that could drift out of sync with whatever Flutter/AGP version generated it.

Run this AFTER `flutter create --platforms=android .` (from the mobile/
directory) and BEFORE `flutter build`. CI does this automatically — see
.github/workflows/build.yml. A developer setting up the project locally for
the first time should run it once too (see docs/BACKEND_SETUP.md).

What it does, and why it's safe to automate (pure string/XML/Gradle-text
edits, not a full rewrite, so it survives Flutter/AGP version drift):
  1. Adds the location permissions the `geolocator`/`geocoding` packages
     need for "use my current location" on the address form. (INTERNET is
     already included by the default Flutter template.)
  2. Sets the app's display label to "Rishikesh Enterprises" instead of the
     generated placeholder.
  3. Pins compileSdk/targetSdk above Flutter's own scaffolded default. Some
     dependencies (e.g. androidx.fragment 1.7.1, pulled in transitively by
     the geocoding plugin) require compiling against API 34+; the
     `flutter create` template's default (tied to whatever Flutter version
     is installed) can be lower, which fails the Gradle
     `checkReleaseAarMetadata` task with "requires ... version 34 or later".
     Pinning explicit numbers here means this doesn't silently break again
     the next time CI picks up a different stable Flutter release.

It is idempotent — safe to run more than once.
"""
import re
import sys
from pathlib import Path

MOBILE_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATHS = [
    MOBILE_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
]

# Both extensions are covered because which one `flutter create` generates
# depends on the Flutter version running in CI (recent versions default to
# the Kotlin DSL, .kts; older ones generate Groovy).
APP_BUILD_GRADLE_PATHS = [
    MOBILE_ROOT / "android" / "app" / "build.gradle.kts",
    MOBILE_ROOT / "android" / "app" / "build.gradle",
]

# See point 3 in the module docstring above for why these are pinned rather
# than left at Flutter's own default.
COMPILE_SDK = 36
TARGET_SDK = 35

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


def patch_build_gradle(path: Path) -> bool:
    """Returns True if this was the build.gradle(.kts) file that exists and
    got handled (so the caller can skip the other extension)."""
    if not path.exists():
        return False

    text = path.read_text()
    original = text

    # Kotlin DSL: `compileSdk = flutter.compileSdkVersion` / `targetSdk = flutter.targetSdkVersion`
    text = re.sub(
        r"compileSdk\s*=\s*flutter\.compileSdkVersion",
        f"compileSdk = {COMPILE_SDK}",
        text,
    )
    text = re.sub(
        r"targetSdk\s*=\s*flutter\.targetSdkVersion",
        f"targetSdk = {TARGET_SDK}",
        text,
    )
    # Groovy DSL: `compileSdkVersion flutter.compileSdkVersion` / `targetSdkVersion flutter.targetSdkVersion`
    text = re.sub(
        r"compileSdkVersion\s+flutter\.compileSdkVersion",
        f"compileSdkVersion {COMPILE_SDK}",
        text,
    )
    text = re.sub(
        r"targetSdkVersion\s+flutter\.targetSdkVersion",
        f"targetSdkVersion {TARGET_SDK}",
        text,
    )

    if text != original:
        path.write_text(text)
        print(f"  + pinned compileSdk={COMPILE_SDK}, targetSdk={TARGET_SDK} in {path}")
    else:
        print(f"  (no changes needed) {path}")
    return True


def main() -> int:
    print("Patching Android platform files…")
    for manifest in MANIFEST_PATHS:
        patch_manifest(manifest)

    for gradle_file in APP_BUILD_GRADLE_PATHS:
        if patch_build_gradle(gradle_file):
            break
    else:
        print(
            "  (skip) no android/app/build.gradle(.kts) found yet — "
            "run `flutter create --platforms=android .` first."
        )

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
