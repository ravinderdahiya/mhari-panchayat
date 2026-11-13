import { describe, expect, it } from 'vitest';
import { describeDevice } from './loginLogs';

describe('describeDevice', () => {
  it('names browser and OS for desktop browsers', () => {
    expect(describeDevice('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'))
      .toBe('Chrome · Windows');
    expect(describeDevice('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0'))
      .toBe('Edge · Windows');
    expect(describeDevice('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'))
      .toBe('Safari · macOS');
    expect(describeDevice('Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0'))
      .toBe('Firefox · Linux');
  });

  it('recognises the Flutter mobile app (Dart HTTP client)', () => {
    expect(describeDevice('Dart/3.5 (dart:io)')).toBe('Mobile app');
  });

  it('names Android and iPhone browsers', () => {
    expect(describeDevice('Mozilla/5.0 (Linux; Android 14; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36'))
      .toBe('Chrome · Android');
    expect(describeDevice('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'))
      .toBe('Safari · iOS');
  });

  it('falls back gracefully', () => {
    expect(describeDevice(null)).toBe('Unknown');
    expect(describeDevice('')).toBe('Unknown');
    expect(describeDevice('curl/8.4.0')).toBe('curl/8.4.0');
  });
});
