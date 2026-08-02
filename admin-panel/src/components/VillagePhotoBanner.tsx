import { useEffect, useState } from 'react';

// Real photographs of villages in Haryana, India - sourced from Wikimedia
// Commons, all CC BY-SA 4.0 (attribution required, kept in `credit` below
// and shown on-screen for the currently visible photo).
// BASE_URL is `/` in local dev and `/mhari-panchayat/` on IIS.
const asset = (path: string) => `${import.meta.env.BASE_URL}${path.replace(/^\//, '')}`;

const PHOTOS = [
  {
    src: asset('village-photos/village-sunset.jpg'),
    credit: 'Village pond at sunset, Kaithal — Vasupriye, CC BY-SA 4.0',
  },
  {
    src: asset('village-photos/sisana-village-road.jpg'),
    credit: 'Banyan-lined village road, Sisana, Sonipat — Ashudahiya01, CC BY-SA 4.0',
  },
  {
    src: asset('village-photos/bachini-farms-winter.jpg'),
    credit: 'Winter morning over farms, Bachini, Mahendragarh — ND Nikhil, CC BY-SA 4.0',
  },
  {
    src: asset('village-photos/shivalya-pond.jpg'),
    credit: 'Shivalya pond, Sisana, Sonipat — Ashudahiya01, CC BY-SA 4.0',
  },
  {
    src: asset('village-photos/village-gate-pipli.jpg'),
    credit: 'Village gate, Pipli, Sirsa — Mulkh Singh, CC BY-SA 4.0',
  },
];

const ROTATE_MS = 5000;

export default function VillagePhotoBanner() {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const id = setInterval(() => setIndex((i) => (i + 1) % PHOTOS.length), ROTATE_MS);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="absolute inset-0 overflow-hidden bg-slate-800">
      {PHOTOS.map((photo, i) => (
        <img
          key={photo.src}
          src={photo.src}
          alt=""
          className="absolute inset-0 w-full h-full object-cover transition-opacity duration-1000 ease-in-out"
          style={{ opacity: i === index ? 1 : 0 }}
          aria-hidden={i !== index}
        />
      ))}
      <div className="absolute inset-0 bg-black/35" />
      <p className="absolute bottom-2 right-3 text-[10px] text-white/80 drop-shadow">
        {PHOTOS[index].credit}
      </p>
    </div>
  );
}
