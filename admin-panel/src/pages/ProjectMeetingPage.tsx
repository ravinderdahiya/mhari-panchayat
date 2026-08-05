import { useState } from 'react';
import {
  ArrowRight, CheckCircle2, ChevronLeft, ChevronRight, CircleDot,
  ClipboardCheck, Database, Flag, Landmark, MapPinned, MessageSquareWarning,
  Monitor, ShieldCheck, Smartphone,
} from 'lucide-react';

const slides = [
  { eyebrow: 'PROJECT REVIEW', title: 'Mhari Panchayat', subtitle: 'A connected grievance, field-survey and village asset governance platform', kind: 'hero' },
  { eyebrow: '01 / VISION', title: 'One platform. Three working surfaces.', subtitle: 'Citizens, field teams and administrators work on the same verified data.', kind: 'surfaces' },
  { eyebrow: '02 / MOBILE APP', title: 'Services in every citizen’s hand', subtitle: 'Simple, trackable journeys designed for field and village use.', kind: 'mobile' },
  { eyebrow: '03 / ADMIN PANEL', title: 'Control room for Panchayat operations', subtitle: 'A role-aware view of grievances, surveys, assets and users.', kind: 'admin' },
  { eyebrow: '04 / WORKFLOW', title: 'Complaint to resolution', subtitle: 'Every action is visible, accountable and connected.', kind: 'complaint' },
  { eyebrow: '05 / WORKFLOW', title: 'Field survey to verified asset', subtitle: 'GIS-enabled evidence moves from mobile capture to admin review.', kind: 'survey' },
  { eyebrow: '06 / DELIVERY', title: 'Project status & next actions', subtitle: 'Meeting-ready snapshot for decisions and ownership.', kind: 'status' },
] as const;

const steps = (items: { title: string; text: string }[]) => (
  <div className="grid grid-cols-1 xl:grid-cols-5 gap-3 mt-8">
    {items.map((item, index) => <div key={item.title} className="relative rounded-xl border border-line bg-white p-4 min-h-32">
      <span className="w-7 h-7 rounded-full bg-sidebar text-white text-xs font-bold flex items-center justify-center">{index + 1}</span>
      <h3 className="font-serif font-semibold text-base mt-3 text-ink">{item.title}</h3>
      <p className="text-xs text-muted mt-1.5 leading-relaxed">{item.text}</p>
      {index < items.length - 1 && <ArrowRight className="hidden xl:block absolute -right-5 top-1/2 z-10 w-6 h-6 text-accent" />}
    </div>)}
  </div>
);

function SlideBody({ kind }: { kind: typeof slides[number]['kind'] }) {
  if (kind === 'hero') return <div className="mt-10 grid lg:grid-cols-[1.15fr_.85fr] gap-8 items-end">
    <div><div className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-2 text-xs font-bold text-sidebar"><CircleDot className="w-4 h-4" /> PROJECT MEETING • AUGUST 2026</div>
      <p className="mt-8 text-lg text-muted leading-relaxed max-w-2xl">Digital governance built around real village workflows—report, assign, act, verify and improve.</p></div>
    <div className="rounded-2xl bg-sidebar p-6 text-white"><Landmark className="w-10 h-10 text-accent" /><p className="mt-8 font-serif text-2xl">हर शिकायत का समाधान.<br/>हर संपत्ति का रिकॉर्ड.</p><p className="text-white/55 text-xs mt-4">Citizen • Officer • Surveyor • Administrator</p></div>
  </div>;
  if (kind === 'surfaces') return <div className="grid md:grid-cols-3 gap-5 mt-8">
    {[[Smartphone,'Mobile App','Citizens report issues; officers and surveyors act in the field.'],[Monitor,'Admin Panel','Teams monitor, configure, review and govern operations.'],[Database,'Laravel API','One secure data and workflow layer connects every role.']].map(([Icon,title,text]) => { const I=Icon as typeof Smartphone; return <div key={title as string} className="rounded-2xl border border-line bg-white p-6"><I className="w-9 h-9 text-accent"/><h3 className="font-serif text-xl mt-6">{title as string}</h3><p className="text-sm text-muted mt-3 leading-relaxed">{text as string}</p></div> })}
  </div>;
  if (kind === 'mobile') return <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-4 mt-8">
    {[[MessageSquareWarning,'Citizen','Raise complaint, add location/photos and track status.'],[ClipboardCheck,'Officer','View tasks, acknowledge, resolve, transfer and report.'],[MapPinned,'Surveyor','Capture GIS asset survey with field evidence.'],[ShieldCheck,'Secure Access','OTP, registration approval and role-based experience.']].map(([Icon,title,text]) => { const I=Icon as typeof Smartphone; return <div key={title as string} className="rounded-xl bg-white border border-line p-5"><I className="w-7 h-7 text-sidebar"/><h3 className="font-semibold mt-4">{title as string}</h3><p className="text-xs text-muted mt-2 leading-relaxed">{text as string}</p></div> })}
  </div>;
  if (kind === 'admin') return <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4 mt-8">
    {['Live dashboard & reports','Complaint lifecycle control','Survey and asset review','Master data management','Users, citizens & roles','GIS village asset visibility'].map((x,i)=><div key={x} className="flex gap-4 items-center rounded-xl bg-white border border-line p-5"><span className="font-mono text-accent font-bold">0{i+1}</span><span className="font-semibold text-sm">{x}</span></div>)}
  </div>;
  if (kind === 'complaint') return steps([{title:'Report',text:'Citizen submits category, location, description and evidence.'},{title:'Acknowledge',text:'Responsible officer accepts and starts action.'},{title:'Resolve',text:'Action, evidence and resolution notes are recorded.'},{title:'Verify',text:'Outcome is reviewed; complaint may be reopened.'},{title:'Measure',text:'Citizen rating and reports improve accountability.'}]);
  if (kind === 'survey') return steps([{title:'Configure',text:'Admin maps departments, surveyors and asset types.'},{title:'Assign',text:'Field responsibility becomes visible in the app.'},{title:'Capture',text:'Surveyor records GIS position, details and photos.'},{title:'Review',text:'Admin checks pending submissions and evidence.'},{title:'Publish',text:'Approved survey updates the village asset record.'}]);
  return <div className="grid lg:grid-cols-[1fr_1fr] gap-6 mt-8"><div className="rounded-2xl bg-white border border-line p-6"><h3 className="font-serif text-xl">Delivered capabilities</h3>{['Role-based access and registration','Complaint operations and reporting','GIS village assets and surveys','Admin masters, users and permissions'].map(x=><p key={x} className="flex items-center gap-3 mt-4 text-sm"><CheckCircle2 className="w-5 h-5 text-status-closed"/>{x}</p>)}</div><div className="rounded-2xl bg-sidebar text-white p-6"><h3 className="font-serif text-xl">Next meeting decisions</h3>{['Confirm UAT owners and scenarios','Finalize production API/SMS readiness','Approve field rollout and training plan','Track launch KPIs and support cadence'].map((x,i)=><p key={x} className="flex items-start gap-3 mt-4 text-sm text-white/80"><Flag className="w-4 h-4 mt-0.5 text-accent"/><span><b className="text-white">0{i+1}</b> — {x}</span></p>)}</div></div>;
}

export default function ProjectMeetingPage() {
  const [index, setIndex] = useState(0); const slide = slides[index];
  return <div className="max-w-[1280px] mx-auto">
    <div className="rounded-2xl border border-line bg-paper shadow-sm overflow-hidden min-h-[600px] flex flex-col">
      <div className="h-1.5 bg-sidebar"><div className="h-full bg-accent transition-all" style={{width:`${((index+1)/slides.length)*100}%`}}/></div>
      <section className="flex-1 p-8 lg:p-12 bg-[radial-gradient(circle_at_top_right,#F2E2BC_0,transparent_32%)]">
        <div className="flex items-center justify-between"><span className="font-mono text-[11px] tracking-[.2em] text-accent-dark font-bold">{slide.eyebrow}</span><span className="text-xs text-muted">{String(index+1).padStart(2,'0')} / {String(slides.length).padStart(2,'0')}</span></div>
        <h2 className="font-serif text-3xl lg:text-5xl text-ink mt-5 max-w-4xl leading-tight">{slide.title}</h2><p className="text-sm lg:text-base text-muted mt-3">{slide.subtitle}</p>
        <SlideBody kind={slide.kind}/>
      </section>
      <footer className="px-6 py-4 border-t border-line flex items-center justify-between bg-white"><div className="flex gap-1.5">{slides.map((_,i)=><button aria-label={`Slide ${i+1}`} key={i} onClick={()=>setIndex(i)} className={`h-2 rounded-full cursor-pointer transition-all ${i===index?'w-7 bg-accent':'w-2 bg-line hover:bg-muted'}`}/>)}</div><div className="flex gap-2"><button onClick={()=>setIndex(Math.max(0,index-1))} disabled={index===0} className="p-2 rounded-lg border border-line disabled:opacity-30 cursor-pointer"><ChevronLeft className="w-4 h-4"/></button><button onClick={()=>setIndex(Math.min(slides.length-1,index+1))} disabled={index===slides.length-1} className="p-2 rounded-lg bg-sidebar text-white disabled:opacity-30 cursor-pointer"><ChevronRight className="w-4 h-4"/></button></div></footer>
    </div>
  </div>;
}
