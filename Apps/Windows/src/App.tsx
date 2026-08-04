import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export type QuotaMeter = {
  label: string;
  remainingPercent: number | null;
  resetText: string | null;
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
};

export type SnapshotPayload = {
  updatedAt: string;
  cards: QuotaCard[];
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
};

type PathsInfo = {
  settings: string;
  configDir: string;
  logs: string;
  codexAuth: string;
  grokAuth: string;
  minimaxConfig: string;
};

const PROVIDERS = [
  { id: "codex", name: "ChatGPT (Codex)" },
  { id: "minimax", name: "MiniMax" },
  { id: "grok", name: "Grok" },
] as const;

export default function App() {
  const [tab, setTab] = useState<"home" | "settings">("home");
  const [data, setData] = useState<SnapshotPayload | null>(null);
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [paths, setPaths] = useState<PathsInfo | null>(null);
  const [hasMinimaxKey, setHasMinimaxKey] = useState(false);
  const [minimaxKeyInput, setMinimaxKeyInput] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [testMsg, setTestMsg] = useState<Record<string, string>>({});

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const next = await invoke<SnapshotPayload>("get_usage_snapshot");
      setData(next);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const loadSettings = useCallback(async () => {
    try {
      const s = await invoke<AppSettings>("get_settings");
      setSettings(s);
      const has = await invoke<boolean>("has_minimax_api_key");
      setHasMinimaxKey(has);
      const p = await invoke<PathsInfo>("get_paths");
      setPaths(p);
    } catch (e) {
      setError(String(e));
    }
  }, []);

  useEffect(() => {
    void refresh();
    void loadSettings();
  }, [refresh, loadSettings]);

  // Auto refresh
  useEffect(() => {
    const secs = settings?.refreshIntervalSecs ?? 300;
    if (!secs || secs < 30) return;
    const t = window.setInterval(() => void refresh(), secs * 1000);
    return () => window.clearInterval(t);
  }, [settings?.refreshIntervalSecs, refresh]);

  const toggleProvider = async (id: string, enabled: boolean) => {
    const s = await invoke<AppSettings>("set_provider_enabled", {
      providerId: id,
      enabled,
    });
    setSettings(s);
    void refresh();
  };

  const saveMinimaxKey = async () => {
    await invoke("set_minimax_api_key", { apiKey: minimaxKeyInput });
    setMinimaxKeyInput("");
    setHasMinimaxKey(true);
    void refresh();
  };

  const clearMinimaxKey = async () => {
    await invoke("clear_minimax_api_key");
    setHasMinimaxKey(false);
  };

  const setRegion = async (region: string) => {
    const s = await invoke<AppSettings>("set_minimax_region", { region });
    setSettings(s);
    void refresh();
  };

  const testProvider = async (id: string) => {
    setTestMsg((m) => ({ ...m, [id]: "检测中…" }));
    try {
      const r = await invoke<{ ok: boolean; message: string }>("test_provider", {
        providerId: id,
      });
      setTestMsg((m) => ({
        ...m,
        [id]: r.ok ? `✓ ${r.message}` : `✗ ${r.message}`,
      }));
    } catch (e) {
      setTestMsg((m) => ({ ...m, [id]: `✗ ${String(e)}` }));
    }
  };

  const saveRefresh = async (secs: number) => {
    if (!settings) return;
    const next = { ...settings, refreshIntervalSecs: secs };
    await invoke("save_settings", { settings: next });
    setSettings(next);
  };

  return (
    <div className="shell">
      <header className="header">
        <div>
          <h1>智额</h1>
          <p className="tagline">SmartQuota · Windows</p>
        </div>
        <div className="header-actions">
          <button
            type="button"
            className={`tab ${tab === "home" ? "active" : ""}`}
            onClick={() => setTab("home")}
          >
            额度
          </button>
          <button
            type="button"
            className={`tab ${tab === "settings" ? "active" : ""}`}
            onClick={() => setTab("settings")}
          >
            设置
          </button>
          <button type="button" className="btn" onClick={() => void refresh()} disabled={loading}>
            {loading ? "…" : "刷新"}
          </button>
        </div>
      </header>

      {error && <div className="banner error">{error}</div>}

      {tab === "home" && (
        <main className="cards">
          {(data?.cards ?? []).map((card) => (
            <article key={card.providerId} className={`card status-border-${card.status}`}>
              <div className="card-top">
                <div>
                  <strong>{card.displayName}</strong>
                  {card.planLabel ? <span className="plan">{card.planLabel}</span> : null}
                </div>
                <span className={`pill status-${card.status}`}>{statusLabel(card.status)}</span>
              </div>
              {(card.meters?.length ? card.meters : fallbackMeters(card)).map((m) => (
                <Meter key={m.label} label={m.label} value={m.remainingPercent} hint={m.resetText} />
              ))}
              <p className="detail">{card.detail}</p>
            </article>
          ))}
          {!data?.cards?.length && !loading && (
            <p className="empty">暂无数据，点击刷新或检查设置。</p>
          )}
        </main>
      )}

      {tab === "settings" && settings && (
        <main className="settings">
          <section className="block">
            <h2>会员开关</h2>
            {PROVIDERS.map((p) => {
              const enabled =
                settings.providers[p.id]?.enabled ??
                (p.id === "codex" || p.id === "minimax" || p.id === "grok");
              return (
                <label key={p.id} className="row">
                  <span>{p.name}</span>
                  <input
                    type="checkbox"
                    checked={!!enabled}
                    onChange={(e) => void toggleProvider(p.id, e.target.checked)}
                  />
                </label>
              );
            })}
          </section>

          <section className="block">
            <h2>MiniMax</h2>
            <label className="row">
              <span>区域</span>
              <select
                value={settings.minimaxRegion || "china"}
                onChange={(e) => void setRegion(e.target.value)}
              >
                <option value="china">中国</option>
                <option value="international">国际</option>
              </select>
            </label>
            <p className="hint">
              Key 状态：{hasMinimaxKey ? "已保存（凭据管理器）" : "未设置"}
            </p>
            <div className="row-input">
              <input
                type="password"
                placeholder="粘贴 sk-cp-… API Key"
                value={minimaxKeyInput}
                onChange={(e) => setMinimaxKeyInput(e.target.value)}
              />
              <button type="button" className="btn" onClick={() => void saveMinimaxKey()}>
                保存
              </button>
            </div>
            {hasMinimaxKey && (
              <button type="button" className="btn danger" onClick={() => void clearMinimaxKey()}>
                清除 Key
              </button>
            )}
          </section>

          <section className="block">
            <h2>额度检测</h2>
            {PROVIDERS.map((p) => (
              <div key={p.id} className="test-row">
                <button type="button" className="btn" onClick={() => void testProvider(p.id)}>
                  检测 {p.name}
                </button>
                <span className="hint">{testMsg[p.id] ?? ""}</span>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>自动刷新</h2>
            <label className="row">
              <span>间隔（秒，0=仅手动）</span>
              <input
                type="number"
                min={0}
                step={30}
                value={settings.refreshIntervalSecs}
                onChange={(e) => void saveRefresh(Number(e.target.value) || 0)}
                style={{ width: 88 }}
              />
            </label>
          </section>

          <section className="block">
            <h2>本机路径</h2>
            {paths && (
              <ul className="paths">
                <li>
                  <code>配置</code> {paths.configDir}
                </li>
                <li>
                  <code>Codex</code> {paths.codexAuth}
                </li>
                <li>
                  <code>Grok</code> {paths.grokAuth}
                </li>
                <li>
                  <code>MiniMax</code> {paths.minimaxConfig}
                </li>
              </ul>
            )}
            <div className="row-input">
              <button type="button" className="btn" onClick={() => void invoke("open_config_folder")}>
                打开配置目录
              </button>
              <button type="button" className="btn" onClick={() => void invoke("open_logs_dir")}>
                打开日志目录
              </button>
            </div>
          </section>

          <p className="hint footer-note">
            关闭窗口后应用仍在托盘运行。密钥仅存本机，不上传。
          </p>
        </main>
      )}

      <footer className="footer">{data?.updatedAt ? `更新于 ${data.updatedAt}` : "—"}</footer>
    </div>
  );
}

function statusLabel(s: string): string {
  const map: Record<string, string> = {
    healthy: "正常",
    warning: "偏低",
    critical: "紧急",
    depleted: "用尽",
    unknown: "未知",
    error: "错误",
    disabled: "关闭",
  };
  return map[s] ?? s;
}

function fallbackMeters(card: QuotaCard): QuotaMeter[] {
  return [
    { label: "5 小时", remainingPercent: card.sessionRemainingPercent, resetText: null },
    { label: "7 天", remainingPercent: card.weeklyRemainingPercent, resetText: null },
  ];
}

function Meter({
  label,
  value,
  hint,
}: {
  label: string;
  value: number | null | undefined;
  hint?: string | null;
}) {
  const pct = value == null ? null : Math.max(0, Math.min(100, value));
  return (
    <div className="meter">
      <div className="meter-label">
        <span>{label}</span>
        <span>{pct == null ? "—" : `${Math.round(pct)}%`}</span>
      </div>
      <div className="meter-track">
        <div className="meter-fill" style={{ width: pct == null ? "0%" : `${pct}%` }} />
      </div>
      {hint ? <div className="meter-hint">{hint}</div> : null}
    </div>
  );
}
