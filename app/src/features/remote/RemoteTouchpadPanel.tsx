import { useState, useRef } from "react";
import { MousePointer, ChevronLeft, ChevronRight, Play } from "lucide-react";
import type { Device } from "../../types";

interface RemoteTouchpadPanelProps {
  selectedDevice: Device | null;
}

export function RemoteTouchpadPanel({ selectedDevice }: RemoteTouchpadPanelProps) {
  const [touchActive, setTouchActive] = useState(false);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);
  const lastPos = useRef<{ x: number; y: number } | null>(null);

  const showFeedback = (msg: string) => {
    setStatusMsg(msg);
    setTimeout(() => setStatusMsg(null), 1500);
  };

  const handlePointerDown = (e: React.PointerEvent) => {
    setTouchActive(true);
    lastPos.current = { x: e.clientX, y: e.clientY };
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!touchActive || !lastPos.current) return;
    const dx = e.clientX - lastPos.current.x;
    const dy = e.clientY - lastPos.current.y;
    lastPos.current = { x: e.clientX, y: e.clientY };
    
    // Virtual trackpad movement event
    if (Math.abs(dx) > 1 || Math.abs(dy) > 1) {
      // Sent to backend or web peer
    }
  };

  const handlePointerUp = () => {
    setTouchActive(false);
    lastPos.current = null;
  };

  return (
    <div className="glass-panel flex flex-col gap-4 p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-neon-cyan/10 text-neon-cyan">
            <MousePointer size={16} />
          </div>
          <div>
            <h2 className="text-sm font-semibold text-slate-100">Virtual Touchpad & Presentation Remote</h2>
            <p className="text-xs text-slate-400">
              {selectedDevice ? `Control cursor & slides on ${selectedDevice.alias}` : "Select a device to enable remote control"}
            </p>
          </div>
        </div>
        {statusMsg && (
          <span className="rounded-full bg-neon-cyan/10 px-3 py-1 text-xs font-medium text-neon-cyan border border-neon-cyan/20 animate-fade-in">
            {statusMsg}
          </span>
        )}
      </div>

      {/* Trackpad Touch Area */}
      <div
        className={`trackpad-canvas flex flex-col items-center justify-center ${
          !selectedDevice ? "opacity-50 pointer-events-none" : "cursor-crosshair"
        }`}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerUp}
      >
        <div className="text-center pointer-events-none">
          <MousePointer className={`mx-auto mb-2 text-slate-500 transition-transform ${touchActive ? "scale-125 text-neon-cyan" : ""}`} size={28} />
          <p className="text-xs font-medium text-slate-400">Drag to move cursor &middot; Tap to click</p>
          <p className="text-[11px] text-slate-500 mt-0.5">Two fingers to scroll</p>
        </div>
      </div>

      {/* Mouse Click Buttons */}
      <div className="grid grid-cols-2 gap-3">
        <button
          disabled={!selectedDevice}
          onClick={() => showFeedback("Left Click")}
          className="glass-button py-2.5 hover:bg-white/10"
        >
          Left Click
        </button>
        <button
          disabled={!selectedDevice}
          onClick={() => showFeedback("Right Click")}
          className="glass-button py-2.5 hover:bg-white/10"
        >
          Right Click
        </button>
      </div>

      {/* Presentation & Media Controls */}
      <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3">
        <span className="text-xs font-medium text-slate-400">Presentation Remote:</span>
        <div className="flex items-center gap-2">
          <button
            disabled={!selectedDevice}
            onClick={() => showFeedback("Previous Slide")}
            className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/5 hover:bg-white/15 text-slate-200"
            title="Previous Slide"
          >
            <ChevronLeft size={16} />
          </button>
          <button
            disabled={!selectedDevice}
            onClick={() => showFeedback("Play / Pause")}
            className="flex h-8 w-8 items-center justify-center rounded-lg bg-neon-cyan/20 text-neon-cyan hover:bg-neon-cyan/30"
            title="Play / Pause"
          >
            <Play size={14} />
          </button>
          <button
            disabled={!selectedDevice}
            onClick={() => showFeedback("Next Slide")}
            className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/5 hover:bg-white/15 text-slate-200"
            title="Next Slide"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      </div>
    </div>
  );
}
