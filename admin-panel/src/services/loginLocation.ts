// Location is optional: denial, unavailable GPS or a timeout must not block login.
export function getLoginLocation(): Promise<{ latitude: number; longitude: number } | undefined> {
  return new Promise((resolve) => {
    if (!navigator.geolocation) { resolve(undefined); return; }
    const timer = setTimeout(() => resolve(undefined), 9000);
    try {
      navigator.geolocation.getCurrentPosition(
        ({ coords }) => {
          clearTimeout(timer);
          resolve({ latitude: coords.latitude, longitude: coords.longitude });
        },
        () => { clearTimeout(timer); resolve(undefined); },
        { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 },
      );
    } catch {
      clearTimeout(timer);
      resolve(undefined);
    }
  });
}
