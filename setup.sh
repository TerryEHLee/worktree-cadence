#!/usr/bin/env bash
# setup.sh — 새 맥에서 워크트리 케이던스 시스템 설치 (idempotent — 재실행 안전)
#
#   1) ~/.config/wtx/config.sh 생성 (없을 때만 — 있으면 절대 안 덮어씀)
#   2) ~/.config/wtx/home → 이 레포 심볼릭 링크 (레포가 SoT, git pull = 업데이트)
#   3) ~/.tmux.conf 설치 (기존 파일은 .bak 백업)
#   4) zshrc 에 alias 블록 추가 (wtx / wtx-save / 스킬용 WTX_HOME)
#   5) launchd 등록 (mirror-sync 30분 · tmux-snapshot 10분)
#   6) Claude 훅 안내 (settings.json 은 자동 수정하지 않음 — 스니펫 병합 안내만)
#
# 이후 할 일:
#   - ~/.config/wtx/config.sh 를 프로젝트에 맞게 수정
#   - 프로젝트 레포에 claude/skills/* 복사, CLAUDE.md.template 반영
#   - git worktree add 로 트렁크들 생성 (README 의 "워크트리 만들기")
set -euo pipefail
WTX_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="$HOME/.config/wtx"
mkdir -p "$CFG_DIR" "$HOME/.config/wtx/logs"

# 1) config
if [ ! -f "$CFG_DIR/config.sh" ]; then
  cp "$WTX_SRC/config.example.sh" "$CFG_DIR/config.sh"
  echo "✅ config 생성: $CFG_DIR/config.sh  ← 프로젝트에 맞게 수정할 것"
else
  echo "⏭️  config 이미 있음 (보존): $CFG_DIR/config.sh"
fi

# 2) 레포 링크 — 스크립트 경로의 고정점
ln -sfn "$WTX_SRC" "$CFG_DIR/home"
echo "✅ $CFG_DIR/home → $WTX_SRC"

# 3) tmux.conf
if [ -f "$HOME/.tmux.conf" ] && ! cmp -s "$WTX_SRC/tmux/tmux.conf" "$HOME/.tmux.conf"; then
  cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak-wtx-$(date +%Y%m%d)"
  echo "ℹ️  기존 ~/.tmux.conf → .bak 백업"
fi
cp "$WTX_SRC/tmux/tmux.conf" "$HOME/.tmux.conf"
echo "✅ ~/.tmux.conf 설치"

# 4) zshrc alias (마커 블록 — 중복 추가 방지)
ZRC="$HOME/.zshrc"; MARK="# >>> wtx (worktree-cadence) >>>"
if ! grep -qF "$MARK" "$ZRC" 2>/dev/null; then
  cat >> "$ZRC" <<ZEOF

$MARK
export WTX_HOME="\$HOME/.config/wtx/home"
alias wtx='bash "\$WTX_HOME/tmux/session-up.sh"'
alias wtx-save='bash "\$WTX_HOME/tmux/session-snapshot.sh"'
# <<< wtx <<<
ZEOF
  echo "✅ ~/.zshrc 에 alias 추가 (wtx / wtx-save)"
else
  echo "⏭️  zshrc alias 이미 있음"
fi

# 5) launchd
for P in com.wtx.mirror-sync com.wtx.tmux-snapshot; do
  DST="$HOME/Library/LaunchAgents/$P.plist"
  sed -e "s|__WTX_HOME__|$WTX_SRC|g" -e "s|__LOG_DIR__|$CFG_DIR/logs|g" "$WTX_SRC/launchd/$P.plist" > "$DST"
  launchctl unload "$DST" 2>/dev/null || true
  launchctl load "$DST"
  echo "✅ launchd 등록: $P"
done
# launchd 는 로그인 셸 PATH 를 모른다 — plist 에 박은 PATH 로 tmux/python3 가 잡히는지 여기서 확인.
# (수동 실행이 되니 자동도 되겠지, 가 8일짜리 무음 실패를 만들었다 — docs/incidents.md)
LPATH="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$HOME/Library/LaunchAgents/com.wtx.tmux-snapshot.plist" 2>/dev/null || echo /usr/bin:/bin)"
for BIN in tmux python3; do
  if PATH="$LPATH" command -v "$BIN" >/dev/null 2>&1; then echo "✅ launchd PATH 에서 $BIN 확인"
  else echo "❌ launchd PATH($LPATH) 에서 $BIN 을 못 찾음 — plist 의 PATH 에 설치 경로를 추가할 것"; fi
done

# 6) Claude 훅 안내
echo
echo "── 남은 수동 단계 ─────────────────────────────────────"
echo "① $CFG_DIR/config.sh 수정 (레포명·브랜치·window 구성)"
echo "② claude/settings-hooks.json 의 hooks 를 ~/.claude/settings.json 에 병합"
echo "   (__WTX_HOME__ → $WTX_SRC 로 치환해서)"
echo "③ 프로젝트 레포에 claude/skills/* 복사 + CLAUDE.md.template 반영"
echo "④ README '워크트리 만들기' 절차로 트렁크 생성 → wtx 로 tmux 기동"
echo "⑤ 하루 지나면 launchctl list com.wtx.tmux-snapshot | grep LastExit 가 0 인지 한 번 확인"
