import { useEffect, useMemo, useState } from 'react';
import { MapPin, Camera, ClipboardCheck, ExternalLink } from 'lucide-react';
import * as api from '../services/api';
import type { Complaint, ComplaintStatus, User } from '../types';
import { StatusBadge } from '../components/StatusBadge';

interface MySurveysPageProps {
  currentUser: User;
  onNavigateToComplaint: (id: number) => void;
}

type SurveyStage = 'Before' | 'During' | 'After';

function nextStage(status: ComplaintStatus): SurveyStage | null {
  if (status === 'Acknowledged') return 'Before';
  if (status === 'Surveyed') return 'During';
  if (status === 'In_Progress') return 'After';
  return null;
}

// Same hashing approach as ComplaintsPage's categoryColor - kept local since
// it's a 4-line helper, not worth sharing a module for.
const CATEGORY_DOT_COLORS = ['#2a78d6', '#008300', '#e87ba4', '#eda100', '#1baf7a', '#eb6834', '#4a3aa7', '#e34948'];
function categoryColor(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return CATEGORY_DOT_COLORS[Math.abs(hash) % CATEGORY_DOT_COLORS.length];
}

export default function MySurveysPage({ currentUser, onNavigateToComplaint }: MySurveysPageProps) {
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [notes, setNotes] = useState('');
  const [photo, setPhoto] = useState<File | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState('');

  const load = async () => {
    setIsLoading(true);
    try {
      const { complaints } = await api.getComplaints();
      setComplaints(complaints);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  // A survey-eligible complaint belongs here if it's already assigned to me,
  // or unassigned (the backend auto-assigns whoever submits the first stage,
  // so an unclaimed one is fair game for any surveyor to pick up).
  const mySurveys = useMemo(
    () => complaints
      .filter((c) => nextStage(c.status) !== null)
      .filter((c) => c.assigned_to_id === null || c.assigned_to_id === currentUser.id)
      .sort((a, b) => a.id - b.id),
    [complaints, currentUser.id],
  );

  const toggleExpand = (id: number) => {
    setExpandedId((prev) => (prev === id ? null : id));
    setNotes('');
    setPhoto(null);
    setError('');
  };

  const submit = async (c: Complaint) => {
    const stage = nextStage(c.status);
    if (!stage) return;
    setIsSubmitting(true);
    setError('');
    try {
      const { complaint } = await api.submitSurvey(c.id, stage, notes || undefined, photo || undefined);
      setComplaints((prev) => prev.map((x) => (x.id === complaint.id ? complaint : x)));
      setExpandedId(null);
      setNotes('');
      setPhoto(null);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-4">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}

      {isLoading ? (
        <p className="text-sm text-muted">Loading…</p>
      ) : mySurveys.length === 0 ? (
        <div className="bg-white border border-slate-200 rounded-2xl p-10 text-center">
          <ClipboardCheck className="w-6 h-6 text-slate-300 mx-auto mb-2" />
          <p className="text-sm text-muted">No complaints need a field survey right now.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {mySurveys.map((c) => {
            const stage = nextStage(c.status)!;
            const isMine = c.assigned_to_id === currentUser.id;
            const isExpanded = expandedId === c.id;
            return (
              <div key={c.id} className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
                <button
                  onClick={() => toggleExpand(c.id)}
                  className="w-full text-left p-4 flex flex-wrap items-center gap-3 cursor-pointer"
                >
                  <span className="font-mono text-[10px] font-bold text-muted bg-cream border border-line rounded px-1.5 py-0.5 shrink-0">
                    #{c.id}
                  </span>
                  <span className="flex items-center gap-2 font-semibold text-ink text-sm shrink-0">
                    <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: categoryColor(c.category.name) }} />
                    {c.category.name}
                  </span>
                  <span className="flex items-center gap-1 text-xs text-muted truncate flex-1 min-w-[120px]">
                    <MapPin className="w-3 h-3 shrink-0" />
                    {[c.village, c.panchayat].filter(Boolean).join(', ') || 'No location'}
                  </span>
                  <StatusBadge status={c.status} />
                  <span className="text-[10px] font-bold uppercase px-2 py-1 rounded-full bg-status-progress/10 text-status-progress shrink-0">
                    {stage} stage
                  </span>
                  {!isMine && (
                    <span className="text-[10px] font-bold uppercase px-2 py-1 rounded-full bg-accent-soft text-accent-dark shrink-0">
                      Unclaimed
                    </span>
                  )}
                </button>

                {isExpanded && (
                  <div className="border-t border-slate-100 p-4 space-y-3 bg-cream/40">
                    <textarea
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      placeholder={`Notes for ${stage} stage (optional)`}
                      rows={2}
                      className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent resize-none"
                    />
                    <div className="flex items-center gap-2">
                      <label className="flex items-center gap-1.5 text-xs font-semibold text-muted border border-line rounded-lg px-2.5 py-1.5 cursor-pointer hover:border-accent-soft">
                        <Camera className="w-3.5 h-3.5" />
                        {photo ? photo.name : 'Attach photo (optional)'}
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
                        />
                      </label>
                      {photo && (
                        <button onClick={() => setPhoto(null)} className="text-xs text-muted hover:text-ink cursor-pointer">
                          Remove
                        </button>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        disabled={isSubmitting}
                        onClick={() => submit(c)}
                        className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg cursor-pointer"
                      >
                        Submit {stage} Stage
                      </button>
                      <button
                        onClick={() => onNavigateToComplaint(c.id)}
                        className="flex items-center gap-1.5 text-xs font-semibold text-accent hover:underline cursor-pointer ml-auto"
                      >
                        View Full Details
                        <ExternalLink className="w-3 h-3" />
                      </button>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
