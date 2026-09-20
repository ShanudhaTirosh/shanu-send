import { useState } from "react";
import { Monitor, Video, Settings, Play, X, Sliders, Smartphone } from "lucide-react";
import type { Device } from "../../types";

interface ScreenMirrorModalProps {
  open: boolean;
  onClose: () => void;
  selectedDevice: Device | null;
}

export function ScreenMirrorModal({ open, onClose, selectedDevice }: ScreenMirrorModalProps) {
  const [resolution, setResolution] = useState("1080p");
  const [fps, setFps] = useState("60");
  const [isMirroring, setIsMirroring] = useState(false);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-void-950/80 p-4 backdrop-blur-md">
      <div className="glass-panel-glow w-full max-w-2xl flex-col overflow-hidden p-6">
        <div className="flex items-center justify-between border-b border-white/10 pb-4">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-neon-cyan/20 text-neon-cyan">
              <Monitor size={18} />
            </div>
            <div>
              <h2 className="text-base font-semibold text-slate-100">Screen Mirroring & Control</h2>
              <p className="text-xs text-slate-400">Scrcpy v4 Ultra-low latency engine & Wireless ADB</p>
            </div>
          </div>
          <button onClick={onClose} className="rounded-lg p-1.5 text-slate-400 hover:bg-white/10 hover:text-white">
            <X size={18} />
          </button>
        </div>

        {/* Settings & Mirror View */}
        <div className="my-5 flex flex-col gap-4">
          <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3.5">
            <div className="flex items-center gap-3">
              <Smartphone size={20} className="text-neon-violet" />
              <div>
                <p className="text-xs font-semibold text-slate-200">
                  {selectedDevice ? selectedDevice.alias : "No Android device selected"}
                </p>
                <p className="text-[11px] text-slate-400">
                  {selectedDevice ? `${selectedDevice.ip}:${selectedDevice.port}` : "Connect via USB or Wireless ADB (Android 11+)"}
                </p>
              </div>
            </div>

            <button
              disabled={!selectedDevice}
              onClick={() => setIsMirroring(!isMirroring)}
              className={`glass-button-primary text-xs ${isMirroring ? "from-pink-500/30 to-purple-600/30 border-pink-500/50 text-pink-300" : ""}`}
            >
              <Play size={14} />
              <span>{isMirroring ? "Stop Mirroring" : "Start Mirror Session"}</span>
            </button>
          </div>

          {/* Mirror Display Preview Canvas */}
          <div className="relative flex h-64 w-full items-center justify-center rounded-2xl border border-white/10 bg-void-900/90 overflow-hidden">
            {isMirroring ? (
              <div className="flex flex-col items-center gap-2 text-neon-cyan animate-pulse">
                <Video size={36} />
                <p className="text-xs font-semibold">Active Mirror Stream (60 FPS &middot; 1080p)</p>
                <p className="text-[11px] text-slate-400">OTG Hardware Mouse & Keyboard enabled</p>
              </div>
            ) : (
              <div className="text-center">
                <Monitor className="mx-auto mb-2 text-slate-600" size={32} />
                <p className="text-xs font-medium text-slate-400">Screen stream offline</p>
                <p className="text-[11px] text-slate-500 mt-0.5">Click Start Mirror Session to project device screen</p>
              </div>
            )}
          </div>

          {/* Engine Parameters */}
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
              <label className="text-[11px] font-medium text-slate-400 flex items-center gap-1.5">
                <Sliders size={12} /> Resolution Scaling
              </label>
              <select
                value={resolution}
                onChange={(e) => setResolution(e.target.value)}
                className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
              >
                <option value="720p">720p HD (Low bandwidth)</option>
                <option value="1080p">1080p Full HD (Recommended)</option>
                <option value="native">Native Unscaled (High Performance)</option>
              </select>
            </div>

            <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
              <label className="text-[11px] font-medium text-slate-400 flex items-center gap-1.5">
                <Settings size={12} /> Frame Rate Limit
              </label>
              <select
                value={fps}
                onChange={(e) => setFps(e.target.value)}
                className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
              >
                <option value="30">30 FPS (Power Saver)</option>
                <option value="60">60 FPS (Ultra Smooth)</option>
                <option value="120">120 FPS (High Refresh Rate)</option>
              </select>
            </div>
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
