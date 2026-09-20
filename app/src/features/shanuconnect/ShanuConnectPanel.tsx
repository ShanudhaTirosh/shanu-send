import React, { useState, useEffect } from 'react';
import {
  Volume2,
  Play,
  Pause,
  SkipForward,
  SkipBack,
  MessageSquare,
  Terminal,
  Battery,
  Bell,
  Lock,
  Wifi,
  Send,
  Radio,
  Sparkles,
  Clipboard,
  ShieldCheck,
} from 'lucide-react';
import type { Device } from '../../types';
import {
  shanuconnectTriggerFindPhone,
  shanuconnectLockDevice,
  shanuconnectRunRemoteCommand,
  shanuconnectSendSms,
  shanuconnectMprisControl,
  onShanuConnectEvent,
} from '../../lib/tauri';

interface ShanuConnectPanelProps {
  selectedDevice: Device | null;
  onSelectDevice?: (device: Device) => void;
  devices?: Device[];
}

type TabType = 'notifications' | 'sms' | 'commands' | 'media' | 'clipboard';

export const ShanuConnectPanel: React.FC<ShanuConnectPanelProps> = ({
  selectedDevice,
  devices = [],
}) => {
  const [activeTab, setActiveTab] = useState<TabType>('notifications');

  // Battery & Connection State
  const [batteryLevel, setBatteryLevel] = useState<number | null>(null);
  const [isCharging, setIsCharging] = useState<boolean>(false);
  const [isRinging, setIsRinging] = useState<boolean>(false);
  const [isDeviceLocked, setIsDeviceLocked] = useState<boolean>(false);
  const [hasReceivedPacket, setHasReceivedPacket] = useState<boolean>(false);

  // MPRIS State
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [trackTitle, setTrackTitle] = useState<string>('No Active Track');
  const [artistName, setArtistName] = useState<string>('Remote Media Stream Inactive');
  const [mediaVolume, setMediaVolume] = useState<number>(100);

  // SMS State
  const [contactSearch, setContactSearch] = useState<string>('');
  const [selectedContact] = useState<string>('');
  const [smsInput, setSmsInput] = useState<string>('');
  const [messages, setMessages] = useState<Array<{ sender: string; text: string; time: string }>>([]);

  // Remote Commands
  const [customCommand, setCustomCommand] = useState<string>('');
  const [commandList, setCommandList] = useState<Array<{ id: string; name: string; cmd: string }>>([
    { id: '1', name: 'Lock Workstation', cmd: 'lock' },
    { id: '2', name: 'Ping Remote Device', cmd: 'ping' },
  ]);

  // Notifications
  const [notifications, setNotifications] = useState<Array<{ id: string; app: string; title: string; body: string }>>([]);

  // Clipboard
  const [sharedClipboard, setSharedClipboard] = useState<string>('');
  const [clipboardCopyStatus, setClipboardCopyStatus] = useState<string | null>(null);

  const isConnected = selectedDevice !== null || hasReceivedPacket;

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    onShanuConnectEvent((payload: { type: string; body: any }) => {
      setHasReceivedPacket(true);
      if (payload.type === 'shanuconnect.battery' || payload.type === 'kdeconnect.battery') {
        if (typeof payload.body?.currentCharge === 'number') {
          setBatteryLevel(payload.body.currentCharge);
        }
        if (typeof payload.body?.isCharging === 'boolean') {
          setIsCharging(payload.body.isCharging);
        }
      } else if (payload.type === 'shanuconnect.mpris' || payload.type === 'kdeconnect.mpris') {
        if (payload.body?.title) setTrackTitle(payload.body.title);
        if (payload.body?.artist) setArtistName(payload.body.artist);
        if (typeof payload.body?.isPlaying === 'boolean') setIsPlaying(payload.body.isPlaying);
      } else if (payload.type === 'shanuconnect.notifications' || payload.type === 'kdeconnect.notifications') {
        setNotifications((prev) => [
          {
            id: payload.body?.id || String(Date.now()),
            app: payload.body?.appName || 'Remote Device',
            title: payload.body?.title || 'Notification',
            body: payload.body?.body || '',
          },
          ...prev,
        ]);
      } else if (payload.type === 'shanuconnect.sms' || payload.type === 'kdeconnect.sms') {
        if (payload.body?.sendBody) {
          setMessages((prev) => [
            ...prev,
            {
              sender: payload.body?.sendTo || 'Remote',
              text: payload.body.sendBody,
              time: 'Just now',
            },
          ]);
        }
      } else if (payload.type === 'shanuconnect.lockdevice' || payload.type === 'kdeconnect.lockdevice') {
        if (typeof payload.body?.isLocked === 'boolean') {
          setIsDeviceLocked(payload.body.isLocked);
        }
      }
    }).then((fn: (() => void) | undefined) => {
      unlisten = fn;
    });

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const handleToggleRing = async () => {
    const nextState = !isRinging;
    setIsRinging(nextState);
    await shanuconnectTriggerFindPhone(nextState);
  };

  const handleToggleLock = async () => {
    const nextState = !isDeviceLocked;
    setIsDeviceLocked(nextState);
    await shanuconnectLockDevice(nextState);
  };

  const handleSendSms = async () => {
    if (!smsInput.trim()) return;
    const text = smsInput;
    setMessages((prev) => [...prev, { sender: 'You', text, time: 'Just now' }]);
    setSmsInput('');
    await shanuconnectSendSms(selectedContact, text);
  };

  const handleAddCommand = () => {
    if (!customCommand.trim()) return;
    setCommandList((prev) => [
      ...prev,
      { id: String(Date.now()), name: customCommand, cmd: customCommand },
    ]);
    setCustomCommand('');
  };

  const handleRunCommand = async (cmdString: string) => {
    await shanuconnectRunRemoteCommand(cmdString);
  };

  const handleMediaPlayPause = async () => {
    const nextState = !isPlaying;
    setIsPlaying(nextState);
    await shanuconnectMprisControl(nextState ? 'play' : 'pause');
  };

  const handleVolumeChange = async (newVol: number) => {
    setMediaVolume(newVol);
    await shanuconnectMprisControl('volume', newVol);
  };

  const handleCopyClipboard = async () => {
    if (!sharedClipboard) return;
    try {
      await navigator.clipboard.writeText(sharedClipboard);
      setClipboardCopyStatus('Copied to system clipboard!');
      setTimeout(() => setClipboardCopyStatus(null), 2500);
    } catch (_) {
      setClipboardCopyStatus('Failed to copy');
    }
  };

  return (
    <div className="flex h-full w-full flex-col rounded-2xl border border-white/10 bg-[#090b11] p-6 text-slate-200 shadow-xl backdrop-blur-xl">
      {/* Header Info & Status */}
      <div className="flex items-center justify-between border-b border-white/10 pb-4">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-400">
            <Sparkles className="h-6 w-6 animate-pulse" />
          </div>
          <div>
            <div className="flex items-center gap-3">
              <h2 className="text-lg font-bold text-white tracking-wide">
                {selectedDevice ? selectedDevice.alias : 'ShanuConnect Suite'}
              </h2>
              {isConnected ? (
                <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3 py-0.5 text-xs font-semibold text-emerald-400">
                  <Wifi size={13} className="animate-pulse" />
                  ShanuConnect Active ({selectedDevice?.ip || 'TCP:1716'})
                </span>
              ) : (
                <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 px-3 py-0.5 text-xs font-semibold text-amber-300">
                  <Radio size={13} className="animate-spin text-amber-400" />
                  Listening for Peer (Port 1716)
                </span>
              )}
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              Protocol v7 &middot; 36 Remote Capabilities Engine
            </p>
          </div>
        </div>

        {/* Quick Quick Bar */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/40 px-3 py-1.5 text-xs">
            <Battery className="h-4 w-4 text-cyan-400" />
            <span className="font-semibold text-slate-200">
              {batteryLevel !== null ? `${batteryLevel}%` : 'N/A'} {isCharging && '⚡'}
            </span>
          </div>

          <button
            onClick={handleToggleRing}
            className={`flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold transition ${
              isRinging
                ? 'animate-bounce border-pink-500/50 bg-pink-500/20 text-pink-300'
                : 'border-white/10 bg-white/5 text-slate-300 hover:bg-white/10'
            }`}
          >
            <Bell size={14} className={isRinging ? 'text-pink-400' : 'text-slate-400'} />
            <span>{isRinging ? 'Ringing Phone...' : 'Find Phone'}</span>
          </button>

          <button
            onClick={handleToggleLock}
            className={`flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold transition ${
              isDeviceLocked
                ? 'border-red-500/50 bg-red-500/20 text-red-300'
                : 'border-white/10 bg-white/5 text-slate-300 hover:bg-white/10'
            }`}
          >
            <Lock size={14} className={isDeviceLocked ? 'text-red-400' : 'text-slate-400'} />
            <span>{isDeviceLocked ? 'Locked' : 'Lock Device'}</span>
          </button>
        </div>
      </div>

      {/* Disconnected Notice Banner when no device is paired */}
      {!isConnected && (
        <div className="mt-4 flex items-center justify-between rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-xs text-amber-200">
          <div className="flex items-center gap-3">
            <ShieldCheck size={18} className="text-amber-400" />
            <div>
              <p className="font-bold">No ShanuConnect Remote Device Selected</p>
              <p className="text-[11px] text-amber-300/80">
                To control remote devices, select a discovered device from the right sidebar or open ShanuSend on your phone.
              </p>
            </div>
          </div>
          {devices.length > 0 && (
            <span className="font-semibold text-amber-400">
              {devices.length} Peer(s) Discovered
            </span>
          )}
        </div>
      )}

      {/* Navigation Sub-Tabs */}
      <div className="mt-4 flex gap-2 border-b border-white/10 pb-3">
        {[
          { id: 'notifications', label: 'Notifications Stream', icon: Bell },
          { id: 'sms', label: 'SMS & Contacts', icon: MessageSquare },
          { id: 'commands', label: 'Remote Commands', icon: Terminal },
          { id: 'media', label: 'Media Remote (MPRIS)', icon: Play },
          { id: 'clipboard', label: 'Shared Clipboard', icon: Clipboard },
        ].map((tab) => {
          const IconComponent = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as TabType)}
              className={`flex items-center gap-2 rounded-xl px-3.5 py-2 text-xs font-semibold transition ${
                isActive
                  ? 'bg-cyan-500/15 text-cyan-300 border border-cyan-500/30 shadow-sm'
                  : 'text-slate-400 hover:bg-white/5 hover:text-slate-200'
              }`}
            >
              <IconComponent size={14} className={isActive ? 'text-cyan-400' : 'text-slate-400'} />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* Main Tab View Contents */}
      <div className="mt-4 flex-1 overflow-y-auto pr-1">
        {/* 1. Notifications Stream */}
        {activeTab === 'notifications' && (
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between text-xs text-slate-400">
              <span>Synced Remote System Notifications</span>
              {notifications.length > 0 && (
                <button
                  onClick={() => setNotifications([])}
                  className="text-cyan-400 hover:underline"
                >
                  Clear All
                </button>
              )}
            </div>

            {notifications.length === 0 ? (
              <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-white/10 py-12 text-slate-500">
                <Bell size={36} className="mb-2 text-slate-600" />
                <p className="text-sm font-semibold text-slate-400">No Notifications Received</p>
                <p className="text-xs text-slate-500">
                  Incoming phone & system notifications will mirror here in real time.
                </p>
              </div>
            ) : (
              notifications.map((n) => (
                <div
                  key={n.id}
                  className="flex items-start justify-between rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-sm"
                >
                  <div className="flex gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-cyan-500/10 text-cyan-400 font-bold text-xs">
                      {n.app.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <p className="text-xs font-bold text-white">{n.title}</p>
                      <p className="text-xs text-slate-300 mt-0.5">{n.body}</p>
                      <span className="text-[10px] text-slate-500 mt-1 inline-block">{n.app}</span>
                    </div>
                  </div>
                  <button
                    onClick={() => setNotifications((prev) => prev.filter((x) => x.id !== n.id))}
                    className="text-slate-500 hover:text-slate-300 text-xs"
                  >
                    Dismiss
                  </button>
                </div>
              ))
            )}
          </div>
        )}

        {/* 2. SMS & Contacts */}
        {activeTab === 'sms' && (
          <div className="grid grid-cols-1 md:grid-cols-[220px_1fr] gap-4 h-full">
            <div className="flex flex-col gap-2 rounded-xl border border-white/10 bg-white/5 p-3">
              <input
                type="text"
                placeholder="Search contacts..."
                value={contactSearch}
                onChange={(e) => setContactSearch(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-void-950/60 p-2 text-xs text-slate-200 placeholder-slate-500 focus:outline-none"
              />
              <div className="flex-1 overflow-y-auto">
                <p className="text-[11px] text-slate-500 p-2 text-center">
                  Address book contacts will sync automatically upon connection.
                </p>
              </div>
            </div>

            <div className="flex flex-col rounded-xl border border-white/10 bg-white/5 p-4">
              <div className="flex-1 overflow-y-auto space-y-2 mb-3">
                {messages.length === 0 ? (
                  <div className="flex flex-col items-center justify-center h-48 text-slate-500 text-xs">
                    <MessageSquare size={32} className="mb-2 text-slate-600" />
                    <p>No SMS conversation history</p>
                  </div>
                ) : (
                  messages.map((m, idx) => (
                    <div
                      key={idx}
                      className={`flex flex-col max-w-[80%] rounded-xl p-3 text-xs ${
                        m.sender === 'You'
                          ? 'ml-auto bg-cyan-500/20 border border-cyan-500/30 text-cyan-200'
                          : 'mr-auto bg-white/10 text-slate-200'
                      }`}
                    >
                      <span className="font-semibold text-[10px] text-slate-400 mb-1">{m.sender}</span>
                      <p>{m.text}</p>
                    </div>
                  ))
                )}
              </div>

              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="Type an SMS message to send via phone..."
                  value={smsInput}
                  onChange={(e) => setSmsInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleSendSms()}
                  className="flex-1 rounded-xl border border-white/10 bg-void-950/80 p-2.5 text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-cyan-500/40"
                />
                <button
                  onClick={handleSendSms}
                  className="flex items-center gap-1.5 rounded-xl bg-cyan-500 px-4 py-2 text-xs font-semibold text-slate-950 transition hover:bg-cyan-400"
                >
                  <Send size={14} />
                  <span>Send</span>
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 3. Remote Commands */}
        {activeTab === 'commands' && (
          <div className="flex flex-col gap-4">
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="Enter custom remote command..."
                value={customCommand}
                onChange={(e) => setCustomCommand(e.target.value)}
                className="flex-1 rounded-xl border border-white/10 bg-void-950/80 p-2.5 text-xs text-slate-200 placeholder-slate-500 focus:outline-none"
              />
              <button
                onClick={handleAddCommand}
                className="rounded-xl border border-white/10 bg-white/10 px-4 py-2 text-xs font-semibold text-slate-200 hover:bg-white/20"
              >
                Add Shortcut
              </button>
            </div>

            <div className="grid grid-cols-2 gap-3">
              {commandList.map((c) => (
                <div
                  key={c.id}
                  className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-4 hover:border-cyan-500/30 transition"
                >
                  <div>
                    <p className="text-xs font-bold text-white">{c.name}</p>
                    <code className="text-[11px] text-cyan-400/80">{c.cmd}</code>
                  </div>
                  <button
                    onClick={() => handleRunCommand(c.cmd)}
                    className="flex items-center gap-1 rounded-lg bg-cyan-500/20 border border-cyan-500/40 px-3 py-1.5 text-xs font-semibold text-cyan-300 hover:bg-cyan-500/30"
                  >
                    <Terminal size={12} />
                    Run
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 4. Media Remote (MPRIS) */}
        {activeTab === 'media' && (
          <div className="flex flex-col items-center justify-center rounded-2xl border border-white/10 bg-white/5 p-8 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 mb-4">
              <Play size={32} />
            </div>
            <h3 className="text-base font-bold text-white">{trackTitle}</h3>
            <p className="text-xs text-slate-400 mt-1">{artistName}</p>

            <div className="flex items-center justify-center gap-6 mt-6">
              <button
                onClick={() => shanuconnectMprisControl('previous')}
                className="flex h-10 w-10 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-slate-300 hover:bg-white/15"
              >
                <SkipBack size={18} />
              </button>

              <button
                onClick={handleMediaPlayPause}
                className="flex h-14 w-14 items-center justify-center rounded-2xl bg-cyan-500 text-slate-950 shadow-glow font-bold hover:bg-cyan-400 transition"
              >
                {isPlaying ? <Pause size={24} /> : <Play size={24} className="ml-0.5" />}
              </button>

              <button
                onClick={() => shanuconnectMprisControl('next')}
                className="flex h-10 w-10 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-slate-300 hover:bg-white/15"
              >
                <SkipForward size={18} />
              </button>
            </div>

            <div className="w-full max-w-md mt-6 flex items-center gap-3 text-xs text-slate-400">
              <Volume2 size={16} />
              <input
                type="range"
                min="0"
                max="100"
                value={mediaVolume}
                onChange={(e) => handleVolumeChange(Number(e.target.value))}
                className="h-1.5 flex-1 appearance-none rounded-lg bg-white/10 accent-cyan-400"
              />
              <span className="w-8 text-right">{mediaVolume}%</span>
            </div>
          </div>
        )}

        {/* 5. Shared Clipboard */}
        {activeTab === 'clipboard' && (
          <div className="flex flex-col gap-3 rounded-2xl border border-white/10 bg-white/5 p-5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-300">Shared System Clipboard</span>
              {clipboardCopyStatus && (
                <span className="text-xs font-semibold text-emerald-400">{clipboardCopyStatus}</span>
              )}
            </div>

            <textarea
              value={sharedClipboard}
              onChange={(e) => setSharedClipboard(e.target.value)}
              placeholder="Text entered here syncs dynamically across connected devices..."
              className="h-32 w-full resize-none rounded-xl border border-white/10 bg-void-950/80 p-3 text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-cyan-500/40"
            />

            <div className="flex justify-end gap-2">
              <button
                onClick={handleCopyClipboard}
                disabled={!sharedClipboard.trim()}
                className="flex items-center gap-1.5 rounded-xl bg-cyan-500 px-4 py-2 text-xs font-semibold text-slate-950 transition hover:bg-cyan-400 disabled:opacity-50"
              >
                <Clipboard size={14} />
                <span>Copy to Local Clipboard</span>
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
