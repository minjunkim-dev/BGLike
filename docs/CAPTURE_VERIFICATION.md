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

macOS의 직접 확인은 아래 실행 기록 도우미를 사용한다. 도우미는 고정 버전의 headless `--check-only`로 스크립트를 먼저 검사한다. 종료 코드가 0이어도 `SCRIPT ERROR` 또는 `Failed to load script`가 있으면 창을 열지 않는다. 이 사전 검사는 런타임 검증을 대신하지 않는다.

도우미는 `open -g -n -W`로 Forward+ 인스턴스를 연다. 사례마다 새 로그와 캡처 폴더를 사용한다. 런타임 오류나 제한 시간 초과를 감지하면 해당 인스턴스를 종료한다. 성공 표식을 읽은 뒤에도 해당 인스턴스만 종료한다. 원본 프레임은 계속 남는다.

직접 확인 모드는 이니셔티브만 고정한다. 실제 전투 주사위와 반응 UI를 유지한다. 게임 창을 전면으로 올리는 명령은 사용하지 않는다. 입력 도구는 해당 Godot 인스턴스에 연결한 비활성 창 입력을 사용한다.

1. 로그의 `[CAPTURE_CHECK] READY`를 확인한다.
2. 게임 창에서 아군 두 명의 `턴 종료`를 누른다.
3. 반응 창이 열리면 사용할 반응 또는 넘기기를 선택한다.
4. 적 AI가 끝난 뒤 아군 차례로 돌아오는지 확인한다.
5. 로그의 `Combat capture: ... 0 failures`와 저장된 원본 PNG를 확인한다.

검사는 차례 복귀 후에도 프레임을 저장한다. PNG를 다시 읽어 640×360 크기를 확인한다. `frames.jsonl`에서 프레임과 선행 이벤트의 연결을 확인한다. 스크립트의 직접 확인 모드는 성공 후 화면을 유지한다. 실행 기록 도우미는 성공 표식을 읽은 뒤 해당 인스턴스를 종료한다. 입력을 기다리는 시간은 120초다. 적 차례 복귀 제한은 15초다. 전체 watchdog은 180초다.

## 직접 확인 실행 기록

1. 작업 폴더 밖에 `plan.json`을 만든다. `source_sha`에는 `git rev-parse HEAD`의 전체 SHA를 넣는다. `inputs`에는 Git이 무시하는 임시 보조 스크립트를 모두 적는다. 사례를 시작한 뒤 계획을 바꾸지 않는다.

   ```json
   {
     "source_sha": "<전체 HEAD SHA>",
     "inputs": [],
     "cases": [{
       "id": "capture-compact",
       "script": "res://tests/combat_capture_test.gd",
       "resolution": [640, 360],
       "timeout": 180,
       "acceptance": "비활성 창의 턴 종료 입력, 적 차례 진입, 아군 차례 복귀, 이벤트와 원본 PNG 대응을 확인한다.",
       "success_marker": "[CAPTURE_CHECK] PASS:"
     }]
   }
   ```

   임시 사례도 같은 형식을 사용한다. `args` 문자열 배열로 `--profile=compact` 같은 사용자 인수를 추가할 수 있다. 스크립트는 실제 창 크기를 유지해야 한다. 크기를 자체 변경하는 스크립트는 그 크기를 합격 기준과 증거에 기록한다.

2. 도우미로 다음 미완료 사례 하나를 실행한다. 도우미가 실행 중일 때 파일을 수정하거나 다른 검사를 시작하지 않는다.

   ```sh
   python3 ~/.agents/tools/agent_workflow.py check -- \
     python3 scripts/manual_qa.py run /tmp/plan.json /tmp/bglike-qa-session-01
   ```

3. 해당 인스턴스에 연결한 CUA로 필수 입력을 수행한다. 실패한 단계 뒤에는 다음 입력을 보내지 않는다. 성공 표식은 자동 검사 완료만 뜻한다. 상태는 `awaiting_review`로 남는다. 원본 PNG를 열고 직접 입력·프레임 번호·이벤트·실행 조건을 작업 폴더 밖의 `review.md`에 기록한다.

4. 합격 기준을 모두 확인했으면 사례를 승인한다. 화면이나 입력이 실패했으면 `accept` 대신 `reject`를 사용한다. 실패 이유도 증거 파일에 적는다.

   ```sh
   python3 scripts/manual_qa.py accept /tmp/plan.json /tmp/bglike-qa-session-01 \
     --case capture-compact --evidence /tmp/review.md
   ```

5. 같은 `run` 명령으로 다음 미완료 사례만 실행한다. 모든 사례가 `passed`이면 종료한다. `status` 명령으로 현황을 확인한다. 계획·SHA·로컬 변경·임시 입력 파일이 바뀌면 기존 기록을 보존하고 새 세션 폴더를 사용한다. 범위를 추가할 때 유효한 기존 증거는 새 보고서에서 참조한다.

`state.json`은 `not_run`, `running`, `failed`, `interrupted`, `awaiting_review`, `passed`를 구분한다. 각 시도의 로그와 캡처를 덮어쓰지 않는다. 오류 뒤의 성공 표식도 성공으로 처리하지 않는다. 미검토 사례가 있으면 다음 사례를 열지 않는다.

`SIGINT`·`SIGTERM`은 현재 사례를 `interrupted`로 기록하고 소유한 프로세스를 종료한다. 제어 프로세스가 강제 종료됐으면 재개 전에 기존 Godot 인스턴스의 생존 여부를 확인한다. 살아 있으면 새 인스턴스를 열지 않는다. 기존 창과 전투 상태를 먼저 확인한다. 기존 인스턴스를 계속 검증할 수 없으면 해당 인스턴스만 종료한다. 이후 같은 `run` 명령은 해당 사례를 새 시도로 시작한다. 전투 중간 상태를 저장하거나 복원하지는 않는다.

## 증거의 완료 기준

| 항목 | 필요한 증거 |
| --- | --- |
| 전투 진행 | 실제 적 차례 진입과 라운드 2 아군 차례 복귀 |
| 저장 | 이벤트 파일과 다시 읽을 수 있는 원본 PNG |
| 대응 | 이벤트 번호·실행 시간·유닛·라운드가 연결된 프레임 |
| 시각 확인 | 적 차례 전후 원본 PNG를 직접 열어 확인 |
| 실행 조건 | 소스 SHA·로컬 diff·Forward+ 시작 로그·직접 입력 기록 |

캡처 관찰 Node의 제거는 전투 콜백과 신호 처리를 보존해야 한다. 저장 실패는 검사 실패로 보고한다. CUA의 흰 화면 캡처 원인을 고쳤다는 뜻으로 보고하지 않는다. 이 도구는 게임 Viewport를 저장하는 별도 경로다.

## 과부하 반복 공격 팝업 재현

`tests/combat_feedback_test.gd`는 실제 3-3 장면에서 고철로봇 3000의 과부하와 인접 아군 두 명을 준비한다. `ScriptedDice`로 명중·빗나감·치명타를 한 번의 반복 공격에 고정한다. 아군 반응 횟수는 소진한다. 이 실행은 자연 주사위 플레이가 아닌 통제된 결함 재현이다. 실제 전투 `_process`, AI와 연출은 유지한다.

`make check`는 매 프레임 팝업끼리의 겹침, 화면 밖 이탈과 HUD 침범을 검사한다. 두 회전 공격의 횟수·피해, 차례 복귀와 팝업 제거도 검사한다.

직접 확인에는 위 계획의 `script`를 `res://tests/combat_feedback_test.gd`로 바꾼다. `success_marker`는 `[FEEDBACK_CHECK] PASS`로 지정한다. 새 세션 폴더를 사용한다. 아군 두 명의 `턴 종료`를 누른다. 명중·빗나감·치명타가 포함된 두 회전 공격을 확인한다. 원본 PNG에서 팝업 배치와 사라지는 과정을 확인한다.
