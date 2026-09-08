#!/usr/bin/env bash
# _wtx-lib.sh — 공통 config 로더. 모든 wtx 스크립트가 처음에 source 한다.
WTX_CONFIG="${WTX_CONFIG:-$HOME/.config/wtx/config.sh}"
if [ ! -f "$WTX_CONFIG" ]; then
  echo "❌ wtx config 없음: $WTX_CONFIG  (config.example.sh 를 복사해 만들 것)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$WTX_CONFIG"

# 폴더명 → 트렁크명. 메인 체크아웃(WTX_REPO)은 트렁크가 아니라 미러다.
wtx_trunk_of() {  # $1 = 폴더 basename
  case "$1" in
    "$WTX_REPO")      echo "" ;;                 # 미러 — 트렁크 아님
    "$WTX_PREFIX"*)   echo "${1#"$WTX_PREFIX"}" ;;
    *)                echo "" ;;
  esac
}
