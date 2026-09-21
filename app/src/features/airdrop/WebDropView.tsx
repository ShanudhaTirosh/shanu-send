import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Zap, UploadCloud, Download, CheckCircle2, AlertCircle, RefreshCw } from "lucide-react";
import { webdropGetSharedFiles, type WebDropSharedFile } from "../../lib/tauri";

export function WebDropView() {
  const [activeTab, setActiveTab] = useState<"send" | "receive" | "text">("send");
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [uploadProgress, setUploadProgress] = useState<number>(0);
  const [uploading, setUploading] = useState<boolean>(false);
  const [statusMessage, setStatusMessage] = useState<{ text: string; isError?: boolean } | null>(null);

  const [sharedFiles, setSharedFiles] = useState<WebDropSharedFile[]>([]);
  const [loadingShared, setLoadingShared] = useState<boolean>(false);

  const [noteText, setNoteText] = useState<string>("");
  const [sendingText, setSendingText] = useState<boolean>(false);

  useEffect(() => {
    if (activeTab === "receive") {
      fetchShared();
    }
  }, [activeTab]);

  const fetchShared = async () => {
    setLoadingShared(true);
    try {
      // 1. Try Tauri invoke first
      const files = await webdropGetSharedFiles();
      if (files && files.length > 0) {
        setSharedFiles(files);
        setLoadingShared(false);
        return;
      }
    } catch (_) {}

    try {
      // 2. Fallback to fetch HTTP endpoint
      const res = await fetch("/api/webdrop/files");
      if (res.ok) {
        const data = await res.json();
        setSharedFiles(data);
      }
    } catch (_) {
      setSharedFiles([]);
    } finally {
      setLoadingShared(false);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setSelectedFiles(Array.from(e.target.files));
      setStatusMessage(null);
    }
  };

  const handleUpload = () => {
    if (selectedFiles.length === 0) return;
    setUploading(true);
    setUploadProgress(0);
    setStatusMessage(null);

    const formData = new FormData();
    for (const f of selectedFiles) {
      formData.append("files", f);
    }

    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/webdrop/upload");

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        setUploadProgress(pct);
      }
    };

    xhr.onload = () => {
      setUploading(false);
      if (xhr.status === 200) {
        setStatusMessage({ text: "Files transferred successfully to host device!" });
        setSelectedFiles([]);
        setUploadProgress(100);
      } else {
        setStatusMessage({ text: "Upload failed. Make sure host device is running.", isError: true });
      }
    };

    xhr.onerror = () => {
      setUploading(false);
      setStatusMessage({ text: "Network error. Unable to connect to host.", isError: true });
    };

    xhr.send(formData);
  };

  const handleSendText = async () => {
    if (!noteText.trim()) return;
    setSendingText(true);
    setStatusMessage(null);
    try {
      const res = await fetch("/api/webdrop/text", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: noteText }),
      });
      if (res.ok) {
        setStatusMessage({ text: "Text note sent to host device!" });
        setNoteText("");
      } else {
        setStatusMessage({ text: "Failed to send text note.", isError: true });
      }
    } catch (_) {
      setStatusMessage({ text: "Network error sending text.", isError: true });
    } finally {
      setSendingText(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0, y: 15 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full max-w-md rounded-3xl border border-white/10 bg-slate-900/90 p-6 shadow-2xl backdrop-blur-xl"
      >
        <div className="flex items-center justify-center gap-2 mb-1">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-cyan-400 to-indigo-600 text-slate-950 shadow-glow">
            <Zap size={20} className="fill-current" />
          </div>
          <h1 className="text-xl font-bold bg-gradient-to-r from-cyan-400 to-indigo-400 bg-clip-text text-transparent">
            ShanuSend WebDrop
          </h1>
        </div>
        <p className="text-center text-xs text-slate-400 mb-6">
          AirDrop & Nearby Share Web Portal. Instant transfers across iOS, Android & PC.
        </p>

        {/* Tabs */}
        <div className="flex rounded-2xl bg-slate-950/80 p-1 border border-white/5 mb-6">
          <button
            onClick={() => setActiveTab("send")}
            className={`flex-1 rounded-xl py-2 text-xs font-semibold transition ${
              activeTab === "send"
                ? "bg-indigo-600 text-white shadow-lg"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            Send File
          </button>
          <button
            onClick={() => setActiveTab("receive")}
            className={`flex-1 rounded-xl py-2 text-xs font-semibold transition ${
              activeTab === "receive"
                ? "bg-indigo-600 text-white shadow-lg"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            Receive Shared
          </button>
          <button
            onClick={() => setActiveTab("text")}
            className={`flex-1 rounded-xl py-2 text-xs font-semibold transition ${
              activeTab === "text"
                ? "bg-indigo-600 text-white shadow-lg"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            Text Note
          </button>
        </div>

        {/* Tab 1: Send File */}
        {activeTab === "send" && (
          <div className="space-y-4">
            <label className="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-slate-700 bg-slate-950/50 p-8 cursor-pointer hover:border-indigo-500 hover:bg-indigo-950/20 transition group">
              <UploadCloud size={40} className="text-cyan-400 group-hover:scale-110 transition duration-200" />
              <span className="mt-3 text-sm font-semibold text-slate-200">
                {selectedFiles.length > 0
                  ? `${selectedFiles.length} file(s) selected`
                  : "Tap or Drag files here to send"}
              </span>
              <span className="text-xs text-slate-500 mt-1">Supports any file type or size</span>
              <input type="file" multiple className="hidden" onChange={handleFileChange} />
            </label>

            <button
              onClick={handleUpload}
              disabled={selectedFiles.length === 0 || uploading}
              className="w-full rounded-xl bg-gradient-to-r from-indigo-600 to-cyan-600 py-3 text-sm font-bold text-white shadow-lg transition disabled:opacity-40 hover:brightness-110"
            >
              {uploading ? `Uploading... (${uploadProgress}%)` : "Send Files to Host Device"}
            </button>

            {uploading && (
              <div className="h-2 w-full overflow-hidden rounded-full bg-slate-800">
                <div
                  className="h-full bg-gradient-to-r from-cyan-400 to-indigo-500 transition-all duration-150"
                  style={{ width: `${uploadProgress}%` }}
                />
              </div>
            )}
          </div>
        )}

        {/* Tab 2: Receive Shared */}
        {activeTab === "receive" && (
          <div className="space-y-3">
            <div className="flex items-center justify-between text-xs text-slate-400 px-1">
              <span>Files shared by host device:</span>
              <button
                onClick={fetchShared}
                className="flex items-center gap-1 text-cyan-400 hover:text-cyan-300"
              >
                <RefreshCw size={12} className={loadingShared ? "animate-spin" : ""} /> Refresh
              </button>
            </div>

            <div className="max-h-60 overflow-y-auto space-y-2 pr-1">
              {sharedFiles.length === 0 ? (
                <div className="rounded-2xl border border-white/5 bg-slate-950/40 p-6 text-center text-xs text-slate-500">
                  No files shared yet by host device.
                </div>
              ) : (
                sharedFiles.map((f) => (
                  <div
                    key={f.id || f.name}
                    className="flex items-center justify-between rounded-xl border border-white/10 bg-slate-950/60 p-3 text-xs"
                  >
                    <div className="overflow-hidden pr-2">
                      <p className="font-semibold text-slate-200 truncate">{f.name}</p>
                      <p className="text-[11px] text-slate-500 font-mono">
                        {(f.size / (1024 * 1024)).toFixed(1)} MB
                      </p>
                    </div>
                    <a
                      href={`/api/webdrop/download/${encodeURIComponent(f.name)}`}
                      download
                      className="flex shrink-0 items-center gap-1 rounded-lg border border-cyan-500/30 bg-cyan-500/20 px-3 py-1.5 font-semibold text-cyan-300 transition hover:bg-cyan-500/40"
                    >
                      <Download size={14} /> Download
                    </a>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {/* Tab 3: Text Note */}
        {activeTab === "text" && (
          <div className="space-y-3">
            <textarea
              value={noteText}
              onChange={(e) => setNoteText(e.target.value)}
              placeholder="Paste link, text, or note to send to host device..."
              className="w-full h-32 rounded-xl border border-white/10 bg-slate-950/60 p-3 text-xs text-slate-200 placeholder-slate-500 focus:border-cyan-400 focus:outline-none resize-none"
            />
            <button
              onClick={handleSendText}
              disabled={!noteText.trim() || sendingText}
              className="w-full rounded-xl bg-gradient-to-r from-indigo-600 to-cyan-600 py-3 text-sm font-bold text-white shadow-lg transition disabled:opacity-40 hover:brightness-110"
            >
              {sendingText ? "Sending..." : "Send Text Snippet"}
            </button>
          </div>
        )}

        {/* Status Message */}
        {statusMessage && (
          <motion.div
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            className={`mt-4 flex items-center gap-2 rounded-xl p-3 text-xs font-semibold ${
              statusMessage.isError
                ? "border border-rose-500/30 bg-rose-500/10 text-rose-300"
                : "border border-emerald-500/30 bg-emerald-500/10 text-emerald-300"
            }`}
          >
            {statusMessage.isError ? (
              <AlertCircle size={16} className="shrink-0" />
            ) : (
              <CheckCircle2 size={16} className="shrink-0" />
            )}
            <span>{statusMessage.text}</span>
          </motion.div>
        )}
      </motion.div>
    </div>
  );
}
