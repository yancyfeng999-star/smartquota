import { useCallback, useEffect, useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t, type Lang } from "./i18n";

export type QuotaMeter = {
  key?: string;
  kind?: string;
  label: string;
  remainingPercent: number | null;
  resetText: string | null;
  resetsAtUnix?: number | null;
};

export type QuotaCard = {
  providerId: string;
  displayName: string;
  status: string;
  sessionRemainingPercent: number | null;
  weeklyRemainingPercent: number | null;
  meters: QuotaMeter[];
  planLabel: string;
  detail: string;
  enabled: boolean;
  sourceMode: string;
  isCore?: boolean;
  accountId?: string | null;
  accountEmail?: string | null;
  accountLabel?: string | null;
  accountState?: string | null;
};

export type AlertEvent = {
  providerId: string;
  kind: string;
  message: string;
};

export type SnapshotPayload = {
  updatedAt: string;
  cards: QuotaCard[];
  alerts?: AlertEvent[];
};

export type AppSettings = {
  language: string;
  providers: Record<
    string,
    { enabled?: boolean | null; planLabel?: string; renewalDate?: string }
  >;
  minimaxRegion: string;
  minimaxAuthEnvVar: string;
  refreshIntervalSecs: number;
  quotaThresholdAlertsEnabled?: boolean;
  sessionAlertThreshold?: number;
  weeklyAlertThreshold?: number;
  nearResetAlertHours?: number;
  underuseAlertRemaining?: number;
  providerOrder?: string[];
  windowPinned?: boolean;
  extensionsEnabled?: boolean;
};

export type DetectItem = {
  providerId: string;
  displayName: string;
  mode: string;
  ready: boolean;
  summary: string;
  howTo: string;
};

type CatalogItem = {
  id: string;
  name: string;
  isCore: boolean;
  defaultEnabled: boolean;
};

type PathsInfo = {
  settings: string;
  configDir: string;
  logs: string;
  codexAuth: string;
  grokAuth: string;
  minimaxConfig: string;
  kimiConfig?: string;
  geminiOauth?: string;
  cursorDb?: string;
  claudeJson?: string;
};

type AccountIdentity = {
  providerId: string;
  normalizedEmail?: string | null;
  label: string;
  accountId: string;
};

type ProviderAccountState = {
  identity: AccountIdentity;
  connectionState: string;
  label: string;
  email?: string | null;
  organization?: string | null;
  lastSnapshotJson?: string | null;
  lastSnapshotTime?: string | null;
};

type AccountCoordinator = {
  providerId: string;
  accounts: Record<string, ProviderAccountState>;
  pending: Record<string, ProviderAccountState>;
  activeAccountId?: string | null;
};

type MultiAccountState = {
  coordinators: Record<string, AccountCoordinator>;
};

const REFRESH_OPTIONS = [
  { secs: 0, key: "refreshOff" as const },
  { secs: 300, key: "refresh5" as const },
  { secs: 600, key: "refresh10" as const },
  { secs: 900, key: "refresh15" as const },
  { secs: 1800, key: "refresh30" as const },
];

const EXT_KEY_PROVIDERS = [
  "antigravity",
  "zai",
  "bedrock",
  "alibaba",
  "ampcode",
  "kiro",
  "mistral",
  "opencode-go",
  "omp",
];

export default function App() {
  const [tab, setTab] = useState<"home" | "settings">("home");
  const [data, setData] = useState<SnapshotPayload | null>(null);
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [catalog, setCatalog] = useState<CatalogItem[]>([]);
  const [detect, setDetect] = useState<DetectItem[]>([]);
  const [paths, setPaths] = useState<PathsInfo | null>(null);
  const [hasMinimaxKey, setHasMinimaxKey] = useState(false);
  const [hasKimiKey, setHasKimiKey] = useState(false);
  const [hasGithub, setHasGithub] = useState(false);
  const [extKeyFlags, setExtKeyFlags] = useState<Record<string, boolean>>({});
  const [minimaxKeyInput, setMinimaxKeyInput] = useState("");
  const [kimiKeyInput, setKimiKeyInput] = useState("");
  const [githubInput, setGithubInput] = useState("");
  const [extKeyInput, setExtKeyInput] = useState<Record<string, string>>({});
  const [planDraft, setPlanDraft] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [testMsg, setTestMsg] = useState<Record<string, string>>({});
  const [bannerAlerts, setBannerAlerts] = useState<string[]>([]);
  const [updateChecking, setUpdateChecking] = useState(false);
  const [updateMsg, setUpdateMsg] = useState<string | null>(null);
  const [updateUrl, setUpdateUrl] = useState<string | null>(null);
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [extList, setExtList] = useState<
    { id: string; name: string; version: string; description?: string; path: string; sections: number }[]
  >([]);
  const [accountStates, setAccountStates] = useState<MultiAccountState>({ coordinators: {} });

  const lang = (settings?.language === "en" ? "en" : "zh-Hans") as Lang;
  const i18n = useMemo(() => t(lang), [lang]);

  const providers = catalog.length
    ? catalog
    : [
        { id: "codex", name: "ChatGPT (Codex)", isCore: true, defaultEnabled: true },
        { id: "kimi", name: "Kimi", isCore: true, defaultEnabled: true },
        { id: "minimax", name: "MiniMax", isCore: true, defaultEnabled: true },
        { id: "grok", name: "Grok", isCore: true, defaultEnabled: true },
      ];

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [next, det] = await Promise.all([
        invoke<SnapshotPayload>("get_usage_snapshot"),
        invoke<DetectItem[]>("detect_credentials"),
      ]);
      setData(next);
      setDetect(det);
      if (next.alerts?.length) {
        setBannerAlerts(next.alerts.map((a) => a.message));
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const checkUpdate = useCallback(async () => {
    setUpdateChecking(true);
    setUpdateMsg(null);
    setUpdateUrl(null);
    setUpdateAvailable(false);
    try {
      const r = await invoke<{
        currentVersion: string;
        status: string;
        latestVersion: string | null;
        message: string;
        openUrl: string | null;
      }>("check_for_update");
      setUpdateMsg(r.message);
      setUpdateAvailable(r.status === "available");
      setUpdateUrl(r.openUrl);
    } catch (e) {
      setUpdateMsg(String(e));
    } finally {
      setUpdateChecking(false);
    }
  }, []);

  const loadSettings = useCallback(async () => {
    try {
      const [s, cat] = await Promise.all([
        invoke<AppSettings>("get_settings"),
        invoke<CatalogItem[]>("get_catalog"),
      ]);
      setSettings(s);
      setCatalog(cat);
      const drafts: Record<string, string> = {};
      for (const p of cat) {
        drafts[p.id] = s.providers[p.id]?.planLabel ?? "";
      }
      setPlanDraft(drafts);
      setHasMinimaxKey(await invoke<boolean>("has_minimax_api_key"));
      setHasKimiKey(await invoke<boolean>("has_kimi_api_key"));
      setHasGithub(await invoke<boolean>("has_github_token"));
      const flags: Record<string, boolean> = {};
      for (const id of EXT_KEY_PROVIDERS) {
        flags[id] = await invoke<boolean>("has_provider_api_key", { providerId: id });
      }
      setExtKeyFlags(flags);
      setPaths(await invoke<PathsInfo>("get_paths"));
      setDetect(await invoke<DetectItem[]>("detect_credentials"));
      try {
        setExtList(await invoke("list_extensions"));
      } catch {
        setExtList([]);
      }
      try {
        setAccountStates(await invoke<MultiAccountState>("get_account_states"));
      } catch {
        setAccountStates({ coordinators: {} });
      }
    } catch (e) {
      setError(String(e));
    }
  }, []);

  useEffect(() => {
    void refresh();
    void loadSettings();
  }, [refresh, loadSettings]);

  useEffect(() => {
    const secs = settings?.refreshIntervalSecs ?? 900;
    if (!secs || secs < 60) return;
    const tmr = window.setInterval(() => void refresh(), secs * 1000);
    return () => window.clearInterval(tmr);
  }, [settings?.refreshIntervalSecs, refresh]);

  const isEnabled = (id: string) => {
    const p = settings?.providers[id]?.enabled;
    if (p != null) return !!p;
    return catalog.find((c) => c.id === id)?.defaultEnabled ?? true;
  };

  const toggleProvider = async (id: string, enabled: boolean) => {
    const s = await invoke<AppSettings>("set_provider_enabled", {
      providerId: id,
      enabled,
    });
    setSettings(s);
    void refresh();
  };

  const savePlan = async (id: string) => {
    const s = await invoke<AppSettings>("set_plan_label", {
      providerId: id,
      planLabel: (planDraft[id] ?? "").trim(),
    });
    setSettings(s);
    void refresh();
  };

  const saveMinimaxKey = async () => {
    const key = minimaxKeyInput.trim();
    if (!key) return;
    await invoke("set_minimax_api_key", { apiKey: key });
    setMinimaxKeyInput("");
    setHasMinimaxKey(true);
    void refresh();
    void loadSettings();
  };

  const saveKimiKey = async () => {
    const key = kimiKeyInput.trim();
    if (!key) return;
    await invoke("set_kimi_api_key", { apiKey: key });
    setKimiKeyInput("");
    setHasKimiKey(true);
    void refresh();
  };

  const saveGithub = async () => {
    const key = githubInput.trim();
    if (!key) return;
    await invoke("set_github_token", { token: key });
    setGithubInput("");
    setHasGithub(true);
    void refresh();
  };

  const saveExtKey = async (id: string) => {
    const key = (extKeyInput[id] ?? "").trim();
    if (!key) return;
    await invoke("set_provider_api_key", { providerId: id, apiKey: key });
    setExtKeyInput((m) => ({ ...m, [id]: "" }));
    setExtKeyFlags((f) => ({ ...f, [id]: true }));
    void refresh();
  };

  const setRegion = async (region: string) => {
    const s = await invoke<AppSettings>("set_minimax_region", { region });
    setSettings(s);
    void refresh();
  };

  const testProvider = async (id: string) => {
    setTestMsg((m) => ({ ...m, [id]: "…" }));
    try {
      const r = await invoke<{ ok: boolean; message: string }>("test_provider", {
        providerId: id,
      });
      setTestMsg((m) => ({
        ...m,
        [id]: r.ok ? `✓ ${r.message}` : `✗ ${r.message}`,
      }));
      void refresh();
    } catch (e) {
      setTestMsg((m) => ({ ...m, [id]: `✗ ${String(e)}` }));
    }
  };

  const patchSettings = async (patch: Partial<AppSettings>) => {
    if (!settings) return;
    const next = { ...settings, ...patch };
    await invoke("save_settings", { settings: next });
    setSettings(next);
  };

  // Account management helpers
  const confirmAccount = async (providerId: string, accountId: string) => {
    const s = await invoke<MultiAccountState>("confirm_account", { providerId, accountId });
    setAccountStates(s);
    void refresh();
  };

  const ignoreAccount = async (providerId: string, accountId: string) => {
    const s = await invoke<MultiAccountState>("ignore_account", { providerId, accountId });
    setAccountStates(s);
  };

  const signOutAccount = async (providerId: string, accountId: string) => {
    const s = await invoke<MultiAccountState>("sign_out_account", { providerId, accountId });
    setAccountStates(s);
    void refresh();
  };

  const selectAccount = async (providerId: string, accountId: string) => {
    const s = await invoke<MultiAccountState>("select_account", { providerId, accountId });
    setAccountStates(s);
    void refresh();
  };

  const deleteAccount = async (providerId: string, accountId: string) => {
    const s = await invoke<MultiAccountState>("delete_account", { providerId, accountId });
    setAccountStates(s);
    void refresh();
  };

  const getCoordinator = (providerId: string): AccountCoordinator | null => {
    return accountStates.coordinators[providerId] ?? null;
  };

  const pendingAccounts = (): Array<{ providerId: string; account: ProviderAccountState }> => {
    const result: Array<{ providerId: string; account: ProviderAccountState }> = [];
    for (const [pid, coord] of Object.entries(accountStates.coordinators)) {
      for (const acct of Object.values(coord.pending)) {
        result.push({ providerId: pid, account: acct });
      }
    }
    return result;
  };

  // Home: only enabled memberships, ordered by settings.providerOrder.
  const visibleCards = (() => {
    const enabled = (data?.cards ?? []).filter((c) => c.enabled);
    const order = settings?.providerOrder ?? [];
    if (!order.length) return enabled;
    const rank = (id: string) => {
      const i = order.indexOf(id);
      return i < 0 ? 999 : i;
    };
    return [...enabled].sort((a, b) => rank(a.providerId) - rank(b.providerId));
  })();

  return (
    <div className="shell">
      <header className="header">
        <div>
          <h1>{i18n.title}</h1>
          <p className="tagline">{i18n.tagline}</p>
        </div>
        <div className="header-actions">
          <button
            type="button"
            className={`tab ${tab === "home" ? "active" : ""}`}
            onClick={() => setTab("home")}
          >
            {i18n.tabHome}
          </button>
          <button
            type="button"
            className={`tab ${tab === "settings" ? "active" : ""}`}
            onClick={() => setTab("settings")}
          >
            {i18n.tabSettings}
          </button>
          <button type="button" className="btn" onClick={() => void refresh()} disabled={loading}>
            {loading ? i18n.loading : i18n.refresh}
          </button>
        </div>
      </header>

      <p className="product-tip">{i18n.tip}</p>

      {error && <div className="banner error">{error}</div>}
      {bannerAlerts.map((msg) => (
        <div key={msg} className="banner warn">
          {msg}
        </div>
      ))}
      {pendingAccounts().map(({ providerId, account }) => (
        <div key={account.identity.accountId} className="banner pending-account">
          <span>
            {i18n.accountPendingTitle}: {account.email ?? account.label}
          </span>
          <button type="button" className="btn" onClick={() => void confirmAccount(providerId, account.identity.accountId)}>
            {i18n.accountConfirm}
          </button>
          <button type="button" className="btn btn-ghost" onClick={() => void ignoreAccount(providerId, account.identity.accountId)}>
            {i18n.accountIgnore}
          </button>
        </div>
      ))}

      {tab === "home" && (
        <main className="cards">
          {visibleCards.map((card) => (
            <article key={card.providerId} className={`card status-border-${card.status}`}>
              <div className="card-top">
                <div>
                  <strong>{card.displayName}</strong>
                  {card.accountEmail ? (
                    <span className="account-email">{card.accountEmail}</span>
                  ) : null}
                  {card.isCore ? (
                    <span className="src src-auto">{i18n.core}</span>
                  ) : (
                    <span className="src src-none">{i18n.ext}</span>
                  )}
                  {card.planLabel ? <span className="plan">{card.planLabel}</span> : null}
                  <span className={`src src-${card.sourceMode}`}>
                    {i18n.source[card.sourceMode] ?? card.sourceMode}
                  </span>
                </div>
                <span className={`pill status-${card.status}`}>
                  {i18n.status[card.status] ?? card.status}
                </span>
              </div>
              {card.status === "disabled" ? (
                <p className="detail setup">{card.detail}</p>
              ) : (
                <>
                  {/* 全渠道统一：5H · 7D · 总额（真月额度优先，否则续费日线性递减） */}
                  {primaryMeters(card, settings?.providers?.[card.providerId]?.renewalDate).map(
                    (m) => (
                      <Meter
                        key={m.key || m.label}
                        label={m.label}
                        value={m.remainingPercent}
                        hint={m.resetText}
                        urgency={resetUrgency(
                          m.resetsAtUnix,
                          settings?.nearResetAlertHours ?? 24
                        )}
                      />
                    )
                  )}
                  <p className="detail">{card.detail}</p>
                </>
              )}
              {(card.status === "setup" || card.status === "error") && (
                <button type="button" className="btn linkish" onClick={() => setTab("settings")}>
                  {i18n.goSettings}
                </button>
              )}
            </article>
          ))}
          {!visibleCards.length && !loading && <p className="empty">{i18n.empty}</p>}
        </main>
      )}

      {tab === "settings" && settings && (
        <main className="settings">
          <section className="block">
            <h2>{i18n.language}</h2>
            <label className="row">
              <span>UI</span>
              <select
                value={settings.language || "zh-Hans"}
                onChange={(e) => void patchSettings({ language: e.target.value })}
              >
                <option value="zh-Hans">简体中文</option>
                <option value="en">English</option>
              </select>
            </label>
          </section>

          <section className="block intro">
            <h2>{i18n.howtoTitle}</h2>
            <ol className="howto">
              <li>{i18n.howto1}</li>
              <li>{i18n.howto2}</li>
              <li>{i18n.howto3}</li>
            </ol>
          </section>

          <section className="block">
            <h2>{i18n.detectTitle}</h2>
            {detect.map((d) => (
              <div key={d.providerId} className={`detect-row mode-${d.mode}`}>
                <div className="detect-head">
                  <strong>{d.displayName}</strong>
                  <span className={`src src-${d.mode}`}>{i18n.source[d.mode] ?? d.mode}</span>
                </div>
                <p className="hint">{d.summary}</p>
                <p className="detail">{d.howTo}</p>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>{i18n.membersTitle}</h2>
            <p className="hint">{i18n.membersHint}</p>
            {providers.map((p) => (
              <label key={p.id} className="row">
                <span>
                  {p.name}{" "}
                  <span className={`src ${p.isCore ? "src-auto" : "src-none"}`}>
                    {p.isCore ? i18n.core : i18n.ext}
                  </span>
                </span>
                <input
                  type="checkbox"
                  checked={isEnabled(p.id)}
                  onChange={(e) => void toggleProvider(p.id, e.target.checked)}
                />
              </label>
            ))}
          </section>

          <section className="block">
            <h2>{i18n.accountsTitle}</h2>
            <p className="hint">{i18n.accountsHint}</p>
            {providers.map((p) => {
              const coord = getCoordinator(p.id);
              const allAccounts = coord
                ? [...Object.values(coord.accounts), ...Object.values(coord.pending)]
                : [];
              return (
                <div key={p.id} className="account-provider-block">
                  <h3 className="subh">{p.name}</h3>
                  {allAccounts.length === 0 ? (
                    <p className="hint">{i18n.noAccounts}</p>
                  ) : (
                    allAccounts.map((acct) => {
                      const isActive = coord?.activeAccountId === acct.identity.accountId;
                      const isPending = acct.connectionState === "pendingConfirmation";
                      const isDisconnected = acct.connectionState === "disconnected";
                      return (
                        <div key={acct.identity.accountId} className={`account-row state-${acct.connectionState}`}>
                          <div className="account-info">
                            <strong>{acct.label || acct.email || acct.identity.accountId}</strong>
                            {acct.email && <span className="hint">{acct.email}</span>}
                            {isActive && <span className="pill account-active">{i18n.accountActive}</span>}
                            {isPending && <span className="pill account-pending">{i18n.accountPending}</span>}
                            {isDisconnected && <span className="pill account-disconnected">{i18n.accountDisconnected}</span>}
                          </div>
                          <div className="account-actions">
                            {isPending && (
                              <>
                                <button type="button" className="btn" onClick={() => void confirmAccount(p.id, acct.identity.accountId)}>
                                  {i18n.accountConfirm}
                                </button>
                                <button type="button" className="btn btn-ghost" onClick={() => void ignoreAccount(p.id, acct.identity.accountId)}>
                                  {i18n.accountIgnore}
                                </button>
                              </>
                            )}
                            {!isPending && !isActive && !isDisconnected && (
                              <button type="button" className="btn" onClick={() => void selectAccount(p.id, acct.identity.accountId)}>
                                {i18n.accountSelect}
                              </button>
                            )}
                            {!isPending && !isDisconnected && (
                              <button type="button" className="btn btn-ghost" onClick={() => void signOutAccount(p.id, acct.identity.accountId)}>
                                {i18n.accountSignOut}
                              </button>
                            )}
                            <button type="button" className="btn danger" onClick={() => void deleteAccount(p.id, acct.identity.accountId)}>
                              {i18n.accountDelete}
                            </button>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              );
            })}
          </section>

          <section className="block">
            <h2>{i18n.planTitle}</h2>
            {providers.map((p) => (
              <div key={p.id} className="row-input plan-row">
                <span className="plan-id">{p.name}</span>
                <input
                  type="text"
                  placeholder={i18n.planPlaceholder}
                  value={planDraft[p.id] ?? ""}
                  onChange={(e) => setPlanDraft((d) => ({ ...d, [p.id]: e.target.value }))}
                />
                <button type="button" className="btn" onClick={() => void savePlan(p.id)}>
                  {i18n.save}
                </button>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>{i18n.keysTitle}</h2>

            <h3 className="subh">{i18n.kimiTitle}</h3>
            <p className="hint">{hasKimiKey ? i18n.hasKey : i18n.kimiHint}</p>
            <div className="row-input">
              <input
                type="password"
                autoComplete="off"
                placeholder="sk-kimi-…"
                value={kimiKeyInput}
                onChange={(e) => setKimiKeyInput(e.target.value)}
              />
              <button type="button" className="btn" onClick={() => void saveKimiKey()}>
                {i18n.save}
              </button>
            </div>
            {hasKimiKey && (
              <button
                type="button"
                className="btn danger"
                onClick={() =>
                  void invoke("clear_kimi_api_key").then(() => {
                    setHasKimiKey(false);
                    void refresh();
                  })
                }
              >
                {i18n.clearKey}
              </button>
            )}

            <h3 className="subh">{i18n.minimaxTitle}</h3>
            <label className="row">
              <span>{i18n.region}</span>
              <select
                value={settings.minimaxRegion || "china"}
                onChange={(e) => void setRegion(e.target.value)}
              >
                <option value="china">{i18n.china}</option>
                <option value="international">{i18n.international}</option>
              </select>
            </label>
            <p className="hint">{hasMinimaxKey ? i18n.hasKey : i18n.noKey}</p>
            <div className="row-input">
              <input
                type="password"
                autoComplete="off"
                placeholder={i18n.minimaxKeyPh}
                value={minimaxKeyInput}
                onChange={(e) => setMinimaxKeyInput(e.target.value)}
              />
              <button type="button" className="btn" onClick={() => void saveMinimaxKey()}>
                {i18n.save}
              </button>
            </div>
            {hasMinimaxKey && (
              <button
                type="button"
                className="btn danger"
                onClick={() =>
                  void invoke("clear_minimax_api_key").then(() => {
                    setHasMinimaxKey(false);
                    void refresh();
                  })
                }
              >
                {i18n.clearKey}
              </button>
            )}

            <h3 className="subh">{i18n.githubTitle}</h3>
            <p className="hint">{hasGithub ? i18n.hasKey : i18n.noKey}</p>
            <div className="row-input">
              <input
                type="password"
                autoComplete="off"
                placeholder={i18n.githubPh}
                value={githubInput}
                onChange={(e) => setGithubInput(e.target.value)}
              />
              <button type="button" className="btn" onClick={() => void saveGithub()}>
                {i18n.save}
              </button>
            </div>
            {hasGithub && (
              <button
                type="button"
                className="btn danger"
                onClick={() =>
                  void invoke("clear_github_token").then(() => {
                    setHasGithub(false);
                    void refresh();
                  })
                }
              >
                {i18n.clearKey}
              </button>
            )}

            <h3 className="subh">{i18n.extKeyTitle}</h3>
            {EXT_KEY_PROVIDERS.map((id) => (
              <div key={id} className="ext-key-block">
                <div className="row">
                  <span>{id}</span>
                  <span className="hint">{extKeyFlags[id] ? i18n.hasKey : i18n.noKey}</span>
                </div>
                <div className="row-input">
                  <input
                    type="password"
                    autoComplete="off"
                    placeholder="API Key"
                    value={extKeyInput[id] ?? ""}
                    onChange={(e) => setExtKeyInput((m) => ({ ...m, [id]: e.target.value }))}
                  />
                  <button type="button" className="btn" onClick={() => void saveExtKey(id)}>
                    {i18n.save}
                  </button>
                </div>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>{i18n.testTitle}</h2>
            {providers.map((p) => (
              <div key={p.id} className="test-row">
                <button type="button" className="btn" onClick={() => void testProvider(p.id)}>
                  {i18n.test} {p.name}
                </button>
                <span className="hint">{testMsg[p.id] ?? ""}</span>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>{i18n.refreshTitle}</h2>
            <label className="row">
              <span> </span>
              <select
                value={nearestRefresh(settings.refreshIntervalSecs)}
                onChange={(e) =>
                  void patchSettings({ refreshIntervalSecs: Number(e.target.value) })
                }
              >
                {REFRESH_OPTIONS.map((o) => (
                  <option key={o.secs} value={o.secs}>
                    {i18n[o.key]}
                  </option>
                ))}
              </select>
            </label>
          </section>

          <section className="block">
            <h2>{i18n.alertsTitle}</h2>
            <label className="row">
              <span>{i18n.alertsEnable}</span>
              <input
                type="checkbox"
                checked={settings.quotaThresholdAlertsEnabled ?? true}
                onChange={(e) =>
                  void patchSettings({ quotaThresholdAlertsEnabled: e.target.checked })
                }
              />
            </label>
            <label className="row">
              <span>{i18n.sessionTh}</span>
              <input
                type="number"
                min={1}
                max={100}
                style={{ width: 72 }}
                value={settings.sessionAlertThreshold ?? 20}
                onChange={(e) =>
                  void patchSettings({ sessionAlertThreshold: Number(e.target.value) || 20 })
                }
              />
            </label>
            <label className="row">
              <span>{i18n.weeklyTh}</span>
              <input
                type="number"
                min={1}
                max={100}
                style={{ width: 72 }}
                value={settings.weeklyAlertThreshold ?? 20}
                onChange={(e) =>
                  void patchSettings({ weeklyAlertThreshold: Number(e.target.value) || 20 })
                }
              />
            </label>
            <label className="row">
              <span>{i18n.nearReset}</span>
              <input
                type="number"
                min={1}
                max={168}
                style={{ width: 72 }}
                value={settings.nearResetAlertHours ?? 24}
                onChange={(e) =>
                  void patchSettings({ nearResetAlertHours: Number(e.target.value) || 24 })
                }
              />
            </label>
            <label className="row">
              <span>{i18n.underuse}</span>
              <input
                type="number"
                min={1}
                max={100}
                style={{ width: 72 }}
                value={settings.underuseAlertRemaining ?? 40}
                onChange={(e) =>
                  void patchSettings({ underuseAlertRemaining: Number(e.target.value) || 40 })
                }
              />
            </label>
          </section>

          <section className="block">
            <h2>固定窗口 / 排序</h2>
            <label className="row">
              <span>窗口置顶（固定）</span>
              <input
                type="checkbox"
                checked={!!settings.windowPinned}
                onChange={(e) =>
                  void invoke<AppSettings>("set_window_pinned", { pinned: e.target.checked }).then(
                    setSettings
                  )
                }
              />
            </label>
            <p className="hint">拖拽排序：使用 ↑ ↓ 调整主页卡片顺序</p>
            {providers.map((p, idx) => (
              <div key={p.id} className="row-input plan-row">
                <span className="plan-id">
                  {idx + 1}. {p.name}
                </span>
                <button
                  type="button"
                  className="btn"
                  disabled={idx === 0}
                  onClick={() => {
                    const order = (settings.providerOrder?.length
                      ? [...settings.providerOrder]
                      : providers.map((x) => x.id));
                    // ensure all
                    for (const x of providers) if (!order.includes(x.id)) order.push(x.id);
                    const i = order.indexOf(p.id);
                    if (i > 0) {
                      [order[i - 1], order[i]] = [order[i], order[i - 1]];
                      void invoke<AppSettings>("set_provider_order", { order }).then((s) => {
                        setSettings(s);
                        void refresh();
                      });
                    }
                  }}
                >
                  ↑
                </button>
                <button
                  type="button"
                  className="btn"
                  disabled={idx >= providers.length - 1}
                  onClick={() => {
                    const order = (settings.providerOrder?.length
                      ? [...settings.providerOrder]
                      : providers.map((x) => x.id));
                    for (const x of providers) if (!order.includes(x.id)) order.push(x.id);
                    const i = order.indexOf(p.id);
                    if (i >= 0 && i < order.length - 1) {
                      [order[i + 1], order[i]] = [order[i], order[i + 1]];
                      void invoke<AppSettings>("set_provider_order", { order }).then((s) => {
                        setSettings(s);
                        void refresh();
                      });
                    }
                  }}
                >
                  ↓
                </button>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>用户扩展</h2>
            <label className="row">
              <span>启用 ~/.smartquota/extensions</span>
              <input
                type="checkbox"
                checked={settings.extensionsEnabled ?? true}
                onChange={(e) => void patchSettings({ extensionsEnabled: e.target.checked })}
              />
            </label>
            {extList.length === 0 ? (
              <p className="hint">暂无扩展。在扩展目录放置 manifest.json + 脚本。</p>
            ) : (
              extList.map((ex) => (
                <div key={ex.id} className="detect-row">
                  <strong>
                    {ex.name} <span className="hint">v{ex.version}</span>
                  </strong>
                  <p className="detail">{ex.description || ex.path}</p>
                </div>
              ))
            )}
            <button
              type="button"
              className="btn"
              onClick={() => void invoke("open_extensions_folder")}
            >
              打开扩展目录
            </button>
          </section>

          <section className="block">
            <h2>{i18n.updateTitle}</h2>
            <p className="hint">{i18n.updateHint}</p>
            <div className="row-input">
              <button
                type="button"
                className="btn"
                disabled={updateChecking}
                onClick={() => void checkUpdate()}
              >
                {updateChecking ? "…" : i18n.checkUpdate}
              </button>
              {updateAvailable && updateUrl && (
                <button
                  type="button"
                  className="btn"
                  onClick={() => void invoke("open_external_url", { url: updateUrl })}
                >
                  {i18n.download}
                </button>
              )}
            </div>
            {updateMsg && <p className="detail">{updateMsg}</p>}
          </section>

          <section className="block">
            <h2>{i18n.pathsTitle}</h2>
            {paths && (
              <ul className="paths">
                <li>
                  <code>config</code> {paths.configDir}
                </li>
                <li>
                  <code>codex</code> {paths.codexAuth}
                </li>
                <li>
                  <code>grok</code> {paths.grokAuth}
                </li>
                <li>
                  <code>minimax</code> {paths.minimaxConfig}
                </li>
                {paths.kimiConfig && (
                  <li>
                    <code>kimi</code> {paths.kimiConfig}
                  </li>
                )}
                {paths.geminiOauth && (
                  <li>
                    <code>gemini</code> {paths.geminiOauth}
                  </li>
                )}
                {paths.cursorDb && (
                  <li>
                    <code>cursor</code> {paths.cursorDb}
                  </li>
                )}
                {paths.claudeJson && (
                  <li>
                    <code>claude</code> {paths.claudeJson}
                  </li>
                )}
              </ul>
            )}
            <div className="row-input">
              <button type="button" className="btn" onClick={() => void invoke("open_config_folder")}>
                {i18n.openConfig}
              </button>
              <button type="button" className="btn" onClick={() => void invoke("open_logs_dir")}>
                {i18n.openLogs}
              </button>
            </div>
          </section>
        </main>
      )}

      <footer className="footer">
        {data?.updatedAt ? `${i18n.updatedAt} ${data.updatedAt}` : "—"} · v0.5.0
      </footer>
    </div>
  );
}

function nearestRefresh(secs: number): number {
  if (!secs) return 0;
  const opts = [300, 600, 900, 1800];
  return opts.reduce((a, b) => (Math.abs(b - secs) < Math.abs(a - secs) ? b : a));
}

/** 5H · 7D · 总额 — same policy as Mac for every provider. */
function primaryMeters(card: QuotaCard, renewalDate?: string | null): QuotaMeter[] {
  const meters = card.meters ?? [];

  const session =
    meters.find((m) => m.kind === "session" || m.key === "session") ??
    ({
      key: "session",
      kind: "session",
      label: "5H",
      remainingPercent: card.sessionRemainingPercent,
      resetText: null,
    } satisfies QuotaMeter);

  const weekly =
    meters.find((m) => m.kind === "weekly" || m.key === "weekly") ??
    ({
      key: "weekly",
      kind: "weekly",
      label: "7D",
      remainingPercent: card.weeklyRemainingPercent,
      resetText: null,
    } satisfies QuotaMeter);

  const realMonthly = meters.find((m) => isRealMonthlyMeter(m));
  const monthly: QuotaMeter = realMonthly
    ? { ...realMonthly, key: realMonthly.key || "monthly", label: "总额" }
    : calendarMonthlyMeter(renewalDate);

  return [
    { ...session, label: "5H" },
    { ...weekly, label: "7D" },
    monthly,
  ];
}

function isRealMonthlyMeter(m: QuotaMeter): boolean {
  const label = (m.label || "").toLowerCase();
  const key = (m.key || "").toLowerCase();
  const kind = (m.kind || "").toLowerCase();
  if (kind === "session" || kind === "weekly" || key === "session" || key === "weekly") {
    return false;
  }
  // Explicit monthly only — do not treat bare "billing" as monthly
  if (kind === "monthly" || key.includes("month") || key.includes("月")) return true;
  if (label.includes("month") || label.includes("月") || label.includes("本月") || label.includes("月度"))
    return true;
  return false;
}

/** remaining% = daysLeft / cycleDays × 100 to next renewal (or end of calendar month). */
function calendarMonthlyMeter(renewalDate?: string | null): QuotaMeter {
  const now = new Date();
  const today = startOfLocalDay(now);
  let renewDay: Date;
  if (renewalDate && renewalDate.trim()) {
    const activation = parseYmd(renewalDate.trim());
    renewDay = activation ? nextRenewal(activation, today) : endOfLocalMonth(today);
  } else {
    renewDay = endOfLocalMonth(today);
  }
  const cycleStart = addMonths(renewDay, -1);
  const cycleDays = Math.max(1, daysBetween(cycleStart, renewDay));
  const daysLeft = renewDay.getTime() <= today.getTime() ? 0 : daysBetween(today, renewDay);
  const remaining = Math.max(0, Math.min(100, (100 * daysLeft) / cycleDays));
  const y = renewDay.getFullYear();
  const mo = String(renewDay.getMonth() + 1).padStart(2, "0");
  const d = String(renewDay.getDate()).padStart(2, "0");
  return {
    key: "monthly-est",
    kind: "time",
    label: "总额",
    remainingPercent: remaining,
    resetText: `${y}-${mo}-${d}`,
    resetsAtUnix: Math.floor(renewDay.getTime() / 1000),
  };
}

function parseYmd(raw: string): Date | null {
  const m = raw.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : startOfLocalDay(d);
}

function startOfLocalDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function endOfLocalMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0);
}

function addMonths(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth() + n, d.getDate());
}

/** Next calendar-month anniversary on or after today (activation day-of-month). */
function nextRenewal(activation: Date, today: Date): Date {
  let candidate = startOfLocalDay(activation);
  if (candidate.getTime() > today.getTime()) return candidate;
  while (candidate.getTime() < today.getTime()) {
    candidate = addMonths(candidate, 1);
  }
  return candidate;
}

function daysBetween(from: Date, to: Date): number {
  const ms = startOfLocalDay(to).getTime() - startOfLocalDay(from).getTime();
  return Math.round(ms / 86_400_000);
}

function resetUrgency(unix: number | null | undefined, nearHours: number): string {
  if (unix == null) return "normal";
  const hours = (unix - Date.now() / 1000) / 3600;
  if (hours <= 0 || hours <= 6) return "imminent";
  if (hours <= nearHours) return "soon";
  return "normal";
}

function Meter({
  label,
  value,
  hint,
  urgency = "normal",
}: {
  label: string;
  value: number | null | undefined;
  hint?: string | null;
  urgency?: string;
}) {
  const pct = value == null ? null : Math.max(0, Math.min(100, value));
  return (
    <div className={`meter urgency-${urgency}`}>
      <div className="meter-label">
        <span>{label}</span>
        <span>{pct == null ? "—" : `${Math.round(pct)}%`}</span>
      </div>
      <div className="meter-track">
        <div className="meter-fill" style={{ width: pct == null ? "0%" : `${pct}%` }} />
      </div>
      {hint ? <div className={`meter-hint urgency-${urgency}`}>{hint}</div> : null}
    </div>
  );
}
