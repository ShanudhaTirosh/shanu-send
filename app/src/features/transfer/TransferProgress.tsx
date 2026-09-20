import { motion } from "framer-motion";
import { CheckCircle2, AlertCircle, Loader2 } from "lucide-react";
import type { LocalFileInput } from "../../lib/tauri";
import type { SendEvent } from "../../types";

export interface FileProgressState {
  bytesSent: number;
  totalBytes: number;
  speedBytesPerSec?: number;
  etaSeconds?: number;
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
          speedBytesPerSec: event.speed_bytes_per_sec,
          etaSeconds: event.eta_seconds,
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

function formatSpeed(bytesPerSec?: number): string {
  if (!bytesPerSec || bytesPerSec <= 0) return "";
  if (bytesPerSec >= 1024 * 1024) {
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} MB/s`;
  }
  return `${(bytesPerSec / 1024).toFixed(0)} KB/s`;
}

function formatEta(seconds?: number): string {
  if (!seconds || seconds <= 0) return "";
  if (seconds < 60) return `${seconds}s left`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${s}s left`;
}

export function TransferProgress({ files, progress }: TransferProgressProps) {
  return (
    <div className="flex flex-col gap-2">
      {files.map((file) => {
        const p = progress[file.id];
        const pct = p && p.totalBytes > 0 ? Math.min(100, (p.bytesSent / p.totalBytes) * 100) : 0;
        const speedText = formatSpeed(p?.speedBytesPerSec);
        const etaText = formatEta(p?.etaSeconds);

        return (
          <div key={file.id} className="glass-panel flex items-center gap-3 px-3.5 py-3">
            {p?.status === "done" && <CheckCircle2 size={18} className="shrink-0 text-emerald-400" />}
            {p?.status === "failed" && <AlertCircle size={18} className="shrink-0 text-rose-400" />}
            {(!p || p.status === "sending" || p.status === "pending") && (
              <Loader2 size={18} className="shrink-0 animate-spin text-neon-cyan" />
            )}

            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <p className="truncate text-sm font-medium text-slate-100">{file.file_name}</p>
                {p?.status === "sending" && (speedText || etaText) && (
                  <div className="flex items-center gap-2 text-xs font-mono text-neon-cyan">
                    {speedText && <span>{speedText}</span>}
                    {etaText && <span className="text-slate-400">({etaText})</span>}
                  </div>
                )}
              </div>
              <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/10">
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
