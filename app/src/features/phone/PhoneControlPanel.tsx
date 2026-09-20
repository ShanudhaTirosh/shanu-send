import { useState } from "react";
import { Bell, Clipboard, BatteryCharging, Play, SkipBack, SkipForward, Smartphone } from "lucide-react";
import type { Device } from "../../types";

interface PhoneControlPanelProps {
  selectedDevice: Device | null;
}

export function PhoneControlPanel({ selectedDevice }: PhoneControlPanelProps) {
  const [clipboardText, setClipboardText] = useState("");
  const [copiedStatus, setCopiedStatus] = useState<string | null>(null);
  const [ringing, setRinging] = useState(false);

  const handleCopyClipboard = async () => {
    if (!clipboardText) return;
    try {
      await navigator.clipboard.writeText(clipboardText);
      setCopiedStatus("Copied to system clipboard!");
      setTimeout(() => setCopiedStatus(null), 2000);
    } catch (_) {
      setCopiedStatus("Failed to copy");
    }
  };

  const handleRingPhone = () => {
    setRinging(true);
    setTimeout(() => setRinging(false), 3000);
  };

  return (
    <div className="glass-panel flex flex-col gap-4 p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-neon-violet/10 text-neon-violet">
            <Smartphone size={16} />
          </div>
          <div>
            <h2 className="text-sm font-semibold text-slate-100">Phone Hub & Utilities</h2>
            <p className="text-xs text-slate-400">
              {selectedDevice ? `Synced with ${selectedDevice.alias}` : "No phone selected"}
            </p>
          </div>
        </div>

        {/* Battery & Signal Status Pill */}
        {selectedDevice && (
          <div className="flex items-center gap-1.5 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1 text-xs font-medium text-emerald-400">
            <BatteryCharging size={14} />
            <span>85%</span>
          </div>
        )}
      </div>

      {/* Quick Action Grid */}
      <div className="grid grid-cols-2 gap-3">
        <button
          disabled={!selectedDevice || ringing}
          onClick={handleRingPhone}
          className={`glass-button flex items-center justify-center gap-2 py-2.5 ${
            ringing ? "animate-bounce border-pink-500/50 bg-pink-500/20 text-pink-300" : ""
          }`}
        >
          <Bell size={15} className={ringing ? "text-pink-400" : "text-neon-violet"} />
          <span>{ringing ? "Ringing Phone..." : "Ring Phone"}</span>
        </button>

        <button
          disabled={!selectedDevice}
          onClick={() => handleCopyClipboard()}
          className="glass-button flex items-center justify-center gap-2 py-2.5"
        >
          <Clipboard size={15} className="text-neon-cyan" />
          <span>Sync Clipboard</span>
        </button>
      </div>

      {/* Shared Clipboard Box */}
      <div className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-medium text-slate-400">Shared Clipboard:</span>
          {copiedStatus && <span className="text-xs font-medium text-emerald-400">{copiedStatus}</span>}
        </div>
        <textarea
          value={clipboardText}
          onChange={(e) => setClipboardText(e.target.value)}
          placeholder="Paste or type text to sync across devices..."
          className="h-16 w-full resize-none rounded-lg border border-white/10 bg-void-950/60 p-2.5 text-xs text-slate-200 placeholder-slate-500 focus:border-neon-cyan/50 focus:outline-none"
        />
        <button
          disabled={!clipboardText.trim()}
          onClick={handleCopyClipboard}
          className="glass-button py-1.5 text-xs self-end"
        >
          Copy Text
        </button>
      </div>

      {/* Media Controller */}
      <div className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3">
        <span className="text-xs font-medium text-slate-400">Remote Media Player:</span>
        <div className="flex items-center justify-between">
          <div className="text-xs">
            <p className="font-semibold text-slate-200">Local Player / Mobile</p>
            <p className="text-[11px] text-slate-500">KDE Connect Media Plugin</p>
          </div>
          <div className="flex items-center gap-2">
            <button className="flex h-7 w-7 items-center justify-center rounded-lg bg-white/5 hover:bg-white/15 text-slate-300">
              <SkipBack size={13} />
            </button>
            <button className="flex h-7 w-7 items-center justify-center rounded-lg bg-neon-cyan/20 text-neon-cyan hover:bg-neon-cyan/30">
              <Play size={13} />
            </button>
            <button className="flex h-7 w-7 items-center justify-center rounded-lg bg-white/5 hover:bg-white/15 text-slate-300">
              <SkipForward size={13} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
