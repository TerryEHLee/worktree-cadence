#!/usr/bin/env bash
# session-up.sh — 워크트리 케이던스 tmux 세션 런처.  alias: wtx
#
# 배치는 config 의 WTX_WINDOWS 가 정의한다. 안전 재실행: 빠진 window 만 채운다.
# 스냅샷(wtx-save)이 있으면 그 배치 + pane 별 `claude --resume <id>` 로 그대로 복원.
# 강제 전체 재생성: tmux kill-session -t <세션> && wtx
#   (tmux 세션을 죽여도 git WIP 은 워크트리 디스크에 그대로 — 유실 없음)
#
# 옵션(env): WTX_NO_CLAUDE=1 Claude 자동 실행 생략 / WTX_NO_ATTACH=1 attach 생략(검증용)
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/_wtx-lib.sh"

SESSION="$WTX_SESSION"
SNAP="${WTX_SNAPSHOT:-$HOME/.config/wtx/session-snapshot.tsv}"

has_window()  { tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$1"; }
pane_count()  { tmux list-panes -t "${SESSION}:$1" 2>/dev/null | wc -l | tr -d ' '; }

build_window() {  # $1=윈도우명, 이후=cwd 목록(절대경로)
  local win="$1"; shift
  tmux new-window -t "${SESSION}:" -n "$win" -c "$1"; shift
  local d; for d in "$@"; do tmux split-window -h -t "${SESSION}:${win}" -c "$d"; done
  tmux select-layout -t "${SESSION}:${win}" even-horizontal
}

# 스냅샷 복원 — pane 생성과 동시에 명령을 지정한다.
# (send-keys 는 셸 프롬프트와 경합해 첫 키가 씹힌다 — 배너가 Enter 를 먹는 것 실측.
#  명령을 pane 생성 인자로 직접 주면 경합 자체가 사라진다)
build_from_snapshot() {
  [ -f "$SNAP" ] || return 1
  local _tag widx wname pidx cwd sid running prev_win="" made=0 n_res=0 n_new=0 cmd full
  while IFS=$'\t' read -r _tag widx wname pidx cwd sid running; do
    cmd=""
    if [ "${WTX_NO_CLAUDE:-0}" != "1" ]; then
      if [ "$sid" != "-" ]; then cmd="claude --resume $sid"; n_res=$((n_res+1))
      elif [ "${running:-0}" = "1" ]; then cmd="claude"; n_new=$((n_new+1)); fi
    fi
    full=""; [ -n "$cmd" ] && full="$cmd; exec \$SHELL -l"
    if [ "$wname" != "$prev_win" ]; then
      tmux new-window   -t "${SESSION}:" -n "$wname" -c "$cwd" ${full:+"$full"}; prev_win="$wname"
    else
      tmux split-window -h -t "${SESSION}:${wname}" -c "$cwd" ${full:+"$full"}
    fi
    made=$((made+1))
  done < <(grep '^PANE' "$SNAP")
  [ "$made" -gt 0 ] || return 1
  tmux list-windows -t "$SESSION" -F '#{window_name}' | while read -r w; do
    tmux select-layout -t "${SESSION}:${w}" even-horizontal 2>/dev/null || true
  done
  echo "→ 스냅샷 복원: pane ${made}개 · Claude 복원 ${n_res} · 새 세션 ${n_new}"
  return 0
}

# 스냅샷 없을 때 fallback — cwd 기준 claude --continue (같은 cwd 는 맨 앞 pane 만)
resume_panes() {
  [ "${WTX_NO_CLAUDE:-0}" = "1" ] && { echo "→ WTX_NO_CLAUDE=1 — 생략"; return; }
  [ -f "$SNAP" ] && return 0
  sleep 1
  local pid cwd proj n=0 seen=""
  while read -r pid cwd; do
    case " $seen " in *" $cwd "*) continue;; esac
    proj="$HOME/.claude/projects/$(printf '%s' "$cwd" | sed 's#/#-#g')"
    if compgen -G "$proj"/*.jsonl >/dev/null 2>&1; then
      seen="$seen $cwd"
      tmux send-keys -t "$pid" C-u                 # 첫 키 유실 흡수
      tmux send-keys -t "$pid" "claude --continue"
      tmux send-keys -t "$pid" Enter
      n=$((n+1))
    fi
  done < <(tmux list-panes -s -t "$SESSION" -F '#{pane_id} #{pane_current_path}')
  echo "→ ${n}개 패널에서 'claude --continue' (스냅샷 없음)"
}

FIRST_WIN="${WTX_WINDOWS[0]%%:*}"
FIRST_TRUNK="$(echo "${WTX_WINDOWS[0]#*:}" | awk '{print $1}')"

FRESH=0
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "→ 새 session '$SESSION' 생성"
  tmux new-session -d -s "$SESSION" -n "__boot__" -c "$WTX_CODES/${WTX_PREFIX}${FIRST_TRUNK}"
  FRESH=1
  build_from_snapshot || echo "→ 스냅샷 없음 — 기본 배치로 생성"
fi

# config 정의 window — 빠진 것/pane 부족만 채움
for SPEC in "${WTX_WINDOWS[@]}"; do
  WIN="${SPEC%%:*}"; TRUNKS="${SPEC#*:}"
  DIRS=(); N=0
  for T in $TRUNKS; do DIRS+=("$WTX_CODES/${WTX_PREFIX}${T}"); N=$((N+1)); done
  if ! has_window "$WIN"; then
    echo "→ window '$WIN' 생성"; build_window "$WIN" "${DIRS[@]}"
  elif [ "$(pane_count "$WIN")" -lt "$N" ]; then
    echo "→ window '$WIN' panes 부족 — 재구성"
    tmux kill-window -t "${SESSION}:${WIN}"; build_window "$WIN" "${DIRS[@]}"
  fi
done
for SPEC in "${WTX_FREE_WINDOWS[@]:-}"; do
  [ -z "$SPEC" ] && continue
  WIN="${SPEC%%:*}"; N="${SPEC#*:}"
  if ! has_window "$WIN"; then
    DIRS=(); for _ in $(seq 1 "$N"); do DIRS+=("$WTX_CODES"); done
    echo "→ window '$WIN' 생성 (${N}컬럼)"; build_window "$WIN" "${DIRS[@]}"
  fi
done
has_window "__boot__" && tmux kill-window -t "${SESSION}:__boot__" 2>/dev/null || true
tmux move-window -r -t "$SESSION"

tmux set-option -t "$SESSION" -g automatic-rename off
tmux set-option -t "$SESSION" -g allow-rename off
tmux set-option -t "$SESSION" -g pane-border-status top
tmux set-option -t "$SESSION" -g pane-border-format ' #[fg=cyan,bold]#{b:pane_current_path}#[default] · #[fg=dim]#{pane_current_command}#[default] '

[ "$FRESH" = "1" ] && resume_panes

tmux select-window -t "${SESSION}:${FIRST_WIN}" 2>/dev/null || true
if [ "${WTX_NO_ATTACH:-0}" = "1" ]; then echo "→ attach 생략(검증용)"
elif [ -z "${TMUX:-}" ]; then exec tmux attach -t "$SESSION"
else tmux switch-client -t "$SESSION"; fi
