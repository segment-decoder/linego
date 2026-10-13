# 온라인 프로토콜 (v1)

WebSocket 텍스트 메시지, 내용은 JSON 객체. 모든 메시지에 `"t"`(종류)가 있다.
서버 구현: `client/server/server_core.gd`, 클라이언트: `client/autoload/net.gd`.

서버가 **권위**를 가진다. 클라이언트는 행동을 요청만 하고, 판 상태는 서버가 보내 준 것만 믿는다.

## 클라이언트 → 서버

| t | 필드 | 설명 |
|---|---|---|
| `create_room` | `v` | 방을 만든다. → `room_created` |
| `join_room` | `v`, `code` | 방 코드로 참가. 성공하면 두 사람 모두 `game_start` |
| `action` | `action` | 수를 둔다. `action`은 GameState 행동 형식 (`{"type":"place","x","y"}` / `{"type":"line","axis","index"}`) |
| `rematch` | | 게임이 끝난 뒤 다시 하기. 두 사람 모두 보내면 흑백을 바꿔 `game_start` |
| `leave` | | 방에서 나간다 (연결을 끊어도 같음) |

`v`는 프로토콜 버전(현재 1). 다르면 `error: version_mismatch`.

## 서버 → 클라이언트

| t | 필드 | 설명 |
|---|---|---|
| `room_created` | `code` | 4자리 방 코드 (헷갈리는 0/O/1/I/L 제외) |
| `game_start` | `code`, `color`, `state` | `color`: 1=흑, 2=백. `state`: `GameState.to_dict()` |
| `state` | `state`, `last`, `by` | 수가 적용된 뒤 두 사람 모두에게. 판 전체 상태를 매번 보낸다 |
| `rematch_requested` | | 상대가 다시 하기를 눌렀다 |
| `opponent_left` | | 상대가 나갔다. 방은 닫힌다 |
| `error` | `reason` | `bad_message`, `version_mismatch`, `no_such_room`, `room_full`, `already_in_room`, `not_in_game`, `not_your_turn`, `game_over`, `cannot_rematch`, `bad_action`, `out_of_board`, `occupied`, `bad_index` |
