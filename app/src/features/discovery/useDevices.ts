import { useCallback, useEffect, useRef, useState } from "react";
import type { Device } from "../../types";
import { refreshDiscovery, startDiscovery } from "../../lib/tauri";

export function useDevices() {
  const [devices, setDevices] = useState<Device[]>([]);
  const [scanning, setScanning] = useState(true);
  const stopRef = useRef<(() => void) | null>(null);

  const upsert = useCallback((device: Device) => {
    setDevices((prev) => {
      const existing = prev.findIndex((d) => d.fingerprint === device.fingerprint);
      if (existing === -1) return [...prev, device];
      const next = [...prev];
      next[existing] = { ...next[existing], ...device };
      return next;
    });
  }, []);

  useEffect(() => {
    let mounted = true;
    startDiscovery((device) => {
      if (mounted) upsert(device);
    }).then((stop) => {
      stopRef.current = stop;
    });

    return () => {
      mounted = false;
      stopRef.current?.();
    };
  }, [upsert]);

  const rescan = useCallback(async () => {
    setScanning(true);
    setDevices([]);
    await refreshDiscovery();
    // Discovery is push-based (multicast replies arrive async); give the
    // radar a moment to feel "active" before settling back to idle.
    window.setTimeout(() => setScanning(false), 1500);
  }, []);

  useEffect(() => {
    const t = window.setTimeout(() => setScanning(false), 1500);
    return () => window.clearTimeout(t);
  }, []);

  return { devices, scanning, rescan };
}
