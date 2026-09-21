import { useState } from "react";
import { motion } from "framer-motion";
import { Send, Download, Monitor, Settings as SettingsIcon, History as HistoryIcon, QrCode, Smartphone, Wifi } from "lucide-react";
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
import { WebDropView } from "./features/airdrop/WebDropView";
import { PhoneControlPanel } from "./features/phone/PhoneControlPanel";
import { ScreenMirrorModal } from "./features/mirror/ScreenMirrorModal";
import { QuickShareModal } from "./features/quickshare/QuickShareModal";
import { ShanuConnectModal } from "./features/shanuconnect/ShanuConnectModal";
import { sendFiles, type LocalFileInput } from "./lib/tauri";

import ScrcpyHub from "./features/scrcpy/ScrcpyHub";

type ActiveTab = "send" | "receive" | "mirror" | "shanuconnect" | "devices";

export default function App() {
  if (typeof window !== "undefined" && (window.location.pathname.startsWith("/web") || window.location.pathname.startsWith("/webdrop"))) {
    return <WebDropView />;
  }

  const { devices, scanning, rescan } = useDevices();
  const [selected, setSelected] = useState<Device | null>(null);
  const [files, setFiles] = useState<LocalFileInput[]>([]);
  const [progress, setProgress] = useState<Record<string, FileProgressState>>({});
  const [sending, setSending] = useState(false);
  const [activeTab, setActiveTab] = useState<ActiveTab>("send");

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
    <div className="mx-auto flex h-screen max-w-6xl flex-col gap-4 p-5 bg-slate-950 text-slate-100">
      <IncomingRequestModal />
      <SettingsPanel open={settingsOpen} onClose={() => setSettingsOpen(false)} />
      <HistoryPanel open={historyOpen} onClose={() => setHistoryOpen(false)} />
      <AirDropBridgeModal open={airDropOpen} onClose={() => setAirDropOpen(false)} />
      <QuickShareModal open={quickShareOpen} onClose={() => setQuickShareOpen(false)} />
      <ScreenMirrorModal open={mirrorOpen} onClose={() => setMirrorOpen(false)} selectedDevice={selected} />
      <ShanuConnectModal isOpen={kdeConnectOpen} onClose={() => setKdeConnectOpen(false)} deviceName={selected?.alias || "ShanuConnect Device"} />

      {/* Header Bar */}
      <header className="flex items-center justify-between border-b border-slate-800 pb-3">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-blue-600 text-white font-bold text-base shadow-sm">
            S
          </div>
          <div>
            <h1 className="text-lg font-bold tracking-tight text-white flex items-center gap-2">
              ShanuSend <span className="rounded-md bg-blue-500/10 px-2 py-0.5 text-[10px] font-medium text-blue-400 border border-blue-500/20">v2.5.3</span>
            </h1>
            <p className="text-xs text-slate-400">Cross-Platform LocalSend File Sharing & Device Suite</p>
          </div>
        </div>

        {/* Action Header Tools */}
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAirDropOpen(true)}
            className="localsend-button text-xs"
            title="WebDrop Browser Portal"
          >
            <QrCode size={14} />
            <span>WebDrop</span>
          </button>
          <button
            onClick={() => setQuickShareOpen(true)}
            className="localsend-button text-xs"
            title="Quick Share Engine"
          >
            <span>Quick Share</span>
          </button>
          <button
            onClick={() => setHistoryOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-slate-800 bg-slate-900 text-slate-300 transition hover:bg-slate-800"
            title="History"
          >
            <HistoryIcon size={16} />
          </button>
          <button
            onClick={() => setSettingsOpen(true)}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-slate-800 bg-slate-900 text-slate-300 transition hover:bg-slate-800"
            title="Settings"
          >
            <SettingsIcon size={16} />
          </button>
        </div>
      </header>

      {/* Primary LocalSend-Style Navigation Rail/Tabs */}
      <nav className="flex gap-2 border-b border-slate-800 pb-3 overflow-x-auto">
        <button
          onClick={() => setActiveTab("send")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition whitespace-nowrap ${
            activeTab === "send" ? "bg-blue-600 text-white" : "bg-slate-900 text-slate-400 hover:bg-slate-800 hover:text-white"
          }`}
        >
          <Send size={14} />
          <span>Send</span>
        </button>

        <button
          onClick={() => setActiveTab("receive")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition whitespace-nowrap ${
            activeTab === "receive" ? "bg-blue-600 text-white" : "bg-slate-900 text-slate-400 hover:bg-slate-800 hover:text-white"
          }`}
        >
          <Download size={14} />
          <span>Receive</span>
        </button>

        <button
          onClick={() => setActiveTab("mirror")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition whitespace-nowrap ${
            activeTab === "mirror" ? "bg-blue-600 text-white" : "bg-slate-900 text-slate-400 hover:bg-slate-800 hover:text-white"
          }`}
        >
          <Monitor size={14} />
          <span>Screen Mirroring (Scrcpy)</span>
        </button>

        <button
          onClick={() => setActiveTab("shanuconnect")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition whitespace-nowrap ${
            activeTab === "shanuconnect" ? "bg-blue-600 text-white" : "bg-slate-900 text-slate-400 hover:bg-slate-800 hover:text-white"
          }`}
        >
          <Smartphone size={14} />
          <span>ShanuConnect Suite</span>
        </button>

        <button
          onClick={() => setActiveTab("devices")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition whitespace-nowrap ${
            activeTab === "devices" ? "bg-blue-600 text-white" : "bg-slate-900 text-slate-400 hover:bg-slate-800 hover:text-white"
          }`}
        >
          <Wifi size={14} />
          <span>Nearby Devices ({devices.length})</span>
        </button>
      </nav>

      {/* Target Device Context Banner */}
      {selected && (
        <div className="flex items-center justify-between rounded-xl border border-blue-500/30 bg-blue-500/10 px-4 py-2 text-xs text-blue-400">
          <div className="flex items-center gap-2">
            <span className="flex h-2 w-2 rounded-full bg-blue-400 animate-pulse" />
            <span className="font-semibold">Selected Peer: {selected.alias}</span>
            <span className="text-slate-400">({selected.device_type} &middot; {selected.ip})</span>
          </div>
          <button
            onClick={() => setSelected(null)}
            className="text-slate-400 hover:text-white"
          >
            Deselect
          </button>
        </div>
      )}

      {/* Main View Area */}
      <main className={`grid flex-1 gap-5 overflow-hidden ${activeTab === "send" ? "grid-cols-1 md:grid-cols-[minmax(0,1fr)_340px]" : "grid-cols-1"}`}>
        <div className="flex flex-col gap-4 overflow-y-auto pr-1">
          {activeTab === "send" && (
            <>
              <DropZone files={files} onFilesChange={setFiles} />
              {Object.keys(progress).length > 0 && <TransferProgress files={files} progress={progress} />}

              <motion.button
                whileTap={{ scale: 0.98 }}
                disabled={!canSend}
                onClick={handleSend}
                className={`localsend-button-primary mt-auto py-3 text-sm font-semibold ${
                  canSend ? "opacity-100" : "opacity-50 cursor-not-allowed"
                }`}
              >
                <Send size={16} />
                {selected ? `Send to ${selected.alias}` : "Select a device from Nearby Devices to send"}
              </motion.button>
            </>
          )}

          {activeTab === "receive" && (
            <div className="flex flex-col gap-4">
              <IncomingTransferPanel />
              <div className="rounded-2xl border border-slate-800 bg-slate-900 p-5 text-center text-xs text-slate-400">
                <p className="font-semibold text-slate-200 mb-1">LocalSend Receiver Ready</p>
                <p>Your device is visible over LAN multicast. Incoming file transfer requests will appear here automatically.</p>
              </div>
            </div>
          )}

          {activeTab === "devices" && (
            <div className="flex-1 overflow-hidden">
              <DeviceList
                devices={devices}
                scanning={scanning}
                selected={selected}
                onSelect={setSelected}
                onRescan={rescan}
              />
            </div>
          )}

          {activeTab === "mirror" && (
            <div className="flex-1 overflow-hidden rounded-2xl border border-slate-800 bg-slate-900">
              <ScrcpyHub />
            </div>
          )}

          {activeTab === "shanuconnect" && (
            <div className="flex-1 overflow-hidden">
              <PhoneControlPanel selectedDevice={selected} devices={devices} />
            </div>
          )}
        </div>

        {/* Sidebar Device Discovery list (for Send tab) */}
        {activeTab === "send" && (
          <DeviceList
            devices={devices}
            scanning={scanning}
            selected={selected}
            onSelect={setSelected}
            onRescan={rescan}
          />
        )}
      </main>
    </div>
  );
}
