import { MapPin, Calendar, User, Layers } from 'lucide-react';
import type { AssetSurvey } from '../types';

const REVIEW_LABEL: Record<string, string> = {
  submitted: 'Not yet forwarded',
  pending: 'Pending review',
  returned: 'Returned for correction',
  gram_sachiv_reviewed: 'Reviewed by Gram Sachiv',
  gram_sachiv_approved: 'Forwarded by Gram Sachiv',
  bdpo_reviewed: 'Reviewed by BDPO',
  bdpo_forwarded: 'Forwarded by BDPO',
  ddpo_reviewed: 'Reviewed by DDPO',
  ddpo_approved: 'Approved by DDPO',
  xen_reviewed: 'Reviewed by XEN-PR',
  xen_forwarded: 'Forwarded by XEN-PR',
  approved: 'Final approved',
  rejected: 'Rejected',
};

const CONDITION_STYLE: Record<AssetSurvey['condition'], string> = {
  GOOD: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  FAIR: 'bg-blue-50 text-blue-700 border-blue-200',
  POOR: 'bg-amber-50 text-amber-800 border-amber-200',
  DAMAGED: 'bg-red-50 text-red-700 border-red-200',
};

const formatDate = (value: string) =>
  new Date(value).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' });

// The map popup's own answer to "view details" for an asset survey marker -
// mirrors ComplaintPopupCard's picks (what/where/who/when) for the other
// layer on this same map, plus a review-status badge and a photo if one
// exists.
export default function SurveyPopupCard({ survey }: { survey: AssetSurvey }) {
  const location = [survey.village, survey.panchayat].filter(Boolean).join(', ');
  const thumbnail = survey.photoUrls?.[0] ?? null;

  return (
    <div className="w-72 -mx-1">
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full border bg-slate-50 text-slate-700 border-slate-200">
          {REVIEW_LABEL[survey.reviewStatus] ?? survey.reviewStatus}
        </span>
        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${CONDITION_STYLE[survey.condition]}`}>
          {survey.condition}
        </span>
      </div>

      <div className="flex items-start gap-2 mb-2">
        <Layers className="w-3.5 h-3.5 text-muted shrink-0 mt-0.5" />
        <div className="text-[13px] font-semibold text-ink leading-snug">
          {survey.assetName}
          {survey.assetTypeName && <span className="text-muted font-normal"> · {survey.assetTypeName}</span>}
        </div>
      </div>

      {location && (
        <div className="flex items-start gap-2 mb-2">
          <MapPin className="w-3.5 h-3.5 text-muted shrink-0 mt-0.5" />
          <div className="text-xs text-muted leading-snug">
            <div className="text-ink/80">{location}</div>
            {survey.district && <div>{survey.district}</div>}
          </div>
        </div>
      )}

      {survey.description && (
        <p className="text-xs text-ink/80 leading-relaxed mb-2.5 line-clamp-3">{survey.description}</p>
      )}

      {thumbnail && (
        <img
          src={thumbnail}
          alt="Asset survey"
          className="w-full h-28 object-cover rounded-lg border border-line mb-2.5"
          onError={(e) => { e.currentTarget.style.display = 'none'; }}
        />
      )}

      <div className="space-y-1 pt-2 border-t border-line text-[11px] text-muted">
        {survey.surveyedByName && (
          <div className="flex items-center gap-1.5">
            <User className="w-3 h-3 shrink-0" />
            Surveyed by <span className="text-ink/80 font-medium">{survey.surveyedByName}</span>
          </div>
        )}
        <div className="flex items-center gap-1.5">
          <Calendar className="w-3 h-3 shrink-0" />
          {formatDate(survey.surveyDate)}
        </div>
      </div>
    </div>
  );
}
