# 가드레일의 사유 — 실사고 기록 (일반화)

규칙만 남기면 다음 사람(미래의 나)이 "왜?"를 물으며 규칙을 무너뜨린다.
각 가드레일이 태어난 사고를 날짜와 함께 남긴다. 회사 특정 정보는 제거했다.

## 커밋 메시지 HEREDOC 줄바꿈 손실 (2026-04)
`git commit -m "$(cat <<EOF ...)"` 패턴이 도구 직렬화 단계에서 개행을 잃어 본문 전체가
subject 한 줄로 박혔다. PR 제목·머지 커밋까지 오염. → **파일 작성 + `git commit -F`** 로 고정.
검증은 `git log -1 --pretty=%s` / `%b` 로만 (커밋 직후 콘솔 요약은 개행을 눌러 보여줘 오진 유발).

## 공유 stash 스택 무인자 pop (2026-08-03)
git worktree 는 refs/stash 를 **전 워크트리가 공유**한다. 무인자 `git stash pop` 이 다른
세션의 stash 를 꺼냈다. → stash 금지. 불가피하면 `push -u -m "<태그>"` + SHA 캡처 + `apply`.

## 중단된 rebase 의 autostash (2026-09-01)
autostash 는 `stash list` 에 뜨지 않는다 — `.git/.../rebase-merge/autostash` 에만 있다.
중단된 rebase 를 두고 detached HEAD 만 보고 "유실됐다" 판단하기 쉽다.
→ fan-out 중 충돌은 **그 자리에서 즉시 `rebase --abort`** (autostash 자동 복원, 절대 방치 금지).

## macOS 대소문자 무시 → 브랜치 ref 오염 (2026-09-02)
기존 `refs/heads/CHORE/` 가 있는 상태에서 `chore/...` 브랜치를 만들면 **생성은 성공**하고
ref 는 조용히 `CHORE/...` 로 들어간다. push 시점에야 `cannot be resolved to branch` 실패.
→ 브랜치 TYPE 은 대문자로 통일. 이미 만들었으면 `git switch <대문자 이름>` 후 push.

## 문서에 박은 표는 반드시 썩는다 (2026-09-02)
포트 표("테스트 전용 8888")가 워크트리 개편 후 **남의 개발서버**를 가리키게 됐다.
잘못된 포트는 404 가 아니라 남의 코드가 정상 응답하므로 "테스트 통과"로 읽힌다 — 조용한 오염.
→ 환경값은 문서가 아니라 **런타임 도출**(.env 의 DEV_PORT) + curl 응답 확인 후 진행.

## 머지 커밋은 전 트렁크에 동일 SHA 로 복제된다 (2026-09-02)
push 흐름의 origin/<BASE> rebase 때문에, 머지된 커밋 하나가 모든 트렁크 히스토리에 나타난다.
"어느 워크트리에서 한 작업인가"는 git log 로 알 수 없다 — **브랜치 reflog 의 `commit:` 항목**이
유일한 진실이고, cherry-pick 이 SHA 를 바꾸므로 매칭 키는 커밋 subject 다. (daily-report 스킬의 근거)

## 참조 미러는 ff-only 로만 (2026-09-07)
메인 체크아웃이 697커밋 뒤처진 채 "무의식적 참조 기준점" 노릇을 하고 있었다.
→ 미러 브랜치 + `merge --ff-only`: 갈라져 있으면 한 글자도 안 건드리고 거부.
실수 커밋을 조용히 덮어쓰는 대신 요란하게 실패한다. 자동화에 이보다 나은 실패 방식은 없다.

## fan-out sync 를 자동화하지 않는 이유 (2026-09-02)
충돌은 abort 로 안전하다. 위험한 것은 **성공한 rebase** — 작업 중인 다른 세션이 읽어둔
파일들이 발밑에서 조용히 바뀌는데 아무 신호가 없다. 장기 작업 워크트리가 수십 커밋
뒤처지는 것은 정상이며(머지되면 0), 뒤처짐 감시는 불필요하다. 기준점은 미러가 맡는다.

## launchd 자동 저장이 8일간 조용히 실패 (2026-09-09)
10분마다 도는 스냅샷 잡이 9월 1일부터 매번 `FileNotFoundError: 'tmux'` 로 죽어 있었다.
launchd 의 기본 PATH 에는 `/opt/homebrew/bin` 이 없다. 수동 `wtx-save` 는 셸 PATH 라 멀쩡해서
아무도 몰랐고, 그 상태로 재부팅했으면 8일 전 대화로 돌아갔을 것이다.
→ plist 에 `EnvironmentVariables:PATH` 고정 + setup.sh 가 그 PATH 로 `tmux`/`python3` 를 찾는지 자가검증.
**검증은 반드시 자동 경로로** — `launchctl kickstart` 후 `LastExitStatus` 를 본다.

## 설정의 SoT 가 둘이면 조용히 진다 (2026-09-09)
tmux 런처가 매 실행마다 `pane-border-format` 을 옛 값으로 `set -g` 하고 있었다. tmux.conf 가
정의한 상태 칩·pane 이름이 "가끔" 사라지는 재현 불가 증상의 정체. 옵션 값 자체는 pane 에
남아 있었고 서식이 안 읽었을 뿐이라, `tmux source-file` 한 번에 돌아온다.
→ tmux 옵션은 tmux.conf 에서만. 런처는 배치만 만든다. **런처 검증은 격리 세션으로만**
(`WTX_SESSION=<임시> WTX_NO_ATTACH=1 WTX_NO_CLAUDE=1`) — 실 세션에 돌린 검증이 사고를 냈다.

## 화면 시각 매칭이 같은 cwd 의 대화를 뒤바꿨다 (2026-09-09, 2026-09-01 재발)
같은 폴더에 pane 이 여럿일 때 "화면의 `done H:MM` ↔ jsonl 마지막 시각" 최소거리 매칭이
p2·p3 를 서로 바꿔 배정했다(24분·56분 차이 경고는 냈다). 그런데 재부팅 복원으로 뜬 Claude 는
전부 `claude --resume <id>` 로 떠 있다 — **추정할 필요가 없는 확정값이 프로세스 인자에 있었다.**
→ ⓪ `ps` 의 `--resume` 인자를 tty 로 pane 에 잇는다. 시각 매칭은 인자 없는 pane 에만.
검증법: 스냅샷 6열 ↔ `ps -o tty,args` 의 `--resume` 을 pane tty 로 대조.

## Next turbopack 이 흘린 postcss 워커 231개 — 39GB (2026-09-09)
24GB 맥에서 load 170, 스왑 33.5/33.8GB. CPU 는 한가한데 진단 명령이 2분 타임아웃. 원인은
`next dev --turbopack` 이 PostCSS 용으로 띄우는 노드 워커 풀(4개씩)을 재생성할 때 옛 풀을
안 죽이는 것 — dev 서버 하나가 이틀 동안 146개(27GB)를 안고 있었다. `ps` 의 RSS 로는 안 보인다
(스왑돼서 1.4MB 로 찍힘) — `top -o cmprs` 의 압축 메모리 열로 봐야 진짜 크기다.
→ `pkill -f '.next/postcss.js'` 로 서버는 살린 채 39GB 즉시 회수(load 170→20, 재부팅 불필요).
근본 대책은 **끝난 dev 서버를 끄는 것** — 그래서 pane 칩에 서버 켜짐과 워커 수를 띄웠다.
