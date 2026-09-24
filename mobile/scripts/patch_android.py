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
  3. Pins compileSdk/targetSdk above Flutter's own scaffolded default, for
     BOTH the app module and every plugin subproject (geolocator_android,
     geocoding_android, etc. — each pulled from pub.dev with its own
     build.gradle that independently reads the same shared default). Some
     transitive androidx dependencies (fragment 1.7.1, core-ktx 1.13.1, …)
     require compiling against API 34+; the `flutter create` template's
     default (tied to whatever Flutter version is installed) can be lower,
     which fails Gradle's `checkReleaseAarMetadata` task on whichever plugin
     hits it first with "requires ... version 34 or later".

     Patching only android/app/build.gradle(.kts) is NOT enough — that only
     changes the *app* module's own compileSdk. Each plugin subproject reads
     the same `flutter.compileSdkVersion` default independently and is
     unaffected by the app's override. The fix has to happen at the
     *root* android/build.gradle(.kts), which can force every subproject
     (app + all plugins) via a `subprojects { ... }` block — the standard
     workaround for this exact class of Flutter/Gradle version-skew error.
  4. Pins the *app* module's minSdk to 23. `google_sign_in_android` (added
     for "Continue with Google") pulls in `androidx.credentials`, whose
     current stable release declares `minSdk 23` in its own manifest —
     above Flutter's own scaffolded default (21). Unlike compileSdk, this
     only needs to be forced on the app module: Gradle's manifest merger
     requires the *final app*'s minSdk to be >= every dependency's minSdk,
     but doesn't care what a lower-minSdk library module declares for
     itself. Forcing it on the app module alone is sufficient.

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

# The root-level Gradle file (one level up from android/app/) — this is
# where the fix for every plugin subproject's compileSdk actually belongs.
# See point 3 in the module docstring.
ROOT_BUILD_GRADLE_PATHS = [
    MOBILE_ROOT / "android" / "build.gradle.kts",
    MOBILE_ROOT / "android" / "build.gradle",
]

# See points 3 and 4 in the module docstring above for why these are pinned
# rather than left at Flutter's own default.
COMPILE_SDK = 36
TARGET_SDK = 35
MIN_SDK = 23

SUBPROJECTS_MARKER = "patch_android.py: force compileSdk across all subprojects"

# Doubled {{ }} are literal Gradle braces (f-string escaping); the single
# {COMPILE_SDK} is the actual Python substitution.
#
# Why the `state.executed` branch exists: Flutter's own template (earlier in
# this same file) has `subprojects { project.evaluationDependsOn(":app") }`,
# and evaluationDependsOn() synchronously force-evaluates its target — so by
# the time THIS block runs, ":app" is already evaluated. Calling
# `afterEvaluate { ... }` on an already-evaluated project throws "Cannot run
# Project.afterEvaluate(Action) when the project is already evaluated." —
# so an already-evaluated project gets the compileSdk override applied
# directly instead of deferred.
SUBPROJECTS_BLOCK_KTS = f"""
// >>> {SUBPROJECTS_MARKER} <<<
// Plugin subprojects (geolocator_android, geocoding_android, ...) each read
// Flutter's own default compileSdk independently of the app module, so
// overriding android/app/build.gradle.kts alone doesn't reach them. This
// forces every Android subproject to compile against the same SDK.
subprojects {{
    if (state.executed) {{
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {{ ext ->
            ext.compileSdkVersion({COMPILE_SDK})
        }}
    }} else {{
        afterEvaluate {{
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {{ ext ->
                ext.compileSdkVersion({COMPILE_SDK})
            }}
        }}
    }}
}}
"""

SUBPROJECTS_BLOCK_GROOVY = f"""
// >>> {SUBPROJECTS_MARKER} <<<
// Plugin subprojects (geolocator_android, geocoding_android, ...) each read
// Flutter's own default compileSdk independently of the app module, so
// overriding android/app/build.gradle alone doesn't reach them. This forces
// every Android subproject to compile against the same SDK.
subprojects {{
    if (state.executed) {{
        if (project.hasProperty('android')) {{
            project.android {{
                compileSdkVersion {COMPILE_SDK}
            }}
        }}
    }} else {{
        afterEvaluate {{
            if (project.hasProperty('android')) {{
                project.android {{
                    compileSdkVersion {COMPILE_SDK}
                }}
            }}
        }}
    }}
}}
"""

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
    # Kotlin DSL: `minSdk = flutter.minSdkVersion`
    text = re.sub(
        r"minSdk\s*=\s*flutter\.minSdkVersion",
        f"minSdk = {MIN_SDK}",
        text,
    )
    # Groovy DSL: `minSdkVersion flutter.minSdkVersion`
    text = re.sub(
        r"minSdkVersion\s+flutter\.minSdkVersion",
        f"minSdkVersion {MIN_SDK}",
        text,
    )

    if text != original:
        path.write_text(text)
        print(f"  + pinned compileSdk={COMPILE_SDK}, targetSdk={TARGET_SDK}, minSdk={MIN_SDK} in {path}")
    else:
        print(f"  (no changes needed) {path}")
    return True


def patch_root_build_gradle(path: Path) -> bool:
    """Appends a `subprojects { ... }` block that forces every plugin
    subproject's compileSdk, not just the app module's. See point 3 in the
    module docstring for why this is necessary. Returns True if this was the
    build.gradle(.kts) file that exists and got handled."""
    if not path.exists():
        return False

    text = path.read_text()

    if SUBPROJECTS_MARKER in text:
        print(f"  (no changes needed) {path}")
        return True

    block = SUBPROJECTS_BLOCK_KTS if path.suffix == ".kts" else SUBPROJECTS_BLOCK_GROOVY
    text = text.rstrip("\n") + "\n" + block
    path.write_text(text)
    print(f"  + appended subprojects compileSdk={COMPILE_SDK} override to {path}")
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

    for gradle_file in ROOT_BUILD_GRADLE_PATHS:
        if patch_root_build_gradle(gradle_file):
            break
    else:
        print(
            "  (skip) no android/build.gradle(.kts) found yet — "
            "run `flutter create --platforms=android .` first."
        )

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
