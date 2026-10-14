# 온라인 프로토콜 (v3)

WebSocket 텍스트 메시지, 내용은 JSON 객체. 모든 메시지에 `"t"`(종류)가 있다.
서버 구현: `client/server/server_core.gd`, 클라이언트: `client/autoload/net.gd`.

서버가 **권위**를 가진다. 클라이언트는 행동을 요청만 하고, 서버가 확정한 수(`move`)만 판에 적용한다.
판 전체는 게임 시작 때만 보내고, 이후에는 수 하나씩 보낸다. 양쪽이 같은 규칙 코드(`core/`)로 적용하므로
판이 아무리 커져도 메시지 크기가 일정하다.

## 클라이언트 → 서버

| t | 필드 | 설명 |
|---|---|---|
| `create_room` | `v`, `minutes` | 방을 만든다. `minutes`: 각자 시간 5/10/20 (그 외·생략 시 10). → `room_created` |
| `join_room` | `v`, `code` | 방 코드로 참가. 성공하면 두 사람 모두 `game_start` |
| `action` | `action` | 수를 둔다. `action`은 GameState 행동 형식 (`{"type":"place","x","y"}` / `{"type":"line","axis","index"}`) |
| `rematch` | | 게임이 끝난 뒤 다시 하기. 두 사람 모두 보내면 흑백을 바꿔 `game_start` |
| `leave` | | 방에서 나간다 (연결을 끊어도 같음) |

`v`는 프로토콜 버전(현재 3). 다르면 `error: version_mismatch`.

## 서버 → 클라이언트

| t | 필드 | 설명 |
|---|---|---|
| `room_created` | `code`, `minutes` | 4자리 방 코드 (헷갈리는 0/O/1/I/L 제외) |
| `game_start` | `code`, `color`, `state`, `clock` | `color`: 1=흑, 2=백. `state`: `GameState.to_dict()` |
| `move` | `action`, `by`, `turn`, `clock` | 서버가 확정한 수. 두 사람 모두에게. `turn`은 적용 후 총 수 — 클라이언트의 수와 다르면 동기화 오류 |
| `timeout` | `loser`, `clock` | 시간 초과로 대국 종료 (서버가 판정) |

`clock`: `{"minutes", "black_ms", "white_ms", "running"}` — 보낸 시점의 남은 시간(ms)과 지금 시간이 흐르는 색(0이면 멈춤).
클라이언트는 받은 시점부터 `running` 쪽 시간을 줄여 보여 주기만 하고, 시간 초과 판정은 서버만 한다.
| `rematch_requested` | | 상대가 다시 하기를 눌렀다 |
| `opponent_left` | | 상대가 나갔다. 방은 닫힌다 |
| `error` | `reason` | `bad_message`, `version_mismatch`, `no_such_room`, `room_full`, `already_in_room`, `not_in_game`, `not_your_turn`, `game_over`, `cannot_rematch`, `bad_action`, `out_of_board`, `occupied`, `bad_index` |
