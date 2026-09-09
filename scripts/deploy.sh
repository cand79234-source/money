#!/usr/bin/env bash
# 一键部署：GitHub + Neon + Render
#
# 前置：在 Render 控制台用同一个 GitHub 账号授权过（这样 Render 才能拉取私有仓库）。
# 用法：
#   GITHUB_TOKEN=ghp_xxx \
#   NEON_API_KEY=nx_xxx \
#   RENDER_API_KEY=rnd_xxx \
#   bash scripts/deploy.sh
#
# 可选覆盖：
#   REPO_NAME=savings-plan
#   NEON_REGION=aws-ap-southeast-1      # 新加坡，离大陆最近
#   RENDER_REGION=singapore
#   VISIBILITY=public                   # 或 private
set -euo pipefail

: "${GITHUB_TOKEN:?缺少 GITHUB_TOKEN（GitHub Personal Access Token，需 repo 权限）}"
: "${NEON_API_KEY:?缺少 NEON_API_KEY（Neon 控制台 → Account → API keys）}"
: "${RENDER_API_KEY:?缺少 RENDER_API_KEY（Render 控制台 → Account Settings → API Keys）}"

REPO_NAME="${REPO_NAME:-savings-plan}"
NEON_REGION="${NEON_REGION:-aws-ap-southeast-1}"
RENDER_REGION="${RENDER_REGION:-singapore}"
VISIBILITY="${VISIBILITY:-public}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> [1/3] GitHub：登录并推送仓库"
printf '%s' "$GITHUB_TOKEN" | gh auth login --with-token
USER="$(gh api user --jq .login)"
echo "GitHub 用户：$USER"

gh repo create "$REPO_NAME" --"$VISIBILITY" --description "攒钱计划 v3 — GitHub + Neon + Render" 2>/dev/null \
  || echo "（仓库已存在，继续推送）"

git init -q 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "https://$USER:$GITHUB_TOKEN@github.com/$USER/$REPO_NAME.git"
git add -A
git -c user.email="deploy@local" -c user.name="deploy" commit -q -m "init: 攒钱计划 v3 全栈 (GitHub+Neon+Render)" 2>/dev/null \
  || echo "（无新提交）"
git branch -M main
git push -u origin main --force
REPO_URL="https://github.com/$USER/$REPO_NAME"
echo "仓库地址：$REPO_URL"

echo "==> [2/3] Neon：创建项目并获取连接串"
NEON_RESP="$(curl -s -X POST https://console.neon.tech/api/v2/projects \
  -H "Authorization: Bearer $NEON_API_KEY" \
  -H "accept: application/json" -H "content-type: application/json" \
  -d "{\"project\":{\"name\":\"$REPO_NAME\",\"region_id\":\"$NEON_REGION\",\"pg_version\":18}}")"
DATABASE_URL="$(printf '%s' "$NEON_RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);cus=d.get('connection_uris') or [];print(cus[0]['connection_uri'] if cus else '')")"
if [ -z "$DATABASE_URL" ]; then
  echo "Neon 连接串获取失败，响应如下：" >&2; echo "$NEON_RESP" >&2; exit 1
fi
echo "Neon 项目已创建，连接串已获取（已隐藏）"

echo "==> [3/3] Render：创建 Web Service 并部署"
OWNER="$(curl -s https://api.render.com/v1/owners -H "Authorization: Bearer $RENDER_API_KEY" -H "accept: application/json" \
  | python3 -c "import sys,json;o=json.load(sys.stdin).get('owners',[]);print(([x['id'] for x in o if x.get('type')=='personal'] or [o[0]['id']])[0] if o else '')")"
[ -z "$OWNER" ] && { echo "无法获取 Render ownerId（请确认 API Key 有效）" >&2; exit 1; }

ENVVARS="$(DB="$DATABASE_URL" python3 -c "import json,os;print(json.dumps([
  {'key':'DATABASE_URL','value':os.environ['DB']},
  {'key':'NODE_ENV','value':'production'},
  {'key':'PORT','value':'10000'}
]))")"

BODY="$(REPO="$REPO_NAME" OWNER="$OWNER" REPO_URL="$REPO_URL" RREGION="$RENDER_REGION" ENVVARS="$ENVVARS" python3 -c "
import json,os
print(json.dumps({
  'type':'web_service','name':os.environ['REPO'],'ownerId':os.environ['OWNER'],
  'repo':os.environ['REPO_URL'],'branch':'main','autoDeploy':'yes',
  'buildCommand':'npm install','startCommand':'node server.js','env':'node',
  'region':os.environ['RREGION'],'plan':'free','healthCheckPath':'/api/health',
  'envVars':json.loads(os.environ['ENVVARS'])
}))")"

RENDER_RESP="$(curl -s -X POST https://api.render.com/v1/services \
  -H "Authorization: Bearer $RENDER_API_KEY" -H "accept: application/json" -H "content-type: application/json" \
  -d "$BODY")"
DASH="$(printf '%s' "$RENDER_RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('service',{}).get('dashboardUrl',''))")"
SLUG="$(printf '%s' "$RENDER_RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('service',{}).get('slug',''))")"

echo
echo "=========================================="
echo "部署已发起！"
echo "  GitHub  : $REPO_URL"
echo "  Neon    : 项目 $REPO_NAME（region $NEON_REGION）"
echo "  Render  : $DASH"
echo "  访问地址: https://$SLUG.onrender.com  （首次启动需等待 1~2 分钟构建）"
echo "=========================================="
