---
name: daily-report
description: >
  오늘 한일 일일 정리. 모든 워크트리의 커밋·미커밋 변경을 긁어
  완료/진행중으로 나누고, 완료 항목은 이슈 트래커 링크를 붙인다.
  journey(joshua·caleb·manna) 는 기능 변화를 세부 서술, 나머지는 1줄 요약.
  Use when: 오늘 한일, 오늘 한 일 정리, 일일 정리, 한일 정리해줘,
  데일리 리포트, 오늘 뭐했지, 오늘 작업 정리, daily report.
allowed-tools: Bash, Read
---

# Daily Report Skill — 오늘 한일 정리

## 책임 범위

**하는 일**: 시간 창 안의 git 변경내역 수집 → 워크트리 귀속 → 완료/진행중 분류 → 이슈 트래커 링크 연결 → 마크다운 리포트 출력 → 실행 시각 기록.

**하지 않는 일** (엄격):
- 위험도·리스크·주의사항·지뢰 평가 **전면 금지**. "위험했다", "조심해야", "회귀 우려" 류 한 줄도 쓰지 않는다.
- 다음 할 일·제안·추천 금지. 사용자가 결정한다.
- commit / push / merge 실행 금지. 이 스킬은 **read-only** 다.
- 파일 저장·Notion 전송 금지. 출력은 터미널 + <PM> Slack DM **초안**까지.
- **Slack 발송 금지** — `slack_send_message_draft` 로 초안만 만든다. 보내는 것은 폐하가 직접.

---

## STEP 0 — 시간 창 결정

상태 파일: `~/.config/wtx/daily-report-last-run` (저장소 밖 사용자 레벨 — 리포트가 워크트리를 가로지르므로)

```bash
STATE=~/.config/wtx/daily-report-last-run
if [ -f "$STATE" ]; then SINCE=$(cat "$STATE"); else SINCE=$(date -v-1d "+%Y-%m-%d 17:00:00"); fi
NOW=$(date "+%Y-%m-%d %H:%M:%S")
```

- 인자 우선: `24h`/`3d` → `date -v-24H`, `2026-09-01 17:00` → 그대로.
- **상태 파일은 리포트 출력 + Slack 초안 작성까지 끝난 뒤에만 갱신** (STEP 8).

---

## STEP 1 — 커밋 수집과 워크트리 귀속 (⚠️ 여기가 이 스킬의 급소)

### 하면 안 되는 것

`git log <트렁크> --since=...` 로 귀속하지 말 것. `push` 스킬이 매 push 마다 `rebase --autostash origin/dev` 를 돌리므로 **머지된 커밋 1개가 동일 SHA 로 전 트렁크에 복제된다.** 한 커밋이 트렁크 5곳에 똑같이 잡히는 식이다. committer date 비교도 소용없다 — 복제본은 SHA 가 같아 date 도 같다.

### 해야 하는 것 — 브랜치 reflog 의 `commit:` 항목

reflog 는 브랜치별로 독립이고, 트렁크 브랜치는 자기 워크트리에서만 전진한다. 따라서 `commit:` 항목 = **그 워크트리에서 실제로 만든 커밋**이다. `rebase (finish)` 는 origin/dev sync 잡음이므로 버린다.

```bash
for T in $(git worktree list | sed -E 's/.*\[(.*)\]$/\1/'); do
  git reflog show "$T" --date=iso 2>/dev/null | grep ': commit' \
    | awk -F'@\\{' -v t="$T" '{split($2,a,"\\}"); if (a[1] >= "'"$SINCE"'") print t" | "a[1]" | "$0}'
done
```

### cherry-pick 은 SHA 를 바꾼다 → 매칭 키는 subject

트렁크 커밋이 `origin/main` 기반 이슈 브랜치로 cherry-pick 되면 SHA 가 새로 생기고, dev 머지 후 트렁크가 rebase 되면 **원본 SHA 는 히스토리에서 사라진다** (reflog 에만 남음). 그래서 히스토리 커밋 ↔ 작성 워크트리 매칭은 **커밋 subject 문자열**로 한다.

```bash
CG=$(git rev-parse --git-common-dir)
grep -rn "commit: .*<subject 일부>" "$CG/logs/refs/heads" | sed -E "s|$CG/logs/refs/heads/||"
```

reflog 에 전혀 안 잡히는 커밋은 다른 사람 것이거나 다른 머신에서 온 것이다 → 다음 항목.

### ⚠️ author 필터 필수 — 남의 커밋이 섞인다

`origin/dev` 로 동료(예: `<리뷰어>`) 커밋이 트렁크에 유입된다. 리포트는 **폐하 본인 작업**이므로 반드시 걸러낸다.

```bash
git log ... --author="<본인 git 이메일>"
# 또는 수집 후 검증: git log -1 --pretty="%an" <SHA>
```

### 이슈 브랜치 활동 (push 여부 신호)

```bash
for B in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep '^ISS-'); do
  git reflog show "$B" --date=iso 2>/dev/null | awk -F'@\\{' -v b="$B" \
    '{split($2,a,"\\}"); if (a[1] >= "'"$SINCE"'") print b" | "a[1]" | "substr($0, index($0,"}: ")+3)}'
done
```

`cherry-pick:` / `rebase (finish):` 가 윈도우 안에 있으면 그날 push 경로를 탄 것이다. 커밋 자체가 윈도우 직전이어도 **완료 시점이 윈도우 안이면 그날 완료로 잡는다** (시각은 정직하게 표기).

---

## STEP 2 — 미커밋 변경 수집 (워크트리마다 독립)

```bash
git worktree list | while read -r DIR _ BR; do
  git -C "$DIR" diff --stat HEAD | tail -1
  git -C "$DIR" status --porcelain
done
```

- untracked(`??`)도 본다 — 신규 기능이 통째로 untracked 인 경우가 많다 (`features/video-upload/` 등). 디렉터리는 `find` 로 안을 펼쳐 무슨 모듈인지 확인한다.
- 루트 1회성 진단 스크립트(`check-*.ts`, `run-*.ts`, `analyze-*.ts`)는 리포트에서 제외.

---

## STEP 3 — 완료 / 진행중 판정 (주관 배제, 그래프로)

```bash
git fetch origin dev --quiet
git merge-base --is-ancestor <SHA> origin/dev && echo 완료 || echo 진행중
```

| 상태 | 조건 |
|:---|:---|
| **완료** | 커밋이 `origin/dev` 에 도달 (push 경로 완주) |
| **진행중** | 트렁크에만 있고 `origin/dev` 미도달 · 또는 미커밋 working tree 변경 |

"완료된 것 같다" 는 인상 판단 금지. 위 두 줄이 유일한 근거다.

---

## STEP 4 — 이슈 트래커 링크 연결 (프로젝트별 어댑터)

> ⚙️ 이 STEP 은 프로젝트의 이슈 트래커에 맞게 수정해서 쓴다. 아래는 Postgres 기반 자체 트래커 예시.

```bash
DBURL=$(grep -m1 '^<DB_URL 환경변수(_UNPOOLED)>=' <앱>/.env | cut -d= -f2- | tr -d '"')
psql "$DBURL" -At -F' | ' -c "select issue_no, title, status, stage from issues where issue_no in ('ISS-101','ISS-102');"
```

- **pooled `<DB_URL 환경변수>` 금지** — URL 의 `pgbouncer` 파라미터를 psql 이 거부한다. 반드시 `_UNPOOLED`.
- 테이블명은 `issues` (Prisma 모델명 `Issue` 아님).
- 링크: `https://<이슈트래커>/issues/ISS-101`
- 제목은 DB 값을 쓴다. 커밋 subject 로 추측하지 않는다. ISS 번호 없는 커밋은 링크 없이.

---

## STEP 5 — 서술 깊이 (워크트리별 차등)

| 그룹 | 워크트리 | 서술 |
|:---|:---|:---|
| **journey 주력 3종** | joshua · caleb · manna | **세부 서술.** 큰 기능 변화는 2~5줄로 "무엇이 어떻게 달라졌는지". `git show --stat` 으로 범위를 잡고 **신규 모듈의 상단 주석을 실제로 열어본다** — 이 레포는 설계 의도를 파일 헤더에 길게 적어두므로 거기서 기능 서술이 바로 나온다. |
| **studio** | studio | 1~2줄 (별도 제품) |
| **angels 4종** | michael · gabriel · raphael · uriel | 1줄씩, 한 일 **전부** 나열 |
| **garden / 구 워크트리** | garden · user · admin | 1줄씩 (잔류 미커밋만 있으면 그것만) |

커밋 메시지를 그대로 옮기지 말고 **기능 관점**으로 다시 쓴다.

---

## STEP 6 — 출력 포맷

```markdown
# 오늘 한일 — {YYYY-MM-DD}
> 구간: {SINCE} ~ {NOW}

## ✅ 완료
### angels / journey ...
- **{워크트리}** — {한 일} · [{ISS-XXX}](링크) {DB 이슈 제목}

## 🔧 진행중
### journey — 주력
**{워크트리}** — [{ISS-XXX}](링크) {이슈 제목}
- {기능 변화 2~5줄}
- {변경 규모: N files, +X/−Y, 미커밋}
```

- 해당 없는 섹션은 **통째로 생략**. 빈 항목 나열 금지.

---

## STEP 7 — <PM> Slack DM 초안 작성

터미널 리포트를 낸 뒤, 같은 내용을 **<PM> PM DM 초안**으로 만든다.

```
mcp__claude_ai_Slack__slack_send_message_draft
  channel_id: <PM Slack user ID>   # slack_search_users 로 확인
  message: <아래 규칙으로 변환한 본문>
```

- **초안만.** `slack_send_message` 절대 사용 금지. 발송은 폐하가 Slack 에서 직접 한다.
- 채널당 **초안 1개 제한**이다. `draft_already_exists` 가 뜨면 새로 만들지 말고, 기존 초안을 지우거나 편집해야 한다고 알린 뒤 멈춘다.

### 사외 독자용 변환 규칙 (터미널 리포트 ≠ Slack 본문)

<PM> 은 QA 담당이지 이 레포의 git 구조를 모른다. 그대로 붙여넣지 말고 다음을 적용한다.

| 빼는 것 | 바꾸는 것 |
|:---|:---|
| 워크트리명 (joshua·caleb·manna·michael…) | **이슈 주제**로 묶는다. 어느 워크트리에서 했는지는 사외 정보가 아니다 |
| SHA·reflog·cherry-pick·트렁크·`origin/dev` | "dev 머지 완료" / "아직 미커밋" 정도로만 |
| 동료 커밋 제외 각주 | 통째로 생략 |
| 파일 경로·모듈명 | 기능 이름으로 풀어 쓴다 (`handoverFulfillment.ts` → "인계 이행 점검") |

- **변경 규모(N files, +X/−Y)는 남긴다** — 진척 감각을 주는 유일한 수치다.
- 위험도·리스크 평가 금지 규칙은 여기서도 그대로다.
- Slack 서식: 마크다운 헤더(`#`)는 렌더링이 나쁘다. `*굵게*` 줄 + `━━━` 구분선 + `•` 불릿을 쓴다. 링크는 `[ISS-430](https://<이슈트래커>/issues/ISS-101)` 형식이 그대로 먹는다.
- 첫 줄 인사 + 끝 줄 마무리를 붙인다. QA 요청은 **명시 지시가 있을 때만** 넣는다.

---

## STEP 8 — 실행 시각 기록

리포트 출력 **후에** 갱신하고, 마지막 줄에 알린다.

```bash
date "+%Y-%m-%d %H:%M:%S" > ~/.config/wtx/daily-report-last-run
```

`_다음 정리는 {NOW} 이후 변경분부터입니다._`
