import type { CSSProperties, ComponentType } from 'react';
import { MapPin, Phone, PhoneCall, Mail, UserRound, UserCheck, Building2, Landmark } from 'lucide-react';
import type { PanchayatOfficial } from '../services/api';

// Attributes as returned by the HARSAC panchayat boundary MapServer's
// panchayat_bnd layer (id 1, "GP_append_1") - see GisController. CPLO/BDPO/
// DDPO contact fields live directly on this GIS layer, but cplo_name is
// blank for a lot of panchayats in HARSAC's source data, and the layer has
// no Gram Sachiv fields at all - both are backfilled from our own
// panchayats/officials lookup instead (see `localOfficials` below).
export interface PanchayatFeatureAttributes {
  district_name?: string | null;
  block_name?: string | null;
  village_name?: string | null;
  localbodyname?: string | null;
  cplo_name?: string | null;
  cplo_mob_no?: string | number | null;
  cplo_mail_id?: string | null;
  bdpo_name?: string | null;
  bdpo_mobile?: string | number | null;
  bdpo_landline?: string | number | null;
  bdpo_e_mail?: string | null;
  bdpo_office_address?: string | null;
  ddpo_name?: string | null;
  ddpo_mobile?: string | number | null;
  ddpo_landline?: string | number | null;
  ddpo_e_mail?: string | null;
  ddpo_office_address?: string | null;
}

export interface LocalOfficials {
  cplo: PanchayatOfficial | null;
  gram_sachiv: PanchayatOfficial | null;
}

// Blank cells come back as empty strings; phone numbers on this GIS layer
// are typed esriFieldTypeDouble (bdpo/ddpo/cplo mobile, bdpo landline) while
// others are strings - normalise both to a trimmed string or null.
const clean = (value?: string | number | null) => {
  if (value == null) return null;
  const trimmed = String(value).trim();
  return trimmed ? trimmed : null;
};

// One accent per role, reusing the existing status palette (index.css) so
// this doesn't introduce new colors to the design system.
const ROLE_STYLE: Record<string, { icon: ComponentType<{ className?: string; style?: CSSProperties }>; color: string; tint: string }> = {
  'Gram Sachiv': { icon: UserCheck, color: 'var(--color-status-new)', tint: 'color-mix(in srgb, var(--color-status-new) 8%, white)' },
  CPLO: { icon: UserRound, color: 'var(--color-status-closed)', tint: 'color-mix(in srgb, var(--color-status-closed) 8%, white)' },
  BDPO: { icon: Building2, color: 'var(--color-accent)', tint: 'color-mix(in srgb, var(--color-accent) 10%, white)' },
  DDPO: { icon: Landmark, color: 'var(--color-status-rejected)', tint: 'color-mix(in srgb, var(--color-status-rejected) 8%, white)' },
};

function OfficerBlock({
  role,
  name,
  mobile,
  landline,
  email,
  officeAddress,
}: {
  role: keyof typeof ROLE_STYLE;
  name: string | null;
  mobile: string | null;
  landline: string | null;
  email: string | null;
  officeAddress?: string | null;
}) {
  const { icon: Icon, color, tint } = ROLE_STYLE[role];
  const hasDetails = name || mobile || landline || email;

  return (
    <div className="rounded-lg p-2.5 border" style={{ backgroundColor: tint, borderColor: `color-mix(in srgb, ${color} 20%, white)` }}>
      <div className="flex items-center gap-2">
        <div className="w-6 h-6 rounded-full flex items-center justify-center shrink-0" style={{ backgroundColor: `color-mix(in srgb, ${color} 18%, white)` }}>
          <Icon className="w-3.5 h-3.5" style={{ color }} />
        </div>
        <div className="text-[10.5px] font-bold uppercase tracking-wide" style={{ color }}>{role}</div>
      </div>

      {hasDetails ? (
        <div className="mt-1.5 pl-8 space-y-1">
          {name && <div className="text-[13px] font-medium text-ink leading-snug">{name}</div>}
          <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-[11px] text-muted">
            {mobile && (
              <span className="flex items-center gap-1">
                <Phone className="w-3 h-3 shrink-0" />
                {mobile}
              </span>
            )}
            {landline && (
              <span className="flex items-center gap-1">
                <PhoneCall className="w-3 h-3 shrink-0" />
                {landline}
              </span>
            )}
            {email && (
              <span className="flex items-center gap-1 truncate">
                <Mail className="w-3 h-3 shrink-0" />
                <span className="truncate">{email}</span>
              </span>
            )}
          </div>
          {officeAddress && <div className="text-[10.5px] text-muted leading-snug">{officeAddress}</div>}
        </div>
      ) : (
        <div className="mt-1.5 pl-8 text-[11px] text-muted italic">Not available</div>
      )}
    </div>
  );
}

export default function PanchayatPopupCard({
  attributes,
  localOfficials,
}: {
  attributes: PanchayatFeatureAttributes;
  // Undefined while the lookup is still in flight, null once it's resolved
  // to nothing - both render fine, this just means "nothing to backfill".
  localOfficials?: LocalOfficials | null;
}) {
  const location = [attributes.block_name, attributes.district_name].filter(Boolean).join(', ');

  const gisCplo = clean(attributes.cplo_name);
  const dbCplo = localOfficials?.cplo;
  const dbGramSachiv = localOfficials?.gram_sachiv;

  return (
    <div className="w-72 -mx-1 -mt-0.5">
      {location && (
        <div className="flex items-center gap-1.5 mb-3 pb-2.5 border-b border-line">
          <MapPin className="w-3.5 h-3.5 text-accent shrink-0" />
          <div className="text-xs text-muted">{location}</div>
        </div>
      )}

      <div className="space-y-2">
        <OfficerBlock
          role="Gram Sachiv"
          name={dbGramSachiv?.name ?? null}
          mobile={clean(dbGramSachiv?.mobile)}
          landline={null}
          email={clean(dbGramSachiv?.email)}
        />
        <OfficerBlock
          role="CPLO"
          name={gisCplo ?? dbCplo?.name ?? null}
          mobile={gisCplo ? clean(attributes.cplo_mob_no) : clean(dbCplo?.mobile)}
          landline={null}
          email={gisCplo ? clean(attributes.cplo_mail_id) : clean(dbCplo?.email)}
        />
        <OfficerBlock
          role="BDPO"
          name={clean(attributes.bdpo_name)}
          mobile={clean(attributes.bdpo_mobile)}
          landline={clean(attributes.bdpo_landline)}
          email={clean(attributes.bdpo_e_mail)}
          officeAddress={clean(attributes.bdpo_office_address)}
        />
        <OfficerBlock
          role="DDPO"
          name={clean(attributes.ddpo_name)}
          mobile={clean(attributes.ddpo_mobile)}
          landline={clean(attributes.ddpo_landline)}
          email={clean(attributes.ddpo_e_mail)}
          officeAddress={clean(attributes.ddpo_office_address)}
        />
      </div>
    </div>
  );
}
