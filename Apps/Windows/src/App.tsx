import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

/** Mirrors macOS Domain UsageSnapshot (subset for MVP UI). */
export type QuotaCard = {
  providerId: string;
  displayName: string;
  status: string;
  sessionRemainingPercent: number | null;
  weeklyRemainingPercent: number | null;
  detail: string;
};

export type SnapshotPayload = {
  updatedAt: string;
  cards: QuotaCard[];
};

export default function App() {
  const [data, setData] = useState<SnapshotPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

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

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <div className="shell">
      <header className="header">
        <div>
          <h1>智额</h1>
          <p className="tagline">SmartQuota · Windows</p>
        </div>
        <button type="button" className="btn" onClick={() => void refresh()} disabled={loading}>
          {loading ? "刷新中…" : "刷新"}
        </button>
      </header>

      {error && <div className="banner error">{error}</div>}

      <main className="cards">
        {(data?.cards ?? []).map((card) => (
          <article key={card.providerId} className="card">
            <div className="card-top">
              <strong>{card.displayName}</strong>
              <span className={`pill status-${card.status}`}>{card.status}</span>
            </div>
            <div className="meters">
              <Meter label="5 小时" value={card.sessionRemainingPercent} />
              <Meter label="7 天" value={card.weeklyRemainingPercent} />
            </div>
            <p className="detail">{card.detail}</p>
          </article>
        ))}
        {!data?.cards?.length && !loading && !error && (
          <p className="empty">暂无数据。安装后将读取本机 Codex / MiniMax / Grok 凭证。</p>
        )}
      </main>

      <footer className="footer">
        {data?.updatedAt ? `更新于 ${data.updatedAt}` : "—"}
      </footer>
    </div>
  );
}

function Meter({ label, value }: { label: string; value: number | null }) {
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
    </div>
  );
}
