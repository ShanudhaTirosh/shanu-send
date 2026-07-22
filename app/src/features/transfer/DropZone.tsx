import { useCallback, useState } from "react";
import { motion } from "framer-motion";
import { UploadCloud, File as FileIcon, X } from "lucide-react";
import type { LocalFileInput } from "../../lib/tauri";

interface DropZoneProps {
  files: LocalFileInput[];
  onFilesChange: (files: LocalFileInput[]) => void;
}

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(1)} ${units[unitIndex]}`;
}

export function DropZone({ files, onFilesChange }: DropZoneProps) {
  const [dragOver, setDragOver] = useState(false);

  const addFiles = useCallback(
    (fileList: FileList) => {
      const next: LocalFileInput[] = Array.from(fileList).map((f) => ({
        id: crypto.randomUUID(),
        // In the Tauri build this becomes a real filesystem path via the
        // file drop event payload; in browser-preview mode we only have a
        // File object, so `path` is a placeholder used purely for display.
        path: (f as File & { path?: string }).path ?? f.name,
        file_name: f.name,
        size: f.size,
        mime: f.type || "application/octet-stream",
      }));
      onFilesChange([...files, ...next]);
    },
    [files, onFilesChange],
  );

  return (
    <div className="flex flex-col gap-3">
      <motion.label
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragOver(false);
          if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
        }}
        animate={{
          borderColor: dragOver ? "rgba(77, 217, 255, 0.6)" : "rgba(255,255,255,0.1)",
          scale: dragOver ? 1.01 : 1,
        }}
        className="glass-panel flex cursor-pointer flex-col items-center justify-center gap-2 border-2 border-dashed p-8 text-center"
      >
        <UploadCloud size={28} className={dragOver ? "text-neon-cyan" : "text-slate-400"} />
        <p className="text-sm text-slate-300">Drag files here, or click to browse</p>
        <input
          type="file"
          multiple
          className="hidden"
          onChange={(e) => e.target.files && addFiles(e.target.files)}
        />
      </motion.label>

      {files.length > 0 && (
        <ul className="flex flex-col gap-2">
          {files.map((file) => (
            <li
              key={file.id}
              className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm"
            >
              <FileIcon size={16} className="shrink-0 text-slate-400" />
              <span className="flex-1 truncate">{file.file_name}</span>
              <span className="shrink-0 text-xs text-slate-500">{humanSize(file.size)}</span>
              <button
                onClick={() => onFilesChange(files.filter((f) => f.id !== file.id))}
                className="shrink-0 text-slate-500 transition hover:text-neon-pink"
                aria-label={`Remove ${file.file_name}`}
              >
                <X size={14} />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
