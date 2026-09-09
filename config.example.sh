#!/usr/bin/env bash
# wtx config — 워크트리 케이던스 시스템의 유일한 설정 파일.
# 설치: 이 파일을 ~/.config/wtx/config.sh 로 복사한 뒤 프로젝트에 맞게 수정한다.
# 모든 스크립트·훅이 이 파일 하나만 source 하므로, 이직/새 프로젝트 = 이 파일 수정이 전부다.

# ── 저장소 ──────────────────────────────────────────────
WTX_CODES="$HOME/Desktop/codes"     # 워크트리들이 사는 부모 디렉터리
WTX_REPO="myrepo"                   # 메인 체크아웃 폴더명 (= .git 실체가 있는 원본)
WTX_PREFIX="${WTX_REPO}-"           # 워크트리 폴더 접두어. 트렁크명 = 폴더명 − 접두어

# ── 브랜치 ──────────────────────────────────────────────
WTX_BASE="dev"                      # 원격 통합 브랜치 — 트렁크가 지속 rebase 하는 대상
WTX_MAIN="main"                     # 보호 브랜치 — 이슈 브랜치의 base
WTX_MIRROR_BRANCH="mirror/${WTX_BASE}"   # 메인 체크아웃이 참조 미러로 쓸 브랜치

# ── tmux ────────────────────────────────────────────────
WTX_SESSION="cadence"               # tmux 세션명
# window 정의: "윈도우명:트렁크1 트렁크2 ..." (트렁크명만 — 폴더는 접두어가 붙는다)
# 케이던스 세계관: journey = 집중(주력·데일리) / angels = 반응(무색 교체 파견)
WTX_WINDOWS=(
  "journey:joshua caleb manna"
  "angels:michael gabriel raphael uriel"
)
# 워크트리 아닌 자유 pane 윈도우 (개인 트랙 런치패드 등). 비우면 생성 안 함
WTX_FREE_WINDOWS=( "personal:4" )   # "윈도우명:pane수" — cwd 는 WTX_CODES

# ── 개발 서버 ────────────────────────────────────────────
# 포트는 여기 적지 않는다. 각 워크트리의 .env 의 DEV_PORT 가 SoT 다.
# (표를 문서·설정에 박으면 반드시 썩는다 — 실측으로 증명된 규칙)
# pane 테두리의 ⚡ 칩도 하드코딩이 아니라 실제 LISTEN 중인 프로세스의 cwd 로 워크트리를 찾는다.
#
# Ctrl+a s 메뉴 "켜기" 가 <워크트리>-dev tmux 세션에서 실행할 명령. "창이름=명령" 을 | 로 나열.
# 폴더명별 예외만 적고, 나머지는 WTX_DEV_DEFAULT.
WTX_DEV_DEFAULT="dev=pnpm dev"
WTX_DEV_START=(
  "${WTX_PREFIX}studio:studio=pnpm dev:studio|profilier=pnpm --filter profilier dev"
)
WTX_DEV_LEAK_WARN=8                 # 워크트리당 .next/postcss.js 워커가 이 수를 넘으면 주황 wN 경고

# ── 기타 ────────────────────────────────────────────────
WTX_SYNC_THROTTLE=180               # 이벤트 sync 시 fetch 최소 간격(초)
