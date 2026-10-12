import { MLB_TEAMS } from './team-registry.mjs';

const FALLBACK_USER_AGENT = 'HubBall/1.0 (+https://api.autumnlane.io)';
const RAW_DATA_ROOT = 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data';
const MLB_CLUBS_LIST_URL = 'https://syndication.twitter.com/srv/timeline-list/screen-name/MLB/slug/clubs?lang=en&theme=light&showHeader=false&hideBorder=true';
export const LIVE_FEED_CACHE_HEADERS = {
  'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
  'Netlify-CDN-Cache-Control': 'public, durable, max-age=300, stale-while-revalidate=3600',
};
const COMMON_SURNAMES = new Set([
  'anderson', 'anthony', 'campbell', 'gray', 'harris', 'hill', 'miller', 'scott', 'short',
  'story', 'walker', 'wells', 'west', 'white', 'young',
]);

const CURATED_TEAM_CONFIG = {
  redsox: {
    label: 'Red Sox',
    listId: '1431748439818346496',
    teamId: 111,
    teamTerms: [
      'red sox', 'redsox', '#redsox', '@redsox', 'bosox', 'fenway', 'woo sox', 'woosox',
      'worcester red sox', 'portland sea dogs', 'portland seadogs', 'red stockings',
      'sox prospects', 'soxprospects',
    ],
    linkTerms: [
      'redsox.com', 'mlb.com/redsox', 'bostonglobe.com/sports/baseball/redsox',
      'bostonherald.com/sports/mlb/boston-red-sox', 'masslive.com/redsox',
      'beyondthemonster', 'overthemonster', 'bosoxinjection', 'soxprospects',
      'thepeskyreport', 'sawxstack',
    ],
    excludedTerms: [
      'white sox', 'chicago sox', 'patriots', '#patriots', '#nfl', 'football', 'celtics',
      '#nba', 'basketball', 'bruins', '#nhl', 'hockey',
    ],
  },
  yankees: {
    label: 'Yankees',
    listId: '2095986539037647187',
    teamId: 147,
    teamTerms: [
      'new york yankees', 'yankees', '#yankees', '@yankees', '#nyy', '#repbx', 'rep bx',
      'bronx bombers', 'yankee stadium', 'scranton/wilkes-barre railriders',
      'swb railriders', 'somerset patriots', 'hudson valley renegades',
    ],
    linkTerms: [
      'yankees.com', 'mlb.com/yankees', 'yesnetwork.com/yankees', 'nypost.com/sports/yankees',
      'nydailynews.com/sports/mlb/new-york-yankees', 'theathletic.com/mlb/team/yankees',
      'pinstripealley', 'riveraveblues', 'yanksgoyard',
    ],
    excludedTerms: [
      'new york mets', '#mets', '@mets', 'ny mets', 'new york jets', '#jets', '@nyjets',
      'new york giants', '#giants', '@giants', 'new york knicks', '#knicks', '@nyknicks',
      'brooklyn nets', '#nets', '@brooklynnets', 'new york rangers', '#nyr', '@nyrangers',
      'new york islanders', '#isles', '@nyislanders', '#nfl', '#nba', '#nhl',
    ],
  },
  mets: {
    label: 'Mets',
    listId: '2096714864223748361',
    teamId: 121,
    teamTerms: [
      'new york mets', 'ny mets', '#mets', '@mets', '#lgm', '#lfgm', 'lfgm',
      'queens', 'citi field', 'syracuse mets', 'binghamton rumble ponies',
      'brooklyn cyclones', 'st. lucie mets', 'st lucie mets',
    ],
    linkTerms: [
      'mets.com', 'mlb.com/mets', 'sny.tv/mets', 'nypost.com/sports/mets',
      'nydailynews.com/sports/mlb/new-york-mets', 'theathletic.com/mlb/team/mets',
      'amazinavenue', 'metsmerizedonline', 'risingapple',
    ],
    excludedTerms: [
      'new york yankees', '#yankees', '@yankees', '#nyy', '#repbx',
      'new york jets', '#jets', '@nyjets', 'new york giants', '#giants', '@giants',
      'new york knicks', '#knicks', '@nyknicks', 'brooklyn nets', '#nets', '@brooklynnets',
      'new york rangers', '#nyr', '@nyrangers', 'new york islanders', '#isles',
      '@nyislanders', '#nfl', '#nba', '#nhl',
    ],
  },
  rays: {
    label: 'Rays',
    listId: '2096730568285200550',
    teamId: 139,
    teamTerms: [
      'tampa bay rays', 'tb rays', '#rays', '@raysbaseball', '#raysup', 'rays up',
      'tropicana field', 'steinbrenner field', 'durham bulls', 'montgomery biscuits',
      'bowling green hot rods', 'charleston riverdogs',
    ],
    linkTerms: [
      'raysbaseball.com', 'mlb.com/rays', 'tampabay.com/sports/rays',
      'theathletic.com/mlb/team/rays', 'draysbay', 'rayscoloredglasses',
    ],
    excludedTerms: [
      'manta ray', 'manta rays', 'stingray', 'stingrays', 'sun rays', 'cosmic rays',
      'toronto blue jays', '#bluejays', '@bluejays', 'tampa bay buccaneers', '#bucs',
      'tampa bay lightning', '#gobolts', '#nfl', '#nhl',
    ],
  },
};

export const TEAM_CONFIG = Object.fromEntries(MLB_TEAMS.map(team => {
  const sourceConfig = CURATED_TEAM_CONFIG[team.api_key] || {
    label: team.short_name,
    xHandle: team.x_handle,
    teamId: team.mlb_id,
    officialHandleOnly: true,
    teamTerms: [
      team.full_name.toLowerCase(), team.short_name.toLowerCase(),
      `@${team.x_handle.toLowerCase()}`,
    ],
    linkTerms: [`mlb.com/${team.api_key}`],
    excludedTerms: [],
  };
  return [team.api_key, {
    apiKey: team.api_key,
    dataDirectory: team.data_directory,
    ...sourceConfig,
  }];
}));

function listURL(team) {
  if (!team.listId) {
    return MLB_CLUBS_LIST_URL;
  }
  return `https://syndication.twitter.com/srv/timeline-list/list-id/${team.listId}?lang=en&theme=light&showHeader=false&hideBorder=true`;
}

function sourceURL(team) {
  return team.listId ? `https://x.com/i/lists/${team.listId}` : `https://x.com/${team.xHandle}`;
}

function rosterURL(team) {
  return `https://statsapi.mlb.com/api/v1/teams/${team.teamId}/roster?rosterType=fullSeason&season=${new Date().getUTCFullYear()}&hydrate=person`;
}

export function fallbackPath(team) {
  const prefix = team.apiKey === 'redsox' ? '' : `${team.dataDirectory}/`;
  return `${prefix}x-posts.json`;
}

async function fetchFallbackFeed(team) {
  const url = `${RAW_DATA_ROOT}/${fallbackPath(team)}`;
  let lastError;
  for (const headers of [{ Accept: 'application/json' }, {
    Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT,
  }]) {
    try {
      const response = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
      if (!response.ok) throw new Error(`snapshot returned ${response.status}`);
      const feed = await response.json();
      if (feed.source !== 'X' || !Array.isArray(feed.recent) || !feed.recent.length) {
        throw new Error('snapshot did not contain X posts');
      }
      return feed;
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not fetch X snapshot: ${lastError?.message || 'unknown error'}`);
}

function cleanText(value) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([\da-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/\s+/g, ' ').trim();
}

async function fetchText(url, expected) {
  let lastError;
  for (const headers of [{}, { 'User-Agent': FALLBACK_USER_AGENT }]) {
    try {
      const response = await fetch(url, { headers, signal: AbortSignal.timeout(12_000) });
      if (!response.ok) throw new Error(`request returned ${response.status}`);
      const body = await response.text();
      if (!body.includes(expected)) throw new Error(`response did not contain ${expected}`);
      return body;
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not fetch source: ${lastError?.message || 'unknown error'}`);
}

function rosterTerms(payload) {
  const terms = new Set();
  for (const row of payload.roster || []) {
    const name = cleanText(row.person?.fullName).toLowerCase();
    if (!name) continue;
    terms.add(name);
    const surname = name.split(/[\s-]+/).at(-1);
    if (surname.length >= 5 && !COMMON_SURNAMES.has(surname)) terms.add(surname);
  }
  return terms;
}

function tweetContext(tweet) {
  const parts = [tweet.full_text, tweet.text];
  for (const nested of [tweet.quoted_status || {}, tweet.retweeted_status || {}]) {
    parts.push(nested.full_text, nested.text);
  }
  for (const item of [tweet, tweet.quoted_status || {}, tweet.retweeted_status || {}]) {
    for (const url of item.entities?.urls || []) parts.push(url.expanded_url, url.display_url);
    for (const media of item.extended_entities?.media || []) parts.push(media.ext_alt_text);
  }
  return cleanText(parts.filter(part => typeof part === 'string').join(' ')).toLowerCase();
}

function relevant(tweet, players, team) {
  if (team.officialHandleOnly) {
    return cleanText(tweet.user?.screen_name).toLowerCase() === team.xHandle.toLowerCase();
  }
  const context = tweetContext(tweet);
  if ([...team.teamTerms, ...team.linkTerms].some(term => context.includes(term))) return true;
  if (team.excludedTerms.some(term => context.includes(term))) return false;
  for (const term of players) {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp(`(^|[^\\w])${escaped}([^\\w]|$)`).test(context)) return true;
  }
  return false;
}

function postFromTweet(tweet) {
  const text = cleanText(tweet.full_text || tweet.text);
  const user = tweet.user || {};
  const handle = cleanText(user.screen_name);
  const permalink = cleanText(tweet.permalink);
  if (!text || !handle || !permalink) return null;
  const quoted = tweet.quoted_status || {};
  const quotedUser = quoted.user || {};
  const publishedDate = new Date(cleanText(tweet.created_at));
  return {
    id: cleanText(tweet.id_str), text, url: `https://x.com${permalink}`,
    published: Number.isNaN(publishedDate.valueOf()) ? cleanText(tweet.created_at) : publishedDate.toISOString(),
    likes: Number(tweet.favorite_count || 0), author: cleanText(user.name) || handle, handle,
    avatar: cleanText(user.profile_image_url_https),
    media: cleanText(tweet.extended_entities?.media?.[0]?.media_url_https),
    quoted_text: cleanText(quoted.full_text || quoted.text),
    quoted_author: cleanText(quotedUser.name), quoted_handle: cleanText(quotedUser.screen_name),
  };
}

export function buildFeed(entries, players, team = TEAM_CONFIG.redsox, generatedAt = new Date()) {
  const seen = new Set();
  const posts = [];
  for (const entry of entries) {
    const tweet = entry.content?.tweet || {};
    if (!tweet.id_str || !relevant(tweet, players, team)) continue;
    const post = postFromTweet(tweet);
    if (!post || seen.has(post.id)) continue;
    seen.add(post.id);
    posts.push(post);
  }
  if (!posts.length) throw new Error(`The ${team.label} relevance filter removed every X post`);
  posts.sort((a, b) => b.published.localeCompare(a.published));
  const cutoff = generatedAt.valueOf() - 24 * 60 * 60 * 1000;
  const popular = posts
    .filter(post => new Date(post.published).valueOf() >= cutoff)
    .sort((a, b) => b.likes - a.likes || b.published.localeCompare(a.published));
  return {
    generated_at: generatedAt.toISOString(), source: 'X', source_url: sourceURL(team),
    recent: posts.slice(0, 24), popular: popular.slice(0, 12),
  };
}

const handleRequest = async request => {
  const requestedTeam = new URL(request.url).searchParams.get('team')?.toLowerCase() || 'redsox';
  const team = TEAM_CONFIG[requestedTeam];
  if (!team) {
    return Response.json({ error: 'Unknown team.' }, { status: 400 });
  }

  try {
    const [listHtml, rosterJson] = await Promise.all([
      fetchText(listURL(team), '__NEXT_DATA__'), fetchText(rosterURL(team), '"roster"'),
    ]);
    const match = listHtml.match(/<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
    if (!match) throw new Error('X list response did not contain timeline data');
    const listPayload = JSON.parse(match[1]);
    const entries = listPayload.props?.pageProps?.timeline?.entries || [];
    const feed = buildFeed(entries, rosterTerms(JSON.parse(rosterJson)), team);
    // Refresh the free public feed every five minutes. The stale window lets Netlify
    // keep serving a verified response while a background refresh absorbs a brief
    // upstream throttle.
    return Response.json(feed, { headers: LIVE_FEED_CACHE_HEADERS });
  } catch (error) {
    console.error('X feed refresh failed', error);
    try {
      const feed = await fetchFallbackFeed(team);
      return Response.json(feed, { headers: {
        'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
        'Netlify-CDN-Cache-Control': 'public, durable, max-age=3600, stale-while-revalidate=604800',
        'X-Hub-Ball-Feed': 'snapshot',
      } });
    } catch (fallbackError) {
      console.error('X snapshot fallback failed', fallbackError);
      return Response.json({ error: 'The live X feed is temporarily unavailable.' }, {
        status: 502, headers: { 'Cache-Control': 'no-store' },
      });
    }
  }
};

export default async request => {
  const response = await handleRequest(request);
  response.headers.set('Netlify-Vary', 'query=team');
  return response;
};

export const config = { path: '/api/x-posts', method: 'GET' };
