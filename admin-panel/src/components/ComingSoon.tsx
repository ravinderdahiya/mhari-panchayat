export default function ComingSoon({ title }: { title: string }) {
  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-10 text-center">
      <h2 className="text-lg font-bold text-slate-800">{title}</h2>
      <p className="text-sm text-slate-400 mt-1">Coming soon.</p>
    </div>
  );
}
