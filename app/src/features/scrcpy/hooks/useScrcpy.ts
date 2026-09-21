import { useState, useEffect, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useLanguage } from '../i18n';

export interface RenderDriverOption {
  id: string;
  label: string;
}

export interface RenderDriverSupport {
  hostOs: string;
  supportsRenderDriver: boolean;
  supportedDrivers: RenderDriverOption[];
}

export interface MdnsDevice {
  name: string;
  service: string;
  address: string;
}

export function isMdnsDeviceConnected(dev: MdnsDevice, devices: string[]): boolean {
  return devices.includes(dev.address) || devices.some(d => d.includes(dev.name));
}

export interface ScrcpyConfig {
  device: string;
  sessionMode: string;
  bitrate?: number;
  fps?: number;
  stayAwake?: boolean;
  turnOff?: boolean;
  audioEnabled?: boolean;
  audioCodec?: string;
  alwaysOnTop?: boolean;
  fullscreen?: boolean;
  borderless?: boolean;
  record?: boolean;
  recordPath?: string;
  scrcpyPath?: string;
  otgPure?: boolean;
  cameraFacing?: string;
  cameraId?: string;
  codec?: string;
  cameraAr?: string;
  cameraHighSpeed?: boolean;
  vdWidth?: number;
  vdHeight?: number;
  vdDpi?: number;
  rotation?: string;
  res?: string;
  aspectRatioLock?: boolean;
  hidKeyboard?: boolean;
  hidMouse?: boolean;
  renderDriver?: string;
  // v4 features
  flexDisplay?: boolean;
  cameraTorch?: boolean;
  cameraZoom?: number;
  backgroundColor?: string;
  keepActive?: boolean;
  vsync?: boolean;
  rememberWindowPosition?: boolean;
  ignoreVideoEncoderConstraints?: boolean;
  windowX?: number;
  windowY?: number;
}

type WindowPositions = Record<string, { x: number; y: number }>;

export function useScrcpy() {
  const { t } = useLanguage();
  const [devices, setDevices] = useState<string[]>([]);
  const [deviceModels, setDeviceModels] = useState<Record<string, string>>({});
  const [deviceFriendlyNames, setDeviceFriendlyNames] = useState<Record<string, string>>({});
  const [logs, setLogs] = useState<string[]>([]);
  const [activeDevice, setActiveDevice] = useState<string>('');
  const [status, setStatus] = useState<string>('');
  const [downloadProgress, setDownloadProgress] = useState<number>(0);
  const [isDownloading, setIsDownloading] = useState(false);
  const [scrcpyStatus, setScrcpyStatus] = useState<{ found: boolean; message: string }>({
    found: false,
    message: t('common.loading'),
  });
  const [isInitialized, setIsInitialized] = useState(false);
  const [runningDevices, setRunningDevices] = useState<string[]>([]);
  const [defaultRecordPath, setDefaultRecordPath] = useState<string>('');
  const [detectedCameras, setDetectedCameras] = useState<{ id: string; name: string }[]>([]);
  const [renderDriverSupport, setRenderDriverSupport] = useState<RenderDriverSupport>({
    hostOs: 'unknown',
    supportsRenderDriver: false,
    supportedDrivers: [],
  });
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isOnboardingOpen, setIsOnboardingOpen] = useState(false);
  const [mdnsDevices, setMdnsDevices] = useState<MdnsDevice[]>([]);
  const [theme, setTheme] = useState('ultraviolet');
  const [colorMode, setColorModeState] = useState<'light' | 'dark' | 'system'>(() => {
    try {
      return (localStorage.getItem('scrcpy_color_mode') as 'light' | 'dark' | 'system') || 'system';
    } catch {
      return 'system';
    }
  });

  const [config, setConfig] = useState<ScrcpyConfig>({
    device: '',
    sessionMode: 'mirror',
    bitrate: 8,
    fps: undefined,
    stayAwake: false,
    turnOff: false,
    audioEnabled: true,
    audioCodec: 'auto',
    alwaysOnTop: false,
    res: '0',
    recordPath: '',
    vdWidth: 1920,
    vdHeight: 1080,
    vdDpi: 420,
    aspectRatioLock: true,
    hidKeyboard: false,
    hidMouse: false,
    flexDisplay: false,
    cameraTorch: false,
    cameraZoom: 1.0,
    backgroundColor: '',
    keepActive: false,
    vsync: true,
    rememberWindowPosition: true,
    ignoreVideoEncoderConstraints: false,
  });

  const [windowPositions, setWindowPositions] = useState<WindowPositions>({});
  const prevDevicesRef = useRef<string[]>([]);
  const mdnsDevicesRef = useRef<MdnsDevice[]>([]);
  const rememberWindowPositionRef = useRef(true);
  const fetchedFriendlyNamesRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    const savedTheme = localStorage.getItem('scrcpy_theme');
    if (savedTheme) {
      setTheme(savedTheme);
    }

    const savedWindowPositions = localStorage.getItem('scrcpy_window_positions');
    if (savedWindowPositions) {
      try {
        setWindowPositions(JSON.parse(savedWindowPositions));
      } catch (e) {
        console.error('Failed to parse saved window positions', e);
      }
    }

    const savedConfig = localStorage.getItem('scrcpy_config');
    if (savedConfig) {
      try {
        const parsed = JSON.parse(savedConfig);
        setConfig(prev => ({ ...prev, ...parsed }));
        if (parsed.scrcpyPath) {
          checkScrcpy(parsed.scrcpyPath);
        }
      } catch (e) {
        console.error('Failed to parse saved config', e);
      }
    }

    const initPaths = async () => {
      try {
        const defaultDir: string = await invoke('get_videos_dir');
        setDefaultRecordPath(defaultDir);

        setConfig(prev => {
          if (!prev.recordPath) {
            return { ...prev, recordPath: defaultDir };
          }
          return prev;
        });

        return defaultDir;
      } catch (e) {
        console.error('Failed to fetch videos dir', e);
        return '';
      }
    };

    const initStart = async () => {
      await initPaths();
      setIsInitialized(true);
    };

    initStart();
  }, []);

  useEffect(() => {
    if (!isInitialized) return;
    localStorage.setItem('scrcpy_config', JSON.stringify(config));
  }, [config, isInitialized]);

  useEffect(() => {
    rememberWindowPositionRef.current = config.rememberWindowPosition !== false;
  }, [config.rememberWindowPosition]);

  useEffect(() => {
    if (!isInitialized) return;
    localStorage.setItem('scrcpy_window_positions', JSON.stringify(windowPositions));
  }, [windowPositions, isInitialized]);

  useEffect(() => {
    if (!isInitialized) return;
    localStorage.setItem('scrcpy_theme', theme);
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme, isInitialized]);

  useEffect(() => {
    const applyMode = (dark: boolean) => {
      document.documentElement.setAttribute('data-mode', dark ? 'dark' : 'light');
    };
    if (colorMode === 'system') {
      const mq = window.matchMedia('(prefers-color-scheme: dark)');
      applyMode(mq.matches);
      const handler = (e: MediaQueryListEvent) => applyMode(e.matches);
      mq.addEventListener('change', handler);
      return () => mq.removeEventListener('change', handler);
    } else {
      applyMode(colorMode === 'dark');
    }
  }, [colorMode]);

  const setColorMode = (mode: 'light' | 'dark' | 'system') => {
    setColorModeState(mode);
    localStorage.setItem('scrcpy_color_mode', mode);
  };

  useEffect(() => {
    setDetectedCameras([]);
  }, [activeDevice]);

  useEffect(() => {
    const unlistenLog = listen<string>('scrcpy-log', event => {
      const newLines = event.payload.split('\n');
      setLogs(prev => [...prev.slice(-(100 - newLines.length)), ...newLines]);
    });

    const unlistenStatus = listen<any>('scrcpy-status', event => {
      const data = event.payload;
      if (data.device && typeof data.running === 'boolean') {
        setRunningDevices(prev => {
          if (data.running) {
            return [...new Set([...prev, data.device])];
          } else {
            return prev.filter(d => d !== data.device);
          }
        });
      } else if (data.type === 'downloading') {
        setIsDownloading(true);
        setStatus(data.message);
      } else if (data.type === 'download-progress') {
        setDownloadProgress(data.percent);
      } else if (data.type === 'download-complete') {
        setIsDownloading(false);
        setStatus(t('logs.downloadComplete'));
        refreshDevicesUntilSettled(data.message);
        checkScrcpy();
      }
    });

    const unlistenWindowPos = listen<{ device: string; x: number; y: number }>(
      'scrcpy-window-pos',
      event => {
        if (!rememberWindowPositionRef.current) return;
        const { device, x, y } = event.payload;
        setWindowPositions(prev => ({ ...prev, [device]: { x, y } }));
      }
    );

    return () => {
      unlistenLog.then(f => f());
      unlistenStatus.then(f => f());
      unlistenWindowPos.then(f => f());
    };
  }, [t]);

  const [historyDevices, setHistoryDevices] = useState<string[]>([]);

  useEffect(() => {
    const savedHistory = localStorage.getItem('scrcpy_history');
    if (savedHistory) {
      try {
        setHistoryDevices(JSON.parse(savedHistory));
      } catch (e) {
        console.error('Failed to parse history', e);
      }
    }
  }, []);

  const addToHistory = (ip: string) => {
    if (!ip.includes(':')) return;
    setHistoryDevices(prev => {
      const next = [ip, ...prev.filter(d => d !== ip)].slice(0, 10);
      localStorage.setItem('scrcpy_history', JSON.stringify(next));
      return next;
    });
  };

  const clearHistory = () => {
    setHistoryDevices([]);
    localStorage.removeItem('scrcpy_history');
  };

  const fetchDevicesOnce = async (customPath?: string, silent: boolean = false) => {
    try {
      const res: any = await invoke('get_devices', { customPath: customPath || config.scrcpyPath });
      let newDevices: string[] = [];

      if (!res.error) {
        newDevices = res.devices as string[];
        if (res.deviceModels) {
          setDeviceModels(res.deviceModels as Record<string, string>);
        }
        const prevDevices = prevDevicesRef.current;

        const added = newDevices.filter(d => !prevDevices.includes(d));
        const removed = prevDevices.filter(d => !newDevices.includes(d));

        added.forEach(device => {
          setLogs(prev => [...prev.slice(-100), t('logs.newDeviceDiscovered', { device })]);
        });

        removed.forEach(device => {
          setLogs(prev => [...prev.slice(-100), t('logs.deviceDisconnected', { device })]);
        });

        setDevices(newDevices);
        prevDevicesRef.current = newDevices;

        if (!silent && added.length === 0 && removed.length === 0) {
          setLogs(prev => [...prev.slice(-100), t('logs.discoveryActive', { count: newDevices.length })]);
        }

        if (newDevices.length > 0 && !activeDevice) {
          setActiveDevice(newDevices[0]);
        }
      } else if (!silent) {
        setLogs(prev => [...prev.slice(-100), t('logs.discoveryError', { error: res.message })]);
      }

      try {
        const mdnsRes: any = await invoke('get_mdns_devices', { customPath: customPath || config.scrcpyPath });
        if (mdnsRes && !mdnsRes.error && mdnsRes.services) {
          const parsedMdns = (mdnsRes.services as any[]).filter(
            s => s.service && (s.service.includes('_adb-tls-connect') || s.service.includes('_adb-tls-pairing'))
          );
          setMdnsDevices(parsedMdns);
          mdnsDevicesRef.current = parsedMdns;
        } else if (mdnsRes && mdnsRes.error) {
          setMdnsDevices([]);
          mdnsDevicesRef.current = [];
        }
      } catch (mdnsErr) {
        console.error('Failed to query mDNS devices:', mdnsErr);
      }
    } catch (e) {
      console.error(e);
      setLogs(prev => [...prev.slice(-100), t('logs.errorRefreshingDevices', { error: String(e) })]);
    }
  };

  const refreshDevices = async (customPath?: string, silent: boolean = false) => {
    if (isRefreshing) return;
    setIsRefreshing(true);
    try {
      await fetchDevicesOnce(customPath, silent);
    } finally {
      setIsRefreshing(false);
    }
  };

  const refreshDevicesUntilSettled = async (customPath?: string, attempts: number = 8, delayMs: number = 2000) => {
    if (isRefreshing) return;
    setIsRefreshing(true);
    try {
      let prevSnapshot = '';
      for (let i = 0; i <= attempts; i++) {
        await fetchDevicesOnce(customPath, true);
        const snapshot = JSON.stringify([prevDevicesRef.current, mdnsDevicesRef.current]);
        if (snapshot === prevSnapshot) return;
        prevSnapshot = snapshot;
        if (i < attempts) await new Promise(r => setTimeout(r, delayMs));
      }
    } finally {
      setIsRefreshing(false);
    }
  };

  const isRefreshingRef = useRef(isRefreshing);
  useEffect(() => {
    isRefreshingRef.current = isRefreshing;
  }, [isRefreshing]);
  const fetchDevicesOnceRef = useRef(fetchDevicesOnce);
  useEffect(() => {
    fetchDevicesOnceRef.current = fetchDevicesOnce;
  });

  useEffect(() => {
    const interval = setInterval(() => {
      if (document.visibilityState === 'hidden' || isRefreshingRef.current) return;
      fetchDevicesOnceRef.current(undefined, true);
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    devices.forEach(async serial => {
      if (fetchedFriendlyNamesRef.current.has(serial)) return;
      fetchedFriendlyNamesRef.current.add(serial);

      const isEmulator = /^emulator-\d+$/.test(serial);

      try {
        const command = isEmulator
          ? 'getprop ro.boot.qemu.avd_name; getprop ro.kernel.qemu.avd_name'
          : 'getprop ro.product.marketname; getprop ro.product.manufacturer; getprop ro.product.model';
        const res: any = await invoke('adb_shell', { device: serial, command, customPath: config.scrcpyPath });

        if (isEmulator) {
          const avdName = res?.success
            ? (res.output as string)
                .split('\n')
                .map(line => line.trim())
                .find(line => line.length > 0)
            : undefined;
          setDeviceFriendlyNames(prev => ({
            ...prev,
            [serial]: avdName ? `${avdName.replace(/_/g, ' ')} (${serial})` : serial,
          }));
          return;
        }

        if (res?.success) {
          const [marketname, manufacturer, model] = (res.output as string)
            .split('\n')
            .map(line => line.trim());
          const name =
            marketname ||
            (manufacturer && model && !model.toLowerCase().startsWith(manufacturer.toLowerCase())
              ? `${manufacturer} ${model}`
              : model);
          if (name) {
            setDeviceFriendlyNames(prev => ({ ...prev, [serial]: name }));
          }
        }
      } catch (e) {
        console.error('Failed to fetch friendly name for', serial, e);
      }
    });
  }, [devices, config.scrcpyPath]);

  useEffect(() => {
    const tryReconnectHistory = () => {
      if (document.visibilityState === 'hidden') return;
      historyDevices.forEach(ip => {
        if (!prevDevicesRef.current.includes(ip)) {
          invoke('adb_connect', { ip, customPath: config.scrcpyPath, silent: true }).catch(() => {});
        }
      });
    };
    tryReconnectHistory();
    const interval = setInterval(tryReconnectHistory, 25000);
    return () => clearInterval(interval);
  }, [historyDevices, config.scrcpyPath]);

  const runScrcpy = async (configToRun: ScrcpyConfig) => {
    try {
      setLogs(prev => [...prev.slice(-100), t('logs.initializingScrcpy', { device: configToRun.device })]);
      const savedPos = configToRun.rememberWindowPosition !== false ? windowPositions[configToRun.device] : undefined;
      const configWithPos: ScrcpyConfig = {
        ...configToRun,
        windowX: savedPos?.x,
        windowY: savedPos?.y,
      };
      await invoke('run_scrcpy', { config: configWithPos });
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.failedToStartScrcpy', { error: String(e) })]);
    }
  };

  const stopScrcpy = async (device: string) => {
    try {
      await invoke('stop_scrcpy', { device });
    } catch (e) {
      console.error(e);
    }
  };

  const recenterMirrorWindow = async (device: string) => {
    try {
      await invoke('recenter_scrcpy_window', { device });
    } catch (e) {
      console.error(e);
    }
  };

  const downloadScrcpy = async () => {
    try {
      setIsDownloading(true);
      await invoke('download_scrcpy');
    } catch (e: any) {
      setIsDownloading(false);
      setLogs(prev => [...prev, t('logs.downloadError', { error: String(e) })]);
    }
  };

  const checkScrcpy = async (customPath?: string) => {
    try {
      const pathToCheck = customPath !== undefined ? customPath : config.scrcpyPath;
      const res: any = await invoke('check_scrcpy', { customPath: pathToCheck });
      setScrcpyStatus(res);

      if (res.found) {
        try {
          const renderRes: any = await invoke('get_render_drivers', { customPath: pathToCheck });
          setRenderDriverSupport({
            hostOs: renderRes?.hostOs || 'unknown',
            supportsRenderDriver: !!renderRes?.supportsRenderDriver,
            supportedDrivers: Array.isArray(renderRes?.supportedDrivers) ? renderRes.supportedDrivers : [],
          });
        } catch {
          setRenderDriverSupport({
            hostOs: 'unknown',
            supportsRenderDriver: false,
            supportedDrivers: [],
          });
        }
      } else {
        setRenderDriverSupport({
          hostOs: 'unknown',
          supportsRenderDriver: false,
          supportedDrivers: [],
        });
      }

      if (!res.found) {
        setIsOnboardingOpen(true);
      }

      return res.found;
    } catch (e: any) {
      setScrcpyStatus({ found: false, message: t('logs.genericError', { error: String(e) }) });
      return false;
    }
  };

  const pairDevice = async (ip: string, code: string, customPath?: string) => {
    try {
      const res: any = await invoke('adb_pair', { ip, code, customPath: customPath || config.scrcpyPath });
      if (res.success) {
        setLogs(prev => [...prev.slice(-100), t('logs.successfullyPaired', { ip })]);
        await refreshDevicesUntilSettled(customPath);
      } else {
        setLogs(prev => {
          const msgs = [t('logs.pairingFailed', { message: String(res.message) })];
          if (typeof res.message === 'string' && res.message.includes('protocol fault')) {
            msgs.push(t('logs.pairingProtocolFault'));
          }
          return [...prev.slice(-100), ...msgs];
        });
      }
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.pairingError', { error: String(e) })]);
      return { success: false, message: e };
    }
  };

  const connectDevice = async (ip: string, customPath?: string) => {
    setIsRefreshing(true);
    try {
      let res: any = await invoke('adb_connect', { ip, customPath: customPath || config.scrcpyPath });

      if (
        !res.success &&
        typeof res.message === 'string' &&
        (res.message.includes('failed to connect') || res.message.includes('cannot connect'))
      ) {
        setLogs(prev => [...prev.slice(-100), t('logs.connectionFailedRetrying')]);
        await invoke('run_terminal_command', { cmd: `adb disconnect ${ip}`, customPath: customPath || config.scrcpyPath });
        await new Promise(r => setTimeout(r, 500));
        res = await invoke('adb_connect', { ip, customPath: customPath || config.scrcpyPath });
      }

      if (res.success) {
        setLogs(prev => [...prev.slice(-100), t('logs.connectedSuccessfully', { ip })]);
        addToHistory(ip);
        await new Promise(r => setTimeout(r, 1000));
        setIsRefreshing(false);
        await refreshDevices(customPath || config.scrcpyPath, true);
      } else {
        setLogs(prev => {
          const msgs = [t('logs.connectionFailed', { message: String(res.message) })];
          if (typeof res.message === 'string' && (res.message.includes('failed to connect') || res.message.includes('cannot connect'))) {
            msgs.push(t('logs.connectionStaleTip'));
          }
          return [...prev.slice(-100), ...msgs];
        });
      }
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.connectionError', { error: String(e) })]);
      return { success: false, message: e };
    } finally {
      setIsRefreshing(false);
    }
  };

  const listScrcpyOptions = async (device: string, arg: string, customPath?: string) => {
    try {
      setLogs(prev => [...prev.slice(-100), t('logs.runningScrcpyArg', { arg })]);
      const res: any = await invoke('list_scrcpy_options', { device, arg, customPath: customPath || config.scrcpyPath });
      if (res.output) {
        const lines = res.output.split('\n');
        setLogs(prev => [...prev.slice(-100), ...lines]);

        if (arg === '--list-cameras') {
          const cameras: { id: string; name: string }[] = [];
          lines.forEach((line: string) => {
            const trimmedLine = line.trim();
            const newMatch = trimmedLine.match(/--camera-id=(\w+)\s*\((.*?)\)/);
            const oldMatch = trimmedLine.match(/^(?:-\s*)?\[(\w+)\]\s*\((.*?)\)\s*(.*)/);

            if (newMatch) {
              const id = newMatch[1];
              const details = newMatch[2];
              cameras.push({ id, name: `${id}: ${details}` });
            } else if (oldMatch) {
              const id = oldMatch[1];
              const resolution = oldMatch[2];
              const metadata = oldMatch[3].replace(/\r$/, '').trim();
              cameras.push({ id, name: `${id}: ${metadata || 'Camera'} (${resolution})` });
            }
          });
          if (cameras.length > 0) {
            setDetectedCameras(cameras);
          } else {
            setLogs(prev => [...prev, t('logs.noCamerasParsed')]);
          }
        }
      }
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.genericError', { error: String(e) })]);
      return { success: false, message: e };
    }
  };

  const pushFile = async (device: string, filePath: string, customPath?: string) => {
    try {
      setLogs(prev => [...prev.slice(-100), t('logs.pushingFile', { device, filePath })]);
      const res: any = await invoke('push_file', { device, filePath, customPath: customPath || config.scrcpyPath });
      setLogs(prev => [...prev.slice(-100), t('logs.adbPrefix', { message: String(res.message) })]);
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.genericError', { error: String(e) })]);
      return { success: false, message: e };
    }
  };

  const installApk = async (device: string, filePath: string, customPath?: string) => {
    try {
      setLogs(prev => [...prev.slice(-100), t('logs.installingApk', { device, filePath })]);
      const res: any = await invoke('install_apk', { device, filePath, customPath: customPath || config.scrcpyPath });
      setLogs(prev => [...prev.slice(-100), t('logs.adbPrefix', { message: String(res.message) })]);
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.genericError', { error: String(e) })]);
      return { success: false, message: e };
    }
  };

  const runTerminalCommand = async (command: string, customPath?: string) => {
    try {
      const lower = command.trim().toLowerCase();
      const prefix = lower.startsWith('scrcpy') || lower.startsWith('adb') ? '' : 'adb ';
      setLogs(prev => [...prev.slice(-100), `> ${prefix}${command}`]);

      const res: any = await invoke('run_terminal_command', {
        device: activeDevice,
        cmd: command,
        customPath: customPath || config.scrcpyPath,
      });

      if (res.stdout) {
        const lines = res.stdout.trim().split('\n');
        setLogs(prev => [...prev.slice(-100), ...lines]);
      }
      if (res.stderr) {
        const lines = res.stderr
          .trim()
          .split('\n')
          .map((l: string) => `[${res.binary?.toUpperCase() || 'ERR'}] ${l}`);
        setLogs(prev => [...prev.slice(-100), ...lines]);
      }
      return res;
    } catch (e: any) {
      setLogs(prev => [...prev.slice(-100), t('logs.commandFailed', { error: String(e) })]);
      return { success: false, message: e };
    }
  };

  const clearLogs = () => setLogs([]);

  return {
    devices,
    deviceModels,
    deviceFriendlyNames,
    logs,
    setLogs,
    clearLogs,
    isDownloading,
    downloadProgress,
    status,
    refreshDevices,
    refreshDevicesUntilSettled,
    runScrcpy,
    stopScrcpy,
    recenterMirrorWindow,
    downloadScrcpy,
    activeDevice,
    setActiveDevice,
    checkScrcpy,
    scrcpyStatus,
    pairDevice,
    connectDevice,
    listScrcpyOptions,
    runTerminalCommand,
    runningDevices,
    defaultRecordPath,
    detectedCameras,
    renderDriverSupport,
    isRefreshing,
    mdnsDevices,
    config,
    setConfig,
    theme,
    setTheme,
    colorMode,
    setColorMode,
    pushFile,
    installApk,
    historyDevices,
    clearHistory,
    sessionRunning: runningDevices.includes(activeDevice || ''),
    isOnboardingOpen,
    setIsOnboardingOpen,
    completeOnboarding: () => {
      localStorage.setItem('scrcpy_onboarding_done', 'true');
      setIsOnboardingOpen(false);
    },
  };
}
