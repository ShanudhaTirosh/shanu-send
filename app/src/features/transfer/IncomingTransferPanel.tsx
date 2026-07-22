import { motion } from "framer-motion";
import { CheckCircle2, AlertCircle, Loader2, Inbox } from "lucide-react";
import { useIncomingTransfers } from "./useIncomingTransfers";

export function IncomingTransferPanel() {
  const transfers = useIncomingTransfers();
  if (transfers.length === 0) return null;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-1.5 text-xs uppercase tracking-wide text-slate-500">
        <Inbox size={13} />
        Receiving
      </div>
      {transfers.map((t) => {
        const pct = t.totalBytes > 0 ? Math.min(100, (t.receivedBytes / t.totalBytes) * 100) : 0;
        return (
          <div key={`${t.sessionId}:${t.fileId}`} className="glass-panel flex items-center gap-3 px-3 py-2.5">
            {t.status === "done" && <CheckCircle2 size={16} className="shrink-0 text-emerald-400" />}
            {t.status === "failed" && <AlertCircle size={16} className="shrink-0 text-rose-400" />}
            {t.status === "receiving" && <Loader2 size={16} className="shrink-0 animate-spin text-neon-violet" />}

            <div className="min-w-0 flex-1">
              <p className="truncate text-sm">{t.fileName}</p>
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
                <motion.div
                  className="h-full rounded-full bg-gradient-to-r from-neon-violet to-neon-pink"
                  initial={{ width: 0 }}
                  animate={{ width: `${pct}%` }}
                  transition={{ ease: "easeOut", duration: 0.2 }}
                />
              </div>
              {t.status === "failed" && <p className="mt-1 text-xs text-rose-400">{t.reason}</p>}
            </div>
          </div>
        );
      })}
    </div>
  );
}
