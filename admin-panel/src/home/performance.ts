export type Tone = 'good' | 'fair' | 'poor';

/** Colour band for an SLA compliance percentage. */
export const complianceTone = (percent: number): Tone => (percent >= 90 ? 'good' : percent >= 70 ? 'fair' : 'poor');

/** 87.5 -> "87.5%", 75 -> "75%" (no pointless ".0"). */
export const formatCompliance = (percent: number) => `${Math.round(percent * 10) / 10}%`;

/** CSS width for a progress bar; a bad value can never overflow the layout. */
export const barWidth = (percent: number) => `${Number.isFinite(percent) ? Math.min(100, Math.max(0, percent)) : 0}%`;
