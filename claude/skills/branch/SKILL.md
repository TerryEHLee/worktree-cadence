---
name: branch
description: >
  새 작업 브랜치 생성. Use when the user asks to create a branch,
  브랜치, 브랜치 만들어, 새 브랜치, 브랜치 생성, new branch,
  작업 시작, 이슈 시작.
allowed-tools: Bash, AskUserQuestion
---

# Branch Skill

이슈 번호 기반으로 일관된 네이밍의 새 작업 브랜치를 생성합니다.
**매 작업마다 브랜치를 새로 만들 때 사용**하는 skill입니다.

---

## 워크트리 ↔ 트렁크 매핑 (브랜치 base 는 늘 `origin/main`)

<repo> 프로젝트는 **워크트리별로 트렁크가 다름**. 그러나 **새 이슈 브랜치의 base 는 워크트리와 무관하게 늘 `origin/main`**.
트렁크 이름은 브랜치 네이밍의 두 번째 슬롯에 들어가 "어느 워크트리에서 만들어졌는지" 표시 용도.

**트렁크명 = 워크트리 폴더명 − `<repo>-` 접두어** (네이밍 두 번째 슬롯용):

| 세션 | 워크트리 → 트렁크 |
|:---|:---|
| journey | `joshua` · `caleb` · `manna` · `studio` |
| angels | `michael` · `gabriel` · `raphael` · `uriel` |
| 구·은퇴예정 | <repo>-admin→`admin` |
| 참조 미러 | `<repo>`(메인 체크아웃) → **작업 워크트리 아님.** `mirror/dev` 브랜치로 origin/dev 를 그대로 반영하는 읽기용 참조본 (2026-09-07 전환) |

`git rev-parse --show-toplevel` 으로 워크트리 인식.

**왜 base 가 `origin/main` 인가:**
- 트렁크/origin/dev 에는 다른 워크트리·이슈의 미완성 WIP 가 누적돼 있음
- 그 위에서 분기하면 push 브랜치에 남의 WIP 가 딸려와 main 머지 시 매번 분리 작업 필요
- **`origin/main` base 면 dev / staging / main 어디든 그대로 머지 가능** — 깔끔한 패치 보장
- 트렁크는 트렁크대로 origin/dev 와 sync 유지 (다른 워크트리 최신 반영). 두 흐름 분리가 핵심

---

## 브랜치 네이밍 컨벤션 (commit skill 과 동일)

### 포맷

```
이슈 있음:  ISS-XXX/<트렁크>/<섹션>-<상세>
이슈 없음:  <TYPE>/<트렁크>/<섹션>-<상세>
```

**예시:**
```
ISS-103/user/mypage-matching-card
ISS-241/hotfix/api-member-info-update
ISS-104/admin/salary-calculator
CHORE/infra/husky-and-commit-skill
REFACTOR/admin/team-management-naming
```

⚠️ **트렁크명을 첫 component 로 쓰지 말 것** — git ref 충돌 (트렁크 브랜치가 같은 이름의 파일 ref 라 동명 디렉토리 못 생김).

### 각 세그먼트 규칙

#### 1. 첫 슬롯 — `ISS-XXX` 또는 `<TYPE>`

- 이슈 있으면: `ISS-<숫자>` (이슈 트래커 티켓 번호)
- 이슈 없으면: **대문자** TYPE 을 첫 슬롯에 — `CHORE` | `FEATURE` | `REFACTOR` | `DOCS` | `TEST` | `INFRA`
  🚫 소문자 금지 — macOS 는 대소문자를 구분하지 않아 기존 `refs/heads/CHORE/` 안으로 들어가고,
  `git switch -c` 는 성공하지만 나중에 `git push` 가 `cannot be resolved to branch` 로 실패한다

#### 2. 두번째 슬롯 — `<성격>` (변경이 무엇을 건드렸나)

`user` | `admin` | `hotfix` | `api` | `shared` | `infra` 중 하나. **commit 스킬의 `<성격>` 과 같은 값이다.**

판정 순서:
1. 이슈 트래커 `category` (admin PG `issues.category`) — 가장 강한 근거
2. 변경 파일 경로 — `app/(user)/`→`user` · `app/admin/`·`features/admin/`→`admin` ·
   `app/api/`→`api` · `shared/`·`entities/`→`shared` · `.husky/`·`.claude/`·root 설정→`infra`
3. 운영 중 버그면 `hotfix` (경로와 무관하게 우선)

🚫 **워크트리·트렁크 이름 금지** (`michael`·`gabriel`·`joshua`·`caleb`·`manna`·`garden`·`studio` 등).
워크트리 이름은 "어느 세션이 작업했나" 일 뿐이고, 브랜치는 "무엇을 건드렸나" 를 말해야
원격 브랜치 목록만 보고 성격이 읽힌다.

> 워크트리가 4개(user/fix/admin/studio)이던 시절엔 트렁크명과 성격이 우연히 같았다.
> 워크트리가 11개로 늘면서 갈라졌다 — 이 슬롯은 **성격** 쪽이다.

#### 3. 세번째 슬롯 — `<섹션>-<상세>` (작업 설명)

- **케밥 케이스** (소문자 + 하이픈)
- **페이지/영역 우선** → 구체적 대상 순서
  - `mypage-matching-card` (페이지 + 대상)
  - `admin-salary-calculator` (영역 + 기능)
  - `api-consultations-source` (API + 엔드포인트)
- 길이: 15~30자 권장
- 불필요한 관사·접속사 제거 (`a`, `the`, `and` 등)

### 페이지명 표기 규칙

| 실제 경로 | 브랜치 표기 |
|-----------|-------------|
| `/mypage` | `mypage` |
| `/mypage/matching` | `mypage-matching` |
| `/personal-info/base-info` | `profile-base-info` |
| `/admin/user-management` | `admin-user-mgmt` |
| `/admin/manager-assignment` | `admin-manager-assign` |
| API 라우트 | `api-<endpoint>` |
| 공용 컴포넌트 | `shared-<component>` |

### 전체 브랜치 길이 가이드

| 길이 | 판정 |
|------|------|
| ~40자 | 권장 |
| ~50자 | 허용 |
| 50자 초과 | 회피 (tab 자동완성 불편, CI/CD 로그 가독성 저하) |

---

## STEP 1: 사용자 정보 수집

다음 정보를 **순서대로** 확인한다. 이미 사용자 메시지에 포함되어 있으면 스킵.

1. **이슈 번호** — `ISS-XXX` 형식
2. **작업 유형** — fix / feat / refactor / chore / test / docs / style / perf
3. **작업 대상 페이지/영역** — `/mypage`, `/admin/...`, `api/...` 등
4. **간단한 설명** — 무엇을 수정/추가하는지

부족한 정보가 있으면 `AskUserQuestion`으로 묻는다.

## STEP 2: 브랜치명 조합 + 확인

수집한 정보를 조합:

```
이슈 있음:  ISS-XXX/<트렁크>/<섹션>-<상세>
이슈 없음:  <TYPE>/<트렁크>/<섹션>-<상세>
```

사용자에게 확인:

```
📋 브랜치 생성 확인
• 브랜치명: ISS-103/user/mypage-matching-card
• base: origin/main (원격 최신 fetch 후)
• 워크트리: <repo> (트렁크: user)
• 길이: 34자

이대로 브랜치를 만들까요?
```

**사용자 확인 후에만 STEP 3으로 진행한다.**

## STEP 3: 브랜치 생성 (base = `origin/main`)

### 3-1: 미커밋 변경 확인

```bash
git status --porcelain
```

변경이 있으면 사용자에게:
- 트렁크에서 커밋 먼저 (`commit skill` 흐름 권장 — 트렁크 commit → cherry-pick)
- branch skill 로 그대로 진행하면 working tree carry-over (origin/main 과 충돌 가능성)
- 취소

**기본 권장: commit skill 사용**. branch skill 은 깨끗한 시작 (working tree 비어있을 때) 용도.

### 3-2: origin/main 최신화 + 새 브랜치 생성

```bash
git fetch origin main
git switch -c <브랜치명> origin/main
```

- 트렁크 위가 아니라 **`origin/main` 위에 새 브랜치**
- 트렁크 / 다른 워크트리 / origin/dev 의 WIP 일절 영향 X
- 이 브랜치는 push 시 dev/staging/main 어디든 그대로 머지 가능

⚠️ `git pull origin main` 금지 — 항상 `fetch` + `switch -c ... origin/main`. pull 은 트렁크에서 안 함, 이슈 브랜치에서만 (push skill rebase 시).

### 3-3: 결과 확인

```bash
git branch --show-current
git log --oneline -3   # origin/main 최신 commit 만 보여야 함
```

## STEP 4: 결과 보고

```
✅ 브랜치 생성 완료
─────────────────────────────────
• 이름: ISS-103/user/mypage-matching-card
• base: origin/main @ <최신 커밋 해시>
• 상태: 작업 준비 완료 (깨끗한 main 위)
─────────────────────────────────

다음 단계: 작업 진행 → /commit (cherry-pick 흐름) → /push
```

---

## 네이밍 예시집

### <repo> (user 트렁크)

```
ISS-103/user/mypage-matching-card
ISS-108/user/freepass-plan
ISS-118/user/manager-recommendation-list
```

### <repo>-admin (admin 트렁크)

```
ISS-104/admin/salary-calculator
ISS-112/admin/offline-meeting-rsvp
```

### 이슈 없는 작업 (TYPE 이 첫 슬롯)

```
CHORE/infra/husky-and-commit-skill
REFACTOR/admin/team-management-naming
docs/user/profile-edu-readme
infra/hotfix/vercel-preview-env
```

---

## 금지 사항

- 🚫 **base 가 `origin/main` 이 아닌 브랜치 생성** — 트렁크/origin/dev/local trunk base 절대 X. dev/staging/main 어디든 깔끔 머지를 위한 핵심 룰
- 🚫 **트렁크명을 첫 슬롯에** — `hotfix/foo/bar` X (git ref 충돌). 첫 슬롯은 `ISS-XXX` 또는 TYPE
- 🚫 **두번째 슬롯에 워크트리·트렁크 이름** — `ISS-XXX/michael/foo` X. 두번째 슬롯은 반드시 `<성격>`
- 🚫 **공백, `~`, `^`, `:`, `?`, `*`, `[`, `\`, `|`** 등 특수문자 (git 자체 제약 + 셸 호환성)
- 🚫 **대문자 사용** (이슈번호 `ISS-` 제외) — 소문자 통일
- 🚫 **언더스코어(`_`)** — 하이픈(`-`)으로 통일
- 🚫 **점(`.`)** — 브랜치명에서 혼동 유발
- 🚫 **50자 초과**
- 🚫 **같은 이슈로 여러 브랜치 생성** — 한 이슈 = 한 브랜치 원칙
- 🚫 **사용자 확인 없이 브랜치 생성 실행**
