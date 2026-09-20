import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Smartphone, Copy, Check, QrCode, Apple } from "lucide-react";
import { getSelfInfo } from "../../lib/tauri";

interface AirDropBridgeModalProps {
  open: boolean;
  onClose: () => void;
}

export function AirDropBridgeModal({ open, onClose }: AirDropBridgeModalProps) {
  const [webUrl, setWebUrl] = useState<string>("http://localhost:53317/webdrop");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    getSelfInfo().then((info) => {
      // Build candidate local URL
      setWebUrl(`http://${window.location.hostname || "192.168.1.X"}:${info.port}/webdrop`);
    }).catch(() => {
      setWebUrl(`http://${window.location.hostname || "localhost"}:53317/webdrop`);
    });
  }, [open]);

  const copyLink = () => {
    navigator.clipboard.writeText(webUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  if (!open) return null;

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
              <div className="mx-auto flex h-32 w-32 items-center justify-center rounded-lg bg-white p-2">
                {/* SVG QR Code pattern fallback */}
                <div className="flex flex-col items-center justify-center text-slate-900">
                  <QrCode size={90} className="text-indigo-600" />
                  <span className="text-[9px] font-bold tracking-widest text-slate-700 uppercase">SCAN TO OPEN</span>
                </div>
              </div>
              <p className="mt-3 text-xs font-mono text-cyan-400 break-all">{webUrl}</p>
              <button
                onClick={copyLink}
                className="mt-2.5 inline-flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-slate-200 transition hover:bg-white/10"
              >
                {copied ? <Check size={14} className="text-emerald-400" /> : <Copy size={14} />}
                {copied ? "Link Copied!" : "Copy Web Portal Link"}
              </button>
            </div>

            <div className="space-y-2.5 text-xs text-slate-300">
              <div className="flex items-start gap-2.5 rounded-lg border border-white/5 bg-white/[0.02] p-2.5">
                <Apple size={16} className="mt-0.5 shrink-0 text-cyan-400" />
                <div>
                  <span className="font-semibold text-slate-100">Apple Device Users (iPhone / iPad / Mac):</span>
                  <p className="text-slate-400">Scan QR Code or open Safari to send files straight into ShanuSend without installing any app.</p>
                </div>
              </div>

              <div className="flex items-start gap-2.5 rounded-lg border border-white/5 bg-white/[0.02] p-2.5">
                <Smartphone size={16} className="mt-0.5 shrink-0 text-indigo-400" />
                <div>
                  <span className="font-semibold text-slate-100">Android & Nearby Share Users:</span>
                  <p className="text-slate-400">Open link in Chrome or use LocalSend Android app to connect automatically over LAN.</p>
                </div>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}
