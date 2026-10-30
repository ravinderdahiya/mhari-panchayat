import { useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { AlertTriangle, Trash2, X } from 'lucide-react';

/** App-styled replacements for window.confirm / window.alert; each opens, resolves once and unmounts. */

interface ConfirmOptions {
  title: string;
  message: string;
  confirmLabel?: string;
  tone?: 'danger' | 'neutral';
}

interface DialogProps extends ConfirmOptions {
  cancelLabel: string | null;
  onClose: (confirmed: boolean) => void;
}

function Dialog({ title, message, confirmLabel = 'Confirm', cancelLabel, tone = 'danger', onClose }: DialogProps) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const danger = tone === 'danger';
  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/45 p-5" onClick={() => onClose(false)}>
      <div role="alertdialog" aria-modal="true" aria-labelledby="dialog-title" aria-describedby="dialog-message"
        className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl" onClick={(event) => event.stopPropagation()}>
        <div className="flex items-start justify-between">
          <div className={`mb-4 flex h-11 w-11 items-center justify-center rounded-full ${danger ? 'bg-red-50 text-red-600' : 'bg-amber-50 text-accent'}`}>
            {danger && cancelLabel ? <Trash2 className="h-5 w-5" /> : <AlertTriangle className="h-5 w-5" />}
          </div>
          <button type="button" aria-label="Close" onClick={() => onClose(false)} className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 cursor-pointer"><X className="h-4 w-4" /></button>
        </div>
        <h2 id="dialog-title" className="text-lg font-bold text-slate-900">{title}</h2>
        <p id="dialog-message" className="mt-2 text-sm leading-6 text-slate-500 break-words">{message}</p>
        <div className="mt-6 flex justify-end gap-2">
          {cancelLabel && (
            <button type="button" onClick={() => onClose(false)} className="rounded-lg border border-slate-200 px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-50 cursor-pointer">
              {cancelLabel}
            </button>
          )}
          <button type="button" autoFocus onClick={() => onClose(true)}
            className={`rounded-lg px-4 py-2 text-xs font-bold text-white cursor-pointer ${danger ? 'bg-red-600 hover:bg-red-700' : 'bg-sidebar hover:opacity-90'}`}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function open(options: ConfirmOptions, cancelLabel: string | null): Promise<boolean> {
  return new Promise((resolve) => {
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);
    let closed = false;
    const close = (confirmed: boolean) => {
      if (closed) return;
      closed = true;
      resolve(confirmed);
      root.unmount();
      host.remove();
    };
    root.render(<Dialog {...options} cancelLabel={cancelLabel} onClose={close} />);
  });
}

export const confirmDialog = (options: ConfirmOptions) => open({ confirmLabel: 'Delete', ...options }, 'Cancel');

export const noticeDialog = (title: string, message: string) =>
  open({ title, message, confirmLabel: 'OK', tone: 'neutral' }, null).then(() => undefined);
