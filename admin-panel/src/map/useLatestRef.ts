import { useEffect, useRef } from 'react';

// Keeps a ref always pointing to the latest value without triggering re-renders.
// Used to avoid stale closures in long-lived effects (ArcGIS view event handlers).
export function useLatestRef<T>(value: T) {
  const ref = useRef(value);
  useEffect(() => {
    ref.current = value;
  }, [value]);
  return ref;
}
