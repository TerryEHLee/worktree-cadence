#!/usr/bin/env bash
# sync-on-event.sh — SessionStart / UserPromptSubmit 훅용 트렁크 이벤트 sync.
#   throttle 창(WTX_SYNC_THROTTLE초) 지났으면 전체 sync (fetch+rebase),
#   창 안이면 네트워크 없이 로컬 ref 로 뒤처짐만 확인해 필요할 때만 rebase.
#   트렁크가 아니면(이슈 브랜치·미러·타 repo) 조용히 통과. 항상 exit 0.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_wtx-lib.sh" 2>/dev/null || exit 0

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0
TRUNK="$(git branch --show-current 2>/dev/null)"
EXPECT="$(wtx_trunk_of "$(basename "$ROOT")")"
[ -z "$TRUNK" ] || [ -z "$EXPECT" ] || [ "$TRUNK" != "$EXPECT" ] && exit 0

GITDIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
[ -d "$GITDIR/wtx-sync.lock.d" ] && exit 0   # 다른 세션이 sync 중

STAMP="$GITDIR/wtx-sync.last"
now=$(date +%s); last=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ $(( now - last )) -ge "${WTX_SYNC_THROTTLE:-180}" ]; then
  echo "$now" > "$STAMP"
  bash "$HERE/sync-trunk.sh" >/dev/null 2>&1 || true
else
  behind=$(git rev-list --count HEAD.."origin/$WTX_BASE" 2>/dev/null || echo 0)
  [ "${behind:-0}" -gt 0 ] && bash "$HERE/sync-trunk.sh" --no-fetch >/dev/null 2>&1 || true
fi
exit 0
