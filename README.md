# 줄긋기 오목 (Linego)

게임 도중 줄을 그어 판을 확장하는 오목. Godot 4.7, 모바일 세로 화면(1080×1920).

규칙은 [docs/RULES.md](docs/RULES.md), 온라인 메시지 형식은 [docs/PROTOCOL.md](docs/PROTOCOL.md) 참고.

## 구조

```
client/                     Godot 프로젝트 (에디터에서 client/project.godot 을 연다)
  core/                     규칙 로직. 노드에 의존하지 않는 순수 GDScript
    board_state.gd            판 상태, 줄 긋기(행/열 삽입), 정확히-5목 탐색
    game_state.gd             턴 진행, 행동 검증/적용, 승리 판정
  scenes/
    home/                   홈 화면 (2인 대전, 온라인 대전, 편리한 이동 설정, 규칙)
    lobby/                  온라인 로비 (서버 주소, 방 만들기 / 방 코드로 참가)
    game/                   게임 화면 (한 기기 대전 / 온라인 대전 공용)
      game.gd                 입력(탭/핀치/드래그) 해석, UI 갱신
      board_view.gd           GameState를 그리기만 함
      board_camera.gd         확대/이동 연산
  autoload/settings.gd      전역 설정 (user://settings.cfg 저장)
  autoload/net.gd           서버 연결 (WebSocket + JSON), 현재 온라인 대국 정보
  server/                   방 코드 대전 서버 (Godot 헤드리스로 실행, core/ 규칙을 그대로 사용)
    server_core.gd            방/턴/검증 로직 (소켓 없음, 테스트 가능)
    server.gd                 WebSocket 전송
    server_main.tscn          서버 실행 진입점
  tests/                    헤드리스 테스트
docs/RULES.md               규칙 문서 (구현의 기준)
docs/PROTOCOL.md            온라인 메시지 형식
```

### 설계 원칙

- **규칙은 `core/` 한 곳에만.** 화면은 `GameState` 를 읽어 그리기만 하고, 모든 행동은
  `GameState.apply(action)` 을 통해서만 일어난다.
- **행동은 직렬화 가능한 Dictionary.**
  `{"type": "place", "x": 2, "y": 3}`, `{"type": "line", "axis": "col", "index": 0}`.
  온라인 대전을 붙일 때 이 형식 그대로 서버와 주고받는다.
- `core/` 는 노드를 쓰지 않으므로 서버(`server/`)도 같은 코드로 수를 검증한다. 규칙을 고치면 클라이언트와 서버에 함께 반영된다.
- 온라인에서는 서버가 권위를 가진다. 클라이언트는 행동을 보내기만 하고, 서버가 돌려준 상태로 화면을 갱신한다.

## 조작

- **돌 놓기 / 세로줄 / 가로줄** 중 모드를 고른 뒤 판을 탭하면 미리보기가 나온다.
  같은 곳을 한 번 더 탭하거나 **확정**을 누르면 실행된다.
- 두 손가락으로 확대·축소·이동, 한 손가락 드래그로 이동. 데스크톱에서는 마우스 휠로 확대.
- **전체보기**: 판 전체가 보이게 맞춘다.

## 온라인 대전 테스트 (같은 PC / 같은 와이파이)

1. **서버 실행** (터미널, `godot` 자리에 Godot 실행 파일 경로. Windows는 `Godot_v4.7.x-stable_win64_console.exe`)
   ```sh
   godot --headless --path client res://server/server_main.tscn
   # 포트 변경: ... res://server/server_main.tscn -- --port=9000
   ```
   서버가 `같은 와이파이에서 접속: 192.168.x.x:8080` 처럼 접속 주소를 출력한다.
   에디터에서 `server/server_main.tscn` 을 열고 **F6**(현재 씬 실행)으로 띄워도 된다.
2. **클라이언트 두 개 실행**: 에디터 메뉴 **Debug → Customize Run Instances...** 에서
   **Enable Multiple Instances** 를 켜고 개수를 2로 한 뒤 **F5**.
3. 한쪽은 **온라인 대전 → 방 만들기**, 다른 쪽은 표시된 **방 코드**로 참가.
   서버 주소는 같은 PC면 `127.0.0.1:8080`, 다른 기기면 서버가 출력한 `192.168.x.x:8080`.
4. 다른 기기(폰/다른 PC)에서 접속이 안 되면: 같은 와이파이인지, PC 방화벽에서 Godot의
   "개인 네트워크" 접근을 허용했는지 확인한다.

## 테스트

```sh
godot --headless --path client --import                    # 최초 1회 (클래스 캐시 생성)
godot --headless --path client -s res://tests/run_tests.gd  # 실패 시 종료 코드 1
```

## 로드맵

- [x] 규칙 코어 + 테스트
- [x] 한 기기 2인 대전, 핀치 줌/이동, 편리한 이동 버튼
- [x] 무승부 규칙 (총 450수)
- [x] 온라인 대전: 방 코드 + 서버 권위 수 검증 (Godot 헤드리스 서버, 같은 와이파이 테스트)
- [ ] 줄 긋기 애니메이션 (돌이 벌어지는 연출), 효과음
- [ ] 한글 폰트 번들 (지금은 OS 폰트 폴백에 의존)
- [ ] 서버 배포 (외부에서 접속 가능한 주소, wss)
- [ ] 재접속, 턴 시간 제한
- [ ] 랜덤 매칭, 랭킹
- [ ] 모바일 내보내기 시 `server/`, `tests/` 제외 (export filter)
