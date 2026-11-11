"""Team relevance rules independent of the post source."""
import re
from html import unescape


def context(tweet: dict) -> str:
    parts = []
    for item in (tweet, tweet.get('quoted_status') or {}, tweet.get('retweeted_status') or {}):
        parts.extend((item.get('full_text'), item.get('text')))
        entities = item.get('entities') or {}
        for url in entities.get('urls', []):
            parts.extend((url.get('expanded_url'), url.get('display_url')))
        for media in (item.get('extended_entities') or {}).get('media', []) + entities.get('media', []):
            parts.append(media.get('ext_alt_text'))
    return unescape(' '.join(p for p in parts if isinstance(p, str))).lower()


def relevant(tweet: dict, config: dict, roster: set[str]) -> bool:
    if not config.get('list_id'):
        handle = config.get('handle')
        return bool(handle and str((tweet.get('user') or {}).get('screen_name') or '').lower() == handle.lower())
    # Reviewed NFL/NHL official authors are relevant even for short game-day posts.
    # Keep the established NBA policy unchanged unless its config explicitly opts in.
    if config.get('accept_official_posts') and config.get('handle'):
        author = str((tweet.get('user') or {}).get('screen_name') or '')
        if author.lower() == config['handle'].lower():
            return True
    text = context(tweet)
    if any(term.lower() in text for term in config['match_terms'] + config['link_terms']):
        return True
    if any(term.lower() in text for term in config['excluded_terms']):
        return False
    return any(re.search(r'(?<!\w)' + re.escape(term.lower()) + r'(?!\w)', text) for term in roster)
