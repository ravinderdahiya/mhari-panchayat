import { useEffect, useState } from 'react';
import { Inbox, Star, UserRound } from 'lucide-react';
import * as api from '../services/api';
import { PhotoThumbnail, PhotoLightbox } from '../components/PhotoLightbox';
import type { Feedback, FeedbackCategory } from '../types';

const CATEGORY_LABEL: Record<FeedbackCategory, string> = {
  bug: 'Bug', suggestion: 'Suggestion', complaint: 'Complaint', general: 'General',
};

const CATEGORY_BADGE: Record<FeedbackCategory, string> = {
  bug: 'bg-red-50 text-red-700 border-red-200',
  suggestion: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  complaint: 'bg-amber-50 text-amber-700 border-amber-200',
  general: 'bg-slate-100 text-slate-600 border-slate-200',
};

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date(value));
}

export default function FeedbackPage() {
  const [feedback, setFeedback] = useState<Feedback[]>([]);
  const [category, setCategory] = useState<FeedbackCategory | 'all'>('all');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null);

  useEffect(() => {
    api.getFeedback()
      .then((res) => setFeedback(res.feedback))
      .catch((reason: Error) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const filtered = category === 'all' ? feedback : feedback.filter((f) => f.category === category);
  const countFor = (c: FeedbackCategory | 'all') => (c === 'all' ? feedback.length : feedback.filter((f) => f.category === c).length);

  return (
    <div className="space-y-4">
      {error && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
          {error}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {(['all', 'bug', 'suggestion', 'complaint', 'general'] as const).map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => setCategory(c)}
            className={`text-xs font-semibold rounded-full border px-3 py-1.5 cursor-pointer ${
              category === c ? 'bg-sidebar text-white border-sidebar' : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
          >
            {c === 'all' ? 'All' : CATEGORY_LABEL[c]} ({countFor(c)})
          </button>
        ))}
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {loading ? (
          <p className="text-sm text-slate-400 p-6 text-center">Loading feedback...</p>
        ) : filtered.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No feedback yet.</p>
          </div>
        ) : (
          <div className="divide-y divide-slate-100">
            {filtered.map((item) => (
              <div key={item.id} className="p-4 space-y-2.5">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-2.5">
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-amber-50 text-accent shrink-0">
                      <UserRound className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="text-sm font-semibold text-slate-800">{item.userName || 'Staff'}</p>
                      <p className="text-[11px] text-slate-400 capitalize">{item.userRole.replaceAll('_', ' ')} · {formatDate(item.createdAt)}</p>
                    </div>
                  </div>
                  <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border shrink-0 ${CATEGORY_BADGE[item.category]}`}>
                    {CATEGORY_LABEL[item.category]}
                  </span>
                </div>

                {item.rating && (
                  <div className="flex items-center gap-0.5">
                    {[1, 2, 3, 4, 5].map((n) => (
                      <Star key={n} className={`w-3.5 h-3.5 ${n <= item.rating! ? 'fill-amber-400 text-amber-400' : 'text-slate-200'}`} />
                    ))}
                  </div>
                )}

                <p className="text-sm text-slate-700 leading-6 whitespace-pre-wrap">{item.message}</p>

                {item.photoUrl && (
                  <div className="w-24">
                    <PhotoThumbnail url={api.mediaUrl(item.photoUrl)} label="Photo" onView={setLightboxUrl} />
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      <PhotoLightbox url={lightboxUrl} onClose={() => setLightboxUrl(null)} />
    </div>
  );
}
