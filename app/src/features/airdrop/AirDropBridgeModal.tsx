import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Smartphone, Copy, Check, QrCode, Apple, FolderPlus, Trash2 } from "lucide-react";
import { getSelfInfo, pickFilesToTransfer, webdropShareFiles, webdropGetSharedFiles, webdropClearSharedFiles, WebDropSharedFile } from "../../lib/tauri";

interface AirDropBridgeModalProps {
  open: boolean;
  onClose: () => void;
}

export function AirDropBridgeModal({ open, onClose }: AirDropBridgeModalProps) {
  const [webUrl, setWebUrl] = useState<string>("http://127.0.0.1:53317/web");
  const [copied, setCopied] = useState(false);
  const [sharedFiles, setSharedFiles] = useState<WebDropSharedFile[]>([]);
  const [sharingStatus, setSharingStatus] = useState<string>("");

  useEffect(() => {
    if (open) {
      getSelfInfo().then((info) => {
        const ip = info.local_ip && info.local_ip !== "127.0.0.1"
          ? info.local_ip
          : (window.location.hostname && window.location.hostname !== "localhost" && window.location.hostname !== "tauri.localhost"
              ? window.location.hostname
              : "127.0.0.1");
        setWebUrl(`http://${ip}:${info.port}/web`);
      }).catch(() => {
        setWebUrl(`http://127.0.0.1:53317/web`);
      });

      refreshSharedFiles();
    }
  }, [open]);

  const refreshSharedFiles = () => {
    webdropGetSharedFiles().then(setSharedFiles).catch(() => {});
  };

  const handleShareFiles = async () => {
    try {
      const files = await pickFilesToTransfer();
      if (files.length > 0) {
        const paths = files.map((f) => f.path);
        const count = await webdropShareFiles(paths);
        setSharingStatus(`Shared ${count} file(s) to Web Portal!`);
        refreshSharedFiles();
        setTimeout(() => setSharingStatus(""), 3000);
      }
    } catch (err: any) {
      setSharingStatus(`Share error: ${err?.message || err}`);
    }
  };

  const handleClearShared = async () => {
    await webdropClearSharedFiles();
    refreshSharedFiles();
  };

  const copyLink = () => {
    navigator.clipboard.writeText(webUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  if (!open) return null;

  const qrImageUrl = `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(webUrl)}&color=4f46e5&bgcolor=ffffff`;

  return (
    <AnimatePresence>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          className="glass-panel relative w-full max-w-md overflow-hidden rounded-2xl border border-white/10 bg-slate-900/95 p-6 shadow-2xl"
        >
          <button
            onClick={onClose}
            className="absolute right-4 top-4 flex h-8 w-8 items-center justify-center rounded-full bg-white/5 text-slate-400 hover:bg-white/10 hover:text-white"
          >
            <X size={16} />
          </button>

          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-cyan-500 to-indigo-600 text-white">
              <QrCode size={20} />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-white">AirDrop & Nearby Share Bridge</h2>
              <p className="text-xs text-slate-400">Instant web-sharing portal for iOS, Mac & Android</p>
            </div>
          </div>

          <div className="mt-5 space-y-4">
            <div className="rounded-xl border border-white/10 bg-slate-950/60 p-4 text-center">
              <div className="mx-auto flex h-36 w-36 items-center justify-center rounded-xl bg-white p-2.5 shadow-lg overflow-hidden">
                <img
                  src={qrImageUrl}
                  alt="Scan to open Web Portal"
                  className="h-full w-full object-contain"
                  onError={(e) => {
                    (e.target as HTMLElement).style.display = "none";
                  }}
                />
              </div>
              <p className="mt-3 text-xs font-mono text-cyan-400 break-all font-semibold">{webUrl}</p>
              <div className="mt-2.5 flex items-center justify-center gap-2">
                <button
                  onClick={copyLink}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-slate-200 transition hover:bg-white/10"
                >
                  {copied ? <Check size={14} className="text-emerald-400" /> : <Copy size={14} />}
                  {copied ? "Copied!" : "Copy Link"}
                </button>
                <button
                  onClick={handleShareFiles}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-500/30 bg-indigo-600/30 px-3 py-1.5 text-xs font-medium text-indigo-200 transition hover:bg-indigo-600/50"
                >
                  <FolderPlus size={14} />
                  Share Desktop Files
                </button>
              </div>
              {sharingStatus && (
                <p className="mt-2 text-xs text-emerald-400 font-medium">{sharingStatus}</p>
              )}
            </div>

            {sharedFiles.length > 0 && (
              <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3 text-xs">
                <div className="flex items-center justify-between text-slate-300 font-medium mb-2">
                  <span>Files Published to Web ({sharedFiles.length}):</span>
                  <button
                    onClick={handleClearShared}
                    className="inline-flex items-center gap-1 text-rose-400 hover:text-rose-300"
                  >
                    <Trash2 size={12} /> Clear
                  </button>
                </div>
                <div className="max-h-24 overflow-y-auto space-y-1">
                  {sharedFiles.map((f) => (
                    <div key={f.id} className="flex justify-between text-slate-400 font-mono text-[11px]">
                      <span className="truncate max-w-[200px]">{f.name}</span>
                      <span>{(f.size / (1024 * 1024)).toFixed(1)} MB</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="space-y-2 text-xs text-slate-300">
              <div className="flex items-start gap-2.5 rounded-lg border border-white/5 bg-white/[0.02] p-2.5">
                <Apple size={16} className="mt-0.5 shrink-0 text-cyan-400" />
                <div>
                  <span className="font-semibold text-slate-100">Apple Users (iPhone / iPad / Mac):</span>
                  <p className="text-slate-400">Scan QR Code or open Safari to send/download files directly without installing any app.</p>
                </div>
              </div>

              <div className="flex items-start gap-2.5 rounded-lg border border-white/5 bg-white/[0.02] p-2.5">
                <Smartphone size={16} className="mt-0.5 shrink-0 text-indigo-400" />
                <div>
                  <span className="font-semibold text-slate-100">Android & Nearby Share:</span>
                  <p className="text-slate-400">Open link in Chrome to upload/download files or text notes instantly.</p>
                </div>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}

