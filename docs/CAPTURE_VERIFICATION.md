# 전투 캡처와 게임 진행 보존 검사

`tests/capture_observer.gd`는 별도 Node다. 전투의 로그·피드백·차례 변경 신호를 관찰한다. 독립 Timer가 이벤트 뒤 1.2초 동안 약 10fps로 원본 Viewport를 저장한다. `RenderingServer.frame_post_draw` 뒤에 이미지를 읽는다. 전투 스크립트를 상속하거나 전투의 `_process`를 덮어쓰지 않는다. 강제 렌더링을 호출하지 않는다.

제품의 메인 장면에는 캡처 Node를 넣지 않는다. 검증 실행에서만 추가한다. 저장 폴더에 `frames.jsonl`이 있으면 덮어쓰기를 거부한다. 실행마다 새 폴더를 사용한다.

## 자동 검사

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot make check
```

기존 Godot 검사에 `tests/combat_capture_test.gd`를 포함한다. 실제 `scenes/main.tscn`을 불러온다. 3-3 스테이지로 진입한다. 이니셔티브만 아군 먼저로 고정한다. 자동 검사는 주사위 seed를 고정한다. 자동 검사는 아군의 반응 횟수를 소진해 선택 창 대기를 피한다. 실제 AI와 이동·공격 연출을 유지한다.

검사는 HUD의 차례 종료 신호를 보낸다. 전투의 `_process`가 적 AI를 시작해야 한다. 적 차례가 끝난 뒤 아군 차례로 돌아와야 한다. 제한 시간 안에 복귀하지 못하면 실패한다. 별도 watchdog도 검증 프로세스를 종료한다.

headless 실행은 차례 복귀와 이벤트 파일을 검사한다. headless 실행은 PNG 검사를 제외했다고 출력한다. 이 성공을 Forward+ 화면 검증으로 사용하지 않는다.

## Forward+ 직접 확인

macOS에서는 다음 명령으로 검증 인스턴스를 백그라운드에서 연다. `--capture-dir`에는 아직 사용하지 않은 절대 경로를 넣는다.

```sh
open -g -n /Applications/Godot.app --args \
  --path "$PWD" --rendering-method forward_plus --accessibility always \
  --log-file /tmp/bglike-capture-playtest.log \
  --script res://tests/combat_capture_test.gd -- \
  --manual --capture-dir=/tmp/bglike-capture-playtest-01
```

직접 확인 모드는 이니셔티브만 고정한다. 실제 전투 주사위와 반응 UI를 유지한다. 게임 창을 전면으로 올리는 명령은 사용하지 않는다. 입력 도구는 해당 Godot 인스턴스에 연결한 비활성 창 입력을 사용한다.

1. 로그의 `[CAPTURE_CHECK] READY`를 확인한다.
2. 게임 창에서 아군 두 명의 `턴 종료`를 누른다.
3. 반응 창이 열리면 사용할 반응 또는 넘기기를 선택한다.
4. 적 AI가 끝난 뒤 아군 차례로 돌아오는지 확인한다.
5. 로그의 `Combat capture: ... 0 failures`와 저장된 원본 PNG를 확인한다.

검사는 차례 복귀 후에도 프레임을 저장한다. PNG를 다시 읽어 640×360 크기를 확인한다. `frames.jsonl`에서 프레임과 선행 이벤트의 연결을 확인한다. 성공한 직접 확인 모드는 화면을 유지한다. 확인 후 해당 검증 인스턴스만 종료한다. 입력을 기다리는 시간은 120초다. 적 차례 복귀 제한은 15초다. 전체 watchdog은 180초다.

## 증거의 완료 기준

| 항목 | 필요한 증거 |
| --- | --- |
| 전투 진행 | 실제 적 차례 진입과 라운드 2 아군 차례 복귀 |
| 저장 | 이벤트 파일과 다시 읽을 수 있는 원본 PNG |
| 대응 | 이벤트 번호·실행 시간·유닛·라운드가 연결된 프레임 |
| 시각 확인 | 적 차례 전후 원본 PNG를 직접 열어 확인 |
| 실행 조건 | 소스 SHA·로컬 diff·Forward+ 시작 로그·직접 입력 기록 |

캡처 관찰 Node의 제거는 전투 콜백과 신호 처리를 보존해야 한다. 저장 실패는 검사 실패로 보고한다. CUA의 흰 화면 캡처 원인을 고쳤다는 뜻으로 보고하지 않는다. 이 도구는 게임 Viewport를 저장하는 별도 경로다.
