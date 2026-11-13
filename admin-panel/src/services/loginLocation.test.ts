import { afterEach, describe, expect, it, vi } from 'vitest';
import { getLoginLocation } from './loginLocation';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('login location', () => {
  it('returns device coordinates including zero without reusing a cached location', async () => {
    const getCurrentPosition = vi.fn((success) => success({ coords: { latitude: 0, longitude: 76.9905 } }));
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition } });
    expect(await getLoginLocation()).toEqual({ latitude: 0, longitude: 76.9905 });
    expect(getCurrentPosition).toHaveBeenCalledWith(
      expect.any(Function), expect.any(Function),
      expect.objectContaining({ maximumAge: 0, timeout: 8000 }),
    );
  });

  it('continues without coordinates when location permission is denied', async () => {
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition: (_success: unknown, error: () => void) => error() } });
    expect(await getLoginLocation()).toBeUndefined();
  });

  it('continues when the browser never answers its location request', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition: vi.fn() } });
    const result = getLoginLocation();
    await vi.advanceTimersByTimeAsync(9000);
    expect(await result).toBeUndefined();
  });

  it('continues when geolocation is unsupported or throws', async () => {
    vi.stubGlobal('navigator', {});
    expect(await getLoginLocation()).toBeUndefined();
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition: () => { throw new Error('Unavailable'); } } });
    expect(await getLoginLocation()).toBeUndefined();
  });
});
