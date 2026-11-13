export type PageItem = number | 'gap';

// Page buttons for the pager: every page when there are at most 7, otherwise
// first, last, and a window around the current page with gaps in between.
export function pageItems(current: number, last: number): PageItem[] {
  const total = Math.max(1, last);
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  if (current <= 4) return [1, 2, 3, 4, 5, 'gap', total];
  if (current >= total - 3) return [1, 'gap', total - 4, total - 3, total - 2, total - 1, total];
  return [1, 'gap', current - 1, current, current + 1, 'gap', total];
}

export function rangeLabel(page: number, perPage: number, total: number): string {
  if (total === 0) return 'Showing 0 of 0';
  const start = (page - 1) * perPage + 1;
  const end = Math.min(page * perPage, total);
  return `Showing ${start}–${end} of ${total}`;
}

// Turns a raw User-Agent header into a short label for the sign-in history table.
export function describeDevice(userAgent: string | null | undefined): string {
  const ua = (userAgent ?? '').trim();
  if (!ua) return 'Unknown';

  // The Flutter app talks to the API through dart:io's HttpClient.
  if (/^Dart\//.test(ua) || /dart:io/.test(ua)) return 'Mobile app';

  const browser =
    /Edg\//.test(ua) ? 'Edge'
    : /OPR\/|Opera/.test(ua) ? 'Opera'
    : /Firefox\//.test(ua) ? 'Firefox'
    : /Chrome\/|CriOS\//.test(ua) ? 'Chrome'
    : /Safari\//.test(ua) ? 'Safari'
    : null;

  const os =
    /Android/.test(ua) ? 'Android'
    : /iPhone|iPad|iPod/.test(ua) ? 'iOS'
    : /Windows/.test(ua) ? 'Windows'
    : /Mac OS X|Macintosh/.test(ua) ? 'macOS'
    : /Linux/.test(ua) ? 'Linux'
    : null;

  if (browser && os) return `${browser} · ${os}`;
  if (browser || os) return (browser ?? os)!;
  return ua.length > 40 ? `${ua.slice(0, 40)}…` : ua;
}
