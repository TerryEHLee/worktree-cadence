#!/usr/bin/env bash
# mirror-main-checkout.sh — 메인 체크아웃(WTX_REPO)을 origin/<BASE> 참조 미러로 유지.
#
# 왜 메인 체크아웃만인가:
#   .git 실체가 있는 원본 폴더는 코드를 눈으로 확인할 때 무의식적으로 여는 기준점이다.
#   수백 커밋 뒤처진 기준점은 낡은 코드를 읽고 잘못된 결론을 내리게 한다.
#   나머지 워크트리는 각자 작업을 머지할 때 자연히 정렬되므로 건드리지 않는다.
#
# 왜 rebase 가 아니라 merge --ff-only 인가:
#   미러는 작업하지 않는 순수 참조본이므로 로컬 커밋이 있어서는 안 된다.
#   ff-only 는 조금이라도 갈라져 있으면 한 글자도 건드리지 않고 거부한다 —
#   실수로 커밋해도 조용히 덮어쓰는 대신 요란하게 실패한다. reset --hard 금지.
#
# 사용: mirror-main-checkout.sh [--quiet]   (launchd 주기 실행 + push 스킬 마지막 단계)
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_wtx-lib.sh"

REPO="${WTX_MIRROR_REPO:-$WTX_CODES/$WTX_REPO}"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
say() { [ "$QUIET" -eq 1 ] || echo "$@"; }

# 링크된 워크트리는 .git 이 파일이라 -d 로 판정하면 안 된다
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { say "⏭️  git 저장소 아님: $REPO"; exit 0; }

BR="$(git -C "$REPO" branch --show-current 2>/dev/null)"
if [ "$BR" != "$WTX_MIRROR_BRANCH" ]; then
  echo "⚠️  미러 브랜치가 아님 (현재: ${BR:-detached}, 기대: $WTX_MIRROR_BRANCH) — 건드리지 않고 종료"
  exit 1
fi
if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
  echo "⚠️  미러에 미커밋 변경 — 자동 갱신 중단. 사람이 확인할 것"
  git -C "$REPO" status --short --untracked-files=no
  exit 1
fi
GITDIR="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null)"
for d in rebase-merge rebase-apply MERGE_HEAD; do
  [ -e "$GITDIR/$d" ] && { echo "⚠️  $d 진행 중 — 건너뜀"; exit 1; }
done

git -C "$REPO" fetch origin "$WTX_BASE" --quiet 2>/dev/null || { say "⏭️  fetch 실패(오프라인?) — 건너뜀"; exit 0; }
BEFORE="$(git -C "$REPO" rev-parse --short HEAD)"
BEHIND="$(git -C "$REPO" rev-list --count HEAD.."origin/$WTX_BASE" 2>/dev/null || echo 0)"
[ "${BEHIND:-0}" -eq 0 ] && { say "✅ 미러 이미 최신 ($BEFORE)"; exit 0; }

if OUT="$(git -C "$REPO" merge --ff-only "origin/$WTX_BASE" 2>&1)"; then
  say "✅ 미러 갱신: $BEFORE → $(git -C "$REPO" rev-parse --short HEAD) (${BEHIND}커밋)"
else
  echo "⚠️  ff-only 실패 — 로컬이 origin/$WTX_BASE 와 갈라져 있음. 파일은 그대로 둠"
  echo "$OUT"; exit 1
fi
