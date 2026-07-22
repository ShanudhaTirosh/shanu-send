import { AnimatePresence, motion } from "framer-motion";
import { X, History as HistoryIcon, ArrowUpRight, ArrowDownLeft, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";
import { clearHistory, listHistory, type TransferRecord } from "../../lib/tauri";

interface HistoryPanelProps {
  open: boolean;
  onClose: () => void;
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

function relativeTime(unixSeconds: number): string {
  const diffMs = Date.now() - unixSeconds * 1000;
  const minutes = Math.floor(diffMs / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function HistoryPanel({ open, onClose }: HistoryPanelProps) {
  const [records, setRecords] = useState<TransferRecord[] | null>(null);

  useEffect(() => {
    if (!open) return;
    listHistory().then(setRecords);
  }, [open]);

  const handleClear = async () => {
    await clearHistory();
    setRecords([]);
  };

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm"
          />
          <motion.aside
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", stiffness: 320, damping: 32 }}
            className="fixed right-0 top-0 z-50 flex h-full w-full max-w-sm flex-col border-l border-white/10 bg-void-900/95 p-5 backdrop-blur-glass"
          >
            <div className="mb-6 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <HistoryIcon size={18} className="text-neon-violet" />
                <h2 className="text-base font-medium">History</h2>
              </div>
              <div className="flex items-center gap-3">
                {records && records.length > 0 && (
                  <button
                    onClick={handleClear}
                    className="text-slate-400 transition hover:text-rose-400"
                    aria-label="Clear history"
                  >
                    <Trash2 size={16} />
                  </button>
                )}
                <button onClick={onClose} className="text-slate-400 transition hover:text-slate-100">
                  <X size={18} />
                </button>
              </div>
            </div>

            {!records ? (
              <p className="text-sm text-slate-500">Loading…</p>
            ) : records.length === 0 ? (
              <div className="flex flex-1 flex-col items-center justify-center gap-2 text-center text-slate-500">
                <HistoryIcon size={28} className="text-slate-600" />
                <p className="text-sm">No transfers yet.</p>
              </div>
            ) : (
              <ul className="flex flex-1 flex-col gap-2 overflow-y-auto">
                {records.map((r) => (
                  <li key={r.id} className="glass-panel flex items-center gap-3 px-3 py-2.5">
                    {r.direction === "sent" ? (
                      <ArrowUpRight
                        size={16}
                        className={`shrink-0 ${r.status === "failed" ? "text-rose-400" : "text-neon-cyan"}`}
                      />
                    ) : (
                      <ArrowDownLeft
                        size={16}
                        className={`shrink-0 ${r.status === "failed" ? "text-rose-400" : "text-neon-violet"}`}
                      />
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm">{r.file_name}</p>
                      <p className="truncate text-xs text-slate-500">
                        {r.direction === "sent" ? "to" : "from"} {r.peer_alias} &middot; {humanSize(r.size)}
                        {r.status === "failed" && <span className="text-rose-400"> &middot; failed</span>}
                      </p>
                    </div>
                    <span className="shrink-0 text-xs text-slate-500">{relativeTime(r.timestamp)}</span>
                  </li>
                ))}
              </ul>
            )}
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}
