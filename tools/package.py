#!/usr/bin/env python3
"""Package the corresponding source and checksum the Android/iOS deliverables."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "artifacts"
SOURCE_DIRECTORIES = (
    "lib", "android", "ios", "assets", "vendor", "test",
    "integration_test", "test_driver", "docs", "tools",
)
SOURCE_FILES = (
    ".gitignore", ".gitattributes", ".metadata", "LICENSE", "README.md",
    "analysis_options.yaml", "pubspec.yaml", "pubspec.lock",
)
SKIP_DIRECTORIES = {
    ".git", ".idea", ".dart_tool", ".gradle", ".kotlin", ".cxx",
    ".swiftpm", ".symlinks", ".generated", "__pycache__", "build",
    "ephemeral", "Pods", "DerivedData", "xcuserdata",
}
SKIP_PATHS = {
    "android/app/debug", "android/app/profile", "android/app/release",
}
SKIP_NAMES = {
    ".DS_Store", ".last_build_id", "local.properties", "key.properties",
    "Generated.xcconfig", "flutter_export_environment.sh", "Flutter.podspec",
}
SKIP_SUFFIXES = {
    ".iml", ".log", ".pyc", ".keystore", ".jks", ".p12", ".p8",
    ".pem", ".mobileprovision", ".xcuserstate",
}


def source_files():
    for name in SOURCE_FILES:
        yield ROOT / name
    for name in SOURCE_DIRECTORIES:
        for directory, subdirs, files in os.walk(ROOT / name):
            parent = Path(directory)
            subdirs[:] = sorted(
                child for child in subdirs
                if child not in SKIP_DIRECTORIES
                and (parent / child).relative_to(ROOT).as_posix() not in SKIP_PATHS
                and not (parent / child).is_symlink()
            )
            for filename in sorted(files):
                path = parent / filename
                if (
                    path.is_symlink()
                    or filename in SKIP_NAMES
                    or path.suffix in SKIP_SUFFIXES
                    or filename == ".env"
                    or filename.startswith(".env.")
                    or filename.startswith("GeneratedPluginRegistrant.")
                ):
                    continue
                yield path


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_zip(path):
    with zipfile.ZipFile(path) as archive:
        invalid = archive.testzip()
        if invalid is not None:
            raise RuntimeError(f"Corrupt ZIP member: {path.name}: {invalid}")
        return len(archive.infolist())


def signing_info(path, kind):
    if kind == "release-apk":
        signer = shutil.which("apksigner")
        sdk_roots = (
            os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME"),
            Path.home() / "Library/Android/sdk", Path.home() / "Android/Sdk",
        )
        for sdk in sdk_roots:
            if signer or not sdk:
                continue
            candidates = sorted(Path(sdk).glob("build-tools/*/apksigner"))
            if candidates:
                signer = str(candidates[-1])
        if signer is None:
            return {"configuration": "not-inspected", "verified": False}
        result = subprocess.run(
            [signer, "verify", "--verbose", "--print-certs", str(path)],
            check=True, capture_output=True, text=True,
        )
        subject = re.search(r"certificate DN: (.+)", result.stdout)
        digest = re.search(r"certificate SHA-256 digest: (.+)", result.stdout)
        name = subject.group(1) if subject else "unknown"
        return {
            "configuration": "local-test-debug-key" if "CN=Android Debug" in name else "signed",
            "verified": True, "certificate_subject": name,
            "certificate_sha256": digest.group(1) if digest else None,
        }
    if kind in {"release-app-bundle", "arm64-xcarchive"}:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
        if kind == "release-app-bundle":
            signed = any(
                name.startswith("META-INF/") and name.endswith((".RSA", ".DSA", ".EC"))
                for name in names
            )
        else:
            signed = any(
                name.endswith("/Products/Applications/Runner.app/_CodeSignature/CodeResources")
                for name in names
            )
        return {"configuration": "signature-present" if signed else "unsigned", "verified": False}
    return {"configuration": "simulator-only" if kind == "simulator-app" else "not-applicable"}


def main():
    match = re.search(
        r"^version:\s*(\S+)\s*$", (ROOT / "pubspec.yaml").read_text(), re.MULTILINE
    )
    if match is None:
        raise RuntimeError("Missing app version in pubspec.yaml")
    version = match.group(1)
    prefix = f"Onyx-Mobile-{version.split('+')[0]}"
    OUTPUT.mkdir(exist_ok=True)
    source = OUTPUT / f"{prefix}-Source.zip"
    temporary = source.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in source_files():
            archive.write(path, f"{prefix}-Source/{path.relative_to(ROOT).as_posix()}")
    check_zip(temporary)
    temporary.replace(source)

    specifications = (
        (f"{prefix}-Android.apk", "android", "release-apk"),
        (f"{prefix}-Android.aab", "android", "release-app-bundle"),
        (f"{prefix}-iOS-Archive.zip", "ios", "arm64-xcarchive"),
        (f"{prefix}-iOS-Simulator.zip", "ios", "simulator-app"),
        (source.name, "android+ios", "corresponding-source"),
    )
    artifacts = []
    for name, platform, kind in specifications:
        path = OUTPUT / name
        if not path.is_file():
            raise RuntimeError(f"Build this artifact before packaging: {name}")
        entries = check_zip(path)
        artifacts.append({
            "file": name, "platform": platform, "kind": kind,
            "signing": signing_info(path, kind), "bytes": path.stat().st_size,
            "sha256": checksum(path), "zip_entries": entries, "zip_crc": "passed",
        })
        print(f"{name}: {path.stat().st_size:,} bytes; ZIP CRC passed")

    toolchain = json.loads((ROOT / "tools/toolchain.json").read_text())
    provenance = json.loads((ROOT / "vendor/onyx/upstream.json").read_text())
    manifest = {
        "name": "Onyx Mobile", "version": version, "app_id": toolchain["app_id"],
        "packaged_utc": datetime.now(timezone.utc).isoformat(),
        "toolchain": toolchain, "upstream": provenance, "license": "GPL-3.0-only",
        "validation_report": "docs/TESTING.md",
        "distribution_instructions": "docs/DISTRIBUTION.md",
        "store_published": False,
        "physical_amplifier_ble_verified": False,
        "artifacts": artifacts,
    }
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
