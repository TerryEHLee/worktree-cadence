---
description: 트렁크를 origin/<BASE> 에 안전하게 sync (멀티세션 lock + autostash rebase)
---

현재 워크트리 트렁크를 `origin/<BASE>` 에 최신화한다. 한 워크트리에서 여러 세션이 도는 환경이라, sync 스크립트가 **lock 을 잡아 다른 세션 tool 을 잠깐 멈춘 뒤**(PreToolUse hook), `rebase --autostash` 로 WIP 를 stash→싱크→pop 하고, lock 을 풀어 다른 세션을 재개시킨다.

다음을 실행하고 **결과만 간결히** 보고:

```bash
bash "$HOME/.config/wtx/home/scripts/sync-trunk.sh"
```

보고 규칙:
- 성공: `before → after` + 트렁크 미푸시 커밋 수 한 줄
- lock 실패("다른 세션이 잠금 중"): 그대로 안내 (잠시 후 재시도)
- rebase 충돌 abort: 어떤 미머지 커밋이 origin/<BASE> 와 충돌하는지 짚고, 해당 이슈를 push/머지해서 트렁크에서 빠지게 하면 해소된다고 안내

절대 하지 말 것: 충돌 시 강제 해소·force. 스크립트가 abort 하면 working tree 는 안전 복원된 상태이므로 그대로 둔다.
