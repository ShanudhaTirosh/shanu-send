import { useEffect, useRef, useState } from "react";
import { onIncomingProgress, onIncomingRequest, type IncomingTransferState } from "../../lib/tauri";

export interface IncomingFileState extends IncomingTransferState {
  fileName: string;
}

/**
 * Merges two event streams into one view model:
 *  - `onIncomingRequest` tells us *what* was accepted (file names/sizes),
 *    the moment the user taps Accept.
 *  - `onIncomingProgress` tells us *how much* has arrived so far, keyed only
 *    by sessionId+fileId (the Rust side doesn't re-send the file name on
 *    every progress tick — no reason to).
 * This hook stitches them together by key so the UI can show a normal
 * "filename.jpg — 40%" row instead of two disconnected data sources.
 */
export function useIncomingTransfers() {
  const [transfers, setTransfers] = useState<Record<string, IncomingFileState>>({});
  const fileNames = useRef<Record<string, string>>({});

  useEffect(() => {
    let stopRequest: (() => void) | undefined;
    let stopProgress: (() => void) | undefined;

    onIncomingRequest((payload, respond) => {
      // Only capture names for files that end up accepted; we don't know
      // acceptance yet at this point, so record all offered files — a
      // rejected file simply never gets a progress event, so it stays inert.
      for (const f of payload.files) {
        fileNames.current[`${payload.sessionId}:${f.id}`] = f.fileName;
      }
      // Let any other listener (e.g. the modal itself) still handle respond.
      void respond;
    }).then((unsub) => {
      stopRequest = unsub;
    });

    onIncomingProgress((update) => {
      const key = `${update.sessionId}:${update.fileId}`;
      setTransfers((prev) => ({
        ...prev,
        [key]: { ...update, fileName: fileNames.current[key] ?? "Incoming file" },
      }));
    }).then((unsub) => {
      stopProgress = unsub;
    });

    return () => {
      stopRequest?.();
      stopProgress?.();
    };
  }, []);

  return Object.values(transfers);
}
