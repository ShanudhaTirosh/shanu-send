import { motion } from "framer-motion";
import { Laptop, Smartphone, Globe, Server, ShieldCheck } from "lucide-react";
import type { Device } from "../../types";

const ICONS: Record<Device["device_type"], typeof Laptop> = {
  Mobile: Smartphone,
  Desktop: Laptop,
  Web: Globe,
  Headless: Server,
  Server: Server,
};

interface DeviceCardProps {
  device: Device;
  selected: boolean;
  onToggle: (device: Device) => void;
}

export function DeviceCard({ device, selected, onToggle }: DeviceCardProps) {
  const Icon = ICONS[device.device_type] ?? Laptop;

  return (
    <motion.button
      layout
      initial={{ opacity: 0, y: 12, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, scale: 0.9 }}
      whileHover={{ y: -2 }}
      whileTap={{ scale: 0.98 }}
      onClick={() => onToggle(device)}
      className={`glass-panel relative flex w-full items-center gap-4 p-4 text-left transition-colors ${
        selected ? "border-neon-cyan/60 shadow-glow" : "hover:border-white/20"
      }`}
    >
      <div
        className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${
          selected ? "bg-neon-cyan/20 text-neon-cyan" : "bg-white/10 text-slate-300"
        }`}
      >
        <Icon size={20} />
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <p className="truncate font-medium text-slate-100">{device.alias}</p>
          {device.trusted && (
            <ShieldCheck size={14} className="shrink-0 text-neon-cyan" aria-label="Trusted device" />
          )}
        </div>
        <p className="truncate text-sm text-slate-400">
          {device.device_model ?? device.device_type} &middot; {device.ip}
        </p>
      </div>

      {selected && (
        <motion.div
          layoutId="selected-ring"
          className="pointer-events-none absolute inset-0 rounded-glass ring-1 ring-neon-cyan/50"
        />
      )}
    </motion.button>
  );
}
