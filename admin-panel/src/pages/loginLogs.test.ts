import { describe, expect, it } from 'vitest';
import { describeDevice, pageItems, rangeLabel } from './loginLogs';

describe('pageItems', () => {
  it('lists every page when there are few', () => {
    expect(pageItems(1, 1)).toEqual([1]);
    expect(pageItems(3, 5)).toEqual([1, 2, 3, 4, 5]);
    expect(pageItems(1, 7)).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  it('collapses distant pages into gaps around the current page', () => {
    expect(pageItems(1, 20)).toEqual([1, 2, 3, 4, 5, 'gap', 20]);
    expect(pageItems(10, 20)).toEqual([1, 'gap', 9, 10, 11, 'gap', 20]);
    expect(pageItems(20, 20)).toEqual([1, 'gap', 16, 17, 18, 19, 20]);
  });

  it('treats an empty result as a single page', () => {
    expect(pageItems(1, 0)).toEqual([1]);
  });
});

describe('rangeLabel', () => {
  it('shows the visible slice of the total', () => {
    expect(rangeLabel(1, 25, 2)).toBe('Showing 1–2 of 2');
    expect(rangeLabel(2, 25, 60)).toBe('Showing 26–50 of 60');
    expect(rangeLabel(3, 25, 60)).toBe('Showing 51–60 of 60');
    expect(rangeLabel(1, 25, 0)).toBe('Showing 0 of 0');
  });
});

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
