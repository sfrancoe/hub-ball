#!/usr/bin/env python3
"""Validate and stage a dated featured pointer; publication is a separate Git operation."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from story_content import decode, digest, encoded, entry_path, identifier, integer, require, timestamp, validate_entry, validate_payload, PAYLOAD_LIMIT

LIMIT = 16 * 1024

def validate(value):
    require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1, 'Unsupported featured schema')
    require(type(value['enabled']) is bool, 'Invalid enablement')
    identifier(value['revision'])
    integer(value['minimumBuild'], 1, 1000000)
    for key in ['publishedAt', 'notBefore', 'expiresAt']:
        timestamp(value[key])
    dates = {key: datetime.strptime(value[key], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc) for key in ['publishedAt','notBefore','expiresAt']}
    require(0 < (dates['expiresAt'] - dates['notBefore']).total_seconds() <= 7 * 86400, 'Window must be at most seven days')
    require(dates['publishedAt'] <= dates['expiresAt'], 'Publication after expiry')
    if value['enabled']:
        validate_entry(value['entry'])
        require(value['entry']['rendererVersion'] == 1 and value['entry']['renderer'] in ['guess-reveal','chart-trajectory','inning-out-grid'], 'Unsupported bundled renderer')
    else:
        require(value['entry'] is None, 'Disabled pointer must have no entry')
    return value

def validate_tree(data_root: Path):
    manifest = validate(decode((data_root/'stories/featured-v1.json').read_bytes(), LIMIT))
    if manifest['enabled']:
        entry = manifest['entry']; payload = (data_root/entry_path(entry)).read_bytes()
        require(digest(payload) == entry['revision'], 'Immutable payload hash mismatch')
        document = validate_payload(decode(payload, PAYLOAD_LIMIT), entry)
        if document.get('presentation'):
            require(manifest['expiresAt'] <= document['presentation']['hookExpiresAt'], 'Opening cannot outlive its time-sensitive hook')
    return manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate', type=Path, help='Validate an existing data directory')
    parser.add_argument('--manifest', type=Path, help='Reviewed featured JSON pointer')
    parser.add_argument('--payload', type=Path, help='Reviewed immutable payload')
    parser.add_argument('--output', type=Path, help='Local staging data directory; never publishes')
    args = parser.parse_args()
    if args.validate:
        value = validate_tree(args.validate)
    else:
        require(args.manifest and args.output, 'Need manifest and output')
        value = validate(decode(args.manifest.read_bytes(), LIMIT))
        if value['enabled']:
            require(args.payload, 'Need payload')
            payload = args.payload.read_bytes(); entry = value['entry']
            require(digest(payload) == entry['revision'], 'Immutable payload hash mismatch')
            validate_payload(decode(payload, PAYLOAD_LIMIT), entry)
            target = args.output/entry_path(entry)
            require(not target.exists() or target.read_bytes() == payload, 'Cannot overwrite immutable payload')
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(payload)
        target = args.output/'stories/featured-v1.json'; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(encoded(value)); validate_tree(args.output)
    print('Validated featured pointer:', value['revision'])

if __name__ == '__main__':
    main()
