#!/usr/bin/env bash
# OTAKU LIVE の機械チェック一式（依存パッケージ不要・Node 18+）
# ローカル・Claude Code の hooks・GitHub Actions のすべてで同じものを使う。
#   bash scripts/check.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
section() { printf '\n== %s ==\n' "$1"; }

section "構文チェック (node --check)"
syn_ok=1
for f in *.js api/*.js; do
  if ! out="$(node --check "$f" 2>&1)"; then
    echo "NG: $f"; echo "$out" | head -n 8; fail=1; syn_ok=0
  fi
done
[ "$syn_ok" -eq 1 ] && echo "OK"

section "単体テスト (node --test)"
if out="$(node --test tests/*.test.cjs 2>&1)"; then
  echo "$out" | grep -E '^# (tests|pass|fail)' || echo "OK"
else
  echo "NG: テスト失敗"; echo "$out" | tail -n 30; fail=1
fi

section "supabase-js のバージョン固定"
versions="$(grep -oh 'supabase-js@[0-9][0-9.]*' -- *.html | sort -u)"
count="$(printf '%s\n' "$versions" | grep -c . || true)"
if [ "$count" -ne 1 ]; then
  echo "NG: HTML 間で supabase-js のバージョンが揃っていません"; printf '%s\n' "$versions"; fail=1
else
  echo "OK: $versions"
fi

section "複数箇所にある設定値の一致"
sb="$(grep -oh 'https://[a-z0-9]*\.supabase\.co' supabase.js api/event-share.js api/event-og.js | sort -u)"
if [ "$(printf '%s\n' "$sb" | grep -c .)" -ne 1 ]; then
  echo "NG: Supabase URL が supabase.js / api/event-share.js / api/event-og.js で一致しません"; printf '%s\n' "$sb"; fail=1
else
  echo "OK: Supabase URL"
fi
dom_ok=1
for f in api/client-error.js api/event-share.js calendar.js; do
  if ! grep -q 'otaku-live-mvp\.vercel\.app' "$f"; then
    echo "NG: 本番ドメインが $f に見つかりません"; fail=1; dom_ok=0
  fi
done
[ "$dom_ok" -eq 1 ] && echo "OK: 本番ドメイン"

section "秘密情報の混入チェック"
if grep -rInE 'service_role|SUPABASE_SERVICE|sb_secret_|-----BEGIN [A-Z ]*PRIVATE KEY' \
     --include='*.js' --include='*.html' . 2>/dev/null | grep -v '^./scripts/'; then
  echo "NG: 秘密情報らしき文字列があります"; fail=1
else
  echo "OK"
fi

echo
if [ "$fail" -ne 0 ]; then echo "結果: NG"; exit 1; fi
echo "結果: すべてOK"
