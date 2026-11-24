export function presentTitle(filename: string): { title: string; year: string | null } {
  const base = filename.replace(/\.[^.]+$/, '');
  const year = base.match(/\b(19|20)\d{2}\b/)?.[0] ?? null;
  const title = base
    .replace(/\[[^\]]*\]/g, ' ')
    .replace(/\((?!(?:19|20)\d{2}\))[^)]*\)/g, ' ')
    .replace(/[._]+/g, ' ')
    .replace(/\b(19|20)\d{2}\b/g, ' ')
    .replace(
      /\b(1080p|720p|2160p|4320p|4k|8k|uhd|hdr|x264|x265|h264|h265|hevc|10bit|bluray|bdrip|brrip|webrip|webdl|web-dl|hdrip|dvdrip|remux|aac|dts|truehd|atmos)\b/gi,
      ' ',
    )
    .replace(/\s+/g, ' ')
    .trim();

  return { title: title || base, year };
}

export function formatBytes(bytes?: number): string | null {
  if (!bytes) return null;
  const gigabytes = bytes / 1024 ** 3;
  if (gigabytes >= 1) return `${gigabytes >= 10 ? gigabytes.toFixed(0) : gigabytes.toFixed(1)} GB`;
  return `${Math.max(1, Math.round(bytes / 1024 ** 2))} MB`;
}

export function formatClock(milliseconds?: number): string | null {
  if (!milliseconds || milliseconds < 1000) return null;
  const total = Math.round(milliseconds / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) return `${hours} ชม. ${minutes} นาที`;
  return `${minutes} นาที`;
}

export function formatRuntime(minutes?: number | null): string | null {
  if (!minutes) return null;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours > 0) return `${hours} ชม. ${rest} นาที`;
  return `${rest} นาที`;
}
