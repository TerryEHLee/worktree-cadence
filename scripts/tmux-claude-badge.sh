#!/usr/bin/env bash
# tmux-claude-badge.sh — Claude pane 의 상태를 "색" 과 "배지" 두 채널로 표시
#
#   pane  : 테두리 상태칩 + 배경 tint   → 지금 이 pane 이 무슨 상태인가 (항상 유지)
#   window: 이름 옆 (N) 배지            → 다른 window 에 내 손이 필요한가 (보면 사라짐)
#
#   ▸ 진행중   파랑  #89b4fa   Claude 가 답을 만드는 중 (기다리면 됨)
#   ! 권한대기 주황  #fab387   막혀 있음 — 내 승인이 필요 (급함)
#   ✓ 완료     초록  #a6e3a1   답변 끝 — 읽으면 됨
#   (없음)              —      유휴 / Claude 안 돎
#
# 사용:
#   tmux-claude-badge.sh run       [pane]  진행중  (UserPromptSubmit / PreToolUse)
#   tmux-claude-badge.sh wait      [pane]  권한대기 (Notification / PermissionRequest)
#   tmux-claude-badge.sh mark      [pane]  완료    (Stop)
#   tmux-claude-badge.sh idle      [pane]  유휴    (SessionStart)
#   tmux-claude-badge.sh clearwin  [pane]  그 window 배지 전부 해제 (tmux 포커스 훅)
#   tmux-claude-badge.sh sweep             전체 재집계 (복구용)
#
#   (구 별칭) clear=idle · clearwait=run — 옛 훅 설정 호환용
#
# 상태 SoT (두 옵션의 수명이 다르므로 분리한다):
#   pane   @cstate                     = run|wait|done|"" — pane 색·칩의 진실. 봐도 안 지워짐
#   pane   @claude_done / @claude_wait = 0|1              — window 배지 재료. 보면 지워짐
#   window @cdone       / @cwait       = 정수 합계          — 상태바가 직접 읽는 값
#
# pane 배경은 select-pane -P 가 아니라 set-option -p window-style 으로 칠한다.
#   select-pane 는 이름 그대로 pane 을 "선택" 하는 명령이라 포커스를 건드릴 여지가 있고,
#   -P 가 실제로 세팅하는 대상이 바로 pane 스코프의 window-style/window-active-style 이다.
set -u

action="${1:-}"
target="${2:-${TMUX_PANE:-}}"

command -v tmux >/dev/null 2>&1 || exit 0
tmux has-session >/dev/null 2>&1 || exit 0

# ── TMUX_PANE 폴백 ──────────────────────────────────────────────────────────
# 백그라운드 잡(`claude --bg-pty-host` 데몬 아래 도는 세션)은 TMUX_PANE 을 못 받는다.
# pane → 대화형 세션 → 데몬 → 잡 순으로 한 다리 건너뛰면서 환경이 끊기기 때문이다.
# 그 결과 훅은 매번 돌지만 대상 pane 을 못 찾아 그 열만 색·배지가 통째로 죽는다.
#
# 연결고리는 cwd 다 — 이 환경은 "워크트리 : 세션 = 1:1" 이라 작업 디렉터리가
# pane 을 유일하게 지목한다. 같은 경로에 pane 이 여럿이면(garden 처럼) 지목이
# 불가능하므로 **아무것도 칠하지 않고 조용히 빠진다.** 엉뚱한 열을 칠하는 것보다 낫다.
if [ -z "$target" ]; then
  _cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  _matches=$(tmux list-panes -a -F '#{pane_id} #{pane_current_path}' 2>/dev/null \
    | awk -v d="$_cwd" '$2 == d { print $1 }')
  _count=$(printf '%s\n' "$_matches" | grep -c . || true)
  if [ "$_count" = "1" ]; then
    target="$_matches"
  elif [ "${_count:-0}" -gt 1 ]; then
    # 동률이면 Claude pane(@pname 이 붙은 것)으로 좁힌다. 그래도 여럿이면 포기.
    _named=$(printf '%s\n' "$_matches" | while read -r _p; do
      [ -n "$(tmux display-message -p -t "$_p" '#{@pname}' 2>/dev/null)" ] && printf '%s\n' "$_p"
    done)
    [ "$(printf '%s\n' "$_named" | grep -c . || true)" = "1" ] && target="$_named"
  fi
fi

# 옛 훅 설정 호환
case "$action" in
  clear)     action=idle ;;
  clearwait) action=run  ;;
esac

# 상태 → 배경 tint. 배경 #1e1e2e 과 "밝기" 가 아니라 "색상" 이 다르도록 골랐다.
tint_for() {
  case "$1" in
    run)  echo "#1a2740" ;;   # 파랑 — B 채널 지배
    wait) echo "#3a2a12" ;;   # 주황 — R 채널 지배
    done) echo "#12331f" ;;   # 초록 — G 채널 지배 + B 를 낮춰 배경과 확실히 분리
    *)    echo "default" ;;
  esac
}

paint() {  # paint <pane> <state>
  local p="$1" bg prev prevbg
  bg="bg=$(tint_for "$2")"
  read -r prev prevbg <<<"$(tmux display-message -p -t "$p" \
    '#{@cstate} #{window-style}' 2>/dev/null)" || return 0
  # 상태와 배경이 "둘 다" 기대값일 때만 건너뛴다.
  # @cstate 만 보면, 밖에서 배경이 덧칠된 경우(옛 훅의 select-pane -P·수동 변경·
  # 스냅샷 복원) 영영 복구되지 않고 색과 칩이 어긋난 채 고착된다.
  [ "$prev" = "$2" ] && [ "$prevbg" = "$bg" ] && return 0
  tmux set-option -p -t "$p" @cstate "$2" 2>/dev/null || return 0
  # 비활성 pane 과 활성 pane 둘 다 칠해야 어느 쪽을 보고 있든 색이 유지된다
  tmux set-option -p -t "$p" window-style "$bg" 2>/dev/null
  tmux set-option -p -t "$p" window-active-style "$bg" 2>/dev/null
  # 테두리 칩은 status 갱신(-S)으로는 안 다시 그려진다. 실제 상태 전이 때만 전체 재그리기.
  tmux refresh-client 2>/dev/null
}

refresh_window() {
  local win="$1" d w
  d=$(tmux list-panes -t "$win" -F '#{@claude_done}' 2>/dev/null | grep -cx 1) || d=0
  w=$(tmux list-panes -t "$win" -F '#{@claude_wait}' 2>/dev/null | grep -cx 1) || w=0
  tmux set-option -w -t "$win" @cdone "$d" 2>/dev/null || return 0
  tmux set-option -w -t "$win" @cwait "$w" 2>/dev/null || return 0
}

if [ "$action" = "sweep" ]; then
  while read -r x; do refresh_window "$x"; done \
    < <(tmux list-windows -a -F '#{window_id}' 2>/dev/null)
  tmux refresh-client -S 2>/dev/null
  exit 0
fi

[ -n "$target" ] || exit 0

# 이미 그 상태이고 배지도 깨끗하면 즉시 종료 —
# PreToolUse(run) 는 도구 호출마다 도는 최다 빈도 훅이라 평상시 tmux 호출 1번으로 끝낸다.
case "$action" in
  run|idle)
    read -r cs cbg cd cw <<<"$(tmux display-message -p -t "$target" \
      '#{@cstate} #{window-style} #{@claude_done} #{@claude_wait}' 2>/dev/null)"
    want=$action; [ "$want" = idle ] && want=""
    if [ "${cs:-}" = "$want" ] && [ "${cbg:-}" = "bg=$(tint_for "$want")" ] \
       && [ "${cd:-0}" != 1 ] && [ "${cw:-0}" != 1 ]; then exit 0; fi
    ;;
esac

# ── 백그라운드 세션 양보 가드 ─────────────────────────────────────────────
# 백그라운드 잡(데몬 아래 `--bg-pty-host`)은 제어 tty 가 없다. 그런데 데몬이 어느 pane 에서
# 태어났으면 TMUX_PANE 을 물려받아 그 pane 을 칠한다 — 그 pane 에 대화형 Claude 가 이미
# 붙어 있으면 두 세션이 한 pane 을 번갈아 덧칠해 칩이 사라졌다 나타났다 한다
# (2026-09-08 manna 실측: 04b05a10 백그라운드 + 175661b3 대화형).
#
# ⚠️ 훅 프로세스 "자신" 의 tty 로 판정하면 안 된다 — 대화형 세션이 띄운 훅도 tty 가 없다(`??`).
#    그래서 부모를 거슬러 올라가 tty 를 가진 조상(=대화형 claude)이 있는지 본다.
#    대화형: hook → zsh(??) → claude(ttysNNN)   /   백그라운드: 전부 ?? 로 launchd 까지 닿는다.
# 규칙: 조상 중 tty 를 가진 것이 하나도 없고, 대상 pane 의 tty 에 Claude 가 살아 있으면
#       그 pane 은 그 Claude 의 것이다 — 아무것도 칠하지 않는다.
# 위치: 상시 경로(PreToolUse 의 "이미 run" 조기 종료) 뒤에 두어 실제 전이 때만 비용을 낸다.
_p=$$ _has_tty=0
for _i in 1 2 3 4 5 6 7 8; do
  _t=$(ps -o tty= -p "$_p" 2>/dev/null | tr -d ' ')
  if [ -n "$_t" ] && [ "$_t" != "??" ]; then _has_tty=1; break; fi
  _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
  { [ -z "$_p" ] || [ "$_p" -le 1 ]; } && break
done
if [ "$_has_tty" = 0 ]; then
  _ptty=$(tmux display-message -p -t "$target" '#{pane_tty}' 2>/dev/null)
  _ptty=${_ptty#/dev/}
  if [ -n "$_ptty" ] && ps -t "$_ptty" -o args= 2>/dev/null | grep -qE '(^|/)claude( |$)|/claude/versions/'; then
    exit 0
  fi
fi

win=$(tmux display-message -p -t "$target" '#{window_id}' 2>/dev/null) || exit 0
[ -n "$win" ] || exit 0

# 그 window 가 붙어 있는 클라이언트 화면에 떠 있으면 = 이미 보고 있음 → window 배지 불필요
# (pane 색·칩은 보고 있든 아니든 항상 칠한다 — 그게 이 pane 의 현재 상태이므로)
visible() {
  local wa sa
  read -r wa sa <<<"$(tmux display-message -p -t "$target" \
    '#{window_active} #{session_attached}' 2>/dev/null)"
  [ "${wa:-0}" = 1 ] && [ "${sa:-0}" != 0 ]
}

case "$action" in
  run)
    paint "$target" run
    tmux set-option -p -t "$target" @claude_done 0 2>/dev/null
    tmux set-option -p -t "$target" @claude_wait 0 2>/dev/null
    ;;
  wait)
    paint "$target" wait
    tmux set-option -p -t "$target" @claude_done 0 2>/dev/null
    if visible; then tmux set-option -p -t "$target" @claude_wait 0 2>/dev/null
    else            tmux set-option -p -t "$target" @claude_wait 1 2>/dev/null; fi
    ;;
  mark)
    paint "$target" done
    tmux set-option -p -t "$target" @claude_wait 0 2>/dev/null
    if visible; then tmux set-option -p -t "$target" @claude_done 0 2>/dev/null
    else            tmux set-option -p -t "$target" @claude_done 1 2>/dev/null; fi
    ;;
  idle)
    paint "$target" ""
    tmux set-option -p -t "$target" @claude_done 0 2>/dev/null
    tmux set-option -p -t "$target" @claude_wait 0 2>/dev/null
    ;;
  clearwin)
    # "봤다" 는 window 단위 — 배지만 끈다. pane 색·칩은 상태 그대로 둔다.
    while read -r p; do
      tmux set-option -p -t "$p" @claude_done 0 2>/dev/null
      tmux set-option -p -t "$p" @claude_wait 0 2>/dev/null
    done < <(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null)
    ;;
  *)
    exit 0
    ;;
esac

refresh_window "$win"
tmux refresh-client -S 2>/dev/null
exit 0
