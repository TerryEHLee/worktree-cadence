#!/usr/bin/env bash
# wtx-save — 현재 tmux 배치 + pane 별 Claude 대화 ID 스냅샷 (복원은 wtx 한 번)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/_wtx-lib.sh"
WTX_SESSION_ENV="$WTX_SESSION" exec /usr/bin/env python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-snapshot.py" "$@"
