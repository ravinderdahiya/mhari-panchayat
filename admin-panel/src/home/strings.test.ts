import { describe, expect, it } from 'vitest';
import { STRINGS, translator } from './strings';

const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

describe('home page strings', () => {
  it('has every English key in Hindi and the other way round', () => {
    const hi = Object.keys(STRINGS.hi);
    const en = Object.keys(STRINGS.en);

    expect(en.filter((k) => !(k in STRINGS.hi))).toEqual([]);
    expect(hi.filter((k) => !(k in STRINGS.en))).toEqual([]);
  });

  it('uses the same {placeholders} in both languages', () => {
    for (const key of Object.keys(STRINGS.en)) {
      expect(placeholders(STRINGS.hi[key] ?? ''), key).toEqual(placeholders(STRINGS.en[key]));
    }
  });

  it('has no empty strings', () => {
    for (const lang of ['hi', 'en'] as const) {
      for (const [key, value] of Object.entries(STRINGS[lang])) expect(value.trim(), `${lang}.${key}`).not.toBe('');
    }
  });

  it('every complaint category tile and FAQ entry has text', () => {
    const t = translator('en');
    for (const key of ['catGali', 'catNaali', 'catPaani', 'catBijli', 'catLight', 'catSafai', 'catAtikraman', 'catOther']) {
      expect(t(key)).not.toBe(key);
    }
    for (const n of [1, 2, 3, 4]) {
      expect(t(`faq${n}q`)).not.toBe(`faq${n}q`);
      expect(t(`faq${n}a`)).not.toBe(`faq${n}a`);
    }
  });
});

describe('translator', () => {
  it('returns the text for the chosen language', () => {
    expect(translator('en')('statTrial')).toBe('In trial phase');
    expect(translator('hi')('statTrial')).toBe('ट्रायल चरण में');
  });

  it('replaces {placeholders}', () => {
    expect(translator('en')('catHint', { c: 'Roads' })).toContain('"Roads"');
  });

  it('falls back to English, then to the key itself', () => {
    expect(translator('hi')('definitely_missing_key')).toBe('definitely_missing_key');
  });
});
