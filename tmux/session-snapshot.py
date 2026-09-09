#!/usr/bin/env python3
"""워크트리 케이던스 tmux 세션 스냅샷 — 재부팅 후 "지금 이 화면 그대로" 복원용 상태 저장.

저장: window 이름·순서 · pane 별 cwd · **그 pane 이 이어가야 할 Claude 세션 ID**

── 왜 세션 ID 까지 저장하는가 ───────────────────────────────────────────
`claude --continue` 는 "그 cwd 의 가장 최근 대화" 하나만 이어받는다. garden·terry 처럼
**같은 cwd 에 pane 이 여러 개**면 전부 같은 대화를 열고 나머지는 조용히 유실된다.
pane 마다 ID 를 못박아 `claude --resume <id>` 로 각자의 대화로 돌려보낸다.

── pane ↔ 대화 매칭 (핵심) ─────────────────────────────────────────────
tmux pane 과 jsonl 을 직접 잇는 정보는 없다(claude 가 파일을 계속 열어두지 않아
lsof 로도 안 잡힌다). 그래서 두 단계로 푼다.

  ① cwd 에 pane 이 하나뿐 → 그 프로젝트의 최신 대화. (= --continue 와 같음, 항상 옳다)
  ② cwd 에 pane 이 여럿   → **화면에 찍힌 응답 시각으로 매칭**한다.
     Claude 는 응답 끝에 `done 8:02 PM` 을 남기고, jsonl 마지막 레코드의 timestamp
     (UTC `...Z`)에 +9h(KST)를 하면 이 시각과 일치한다. pane 별 화면 시각과
     대화별 마지막 시각을 최소거리로 짝지어 정확히 배정한다.

     ※ mtime 정렬을 쓰지 않는 이유: recap·메타 레코드 기록 때문에 **내용상 오래된
       대화의 파일이 더 늦게 수정**될 수 있다. 실제로 2026-09-01 실측에서 mtime 배분이
       terry 의 앱개발(p2)과 겜개발(p3) 대화를 서로 뒤바꿔 배정했다.

  화면 시각을 못 읽은 pane 은 남은 대화 중 mtime 최신순으로 채운다(차선).

  ⓪ (2026-09-09 추가, ①② 보다 우선) pane 의 claude 가 `--resume <id>` 로 떠 있으면 그 id 확정.
     재부팅 복원으로 뜬 세션은 전부 이 꼴이라 추정이 필요 없다. 시각 매칭이 같은 cwd 의
     pane 두 개를 서로 뒤바꾸는 것을 실측(2026-09-09)하고 도입 — 추정은 인자 없는 pane 에만.

저장 v3: 8번째 열에 pane 이름(@pname). tmux 서버가 죽으면 이름도 사라지므로 같이 실어 복원.
"""
import json, os, re, subprocess, sys, time
from datetime import datetime, timezone, timedelta

SESSION  = os.environ.get("WTX_SESSION_ENV", os.environ.get("WTX_FALLBACK","cadence"))
SNAP     = os.environ.get("WTX_SNAPSHOT", os.path.expanduser("~/.config/wtx/session-snapshot.tsv"))
PROJECTS = os.path.expanduser("~/.claude/projects")
KST      = timezone(timedelta(hours=9))
DONE_RE  = re.compile(r"done (\d{1,2}):(\d{2})\s*(AM|PM)")


def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True).stdout.rstrip("\n")


def proj_dir(cwd):
    return os.path.join(PROJECTS, cwd.replace("/", "-"))


def convo_last_ts(path):
    """jsonl 의 마지막 유효 timestamp → KST datetime (없으면 None). 끝에서부터 읽는다."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            chunk = min(size, 262144)          # 끝 256KB 면 마지막 레코드는 충분히 들어온다
            f.seek(size - chunk)
            lines = f.read().decode("utf-8", "replace").splitlines()
        for line in reversed(lines):
            try:
                ts = json.loads(line).get("timestamp")
            except Exception:
                continue
            if ts:
                return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(KST)
    except Exception:
        pass
    return None


def pane_screen_time(target):
    """pane 화면에서 마지막 `done H:MM AM/PM` → (시, 분) 24h. 없으면 None."""
    out = subprocess.run(["tmux", "capture-pane", "-p", "-S", "-300", "-t", target],
                         capture_output=True, text=True).stdout
    m = list(DONE_RE.finditer(out))
    if not m:
        return None
    h, mm, ap = int(m[-1].group(1)), int(m[-1].group(2)), m[-1].group(3)
    if ap == "PM" and h != 12: h += 12
    if ap == "AM" and h == 12: h = 0
    return h * 60 + mm


def main():
    if subprocess.run(["tmux", "has-session", "-t", SESSION],
                      capture_output=True).returncode != 0:
        print(f"⚠️  tmux 세션 '{SESSION}' 이 없습니다 — 스냅샷할 것이 없습니다"); return 1

    # claude 가 붙어 있는 tty 집합 (pane_pid 자식 추적은 놓친다 — tty 가 정확)
    ps = subprocess.run(["ps", "-Ao", "tty,args"], capture_output=True, text=True).stdout
    # args 의 **첫 토큰**이 claude 여야 한다. 줄 끝으로 판정하면 `claude --continue`
    # 로 떠 있는 pane 을 놓친다(실측: terryehlee·studio 가 통째로 빠졌다).
    claude_ttys = set()
    resume_by_tty = {}        # tty → `--resume <id>` 인자 (확정값)
    for l in ps.splitlines():
        parts = l.split()
        if len(parts) >= 2 and parts[0].startswith("ttys") and os.path.basename(parts[1]) == "claude":
            claude_ttys.add(parts[0])
            if "--resume" in parts[2:]:
                i = parts.index("--resume")
                if i + 1 < len(parts) and len(parts[i + 1]) >= 8:
                    resume_by_tty[parts[0]] = parts[i + 1]

    windows = [l.split("\t") for l in tmux("list-windows", "-t", SESSION,
                                           "-F", "#{window_index}\t#{window_name}").splitlines() if l]
    panes = [l.split("\t") for l in tmux("list-panes", "-s", "-t", SESSION,
             "-F", "#{window_index}\t#{window_name}\t#{pane_index}\t#{pane_tty}\t#{pane_current_path}").splitlines() if l]

    # pane 이름(@pname). 탭은 TSV 구분자라 제거.
    pnames = {}
    for l in tmux("list-panes", "-s", "-t", SESSION,
                  "-F", "#{window_index}\t#{pane_index}\t#{@pname}").splitlines():
        parts = l.split("\t")
        if len(parts) >= 3 and parts[2].strip():
            pnames[(parts[0], parts[1])] = parts[2].replace("\t", " ").strip()

    # cwd 별로 pane 을 묶는다
    groups = {}
    for widx, wname, pidx, ptty, cwd in panes:
        groups.setdefault(cwd, []).append((widx, wname, pidx, ptty))

    assigned = {}    # (wname, pidx) -> session id
    running  = {}    # (wname, pidx) -> 0/1
    notes    = []

    for cwd, members in groups.items():
        for widx, wname, pidx, ptty in members:
            running[(wname, pidx)] = 1 if ptty.replace("/dev/", "") in claude_ttys else 0

        d = proj_dir(cwd)
        files = []
        if os.path.isdir(d):
            files = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".jsonl")]
        if not files:
            continue

        live = [m for m in members if running[(m[1], m[2])] == 1]
        if not live:
            continue

        # ⓪ `--resume <id>` 로 떠 있는 pane 은 그 id 그대로 (확정). 나머지만 ①②로 추정.
        pinned = []
        for m in live:
            sid = resume_by_tty.get(m[3].replace("/dev/", ""))
            if sid:
                assigned[(m[1], m[2])] = sid
                pinned.append(m)
        if pinned:
            pinned_ids = {assigned[(m[1], m[2])] for m in pinned}
            files = [f for f in files if os.path.basename(f)[:-6] not in pinned_ids]
            live = [m for m in live if m not in pinned]
        if not live or not files:
            continue

        by_mtime = sorted(files, key=lambda p: os.path.getmtime(p), reverse=True)

        # ① pane 하나 → 최신 대화. 항상 옳다.
        if len(live) == 1:
            widx, wname, pidx, _ = live[0]
            assigned[(wname, pidx)] = os.path.basename(by_mtime[0])[:-6]
            continue

        # ② pane 여럿 → 화면 시각 ↔ 대화 마지막 시각 최소거리 매칭
        cand = [(p, convo_last_ts(p)) for p in files]
        cand = [(p, t) for p, t in cand if t]
        pool = {p: t.hour * 60 + t.minute for p, t in cand}
        left_files = list(by_mtime)
        timed, untimed = [], []
        for widx, wname, pidx, _ in live:
            st = pane_screen_time(f"{SESSION}:{wname}.{pidx}")
            (timed if st is not None else untimed).append(((wname, pidx), st))

        # 화면 시각이 있는 pane 부터, 가장 가까운 대화를 가져간다
        for key, st in sorted(timed, key=lambda x: x[1]):
            best, bestd = None, None
            for p in left_files:
                if p not in pool:
                    continue
                d_ = min(abs(pool[p] - st), 1440 - abs(pool[p] - st))   # 자정 넘김 보정
                if bestd is None or d_ < bestd:
                    best, bestd = p, d_
            if best is None:
                continue
            assigned[key] = os.path.basename(best)[:-6]
            left_files.remove(best)
            if bestd > 15:
                notes.append(f"   ⚠️ {key[0]} p{key[1]}: 화면 시각과 {bestd}분 차이 — 확인 권장")
        # 시각을 못 읽은 pane 은 남은 것 중 최신순
        for key, _ in untimed:
            if left_files:
                assigned[key] = os.path.basename(left_files.pop(0))[:-6]

    tmp = SNAP + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("# wtx session snapshot v3\n")
        f.write(f"# saved\t{time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# session\t{SESSION}\n")
        for widx, wname in windows:
            f.write(f"WINDOW\t{widx}\t{wname}\n")
        for widx, wname, pidx, ptty, cwd in panes:
            sid = assigned.get((wname, pidx), "-")
            run = running.get((wname, pidx), 0)
            pname = pnames.get((widx, pidx), "")
            f.write(f"PANE\t{widx}\t{wname}\t{pidx}\t{cwd}\t{sid}\t{run}\t{pname}\n")
    os.replace(tmp, SNAP)

    n_res = sum(1 for k in assigned)
    print(f"✅ 스냅샷 저장 → {SNAP}")
    print(f"   window {len(windows)}개 · pane {len(panes)}개 · 대화 복원 대상 {n_res}개")
    for n in notes:
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
