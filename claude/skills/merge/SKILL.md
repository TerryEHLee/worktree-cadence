---
name: merge
description: >
  머지 실행 + 리포트 생성. Use when the user asks to merge,
  머지, 머지해, dev에 합쳐, dev 머지, 브랜치 합쳐,
  merge to dev.
allowed-tools: Bash, AskUserQuestion, ToolSearch, Read, Grep, Glob, Agent
---

# Merge Skill

현재 브랜치의 커밋들을 분석하여 **비개발자도 이해 가능한 머지 리포트**를 생성하고,
사용자 확인 후 **dev → staging → main** 순차 머지 + 푸시를 자동 실행합니다.

---

## 워크트리별 베이스 브랜치 컨텍스트 (CRITICAL)

이 skill 은 **이슈 브랜치** (`ISS-XXX/<type>/<desc>`) 에서 호출되어야 한다.
트렁크 브랜치(joshua·caleb·manna·studio·michael·gabriel·raphael·uriel·garden·admin) 에서 직접 호출 금지.

| 워크트리 | 베이스 브랜치 | origin push |
|:---|:---|:---|
| `~/Desktop/codes/<repo>` | `mirror/dev` | ❌ **참조 미러 — 머지 대상 아님** |
| `~/Desktop/codes/<repo>-admin` | `admin` | ❌ (로컬 누적기) |

### push 정책

- **이슈 브랜치만 origin push** — `git push origin ISS-XXX/...`
- **베이스 브랜치 push 절대 금지** — origin/dev 와 항상 diverge
- 베이스 브랜치는 commit skill 의 STEP 8.5 머지 백으로만 변경됨

### PR 정책

- **모든 PR 의 head = 이슈 브랜치** (베이스 브랜치 X)
- 핫픽스 워크트리에서 시작된 변경은 dev/staging/main 셋 다 PR 필수 (3쪽 정합)
- 메인 워크트리는 dev → staging → main 순차

---

## STEP 1: 머지 범위 파악

```bash
git branch --show-current
git log dev..HEAD --oneline
```

커밋이 없으면 사용자에게 알리고 중단.

## STEP 2: 정보 수집

```bash
# 커밋 시간 정보
git log --format="%H %aI" dev..HEAD

# 파일 변경 통계
git diff --stat dev..HEAD

# 총 변경 줄 수
git diff --shortstat dev..HEAD

# 각 커밋 메시지 전체
git log --format="%s%n%b" dev..HEAD
```

## STEP 3: 머지 메시지 생성

### 머지 메시지 형식

```
🚀 MERGE — YYYY년 MM월 DD일 HH:mm

📦 업데이트 내용
─────────────────────────────────
[관리자] 섹션명
  • 변경 내용을 비개발자가 이해할 수 있는 한국어로 설명
  • 기능 관점에서 무엇이 바뀌었는지 서술

[사용자] 섹션명
  • 변경 내용 설명

[공통]
  • 변경 내용 설명
─────────────────────────────────

📝 커밋 내역
  1. [TYPE]{page}: 커밋 메시지 제목
  2. [TYPE]{page}: 커밋 메시지 제목
  ...

📊 통계
  수정한 파일: N개
  코드 변경: 추가 N줄 / 삭제 N줄
```

### 작성 규칙

**📦 업데이트 내용 섹션:**
- 커밋 메시지를 그대로 복사하지 않음
- **비개발자(기획자, 디자이너, 대표)가 읽어도 이해**할 수 있게 작성
- 기술 용어 대신 기능/화면 관점으로 서술
- 페이지(섹션) 단위로 그룹핑
- `[관리자]`, `[사용자]`, `[공통]`으로 영역 구분

**변환 예시:**
```
커밋 메시지:
  [FIX]{admin/consultations}: validateRequest 인증 로직 수정

업데이트 내용:
  [관리자] <섹션명>
    • <수정 요약 예시>
```

```
커밋 메시지:
  [FEATURE]{user/mypage}: 프로필 사진 업로드 S3 연동

업데이트 내용:
  [사용자] 마이페이지
    • 프로필 사진 업로드 기능 추가
```

```
커밋 메시지:
  [REFACTOR]{user/auth}: OAuth 토큰 갱신 로직 리팩토링

업데이트 내용:
  [사용자] 로그인
    • 소셜 로그인 안정성 개선
```

**📝 커밋 내역 섹션:**
- 실제 커밋 메시지의 첫 줄(제목)만 번호 매겨 나열
- 개발자용 상세 기록 용도

**📊 통계 섹션:**
- 수정한 파일 수, 추가/삭제 줄 수만 간략히

### 날짜/시간
- 머지 실행 시점의 한국 시간 (KST, +09:00)
- `date +"%Y년 %m월 %d일 %H:%M"` 으로 현재 시간 사용

## STEP 4: 사용자 확인

생성된 머지 메시지를 사용자에게 보여주고 확인:

```
📋 머지 확인
• 브랜치: [현재 브랜치] → dev → staging → main
• 커밋 수: N개

[생성된 머지 메시지 전체]

이대로 머지를 진행할까요?
```

**사용자 확인 후에만 STEP 5로 진행한다.**

## STEP 5: 푸시 + 원격 머지 체인 실행 (dev / staging 까지만 자동)

사용자 확인 후 아래 순서를 **자동으로 연속 실행**한다.
**모든 머지는 원격(GitHub)에서 수행** — 로컬 checkout/merge 없이 `gh` CLI로 PR 생성 → 머지한다.
이렇게 하면 로컬/원격 불일치로 인한 충돌을 방지할 수 있다.

### ⛔ main 자동 머지 금지 (CRITICAL)

자동 머지 흐름은 **dev → staging 까지만**.
main 머지는 **staging QA 통과 후** 사용자가 *명시적으로 트리거* 할 때만 진행한다.

| 단계 | 자동? | 트리거 |
|:---|:---:|:---|
| 이슈브랜치 → dev | ✅ | merge skill 호출 시 자동 |
| dev → staging | ✅ | merge skill 호출 시 자동 |
| staging → main | ❌ | 사용자가 "main 머지" / "main 반영" / "프로덕션 배포" 등 명시적 요청 시에만 |

### 5-1: 현재 브랜치 푸시

```bash
git push origin <현재브랜치>
```

### 5-2: 현재 브랜치 → dev (원격 머지)

```bash
# PR 생성 + 즉시 머지 (merge commit 방식)
gh pr create --base dev --head <현재브랜치> --title "머지 메시지 제목" --body "머지 메시지 본문"
gh pr merge <PR번호> --merge --delete-branch=false
```

### 5-3: dev → staging (원격 머지)

```bash
gh pr create --base staging --head dev --title "머지 메시지 제목" --body "머지 메시지 본문"
gh pr merge <PR번호> --merge --delete-branch=false
```

### 5-4: 로컬 동기화 + main 안내

머지 체인 (dev/staging) 완료 후 로컬 브랜치들을 원격과 동기화:

```bash
git fetch origin
# 현재 브랜치에 머무름 (checkout 하지 않음)
```

사용자에게 main 머지 안내:

```
✅ dev / staging 머지 완료
─────────────────────────────────
[현재 브랜치] → dev      ✅ pushed
            dev → staging ✅ pushed
            staging → main ⏸  대기 (staging QA 통과 후 별도 요청 시 진행)
─────────────────────────────────

📌 main 머지 진행 시점
  - staging Vercel preview 빌드 통과 확인
  - 운영 환경 영향 검증 (QA / 회귀 테스트)
  - 통과 후 "main 머지", "프로덕션 반영" 등 명시 요청
```

### 5-5: main 머지 (사용자 명시 요청 시만 별도 실행)

사용자가 staging QA 통과 후 main 머지를 명시 요청하면:

```bash
# 이슈 브랜치 → main 직접 PR (staging 과 같은 head 사용)
gh pr create --base main --head <이슈브랜치> --title "...(main)" --body "..."
gh pr merge <PR번호> --merge --delete-branch=false
```

### PR 제목/본문 규칙

- **PR 제목**: 머지 메시지의 첫 줄 (`🚀 MERGE — YYYY년 MM월 DD일 HH:mm`)
- **PR 본문**: 머지 메시지 전체 (📦 업데이트 내용 + 📝 커밋 내역 + 📊 통계)
- dev/staging PR 동일 제목/본문 사용
- main PR 은 staging QA 결과/통과 시점도 본문에 추가
- `--delete-branch=false` 필수 — dev, staging 브랜치가 삭제되면 안 됨

### 충돌 처리

PR 머지 시 충돌이 발생하면 `gh pr merge`가 실패한다:
1. 사용자에게 충돌 발생 단계 알림
2. GitHub에서 충돌 확인할 수 있는 PR URL 제공
3. 이후 단계 중단

```
⚠️ 원격 머지 충돌 발생
• 단계: dev → staging
• PR: https://github.com/.../pull/123
• 조치: GitHub에서 충돌을 확인하고 수동 해결 후 다시 시도해주세요.
```

## STEP 6: 머지 결과 보고 + 테스트 체크리스트

### 6-1: 머지 결과

```
✅ 머지 완료
─────────────────────────────────
[현재 브랜치] → dev      ✅ pushed
            dev → staging ✅ pushed
            staging → main ⏸  대기 (staging QA 통과 후 별도 요청 시 진행)
─────────────────────────────────
현재 브랜치: [원래 브랜치]로 복귀 완료

📌 다음 단계
  1. Vercel staging preview 빌드 결과 확인
  2. staging 환경에서 변경 사항 QA / 회귀 테스트
  3. 통과 후 사용자가 "main 머지" 명시 요청 → STEP 5-5 실행
```

main 머지가 별도로 진행되면 그 후 결과:

```
✅ main 머지 완료
─────────────────────────────────
staging → main ✅ pushed (PR #XXX, SHA xxxxxxxx)
─────────────────────────────────
프로덕션 deployment 트리거됨
```

### 6-2: 테스트 체크리스트 생성

머지 메시지의 **📦 업데이트 내용**을 기반으로 테스트 체크리스트를 자동 생성한다.
비개발자가 직접 확인할 수 있는 **사용자 관점의 체크리스트**로 작성한다.

**체크리스트 형식:**

```
🧪 테스트 체크리스트
─────────────────────────────────
[사용자 페이지]
  □ 테스트 항목 — 확인 방법 (어디서, 무엇을, 어떻게)
  □ 테스트 항목 — 확인 방법

[관리자 페이지]
  □ 테스트 항목 — 확인 방법
  □ 테스트 항목 — 확인 방법

[공통]
  □ 테스트 항목 — 확인 방법
─────────────────────────────────
```

**체크리스트 작성 규칙:**
- 업데이트 내용의 각 항목마다 1개 이상의 테스트 항목 생성
- **구체적인 확인 방법** 포함 (어떤 페이지에서, 어떤 동작을, 어떤 결과가 나오는지)
- FIX 항목: 수정 전 재현 시나리오 + 수정 후 정상 동작 확인
- FEATURE 항목: 새 기능의 동작 확인 + 기존 기능에 영향 없는지 확인
- 모바일/PC 구분이 필요한 항목은 명시

**변환 예시:**
```
업데이트 내용:
  [사용자] 프로필 정보
    • 자동저장 시 기존 입력값이 초기화되던 문제 수정
    • 필수 항목 미입력 시에도 입력한 내용은 저장되도록 개선

테스트 체크리스트:
  [사용자 페이지]
    □ 프로필 정보 > 기본정보 입력 후 다른 탭 이동 → 다시 돌아왔을 때 입력값 유지 확인
    □ 프로필 정보 > 필수 항목 일부 비우고 다음 버튼 → 에러 표시 + "저장되었습니다" 토스트 확인
    □ 프로필 정보 > 모든 필드 입력 후 새로고침 → 입력값 모두 유지 확인
```

```
업데이트 내용:
  [사용자] 본인인증
    • iOS 앱에서 본인인증 팝업이 차단되던 문제 수정

테스트 체크리스트:
  [사용자 페이지]
    □ iOS 앱 > 본인인증 버튼 탭 → 팝업 정상 열림 확인 (차단 메시지 없음)
    □ iOS 앱 > 본인인증 완료 → 인증 결과 정상 반영 확인
    □ PC 브라우저 > 본인인증 버튼 클릭 → 기존과 동일하게 팝업 열림 확인 (회귀 테스트)
```

## STEP 7: 배포 후 라이브 테스트 (선택)

사용자가 배포 완료 후 테스트를 요청하면 실행한다.
**Chrome DevTools MCP 도구**를 사용하여 <프로덕션 도메인>에서 변경사항을 검증한다.

### 7-1: 테스트 계획 수립

커밋 내역을 분석하여 테스트 항목을 분류:

| 분류 | 설명 | 테스트 방법 |
|:---|:---|:---|
| **브라우저 테스트 가능** | UI 변경, 메타태그, 페이지 렌더링 | Chrome DevTools로 직접 검증 |
| **API 테스트 가능** | API 응답 변경, 데이터 처리 | evaluate_script로 fetch 호출 |
| **수동 확인 필요** | 특정 데이터 조건, 크론잡 등 | 사용자에게 수동 확인 안내 |

테스트 계획을 사용자에게 보여주고 확인:

```
🧪 자동 테스트 계획
─────────────────────────────────
[자동 테스트] (Chrome DevTools)
  1. 테스트 항목 — 검증 방법
  2. 테스트 항목 — 검증 방법

[수동 확인 필요]
  1. 항목 — 필요한 조건/이유
─────────────────────────────────
테스트를 진행할까요?
```

### 7-2: Chrome DevTools MCP 테스트 실행

ToolSearch로 필요한 Chrome DevTools 도구를 로드한 뒤 테스트 진행.

**사용 도구:**
- `navigate_page` — 페이지 이동
- `take_screenshot` — 스크린샷 캡처 (증거용)
- `evaluate_script` — DOM 검사, meta 태그 확인, API 호출
- `click` — 버튼/링크 클릭
- `wait_for` — 요소 로딩 대기

**테스트 패턴 예시:**

```
# meta 태그 검증
evaluate_script: document.querySelector('meta[name="description"]').content

# 특정 요소 존재 확인
evaluate_script: !!document.querySelector('.target-class')

# API 응답 검증
evaluate_script: fetch('/api/endpoint').then(r => r.json())

# 페이지 텍스트 확인
evaluate_script: document.querySelector('.selector')?.textContent
```

**테스트 흐름:**
1. <프로덕션 도메인>으로 이동 (로그인 세션은 Chrome 프로필에 유지됨)
2. 각 테스트 항목별로 페이지 이동 → 검증 → 스크린샷
3. 결과를 실시간으로 기록

### 7-3: 테스트 결과 보고

```
🧪 테스트 결과
─────────────────────────────────
✅ 항목명 — 검증 결과 설명
✅ 항목명 — 검증 결과 설명
❌ 항목명 — 실패 원인 + 스크린샷
⏭️ 항목명 — 수동 확인 필요 (사유)
─────────────────────────────────
통과: N/N개
```

- ❌ 실패 항목이 있으면 원인 분석 + 수정 방안 제시
- 모두 통과하면 머지 완료 확정

---

## 금지 사항

- Claude/AI 관련 문구 포함 금지
- ⏺ 기호 포함 금지
- `--force` 옵션 사용 금지
- 사용자 확인 없이 머지/푸시 실행 금지
- **사용자 명시 요청 없이 main 머지 절대 금지** — staging QA 통과 + 사용자가 "main 머지" / "프로덕션 반영" 등 트리거할 때만 STEP 5-5 진행
- 트렁크 브랜치 origin push 금지 (이슈 브랜치만). `<repo>`(메인 체크아웃) 미러는 머지·push 어느 쪽도 대상 아님
- 베이스 브랜치를 PR head 로 사용 금지 (head 는 항상 이슈 브랜치)
