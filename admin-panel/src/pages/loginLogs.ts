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
