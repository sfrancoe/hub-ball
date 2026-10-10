#!/usr/bin/env python3
"""Prepare a broad TestFlight target locally after fresh Apple verification. Never deploys."""
import argparse
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
APP = '6809478747'
BUNDLE = 'com.sfrancoe.HubBall'
GROUPS = {'a7c07355-b794-49b9-b36d-75c129c8d6bb', '58b84a1e-c8ab-4b73-9948-3362b4569fd1'}
OUTPUT = ROOT / 'data/releases/testflight-v1.json'


def request(path: str) -> dict:
    """Use existing local release credentials. Nothing is embedded in the app/manifest."""
    config = json.loads((Path.home() / '.config/hub-ball/app-store-connect.json').read_text())
    key = Path(config['key_path']).expanduser()
    if key.stat().st_mode & 0o077:
        raise ValueError('Signing key permissions are not private')
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
    now = int(time.time())
    header = encode(json.dumps({'alg': 'ES256', 'kid': config['key_id'], 'typ': 'JWT'}).encode())
    payload = encode(json.dumps({'iss': config['issuer_id'], 'iat': now, 'exp': now + 120, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + b'.' + payload
    signature = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(key)], input=message, capture_output=True, check=True).stdout
    if signature[0] != 48 or signature[2] != 2:
        raise ValueError('Unexpected signing encoding')
    length = signature[3]; r = signature[4:4 + length]; offset = 4 + length
    if signature[offset] != 2:
        raise ValueError('Unexpected signing encoding')
    length = signature[offset + 1]; s = signature[offset + 2:offset + 2 + length]
    token = (message + b'.' + encode(int.from_bytes(r, 'big').to_bytes(32, 'big') + int.from_bytes(s, 'big').to_bytes(32, 'big'))).decode()
    if not path.startswith('/v1/') or '://' in path:
        raise ValueError('Apple API path required')
    req = urllib.request.Request('https://api.appstoreconnect.apple.com' + path, headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def complete(path: str, fetch=request) -> dict:
    value = fetch(path)
    if value.get('links', {}).get('next'):
        raise ValueError('Additional Apple pages require inspection; do not publish a partial audience')
    return value


def verified_target(build: int, receipt: dict, info: dict, fetch=request, now=None) -> dict:
    now = now or datetime.now(timezone.utc)
    if not (receipt['build'] == build and receipt.get('uploadStatus', receipt['status']) == 'upload_command_succeeded'):
        raise ValueError('Exact build upload receipt required')
    if not (info['CFBundleIdentifier'] == BUNDLE and int(info['CFBundleVersion']) == build):
        raise ValueError('Apple release verification failed')
    if not (set(info['UIDeviceFamily']) == {1, 2}):
        raise ValueError('Broad target must support iPhone and iPad')
    groups = complete(f'/v1/apps/{APP}/betaGroups?limit=200', fetch)['data']
    if not ({g['id'] for g in groups} == GROUPS):
        raise ValueError('Unknown supported tester groups: fail open')
    response = complete(f'/v1/builds?filter[app]={APP}&filter[version]={build}&include=preReleaseVersion,buildBetaDetail&limit=200', fetch)
    if not (len(response['data']) == 1):
        raise ValueError('Apple release verification failed')
    b = response['data'][0]; attrs = b['attributes']; bid = b['id']
    if not (attrs['processingState'] == 'VALID' and attrs.get('expired') is False):
        raise ValueError('Apple release verification failed')
    expiry = datetime.fromisoformat(attrs['expirationDate'].replace('Z', '+00:00'))
    if not (now < expiry and (expiry - now).total_seconds() <= 90 * 86400):
        raise ValueError('Apple release verification failed')
    version = next(x['attributes']['version'] for x in response['included'] if x['type'] == 'preReleaseVersions')
    if not (version == receipt['version'] == info['CFBundleShortVersionString']):
        raise ValueError('Apple release verification failed')
    if not (attrs['minOsVersion'] == info['MinimumOSVersion']):
        raise ValueError('Archive and Apple OS support disagree')
    detail = next(x['attributes'] for x in response['included'] if x['type'] == 'buildBetaDetails')
    if not (detail['internalBuildState'] == 'IN_BETA_TESTING' and detail['externalBuildState'] == 'IN_BETA_TESTING'):
        raise ValueError('Apple release verification failed')
    for group in groups:
        builds = complete(f"/v1/betaGroups/{group['id']}/builds?limit=200", fetch)['data']
        if not (any(x['id'] == bid for x in builds)):
            raise ValueError('Private or unavailable build: cannot advance broad target')
    return {'version': version, 'build': build, 'audience': 'all-supported-testers', 'available': True,
            'confirmedAt': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'expiresAt': expiry.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'minimumOS': info['MinimumOSVersion'], 'deviceFamilies': ['iphone', 'ipad'], 'verifiedGroupIDs': sorted(GROUPS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--disable', action='store_true')
    group.add_argument('--build', type=int)
    args = parser.parse_args()
    target = None
    if args.build is not None:
        matches = list((Path.home() / 'Library/Application Support/Hub Ball Releases').glob(f'*-{args.build}.json'))
        if not (len(matches) == 1):
            raise ValueError('Resolve the exact version/build receipt before publishing')
        receipt = json.loads(matches[0].read_text())
        info = plistlib.loads((Path(receipt['output']) / 'Hub Ball.xcarchive/Products/Applications/Hub Ball.app/Info.plist').read_bytes())
        target = verified_target(args.build, receipt, info)
        if OUTPUT.exists():
            previous = json.loads(OUTPUT.read_text()).get('target')
            if previous:
                if not (target['build'] >= previous['build']):
                    raise ValueError('Broad sequence must not move backwards')
    manifest = {'schemaVersion': 1, 'bundleID': BUNDLE, 'enabled': target is not None, 'target': target}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT.with_suffix('.tmp'); temporary.write_text(json.dumps(manifest, indent=2) + '\n'); temporary.replace(OUTPUT)
    print(f'Prepared locally: {OUTPUT}; enabled={manifest["enabled"]}. No push or deployment performed.')


if __name__ == '__main__':
    main()
