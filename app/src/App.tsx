import { useState } from "react";
import { motion } from "framer-motion";
import { Send, Zap, Settings as SettingsIcon, History as HistoryIcon } from "lucide-react";
import type { Device } from "./types";
import { useDevices } from "./features/discovery/useDevices";
import { DeviceList } from "./features/discovery/DeviceList";
import { DropZone } from "./features/transfer/DropZone";
import { TransferProgress, reduceSendEvent, type FileProgressState } from "./features/transfer/TransferProgress";
import { IncomingRequestModal } from "./features/transfer/IncomingRequestModal";
import { IncomingTransferPanel } from "./features/transfer/IncomingTransferPanel";
import { SettingsPanel } from "./features/settings/SettingsPanel";
import { HistoryPanel } from "./features/history/HistoryPanel";
import { sendFiles, type LocalFileInput } from "./lib/tauri";

export default function App() {
  const { devices, scanning, rescan } = useDevices();
  const [selected, setSelected] = useState<Device | null>(null);
  const [files, setFiles] = useState<LocalFileInput[]>([]);
  const [progress, setProgress] = useState<Record<string, FileProgressState>>({});
  const [sending, setSending] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);

  const handleSend = async () => {
    if (!selected || files.length === 0) return;
    setSending(true);
    setProgress({});
    await sendFiles(selected, files, (event) => {
      setProgress((prev) => reduceSendEvent(prev, event));
      if (event.type === "AllDone") setSending(false);
    });
  };

  const canSend = selected !== null && files.length > 0 && !sending;

  return (
    <div className="mx-auto flex h-screen max-w-5xl flex-col gap-6 p-6">
      <IncomingRequestModal />
      <SettingsPanel open={settingsOpen} onClose={() => setSettingsOpen(false)} />
      <HistoryPanel open={historyOpen} onClose={() => setHistoryOpen(false)} />

      <header className="flex items-center justify-between gap-2.5">
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-neon-cyan to-neon-violet">
            <Zap size={18} className="text-void-950" />
          </div>
          <div>
            <h1 className="text-lg font-semibold leading-tight">ShanuSend</h1>
            <p className="text-xs text-slate-500">LocalSend-compatible &middot; ShanuTechX</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setHistoryOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10"
            aria-label="History"
          >
            <HistoryIcon size={16} />
          </button>
          <button
            onClick={() => setSettingsOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10"
            aria-label="Settings"
          >
            <SettingsIcon size={16} />
          </button>
        </div>
      </header>

      <main className="grid flex-1 grid-cols-1 gap-6 overflow-hidden md:grid-cols-[minmax(0,1fr)_360px]">
        <div className="flex flex-col gap-4 overflow-hidden">
          <DropZone files={files} onFilesChange={setFiles} />
          {Object.keys(progress).length > 0 && <TransferProgress files={files} progress={progress} />}
          <IncomingTransferPanel />

          <motion.button
            whileTap={{ scale: 0.98 }}
            disabled={!canSend}
            onClick={handleSend}
            className={`glass-panel mt-auto flex items-center justify-center gap-2 py-3 text-sm font-medium transition ${
              canSend
                ? "bg-gradient-to-r from-neon-cyan/20 to-neon-violet/20 text-slate-50 hover:shadow-glow"
                : "cursor-not-allowed text-slate-500"
            }`}
          >
            <Send size={16} />
            {selected ? `Send to ${selected.alias}` : "Select a device to send"}
          </motion.button>
        </div>

        <DeviceList
          devices={devices}
          scanning={scanning}
          selected={selected}
          onSelect={setSelected}
          onRescan={rescan}
        />
      </main>
    </div>
  );
}
