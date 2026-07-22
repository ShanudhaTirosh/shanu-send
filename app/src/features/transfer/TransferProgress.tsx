import { motion } from "framer-motion";
import { CheckCircle2, AlertCircle, Loader2 } from "lucide-react";
import type { LocalFileInput } from "../../lib/tauri";
import type { SendEvent } from "../../types";

export interface FileProgressState {
  bytesSent: number;
  totalBytes: number;
  status: "pending" | "sending" | "done" | "failed";
  reason?: string;
}

interface TransferProgressProps {
  files: LocalFileInput[];
  progress: Record<string, FileProgressState>;
}

export function reduceSendEvent(
  prev: Record<string, FileProgressState>,
  event: SendEvent,
): Record<string, FileProgressState> {
  switch (event.type) {
    case "FileProgress":
      return {
        ...prev,
        [event.file_id]: {
          bytesSent: event.bytes_sent,
          totalBytes: event.total_bytes,
          status: event.bytes_sent >= event.total_bytes ? "done" : "sending",
        },
      };
    case "FileDone":
      return {
        ...prev,
        [event.file_id]: { ...prev[event.file_id], status: "done" } as FileProgressState,
      };
    case "FileFailed":
      return {
        ...prev,
        [event.file_id]: {
          ...prev[event.file_id],
          status: "failed",
          reason: event.reason,
        } as FileProgressState,
      };
    default:
      return prev;
  }
}

export function TransferProgress({ files, progress }: TransferProgressProps) {
  return (
    <div className="flex flex-col gap-2">
      {files.map((file) => {
        const p = progress[file.id];
        const pct = p && p.totalBytes > 0 ? Math.min(100, (p.bytesSent / p.totalBytes) * 100) : 0;
        return (
          <div key={file.id} className="glass-panel flex items-center gap-3 px-3 py-2.5">
            {p?.status === "done" && <CheckCircle2 size={16} className="shrink-0 text-emerald-400" />}
            {p?.status === "failed" && <AlertCircle size={16} className="shrink-0 text-rose-400" />}
            {(!p || p.status === "sending" || p.status === "pending") && (
              <Loader2 size={16} className="shrink-0 animate-spin text-neon-cyan" />
            )}

            <div className="min-w-0 flex-1">
              <p className="truncate text-sm">{file.file_name}</p>
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
                <motion.div
                  className="h-full rounded-full bg-gradient-to-r from-neon-cyan to-neon-violet"
                  initial={{ width: 0 }}
                  animate={{ width: `${pct}%` }}
                  transition={{ ease: "easeOut", duration: 0.2 }}
                />
              </div>
              {p?.status === "failed" && <p className="mt-1 text-xs text-rose-400">{p.reason}</p>}
            </div>
          </div>
        );
      })}
    </div>
  );
}
