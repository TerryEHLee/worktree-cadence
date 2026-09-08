#!/usr/bin/env bash
# tool-lock-guard.sh — PreToolUse hook.
# 트렁크 sync lock 이 걸려 있으면 이 세션의 tool 호출을 차단(직렬화).
# sync 끝나면 lock 해제 → 다음 tool 호출부터 자동 통과.
# exit 0 = 통과, exit 2 = 차단(stderr 가 모델에게 피드백).
GITDIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
LOCK="$GITDIR/wtx-sync.lock.d"
if [ -d "$LOCK" ]; then
  # stale lock 방어: 10분 넘게 남아있으면 죽은 lock 으로 간주하고 통과
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; exit 0
  fi
  echo "⏸️ 트렁크 sync 진행 중 — 이 도구 호출은 일시 차단됨. 몇 초 뒤 다시 시도하세요." >&2
  exit 2
fi
exit 0
