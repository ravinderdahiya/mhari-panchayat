import { describe, expect, it } from 'vitest';
import { barWidth, complianceTone, formatCompliance } from './performance';

describe('complianceTone', () => {
  it('is good from 90% up, fair from 70% and poor below', () => {
    expect(complianceTone(100)).toBe('good');
    expect(complianceTone(90)).toBe('good');
    expect(complianceTone(89.9)).toBe('fair');
    expect(complianceTone(70)).toBe('fair');
    expect(complianceTone(69.9)).toBe('poor');
    expect(complianceTone(0)).toBe('poor');
  });
});

describe('formatCompliance', () => {
  it('drops a pointless ".0" and keeps one decimal otherwise', () => {
    expect(formatCompliance(100)).toBe('100%');
    expect(formatCompliance(75)).toBe('75%');
    expect(formatCompliance(87.5)).toBe('87.5%');
    expect(formatCompliance(66.666)).toBe('66.7%');
  });
});

describe('barWidth', () => {
  it('is the percentage, clamped to 0-100 so a bad value cannot break the layout', () => {
    expect(barWidth(42)).toBe('42%');
    expect(barWidth(-5)).toBe('0%');
    expect(barWidth(180)).toBe('100%');
    expect(barWidth(Number.NaN)).toBe('0%');
  });
});
