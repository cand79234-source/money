// 攒钱计划 v3 — 后端服务
// 托管静态页面，并把整个应用状态持久化到 Neon (Postgres)。
// 无 DATABASE_URL 时自动回退为纯静态托管（状态仅存浏览器 localStorage）。
const express = require('express');
const path = require('path');
const { Pool } = require('pg');

const app = express();
app.use(express.json({ limit: '4mb' }));

const DATABASE_URL = process.env.DATABASE_URL || '';
const USE_DB = /^postgres(ql)?:\/\//i.test(DATABASE_URL);
const pool = USE_DB
  ? new Pool({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false }, max: 5 })
  : null;

const STATE_ID = process.env.STATE_ID || 'default';

async function ensureTable() {
  if (!pool) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_state (
      id          text PRIMARY KEY,
      data        jsonb NOT NULL,
      updated_at  timestamptz NOT NULL DEFAULT now()
    );
  `);
}

// 健康检查（Render 用）
app.get('/api/health', (_req, res) =>
  res.json({ ok: true, db: !!pool, time: new Date().toISOString() })
);

// 读取状态
app.get('/api/state', async (_req, res) => {
  if (!pool) return res.json({ data: null });
  try {
    const r = await pool.query('SELECT data FROM app_state WHERE id=$1', [STATE_ID]);
    res.json({ data: r.rows.length ? r.rows[0].data : null });
  } catch (e) {
    console.error('GET /api/state failed:', e.message);
    res.status(500).json({ error: 'db_read_failed' });
  }
});

// 保存状态（前端每次 save 都会调用）
app.post('/api/state', async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_URL not configured' });
  const data = req.body && req.body.data;
  if (data === undefined) return res.status(400).json({ error: 'data required' });
  try {
    await pool.query(
      `INSERT INTO app_state (id, data, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [STATE_ID, data]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('POST /api/state failed:', e.message);
    res.status(500).json({ error: 'db_write_failed' });
  }
});

// 显式提供 manifest / service worker，确保 MIME 和缓存策略正确
app.get('/manifest.webmanifest', (_req, res) =>
  res.type('application/manifest+json').sendFile(path.join(__dirname, 'public', 'manifest.webmanifest'))
);
app.get('/sw.js', (_req, res) =>
  res.set('Cache-Control', 'public, max-age=0, must-revalidate').type('application/javascript')
    .sendFile(path.join(__dirname, 'public', 'sw.js'))
);

// 首页永远拿最新的，避免被浏览器/Service Worker 缓存住旧版本
app.get(['/', '/index.html'], (_req, res) =>
  res.set('Cache-Control', 'no-cache, no-store, must-revalidate')
    .sendFile(path.join(__dirname, 'public', 'index.html'))
);

// 静态资源 + SPA 回退
app.use(express.static(path.join(__dirname, 'public'), { etag: false, lastModified: false }));
app.get('*', (_req, res) =>
  res.set('Cache-Control', 'no-cache, no-store, must-revalidate')
    .sendFile(path.join(__dirname, 'public', 'index.html'))
);

const PORT = process.env.PORT || 3000;
ensureTable()
  .catch((e) => console.error('DB init error:', e.message))
  .finally(() => {
    app.listen(PORT, () => {
      console.log(`攒钱计划 已启动: http://localhost:${PORT}  (db=${!!pool})`);
    });
  });
