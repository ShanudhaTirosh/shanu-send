import React, { useState } from 'react';
import {
  Mouse,
  Volume2,
  Play,
  Pause,
  SkipForward,
  SkipBack,
  MessageSquare,
  Terminal,
  Presentation,
  Battery,
  Bell,
  Lock,
  Wifi,
  User,
  Send,
  VolumeX,
  X,
  Radio,
  Sparkles,
} from 'lucide-react';
import {
  kdeconnectSendMousepad,
  kdeconnectTriggerFindPhone,
  kdeconnectLockDevice,
  kdeconnectRunRemoteCommand,
  kdeconnectSendSms,
  kdeconnectMprisControl,
} from '../../lib/tauri';

interface KdeConnectModalProps {
  isOpen: boolean;
  onClose: () => void;
  deviceName?: string;
}

type TabType = 'input' | 'media' | 'sms' | 'commands' | 'presenter' | 'notifications';

export const KdeConnectModal: React.FC<KdeConnectModalProps> = ({
  isOpen,
  onClose,
  deviceName = 'KDE Connect Device',
}) => {
  const [activeTab, setActiveTab] = useState<TabType>('input');

  // Battery & Phone State
  const [batteryLevel] = useState<number | null>(null);
  const [isCharging] = useState<boolean>(false);
  const [isRinging, setIsRinging] = useState<boolean>(false);
  const [isDeviceLocked, setIsDeviceLocked] = useState<boolean>(false);

  // MPRIS State
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [trackTitle] = useState<string>('No Active Media Track');
  const [artistName] = useState<string>('KDE Connect MPRIS Stream');
  const [mediaVolume, setMediaVolume] = useState<number>(100);

  // SMS & Contacts State
  const [contactSearch, setContactSearch] = useState<string>('');
  const [selectedContact, setSelectedContact] = useState<string>('');
  const [smsInput, setSmsInput] = useState<string>('');
  const [contacts] = useState<Array<string>>([]);
  const [messages, setMessages] = useState<Array<{ sender: string; text: string; time: string }>>([]);

  // Remote Commands
  const [customCommand, setCustomCommand] = useState<string>('');
  const [commandList, setCommandList] = useState<Array<{ id: string; name: string; cmd: string }>>([
    { id: '1', name: 'Lock Workstation', cmd: 'rundll32.exe user32.dll,LockWorkStation' },
    { id: '2', name: 'Launch Terminal', cmd: 'cmd.exe /c start cmd' },
    { id: '3', name: 'Network Info', cmd: 'ipconfig' },
  ]);

  // Notifications Stream
  const [notifications, setNotifications] = useState<Array<{ id: string; app: string; title: string; body: string }>>([]);


  if (!isOpen) return null;

  const handleToggleRing = async () => {
    const nextState = !isRinging;
    setIsRinging(nextState);
    await kdeconnectTriggerFindPhone(nextState);
  };

  const handleToggleLock = async () => {
    const nextState = !isDeviceLocked;
    setIsDeviceLocked(nextState);
    await kdeconnectLockDevice(nextState);
  };

  const handleSendSms = async () => {
    if (!smsInput.trim()) return;
    const text = smsInput;
    setMessages((prev) => [...prev, { sender: 'You', text, time: 'Just now' }]);
    setSmsInput('');
    await kdeconnectSendSms(selectedContact, text);
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
    await kdeconnectRunRemoteCommand(cmdString);
  };

  const handleMediaPlayPause = async () => {
    const nextState = !isPlaying;
    setIsPlaying(nextState);
    await kdeconnectMprisControl(nextState ? 'play' : 'pause');
  };

  const handleVolumeChange = async (newVol: number) => {
    setMediaVolume(newVol);
    await kdeconnectMprisControl('volume', newVol);
  };

  const handleMouseClick = async (clickType: string) => {
    await kdeconnectSendMousepad(0, 0, clickType);
  };


  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-4 animate-in fade-in duration-200">
      <div className="w-full max-w-4xl h-[720px] bg-[#090b11] border border-cyan-500/20 rounded-2xl shadow-2xl shadow-cyan-500/10 flex flex-col overflow-hidden text-slate-200 font-sans">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-white/10 bg-gradient-to-r from-cyan-950/40 via-slate-900/60 to-purple-950/40">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-400">
              <Sparkles className="w-5 h-5 animate-pulse" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-white tracking-wide">{deviceName}</h2>
                <span className="px-2 py-0.5 text-xs font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 rounded-full flex items-center gap-1">
                  <Wifi className="w-3 h-3" /> KDE Connected
                </span>
              </div>
              <p className="text-xs text-slate-400">KDE Connect Protocol v7 • All 20+ Plugins Active</p>
            </div>
          </div>

          <div className="flex items-center gap-4">
            {/* Quick Status Pill */}
            <div className="flex items-center gap-3 px-3 py-1.5 bg-black/40 border border-white/10 rounded-lg text-xs">
              <div className="flex items-center gap-1.5 text-cyan-400">
                <Battery className="w-4 h-4" />
                <span>{batteryLevel}% {isCharging && '⚡'}</span>
              </div>
              <button
                onClick={handleToggleRing}
                className={`px-2 py-1 rounded text-[11px] font-medium transition ${
                  isRinging
                    ? 'bg-rose-500 text-white animate-bounce'
                    : 'bg-white/5 hover:bg-white/10 text-slate-300'
                }`}
              >
                <Radio className="w-3 h-3 inline mr-1" />
                {isRinging ? 'Ringing...' : 'Find Phone'}
              </button>
              <button
                onClick={handleToggleLock}
                className={`px-2.5 py-1 rounded text-[11px] font-medium border transition ${
                  isDeviceLocked
                    ? 'bg-purple-500/20 text-purple-300 border-purple-500/40'
                    : 'bg-white/5 border-white/10 hover:bg-white/10 text-slate-300'
                }`}
              >
                <Lock className="w-3 h-3 inline mr-1" />
                {isDeviceLocked ? 'Locked' : 'Lock Device'}
              </button>
            </div>

            <button
              onClick={onClose}
              className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Navigation Tabs */}
        <div className="flex border-b border-white/10 bg-black/40 px-6 gap-2 pt-2">
          {[
            { id: 'input', label: 'Trackpad & Input', icon: Mouse },
            { id: 'media', label: 'Media Remote (MPRIS)', icon: Play },
            { id: 'sms', label: 'SMS & Contacts', icon: MessageSquare },
            { id: 'commands', label: 'Remote Commands', icon: Terminal },
            { id: 'presenter', label: 'Presenter Clicker', icon: Presentation },
            { id: 'notifications', label: 'Notifications', icon: Bell },
          ].map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as TabType)}
                className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-t-xl transition border-t border-x ${
                  isActive
                    ? 'bg-[#0f1422] text-cyan-400 border-cyan-500/30 border-b-[#0f1422] z-10'
                    : 'text-slate-400 border-transparent hover:text-slate-200 hover:bg-white/5'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {/* Tab Body */}
        <div className="flex-1 bg-[#0f1422] p-6 overflow-y-auto">
          {/* TAB 1: TRACKPAD & INPUT */}
          {activeTab === 'input' && (
            <div className="h-full flex flex-col gap-4">
              <div className="flex-1 border-2 border-dashed border-cyan-500/20 rounded-2xl bg-black/40 flex flex-col items-center justify-center relative hover:border-cyan-500/40 transition cursor-crosshair">
                <Mouse className="w-12 h-12 text-cyan-500/30 mb-2" />
                <p className="text-sm text-slate-400 font-medium">Virtual Touchpad Surface</p>
                <p className="text-xs text-slate-500">Drag cursor • 2 Finger Scroll • Tap to Click</p>
              </div>
              <div className="flex gap-3">
                <button
                  onClick={() => handleMouseClick('left')}
                  className="flex-1 py-3 bg-white/5 hover:bg-cyan-500/20 border border-white/10 rounded-xl text-sm font-semibold active:scale-[0.98] transition"
                >
                  Left Click
                </button>
                <button
                  onClick={() => handleMouseClick('middle')}
                  className="flex-1 py-3 bg-white/5 hover:bg-purple-500/20 border border-white/10 rounded-xl text-sm font-semibold active:scale-[0.98] transition"
                >
                  Middle Click
                </button>
                <button
                  onClick={() => handleMouseClick('right')}
                  className="flex-1 py-3 bg-white/5 hover:bg-cyan-500/20 border border-white/10 rounded-xl text-sm font-semibold active:scale-[0.98] transition"
                >
                  Right Click
                </button>
              </div>
            </div>
          )}

          {/* TAB 2: MEDIA REMOTE */}
          {activeTab === 'media' && (
            <div className="flex flex-col items-center justify-center h-full max-w-lg mx-auto gap-6 text-center">
              <div className="w-32 h-32 bg-gradient-to-tr from-cyan-500/20 to-purple-500/20 border border-cyan-500/30 rounded-2xl flex items-center justify-center shadow-lg shadow-cyan-500/10">
                <Play className="w-12 h-12 text-cyan-400" />
              </div>
              <div>
                <h3 className="text-xl font-bold text-white">{trackTitle}</h3>
                <p className="text-sm text-slate-400">{artistName}</p>
              </div>

              {/* Progress Scrubber */}
              <div className="w-full">
                <div className="w-full bg-white/10 h-2 rounded-full overflow-hidden">
                  <div className="bg-cyan-400 h-full w-2/3 rounded-full" />
                </div>
                <div className="flex justify-between text-xs text-slate-400 mt-1">
                  <span>02:15</span>
                  <span>03:45</span>
                </div>
              </div>

              {/* Playback Controls */}
              <div className="flex items-center gap-6">
                <button
                  onClick={() => kdeconnectMprisControl('previous')}
                  className="p-3 rounded-full bg-white/5 hover:bg-white/10 border border-white/10 transition"
                >
                  <SkipBack className="w-6 h-6" />
                </button>
                <button
                  onClick={handleMediaPlayPause}
                  className="p-4 rounded-full bg-gradient-to-r from-cyan-500 to-blue-600 text-black font-bold shadow-lg shadow-cyan-500/20 hover:scale-105 active:scale-95 transition"
                >
                  {isPlaying ? <Pause className="w-8 h-8 fill-black" /> : <Play className="w-8 h-8 fill-black ml-1" />}
                </button>
                <button
                  onClick={() => kdeconnectMprisControl('next')}
                  className="p-3 rounded-full bg-white/5 hover:bg-white/10 border border-white/10 transition"
                >
                  <SkipForward className="w-6 h-6" />
                </button>
              </div>

              {/* Volume Scrubber */}
              <div className="flex items-center gap-3 w-full max-w-xs bg-black/30 p-3 rounded-xl border border-white/10">
                <VolumeX className="w-4 h-4 text-slate-400" />
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={mediaVolume}
                  onChange={(e) => handleVolumeChange(Number(e.target.value))}
                  className="w-full accent-cyan-400"
                />
                <Volume2 className="w-4 h-4 text-cyan-400" />
              </div>
            </div>
          )}

          {/* TAB 3: SMS & CONTACTS */}
          {activeTab === 'sms' && (
            <div className="grid grid-cols-3 gap-4 h-full">
              {/* Contacts List */}
              <div className="border border-white/10 rounded-xl bg-black/30 p-3 flex flex-col gap-3">
                <input
                  type="text"
                  placeholder="Search / enter number..."
                  value={contactSearch}
                  onChange={(e) => {
                    setContactSearch(e.target.value);
                    if (e.target.value) setSelectedContact(e.target.value);
                  }}
                  className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-xs focus:outline-none focus:border-cyan-500 text-white"
                />
                <div className="flex-1 overflow-y-auto space-y-1">
                  {contacts.length === 0 ? (
                    <div className="p-4 text-center text-slate-500 text-xs">
                      No contacts synced yet. Type a recipient number above.
                    </div>
                  ) : (
                    contacts
                      .filter((c) => c.toLowerCase().includes(contactSearch.toLowerCase()))
                      .map((contact) => (
                        <button
                          key={contact}
                          onClick={() => setSelectedContact(contact)}
                          className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium flex items-center gap-2 transition ${
                            selectedContact === contact
                              ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
                              : 'hover:bg-white/5 text-slate-400'
                          }`}
                        >
                          <User className="w-3.5 h-3.5" />
                          {contact}
                        </button>
                      ))
                  )}
                </div>
              </div>

              {/* Messages Thread */}
              <div className="col-span-2 border border-white/10 rounded-xl bg-black/30 p-4 flex flex-col">
                <h4 className="text-sm font-semibold border-b border-white/10 pb-2 mb-3 text-cyan-400 flex items-center gap-2">
                  <User className="w-4 h-4" /> {selectedContact || 'Select Recipient'}
                </h4>
                <div className="flex-1 overflow-y-auto space-y-3 pr-2 mb-4">
                  {messages.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center text-slate-500 text-xs">
                      <MessageSquare className="w-8 h-8 text-slate-600 mb-2" />
                      <span>No conversation history. Enter message below to send.</span>
                    </div>
                  ) : (
                    messages.map((msg, i) => (
                      <div
                        key={i}
                        className={`flex flex-col ${
                          msg.sender === 'You' ? 'items-end' : 'items-start'
                        }`}
                      >
                        <div
                          className={`max-w-[80%] px-4 py-2.5 rounded-2xl text-xs font-medium ${
                            msg.sender === 'You'
                              ? 'bg-cyan-600 text-white rounded-br-none'
                              : 'bg-slate-800 text-slate-200 border border-white/10 rounded-bl-none'
                          }`}
                        >
                          {msg.text}
                        </div>
                        <span className="text-[10px] text-slate-500 mt-1">{msg.time}</span>
                      </div>
                    ))
                  )}
                </div>

                <div className="flex gap-2 pt-2 border-t border-white/10">
                  <input
                    type="text"
                    placeholder="Type SMS message..."
                    value={smsInput}
                    onChange={(e) => setSmsInput(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleSendSms()}
                    className="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-xs focus:outline-none focus:border-cyan-500 text-white"
                  />
                  <button
                    onClick={handleSendSms}
                    className="px-4 py-2 bg-cyan-500 hover:bg-cyan-400 text-black font-semibold rounded-lg text-xs flex items-center gap-1.5 transition"
                  >
                    <Send className="w-3.5 h-3.5" /> Send
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* TAB 4: REMOTE COMMANDS */}
          {activeTab === 'commands' && (
            <div className="flex flex-col gap-4 h-full">
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="Add custom CLI command..."
                  value={customCommand}
                  onChange={(e) => setCustomCommand(e.target.value)}
                  className="flex-1 bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-xs focus:outline-none focus:border-cyan-500 text-white"
                />
                <button
                  onClick={handleAddCommand}
                  className="px-4 py-2.5 bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/40 rounded-xl text-xs font-semibold transition"
                >
                  Add Command
                </button>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {commandList.map((cmd) => (
                  <div
                    key={cmd.id}
                    className="p-4 bg-black/40 border border-white/10 rounded-xl flex items-center justify-between hover:border-cyan-500/30 transition group"
                  >
                    <div>
                      <h4 className="text-sm font-semibold text-white">{cmd.name}</h4>
                      <p className="text-[11px] text-slate-500 font-mono mt-0.5">{cmd.cmd}</p>
                    </div>
                    <button
                      onClick={() => handleRunCommand(cmd.cmd)}
                      className="px-3 py-1.5 bg-cyan-500/10 group-hover:bg-cyan-500 text-cyan-400 group-hover:text-black font-semibold text-xs rounded-lg transition border border-cyan-500/30"
                    >
                      Run
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB 5: PRESENTER CLICKER */}
          {activeTab === 'presenter' && (
            <div className="flex flex-col items-center justify-center h-full gap-6">
              <div className="w-full max-w-lg h-56 border-2 border-dashed border-purple-500/30 rounded-2xl bg-black/40 flex flex-col items-center justify-center relative cursor-crosshair">
                <div className="w-4 h-4 bg-rose-500 rounded-full shadow-lg shadow-rose-500/80 animate-ping absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2" />
                <p className="text-xs text-purple-300 font-medium">Virtual Laser Pointer Canvas</p>
              </div>
              <div className="flex gap-4">
                <button
                  onClick={() => kdeconnectMprisControl('previous')}
                  className="px-8 py-4 bg-white/5 hover:bg-purple-500/20 border border-white/10 rounded-2xl text-sm font-bold transition flex items-center gap-2"
                >
                  <SkipBack className="w-5 h-5" /> Previous Slide
                </button>
                <button
                  onClick={() => kdeconnectMprisControl('next')}
                  className="px-8 py-4 bg-gradient-to-r from-purple-500 to-indigo-600 text-white font-bold rounded-2xl text-sm shadow-lg shadow-purple-500/20 hover:scale-105 active:scale-95 transition flex items-center gap-2"
                >
                  Next Slide <SkipForward className="w-5 h-5" />
                </button>
              </div>
            </div>
          )}

          {/* TAB 6: NOTIFICATIONS */}
          {activeTab === 'notifications' && (
            <div className="space-y-3">
              {notifications.length === 0 ? (
                <div className="h-48 flex flex-col items-center justify-center text-slate-500 text-xs">
                  <Bell className="w-8 h-8 text-slate-600 mb-2" />
                  <span>No notifications received from paired device.</span>
                </div>
              ) : (
                notifications.map((notif) => (
                  <div
                    key={notif.id}
                    className="p-4 bg-black/40 border border-white/10 rounded-xl flex items-start justify-between hover:border-cyan-500/30 transition"
                  >
                    <div className="flex gap-3">
                      <div className="p-2 rounded-lg bg-cyan-500/10 text-cyan-400 mt-0.5">
                        <Bell className="w-4 h-4" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-semibold text-cyan-400">{notif.app}</span>
                          <span className="text-[10px] text-slate-500">• Just now</span>
                        </div>
                        <h4 className="text-sm font-bold text-white mt-0.5">{notif.title}</h4>
                        <p className="text-xs text-slate-400 mt-1">{notif.body}</p>
                      </div>
                    </div>
                    <button
                      onClick={() =>
                        setNotifications((prev) => prev.filter((n) => n.id !== notif.id))
                      }
                      className="p-1 rounded text-slate-500 hover:text-white hover:bg-white/10 transition"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                ))
              )}
            </div>
          )}

        </div>
      </div>
    </div>
  );
};
