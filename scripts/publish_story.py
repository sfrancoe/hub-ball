#!/usr/bin/env python3
"""Stage or roll back a LOCAL story catalog. Never commits, pushes, deploys or uploads."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile
from datetime import datetime, timezone
from uuid import uuid4
from story_content import CATALOG_LIMIT, PAYLOAD_LIMIT, decode, digest, encoded, entry_path, require, validate_catalog, validate_payload, validate_tree


def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as scratch:
        scratch.write(data)
        name = scratch.name
    try:
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def check_payloads(catalog, root):
    for entry in catalog['stories']:
        data = (root / entry_path(entry)).read_bytes()
        require(digest(data) == entry['revision'], 'Missing or corrupt staged payload')
        validate_payload(decode(data, PAYLOAD_LIMIT), entry)


def switch_catalog(catalog, root):
    validate_catalog(catalog)
    check_payloads(catalog, root)  # Do all fallible validation before switching the pointer.
    path = root / 'stories/catalog-v1.json'
    if path.exists():
        previous = validate_catalog(decode(path.read_bytes(), CATALOG_LIMIT))
        atomic_write(root / f"stories/catalog-history/{previous['revision']}.json", encoded(previous))
    atomic_write(path, encoded(catalog))


def stage(payload_path, root, summary, teams, published_at=None):
    data = payload_path.read_bytes()
    payload = validate_payload(decode(data, PAYLOAD_LIMIT))
    path = root / 'stories/catalog-v1.json'
    previous = validate_tree(root) if path.exists() else {'stories': []}
    timestamp = published_at or now()
    entry = {'id': payload['id'], 'revision': digest(data), 'title': payload['title'], 'summary': summary,
             'fallback': payload.get('answer') or payload.get('conclusion') or payload.get('commentary') or payload['payoff'], 'teamIDs': teams, 'publishedAt': timestamp,
             'renderer': payload['renderer'], 'rendererVersion': payload['rendererVersion'], 'minimumRendererVersion': 6 if payload['renderer']=='grouped-unit-grid' else 4 if payload['renderer'] == 'inning-out-grid' else (5 if payload.get('presentation') else 3 if payload['chart'].get('sequence') or any(b.get('comparison') for b in payload['chart']['emphasis']) else 2) if payload['renderer'] == 'chart-trajectory' else 1}
    catalog = {'schemaVersion': 1, 'revision': 'release-' + uuid4().hex, 'publishedAt': timestamp,
               'stories': [entry] + [e for e in previous['stories'] if e['id'] != entry['id']]}
    validate_catalog(catalog)
    require(len(encoded(catalog)) <= CATALOG_LIMIT, 'Catalog exceeds limit')
    immutable = root / entry_path(entry)
    require(not immutable.exists() or immutable.read_bytes() == data, 'Refusing to replace immutable content')
    if not immutable.exists():
        atomic_write(immutable, data)
    switch_catalog(catalog, root)
    return catalog


def rollback(prior_path, root):
    prior = validate_catalog(decode(prior_path.read_bytes(), CATALOG_LIMIT))
    catalog = {**prior, 'revision': 'rollback-' + uuid4().hex, 'publishedAt': now()}
    switch_catalog(catalog, root)
    return catalog


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    stage_parser = sub.add_parser('stage')
    stage_parser.add_argument('--payload', type=Path, required=True)
    stage_parser.add_argument('--summary', required=True)
    stage_parser.add_argument('--teams', required=True, help='Comma-separated MLB IDs')
    stage_parser.add_argument('--published-at')
    stage_parser.add_argument('--data-root', type=Path, required=True, help='Explicit local staging directory')
    rollback_parser = sub.add_parser('rollback')
    rollback_parser.add_argument('--catalog', type=Path, required=True, help='Previously saved catalog')
    rollback_parser.add_argument('--data-root', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'stage':
        result = stage(args.payload, args.data_root, args.summary, [int(t) for t in args.teams.split(',')], args.published_at)
    else:
        result = rollback(args.catalog, args.data_root)
    print(f"LOCAL {args.action}: {len(result['stories'])} stories, {result['revision']}")
    print('Nothing committed, pushed, deployed or distributed.')
