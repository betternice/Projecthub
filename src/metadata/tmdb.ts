import { presentTitle } from '../format';
import { findWikiMovie, wikiMediaDetail } from './wiki';

export type MediaMatch = {
  tmdbId: number | null;
  wikibaseId: string | null;
  kind: 'movie' | 'tv';
  title: string;
  overview: string | null;
  year: string | null;
  posterUrl: string | null;
  backdropUrl: string | null;
  rating: number | null;
};

export type CastMember = {
  name: string;
  character: string | null;
  profileUrl: string | null;
};

export type MediaDetail = MediaMatch & {
  runtime: number | null;
  cast: CastMember[];
  genres: string[];
  director: string | null;
};

export class TmdbError extends Error {}

type TmdbResult = {
  id: number;
  title?: string;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  popularity?: number;
};

const cache = new Map<string, MediaMatch | null>();
const lookupCache = new Map<string, MediaMatch | null>();

function image(path: string | null | undefined, size: 'w185' | 'w500' | 'w780'): string | null {
  return path ? `https://image.tmdb.org/t/p/${size}${path}` : null;
}

function toMatch(kind: 'movie' | 'tv', result: TmdbResult): MediaMatch {
  const date = kind === 'movie' ? result.release_date : result.first_air_date;
  return {
    tmdbId: result.id,
    wikibaseId: null,
    kind,
    title: result.title || result.name || '',
    overview: result.overview?.trim() || null,
    year: date?.slice(0, 4) ?? null,
    posterUrl: image(result.poster_path, 'w500'),
    backdropUrl: image(result.backdrop_path, 'w780'),
    rating: result.vote_average ? Math.round(result.vote_average * 10) / 10 : null,
  };
}

async function searchKind(
  apiKey: string,
  kind: 'movie' | 'tv',
  title: string,
  year: string | null,
  language: string,
): Promise<MediaMatch | null> {
  const params = new URLSearchParams({
    api_key: apiKey,
    query: title,
    language,
    include_adult: 'false',
  });
  if (year) params.set(kind === 'movie' ? 'year' : 'first_air_date_year', year);

  const response = await fetch(`https://api.themoviedb.org/3/search/${kind}?${params}`);
  if (response.status === 401) throw new TmdbError('ใช้ TMDB API key นี้ไม่ได้');
  if (!response.ok) return null;

  const body = (await response.json()) as { results?: TmdbResult[] };
  const results = body.results ?? [];
  if (results.length === 0) return null;
  const best = [...results].sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0))[0];
  return toMatch(kind, best);
}

export async function matchTitle(apiKey: string, filename: string): Promise<MediaMatch | null> {
  const { title, year } = presentTitle(filename);
  if (!title) return null;
  const cacheKey = `${title}|${year ?? ''}`;
  if (cache.has(cacheKey)) return cache.get(cacheKey) ?? null;

  const match =
    (await searchKind(apiKey, 'movie', title, year, 'th-TH')) ??
    (await searchKind(apiKey, 'movie', title, null, 'th-TH')) ??
    (await searchKind(apiKey, 'tv', title, year, 'th-TH')) ??
    (await searchKind(apiKey, 'movie', title, year, 'en-US')) ??
    (await searchKind(apiKey, 'tv', title, year, 'en-US'));

  cache.set(cacheKey, match);
  return match;
}

export async function fetchMediaDetail(apiKey: string, match: MediaMatch): Promise<MediaDetail> {
  if (!match.tmdbId) return { ...match, runtime: null, cast: [], genres: [], director: null };
  const path = match.kind === 'movie' ? 'movie' : 'tv';
  const params = new URLSearchParams({
    api_key: apiKey,
    language: 'th-TH',
    append_to_response: 'credits',
  });
  const response = await fetch(`https://api.themoviedb.org/3/${path}/${match.tmdbId}?${params}`);
  if (!response.ok) return { ...match, runtime: null, cast: [], genres: [], director: null };

  const body = (await response.json()) as {
    overview?: string;
    runtime?: number;
    episode_run_time?: number[];
    genres?: { name?: string }[];
    credits?: {
      cast?: { name?: string; character?: string; profile_path?: string | null }[];
      crew?: { name?: string; job?: string }[];
    };
  };
  const cast = (body.credits?.cast ?? []).slice(0, 12).map((person) => ({
    name: person.name || '',
    character: person.character || null,
    profileUrl: image(person.profile_path, 'w185'),
  }));

  return {
    ...match,
    overview: body.overview?.trim() || match.overview,
    runtime: match.kind === 'movie' ? body.runtime ?? null : body.episode_run_time?.[0] ?? null,
    cast: cast.filter((person) => person.name),
    genres: (body.genres ?? []).map((genre) => genre.name).filter((name): name is string => Boolean(name)).slice(0, 2),
    director: body.credits?.crew?.find((person) => person.job === 'Director')?.name ?? null,
  };
}

export async function lookupMedia(filename: string, apiKey?: string | null): Promise<MediaMatch | null> {
  const { title, year } = presentTitle(filename);
  const cacheKey = `${apiKey ?? ''}|${title}|${year ?? ''}`;
  if (lookupCache.has(cacheKey)) return lookupCache.get(cacheKey) ?? null;

  let match: MediaMatch | null = null;
  if (apiKey) {
    try {
      match = await matchTitle(apiKey, filename);
    } catch (error) {
      if (!(error instanceof TmdbError)) throw error;
    }
  }
  if (!match) match = await findWikiMovie(filename);
  lookupCache.set(cacheKey, match);
  return match;
}

export async function lookupDetail(match: MediaMatch, apiKey?: string | null): Promise<MediaDetail> {
  if (match.tmdbId && apiKey) {
    try {
      return await fetchMediaDetail(apiKey, match);
    } catch (error) {
      if (!(error instanceof TmdbError)) throw error;
    }
  }
  if (match.wikibaseId) return wikiMediaDetail(match);
  return { ...match, runtime: null, cast: [], genres: [], director: null };
}
