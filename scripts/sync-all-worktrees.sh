#!/usr/bin/env bash
# sync-all-worktrees.sh — 워크트리 전체 fan-out sync (⚠️ 수동 도구 — 자동 배선하지 말 것)
#
# 언제 쓰나: "이 파일을 전 워크트리에 지금 퍼뜨려야 한다" 같은 일회성 정리 때만.
# 평소에는 불필요하다 — 각 워크트리는 자기 push/프롬프트 때 자연히 정렬되고,
# 장기 작업 워크트리가 수십 커밋 뒤처지는 것은 정상(머지되면 0이 된다).
#
# 왜 자동화하지 않는가: 성공한 rebase 가 더 위험하다. 작업 중인 다른 세션이 30분 전
# 읽은 파일들이 발밑에서 조용히 바뀌는데 아무 신호도 없다. 충돌은 abort 로 요란하게
# 실패하지만(안전), 성공은 침묵한다.
#
# 안전장치: 워크트리별 lock / rebase 진행 중 건너뜀 / 충돌 시 그 워크트리만 즉시 abort
#           (autostash 자동 복원 — WIP 손실 0) / 이슈 브랜치·미러는 건너뜀.
# 사용: sync-all-worktrees.sh [--dry-run] [--no-fetch]   ← 반드시 --dry-run 먼저
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_wtx-lib.sh"

DRY_RUN=0; NO_FETCH=0
for a in "$@"; do case "$a" in
  --dry-run) DRY_RUN=1 ;; --no-fetch) NO_FETCH=1 ;;
  *) echo "알 수 없는 인자: $a"; exit 0 ;;
esac; done

MAIN="$WTX_CODES/$WTX_REPO"
git -C "$MAIN" rev-parse --git-common-dir >/dev/null 2>&1 || { echo "❌ 저장소 없음: $MAIN"; exit 0; }
[ "$NO_FETCH" = "1" ] || git -C "$MAIN" fetch origin "$WTX_BASE" --quiet

SYNCED=(); SKIPPED=(); FAILED=()
while IFS= read -r WT; do
  [ -z "$WT" ] && continue
  NAME="$(basename "$WT")"; BR="$(git -C "$WT" branch --show-current 2>/dev/null)"
  EXPECT="$(wtx_trunk_of "$NAME")"
  if [ "$NAME" = "$WTX_REPO" ]; then SKIPPED+=("$NAME — 참조 미러 (mirror-main-checkout.sh 담당)"); continue; fi
  if [ -z "$EXPECT" ] || [ "$BR" != "$EXPECT" ]; then SKIPPED+=("$NAME [$BR] — 트렁크 아님(이슈브랜치/detached)"); continue; fi
  GITDIR="$(git -C "$WT" rev-parse --absolute-git-dir 2>/dev/null)" || { SKIPPED+=("$NAME — gitdir 실패"); continue; }
  { [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; } && { SKIPPED+=("$NAME — rebase 진행 중"); continue; }

  BEHIND="$(git -C "$WT" rev-list --count HEAD.."origin/$WTX_BASE" 2>/dev/null || echo '?')"
  DIRTY="$(git -C "$WT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$DRY_RUN" = "1" ]; then
    if [ "${BEHIND:-0}" = "0" ]; then SYNCED+=("$NAME [$BR] — 이미 최신"); else
      SYNCED+=("$NAME [$BR] — (dry-run) rebase 예정 · ${BEHIND}커밋 뒤처짐 · 미커밋 ${DIRTY}개"); fi
    continue
  fi
  LOCK="$GITDIR/wtx-sync.lock.d"
  mkdir "$LOCK" 2>/dev/null || { SKIPPED+=("$NAME — lock (다른 세션 sync 중)"); continue; }
  BEFORE="$(git -C "$WT" rev-parse --short HEAD)"
  # 출력을 변수로 받아 git 자신의 종료코드로 판정 (파이프에 물리면 실패가 성공으로 잡힘)
  OUT="$(git -C "$WT" rebase --autostash "origin/$WTX_BASE" --quiet 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ]; then
    SYNCED+=("$NAME [$BR] — $BEFORE → $(git -C "$WT" rev-parse --short HEAD) (미커밋 ${DIRTY}개 유지)")
  else
    git -C "$WT" rebase --abort 2>/dev/null
    FAILED+=("$NAME [$BR] — rebase 충돌 → abort. WIP 는 autostash 로 복원됨")
  fi
  rmdir "$LOCK" 2>/dev/null
done < <(git -C "$MAIN" worktree list --porcelain | awk '/^worktree /{print $2}')

echo; echo "═══ fan-out sync 결과 ═══"
[ ${#SYNCED[@]}  -gt 0 ] && { echo "✅ 정렬됨";  printf '   %s\n' "${SYNCED[@]}"; }
[ ${#SKIPPED[@]} -gt 0 ] && { echo "⏭️  건너뜀"; printf '   %s\n' "${SKIPPED[@]}"; }
[ ${#FAILED[@]}  -gt 0 ] && { echo "⚠️  실패 — 수동 확인 필요"; printf '   %s\n' "${FAILED[@]}"; }
exit 0
