import { useEffect, useRef, useState } from 'react';

/** True once the element has scrolled into view (and stays true). */
export function useInView<T extends HTMLElement>(rootMargin = '0px') {
  const ref = useRef<T | null>(null);
  const [seen, setSeen] = useState(false);

  useEffect(() => {
    const node = ref.current;
    if (!node || seen) return undefined;
    if (typeof IntersectionObserver === 'undefined') {
      setSeen(true);
      return undefined;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setSeen(true);
          observer.disconnect();
        }
      },
      { rootMargin },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [seen, rootMargin]);

  return [ref, seen] as const;
}

/** Eases a number up from 0 to `target` once `start` is true (respects reduced motion). */
export function useCountUp(target: number | null, start: boolean, durationMs = 1400, decimals = 0) {
  const [value, setValue] = useState(0);

  useEffect(() => {
    if (target === null || !start) return undefined;
    const reduce = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (reduce || target === 0) {
      setValue(target);
      return undefined;
    }
    let frame = 0;
    const begin = performance.now();
    const tick = (now: number) => {
      const progress = Math.min(1, (now - begin) / durationMs);
      const eased = 1 - Math.pow(1 - progress, 3);
      setValue(Number((target * eased).toFixed(decimals)));
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, start, durationMs, decimals]);

  return value;
}

/** A value kept in localStorage; storage being blocked never breaks the page. */
export function usePersistentState<T extends string>(key: string, initial: T, allowed?: readonly T[]) {
  const [value, setValue] = useState<T>(() => {
    try {
      const stored = window.localStorage.getItem(key) as T | null;
      if (stored && (!allowed || allowed.includes(stored))) return stored;
    } catch {
      // private mode / blocked storage - fall through
    }
    return initial;
  });

  useEffect(() => {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // ignore
    }
  }, [key, value]);

  return [value, setValue] as const;
}
