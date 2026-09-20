import { useState } from "react";
import { Share2, Wifi, Bluetooth, ShieldCheck, X, RefreshCw, CheckCircle2 } from "lucide-react";

interface QuickShareModalProps {
  open: boolean;
  onClose: () => void;
}

export function QuickShareModal({ open, onClose }: QuickShareModalProps) {
  const [bleEnabled, setBleEnabled] = useState(true);
  const [wifiDirectEnabled, setWifiDirectEnabled] = useState(true);
  const [pin, setPin] = useState<string | null>(null);

  if (!open) return null;

  const handleSimulatePin = () => {
    const randomPin = Math.floor(1000 + Math.random() * 9000).toString();
    setPin(randomPin);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-void-950/80 p-4 backdrop-blur-md">
      <div className="glass-panel-glow w-full max-w-xl flex-col overflow-hidden p-6">
        <div className="flex items-center justify-between border-b border-white/10 pb-4">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-neon-cyan/20 text-neon-cyan">
              <Share2 size={18} />
            </div>
            <div>
              <h2 className="text-base font-semibold text-slate-100">Android Quick Share Engine</h2>
              <p className="text-xs text-slate-400">Native Nearby Share / BLE 0xFE2C & UKEY2 Handshake</p>
            </div>
          </div>
          <button onClick={onClose} className="rounded-lg p-1.5 text-slate-400 hover:bg-white/10 hover:text-white">
            <X size={18} />
          </button>
        </div>

        {/* Engine Status Grid */}
        <div className="my-5 flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3.5">
              <div className="flex items-center gap-2.5">
                <Bluetooth size={18} className="text-neon-cyan" />
                <div>
                  <p className="text-xs font-semibold text-slate-200">Bluetooth LE</p>
                  <p className="text-[11px] text-slate-400">UUID 0xFE2C / L2CAP</p>
                </div>
              </div>
              <input
                type="checkbox"
                checked={bleEnabled}
                onChange={(e) => setBleEnabled(e.target.checked)}
                className="h-4 w-4 rounded border-white/20 bg-void-950 text-neon-cyan focus:ring-neon-cyan"
              />
            </div>

            <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3.5">
              <div className="flex items-center gap-2.5">
                <Wifi size={18} className="text-neon-violet" />
                <div>
                  <p className="text-xs font-semibold text-slate-200">Wi-Fi Direct / mDNS</p>
                  <p className="text-[11px] text-slate-400">Service _FC92._tcp</p>
                </div>
              </div>
              <input
                type="checkbox"
                checked={wifiDirectEnabled}
                onChange={(e) => setWifiDirectEnabled(e.target.checked)}
                className="h-4 w-4 rounded border-white/20 bg-void-950 text-neon-violet focus:ring-neon-violet"
              />
            </div>
          </div>

          {/* UKEY2 Security & PIN Verification */}
          <div className="flex flex-col gap-3 rounded-xl border border-white/10 bg-white/5 p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <ShieldCheck size={16} className="text-emerald-400" />
                <span className="text-xs font-semibold text-slate-200">UKEY2 Secure Authentication</span>
              </div>
              <button
                onClick={handleSimulatePin}
                className="glass-button text-[11px] py-1 px-2.5"
              >
                <RefreshCw size={12} />
                <span>Test Handshake</span>
              </button>
            </div>

            {pin ? (
              <div className="flex items-center justify-between rounded-lg border border-emerald-500/30 bg-emerald-500/10 p-3 text-emerald-300">
                <div className="flex items-center gap-2">
                  <CheckCircle2 size={16} />
                  <span className="text-xs font-medium">UKEY2 Verification PIN Generated:</span>
                </div>
                <span className="text-lg font-mono font-bold tracking-widest text-emerald-200">{pin}</span>
              </div>
            ) : (
              <p className="text-xs text-slate-400">
                Android phones running Nearby / Quick Share will discover this PC automatically via BLE advertisement and mDNS.
              </p>
            )}
          </div>
        </div>

        <div className="flex justify-end">
          <button onClick={onClose} className="glass-button text-xs">
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
