#!/usr/bin/env bash
# sync-trunk.sh — 현재 워크트리의 트렁크를 origin/<BASE> 에 sync (한 워크트리 멀티세션 안전)
#
# 동작: lock 획득(=같은 워크트리 다른 세션 tool 일시정지) → fetch → rebase --autostash
#       → lock 해제. WIP 는 autostash 가 stash→싱크→pop 을 한 트랜잭션으로 보장.
# lock 은 mkdir 원자성 사용(macOS flock 부재 대응). 종료 시 trap 으로 자동 해제.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_wtx-lib.sh"

NO_FETCH=0
[ "${1:-}" = "--no-fetch" ] && NO_FETCH=1

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "❌ git 저장소 아님"; exit 1; }
GITDIR="$(git rev-parse --git-dir)"
LOCK="$GITDIR/wtx-sync.lock.d"
TRUNK="$(git branch --show-current)"

NAME="$(basename "$(git rev-parse --show-toplevel)")"
EXPECT="$(wtx_trunk_of "$NAME")"
if [ -z "$TRUNK" ] || [ -z "$EXPECT" ] || [ "$TRUNK" != "$EXPECT" ]; then
  echo "❌ 현재 '$TRUNK' (폴더 $NAME) — 트렁크(폴더명−${WTX_PREFIX})에서만 sync (이슈브랜치·미러 제외)"
  exit 1
fi

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "⏳ 다른 세션이 트렁크 잠금 중 — 잠시 후 다시 시도"
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

echo "🔒 lock 획득 — 이 워크트리 다른 세션 tool 일시 차단됨"
if [ "$NO_FETCH" = "1" ]; then
  echo "⏭️ --no-fetch — 로컬 origin/$WTX_BASE ref 로만 rebase (throttle 창)"
else
  git fetch origin "$WTX_BASE" || { echo "❌ fetch 실패"; exit 1; }
fi

BEFORE="$(git rev-parse --short HEAD)"
BEHIND="$(git rev-list --count HEAD.."origin/$WTX_BASE")"
echo "🔄 rebase --autostash origin/$WTX_BASE (${BEHIND} 커밋 뒤처짐) …"

if git rebase --autostash "origin/$WTX_BASE"; then
  AFTER="$(git rev-parse --short HEAD)"
  AHEAD="$(git rev-list --count "origin/$WTX_BASE"..HEAD)"
  echo "✅ sync 완료: ${BEFORE} → ${AFTER}  (트렁크 = origin/$WTX_BASE + 미푸시 ${AHEAD} 커밋)"
else
  git rebase --abort 2>/dev/null
  echo "⚠️ rebase 충돌 → abort (working tree 는 autostash 로 안전 복원)."
  echo "   트렁크 미머지 커밋이 origin/$WTX_BASE 와 충돌 — 해당 이슈 push/머지 후 재시도."
  exit 1
fi
echo "🔓 lock 해제 — 다른 세션 재개"
