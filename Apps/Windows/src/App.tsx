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
  sourceMode: string;
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

export type DetectItem = {
  providerId: string;
  displayName: string;
  mode: string;
  ready: boolean;
  summary: string;
  howTo: string;
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
  const [detect, setDetect] = useState<DetectItem[]>([]);
  const [paths, setPaths] = useState<PathsInfo | null>(null);
  const [hasMinimaxKey, setHasMinimaxKey] = useState(false);
  const [minimaxKeyInput, setMinimaxKeyInput] = useState("");
  const [planDraft, setPlanDraft] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [testMsg, setTestMsg] = useState<Record<string, string>>({});

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
      const drafts: Record<string, string> = {};
      for (const p of PROVIDERS) {
        drafts[p.id] = s.providers[p.id]?.planLabel ?? "";
      }
      setPlanDraft(drafts);
      setHasMinimaxKey(await invoke<boolean>("has_minimax_api_key"));
      setPaths(await invoke<PathsInfo>("get_paths"));
      setDetect(await invoke<DetectItem[]>("detect_credentials"));
    } catch (e) {
      setError(String(e));
    }
  }, []);

  useEffect(() => {
    void refresh();
    void loadSettings();
  }, [refresh, loadSettings]);

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

  const clearMinimaxKey = async () => {
    await invoke("clear_minimax_api_key");
    setHasMinimaxKey(false);
    void refresh();
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
      void refresh();
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
          <p className="tagline">本机额度监控 · 不预置账号</p>
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

      <p className="product-tip">
        能识别本机 CLI 登录就自动查额度；识别不到请到「设置」自行填写。软件不保存开发者信息，只使用你本机的配置。
      </p>

      {error && <div className="banner error">{error}</div>}

      {tab === "home" && (
        <main className="cards">
          {(data?.cards ?? []).map((card) => (
            <article key={card.providerId} className={`card status-border-${card.status}`}>
              <div className="card-top">
                <div>
                  <strong>{card.displayName}</strong>
                  {card.planLabel ? <span className="plan">{card.planLabel}</span> : null}
                  <span className={`src src-${card.sourceMode}`}>{sourceLabel(card.sourceMode)}</span>
                </div>
                <span className={`pill status-${card.status}`}>{statusLabel(card.status)}</span>
              </div>
              {card.status === "setup" || card.status === "error" || card.status === "disabled" ? (
                <p className="detail setup">{card.detail}</p>
              ) : (
                <>
                  {(card.meters?.length ? card.meters : fallbackMeters(card)).map((m) => (
                    <Meter
                      key={m.label}
                      label={m.label}
                      value={m.remainingPercent}
                      hint={m.resetText}
                    />
                  ))}
                  <p className="detail">{card.detail}</p>
                </>
              )}
              {(card.status === "setup" || card.status === "error") && (
                <button type="button" className="btn linkish" onClick={() => setTab("settings")}>
                  去设置配置 →
                </button>
              )}
            </article>
          ))}
          {!data?.cards?.length && !loading && (
            <p className="empty">暂无数据，点击刷新。</p>
          )}
        </main>
      )}

      {tab === "settings" && settings && (
        <main className="settings">
          <section className="block intro">
            <h2>使用方式</h2>
            <ol className="howto">
              <li>
                <strong>自动识别</strong>：本机已有 Codex / Grok 登录文件时，打开开关即可查额度。
              </li>
              <li>
                <strong>手动填写</strong>：MiniMax 等需要 Key 的，在下方粘贴你自己的 Key。
              </li>
              <li>
                <strong>套餐名</strong>：仅展示用，可随便写；不写也可以。
              </li>
            </ol>
          </section>

          <section className="block">
            <h2>本机识别状态</h2>
            {detect.map((d) => (
              <div key={d.providerId} className={`detect-row mode-${d.mode}`}>
                <div className="detect-head">
                  <strong>{d.displayName}</strong>
                  <span className={`src src-${d.mode}`}>{sourceLabel(d.mode)}</span>
                </div>
                <p className="hint">{d.summary}</p>
                <p className="detail">{d.howTo}</p>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>会员开关</h2>
            {PROVIDERS.map((p) => {
              const enabled =
                settings.providers[p.id]?.enabled ?? true;
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
            <h2>套餐显示名（可选，你自己填）</h2>
            {PROVIDERS.map((p) => (
              <div key={p.id} className="row-input plan-row">
                <span className="plan-id">{p.name}</span>
                <input
                  type="text"
                  placeholder="例如 Plus / Pro（仅展示）"
                  value={planDraft[p.id] ?? ""}
                  onChange={(e) =>
                    setPlanDraft((d) => ({ ...d, [p.id]: e.target.value }))
                  }
                />
                <button type="button" className="btn" onClick={() => void savePlan(p.id)}>
                  保存
                </button>
              </div>
            ))}
          </section>

          <section className="block">
            <h2>MiniMax（需自行填写 Key）</h2>
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
              {hasMinimaxKey
                ? "已保存你填写的 Key（仅本机凭据管理器，可清除）"
                : "尚未填写 Key — 识别不到时请粘贴你的 sk-cp-…"}
            </p>
            <div className="row-input">
              <input
                type="password"
                autoComplete="off"
                placeholder="粘贴你的 Coding Plan API Key"
                value={minimaxKeyInput}
                onChange={(e) => setMinimaxKeyInput(e.target.value)}
              />
              <button type="button" className="btn" onClick={() => void saveMinimaxKey()}>
                保存
              </button>
            </div>
            {hasMinimaxKey && (
              <button type="button" className="btn danger" onClick={() => void clearMinimaxKey()}>
                清除我填写的 Key
              </button>
            )}
          </section>

          <section className="block">
            <h2>检测连接</h2>
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
            <h2>本机路径（供你对照）</h2>
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
    error: "失败",
    disabled: "关闭",
    setup: "待配置",
  };
  return map[s] ?? s;
}

function sourceLabel(mode: string): string {
  if (mode === "auto") return "自动识别";
  if (mode === "manual") return "你填写的";
  return "未识别";
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
