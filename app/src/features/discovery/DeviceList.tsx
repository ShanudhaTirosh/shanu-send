import { AnimatePresence } from "framer-motion";
import { RefreshCw, RadioTower } from "lucide-react";
import type { Device } from "../../types";
import { DeviceCard } from "./DeviceCard";

interface DeviceListProps {
  devices: Device[];
  scanning: boolean;
  selected: Device | null;
  onSelect: (device: Device) => void;
  onRescan: () => void;
}

export function DeviceList({ devices, scanning, selected, onSelect, onRescan }: DeviceListProps) {
  return (
    <section className="flex h-full flex-col gap-4">
      <header className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="relative flex h-8 w-8 items-center justify-center">
            {scanning && (
              <span className="absolute inline-flex h-full w-full animate-radar rounded-full bg-neon-cyan/40" />
            )}
            <RadioTower size={18} className="relative text-neon-cyan" />
          </div>
          <h2 className="text-sm font-medium uppercase tracking-wide text-slate-300">
            Nearby devices &middot; {devices.length}
          </h2>
        </div>
        <button
          onClick={onRescan}
          className="flex items-center gap-1.5 rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs text-slate-300 transition hover:bg-white/10"
        >
          <RefreshCw size={13} className={scanning ? "animate-spin" : ""} />
          Rescan
        </button>
      </header>

      <div className="flex flex-1 flex-col gap-3 overflow-y-auto pr-1">
        <AnimatePresence>
          {devices.map((device) => (
            <DeviceCard
              key={device.fingerprint}
              device={device}
              selected={selected?.fingerprint === device.fingerprint}
              onToggle={onSelect}
            />
          ))}
        </AnimatePresence>

        {devices.length === 0 && (
          <div className="glass-panel flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center text-slate-400">
            <RadioTower size={28} className="text-slate-500" />
            <p className="text-sm">
              {scanning ? "Looking for devices on your network…" : "No devices found yet."}
            </p>
            <p className="text-xs text-slate-500">
              Make sure the other device is on the same Wi-Fi/LAN and has ShanuSend or LocalSend open.
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
