---
name: commit
description: >
  Git 커밋 워크플로우. 이 세션에서 변경한 내용을 트렁크에 commit 한 뒤,
  origin/main 기반의 깨끗한 이슈 브랜치를 만들어 그 commit 을 cherry-pick 한다.
  이슈 브랜치가 origin/main 기준이라 dev/staging/main 어디든 그대로 머지 가능.
  Use when: 커밋, 커밋해, git commit, 커밋 해줘, 변경사항 저장, 작업 저장.
allowed-tools: Read, Bash, AskUserQuestion
---

# Commit Workflow Skill

이 스킬의 책임 범위는 **엄격히 5가지**로 제한된다:

1. 이 세션에서 변경한 파일만 식별
2. 이슈번호 추출
3. **트렁크에 명시 파일만 add + commit** (트렁크가 이 변경의 source of truth — 다른 세션도 즉시 본다)
4. **origin/main 기반의 깨끗한 이슈 브랜치 생성 + cherry-pick** (push 시 dev/staging/main 어디든 깔끔 머지 보장)
5. 트렁크로 복귀 (트렁크에 이미 commit 있으므로 별도 머지백 불필요)

**범위 밖 (다른 스킬에서 처리):**
- push (별도 스킬)
- merge (별도 스킬)
- PR 생성 (별도 스킬)

이 분리는 동시 진행 중인 다른 세션 작업과의 간섭을 막기 위한 의도이며, **절대 합치지 않는다**.

---

## 워크트리 → 트렁크 매핑

**규칙: 트렁크명 = 워크트리 폴더명 − `<repo>-` 접두어** (`<repo>-joshua`→`joshua`, `<repo>-studio`→`studio` …). 워크트리를 늘려도 매핑 자동 성립.

| 세션 | 워크트리 → 트렁크 |
|:---|:---|
| journey (집중) | `joshua` · `caleb` · `manna` · `studio` |
| angels (반응) | `michael` · `gabriel` · `raphael` · `uriel` |
| 구·은퇴예정 | `<repo>-admin`→`admin` |
| 참조 미러 | `<repo>`(메인 체크아웃) → **작업 워크트리 아님.** `mirror/dev` 브랜치로 origin/dev 를 그대로 반영하는 읽기용 참조본 (2026-09-07 전환) |

> `<repo>-fix`(hotfix) 워크트리는 2026-09-01 제거됨. `<repo>`(메인 체크아웃) 는 2026-09-07 참조 미러로 전환 —
> 기존 WIP 는 `archive/<repo>-user-wip-20260907`, 미머지 커밋 2개는 `user` 브랜치에 보존.
> **둘 다 commit 대상 워크트리가 아니다.**

워크트리 : 커밋세션 = **1:1** (한 워크트리에 커밋 세션 2개 금지 — index/HEAD/트렁크 충돌). 모든 작업은 그 트렁크에 누적된다. **이 세션의 변경만 정확히 격리**하는 것이 commit skill 의 핵심 목적.

---

## STEP 1: 워크트리·트렁크 확인

1. `pwd` 로 현재 워크트리 디렉토리 확인
2. 위 매핑표로 트렁크 결정
3. `git branch --show-current` 로 현재 브랜치가 트렁크인지 확인
   - 트렁크 위에 있음: 정상
   - 이미 다른 이슈 브랜치 위: 사용자에게 의도 확인 (`AskUserQuestion`)

## STEP 2: 세션 변동사항 식별 (CRITICAL)

1. `git status --short` 로 working tree 상태 파악
2. **대화 히스토리 스캔** — 이번 세션에서 Edit/Write 한 파일 목록만 체크
3. 다른 세션이 만든 untracked/modified 파일은 **반드시 제외**

`git status` 에 보여도 이번 세션이 안 만진 파일은 **절대 stage 안 함**.
다른 세션 작업이 섞이는 게 가장 큰 위험.

### 1회성 파일 처리

진단 스크립트, 임시 분석 파일 등 1회성 산출물은 **커밋 안 함**. 사용자에게 알리고 즉시 `rm`.

```
⚠️ 1회성 파일 감지: <path>
이 파일은 커밋 대상이 아닙니다 — 삭제 후 진행할까요?
```

기본: 삭제. 사용자 명시 보존 시에만 유지.

## STEP 3: 이슈번호 추출

1. **대화 히스토리에서 `ISS-\d+` 패턴** 우선 검색
2. 없으면 현재 브랜치명에서 정규식 추출
3. 둘 다 실패 → `AskUserQuestion`

```
📋 이슈번호 확인
• ISS-XXX: 직접 입력
• 없음: 이슈번호 없이 커밋 (인프라/리팩 등)
```

## STEP 4: 영역·섹션 분류 + 분리 판단

| 파일 경로 | 영역 | 섹션 |
|:---|:---|:---|
| `src/app/admin/<sec>/`, `src/features/admin/<sec>/` | admin | sec |
| `src/app/(user)/<sec>/`, `src/features/<non-admin>/` | user | sec |
| `src/app/api/<sec>/` | api | sec |
| `src/shared/`, `src/entities/` | shared | 용도 |
| `prisma/` | shared | db |
| `.husky/`, `.claude/`, root 설정 | infra | 용도 |

**분리 커밋 기준:**
- 다른 섹션 → 별도 커밋 (별도 이슈 브랜치)
- 다른 이슈번호 → 별도 커밋
- 같은 섹션 다파일 → 1 커밋

## STEP 5: 브랜치 네이밍 + 사용자 확인

```
이슈 있음:  ISS-XXX/<성격>/<섹션>-<상세>
이슈 없음:  <TYPE>/<성격>/<섹션>-<상세>
```

- `<성격>`: **변경의 성격** — `user` | `admin` | `hotfix` | `api` | `shared` | `infra`
- `<TYPE>` (이슈 없을 때 첫 component): **대문자** — `CHORE` | `FEATURE` | `REFACTOR` | `DOCS` | `TEST` | `INFRA`
  커밋 메시지의 `[TYPE]` 과 같은 표기다. 최근 관례 실측도 전부 대문자 (`CHORE/infra/…` · `FEATURE/studio/…`)
- 🚫 **소문자 TYPE 금지 — push 가 거부된다.** macOS 파일시스템은 대소문자를 구분하지 않아,
  이미 `refs/heads/CHORE/` 디렉토리가 있는 상태에서 `chore/infra/foo` 로 브랜치를 만들면
  `git switch -c` 는 성공하지만 ref 는 조용히 `CHORE/infra/foo` 로 만들어진다. 그 뒤
  `git push origin chore/infra/foo` 가 `fatal: … cannot be resolved to branch` 로 실패한다.
  (2026-09-02 실제 발생 — `chore/infra/daily-report-skill`)
  → 이미 만들었다면 `git switch <대문자 이름>` 으로 HEAD 를 정상 표기로 옮긴 뒤 push 한다
- 🚫 **워크트리·트렁크 이름 금지** (`michael`·`gabriel`·`raphael`·`uriel`·`joshua`·`caleb`·`manna`·`garden`).
  워크트리 이름은 "누가(어느 세션이) 작업했나"일 뿐이고, 브랜치는 "무엇을 건드렸나"를 말해야
  원격 브랜치 목록만 보고 성격이 읽힌다.
- ⚠️ 트렁크명을 **첫** component 로도 쓰지 말 것 — git ref 충돌 (트렁크 브랜치가 같은 이름의
  파일 ref 라 동명 디렉토리 못 생김)

### `<성격>` 판정 순서

1. **이슈 트래커 `category`** — admin PG `issues.category` (hotfix / user / admin / infra). 가장 강한 근거
2. **변경 파일 경로** — `app/(user)/`→`user` · `app/admin/`·`features/admin/`→`admin` ·
   `app/api/`→`api` · `shared/`·`entities/`→`shared` · `.husky/`·`.claude/`·root 설정→`infra`
3. **운영 중 버그면** `hotfix` (경로와 무관하게 우선)

여러 축에 걸치면 **주 무대 + 이슈 category** 로 하나만 고른다.
(예: 회원 화면 11파일 + admin 3파일 동시 수정이지만 category=hotfix → `hotfix`)

예시:
- `ISS-241/api/member-info-update` (이슈 있음, API 라우트 변경)
- `ISS-103/user/schedule-confirm` (이슈 있음, 회원 화면)
- `ISS-426/hotfix/rich-text-body-class-sot` (이슈 있음, 운영 중 표시 버그)
- `CHORE/infra/husky-and-commit-skill` (이슈 없음, CHORE 가 첫 component)
- `REFACTOR/admin/team-management-naming` (이슈 없음, REFACTOR 가 첫 component)

사용자에게 commit plan 보여주고 OK 받기:

```
📋 커밋 계획
워크트리: <repo>-michael → 트렁크: michael
이슈: ISS-XXX
흐름: 트렁크 commit → origin/main 기반 이슈 브랜치 cherry-pick → 트렁크 복귀
브랜치: ISS-XXX/<성격>/<섹션>-<상세>  (base: origin/main)
        └ 성격 판정 근거: <이슈 category / 파일 경로 / 운영버그 여부>
대상 파일:
  M <path>
1회성 (삭제 예정):
  ?? <path>
제외 (다른 세션):
  ?? <path>
커밋 메시지:
  [ISS-XXX][TYPE]{section}: ...
진행할까요?
```

## STEP 6: 트렁크에 add + commit (이 변경의 source of truth)

먼저 현재 트렁크에 직접 commit 한다. 트렁크가 이 변경의 source of truth 가 되고, 같은 워크트리 다른 세션도 즉시 본다.

### 6-1: stage

```bash
git add <file1> <file2> ...   # 절대 -A / . 금지
```

### 6-2: 메시지 작성 — Write tool + `git commit -F` (CRITICAL)

🚫 **`git commit -m "$(cat <<'EOF' ... EOF)"` 패턴 금지** — Bash tool 의 command 직렬화 단계에서 HEREDOC 의 줄바꿈이 손실되어 메시지 전체가 한 줄로 박히는 사고가 실제 발생 (예: ISS-176 c785af31). subject 한 줄에 본문이 통째로 들어가고 body 가 빈 값이 되어, `git log --pretty=%s/%b`, PR title, dev/staging 머지 commit 까지 모두 long-line 으로 오염됨.

✅ **권장 패턴**: Write tool 로 메시지 파일을 만들고 `git commit -F` 로 전달. JSON content 안의 `\n` 은 도구 직렬화 경계에서 안전하게 보존됨.

**1) Write tool 로 메시지 파일 생성** (`.txt` 확장자 — git hook 영향 없음):

```ts
Write({
  file_path: "/tmp/commit-msg-ISS-XXX.txt",
  content: `[ISS-XXX][TYPE]{path/section}: 제목

* 변경 1
* 변경 2
=====
1. file1.ts
2. file2.tsx
`
})
```

⚠️ **제목 다음 빈 줄 1개 필수** (위 템플릿의 `제목` 아래 빈 줄). git 은 **첫 빈 줄까지를 subject** 로 간주하므로, 빈 줄이 없으면 bullet 과 파일 리스트까지 전부 subject 로 빨려 들어가 `%b`(body) 가 빈 값이 된다. 그 결과 `git log --oneline`, PR 제목, dev/staging 머지 commit 이 전부 long-line 으로 오염된다. (2026-08-07 실제 발생 — commit 30e93456)

**2) `-F` 로 commit + 즉시 정리**:

```bash
git commit -F /tmp/commit-msg-ISS-XXX.txt && rm /tmp/commit-msg-ISS-XXX.txt
```

### 6-3: 한 줄 subject 만 있는 단순 commit

본문 bullet 이 없는 스타일/문서 정도 단순 commit 은 `-m` 한 번 OK:

```bash
git commit -m "[CHORE]{infra}: gitignore 정리"
```

### 메시지 규칙
- `[ISS-XXX]` 이슈 있을 때만 (없으면 생략)
- `[TYPE]`: FEATURE | FIX | REFACTOR | STYLE | DOCS | TEST | CHORE
- `{path/section}`: 수정한 섹션 경로 (예: `{api/member-info-update}`)
- 제목: 한 줄, 한국어 OK
- **제목 다음 빈 줄 1개 필수** — 없으면 subject/body 분리 실패 (위 6-2 경고 참조)
- `*` bullet: 변경 내용 / 이유
- `=====` + 변경 파일 번호 리스트
- 🚫 Claude/AI 언급, ⏺ 기호, 한 줄 뭉치기, --amend, --force

### 6-2b: commit 직후 메시지 검증 (필수)

commit 후 아래로 subject/body 분리를 확인한다. 오진 방지를 위해 `git log` 요약 출력이 아니라 `%s`/`%b` 를 직접 본다.

```bash
git log -1 --pretty=%s   # 제목 한 줄만 나와야 정상 (bullet 이 딸려오면 빈 줄 누락)
git log -1 --pretty=%b   # bullet·파일 리스트가 나와야 정상 (비어 있으면 빈 줄 누락)
```

⚠️ `git commit` 실행 직후 콘솔에 찍히는 `[branch abc1234] 제목...` 한 줄 요약은 원래 개행을 공백으로 눌러 보여준다 — **이것만 보고 "한 줄 뭉침" 이라 오진하지 말 것.** 판단은 위 `%s`/`%b` 로만 한다.

빈 줄 누락을 발견해도 `--amend` 는 금지 — 사용자에게 보고하고 명시 동의를 받은 경우에만 수정한다.

### pre-commit 훅 동작 (자동 처리)
- ✅ console.log/debug/info/warn 자동 제거 (`scripts/strip-console-logs.sh`) — `console.error` 는 유지
- ✅ import 정렬, unused imports/vars 자동 제거 (eslint --fix)
- ✅ prettier 포맷팅
- ✅ **scope-aware tsc** — 풀 컨텍스트로 타입 체크하되, **에러 보고는 staged 파일에 한정**. 다른 세션 WIP 에러는 차단 X

### pre-commit 훅 실패 시 (CRITICAL)

세션 격리 + scope-aware tsc 라 fail 확률 매우 낮다.
fail 했다면 **거의 100% 이번 세션 책임**.

1. 에러 위치 + 종류 + 원인 추정 보고
2. **AskUserQuestion** 으로 분기:

```
⚠️ pre-commit 훅 실패
에러 위치: <파일:라인>
에러: <ts-error / lint / etc>
원인 추정: [내 변경 안의 문제 / 명백한 false positive]

A. 로컬에서 수정 후 재커밋 (기본·권장)
B. 명백한 false positive 확신 시 → --no-verify 진행
```

기본은 **A (로컬 fix)**. `--no-verify` 는 사용자 명시 동의 + 명백한 false positive 일 때만.

### 6-4: commit SHA 저장

```bash
TRUNK_COMMIT=$(git rev-parse HEAD)
```

이 SHA 를 STEP 7 의 cherry-pick 대상으로 쓴다. (여러 commit 이면 모두 저장)

## STEP 7: origin/main 기반 이슈 브랜치 생성 + cherry-pick

트렁크 commit 을 source 로 삼아, **`origin/main` 위에 깨끗하게 얹은 이슈 브랜치**를 만든다. 이 브랜치는 dev/staging/main 어디든 그대로 머지 가능한 정제된 패치.

### 7-1: origin/main 최신화

```bash
git fetch origin main
```

read-only download. working tree / 트렁크 무영향.

### 7-2: origin/main 기반 이슈 브랜치 생성

```bash
git switch -c ISS-XXX/<성격>/<섹션>-<상세> origin/main
```

- `-c` + `origin/main` 명시 → 트렁크 위가 아니라 **origin/main 위에 새 브랜치**
- 트렁크 commit 은 그대로 남음. 트렁크 working tree 가 깨끗하니 switch 안전

### 7-3: 트렁크 commit cherry-pick

```bash
git cherry-pick $TRUNK_COMMIT
```

- 트렁크 commit content (메시지·diff) 를 origin/main 위에 새 SHA 로 재생산
- 이슈 브랜치 = `origin/main` + ★ 하나 (또는 여러 ★)

### 7-4: cherry-pick 충돌 시

dev 에는 있고 main 에는 없는 코드 영역을 건드린 commit 이면 충돌 가능. `AskUserQuestion` 분기:

```
⚠️ cherry-pick 충돌 — dev 전용 코드 영역 변경 의심
파일: <path>
충돌 영역: <hunk>

A. LLM 이 양측 의도 분석 후 해소안 제시 → 사용자 검토 → cherry-pick --continue
B. 사용자가 직접 해소 후 --continue
C. cherry-pick --abort → 트렁크 복귀 (이 변경은 dev 전용 — main 직접 머지 불가)
```

기본 권장: **A** (해소안 제시). 단순 충돌은 거의 자동.

## STEP 8: 트렁크 복귀 (머지백 불필요)

```bash
git switch <트렁크>
```

**트렁크에 이미 commit 이 있으므로 별도 머지백 불필요.**
같은 워크트리 다른 세션은 STEP 6 시점부터 이미 이 변경을 본다.
이슈 브랜치는 push 직전까지 손대지 않고 정제된 상태로 보관.

### 트렁크 working tree 확인
```bash
git status
```
- 깨끗: 정상 종료
- 다른 세션의 미커밋 변경 잔존: 정상 (그 세션이 처리)

### 트렁크 commit ↔ 이슈 브랜치 commit 의 SHA 분기
- 트렁크: 원본 SHA
- 이슈 브랜치: cherry-pick 으로 만든 새 SHA (같은 내용)
- push → PR 머지 → origin/dev 에 cherry-pick SHA 가 들어감
- 다음 트렁크 rebase 시 cherry-pick 동등성 감지로 원본 SHA 자동 drop → 트렁크 깨끗

## STEP 9: 해결된 문제 서술

```
💡 이번 커밋으로 해결된 문제
[문제] 제목
  발생: 사용자 관점 — 어떤 화면/동작에서 어떤 현상
  원인: 개발자 관점 — 기술적 근본 원인
  해결: 어떤 코드/데이터 변경으로 닫았는지
```

복수 문제는 문제 단위 그룹핑.
단순 리팩/스타일은 "개선 사항" 으로 별도 표기.

---

## 금지 사항 (CRITICAL)

- 🚫 `main`·`dev`·`staging` 직접 commit (트렁크 joshua·caleb·manna·studio·michael·gabriel·raphael·uriel·garden·admin 은 STEP 6 표준 commit 대상)
- 🚫 `<repo>`(메인 체크아웃) 에서 commit — 참조 미러(`mirror/dev`)다. 커밋하면 ff-only 자동 갱신이 영구 실패한다
- 🚫 **이슈 브랜치를 트렁크 base 로 생성** — 반드시 `origin/main` base (STEP 7-2). 트렁크 base 면 dev 만의 WIP 가 딸려와 main 머지 시 매번 분리 작업 필요해짐
- 🚫 **브랜치명에 워크트리·트렁크 이름** (`michael`/`joshua`/`caleb` 등) — 2번째 component 는 변경 성격 (STEP 5)
- 🚫 `git add -A` / `git add .`
- 🚫 1회성 산출물 commit (삭제하라)
- 🚫 다른 세션 변경 commit
- 🚫 stash 사용
- 🚫 `--amend`, `--force`
- 🚫 `--no-verify` (단 사용자 명시 동의 + 명백한 false positive 시 예외)
- 🚫 push (별도 스킬)
- 🚫 트렁크 ↔ 트렁크 머지 (`hotfix → main`, `dev → user` 등) — 별도 머지 스킬
- 🚫 이슈 브랜치 → 트렁크 머지백 (구 흐름) — 트렁크에 이미 STEP 6 commit 있으므로 불필요
- 🚫 PR 생성 (별도 스킬)
- 🚫 Claude/AI 언급, ⏺ 기호, 한 줄 뭉치기
- 🚫 `git commit -m "$(cat <<'EOF' ... EOF)"` HEREDOC 패턴 — 도구 직렬화 단계에서 줄바꿈 손실 사고 발생 (ISS-176 c785af31). STEP 6-2 의 `Write tool + git commit -F` 패턴 사용
