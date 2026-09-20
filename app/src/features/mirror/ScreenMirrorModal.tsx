import { useState, useEffect } from "react";
import {
  Monitor,
  Video,
  Play,
  X,
  Sliders,
  Camera,
  Sun,
  Volume2,
  Radio,
  FileDown,
  Sparkles,
  Disc,
  Terminal,
  Zap,
  Download,
  AlertCircle,
} from "lucide-react";
import type { Device } from "../../types";

import {
  scrcpyAdbPair,
  scrcpyAdbConnect,
  scrcpyStartMirror,
  scrcpyAdbSendKeyevent,
  scrcpyAdbShell,
  scrcpyCheckInstalled,
  scrcpyDownloadDependencies,
  onScrcpyDownloadProgress,
  type ScrcpyDownloadProgress,
} from "../../lib/tauri";

interface ScreenMirrorModalProps {
  open: boolean;
  onClose: () => void;
  selectedDevice: Device | null;
}

type TabType = "display" | "audio" | "camera" | "presets" | "adb" | "logs";

export function ScreenMirrorModal({ open, onClose, selectedDevice }: ScreenMirrorModalProps) {
  const [activeTab, setActiveTab] = useState<TabType>("display");
  const [isMirroring, setIsMirroring] = useState(false);
  const [isRecording, setIsRecording] = useState(false);

  // Auto-Installer State
  const [isEngineInstalled, setIsEngineInstalled] = useState<boolean | null>(null);
  const [isDownloadingEngine, setIsDownloadingEngine] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState<ScrcpyDownloadProgress>({
    percent: 0,
    status: "",
  });

  // Video Options
  const [videoCodec, setVideoCodec] = useState("h264");
  const [bitrate, setBitrate] = useState("16");
  const [fps, setFps] = useState("60");
  const [resolution, setResolution] = useState("1080p");

  // Audio Options
  const [audioCodec, setAudioCodec] = useState("opus");
  const [audioSource, setAudioSource] = useState("output");

  // Camera Options
  const [cameraMode, setCameraMode] = useState(false);
  const [cameraFacing, setCameraFacing] = useState("back");
  const [torchEnabled, setTorchEnabled] = useState(false);
  const [zoom, setZoom] = useState("1.0");

  // Control Toggles
  const [stayAwake, setStayAwake] = useState(true);
  const [turnScreenOff, setTurnScreenOff] = useState(false);
  const [showTouches, setShowTouches] = useState(false);
  const [otgMode, setOtgMode] = useState(false);

  // Wireless ADB Pairing
  const [adbIp, setAdbIp] = useState("");
  const [adbPort, setAdbPort] = useState("5555");
  const [pairingCode, setPairingCode] = useState("");
  const [adbStatus, setAdbStatus] = useState<string | null>(null);

  // Terminal & Logs
  const [logs, setLogs] = useState<string[]>([
    "[SYSTEM] Scrcpy Pro Suite Engine initialized.",
    "[SYSTEM] Ready for ADB connection & screen mirroring session.",
  ]);

  const [feedback, setFeedback] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    scrcpyCheckInstalled().then((installed) => {
      setIsEngineInstalled(installed);
    });

    let unlisten: (() => void) | undefined;
    onScrcpyDownloadProgress((payload) => {
      setDownloadProgress(payload);
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      if (unlisten) unlisten();
    };
  }, [open]);

  const handleAutoInstall = async () => {
    setIsDownloadingEngine(true);
    addLog("Initiating automated Scrcpy & ADB Pro Engine download...");
    try {
      const result = await scrcpyDownloadDependencies();
      setIsEngineInstalled(true);
      setIsDownloadingEngine(false);
      showActionFeedback("Scrcpy & ADB Engine Installed Successfully!");
      addLog(`[SUCCESS] ${result}`);
    } catch (err: any) {
      setIsDownloadingEngine(false);
      showActionFeedback(`Install failed: ${err}`);
      addLog(`[ERROR] Auto-installation failed: ${err}`);
    }
  };

  if (!open) return null;

  const showActionFeedback = (msg: string) => {
    setFeedback(msg);
    setTimeout(() => setFeedback(null), 2500);
  };

  const addLog = (msg: string) => {
    setLogs((prev) => [...prev, `[${new Date().toLocaleTimeString()}] ${msg}`]);
  };

  const handlePairAdb = async () => {
    if (!adbIp || !pairingCode) return;
    setAdbStatus("Pairing with Wireless ADB...");
    addLog(`Pairing with Wireless ADB at ${adbIp}:${adbPort}...`);
    try {
      const targetAddr = `${adbIp}:${adbPort}`;
      const pairRes = await scrcpyAdbPair(targetAddr, pairingCode);
      setAdbStatus(`Paired: ${pairRes}. Connecting...`);
      addLog(`Paired successfully: ${pairRes}`);
      const connRes = await scrcpyAdbConnect(targetAddr);
      setAdbStatus(`Connected: ${connRes}`);
      addLog(`ADB Wireless Connection: ${connRes}`);
    } catch (err) {
      setAdbStatus(`ADB Error: ${err}`);
      addLog(`[ERROR] ADB Pairing failed: ${err}`);
    }
  };

  const handleSendKey = async (keycode: number, label: string) => {
    try {
      await scrcpyAdbSendKeyevent(selectedDevice?.ip || undefined, keycode);
      showActionFeedback(`Triggered ${label}`);
      addLog(`ADB Keyevent sent: ${label} (Keycode ${keycode})`);
    } catch (e: any) {
      showActionFeedback(`Keyevent Error: ${e}`);
      addLog(`[ERROR] Keyevent failed: ${e}`);
    }
  };

  const handleTakeScreenshot = async () => {
    try {
      await scrcpyAdbShell(
        selectedDevice?.ip || undefined,
        "screencap -p /sdcard/Download/screenshot.png"
      );
      showActionFeedback("Screenshot saved to phone Downloads!");
      addLog("Captured screenshot to /sdcard/Download/screenshot.png");
    } catch (e: any) {
      showActionFeedback(`Screenshot Error: ${e}`);
      addLog(`[ERROR] Screenshot failed: ${e}`);
    }
  };

  const applyPreset = (presetName: string) => {
    if (presetName === "1080p") {
      setResolution("1080p");
      setBitrate("16");
      setFps("60");
      setVideoCodec("h264");
      setCameraMode(false);
      setOtgMode(false);
    } else if (presetName === "1440p") {
      setResolution("native");
      setBitrate("24");
      setFps("60");
      setVideoCodec("h265");
      setCameraMode(false);
      setOtgMode(false);
    } else if (presetName === "4k") {
      setResolution("native");
      setBitrate("32");
      setFps("60");
      setVideoCodec("h265");
      setCameraMode(false);
      setOtgMode(false);
    } else if (presetName === "gaming") {
      setResolution("720p");
      setBitrate("12");
      setFps("120");
      setVideoCodec("h264");
      setCameraMode(false);
      setOtgMode(false);
    } else if (presetName === "webcam") {
      setCameraMode(true);
      setResolution("1080p");
      setBitrate("16");
      setFps("60");
      setCameraFacing("back");
    } else if (presetName === "otg") {
      setOtgMode(true);
      setCameraMode(false);
    }
    showActionFeedback(`Applied ${presetName.toUpperCase()} Preset`);
    addLog(`Applied Quick Preset: ${presetName.toUpperCase()}`);
  };

  const toggleMirror = async () => {
    if (!isMirroring) {
      try {
        addLog(`Launching scrcpy session... Resolution: ${resolution}, Bitrate: ${bitrate}Mbps, FPS: ${fps}`);
        const res = await scrcpyStartMirror({
          deviceId: selectedDevice?.ip || undefined,
          maxSize: parseInt(resolution) || 1080,
          bitRate: parseInt(bitrate),
          fps: parseInt(fps),
          videoCodec,
          audioCodec,
          cameraMode,
          cameraFacing,
          stayAwake,
          turnScreenOff,
          showTouches,
          otgMode,
          record: isRecording,
        });
        setIsMirroring(true);
        showActionFeedback(res);
        addLog(`Scrcpy process active: ${res}`);
      } catch (e: any) {
        showActionFeedback(`Scrcpy Error: ${e}`);
        addLog(`[ERROR] Scrcpy launch failed: ${e}`);
      }
    } else {
      setIsMirroring(false);
      showActionFeedback("Mirror session ended.");
      addLog("Scrcpy mirror session ended.");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-void-950/85 p-4 backdrop-blur-lg">
      <div className="glass-panel-glow flex h-[90vh] w-full max-w-4xl flex-col overflow-hidden p-6 shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-white/10 pb-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-gradient-to-br from-neon-cyan to-neon-violet shadow-glow">
              <Monitor size={20} className="text-void-950" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-white flex items-center gap-2">
                Scrcpy Pro Suite{" "}
                <span className="rounded-full bg-neon-violet/10 px-2 py-0.5 text-[10px] font-semibold text-neon-violet border border-neon-violet/20">
                  v4 Engine
                </span>
              </h2>
              <p className="text-xs text-slate-400">
                Full Audio & Video Mirroring, Pro Webcam Mode, OTG Peripherals & Wireless ADB
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {feedback && (
              <span className="rounded-full bg-neon-cyan/10 px-3 py-1 text-xs font-semibold text-neon-cyan border border-neon-cyan/20 animate-fade-in">
                {feedback}
              </span>
            )}
            <button
              onClick={onClose}
              className="rounded-xl p-1.5 text-slate-400 hover:bg-white/10 hover:text-white"
            >
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Navigation Tabs */}
        <div className="my-4 flex gap-1.5 rounded-xl border border-white/10 bg-white/5 p-1 backdrop-blur-glass overflow-x-auto">
          <button
            onClick={() => setActiveTab("display")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "display"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Sliders size={14} />
            <span>Video & Graphics</span>
          </button>

          <button
            onClick={() => setActiveTab("audio")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "audio"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Volume2 size={14} />
            <span>Audio Stream</span>
          </button>

          <button
            onClick={() => setActiveTab("camera")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "camera"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Camera size={14} />
            <span>Pro Webcam</span>
          </button>

          <button
            onClick={() => setActiveTab("presets")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "presets"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Zap size={14} />
            <span>Presets</span>
          </button>

          <button
            onClick={() => setActiveTab("adb")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "adb"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Radio size={14} />
            <span>Wireless ADB</span>
          </button>

          <button
            onClick={() => setActiveTab("logs")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 px-3 text-xs font-semibold transition ${
              activeTab === "logs"
                ? "bg-white/15 text-white shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Terminal size={14} />
            <span>Console</span>
          </button>
        </div>

        {/* Main Workspace Body */}
        <div className="grid flex-1 grid-cols-1 gap-6 overflow-hidden md:grid-cols-[1fr_340px]">
          {/* Mirror Canvas & Pro Navigation Dock */}
          <div className="flex flex-col gap-3 overflow-hidden">
            {/* Mirror Stream Display / Auto Install Banner */}
            <div className="relative flex flex-1 items-center justify-center rounded-2xl border border-white/10 bg-void-900/90 overflow-hidden p-6">
              {isEngineInstalled === false && (
                <div className="flex flex-col items-center text-center max-w-md gap-3">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
                    <AlertCircle size={28} />
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-white">Scrcpy & ADB Engine Needed</h3>
                    <p className="text-xs text-slate-400 mt-1 leading-relaxed">
                      To mirror your screen and control your Android device, ShanuSend will automatically download and configure official Scrcpy & ADB binaries directly into your application directory.
                    </p>
                  </div>
                  {isDownloadingEngine ? (
                    <div className="w-full mt-2 flex flex-col gap-2">
                      <div className="flex justify-between text-xs font-semibold text-neon-cyan">
                        <span>{downloadProgress.status || "Downloading..."}</span>
                        <span>{Math.round(downloadProgress.percent)}%</span>
                      </div>
                      <div className="h-2 w-full overflow-hidden rounded-full bg-white/10">
                        <div
                          className="h-full bg-gradient-to-r from-neon-cyan to-neon-violet transition-all duration-300"
                          style={{ width: `${downloadProgress.percent}%` }}
                        />
                      </div>
                    </div>
                  ) : (
                    <button
                      onClick={handleAutoInstall}
                      className="glass-button-primary mt-2 py-2.5 px-5 text-xs font-bold flex items-center gap-2 shadow-glow"
                    >
                      <Download size={16} />
                      <span>Auto Download & Setup Engine (1-Click)</span>
                    </button>
                  )}
                </div>
              )}

              {isEngineInstalled !== false && (
                <>
                  {isMirroring ? (
                    <div className="flex flex-col items-center gap-3 text-neon-cyan animate-pulse">
                      <Video size={48} />
                      <div className="text-center">
                        <p className="text-sm font-bold">Active Mirror Stream &middot; {resolution}</p>
                        <p className="text-xs text-slate-400">
                          {fps} FPS &middot; {bitrate} Mbps &middot; Codec: {videoCodec.toUpperCase()} &middot; Audio: {audioCodec.toUpperCase()}
                        </p>
                      </div>
                      {isRecording && (
                        <span className="flex items-center gap-1.5 rounded-full bg-pink-500/20 px-3 py-1 text-xs font-bold text-pink-400 border border-pink-500/40">
                          <Disc size={12} className="animate-spin" /> RECORDING MP4
                        </span>
                      )}
                    </div>
                  ) : (
                    <div className="text-center p-6">
                      <Monitor className="mx-auto mb-3 text-slate-600" size={40} />
                      <p className="text-sm font-semibold text-slate-300">Screen Mirror Offline</p>
                      <p className="text-xs text-slate-500 mt-1 max-w-xs">
                        Select your preferred codec & resolution settings, then click Start Mirror Session below.
                      </p>
                    </div>
                  )}
                </>
              )}
            </div>

            {/* Hardware On-Screen Navigation Dock */}
            <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-2.5">
              <div className="flex items-center gap-1">
                <button
                  disabled={!isMirroring}
                  onClick={() => handleSendKey(4, "Back button")}
                  className="glass-button text-xs py-1.5 px-3"
                  title="Android Back"
                >
                  Back
                </button>
                <button
                  disabled={!isMirroring}
                  onClick={() => handleSendKey(3, "Home button")}
                  className="glass-button text-xs py-1.5 px-3"
                  title="Android Home"
                >
                  Home
                </button>
                <button
                  disabled={!isMirroring}
                  onClick={() => handleSendKey(187, "App Switcher")}
                  className="glass-button text-xs py-1.5 px-3"
                  title="App Switcher"
                >
                  Recents
                </button>
              </div>

              <div className="flex items-center gap-1">
                <button
                  disabled={!isMirroring}
                  onClick={handleTakeScreenshot}
                  className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/5 hover:bg-white/15 text-slate-300"
                  title="Take Screenshot"
                >
                  <Sparkles size={15} />
                </button>
                <button
                  disabled={!isMirroring}
                  onClick={() => setIsRecording(!isRecording)}
                  className={`flex h-8 w-8 items-center justify-center rounded-lg ${
                    isRecording ? "bg-pink-500/30 text-pink-400" : "bg-white/5 hover:bg-white/15 text-slate-300"
                  }`}
                  title="Toggle Screen Recording"
                >
                  <Disc size={15} />
                </button>
              </div>
            </div>
          </div>

          {/* Configuration Sidebar */}
          <div className="flex flex-col gap-4 overflow-y-auto pr-1">
            {activeTab === "display" && (
              <>
                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Video Codec</label>
                  <select
                    value={videoCodec}
                    onChange={(e) => setVideoCodec(e.target.value)}
                    className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="h264">H.264 / AVC (Default, Maximum compatibility)</option>
                    <option value="h265">H.265 / HEVC (Higher Quality, Low bandwidth)</option>
                    <option value="av1">AV1 (Next-Gen Codec)</option>
                  </select>
                </div>

                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Resolution Scaling</label>
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
                  <label className="text-xs font-semibold text-slate-300">
                    Video Bitrate ({bitrate} Mbps)
                  </label>
                  <input
                    type="range"
                    min="4"
                    max="32"
                    value={bitrate}
                    onChange={(e) => setBitrate(e.target.value)}
                    className="h-1.5 w-full accent-neon-cyan cursor-pointer"
                  />
                  <div className="flex justify-between text-[10px] text-slate-500">
                    <span>4 Mbps (Low)</span>
                    <span>16 Mbps (Balanced)</span>
                    <span>32 Mbps (Ultra)</span>
                  </div>
                </div>

                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Max Frame Rate</label>
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

                <div className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">
                    Display Controls & Hardware OTG
                  </label>
                  <label className="flex items-center justify-between text-xs text-slate-400 cursor-pointer">
                    <span>Stay Awake while Mirroring</span>
                    <input
                      type="checkbox"
                      checked={stayAwake}
                      onChange={(e) => setStayAwake(e.target.checked)}
                    />
                  </label>
                  <label className="flex items-center justify-between text-xs text-slate-400 cursor-pointer">
                    <span>Turn Screen Off while Mirroring</span>
                    <input
                      type="checkbox"
                      checked={turnScreenOff}
                      onChange={(e) => setTurnScreenOff(e.target.checked)}
                    />
                  </label>
                  <label className="flex items-center justify-between text-xs text-slate-400 cursor-pointer">
                    <span>Show Visual Touch Feedback</span>
                    <input
                      type="checkbox"
                      checked={showTouches}
                      onChange={(e) => setShowTouches(e.target.checked)}
                    />
                  </label>
                  <label className="flex items-center justify-between text-xs text-slate-400 cursor-pointer">
                    <span>OTG Hardware Mouse & Keyboard</span>
                    <input
                      type="checkbox"
                      checked={otgMode}
                      onChange={(e) => setOtgMode(e.target.checked)}
                    />
                  </label>
                </div>
              </>
            )}

            {activeTab === "audio" && (
              <>
                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">
                    Audio Codec (Android 11+)
                  </label>
                  <select
                    value={audioCodec}
                    onChange={(e) => setAudioCodec(e.target.value)}
                    className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="opus">Opus (High Fidelity, Low latency)</option>
                    <option value="aac">AAC (Broad Compatibility)</option>
                    <option value="flac">FLAC (Lossless Quality)</option>
                    <option value="raw">RAW PCM (Uncompressed Stream)</option>
                    <option value="disabled">Disabled (Mute Audio)</option>
                  </select>
                </div>

                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Audio Source</label>
                  <select
                    value={audioSource}
                    onChange={(e) => setAudioSource(e.target.value)}
                    className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="output">Device Internal Audio Output</option>
                    <option value="mic">Device Microphone</option>
                  </select>
                </div>
              </>
            )}

            {activeTab === "camera" && (
              <>
                <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3">
                  <span className="text-xs font-semibold text-slate-200">Enable Pro Webcam Mode</span>
                  <input
                    type="checkbox"
                    checked={cameraMode}
                    onChange={(e) => setCameraMode(e.target.checked)}
                  />
                </div>

                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Camera Lens Facing</label>
                  <select
                    value={cameraFacing}
                    onChange={(e) => setCameraFacing(e.target.value)}
                    className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="back">Rear Main Camera (High Res)</option>
                    <option value="front">Front Selfie Camera</option>
                  </select>
                </div>

                <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3">
                  <span className="text-xs font-semibold text-slate-200">Torch / Flashlight</span>
                  <button
                    onClick={() => setTorchEnabled(!torchEnabled)}
                    className={`glass-button text-xs py-1 px-3 ${
                      torchEnabled ? "border-amber-500/50 bg-amber-500/20 text-amber-300" : ""
                    }`}
                  >
                    <Sun size={14} />
                    <span>{torchEnabled ? "Flash ON" : "Flash OFF"}</span>
                  </button>
                </div>

                <div className="flex flex-col gap-1.5 rounded-xl border border-white/10 bg-white/5 p-3">
                  <label className="text-xs font-semibold text-slate-300">Zoom Scale ({zoom}x)</label>
                  <input
                    type="range"
                    min="1.0"
                    max="5.0"
                    step="0.1"
                    value={zoom}
                    onChange={(e) => setZoom(e.target.value)}
                    className="h-1.5 w-full accent-neon-cyan cursor-pointer"
                  />
                </div>
              </>
            )}

            {activeTab === "presets" && (
              <div className="flex flex-col gap-2.5">
                <span className="text-xs font-semibold text-slate-200">Quick Configuration Presets</span>
                <button
                  onClick={() => applyPreset("1080p")}
                  className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3 hover:border-neon-cyan/40 transition text-left"
                >
                  <div>
                    <p className="text-xs font-bold text-white">1080p Balanced</p>
                    <p className="text-[11px] text-slate-400">1080p &middot; 16Mbps &middot; 60 FPS &middot; H.264</p>
                  </div>
                  <Zap size={16} className="text-neon-cyan" />
                </button>

                <button
                  onClick={() => applyPreset("1440p")}
                  className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3 hover:border-neon-cyan/40 transition text-left"
                >
                  <div>
                    <p className="text-xs font-bold text-white">1440p High Quality</p>
                    <p className="text-[11px] text-slate-400">Native &middot; 24Mbps &middot; 60 FPS &middot; H.265</p>
                  </div>
                  <Zap size={16} className="text-neon-violet" />
                </button>

                <button
                  onClick={() => applyPreset("gaming")}
                  className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3 hover:border-neon-cyan/40 transition text-left"
                >
                  <div>
                    <p className="text-xs font-bold text-white">120 FPS High Refresh Gaming</p>
                    <p className="text-[11px] text-slate-400">720p &middot; 12Mbps &middot; 120 FPS &middot; Low Latency</p>
                  </div>
                  <Zap size={16} className="text-amber-400" />
                </button>

                <button
                  onClick={() => applyPreset("webcam")}
                  className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3 hover:border-neon-cyan/40 transition text-left"
                >
                  <div>
                    <p className="text-xs font-bold text-white">Pro Webcam Feed</p>
                    <p className="text-[11px] text-slate-400">Rear Camera &middot; 1080p &middot; OBS Ready</p>
                  </div>
                  <Camera size={16} className="text-emerald-400" />
                </button>
              </div>
            )}

            {activeTab === "adb" && (
              <>
                <div className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3">
                  <span className="text-xs font-semibold text-slate-200">
                    Android 11+ Wireless ADB Pairing
                  </span>
                  <input
                    type="text"
                    value={adbIp}
                    onChange={(e) => setAdbIp(e.target.value)}
                    placeholder="Device IP (e.g. 192.168.1.50)"
                    className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 placeholder-slate-500 focus:outline-none"
                  />
                  <div className="grid grid-cols-2 gap-2">
                    <input
                      type="text"
                      value={adbPort}
                      onChange={(e) => setAdbPort(e.target.value)}
                      placeholder="Port (5555)"
                      className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                    />
                    <input
                      type="text"
                      value={pairingCode}
                      onChange={(e) => setPairingCode(e.target.value)}
                      placeholder="6-digit Pairing Code"
                      className="rounded-lg border border-white/10 bg-void-950 p-2 text-xs text-slate-200 focus:outline-none"
                    />
                  </div>
                  <button onClick={handlePairAdb} className="glass-button-primary py-2 text-xs mt-1">
                    Pair & Connect ADB
                  </button>
                  {adbStatus && <p className="text-xs font-medium text-neon-cyan mt-1">{adbStatus}</p>}
                </div>

                {/* Drag and drop APK pusher */}
                <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-white/20 bg-white/5 p-5 text-center cursor-pointer hover:border-neon-cyan/50">
                  <FileDown size={24} className="text-neon-cyan mb-2" />
                  <p className="text-xs font-semibold text-slate-200">Drag & Drop APK Files</p>
                  <p className="text-[11px] text-slate-500">Auto-install on connected Android device</p>
                </div>
              </>
            )}

            {activeTab === "logs" && (
              <div className="flex flex-col gap-2 h-full">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-slate-200">Live Scrcpy Terminal Output</span>
                  <button
                    onClick={() => setLogs([])}
                    className="text-[11px] text-slate-400 hover:text-white"
                  >
                    Clear Log
                  </button>
                </div>
                <div className="flex-1 rounded-xl border border-white/10 bg-void-950 p-3 font-mono text-[11px] text-neon-cyan/90 overflow-y-auto max-h-[300px]">
                  {logs.map((log, idx) => (
                    <p key={idx} className="leading-relaxed">
                      {log}
                    </p>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-between border-t border-white/10 pt-4 mt-4">
          <div className="flex items-center gap-2">
            <span className="flex h-2 w-2 rounded-full bg-emerald-400"></span>
            <span className="text-xs text-slate-400">
              Target: {selectedDevice ? selectedDevice.alias : "Default ADB Target"}
            </span>
          </div>
          <div className="flex gap-2">
            <button
              onClick={toggleMirror}
              className={`glass-button-primary text-xs ${
                isMirroring
                  ? "from-pink-500/30 to-purple-600/30 border-pink-500/50 text-pink-300"
                  : ""
              }`}
            >
              <Play size={14} />
              <span>{isMirroring ? "Stop Mirroring" : "Start Mirror Session"}</span>
            </button>
            <button onClick={onClose} className="glass-button text-xs">
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
