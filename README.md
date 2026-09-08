# worktree-cadence

한 저장소를 **git worktree 여러 개로 나눠, 병렬 Claude Code 세션들이 서로 밟지 않고
동시에 일하게 하는** 개인 개발 운영 체계. 커밋/푸시/원격 sync 루틴과 tmux 세팅까지
새 맥에서 `setup.sh` 한 번으로 재현하는 것이 목표다.

## 핵심 아이디어

```
                    origin/<MAIN>  ←(주1회 umbrella PR)─  origin/<staging>
                         │                                      ↑
        이슈 브랜치 base ─┘            자동 머지 체인 ────────────┤
                                                                │
   ISS-XXX/성격/상세  ──push──▶  origin/<BASE>  ◀─── 모든 트렁크가 rebase 로 수렴
        ▲ cherry-pick                  │
        │                              ▼ (원격 경유만 — 워크트리끼리 직접 sync 없음)
 ┌──────┴──────────────────────────────────────────────────┐
 │  worktrees:  joshua  caleb  manna  │ michael gabriel …  │   ← 트렁크 = 로컬 WIP 누적기
 │  (journey — 집중)                  │ (angels — 반응)     │
 └──────────────────────────────────────────────────────────┘
              메인 체크아웃 = mirror/<BASE> (읽기 전용 참조본, ff-only)
```

1. **케이던스 워크트리** — 워크트리를 '종류'가 아니라 **케이던스**로 나눈다.
   journey(장기 집중: 주력1·주력2·데일리) / angels(반응: 무색 교체 파견 슬롯).
   트렁크명 = 폴더명 − 접두어. 워크트리:커밋세션 = 1:1. 포트도 워크트리당 1개(.env 의 DEV_PORT).
2. **트렁크 = WIP 누적기** — 트렁크는 push 하지 않는다. 커밋 시점에 `origin/<MAIN>` 기반
   이슈 브랜치로 cherry-pick 해 깨끗한 패치만 내보내고, 트렁크는 `origin/<BASE>` 에
   `rebase --autostash` 로 지속 수렴한다 (WIP 손실 0).
3. **두 경로 머지** — push(리뷰 없이 BASE→staging 자동) / pr(리뷰 경로). MAIN 은 수동 보호.
4. **미러** — 메인 체크아웃은 작업하지 않는 참조본. `merge --ff-only` 라 갈라지면 거부만 한다.
5. **멀티세션 안전장치** — sync 는 mkdir lock 으로 같은 워크트리의 다른 세션 tool 을
   잠깐 세우고(PreToolUse hook), tmux 배지가 pane 별 Claude 상태(진행/승인대기/완료)를 색으로 보여준다.
6. **재부팅 복원** — 10분마다 tmux 배치 + pane 별 Claude 대화 ID 스냅샷.
   `wtx` 한 번으로 화면 그대로 + 각 pane 의 대화(`claude --resume <id>`)까지 복귀.

왜 이런 규칙들인지는 [docs/incidents.md](docs/incidents.md) — 전부 실사고에서 나왔다.

## 새 맥 셋업 (5분)

```bash
# 0) 선행: git, tmux, gh, Claude Code, (psql — daily-report 이슈트래커 연동 시)
git clone git@github.com:TerryEHLee/worktree-cadence.git ~/Desktop/codes/worktree-cadence
cd ~/Desktop/codes/worktree-cadence && ./setup.sh

# 1) 설정
vi ~/.config/wtx/config.sh        # 레포명·BASE/MAIN 브랜치·window 구성

# 2) 프로젝트 레포 준비
git clone <repo-url> ~/Desktop/codes/<repo>
cd ~/Desktop/codes/<repo>
git switch -c mirror/<BASE> origin/<BASE>          # 메인 체크아웃 = 미러

# 3) 워크트리 만들기 (트렁크명만 바꿔 반복)
git branch joshua origin/<BASE> 2>/dev/null || true
git worktree add ~/Desktop/codes/<repo>-joshua joshua
#   ... caleb, manna, michael, gabriel, raphael, uriel 반복
#   각 워크트리 <앱>/.env 에 DEV_PORT=<고유포트> 지정 (예: 7777/8888/9999/1111/2222/3333/4444)

# 4) Claude 연결
#   - claude/settings-hooks.json 의 hooks 를 ~/.claude/settings.json 에 병합
#   - claude/skills/* 를 프로젝트 레포 .claude/skills/ 로 복사 (placeholder 채우기)
#   - claude/commands/sync.md 를 ~/.claude/commands/ 로 복사
#   - claude/CLAUDE.md.template 를 프로젝트 CLAUDE.md 에 반영

# 5) 기동
source ~/.zshrc && wtx
```

## 구성

| 경로 | 내용 |
|:---|:---|
| `config.example.sh` | **유일한 설정** — 레포·브랜치·tmux window. 이직 = 이 파일 수정이 전부 |
| `setup.sh` | 새 맥 부트스트랩 (idempotent, 기존 설정 보존) |
| `scripts/` | sync-trunk(lock+autostash) · sync-on-event(훅, throttle) · tool-lock-guard · sync-all-worktrees(수동 fan-out) · mirror-main-checkout(ff-only) · tmux-claude-badge |
| `tmux/` | session-up(런처=`wtx`) · session-snapshot(=`wtx-save`, 10분 자동) · tmux.conf |
| `launchd/` | mirror-sync(30분) · tmux-snapshot(10분) 템플릿 |
| `claude/` | skills(branch·commit·push·merge·daily-report) · commands(sync) · settings-hooks.json · CLAUDE.md.template |
| `docs/incidents.md` | 각 가드레일이 태어난 실사고 기록 |

## 스킬 = 실행 가능한 프로세스 문서

`claude/skills/` 의 마크다운은 설명서가 아니라 Claude Code 가 그대로 따르는 **절차**다.
`<repo>`, `<BASE>`, `<리뷰어>` 같은 placeholder 를 프로젝트 값으로 채워 쓴다.

- `branch` / `commit` — 트렁크 커밋 → origin/<MAIN> 기반 이슈 브랜치 cherry-pick (이름 규칙·함정 포함)
- `push` — 원격 정합 → push → BASE/staging 자동 머지 → 트렁크 복귀 + autostash 최신화 + 미러 갱신
- `merge` — 머지 실행 + 리포트
- `daily-report` — 전 워크트리 변경을 reflog 기반으로 귀속해 일일 정리 (완료/진행중, 이슈 링크)
- `commands/sync` — 트렁크 수동 sync (lock + autostash)

## 원칙 요약

- 환경값(포트 등)은 문서에 박지 않는다 — 런타임 도출 (표는 반드시 썩는다)
- 파괴적 명령으로 문제를 풀지 않는다 — reset --hard 대신 브랜치 보존 + ff-only
- 자동화의 실패 방식이 안전한가부터 본다 — 갈라지면 "아무것도 안 하고 거부"가 최선
- 규칙에는 사유(사고)를 함께 남긴다 — 사유 없는 규칙은 무너진다
