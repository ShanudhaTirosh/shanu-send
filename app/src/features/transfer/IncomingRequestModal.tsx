import { AnimatePresence, motion } from "framer-motion";
import { Download, X, File as FileIcon } from "lucide-react";
import { useEffect, useState } from "react";
import type { IncomingRequestPayload } from "../../lib/tauri";
import { onIncomingRequest } from "../../lib/tauri";

interface PendingRequest {
  payload: IncomingRequestPayload;
  respond: (accept: boolean) => Promise<void>;
}

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(1)} ${units[unitIndex]}`;
}

/**
 * Renders as a fixed overlay when a peer wants to send us files. Auto-hides
 * once the user responds; the server itself auto-declines after 30s if no
 * response, so this doesn't need its own timeout logic.
 */
export function IncomingRequestModal() {
  const [pending, setPending] = useState<PendingRequest | null>(null);

  useEffect(() => {
    let stop: (() => void) | undefined;
    onIncomingRequest((payload, respond) => {
      setPending({ payload, respond });
    }).then((unsub) => {
      stop = unsub;
    });
    return () => stop?.();
  }, []);

  const respond = async (accept: boolean) => {
    if (!pending) return;
    await pending.respond(accept);
    setPending(null);
  };

  const totalSize = pending?.payload.files.reduce((sum, f) => sum + f.size, 0) ?? 0;

  return (
    <AnimatePresence>
      {pending && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-6 backdrop-blur-sm md:items-center"
        >
          <motion.div
            initial={{ opacity: 0, y: 24, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 12, scale: 0.96 }}
            transition={{ type: "spring", stiffness: 300, damping: 26 }}
            className="glass-panel w-full max-w-sm p-5 shadow-glow"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-neon-cyan/20 text-neon-cyan">
                <Download size={18} />
              </div>
              <div className="min-w-0">
                <p className="font-medium text-slate-100">{pending.payload.senderAlias}</p>
                <p className="text-xs text-slate-400">wants to send you files</p>
              </div>
            </div>

            <ul className="mt-4 max-h-40 space-y-1.5 overflow-y-auto">
              {pending.payload.files.map((f) => (
                <li key={f.id} className="flex items-center gap-2 text-sm text-slate-300">
                  <FileIcon size={14} className="shrink-0 text-slate-500" />
                  <span className="truncate">{f.fileName}</span>
                  <span className="ml-auto shrink-0 text-xs text-slate-500">{humanSize(f.size)}</span>
                </li>
              ))}
            </ul>
            <p className="mt-2 text-xs text-slate-500">
              {pending.payload.files.length} file{pending.payload.files.length === 1 ? "" : "s"} &middot;{" "}
              {humanSize(totalSize)} total
            </p>

            <div className="mt-5 flex gap-2">
              <button
                onClick={() => respond(false)}
                className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-white/10 bg-white/5 py-2.5 text-sm text-slate-300 transition hover:bg-white/10"
              >
                <X size={15} />
                Decline
              </button>
              <button
                onClick={() => respond(true)}
                className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-2.5 text-sm font-medium text-void-950 transition hover:shadow-glow"
              >
                <Download size={15} />
                Accept
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
