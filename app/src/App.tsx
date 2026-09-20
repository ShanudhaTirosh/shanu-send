import { useState } from "react";
import { motion } from "framer-motion";
import { Send, Zap, Settings as SettingsIcon, History as HistoryIcon, QrCode, Smartphone, Monitor, FolderUp } from "lucide-react";
import type { Device } from "./types";
import { useDevices } from "./features/discovery/useDevices";
import { DeviceList } from "./features/discovery/DeviceList";
import { DropZone } from "./features/transfer/DropZone";
import { TransferProgress, reduceSendEvent, type FileProgressState } from "./features/transfer/TransferProgress";
import { IncomingRequestModal } from "./features/transfer/IncomingRequestModal";
import { IncomingTransferPanel } from "./features/transfer/IncomingTransferPanel";
import { SettingsPanel } from "./features/settings/SettingsPanel";
import { HistoryPanel } from "./features/history/HistoryPanel";
import { AirDropBridgeModal } from "./features/airdrop/AirDropBridgeModal";
import { PhoneControlPanel } from "./features/phone/PhoneControlPanel";
import { ScreenMirrorModal } from "./features/mirror/ScreenMirrorModal";
import { QuickShareModal } from "./features/quickshare/QuickShareModal";
import { ShanuConnectModal } from "./features/shanuconnect/ShanuConnectModal";
import { sendFiles, type LocalFileInput } from "./lib/tauri";

type ActiveTab = "transfer" | "mirror" | "shanuconnect";

export default function App() {
  const { devices, scanning, rescan } = useDevices();
  const [selected, setSelected] = useState<Device | null>(null);
  const [files, setFiles] = useState<LocalFileInput[]>([]);
  const [progress, setProgress] = useState<Record<string, FileProgressState>>({});
  const [sending, setSending] = useState(false);
  const [activeTab, setActiveTab] = useState<ActiveTab>("transfer");

  // Modals
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [airDropOpen, setAirDropOpen] = useState(false);
  const [quickShareOpen, setQuickShareOpen] = useState(false);
  const [mirrorOpen, setMirrorOpen] = useState(false);
  const [kdeConnectOpen, setKdeConnectOpen] = useState(false);

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
    <div className="mx-auto flex h-screen max-w-6xl flex-col gap-5 p-6">
      <IncomingRequestModal />
      <SettingsPanel open={settingsOpen} onClose={() => setSettingsOpen(false)} />
      <HistoryPanel open={historyOpen} onClose={() => setHistoryOpen(false)} />
      <AirDropBridgeModal open={airDropOpen} onClose={() => setAirDropOpen(false)} />
      <QuickShareModal open={quickShareOpen} onClose={() => setQuickShareOpen(false)} />
      <ScreenMirrorModal open={mirrorOpen} onClose={() => setMirrorOpen(false)} selectedDevice={selected} />
      <ShanuConnectModal isOpen={kdeConnectOpen} onClose={() => setKdeConnectOpen(false)} deviceName={selected?.alias || "ShanuConnect Device"} />

      {/* Header Bar */}
      <header className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-gradient-to-br from-neon-cyan to-neon-violet shadow-glow">
            <Zap size={20} className="text-void-950" />
          </div>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-white flex items-center gap-2">
              ShanuSend <span className="rounded-full bg-neon-cyan/10 px-2 py-0.5 text-[10px] font-semibold text-neon-cyan border border-neon-cyan/20">Desktop Pro v2.5</span>
            </h1>
            <p className="text-xs text-slate-400">Universal LAN Sharing, Scrcpy Mirroring & ShanuConnect Suite</p>
          </div>
        </div>

        {/* Action Header Items */}
        <div className="flex items-center gap-2">
          <button
            onClick={() => setActiveTab("shanuconnect")}
            className="flex h-9 items-center gap-1.5 rounded-xl border border-cyan-500/40 bg-cyan-500/10 px-3 text-xs font-semibold text-cyan-300 transition hover:bg-cyan-500/20"
            title="ShanuConnect Suite Workspace"
          >
            <Smartphone size={15} className="text-cyan-400" />
            <span>ShanuConnect Hub</span>
          </button>
          <button
            onClick={() => setQuickShareOpen(true)}
            className="flex h-9 items-center gap-1.5 rounded-xl border border-violet-500/40 bg-violet-500/10 px-3 text-xs font-semibold text-violet-300 transition hover:bg-violet-500/20"
            title="Quick Share Engine"
          >
            <span>Quick Share</span>
          </button>
          <button
            onClick={() => setMirrorOpen(true)}
            className="glass-button text-xs"
            title="Screen Mirroring (Desktop Host)"
          >
            <Monitor size={15} className="text-neon-cyan" />
            <span className="hidden sm:inline">Screen Mirror</span>
          </button>
          <button
            onClick={() => setAirDropOpen(true)}
            className="flex h-9 items-center gap-1.5 rounded-xl border border-cyan-500/40 bg-cyan-500/10 px-3.5 text-xs font-semibold text-cyan-300 transition hover:bg-cyan-500/20"
            title="AirDrop / WebDrop Portal"
          >
            <QrCode size={15} />
            <span>WebDrop Portal</span>
          </button>
          <button
            onClick={() => setHistoryOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10"
            title="History"
          >
            <HistoryIcon size={16} />
          </button>
          <button
            onClick={() => setSettingsOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10"
            title="Settings"
          >
            <SettingsIcon size={16} />
          </button>
        </div>
      </header>

      {/* Target Device Contextual Banner */}
      {selected && (
        <div className="flex items-center justify-between rounded-xl border border-neon-cyan/30 bg-neon-cyan/5 px-4 py-2 text-xs text-neon-cyan animate-fade-in">
          <div className="flex items-center gap-2">
            <span className="flex h-2 w-2 rounded-full bg-neon-cyan animate-ping" />
            <span className="font-semibold">Target Device: {selected.alias}</span>
            <span className="text-slate-400">({selected.device_type} &middot; {selected.ip})</span>
          </div>
          <div className="flex items-center gap-3">
            {selected.device_type === "Mobile" && (
              <button
                onClick={() => setMirrorOpen(true)}
                className="font-semibold text-neon-cyan hover:underline"
              >
                Launch Screen Mirror →
              </button>
            )}
            <button
              onClick={() => setSelected(null)}
              className="text-slate-400 hover:text-white"
            >
              Deselect
            </button>
          </div>
        </div>
      )}

      {/* Primary Navigation Tabs */}
      <div className="flex rounded-2xl border border-white/10 bg-white/5 p-1.5 backdrop-blur-glass">
        <button
          onClick={() => setActiveTab("transfer")}
          className={`flex flex-1 items-center justify-center gap-2 rounded-xl py-2 text-xs font-semibold transition ${
            activeTab === "transfer" ? "bg-white/15 text-white shadow-sm" : "text-slate-400 hover:text-slate-200"
          }`}
        >
          <FolderUp size={15} />
          <span>File Transfer</span>
        </button>
        <button
          onClick={() => setActiveTab("mirror")}
          className={`flex flex-1 items-center justify-center gap-2 rounded-xl py-2 text-xs font-semibold transition ${
            activeTab === "mirror" ? "bg-white/15 text-white shadow-sm" : "text-slate-400 hover:text-slate-200"
          }`}
        >
          <Monitor size={15} />
          <span>Screen Mirroring</span>
        </button>
        <button
          onClick={() => setActiveTab("shanuconnect")}
          className={`flex flex-1 items-center justify-center gap-2 rounded-xl py-2 text-xs font-semibold transition ${
            activeTab === "shanuconnect" ? "bg-white/15 text-white shadow-sm" : "text-slate-400 hover:text-slate-200"
          }`}
        >
          <Smartphone size={15} />
          <span>ShanuConnect Hub</span>
        </button>
      </div>

      {/* Main Grid View */}
      <main className="grid flex-1 grid-cols-1 gap-6 overflow-hidden md:grid-cols-[minmax(0,1fr)_360px]">
        <div className="flex flex-col gap-4 overflow-y-auto pr-1">
          {activeTab === "transfer" && (
            <>
              <DropZone files={files} onFilesChange={setFiles} />
              {Object.keys(progress).length > 0 && <TransferProgress files={files} progress={progress} />}
              <IncomingTransferPanel />

              <motion.button
                whileTap={{ scale: 0.98 }}
                disabled={!canSend}
                onClick={handleSend}
                className={`glass-button-primary mt-auto py-3 text-sm font-semibold ${
                  canSend ? "opacity-100" : "opacity-50 cursor-not-allowed"
                }`}
              >
                <Send size={16} />
                {selected ? `Send to ${selected.alias}` : "Select a device to send"}
              </motion.button>
            </>
          )}

          {activeTab === "mirror" && (
            <div className="flex flex-col gap-4 rounded-2xl border border-white/10 bg-white/5 p-6">
              <div className="flex items-center justify-between border-b border-white/10 pb-4">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-neon-cyan/20 text-neon-cyan">
                    <Monitor size={20} />
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-white">Desktop Screen Mirror Host</h3>
                    <p className="text-xs text-slate-400">Stream connected Android screens using high-performance Scrcpy H.264/H.265 engine</p>
                  </div>
                </div>
                <button
                  onClick={() => setMirrorOpen(true)}
                  className="glass-button-primary text-xs px-4 py-2"
                >
                  Configure & Start Mirror
                </button>
              </div>
              <div className="grid grid-cols-3 gap-3 text-xs text-slate-300">
                <div className="rounded-xl border border-white/10 bg-void-950/60 p-3">
                  <p className="font-semibold text-neon-cyan">Wireless ADB Pairing</p>
                  <p className="mt-1 text-[11px] text-slate-400">Pair Android 11+ over Wi-Fi without USB cables</p>
                </div>
                <div className="rounded-xl border border-white/10 bg-void-950/60 p-3">
                  <p className="font-semibold text-neon-violet">Hardware OTG Mode</p>
                  <p className="mt-1 text-[11px] text-slate-400">Seamless cursor & physical keyboard forwarding</p>
                </div>
                <div className="rounded-xl border border-white/10 bg-void-950/60 p-3">
                  <p className="font-semibold text-emerald-400">Opus Audio Pass-Through</p>
                  <p className="mt-1 text-[11px] text-slate-400">Low-latency internal device audio streaming</p>
                </div>
              </div>
            </div>
          )}

          {activeTab === "shanuconnect" && (
            <PhoneControlPanel selectedDevice={selected} devices={devices} />
          )}
        </div>

        {/* Discovery Device Sidebar */}
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
