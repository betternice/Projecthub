import { presentTitle } from '../format';
import type { CastMember, MediaDetail, MediaMatch } from './tmdb';

const HEADERS = {
  Accept: 'application/json',
  'User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
  'Api-User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
};

type WikiSearchHit = { key?: string; title?: string; description?: string };

type WikiSummary = {
  title?: string;
  description?: string;
  extract?: string;
  originalimage?: { source?: string };
  thumbnail?: { source?: string };
  wikibase_item?: string;
};

type WikiClaim = {
  mainsnak?: { datavalue?: { value?: { id?: string; time?: string; amount?: string; unit?: string } } };
};

type WikiEntity = {
  sitelinks?: { thwiki?: { title?: string } };
  claims?: Record<string, WikiClaim[]>;
};

function firstParagraph(text: string): string {
  return text
    .split('\n')
    .map((line) => line.trim())
    .find(Boolean) ?? '';
}

function cleanWikiTitle(title: string, fallbackYear: string | null): { title: string; year: string | null } {
  const year = title.match(/\(((?:19|20)\d{2})/)?.[1] ?? fallbackYear;
  const cleaned = title.replace(/\s*\([^)]*\)\s*$/, '').trim();
  return { title: cleaned || title, year };
}

async function readJson<T>(url: string): Promise<T | null> {
  const response = await fetch(url, { headers: HEADERS });
  if (!response.ok) return null;
  return (await response.json()) as T;
}

async function search(lang: 'en' | 'th', query: string): Promise<WikiSearchHit[]> {
  const body = await readJson<{ pages?: WikiSearchHit[] }>(
    `https://${lang}.wikipedia.org/w/rest.php/v1/search/page?q=${encodeURIComponent(query)}&limit=5`,
  );
  return body?.pages ?? [];
}

function choose(hits: WikiSearchHit[], title: string, year: string | null): WikiSearchHit | null {
  const wanted = title.toLowerCase();
  let best: { hit: WikiSearchHit; score: number } | null = null;
  for (const hit of hits) {
    const name = (hit.title || '').toLowerCase();
    const description = (hit.description || '').toLowerCase();
    let score = 0;
    if (/film|movie|ภาพยนตร์|ละคร|television series|tv series/.test(description)) score += 6;
    if (/\(film\)|ภาพยนตร์/.test(name)) score += 2;
    if (year && (name.includes(year) || description.includes(year))) score += 4;
    if (name === wanted || name.startsWith(wanted)) score += 4;
    else if (name.includes(wanted)) score += 2;
    if (/album|soundtrack|song|novel|book|episode/.test(description)) score -= 6;
    if (!best || score > best.score) best = { hit, score };
  }
  return best && best.score >= 6 ? best.hit : null;
}

async function pageSummary(lang: 'en' | 'th', titleOrKey: string): Promise<WikiSummary | null> {
  return readJson<WikiSummary>(
    `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(titleOrKey)}`,
  );
}

export async function findWikiMovie(filename: string): Promise<MediaMatch | null> {
  const { title, year } = presentTitle(filename);
  if (!title) return null;
  const thai = /[\u0E00-\u0E7F]/.test(title);
  const query = thai ? `${title} ภาพยนตร์` : [title, year, 'film'].filter(Boolean).join(' ');
  const hit = choose(await search(thai ? 'th' : 'en', query), title, year);
  if (!hit?.title && !hit?.key) return null;

  const summary = await pageSummary(thai ? 'th' : 'en', hit.key || hit.title || title);
  if (!summary?.title && !summary?.extract && !summary?.originalimage?.source) return null;

  const cleaned = cleanWikiTitle(summary?.title || hit.title || title, year);
  const describedYear = summary?.description?.match(/\b(19|20)\d{2}\b/)?.[0] ?? null;
  const poster = summary?.originalimage?.source || summary?.thumbnail?.source || null;
  const overview = firstParagraph(summary?.extract || '');

  return {
    tmdbId: null,
    wikibaseId: summary?.wikibase_item ?? null,
    kind: /series|television|ละคร/i.test(`${summary?.description ?? ''} ${summary?.title ?? ''}`) ? 'tv' : 'movie',
    title: cleaned.title,
    overview: overview || null,
    year: cleaned.year || describedYear || year,
    posterUrl: poster,
    backdropUrl: poster,
    rating: null,
  };
}

function claimIds(claims: Record<string, WikiClaim[]> | undefined, prop: string, limit: number): string[] {
  return (claims?.[prop] ?? [])
    .map((claim) => claim.mainsnak?.datavalue?.value?.id)
    .filter((id): id is string => Boolean(id))
    .slice(0, limit);
}

function claimYear(claims: Record<string, WikiClaim[]> | undefined): string | null {
  const time = claims?.P577?.[0]?.mainsnak?.datavalue?.value?.time;
  return time?.match(/(19|20)\d{2}/)?.[0] ?? null;
}

function claimMinutes(claims: Record<string, WikiClaim[]> | undefined): number | null {
  const value = claims?.P2047?.[0]?.mainsnak?.datavalue?.value;
  if (!value?.amount || !String(value.unit || '').endsWith('Q7727')) return null;
  const minutes = Math.abs(parseInt(value.amount, 10));
  return minutes > 0 && minutes < 1000 ? minutes : null;
}

async function entity(id: string): Promise<WikiEntity | null> {
  const body = await readJson<{ entities?: Record<string, WikiEntity> }>(
    `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${encodeURIComponent(id)}&props=sitelinks|claims&sitefilter=thwiki&format=json`,
  );
  return body?.entities?.[id] ?? null;
}

async function labels(ids: string[]): Promise<Record<string, string>> {
  if (ids.length === 0) return {};
  const body = await readJson<{ entities?: Record<string, { labels?: { th?: { value?: string }; en?: { value?: string } } }> }>(
    `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${ids.join('|')}&props=labels&languages=th|en&format=json`,
  );
  const map: Record<string, string> = {};
  for (const [id, item] of Object.entries(body?.entities ?? {})) {
    map[id] = item.labels?.th?.value || item.labels?.en?.value || '';
  }
  return map;
}

export async function wikiMediaDetail(match: MediaMatch): Promise<MediaDetail> {
  if (!match.wikibaseId) return { ...match, runtime: null, cast: [], genres: [], director: null };

  const record = await entity(match.wikibaseId);
  const claims = record?.claims;
  const thaiTitle = record?.sitelinks?.thwiki?.title;
  let next = match;
  if (thaiTitle) {
    const thai = await pageSummary('th', thaiTitle);
    const overview = firstParagraph(thai?.extract || '');
    const poster = next.posterUrl || thai?.originalimage?.source || thai?.thumbnail?.source || null;
    next = {
      ...next,
      title: thai?.title ? cleanWikiTitle(thai.title, next.year).title : next.title,
      overview: overview || next.overview,
      posterUrl: poster,
      backdropUrl: next.backdropUrl || poster,
      year: next.year || claimYear(claims),
    };
  }

  const genreIds = claimIds(claims, 'P136', 2);
  const directorIds = claimIds(claims, 'P57', 1);
  const castIds = claimIds(claims, 'P161', 10);
  const names = await labels([...genreIds, ...directorIds, ...castIds]);
  const cast: CastMember[] = castIds
    .map((id) => ({ name: names[id] || '', character: null, profileUrl: null }))
    .filter((person) => person.name);

  return {
    ...next,
    year: next.year || claimYear(claims),
    runtime: claimMinutes(claims),
    genres: genreIds.map((id) => names[id]).filter(Boolean),
    director: directorIds.map((id) => names[id]).find(Boolean) ?? null,
    cast,
  };
}
