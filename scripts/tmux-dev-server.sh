#!/usr/bin/env bash
# tmux-dev-server.sh — pane 테두리에 그 워크트리 dev 서버의 켜짐/꺼짐을 보여주고, 메뉴로 켜고 끈다
#
#   ⚡ 7777     민트   dev 서버 LISTEN 중 (포트). 여러 앱이면 "5555 6006" 처럼 나열
#   ○ dev      회색   워크트리인데 서버 없음
#   w12        주황   turbopack postcss 워커 누수 경고 (WTX_DEV_LEAK_WARN 초과) — 메뉴에서 정리
#   (없음)            워크트리가 아닌 pane (예: WTX_CODES 자체)
#
# 상태 SoT: pane 옵션 @dev ("off" | "7777" | "5555 6006" | "") · @devw (누수 워커 수 | "")
#   테두리 서식(tmux.conf pane-border-format)은 이 옵션만 읽는다 — 서식 안 셸아웃 없음.
#   갱신은 status-right 의 #() 이 status-interval 마다 `refresh` 를 한 번 부른다 (lsof 1회 ≈ 40ms).
#   **포트 하드코딩 없음** — 실제 LISTEN 중인 node 프로세스의 cwd 로 워크트리에 귀속시킨다.
#   (문서·설정에 박은 포트 표는 반드시 썩는다 — docs/incidents.md)
#
# 사용:
#   tmux-dev-server.sh refresh            모든 pane 의 @dev/@devw 재계산 (바뀐 것만 set, 바뀌면 refresh-client)
#   tmux-dev-server.sh menu    <pane_id>  그 pane 워크트리의 dev 서버 메뉴 (Ctrl+a s)
#   tmux-dev-server.sh toggle  <pane_id>  켜져 있으면 끄고, 꺼져 있으면 켠다
#   tmux-dev-server.sh start   <pane_id>  <워크트리>-dev tmux 세션에서 시작 명령 실행 (로그는 그 세션에 남는다)
#   tmux-dev-server.sh stop    <pane_id>  next dev + next-server + postcss 워커 + <워크트리>-dev 세션 정리
#   tmux-dev-server.sh logs    <pane_id>  <워크트리>-dev 세션을 팝업으로 attach (팝업 안 Ctrl+a d 로 닫기)
#   tmux-dev-server.sh workers <pane_id>  그 워크트리의 누수 postcss 워커만 kill (서버는 유지)
#
# 워크트리 = $WTX_CODES/<폴더>. pane cwd 가 그 아래면 그 워크트리 소속 (메인 체크아웃·개인 레포 포함).
# 시작 명령은 config.sh 의 WTX_DEV_START / WTX_DEV_DEFAULT.
# macOS 기본 bash 3.2 — 연관 배열 없음. 표는 임시 파일 + awk 로.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_wtx-lib.sh"
CODES="$WTX_CODES"
LEAK_WARN="${WTX_DEV_LEAK_WARN:-8}"
DEFAULT_START="${WTX_DEV_DEFAULT:-dev=pnpm dev}"

# 워크트리 폴더명 → 시작 명령. "창이름=명령" 을 `|` 로 나열 → <wt>-dev 세션에 창 하나씩.
# (공백 구분은 명령 안 공백에 쪼개진다 — 실측: "dev=pnpm dev" 가 창 2개로 갈라짐)
start_cmds() {
  local spec
  for spec in "${WTX_DEV_START[@]:-}"; do
    [ -z "$spec" ] && continue
    [ "${spec%%:*}" = "$1" ] && { echo "${spec#*:}"; return; }
  done
  echo "$DEFAULT_START"
}

wt_of_path() {                       # $CODES/myrepo-joshua/apps/web → myrepo-joshua
  case "$1" in
    "$CODES"/*) local rest="${1#"$CODES"/}"; echo "${rest%%/*}" ;;
    *) echo "" ;;
  esac
}
wt_of_pane() { wt_of_path "$(tmux display -p -t "$1" '#{pane_current_path}' 2>/dev/null)"; }

# ── 실측 → 표: "PORTS\t<wt>\t<ports>" / "WORKERS\t<wt>\t<n>" ────────────────────
scan() {
  local tmp; tmp=$(mktemp -t devscan) || return 1
  # 1) LISTEN 중인 node/next 계열: "pid port"
  lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null | awk '
    /^p/ { pid = substr($0, 2); cmd = "" }
    /^c/ { cmd = substr($0, 2) }
    /^n/ { if (cmd ~ /^(node|next)/) { n = split($0, a, ":"); if (a[n] ~ /^[0-9]+$/) print pid, a[n] } }' > "$tmp.ports"
  # 2) 그 pid 들의 cwd: "pid cwd"
  local pids; pids=$(awk '{print $1}' "$tmp.ports" | sort -u | paste -sd, -)
  : > "$tmp.cwd"
  [ -n "$pids" ] && lsof -a -p "$pids" -d cwd -Fpn 2>/dev/null | awk '
    /^p/ { pid = substr($0, 2) }
    /^n/ { print pid, substr($0, 2) }' > "$tmp.cwd"
  # 3) 조인: pid→워크트리→포트 (IPv4/IPv6 중복 제거, 숫자 정렬)
  awk -v C="$CODES/" '
    NR == FNR { if (index($2, C) == 1) { r = substr($2, length(C) + 1); sub(/\/.*/, "", r); wt[$1] = r } next }
    ($1 in wt) { print "PORT\t" wt[$1] "\t" $2 }' "$tmp.cwd" "$tmp.ports" | sort -u -t $'\t' -k2,2 -k3,3n \
    | awk -F'\t' '{ p[$2] = p[$2] " " $3 } END { for (w in p) { sub(/^ /, "", p[w]); printf "PORTS\t%s\t%s\n", w, p[w] } }'
  # 4) postcss 워커 수 (워크트리별) — Next turbopack 이 흘리는 `.next/postcss.js` 노드 프로세스
  ps -Ao args 2>/dev/null | grep -F '.next/postcss.js' | grep -v grep | awk -v C="$CODES/" '
    { i = index($0, C); if (i) { r = substr($0, i + length(C)); sub(/\/.*/, "", r); n[r]++ } }
    END { for (w in n) printf "WORKERS\t%s\t%d\n", w, n[w] }'
  rm -f "$tmp" "$tmp.ports" "$tmp.cwd"
}

refresh() {
  local table; table=$(mktemp -t devtable) || return 1
  scan > "$table"
  local changed=0 pid cwd cur_dev cur_w wt want_dev want_w n
  while IFS=$'\t' read -r pid cwd cur_dev cur_w; do
    wt=$(wt_of_path "$cwd")
    if [ -z "$wt" ]; then want_dev=""; want_w=""
    else
      want_dev=$(awk -F'\t' -v W="$wt" '$1=="PORTS" && $2==W {print $3}' "$table"); want_dev="${want_dev:-off}"
      n=$(awk -F'\t' -v W="$wt" '$1=="WORKERS" && $2==W {print $3}' "$table"); n="${n:-0}"
      want_w=""; [ "$n" -gt "$LEAK_WARN" ] && want_w="$n"
    fi
    if [ "$cur_dev" != "$want_dev" ]; then tmux set-option -p -t "$pid" @dev "$want_dev"; changed=1; fi
    if [ "$cur_w" != "$want_w" ]; then tmux set-option -p -t "$pid" @devw "$want_w"; changed=1; fi
  done < <(tmux list-panes -a -F $'#{pane_id}\t#{pane_current_path}\t#{@dev}\t#{@devw}' 2>/dev/null)
  rm -f "$table"
  # 테두리 칩은 refresh-client -S 로는 안 다시 그려진다 (status 전용) → 전이 때만 전체 refresh
  [ "$changed" = 1 ] && tmux refresh-client 2>/dev/null
  return 0
}

# ── 제어 ─────────────────────────────────────────────────────────────────────
dev_session() { echo "${1}-dev"; }
TAIL="; echo; echo '[dev 종료 — 아무 키나 누르면 닫힙니다]'; read -r _"

start() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane")
  [ -n "$wt" ] || { tmux display -t "$pane" "이 pane 은 워크트리가 아닙니다"; return 1; }
  local sess; sess=$(dev_session "$wt")
  local first=1 entry name cmd
  local IFS='|'
  for entry in $(start_cmds "$wt"); do
    name="${entry%%=*}"; cmd="${entry#*=}"
    if [ "$first" = 1 ]; then
      tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess"
      tmux new-session -d -s "$sess" -n "$name" -c "$CODES/$wt" "$cmd$TAIL"
      first=0
    else
      tmux new-window -d -t "$sess" -n "$name" -c "$CODES/$wt" "$cmd$TAIL"
    fi
  done
  tmux display -t "$pane" "⚡ $wt dev 서버 시작 — 로그: Ctrl+a s → 로그 보기"
  # 포트가 뜨기까지 잠시 걸린다 — 백그라운드로 몇 번 재계산
  ( for _ in 1 2 3 4 5 6; do sleep 5; refresh; done ) >/dev/null 2>&1 &
}

stop() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane")
  [ -n "$wt" ] || return 1
  local root="$CODES/$wt" sess p; sess=$(dev_session "$wt")
  # 1) next dev / dev.mjs 부모 → 그 자식(next-server) 까지. args 에 워크트리 경로가 박혀 있다.
  for p in $(pgrep -f "$root/.*(next(/dist/bin/next)? dev|scripts/dev\.mjs)"); do
    pgrep -P "$p" | xargs kill -TERM 2>/dev/null; kill -TERM "$p" 2>/dev/null
  done
  # 2) 누수 워커
  pkill -f "$root/.*\.next/postcss\.js" 2>/dev/null
  # 3) 로그 세션 (turbo/pnpm 은 이 셸의 자식이라 같이 정리된다)
  tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess"
  sleep 1
  # 4) 그래도 그 워크트리 cwd 로 LISTEN 하는 놈이 남았으면 강제
  if scan | awk -F'\t' -v W="$wt" '$1=="PORTS" && $2==W {f=1} END {exit !f}'; then
    for p in $(lsof -nP -iTCP -sTCP:LISTEN -Fp 2>/dev/null | sed -n 's/^p//p'); do
      case "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" in "$root"/*|"$root") kill -KILL "$p" 2>/dev/null ;; esac
    done
  fi
  refresh
  tmux display -t "$pane" "■ $wt dev 서버 종료"
}

toggle() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane")
  [ -n "$wt" ] || { tmux display -t "$pane" "이 pane 은 워크트리가 아닙니다"; return 1; }
  local cur; cur=$(tmux display -p -t "$pane" '#{@dev}')
  if [ -n "$cur" ] && [ "$cur" != off ]; then stop "$pane"; else start "$pane"; fi
}

logs() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane"); local sess; sess=$(dev_session "$wt")
  if ! tmux has-session -t "$sess" 2>/dev/null; then
    tmux display -t "$pane" "$wt 의 로그 세션이 없습니다 (이 메뉴로 켠 서버만 로그가 남습니다)"; return 1
  fi
  # 팝업 안에서 중첩 attach. 닫기 = 팝업 안에서 Ctrl+a d (detach)
  tmux display-popup -E -t "$pane" -w 92% -h 88% -T " $sess — Ctrl+a d 로 닫기 " "TMUX= tmux attach -t $sess"
}

workers() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane"); [ -n "$wt" ] || return 1
  local n; n=$(pgrep -f "$CODES/$wt/.*\.next/postcss\.js" | wc -l | tr -d ' ')
  pkill -f "$CODES/$wt/.*\.next/postcss\.js" 2>/dev/null
  refresh
  tmux display -t "$pane" "🧹 $wt postcss 워커 ${n}개 정리 (서버는 유지 — 다음 CSS 컴파일 때 4개 새로 뜸)"
}

menu() {
  local pane="$1" wt; wt=$(wt_of_pane "$pane")
  [ -n "$wt" ] || { tmux display -t "$pane" "이 pane 은 워크트리가 아닙니다"; return 1; }
  local cur w; cur=$(tmux display -p -t "$pane" '#{@dev}'); w=$(tmux display -p -t "$pane" '#{@devw}')
  local me="bash $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tmux-dev-server.sh"
  local toggle_label
  if [ -n "$cur" ] && [ "$cur" != off ]; then toggle_label="■  끄기  (⚡ $cur)"
  else toggle_label="⚡  켜기  ($(start_cmds "$wt" | sed 's/[a-z]*=//g; s/|/  ·  /g'))"; fi
  local worker_label="🧹  누수 워커 정리"; [ -n "$w" ] && worker_label="🧹  누수 워커 정리  (w$w  ⚠)"
  tmux display-menu -t "$pane" -T "#[align=centre bold] dev 서버 · $wt " -x P -y P \
    "$toggle_label"      s "run-shell -b '$me toggle $pane'" \
    "󰈙  로그 보기"        l "run-shell -b '$me logs $pane'" \
    "" \
    "$worker_label"      w "run-shell -b '$me workers $pane'" \
    "↻  상태 새로고침"    r "run-shell -b '$me refresh'" \
    "" \
    "닫기"               q ""
}

case "${1:-}" in
  refresh) refresh ;;
  menu|toggle|start|stop|logs|workers) "$1" "${2:?pane_id 필요}" ;;
  *) sed -n '2,25p' "$0"; exit 1 ;;
esac
