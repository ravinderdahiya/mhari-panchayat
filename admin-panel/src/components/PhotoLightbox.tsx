import { useEffect, useState } from 'react';
import { ChevronLeft, ChevronRight, ExternalLink, Minus, Plus, X } from 'lucide-react';

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

const ZOOM_LEVELS = [1, 1.5, 2, 3];

// `images` is the full gallery the opened `url` belongs to (e.g. all photos
// on the same complaint/survey) - pass it to get Prev/Next navigation and a
// "2 / 5" counter. Omit it (or a single-item list) for a plain single-photo
// viewer, same as before.
export function PhotoLightbox({ url, images, onClose }: { url: string | null; images?: string[]; onClose: () => void }) {
  const gallery = images && images.length > 1 ? images : null;
  const [index, setIndex] = useState(0);
  const [zoomStep, setZoomStep] = useState(0);

  // Re-sync to whichever photo was actually clicked, and reset zoom, each
  // time a (possibly different) photo is opened.
  useEffect(() => {
    if (!url) return;
    setIndex(gallery ? Math.max(0, gallery.indexOf(url)) : 0);
    setZoomStep(0);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- gallery is a fresh array every render; only re-sync when the opened url itself changes
  }, [url]);

  const hasMultiple = !!gallery;
  const current = hasMultiple ? gallery![index] : url;

  const goPrev = () => { setIndex((i) => (i - 1 + gallery!.length) % gallery!.length); setZoomStep(0); };
  const goNext = () => { setIndex((i) => (i + 1) % gallery!.length); setZoomStep(0); };
  const zoomIn = () => setZoomStep((s) => Math.min(ZOOM_LEVELS.length - 1, s + 1));
  const zoomOut = () => setZoomStep((s) => Math.max(0, s - 1));
  const toggleZoom = () => setZoomStep((s) => (s + 1) % ZOOM_LEVELS.length);

  useEffect(() => {
    if (!url) return undefined;
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
      else if (event.key === 'ArrowLeft' && hasMultiple) goPrev();
      else if (event.key === 'ArrowRight' && hasMultiple) goNext();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url, hasMultiple, index]);

  if (!url || !current) return null;
  const zoom = ZOOM_LEVELS[zoomStep];

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
        className="absolute top-4 right-4 text-white/80 hover:text-white cursor-pointer z-10"
      >
        <X className="w-6 h-6" />
      </button>

      <div
        className="absolute top-4 left-4 flex items-center gap-1.5 z-10"
        onClick={(event) => event.stopPropagation()}
      >
        <button
          type="button"
          aria-label="Zoom out"
          disabled={zoomStep === 0}
          onClick={zoomOut}
          className="p-1.5 rounded-lg bg-white/10 text-white/80 hover:text-white hover:bg-white/20 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer"
        >
          <Minus className="w-4 h-4" />
        </button>
        <span className="text-xs text-white/70 font-semibold w-9 text-center">{zoom}x</span>
        <button
          type="button"
          aria-label="Zoom in"
          disabled={zoomStep === ZOOM_LEVELS.length - 1}
          onClick={zoomIn}
          className="p-1.5 rounded-lg bg-white/10 text-white/80 hover:text-white hover:bg-white/20 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer"
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>

      {hasMultiple && (
        <>
          <button
            type="button"
            aria-label="Previous photo"
            onClick={(event) => { event.stopPropagation(); goPrev(); }}
            className="absolute left-3 top-1/2 -translate-y-1/2 p-2 rounded-full bg-white/10 text-white/80 hover:text-white hover:bg-white/20 cursor-pointer z-10"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <button
            type="button"
            aria-label="Next photo"
            onClick={(event) => { event.stopPropagation(); goNext(); }}
            className="absolute right-3 top-1/2 -translate-y-1/2 p-2 rounded-full bg-white/10 text-white/80 hover:text-white hover:bg-white/20 cursor-pointer z-10"
          >
            <ChevronRight className="w-6 h-6" />
          </button>
          <span className="absolute bottom-4 left-1/2 -translate-x-1/2 text-xs font-semibold text-white/80 bg-black/40 rounded-full px-2.5 py-1 z-10">
            {index + 1} / {gallery!.length}
          </span>
        </>
      )}

      <div
        className="max-w-[92vw] max-h-[88vh] overflow-auto rounded-lg"
        onClick={(event) => event.stopPropagation()}
      >
        <img
          src={current}
          alt="Full size preview"
          onClick={toggleZoom}
          className={`block rounded-lg ${zoom === 1 ? 'max-w-full max-h-[88vh] object-contain cursor-zoom-in' : 'max-w-none h-auto cursor-zoom-out'}`}
          style={zoom > 1 ? { width: `${zoom * 100}%` } : undefined}
        />
      </div>
    </div>
  );
}
