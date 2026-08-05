import { ExternalLink, X } from 'lucide-react';

export function PhotoThumbnail({ url, label, onView }: { url: string; label: string; onView: (url: string) => void }) {
  return (
    <button
      type="button"
      onClick={() => onView(url)}
      className="group relative block rounded-xl overflow-hidden border border-slate-200 aspect-square cursor-pointer"
    >
      <img src={url} alt={`${label} photo`} className="w-full h-full object-cover" />
      <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center">
        <ExternalLink className="w-4 h-4 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
      </div>
      <span className="absolute bottom-1 left-1.5 text-[9px] font-bold uppercase text-white bg-black/50 rounded px-1.5 py-0.5">
        {label}
      </span>
    </button>
  );
}

export function PhotoLightbox({ url, onClose }: { url: string | null; onClose: () => void }) {
  if (!url) return null;
  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 p-6"
      onClick={(event) => { event.stopPropagation(); onClose(); }}
    >
      <button
        type="button"
        aria-label="Close"
        onClick={(event) => { event.stopPropagation(); onClose(); }}
        className="absolute top-4 right-4 text-white/80 hover:text-white cursor-pointer"
      >
        <X className="w-6 h-6" />
      </button>
      <img
        src={url}
        alt="Full size preview"
        className="max-w-full max-h-full rounded-lg object-contain"
        onClick={(event) => event.stopPropagation()}
      />
    </div>
  );
}
