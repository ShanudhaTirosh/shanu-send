import { AnimatePresence, motion } from "framer-motion";
import { X, Settings as SettingsIcon, ShieldCheck, FolderOpen, Save } from "lucide-react";
import { useEffect, useState } from "react";
import { getSettings, pickSaveFolder, renameDevice, setPin, setSaveDir, type Settings } from "../../lib/tauri";

interface SettingsPanelProps {
  open: boolean;
  onClose: () => void;
}

export function SettingsPanel({ open, onClose }: SettingsPanelProps) {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [aliasDraft, setAliasDraft] = useState("");
  const [pinDraft, setPinDraft] = useState("");
  const [pinEnabled, setPinEnabled] = useState(false);
  const [savedNote, setSavedNote] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    getSettings().then((s) => {
      setSettings(s);
      setAliasDraft(s.alias);
      setPinEnabled(s.pin_enabled);
    });
  }, [open]);

  const saveAlias = async () => {
    if (!settings || aliasDraft.trim() === settings.alias) return;
    await renameDevice(aliasDraft.trim());
    setSavedNote("Saved — restart ShanuSend for the new name to take effect.");
  };

  const togglePin = async (enabled: boolean) => {
    setPinEnabled(enabled);
    if (!enabled) {
      await setPin(null);
      setSavedNote("PIN protection disabled.");
    } else if (pinDraft.trim().length >= 4) {
      await setPin(pinDraft.trim());
      setSavedNote("PIN protection enabled.");
    }
  };

  const savePin = async () => {
    if (pinDraft.trim().length < 4) return;
    await setPin(pinDraft.trim());
    setPinEnabled(true);
    setSavedNote("PIN updated.");
  };

  const chooseFolder = async () => {
    const chosen = await pickSaveFolder();
    if (!chosen) return;
    await setSaveDir(chosen);
    setSettings((prev) => (prev ? { ...prev, save_dir: chosen } : prev));
    setSavedNote("Save folder updated.");
  };

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm"
          />
          <motion.aside
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", stiffness: 320, damping: 32 }}
            className="fixed right-0 top-0 z-50 h-full w-full max-w-sm border-l border-white/10 bg-void-900/95 p-5 backdrop-blur-glass"
          >
            <div className="mb-6 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SettingsIcon size={18} className="text-neon-cyan" />
                <h2 className="text-base font-medium">Settings</h2>
              </div>
              <button onClick={onClose} className="text-slate-400 transition hover:text-slate-100">
                <X size={18} />
              </button>
            </div>

            {!settings ? (
              <p className="text-sm text-slate-500">Loading…</p>
            ) : (
              <div className="flex flex-col gap-6">
                <section className="flex flex-col gap-2">
                  <label className="text-xs uppercase tracking-wide text-slate-500">Device name</label>
                  <div className="flex gap-2">
                    <input
                      value={aliasDraft}
                      onChange={(e) => setAliasDraft(e.target.value)}
                      className="flex-1 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm outline-none focus:border-neon-cyan/50"
                    />
                    <button
                      onClick={saveAlias}
                      className="flex items-center gap-1 rounded-xl border border-white/10 bg-white/5 px-3 text-sm transition hover:bg-white/10"
                    >
                      <Save size={14} />
                    </button>
                  </div>
                </section>

                <section className="flex flex-col gap-2">
                  <label className="text-xs uppercase tracking-wide text-slate-500">Save files to</label>
                  <button
                    onClick={chooseFolder}
                    className="flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-left text-sm text-slate-300 transition hover:bg-white/10"
                  >
                    <FolderOpen size={14} className="shrink-0 text-slate-500" />
                    <span className="truncate">{settings.save_dir}</span>
                  </button>
                </section>

                <section className="flex flex-col gap-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs uppercase tracking-wide text-slate-500">PIN protection</label>
                    <button
                      onClick={() => togglePin(!pinEnabled)}
                      className={`h-6 w-11 rounded-full transition ${
                        pinEnabled ? "bg-neon-cyan/70" : "bg-white/10"
                      }`}
                    >
                      <motion.span
                        animate={{ x: pinEnabled ? 20 : 2 }}
                        className="block h-5 w-5 rounded-full bg-white shadow"
                      />
                    </button>
                  </div>
                  {pinEnabled && (
                    <div className="flex gap-2">
                      <input
                        value={pinDraft}
                        onChange={(e) => setPinDraft(e.target.value.replace(/\D/g, "").slice(0, 8))}
                        placeholder="4–8 digit PIN"
                        inputMode="numeric"
                        className="flex-1 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm outline-none focus:border-neon-cyan/50"
                      />
                      <button
                        onClick={savePin}
                        className="rounded-xl border border-white/10 bg-white/5 px-3 text-sm transition hover:bg-white/10"
                      >
                        Set
                      </button>
                    </div>
                  )}
                  <p className="text-xs text-slate-500">
                    When enabled, other devices must enter this PIN before sending you files.
                  </p>
                </section>

                <section className="flex flex-col gap-2">
                  <label className="flex items-center gap-1.5 text-xs uppercase tracking-wide text-slate-500">
                    <ShieldCheck size={13} />
                    Trusted devices
                  </label>
                  {settings.trusted_fingerprints.length === 0 ? (
                    <p className="text-xs text-slate-500">
                      None yet. Trusted devices skip the accept prompt and receive files automatically.
                    </p>
                  ) : (
                    <ul className="flex flex-col gap-1.5">
                      {settings.trusted_fingerprints.map((fp) => (
                        <li
                          key={fp}
                          className="truncate rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs text-slate-400"
                        >
                          {fp.slice(0, 16)}…
                        </li>
                      ))}
                    </ul>
                  )}
                </section>

                {savedNote && <p className="text-xs text-neon-cyan">{savedNote}</p>}
              </div>
            )}
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}
