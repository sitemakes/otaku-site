#!/usr/bin/env bash
# Claude Code: .js を編集した直後に構文チェック。
# エラーは exit 2 で Claude に返し、その場で直させる。
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write((j.tool_input&&j.tool_input.file_path)||"")}catch{}})')"

case "$file" in
  *.js|*.cjs) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

if ! out="$(node --check "$file" 2>&1)"; then
  echo "構文エラーがあります。修正してください: $file" >&2
  echo "$out" | head -n 20 >&2
  exit 2
fi
exit 0
