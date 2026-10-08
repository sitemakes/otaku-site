#!/usr/bin/env bash
# Claude Code: 作業を終える前に scripts/check.sh を実行。
# NG なら exit 2 で作業を続けさせる（2回目の停止は通して無限ループを防ぐ）。
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).stop_hook_active===true))}catch{process.stdout.write("false")}})')"
[ "$active" = "true" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# JS / HTML に変更が無ければ何もしない
if [ -z "$(git status --porcelain -- '*.js' '*.cjs' '*.html' 2>/dev/null)" ]; then
  exit 0
fi

if ! out="$(bash scripts/check.sh 2>&1)"; then
  echo "scripts/check.sh が NG です。修正してから終了してください。" >&2
  echo "$out" | grep -E 'NG|Error|not ok|✖' | head -n 30 >&2
  exit 2
fi
exit 0
