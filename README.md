# 줄긋기 오목 (Linego)

게임 도중 줄을 그어 판을 확장하는 오목. Godot 4.7, 모바일 세로 화면(1080×1920).

규칙은 [docs/RULES.md](docs/RULES.md) 참고.

## 구조

```
client/                     Godot 프로젝트 (에디터에서 client/project.godot 을 연다)
  core/                     규칙 로직. 노드에 의존하지 않는 순수 GDScript
    board_state.gd            판 상태, 줄 긋기(행/열 삽입), 정확히-5목 탐색
    game_state.gd             턴 진행, 행동 검증/적용, 승리 판정
  scenes/
    home/                   홈 화면 (2인 대전 시작, 편리한 이동 설정, 규칙)
    game/                   게임 화면
      game.gd                 입력(탭/핀치/드래그) 해석, UI 갱신
      board_view.gd           GameState를 그리기만 함
      board_camera.gd         확대/이동 연산
  autoload/settings.gd      전역 설정 (user://settings.cfg 저장)
  tests/                    헤드리스 테스트
docs/RULES.md               규칙 문서 (구현의 기준)
```

### 설계 원칙

- **규칙은 `core/` 한 곳에만.** 화면은 `GameState` 를 읽어 그리기만 하고, 모든 행동은
  `GameState.apply(action)` 을 통해서만 일어난다.
- **행동은 직렬화 가능한 Dictionary.**
  `{"type": "place", "x": 2, "y": 3}`, `{"type": "line", "axis": "col", "index": 0}`.
  온라인 대전을 붙일 때 이 형식 그대로 서버와 주고받는다.
- `core/` 는 노드를 쓰지 않으므로 Godot 헤드리스 서버에서도 같은 코드로 수를 검증할 수 있다.

## 조작

- **돌 놓기 / 세로줄 / 가로줄** 중 모드를 고른 뒤 판을 탭하면 미리보기가 나온다.
  같은 곳을 한 번 더 탭하거나 **확정**을 누르면 실행된다.
- 두 손가락으로 확대·축소·이동, 한 손가락 드래그로 이동. 데스크톱에서는 마우스 휠로 확대.
- **전체보기**: 판 전체가 보이게 맞춘다.

## 테스트

```sh
godot --headless --path client --import                    # 최초 1회 (클래스 캐시 생성)
godot --headless --path client -s res://tests/run_tests.gd  # 실패 시 종료 코드 1
```

## 로드맵

- [x] 규칙 코어 + 테스트
- [x] 한 기기 2인 대전, 핀치 줌/이동, 편리한 이동 버튼
- [ ] 미정 규칙 확정 (판 최대 크기 / 무승부) — docs/RULES.md 참고
- [ ] 줄 긋기 애니메이션 (돌이 벌어지는 연출), 효과음
- [ ] 한글 폰트 번들 (지금은 OS 폰트 폴백에 의존)
- [ ] 온라인 대전 (매칭 + 서버 권위 수 검증)
