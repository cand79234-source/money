# 攒钱计划 v3 · 全栈部署（GitHub + Neon + Render）

一个移动端「攒钱计划」记账/储蓄规划单页应用，同时是 **PWA**：在 Chrome/Safari/Edge 里可以「安装到桌面」或「添加到主屏幕」，打开后像原生 App 一样全屏运行。原始版本把全部状态存在浏览器 `localStorage`（换设备即丢失）。本仓库在其基础上加了一层**极薄的 Node 后端**，把整个应用状态持久化到 **Neon（Postgres）**，并托管在 **Render**，代码托管在 **GitHub**。

## 架构

```
┌────────────┐      HTTP /api/state       ┌──────────────────┐
│  浏览器     │ ───────────────────────▶  │  Render          │
│ index.html │ ◀───────────────────────  │  Web Service     │
│ (攒钱计划)  │     GET/POST 状态 JSON     │  (Node/Express)  │
└────────────┘                            └────────┬─────────┘
                                                  │ pg (DATABASE_URL)
                                                  ▼
                                          ┌──────────────────┐
                                          │  Neon Postgres   │
                                          │  table:app_state │
                                          └──────────────────┘
```

- 前端：原 `index.html`（手机端 UI 未改动），仅在 `save()` 时额外把状态 POST 到后端；启动时从后端拉取最新状态。
- 后端：`server.js`（Express）。无 `DATABASE_URL` 时自动回退为纯静态托管（状态仍存 `localStorage`），方便本地直接打开。
- 数据库：Neon 上一张表 `app_state(id, data jsonb, updated_at)`，存整份应用 JSON。表在首次启动时自动创建。

## 目录结构

```
.
├── public/
│   ├── index.html              # 页面（已加入后端同步 + PWA 注册）
│   ├── manifest.webmanifest    # PWA 安装清单
│   ├── sw.js                   # Service Worker（离线缓存）
│   ├── icon-192.png
│   ├── icon-512.png
│   ├── icon-maskable-512.png
│   └── apple-touch-icon.png
├── server.js                   # Express 后端 + Neon 持久化
├── package.json
├── render.yaml                 # Render Blueprint 配置
├── .env.example                # 本地开发用的 DATABASE_URL 模板
└── scripts/
    ├── deploy.sh               # 一键部署：GitHub → Neon → Render
    └── gen_icons.py            # 生成 PWA 图标
```

## 本地运行

```bash
npm install
# 纯静态预览（不连数据库，状态存 localStorage）：
PORT=3000 npm start
# 或接 Neon：把 .env.example 复制为 .env 填入 DATABASE_URL 后：
cp .env.example .env   # 填入你的 Neon 连接串
npm start
```

打开 http://localhost:3000 即可。

## 部署（自动化，推荐）

准备好三个 token 后，一条命令完成全部：

```bash
GITHUB_TOKEN=ghp_xxx \
NEON_API_KEY=nx_xxx \
RENDER_API_KEY=rnd_xxx \
bash scripts/deploy.sh
```

| Token | 来源 |
|---|---|
| `GITHUB_TOKEN` | GitHub → Settings → Developer settings → PAT（勾选 `repo`） |
| `NEON_API_KEY` | Neon 控制台 → Account → API Keys |
| `RENDER_API_KEY` | Render 控制台 → Account Settings → API Keys |

> 注意：Render 需要用**同一个 GitHub 账号**授权过，才能拉取仓库。若仓库设为 `private` 请确保该账号可见。

脚本会：① 用 `gh` 建仓库并推送 ② 用 Neon API 建项目拿到连接串 ③ 用 Render API 建 Web Service 并写入 `DATABASE_URL` 触发部署。

## 部署（手动）

1. **GitHub**：把本仓库推到你的账号（仓库名如 `savings-plan`）。
2. **Neon**：新建 Project（建议 region `aws-ap-southeast-1` 新加坡），复制 Connection String。
3. **Render**：New → Blueprint，关联本仓库（或直接 New Web Service），设置：
   - Runtime: Node，Branch: main
   - Build: `npm install`，Start: `node server.js`
   - Health check path: `/api/health`
   - 环境变量 `DATABASE_URL` = 上面的 Neon 连接串（标记为 Secret）
   - 或直接在 Render 用仓库里的 `render.yaml`。

部署完成后访问 `https://<slug>.onrender.com`。Free 套餐在闲置后会休眠，首次访问需短暂唤醒。

## PWA（像 App 一样安装到桌面/主屏幕）

- 访问线上地址时，Chrome/Edge 地址栏或菜单会出现「安装」按钮；iOS 用 Safari「添加到主屏幕」。
- 安装后会以**全屏/standalone** 模式打开，有独立图标和启动画面。
- 依赖：
  - `manifest.webmanifest`：应用名称、图标、主题色、display: standalone。
  - `sw.js`：缓存首页和静态资源，离线也能打开（数据接口会在恢复联网后自动同步）。
- 若需要重新生成图标：`python3 scripts/gen_icons.py`。

## 数据说明

- 当前为**单人单份状态**（表行 `id='default'`）。多用户/多份可改用不同 `STATE_ID`。
- 前端保留 `localStorage` 作为离线缓存：后端不可用时不会丢操作，恢复联网后下次保存会重新同步。
- 若要从零重置数据：在 Neon 控制台执行 `DELETE FROM app_state;`。
