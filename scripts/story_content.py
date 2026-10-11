"""Versioned editorial story contract. Standard library only; never executes content."""
import hashlib
import json
import math
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

CATALOG_LIMIT = 128 * 1024
PAYLOAD_LIMIT = 512 * 1024
SLUG = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*\Z')
HASH = re.compile(r'[a-f0-9]{64}\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value, limit=2000):
    require(isinstance(value, str) and 0 < len(value) <= limit and not any(ord(c) < 32 and c not in '\n\t' for c in value), 'Invalid text')


def identifier(value):
    require(isinstance(value, str) and len(value) <= 80 and SLUG.fullmatch(value), 'Invalid identifier')


def timestamp(value):
    require(isinstance(value, str) and value.endswith('Z'), 'Expected UTC timestamp')
    datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ')


def integer(value, lower=0, upper=100000):
    require(type(value) is int and lower <= value <= upper, 'Invalid integer')


def unique(items):
    require(len({row['id'] for row in items}) == len(items), 'Duplicate identifiers')


def decode(data, limit):
    require(len(data) <= limit, 'Content exceeds size limit')
    def no_duplicates(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=no_duplicates, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Non-finite number')))


def entry_path(entry):
    identifier(entry['id'])
    require(isinstance(entry['revision'], str) and HASH.fullmatch(entry['revision']), 'Invalid revision hash')
    return f"stories/{entry['id']}/{entry['revision']}.json"


def validate_entry(entry):
    entry_path(entry)
    for field, limit in [('title', 160), ('summary', 400), ('fallback', 2000)]:
        text(entry[field], limit)
    identifier(entry['renderer'])
    integer(entry['rendererVersion'], 1, 100)
    integer(entry['minimumRendererVersion'], 1, 100)
    timestamp(entry['publishedAt'])
    teams = entry['teamIDs']
    require(isinstance(teams, list) and len(teams) <= 30 and len(set(teams)) == len(teams), 'Invalid team list')
    for team in teams:
        integer(team, 1, 1000)


def validate_catalog(catalog):
    require(type(catalog['schemaVersion']) is int and catalog['schemaVersion'] == 1, 'Unsupported catalog schema')
    identifier(catalog['revision'])
    timestamp(catalog['publishedAt'])
    require(isinstance(catalog['stories'], list) and len(catalog['stories']) <= 120, 'Too many stories')
    unique(catalog['stories'])
    for entry in catalog['stories']:
        validate_entry(entry)
    return catalog


def validate_payload(payload, entry=None):
    require(type(payload['schemaVersion']) is int and payload['schemaVersion'] == 1, 'Unsupported story schema')
    identifier(payload['id'])
    if payload['renderer'] == 'inning-out-grid':
        return validate_out_grid(payload, entry)
    if payload['renderer'] == 'chart-trajectory':
        return validate_trajectory(payload, entry)
    require(payload['renderer'] == 'guess-reveal' and type(payload['rendererVersion']) is int and payload['rendererVersion'] == 1, 'Unsupported story renderer')
    for field, limit in [('title', 160), ('kicker', 160), ('intro', 2000), ('question', 300), ('answerTitle', 200), ('answer', 2000), ('conclusion', 2000)]:
        text(payload[field], limit)
    choices = payload['choices']
    require(2 <= len(choices) <= 4, 'Expected two to four choices')
    unique(choices)
    for choice in choices:
        identifier(choice['id'])
        for field in ['label', 'value', 'unit', 'detail']:
            text(choice[field], 300)
    require(payload['correctChoiceID'] in {c['id'] for c in choices}, 'Missing correct choice')
    require(len(payload['stats']) <= 6 and len(payload['bars']) <= 8, 'Too many chart values')
    for stat in payload['stats']:
        for field in ['label', 'value', 'note']:
            text(stat[field], 300)
    for bar in payload['bars']:
        text(bar['label'], 160)
        text(bar['unit'], 80)
        text(bar['detail'], 500)
        require(type(bar['value']) in [int, float] and math.isfinite(bar['value']) and 0 <= bar['value'] <= 100000, 'Invalid chart value')
    maximum = payload.get('barMaximum')
    if maximum is not None:
        require(type(maximum) in [int, float] and math.isfinite(maximum) and 1 <= maximum <= 100000 and all(b['value'] <= maximum for b in payload['bars']), 'Invalid chart maximum')
    passport = payload.get('passport')
    if passport is not None:
        text(passport['title'], 160)
        text(passport['intro'])
        require(1 <= len(passport['items']) <= 60, 'Invalid grid size')
        unique(passport['items'])
        for item in passport['items']:
            identifier(item['id'])
            for field in ['label', 'name', 'detail']:
                text(item[field], 1000)
            require(item['result'] in ['yes', 'no', 'unknown'], 'Invalid grid result')
    require(1 <= len(payload['methodology']) <= 12, 'Missing methodology')
    for paragraph in payload['methodology']:
        text(paragraph)
    require(1 <= len(payload['sources']) <= 12, 'Missing sources')
    unique(payload['sources'])
    for source in payload['sources']:
        identifier(source['id'])
        text(source['title'], 200)
        url = urlsplit(source['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and len(source['url']) <= 2000, 'Unsafe source URL')
        timestamp(source['retrievedAt'])
    if entry:
        require(payload['id'] == entry['id'] and payload['title'] == entry['title'], 'Story identity mismatch')
        require(payload['renderer'] == entry['renderer'] and payload['rendererVersion'] == entry['rendererVersion'], 'Renderer mismatch')
    return payload


def validate_trajectory(payload, entry=None):
    require(type(payload['rendererVersion']) is int and payload['rendererVersion'] == 1, 'Unsupported chart renderer')
    for field, limit in [('title', 160), ('kicker', 160), ('intro', 2000), ('conclusion', 2000)]:
        text(payload[field], limit)
    chart = payload['chart']
    require(chart['kind'] in ['line', 'step', 'bar'], 'Unsupported chart kind')
    def number(value):
        require(type(value) in [int, float] and math.isfinite(value), 'Invalid finite chart number')
    number(chart['durationSeconds']); require(2 <= chart['durationSeconds'] <= 20, 'Invalid duration')
    for axis in [chart['xAxis'], chart['yAxis']]:
        text(axis['label'], 80)
        number(axis['minimum']); number(axis['maximum'])
        require(-1000000 <= axis['minimum'] < axis['maximum'] <= 1000000, 'Invalid axis range')
        ticks = axis['ticks']; require(2 <= len(ticks) <= 8 and len(set(ticks)) == len(ticks) and ticks == sorted(ticks), 'Invalid ticks')
        for tick in ticks:
            number(tick); require(axis['minimum'] <= tick <= axis['maximum'], 'Tick outside axis')
    xa, ya = chart['xAxis'], chart['yAxis']
    series = chart['series']; require(1 <= len(series) <= 6 and sum(len(r['points']) for r in series) <= 2000, 'Too many series or points'); unique(series)
    for row in series:
        identifier(row['id']); text(row['label'], 80)
        require(row['color'] in ['coral', 'navy', 'gold', 'teal', 'purple', 'gray'], 'Unknown palette color')
        points = row['points']; require(2 <= len(points) <= 600 and points[0]['x'] == xa['minimum'] and points[-1]['x'] == xa['maximum'], 'Invalid series bounds')
        for i, point in enumerate(points):
            number(point['x']); number(point['y'])
            require(xa['minimum'] <= point['x'] <= xa['maximum'] and ya['minimum'] <= point['y'] <= ya['maximum'] and (i == 0 or points[i-1]['x'] < point['x']), 'Invalid ordered point')
        if chart['kind'] == 'bar': require(len(points) <= 60 and ya['minimum'] <= 0 <= ya['maximum'], 'Bar chart requires bounded groups and zero baseline')
    beats = chart['emphasis']; require(len(beats) <= 8, 'Too many emphasis points'); unique(beats)
    require([b['x'] for b in beats] == sorted(b['x'] for b in beats) and len({b['x'] for b in beats}) == len(beats), 'Invalid emphasis order')
    for beat in beats:
        identifier(beat['id']); text(beat['title'], 160); text(beat['detail'], 500)
        for key in ['x', 'y', 'holdSeconds']: number(beat[key])
        require(xa['minimum'] <= beat['x'] <= xa['maximum'] and ya['minimum'] <= beat['y'] <= ya['maximum'] and 0 <= beat['holdSeconds'] <= 2, 'Invalid emphasis')
    require(chart['durationSeconds'] - sum(b['holdSeconds'] for b in beats) >= 1, 'Holds exceed duration')
    sequence = chart.get('sequence')
    if sequence is not None:
        require(type(sequence) is dict and 'secondsPerSeries' in sequence, 'Invalid sequence')
        number(sequence['secondsPerSeries'])
        require(1 <= sequence['secondsPerSeries'] <= 4 and abs(sequence['secondsPerSeries'] * len(series) + sum(b['holdSeconds'] for b in beats) - chart['durationSeconds']) < .001, 'Invalid sequence timing')
    for beat in beats:
        comparison = beat.get('comparison')
        if comparison is None: continue
        require(type(comparison) is dict and {'sourceSeriesID', 'targetSeriesID'} <= comparison.keys(), 'Invalid comparison')
        ids = [r['id'] for r in series]
        require(sequence and comparison['sourceSeriesID'] in ids and comparison['targetSeriesID'] in ids, 'Invalid comparison identity')
        source, target = ids.index(comparison['sourceSeriesID']), ids.index(comparison['targetSeriesID'])
        source_points = series[source]['points']
        lower = max(i for i,p in enumerate(source_points) if p['x'] <= beat['x'])
        value = source_points[lower]['y']
        if chart['kind'] == 'line' and source_points[lower]['x'] < beat['x']:
            a,b = source_points[lower:lower+2]; value += (b['y']-a['y']) * (beat['x']-a['x']) / (b['x']-a['x'])
        require(target < source and value == beat['y'] and series[target]['points'][-1]['y'] == beat['y'] and beat['holdSeconds'] >= 1.9, 'Comparison must join equal factual values on an earlier completed series')
    require(1 <= len(payload['methodology']) <= 12 and 1 <= len(payload['sources']) <= 12, 'Missing methodology or sources'); unique(payload['sources'])
    for paragraph in payload['methodology']: text(paragraph)
    for source in payload['sources']:
        identifier(source['id']); text(source['title'], 200); timestamp(source['retrievedAt'])
        url = urlsplit(source['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and len(source['url']) <= 2000, 'Unsafe source URL')
    if entry:
        require(all(payload[k] == entry[k] for k in ['id', 'title', 'renderer', 'rendererVersion']) and entry['minimumRendererVersion'] >= 2, 'Chart capability or identity mismatch')
        require(entry['minimumRendererVersion'] >= (3 if sequence or any(b.get('comparison') for b in beats) else 2), 'Sequence/comparison capability mismatch')
    return payload


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_tree(root: Path):
    catalog = validate_catalog(decode((root / 'stories/catalog-v1.json').read_bytes(), CATALOG_LIMIT))
    for entry in catalog['stories']:
        data = (root / entry_path(entry)).read_bytes()
        require(digest(data) == entry['revision'], 'Payload hash mismatch')
        validate_payload(decode(data, PAYLOAD_LIMIT), entry)
    return catalog


def validate_out_grid(payload, entry=None):
    require(type(payload['rendererVersion']) is int and payload['rendererVersion'] == 1, 'Unsupported out-grid renderer')
    for field, limit in [('title', 160), ('heading', 160), ('commentary', 2000)]: text(payload[field], limit)
    duration = payload['durationSeconds']
    require(type(duration) in [int, float] and math.isfinite(duration) and 2 <= duration <= 20, 'Invalid duration')
    outs = payload['outs']; require(isinstance(outs, list) and len(outs) == 27, 'Expected exactly 27 batter outs')
    for index, out in enumerate(outs):
        integer(out['number'], 1, 27); integer(out['inning'], 1, 9)
        require(out['number'] == index + 1 and out['inning'] == index // 3 + 1 and out['result'] in ['strikeout', 'other'], 'Invalid chronological inning grid')
        text(out['pitcher'], 120); text(out['batter'], 120)
    require(1 <= len(payload['methodology']) <= 12 and 1 <= len(payload['sources']) <= 12, 'Missing provenance'); unique(payload['sources'])
    for paragraph in payload['methodology']: text(paragraph)
    for source in payload['sources']:
        identifier(source['id']); text(source['title'], 200); timestamp(source['retrievedAt'])
        url = urlsplit(source['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and len(source['url']) <= 2000, 'Unsafe source URL')
    if entry:
        require(all(payload[k] == entry[k] for k in ['id', 'title', 'renderer', 'rendererVersion']) and entry['minimumRendererVersion'] >= 4, 'Grid capability or identity mismatch')
    return payload
