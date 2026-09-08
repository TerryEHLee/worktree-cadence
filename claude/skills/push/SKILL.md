---
name: push
description: >
  이슈 브랜치를 origin/main 과 정합 후 push → **원격 dev/staging 자동 머지** →
  로컬 트렁크를 origin/dev 에 autostash rebase 로 최신화 → 트렁크 즉시 복귀.
  WIP 손실 0 (autostash). 코드리뷰 경유(/pr)와 분리된 *빠른 자동 머지 경로*.
  main 머지는 수동 보호. Use when: push, push 해, /push, 푸시, 푸시해, 원격에 올려.
allowed-tools: Read, Bash, AskUserQuestion
---

# Push Workflow Skill

이 스킬의 책임 범위는 **엄격히 5가지**:

1. 이슈 브랜치를 원격 **`origin/main`** 과 정합 (fetch + autostash rebase + 충돌 해소)
2. 원격 push (`--force-with-lease`)
3. **원격 자동 머지 체인** — `이슈브랜치 → dev`, `dev → staging` (gh PR create + merge). **main 은 제외 (수동 보호)**
4. **로컬 트렁크 최신화** — 트렁크 복귀 후 `git rebase --autostash origin/dev` (dirty 여도 **항상** 실행)
5. 위 전 과정에서 **WIP 손실 0** 보장 (autostash)

**범위 밖 (다른 스킬에서 처리):**
- **코드리뷰 PR (pr skill)** — <리뷰어> 리뷰가 필요한 변경은 push 대신 `/pr`. push 는 *리뷰 없이 바로 dev/staging 까지 자동 머지하는 빠른 경로*. 둘은 명확히 구분된다
- **staging → main 머지** — staging QA 통과 후 사용자가 명시 요청할 때만 (별도 트리거)
- **Notion QA, Slack DM** — 명시 지시 시 별도
- commit (commit 스킬), branch 생성 (branch 스킬)

> **push vs pr (CRITICAL 구분)**
> - `push` = 리뷰 없이 **dev/staging 까지 자동 머지** + 트렁크 최신화. 빠른 셀프 경로.
> - `pr` = **<리뷰어> 코드리뷰** 거치는 dev PR 생성 (자동 머지 X). 리뷰가 필요한 변경에만.
> 한 변경은 둘 중 하나의 경로만 탄다. 같이 호출하지 않는다.

---

## ⚠️ 핵심 원칙 1: 트렁크 복귀가 빠를수록 좋다 (CRITICAL)

같은 워크트리에 동시 작동 중인 다른 세션이 있다. 이슈 브랜치에 머무는 시간이 길수록 다른 세션이 차단되거나 cross-contamination 위험이 생긴다. **머지 체인(STEP 5)이 끝나는 즉시 STEP 6 (트렁크 복귀 + 최신화)** 를 실행하고 스킬 종료. 트렁크는 늘 워크트리의 중심 상태로 유지한다.

## ⚠️ 핵심 원칙 2: 트렁크는 늘 origin/dev 최신을 유지한다 (CRITICAL)

다른 워크트리(hotfix/admin/studio)에서 머지된 작업은 **오직 원격(origin/dev)을 경유**해서만 이 트렁크로 들어온다. 워크트리끼리 직접 sync 되지 않는다. 그 유입 시점이 바로 STEP 6 의 `git rebase origin/dev` 다.

- **이전엔 트렁크가 dirty 면 STEP 6 동기화를 "보류" 했다 → 트렁크가 조용히 stale 누적되는 사고의 원인이었다.**
- **이제는 dirty 여도 `--autostash` 로 항상 최신화한다.** dirty 는 더 이상 최신화를 막는 사유가 아니다.

## ⚠️ 핵심 원칙 3: WIP 손실 0 (CRITICAL)

이 스킬은 절대 working tree 의 미커밋 변경(WIP)을 잃지 않는다.

- 모든 rebase 는 **`--autostash`** — git 이 rebase 전 자동 stash, 후 자동 pop 을 *한 트랜잭션*으로 보장. 수동 stash/pop 의 "pop 까먹음" 사고가 원천 차단됨.
- `git reset --hard`, `git checkout -- .`, `git clean` **절대 금지**.
- `--autostash` pop 이 충돌하면 git 이 멈추고 알려준다(변경은 stash 에 안전 보존) → 사용자에게 보고 후 수동 해소. **silent 유실 없음.**

> memory `feedback_stash_short_allowed`: "stash 금지" 는 *브랜치 분기 수단* 맥락. push 통과·rebase 용 mechanical autostash 는 예외 허용.

---

## 사전조건

- commit skill 로 트렁크에 commit + `origin/main` 기반 이슈 브랜치 cherry-pick 완료
- 푸시할 이슈 브랜치 base = `origin/main`, 그 위에 이번 이슈 commit (1개 또는 N개)

---

## STEP 1: 푸시 대상 식별 + 사용자 확인

1. `pwd` 로 워크트리 → 트렁크 결정 (**트렁크 = 폴더명 − `<repo>-`**: joshua/caleb/manna/studio/michael/gabriel/raphael/uriel. 구·은퇴예정: <repo>-admin→admin). `<repo>`(메인 체크아웃) 는 참조 미러(`mirror/dev`)라 push 대상이 아니다
2. `git log -1 <트렁크>` 로 트렁크 HEAD 확인
3. 푸시할 이슈 브랜치 식별 — 대화 히스토리 + `git for-each-ref --sort=-committerdate refs/heads/` 조합
4. 여러 후보면 `AskUserQuestion`
5. **사용자에게 plan 보여주고 OK 받기**:

```
📤 푸시 + 자동 머지 계획
워크트리: <name> → 트렁크: <trunk>
이슈 브랜치: <branch>
push 대상: origin/<branch> (force-with-lease)
자동 머지: <branch> → dev → staging  (원격, gh PR merge)
main: ❌ 제외 (staging QA 통과 후 별도 요청 시만)
트렁크 최신화: <trunk> ← origin/dev (--autostash, dirty 여도 실행)
리뷰: 없음 (리뷰 필요하면 push 대신 /pr)
진행할까요?
```

⚠️ 머지는 원격 dev/staging 을 건드리는 비가역 작업 → 반드시 사용자 OK 후 진행.

## STEP 2: fetch (read-only)

```bash
git fetch origin main dev staging
```

working tree / 로컬 브랜치 무손상. read-only download.

## STEP 3: 이슈 브랜치 이동 + rebase (vs origin/main)

```bash
git switch <issue-branch>
git rebase --autostash origin/main
```

- 브랜치 base 가 `origin/main` 이므로 rebase 대상도 `origin/main`
- `--autostash` 로 WIP 자동 보존 (STEP 1 트렁크의 미커밋 변경이 switch 로 carry-over 된 상태여도 안전)
- rebase 후 commit hash 변경 → force-with-lease 필요
- main 은 movement 가 적어 충돌 가능성 매우 낮음

### 충돌 발생 시 (CRITICAL)

1. 충돌 파일 + 충돌 영역 보고
2. `AskUserQuestion`:

```
⚠️ Rebase 충돌 (vs origin/main)
파일: <path>
충돌 영역: <hunk>
A. LLM 이 양측 의도 분석 후 해소안 제시 → 사용자 검토 → continue (기본 권장)
B. 사용자가 직접 해소 (지시 후 git rebase --continue)
C. rebase --abort (push 보류)
```

## STEP 4: Push

```bash
git push origin <issue-branch> --force-with-lease
```

- pre-push 풀 빌드 (1-3분). false positive (turbopack runtime chunk 등) 의심 시 memory `feedback_husky_turbopack_false_positive` / `feedback_root_cause_over_bypass` 참조 — root cause fix 우선, `--no-verify` 는 사용자 동의 후 최후수단
- 빌드 실패 시 보고 + 수정 후 재시도

## STEP 5: 원격 자동 머지 체인 — dev → staging (CRITICAL)

**모든 머지는 원격(GitHub)에서 `gh` CLI 로 수행** — 로컬 checkout/merge 없이 PR 생성 → 머지. 로컬/원격 불일치 충돌 방지.

PR title/body 는 commit 메시지에서 추출 (Claude/AI 언급·⏺ 금지, HEREDOC 줄바꿈 손실 방지 위해 body 는 Write tool 로 `/tmp` 파일 생성 후 `--body-file`).

### 5-1: 이슈브랜치 → dev

```bash
gh pr create --base dev --head <issue-branch> --title "<TITLE>" --body-file /tmp/pr-body.txt
gh pr merge <PR번호> --merge --delete-branch=false
```

### 5-2: dev → staging

```bash
gh pr create --base staging --head dev --title "<TITLE>" --body-file /tmp/pr-body.txt
gh pr merge <PR번호> --merge --delete-branch=false
rm /tmp/pr-body.txt
```

- `--delete-branch=false` 필수 (dev/staging 브랜치 보존)
- 이미 동일 base/head open PR 존재 시 중복 생성 X → 기존 PR 머지

### ⛔ main 자동 머지 금지

`staging → main` 은 자동 흐름에 **절대 포함하지 않는다**. staging QA 통과 후 사용자가 "main 머지" / "프로덕션 반영" 등 명시 요청 시에만 별도 진행.

### 머지 충돌 시

`gh pr merge` 실패 → 해당 단계·PR URL 보고 + 이후 머지 단계 중단 (트렁크 최신화 STEP 6 은 계속 진행):

```
⚠️ 원격 머지 충돌
단계: <이슈브랜치→dev | dev→staging>
PR: <url>
조치: GitHub 에서 충돌 해결 후 재시도.
```

> 주의: `dev → staging` 은 dev 전체를 staging 으로 올린다(다른 워크트리 머지분 포함). 기존 merge 스킬과 동일 동작. staging 이 dev 와 크게 벌어졌으면 사용자에게 알리고 확인.

## STEP 6: 트렁크 복귀 + 최신화 (CRITICAL — 머지 직후 즉시, dirty 여도 항상)

```bash
git switch <트렁크>
git fetch origin dev
git rebase --autostash origin/dev
```

- 방금 머지한 commit 은 cherry-pick 동등성으로 자동 스킵 → 깔끔
- 다른 워크트리가 origin/dev 에 머지한 모든 작업이 이 시점에 트렁크로 유입
- WIP 는 `--autostash` 로 보존 후 자동 복원 → **트렁크는 늘 "origin/dev 최신 + 본인 미푸시 누적 + WIP" 형태**
- **dirty 여도 보류하지 않는다.** autostash 가 처리.

### autostash pop 충돌 시 (드묾)

git 이 멈추고 충돌 보고 → WIP 는 stash 에 안전. 충돌 파일 보고 후 사용자와 해소. **절대 reset/discard 로 넘어가지 않는다.**

### <repo> 참조 미러 갱신 (한 줄, 항상)

```bash
bash $WTX_HOME/scripts/mirror-main-checkout.sh --quiet
```

`<repo>`(메인 체크아웃) 는 이 저장소의 **원본 체크아웃**(`.git` 실체가 거기 있고 나머지 워크트리가 그곳을 가리킨다)이라,
코드를 눈으로 확인할 때 무의식적으로 열게 되는 기준점이다. 그래서 이것만은 항상 최신으로 둔다.

- `<repo>`(메인 체크아웃) 는 **작업하지 않는 순수 참조 미러**다. 브랜치는 `mirror/dev`, 로컬 커밋이 있어서는 안 된다
- 명령은 `merge --ff-only` — 조금이라도 갈라져 있으면 **한 글자도 안 건드리고 거부**한다. `rebase`·`reset --hard` 를 쓰지 않는 이유
- push 는 방금 `origin/dev` 를 갱신했으므로 이 시점이 가장 정확하다. 비용 0.5초
- 별도로 launchd `com.wtx.mirror-sync` 가 30분마다 같은 스크립트를 돌린다 (남이 dev 에 머지한 경우까지 커버)
- ⚠️ 실패 메시지가 뜨면 **누군가 <repo> 에서 작업했다는 뜻**이다. 자동 해소하지 말고 사용자에게 보고한다

> <repo> 는 더 이상 `user` 트렁크 작업 워크트리가 아니다. 기존 WIP 는
> `archive/<repo>-user-wip-20260907` 브랜치에, 미머지 커밋 2개는 `user` 브랜치에 보존돼 있다 (2026-09-07).

### 다른 워크트리는? — 가능하지만 자동으로 하지 않는다

> ⚠️ **"git 이 차단해서 못 한다" 는 틀린 설명이다.** git 이 막는 것은 *남의 워크트리에
> 체크아웃된 브랜치를 `switch` 로 가져오는 것*뿐이고, **그 워크트리 안에서 그 브랜치를
> rebase 하는 것(`git -C <dir> rebase --autostash origin/dev`)은 정상 동작한다.**

자동으로 하지 않는 이유는 불가능해서가 아니라, **작업 중인 다른 세션의 발밑을 바꾸기 때문**이다.
그 워크트리의 미푸시 커밋이 origin/dev 와 충돌하면 rebase 가 멈추는데, 어느 쪽 의도를 살릴지는
그 작업을 하고 있는 세션만 판단할 수 있다. (2026-09-02 실측: 7개 중 joshua·caleb 2개가 충돌)

그래서 STEP 6 의 기본값은 **현재 워크트리 트렁크만** 최신화다.

장기 작업 중인 워크트리가 수십 커밋 뒤처지는 것은 **정상**이다 — 그 작업이 머지되면 0 이 된다.
뒤처짐 자체를 문제로 보고 감시할 필요는 없다. 눈으로 참고하는 기준점은 `<repo>`(메인 체크아웃) 미러가 맡는다.

#### fan-out sync 도구 (수동 실행)

```bash
bash $WTX_HOME/scripts/sync-all-worktrees.sh --dry-run   # 반드시 먼저. 뒤처짐·미커밋 수만 보고
bash $WTX_HOME/scripts/sync-all-worktrees.sh             # 실행
```

- 워크트리별 lock(mkdir 원자성) — 이미 잠겨 있으면 그 워크트리는 건너뜀
- rebase 진행 중인 워크트리는 건너뜀
- **studio 는 자동 제외** (별도 프로젝트)
- 이슈 브랜치·detached 는 건너뛰고 뒤처짐만 보고 (이슈 브랜치를 origin/dev 로 rebase 하는 것은 CLAUDE.md 금지사항)
- WIP 는 `--autostash` 로 보존. `reset --hard` / `checkout -- .` / `clean` 은 쓰지 않는다

#### 🚫 충돌 시 — 절대 중단 상태로 두지 않는다

fan-out 중 어느 워크트리가 충돌하면 **그 워크트리만 즉시 `git -C <dir> rebase --abort`** 하고 다음으로 넘어간다.
abort 는 autostash 를 되돌려 놓으므로(`Applied autostash`) WIP 손실이 없다.

```bash
git -C <dir> rebase --abort
git -C <dir> status --porcelain | wc -l   # rebase 전 파일 수와 일치하는지 확인
```

중단된 rebase 를 남겨두면 그 세션이 detached 상태를 만나고, autostash 는 `stash list` 에 뜨지 않아
(`.git/worktrees/<name>/rebase-merge/autostash` 에만 있음) 복구가 어려워진다.
충돌한 워크트리는 **그 세션이 자기 충돌을 해소하며 받아가도록 남긴다** — 대신 해소하지 않는다.

## STEP 7: 결과 보고

```
✅ Push + 자동 머지 + 트렁크 최신화 완료 — <branch>

- 이슈 브랜치 push: <hash> (origin/<branch>)
- 자동 머지: <branch> → dev ✅ / dev → staging ✅ / main ⏸ (수동 보호)
- 트렁크 복귀: <트렁크> ← origin/dev (autostash) <ok / pop 충돌:해소필요>
- WIP 보존: ✅ (autostash)

다음 단계:
  - staging Vercel preview 확인 → QA
  - QA 통과 후 "main 머지" 명시 요청 시 staging → main 진행
```

---

## 금지 사항 (CRITICAL)

- 🚫 **`staging → main` 자동 머지** — main 은 staging QA 통과 + 사용자 명시 요청 시에만
- 🚫 **이슈 브랜치를 `origin/dev` 로 rebase** — 브랜치 base 는 `origin/main`. dev 로 rebase 하면 main 에 없는 다른 워크트리 WIP 가 딸려와 main 머지가 더러워짐 (트렁크 rebase 대상만 origin/dev)
- 🚫 **트렁크 최신화(STEP 6) "보류"** — dirty 는 더 이상 보류 사유 아님. autostash 로 항상 실행
- 🚫 **`git reset --hard` / `git checkout -- .` / `git clean`** — WIP 유실 위험. autostash 외 stash 조작 금지
- 🚫 트렁크 자체를 push (`git push origin <트렁크>` 직접 push 금지 — 이슈 브랜치만)
- 🚫 `--force` (반드시 `--force-with-lease`)
- 🚫 PR/머지 메시지에 Claude/AI 언급, ⏺ 기호, HEREDOC 줄바꿈 손실 패턴
- 🚫 같은 변경에 push 와 `/pr` 동시 — 둘은 분리된 경로 (자동 머지 vs 리뷰)
