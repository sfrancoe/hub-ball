#!/usr/bin/env python3
"""Run deterministic App Store readiness checks for the native iOS app.

This is intentionally dependency-free. It catches project and packaging problems
before TestFlight; judgment calls from Apple's review guidelines remain manual.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS_ROOT = ROOT / "ios" / "Hub Ball"
SOURCE_ROOT = IOS_ROOT / "Hub Ball"
PROJECT = IOS_ROOT / "Hub Ball.xcodeproj"
PBXPROJ = PROJECT / "project.pbxproj"
APP_ICON = SOURCE_ROOT / "Assets.xcassets" / "AppIcon.appiconset"
PRIVACY_MANIFEST = SOURCE_ROOT / "PrivacyInfo.xcprivacy"
METADATA = ROOT / "app-store" / "metadata.json"
EXPECTED_BUNDLE_ID = "com.sfrancoe.HubBall"

PAID_OR_METERED_ENDPOINTS = {"https://red-sox.netlify.app/api/x-discovery"}
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
KNOWN_ENDPOINTS = {
    "https://red-sox.netlify.app/api/x-discovery",
    "https://red-sox.netlify.app/api/x-posts",
    "https://red-sox.netlify.app/api/hr-chase",
    "https://red-sox.netlify.app/api/mlb/schedule?team=red-sox",
    "https://red-sox.netlify.app/api/mlb/standings?team=redsox",
    "https://red-sox.netlify.app/api/postseason?season=2026",
    "https://red-sox.netlify.app/api/data/athletic.json",
    "https://red-sox.netlify.app/api/data/globe.json",
    "https://red-sox.netlify.app/api/data/herald.json",
    "https://red-sox.netlify.app/api/data/masslive.json",
    "https://red-sox.netlify.app/api/data/meta.json",
    "https://red-sox.netlify.app/api/data/pitching.json",
    "https://red-sox.netlify.app/api/data/players.json",
    "https://red-sox.netlify.app/api/data/recent-game.json",
    "https://red-sox.netlify.app/api/data/schedule.json",
    "https://red-sox.netlify.app/api/data/seasons.json",
    "https://red-sox.netlify.app/api/data/standings.json",
}
# Editorial citations open in the browser; they are not application data feeds.
EDITORIAL_LINKS = {
    "https://malaysia.news.yahoo.com/brewers-clinch-playoffs-become-first-team-in-mlb-history-to-record-multiple-shutout-wins-of-20-plus-runs-in-a-season-121406831.html",
    "https://www.mlb.com/gameday/824708",
    "https://x.com/gingersnaphyde/status/2099245461748002821",
}
PUBLIC_WEB_PAGES = {
    "https://testflight.apple.com/",
    "https://red-sox.netlify.app/october/",
    "https://www.mlb.com/stats/batting-average/2026",
}
JSON_PROBE_OVERRIDES = {
    "https://red-sox.netlify.app": "https://red-sox.netlify.app/api/data/meta.json",
    # A configured data directory is not a JSON document; probe a real feed.
    "https://red-sox.netlify.app/api/data": "https://red-sox.netlify.app/api/data/meta.json",
    "https://api.autumnlane.io": "https://api.autumnlane.io/api/data/meta.json",
    "https://api.autumnlane.io/api/data": "https://api.autumnlane.io/api/data/meta.json",
    "https://statsapi.mlb.com": "https://statsapi.mlb.com/api/v1/teams/111",
}
UNLICENSED_RUNTIME_HOSTS = {"statsapi.mlb.com", "img.mlbstatic.com"}


@dataclass(frozen=True)
class Check:
    status: str
    name: str
    detail: str


def result(status: str, name: str, detail: str) -> Check:
    return Check(status=status, name=name, detail=detail)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def setting_values(project_text: str, key: str) -> list[str]:
    pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.+?);\s*$", re.MULTILINE)
    return sorted({match.group(1).strip().strip('"') for match in pattern.finditer(project_text)})


def application_settings_text(project_file: Path) -> str:
    """Inspect the shipped application, excluding unit-test target identities."""
    completed = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(project_file)], capture_output=True, text=True, check=True)
    project = json.loads(completed.stdout)
    objects = project['objects']
    apps = [objects[key] for key in objects[project['rootObject']]['targets']
            if objects[key].get('productType') == 'com.apple.product-type.application']
    if len(apps) != 1:
        raise ValueError('Expected exactly one application target')
    configurations = objects[apps[0]['buildConfigurationList']]['buildConfigurations']
    return '\n'.join(f'{key} = {value};' for configuration in configurations
                     for key, value in objects[configuration]['buildSettings'].items())


def check_project_settings(project_text: str) -> list[Check]:
    checks: list[Check] = []
    bundle_ids = setting_values(project_text, "PRODUCT_BUNDLE_IDENTIFIER")
    if bundle_ids == [EXPECTED_BUNDLE_ID]:
        checks.append(result("PASS", "Bundle identifier", EXPECTED_BUNDLE_ID))
    elif bundle_ids:
        checks.append(
            result(
                "FAIL",
                "Bundle identifier",
                f"Expected {EXPECTED_BUNDLE_ID}; found {', '.join(bundle_ids)}.",
            )
        )
    else:
        checks.append(result("FAIL", "Bundle identifier", "PRODUCT_BUNDLE_IDENTIFIER is missing."))

    versions = setting_values(project_text, "MARKETING_VERSION")
    builds = setting_values(project_text, "CURRENT_PROJECT_VERSION")
    if versions and builds:
        checks.append(result("PASS", "Version and build", f"Version {versions[0]}, build {builds[0]}"))
    else:
        checks.append(result("FAIL", "Version and build", "Marketing version or build number is missing."))

    teams = setting_values(project_text, "DEVELOPMENT_TEAM")
    checks.append(
        result("PASS", "Signing team", "An Apple development team is configured.")
        if teams
        else result("FAIL", "Signing team", "No Apple development team is configured.")
    )

    families = setting_values(project_text, "TARGETED_DEVICE_FAMILY")
    if any("2" in value.split(",") for value in families):
        checks.append(
            result(
                "WARN",
                "iPad support",
                "The target includes iPad. Test every screen on iPad or make version 1 iPhone-only.",
            )
        )
    elif families:
        checks.append(result("PASS", "Device family", "The target is configured for iPhone."))
    else:
        checks.append(result("WARN", "Device family", "TARGETED_DEVICE_FAMILY was not found."))
    return checks


def check_app_icon() -> Check:
    contents_path = APP_ICON / "Contents.json"
    if not contents_path.exists():
        return result("FAIL", "App icon", "The AppIcon asset catalog is missing.")
    try:
        contents = json.loads(read_text(contents_path))
    except (json.JSONDecodeError, OSError) as exc:
        return result("FAIL", "App icon", f"Contents.json cannot be read: {exc}")
    filenames = [image.get("filename") for image in contents.get("images", []) if image.get("filename")]
    existing = [name for name in filenames if (APP_ICON / name).is_file()]
    if not existing:
        return result("FAIL", "App icon", "No 1024×1024 App Store icon file is assigned.")
    return result("PASS", "App icon", f"Assigned icon asset: {existing[0]}")


def check_privacy_manifest() -> Check:
    if not PRIVACY_MANIFEST.exists():
        return result(
            "FAIL",
            "Privacy manifest",
            "PrivacyInfo.xcprivacy is missing. Confirm data collection and required-reason APIs.",
        )
    try:
        with PRIVACY_MANIFEST.open("rb") as handle:
            manifest = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        return result("FAIL", "Privacy manifest", f"The manifest is not a valid property list: {exc}")
    if not isinstance(manifest, dict):
        return result("FAIL", "Privacy manifest", "The manifest must contain a dictionary.")
    accessed = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(accessed, list) or any(not isinstance(entry, dict) for entry in accessed):
        return result("FAIL", "Privacy manifest", "NSPrivacyAccessedAPITypes must be an array of dictionaries.")
    uses_defaults = any(
        re.search(r"\bUserDefaults\b|@AppStorage\b", release_source(path))
        for path in swift_sources()
    )
    if uses_defaults and not any(
        entry.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
        and isinstance(entry.get("NSPrivacyAccessedAPITypeReasons"), list)
        and "CA92.1" in entry["NSPrivacyAccessedAPITypeReasons"]
        for entry in accessed
    ):
        return result(
            "FAIL", "Privacy manifest",
            "App-local UserDefaults/@AppStorage requires the UserDefaults category with reason CA92.1.",
        )
    return result("PASS", "Privacy manifest", "Manifest is readable and app-local UserDefaults usage is declared.")


def check_metadata() -> list[Check]:
    if not METADATA.exists():
        return [
            result(
                "WARN",
                "App Store metadata",
                "app-store/metadata.json is not complete yet (privacy URL, support URL, and review notes).",
            )
        ]
    try:
        data = json.loads(read_text(METADATA))
    except (json.JSONDecodeError, OSError) as exc:
        return [result("FAIL", "App Store metadata", f"metadata.json cannot be read: {exc}")]
    checks: list[Check] = []
    for key, label in (
        ("app_name", "App name"),
        ("subtitle", "App subtitle"),
        ("description", "App description"),
        ("privacy_policy_url", "Privacy policy URL"),
        ("support_url", "Support URL"),
        ("review_notes", "App Review notes"),
    ):
        value = str(data.get(key, "")).strip()
        checks.append(
            result("PASS", label, "Provided.")
            if value and "TODO" not in value.upper()
            else result("WARN", label, "Not completed yet.")
        )
    return checks


def check_unlicensed_runtime_sources() -> Check:
    findings: list[str] = []
    paths = swift_sources() + [SOURCE_ROOT / "players.json"]
    for path in paths:
        if not path.exists():
            continue
        contents = read_text(path)
        for host in UNLICENSED_RUNTIME_HOSTS:
            if host in contents:
                findings.append(f"{path.name}: {host}")
    if findings:
        return result(
            "FAIL",
            "Production data sources",
            "Prototype-only MLB endpoints remain in the app: " + ", ".join(findings),
        )
    return result("PASS", "Production data sources", "No prototype-only MLB endpoints are bundled.")


def swift_sources() -> list[Path]:
    return sorted(SOURCE_ROOT.glob("*.swift"))


def release_source(path: Path) -> str:
    """Return Swift source with DEBUG-only compilation blocks removed."""
    return re.sub(r"^\s*#if DEBUG\b.*?^\s*#endif\b", "", read_text(path), flags=re.MULTILINE | re.DOTALL)


def check_placeholders() -> Check:
    findings: list[str] = []
    patterns = re.compile(r"\b(TODO|FIXME|Lorem ipsum)\b|example\.com|localhost|127\.0\.0\.1", re.IGNORECASE)
    for path in swift_sources():
        for number, line in enumerate(release_source(path).splitlines(), start=1):
            if patterns.search(line):
                findings.append(f"{path.name}:{number}")
    if findings:
        return result("WARN", "Placeholder content", "Review " + ", ".join(findings[:8]))
    return result("PASS", "Placeholder content", "No obvious placeholders or local-only URLs found.")


def discovered_urls() -> list[str]:
    urls = set(KNOWN_ENDPOINTS)
    pattern = re.compile(r'https://[^"\s)]+')
    for path in swift_sources():
        urls.update(url for url in pattern.findall(read_text(path)) if "\\(" not in url)
    return sorted(urls)


def check_transport_security() -> Check:
    insecure = [path.name for path in swift_sources() if "http://" in release_source(path)]
    if insecure:
        return result("FAIL", "Network security", "Insecure HTTP URLs found in " + ", ".join(insecure))
    return result("PASS", "Network security", "All hard-coded app endpoints use HTTPS.")


def fetch_url(url: str, fallback: bool = False) -> tuple[int, bytes]:
    headers = {
        "Accept": "text/html" if url in EDITORIAL_LINKS or url in PUBLIC_WEB_PAGES else "application/json"
    }
    if fallback:
        headers["User-Agent"] = FALLBACK_USER_AGENT
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.status, response.read(1_500_000)


def check_live_endpoints() -> list[Check]:
    checks: list[Check] = []
    for url in discovered_urls():
        if url in PAID_OR_METERED_ENDPOINTS:
            checks.append(result("SKIP", "Live endpoint", f"Skipped metered endpoint: {url}"))
            continue
        probe_url = JSON_PROBE_OVERRIDES.get(url, url)
        try:
            status, payload = fetch_url(probe_url)
        except urllib.error.HTTPError as exc:
            if exc.code in {403, 429, 503}:
                try:
                    status, payload = fetch_url(probe_url, fallback=True)
                except Exception as fallback_exc:  # noqa: BLE001
                    checks.append(result("FAIL", "Live endpoint", f"{url}: {fallback_exc}"))
                    continue
            else:
                checks.append(result("FAIL", "Live endpoint", f"{url}: HTTP {exc.code}"))
                continue
        except Exception as exc:  # noqa: BLE001
            checks.append(result("FAIL", "Live endpoint", f"{url}: {exc}"))
            continue
        if url in EDITORIAL_LINKS:
            valid_html = b"<html" in payload.lower() and b"<title" in payload.lower()
            checks.append(result("PASS" if valid_html else "FAIL", "Editorial source link",
                                 f"HTTP {status}: {url}" if valid_html else f"{url}: expected an HTML page"))
            continue
        if url in PUBLIC_WEB_PAGES:
            valid_html = b"<html" in payload.lower() and b"<title" in payload.lower()
            checks.append(result("PASS" if valid_html else "FAIL", "Public web page",
                                 f"HTTP {status}: {url}" if valid_html else f"{url}: expected an HTML page"))
            continue
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
            checks.append(result("FAIL", "Live endpoint", f"{url}: response is not valid JSON"))
            continue
        if "/api/mlb/standings" in url:
            if parsed.get("freshness") != "live" or not parsed.get("source_updated_at"):
                checks.append(result("FAIL", "Live standings", f"{url}: live data is unavailable"))
                continue
            divisions = parsed.get("divisions") or []
            if len(divisions) != 3 or not parsed.get("wild_card"):
                checks.append(result("FAIL", "Live standings", f"{url}: standings are incomplete"))
                continue
        checks.append(result("PASS", "Live endpoint", f"HTTP {status}: {url}"))
    return checks


def run_release_build() -> Check:
    with tempfile.TemporaryDirectory(prefix="hub-ball-app-store-") as derived_data:
        command = [
            "xcodebuild",
            "-quiet",
            "-project",
            str(PROJECT),
            "-scheme",
            "Hub Ball",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=iOS",
            "-derivedDataPath",
            derived_data,
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=240,
                check=False,
            )
        except FileNotFoundError:
            return result("FAIL", "Release build", "Xcode command-line tools are unavailable.")
        except subprocess.TimeoutExpired:
            return result("FAIL", "Release build", "The unsigned Release build timed out after four minutes.")
    if completed.returncode == 0:
        return result("PASS", "Release build", "Unsigned generic-device Release build succeeded.")
    output = (completed.stderr or completed.stdout).strip().splitlines()
    detail = output[-1] if output else "xcodebuild failed without an error message."
    return result("FAIL", "Release build", detail)


def manual_review_checks() -> list[Check]:
    return [
        result(
            "WARN",
            "Trademark and affiliation",
            "Confirm permission and presentation for team names; keep clear unofficial-app language.",
        ),
        result(
            "WARN",
            "Third-party content",
            "Confirm terms/permission for newspaper and X content, attribution, excerpts, and external links.",
        ),
        result(
            "WARN",
            "Native usefulness",
            "Document live scores, box scores, schedule, standings, stats, and the animated graph in review notes.",
        ),
        result(
            "WARN",
            "Offline behavior",
            "Before submission, test every screen with slow, unavailable, and stale backend data.",
        ),
    ]


def render(checks: list[Check], json_output: bool) -> None:
    counts = {status: sum(check.status == status for check in checks) for status in ("PASS", "WARN", "FAIL", "SKIP")}
    if json_output:
        print(json.dumps({"summary": counts, "checks": [asdict(check) for check in checks]}, indent=2))
        return
    icons = {"PASS": "✓", "WARN": "!", "FAIL": "✗", "SKIP": "–"}
    print("\nHub Ball — App Store preflight\n")
    for check in checks:
        print(f"{icons[check.status]} {check.status:<4}  {check.name}")
        print(f"        {check.detail}")
    print(
        f"\nSummary: {counts['PASS']} passed, {counts['WARN']} warnings, "
        f"{counts['FAIL']} failed, {counts['SKIP']} skipped."
    )
    if counts["FAIL"]:
        print("Not ready for TestFlight yet. Fix failed checks first.")
    elif counts["WARN"]:
        print("Build-ready, with review decisions still to resolve before submission.")
    else:
        print("Automated checks passed. Final Apple validation and human review are still required.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="Skip the unsigned Release build.")
    parser.add_argument("--network", action="store_true", help="Check live non-metered JSON endpoints.")
    parser.add_argument("--json", action="store_true", help="Print a machine-readable report.")
    args = parser.parse_args()
    if not PBXPROJ.exists():
        render([result("FAIL", "Xcode project", f"Missing {PBXPROJ}")], args.json)
        return 1
    project_text = application_settings_text(PBXPROJ)
    checks = [result("PASS", "Xcode project", str(PROJECT.relative_to(ROOT)))]
    checks.extend(check_project_settings(project_text))
    checks.append(check_app_icon())
    checks.append(check_privacy_manifest())
    checks.extend(check_metadata())
    checks.append(check_placeholders())
    checks.append(check_transport_security())
    checks.append(check_unlicensed_runtime_sources())
    if args.network:
        checks.extend(check_live_endpoints())
    else:
        checks.append(result("SKIP", "Live endpoints", "Run again with --network before TestFlight."))
    checks.append(
        result("SKIP", "Release build", "Skipped by command-line option.")
        if args.skip_build
        else run_release_build()
    )
    checks.extend(manual_review_checks())
    render(checks, args.json)
    return 1 if any(check.status == "FAIL" for check in checks) else 0


if __name__ == "__main__":
    sys.exit(main())
