# 전투 캡처와 게임 진행 보존 검사

`tests/capture_observer.gd`는 별도 Node다. 전투의 로그·피드백·차례 변경 신호를 관찰한다. 독립 Timer가 이벤트 뒤 1.2초 동안 약 10fps로 원본 Viewport를 저장한다. `RenderingServer.frame_post_draw` 뒤에 이미지를 읽는다. 전투 스크립트를 상속하거나 전투의 `_process`를 덮어쓰지 않는다. 강제 렌더링을 호출하지 않는다.

제품의 메인 장면에는 캡처 Node를 넣지 않는다. 검증 실행에서만 추가한다. 저장 폴더에 `frames.jsonl`이 있으면 덮어쓰기를 거부한다. 실행마다 새 폴더를 사용한다.

## 확인 등급

Issue·PR·기획 문서의 확인 항목과 체크박스는 아래 등급 중 하나다. 누가 체크하는지는 이 절이 기준이다. 다른 문서가 사람 확인이나 기획 검수로 지정한 항목은 사람 판단이다.

| 등급 | 예 | 체크 |
| --- | --- | --- |
| 자동 검사 | Godot 회귀 검사, CI, 문서 반영, 입력 영역 유지 | 에이전트가 명령·결과·CI 링크와 함께 체크한다. |
| 에이전트 직접 조작 | 실제 OS 입력, Retina·Metal, 해상도별 화면 | 사용자가 현재 대화나 Issue에서 그 항목을 에이전트에 맡겼을 때 에이전트가 체크한다. 체크한 줄에 위임 근거와 [직접 확인](#forward-직접-확인) 증거를 링크한다. 대화에서 맡겼으면 날짜와 사용자 발언 원문을 Issue나 PR 코멘트에 먼저 남기고 그 코멘트를 링크한다. 맡기지 않았으면 결과를 코멘트로 남기고 체크는 사람이 한다. |
| 사람 판단 | 미감, 조작감, 기획 검수, 크기·수치 확정 같은 제품 결정 | 사람이 체크한다. 에이전트는 판단 자료와 증거를 코멘트로 남긴다. |

항목에 등급이 적혀 있지 않으면 내용으로 정한다. "보기 좋은지", "확정"처럼 판단이 들어간 항목과 등급이 애매한 항목은 사람 판단이다. 위임은 맡긴 항목에만 적용하고 다른 항목이나 이후 작업으로 넓히지 않는다.

## 자동 검사

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot make check
```

기존 Godot 검사에 `tests/combat_capture_test.gd`를 포함한다. 실제 게임 장면 `scenes/game.tscn`을 불러온다. 3-3 스테이지로 진입한다. 이니셔티브만 아군 먼저로 고정한다. 자동 검사는 주사위 seed를 고정한다. 자동 검사는 아군의 반응 횟수를 소진해 선택 창 대기를 피한다. 실제 AI와 이동·공격 연출을 유지한다.

이동·공격 연출을 바꾸면 [HUD 장면 검사](../tests/combat_hud_test.gd)와 [동작 장면 검사](../tests/combat_actions_test.gd)를 함께 확인한다. 두 파일은 서로 다른 장면 진입점과 입력 잠금 fixture를 가진다. 새로 시작한 연출은 완료까지 기다린다. 이미 잠근 fixture와 반응 창은 다음 입력을 기다리는 상태로 구분한다. 기회 공격 뒤 점프 검사는 공격 연출이 끝난 뒤 비용 소비·공중 상태를 확인한다. 최종 검사는 `make check`로 수행한다.

검사는 HUD의 차례 종료 신호를 보낸다. 전투의 `_process`가 적 AI를 시작해야 한다. 적 차례가 끝난 뒤 아군 차례로 돌아와야 한다. 제한 시간 안에 복귀하지 못하면 실패한다. 별도 watchdog도 검증 프로세스를 종료한다.

headless 실행은 차례 복귀와 이벤트 파일을 검사한다. headless 실행은 PNG 검사를 제외했다고 출력한다. 이 성공을 Forward+ 화면 검증으로 사용하지 않는다.

## Forward+ 직접 확인

에이전트의 직접 확인은 아래 실행 기록 도우미(`scripts/manual_qa.py`)를 사용한다. 기본은 Docker 안의 화면 밖 실행(`--mode offscreen`)이다. macOS 창 실행(`--mode macos`)은 실제 OS 입력·Retina·Metal 확인이 필요한 사례에 쓴다. 포커스 사용은 해당 사례에 대한 사용자의 명시적 승인이 있어야 한다. 사람의 직접 확인은 그대로 macOS 편집기에서 한다. 확인 결과로 체크박스를 처리하는 기준은 [확인 등급](#확인-등급)을 따른다.

두 방법 모두 고정 버전의 headless `--check-only`로 스크립트를 먼저 검사한다. 종료 코드가 0이어도 `SCRIPT ERROR` 또는 `Failed to load script`가 있으면 게임을 열지 않는다. 이 사전 검사는 런타임 검증을 대신하지 않는다. 사례마다 새 로그와 캡처 폴더를 사용한다. 런타임 오류, 제한 시간 초과, 성공 표식 뒤에 소유한 인스턴스만 종료한다. 원본 프레임은 계속 남는다.

### 실행 경로 선택

1. 새 실행 환경을 준비하기 전에 [기존 사례](#사례별-전제조건)와 관련 PR의 최종 검수 기록을 찾는다. 실제 Mac 입력의 선례는 [#351의 PR #352](https://github.com/minjunkim-dev/BGLike/pull/352), 가방·보상 반복 사례와 하단 경계는 [#366의 PR #368](https://github.com/minjunkim-dev/BGLike/pull/368)·[#367의 PR #369](https://github.com/minjunkim-dev/BGLike/pull/369)다. 사용한 스크립트·실행 방법·입력 경로·포커스 승인 범위와 증거의 한계를 확인한다. 실제 입력을 받는 관찰 사례는 `presentation_qa.gd --transitions`(`--case=prep|crate|rock|resume`, 정비 화면은 `prep`)와 `--manual`을 읽는 `combat_capture_test.gd`·`combat_feedback_test.gd`다. 맞는 사례가 있으면 그 사례로 `manual_qa.py`를 실행하고, 도우미가 만드는 것 외에 프로젝트 사본이나 별도 실행 환경을 만들지 않는다. 맞는 사례가 없을 때 반복할 확인이면 기존 사례를 확장하거나 [사례별 전제조건](#사례별-전제조건)대로 `tests/`에 추가하고, 한 번만 할 확인은 아래 [실행 기록](#직접-확인-실행-기록)의 임시 사례 형식을 쓴다.
2. 이번에 필요한 증거를 고른다. 문구·배치는 화면 밖 사례를 재사용한다. 실제 macOS 입력·Retina·Metal이 목표이면 호스트 Mac의 기존 실행기를 사용하고, 자동 입력을 대신 실행하지 않는 관찰용 사례를 고른다. 호스트 하드웨어 검증은 호스트 경로를 유지한다.
3. 현재 대화의 포커스 승인 범위를 확인한다. 승인이 없으면 기본 보호를 유지한다. Godot의 자체 활성화로 중단되면 해당 실패와 미검증 범위를 기록한다. 승인된 사례는 아래 `foreground_approval`에 날짜·사용자 발언·대상 사례를 적는다. 과거 실행의 승인을 새 사례로 옮기지 않는다.

### 화면 밖 실행 (기본)

`scripts/qa_offscreen.Dockerfile`이 Ubuntu 24.04 이미지 `bglike-qa-offscreen`을 만든다. Xvfb, Mesa llvmpipe Vulkan과 `fonts-noto-cjk`를 설치한다. Godot은 `scripts/install_godot.sh`가 `scripts/godot.env`의 Linux SHA-256을 확인한 공식 4.7.2다. Docker(OrbStack)가 필요하다. 도우미는 시도마다 `docker build`를 호출해 이미지를 Dockerfile·설치 스크립트와 맞춘다. 첫 빌드는 몇 분 걸리고, 이후는 캐시를 쓴다.

빌드 전에 `docker info`로 엔진 연결을 5초 안에 확인한다. CLI 없음·연결 실패·시간 초과는 실패한 시도로 기록하고 빌드와 컨테이너 정리를 시작하지 않는다. OrbStack 전체 재시작은 다른 컨테이너·VM에 영향을 주므로 사용자 승인을 받은 뒤 수행한다.
기존 세션을 재개할 때의 컨테이너 조회와 소유 컨테이너 정리 명령에도 각각 5초 제한을 둔다. Docker가 멎으면 기존 인스턴스가 없다고 간주하지 않고 실패한다.

1. 시도마다 네트워크 없는 새 컨테이너를 띄운다. 작업 폴더를 읽기 전용으로 연결하고 `.godot`·`.git`·`.cache`·`.env*`·`export_credentials.cfg`를 뺀 사본을 컨테이너 안에서 import한다. import에 `SCRIPT ERROR` 또는 `Failed to load script`가 있으면 게임을 열지 않는다.
2. 시도 폴더가 컨테이너의 `/out`이다. `container.log`, `import.log`, `preflight.log`, `game.log`, `frames/`가 시도 폴더에 남는다. `state.json`의 시도 기록에 컨테이너 이름과 이미지 ID를 남긴다.
3. Godot는 `xvfb-run` 안에서 사례 해상도와 같은 가상 화면에 Forward+ Vulkan으로 연다. `game.log`에 `Forward+`와 `llvmpipe`가 찍힌다.
4. 성공·실패·중단 뒤 `docker rm -f`로 컨테이너를 지운다. 지우지 못하면 실패로 기록한다. 제어 프로세스가 강제 종료되어 컨테이너가 남으면 다음 `run`이 멈춘다. `docker ps --filter name=bglike-qa`로 확인하고 로그를 본 뒤 `docker rm -f <이름>`으로 지운다.

화면 밖에는 OS 입력을 보낼 창이 없다. 도우미는 `--manual`을 넘기지 않는다. 사례 스크립트가 자동 경로에서 입력을 만든다(`Input.parse_input_event`, HUD 신호). 그리고 성공 표식을 출력한 뒤 스스로 종료한다. `combat_capture_test.gd`와 `combat_feedback_test.gd`는 `success_marker`를 `, 0 failures;`로 둔다. 실패 수가 1 이상이면 오류 규칙이 먼저 실패로 처리한다.

증거의 한계:

- 프로젝트는 글꼴을 넣지 않는다. 한글은 운영체제의 대체 글꼴로 그린다. 컨테이너는 Noto Sans CJK, macOS는 Apple SD Gothic Neo다. 글리프 모양·폭이 달라 줄바꿈과 넘침이 macOS와 다를 수 있다. 글자 배치가 합격 기준이면 [macOS 창 실행](#macos-창-실행---mode-macos) 또는 사람의 macOS 확인을 남긴다.
- Mesa llvmpipe는 CPU에서 도는 소프트웨어 Vulkan이다. macOS Metal과 셰이더 정밀도, 필터, 안티앨리어싱 결과가 픽셀 단위로 다를 수 있다. 프레임 속도와 연출 시간도 다르다. 픽셀 비교는 같은 경로에서 찍은 변경 전후끼리만 한다.
- Retina(HiDPI) 배율, macOS 창 관리와 실제 키보드·마우스·컨트롤러 입력 전달은 확인하지 못한다. 스크립트 입력은 OS 입력 경로를 거치지 않는다. 이 항목은 [macOS 창 실행](#macos-창-실행---mode-macos) 또는 사람의 macOS 편집기 확인으로 남기고, 체크는 [확인 등급](#확인-등급)을 따른다.
- 오디오는 dummy 드라이버로 대체된다.

### macOS 창 실행 (`--mode macos`)

도우미는 `open -g -n -W`로 Forward+ 인스턴스를 연다. `--manual`을 넘긴다. 직접 확인 모드는 이니셔티브만 고정한다. 실제 전투 주사위와 반응 UI를 유지한다. 기본은 해당 Godot 인스턴스에 연결한 비활성 창 입력이다. 포커스 사용을 승인받은 사례도 같은 실행·사전 검사·입력·종료 경로를 재사용한다.

`open -g`로 띄워도 Godot 창이 스스로 맨 앞에 올 수 있다. 2026-10-22 [#264](https://github.com/minjunkim-dev/BGLike/issues/264) 작업([PR #268](https://github.com/minjunkim-dev/BGLike/pull/268))에서 일어났다. 조건은 공식 Godot 4.7.2 Forward+의 macOS `open -g` 창과, 2-1 장면의 윤곽을 원본 Viewport로 저장하는 임시 스크립트다. 윤곽 캡처 두 번에서 Godot가 약 0.3초 맨 앞 앱이 됐다. 감시 스크립트가 `lsappinfo front`로 감지했다. 그 스크립트는 pid를 잘못 읽어 즉시 종료하지 못했다. 두 인스턴스는 캡처 뒤 스스로 끝났다.

같은 날 같은 실행 방법의 [PR #266](https://github.com/minjunkim-dev/BGLike/pull/266) 측정은 `lsappinfo front`를 0.05초 간격으로 읽었고, Godot가 맨 앞에 오지 않았다. 간헐적이며 원인은 특정하지 못했다. 이후 PR #267, #269~#271, #273, #275의 화면 확인은 화면 밖 실행으로 대신했다. 사용자 포커스를 가져가므로 이 문서를 고칠 때 다시 재현하지 않았다.

보호 장치: 게임을 연 뒤 0.1초마다 `lsappinfo front`의 pid를 읽는다. 그 pid가 이 시도의 Godot(실행 파일과 로그 경로로 식별)이면 즉시 그 인스턴스를 종료하고 사례를 `failed`로 기록한다. 시도 기록의 `foreground`와 `reason`에 감지를, `cleanup_error`에 종료 실패(`Owned Godot instance did not stop`)를 남긴다. 감지 전에 포커스는 이미 넘어갔을 수 있다. 이 장치는 피해 시간을 줄일 뿐 막지 못한다. 그래서 기본은 화면 밖 실행이다.

명시적 승인: 현재 사용자가 특정 사례의 포커스 사용을 허용했으면 그 사례 객체에 `"foreground_approval": "<승인 날짜·사용자 발언·대상 사례>"`를 넣는다. 비어 있지 않은 문자열만 받으며 `--mode macos`에서만 유효하다. 시도 기록에 승인 원문과 감지한 `foreground_pid`를 남기고, 승인된 소유 Godot의 전면 전환은 중단 사유로 처리하지 않는다. 실행기가 앱을 활성화하는 명령을 추가하지는 않는다. 다른 사례는 각각 승인이 필요하다. 승인 내용은 계획 fingerprint에 포함되므로 변경·철회 시 기존 세션을 재사용할 수 없다. 기본 보호, 오류·시간 제한, 소유 프로세스 정리와 원본 검토 후 `accept`는 유지한다.

아래 절차와 CUA 규칙은 macOS 창 실행에 적용한다.

1. 로그의 `[CAPTURE_CHECK] READY`를 확인한다.
2. 게임 창에서 아군 두 명의 `턴 종료`를 누른다.
3. 반응 창이 열리면 사용할 반응 또는 넘기기를 선택한다.
4. 적 AI가 끝난 뒤 아군 차례로 돌아오는지 확인한다.
5. 로그의 `Combat capture: ... 0 failures`와 저장된 원본 PNG를 확인한다.

검사는 차례 복귀 후에도 프레임을 저장한다. PNG를 다시 읽어 1280×720 크기를 확인한다. `frames.jsonl`에서 프레임과 선행 이벤트의 연결을 확인한다. 스크립트의 직접 확인 모드는 성공 후 화면을 유지한다. 실행 기록 도우미는 성공 표식을 읽은 뒤 해당 인스턴스를 종료한다. 입력을 기다리는 시간은 120초다. 적 차례 복귀 제한은 15초다. 전체 watchdog은 180초다.

### CUA 대상 갱신과 복구

1. 실행 로그와 인스턴스를 대조한 뒤 해당 Godot 인스턴스에 연결한다. 포커스 승인 범위 안에서만 창을 활성화하고, 입력은 해당 인스턴스에 보낸다. Mac 잠금이나 도구의 접근 차단은 우회하지 않는다. 현재 사례를 중단하고 차단 이유를 기록한다.
2. 입력마다 새 AX 상태를 읽고 다음 대상을 다시 찾는다. 이전 입력에서 사용한 AX 번호를 재사용하지 않는다. 초상은 현재 스크롤 영역에 보이는 대상을 선택한다. 상태가 바뀌지 않으면 입력을 반복하기 전에 로그와 전투 상태를 확인한다.
3. `windowNotFoundAtPosition`이면 같은 인스턴스에 한 번만 재연결한다. 새 AX 상태에서 대상을 찾아 입력을 한 번만 다시 시도한다. 다시 실패하면 현재 사례를 중단한다. 다른 창으로 대상을 바꾸거나 전면으로 올리지 않는다.
4. CUA 조작 실패는 `도구 실패`로 기록한다. 입력 전달과 게임 상태를 확인한 뒤 합격 기준을 어긴 경우에만 `게임 실패`로 기록한다. 실패 뒤에는 다음 입력이나 사례로 넘어가지 않는다.
5. 창 캡처가 흰 화면이면 독립 관찰 Node의 원본 Viewport PNG를 사용한다. 이벤트 번호·시간과 대응시켜 확인한다. PNG는 픽셀 증거다. 입력 성공과 전투 진행은 별도 로그·상태로 확인한다. 이 경로를 CUA 캡처 문제의 해결로 보고하지 않는다.

### 모달 입력과 종료 상태 관찰

반응 모달은 Tab을 전투 루트의 `_input`에 전달하지 않을 수 있다. 루트의 입력 횟수만 기다리면 native 입력을 보냈어도 사례가 멈춘다. 모달 잠금은 앱에 보낸 입력, 새 AX 상태와 조작 유닛 상태를 함께 확인한다. 모달을 닫은 뒤에도 조작 유닛이 같은지 확인한다. 모달 안의 포커스 이동과 전투의 조작 유닛 전환을 구분한다.

마지막 입력 직후 `noWindowsAvailable`이나 `procNotFound`가 나오면 기존 실행의 로그와 `state.json`을 먼저 확인한다. 성공 표식을 읽은 도우미가 소유 인스턴스를 정리했을 수 있다. `awaiting_review`는 검토 대기 상태다. 원본 프레임과 입력 증거를 확인한 뒤 `accept`한다. 로그와 실행 상태를 확인하기 전에 `getApp`으로 새 앱을 실행하지 않는다.

## 직접 확인 실행 기록

1. 작업 폴더 밖에 `plan.json`을 만든다. `source_sha`에는 `git rev-parse HEAD`의 전체 SHA를 넣는다. `inputs`에는 Git이 무시하는 임시 보조 스크립트를 모두 적는다. 사례를 시작한 뒤 계획을 바꾸지 않는다. 아래 예시는 macOS 창 실행의 직접 입력 사례다.

   ```json
   {
     "source_sha": "<전체 HEAD SHA>",
     "inputs": [],
     "cases": [{
       "id": "capture-compact",
       "script": "res://tests/combat_capture_test.gd",
       "resolution": [1280, 720],
       "timeout": 180,
       "acceptance": "비활성 창의 턴 종료 입력, 적 차례 진입, 아군 차례 복귀, 이벤트와 원본 PNG 대응을 확인한다.",
       "success_marker": "[CAPTURE_CHECK] PASS:"
     }]
   }
   ```

   화면 밖 실행은 같은 스크립트의 자동 경로를 쓰므로 `success_marker`를 `", 0 failures;"`로 바꾸고, 합격 기준에서 직접 입력을 뺀다.

   임시 사례도 같은 형식을 사용한다. `args` 문자열 배열로 `--profile=compact` 같은 사용자 인수를 추가할 수 있다. 스크립트는 실제 창 크기를 유지해야 한다. 크기를 자체 변경하는 스크립트는 그 크기를 합격 기준과 증거에 기록한다.

   초기화가 있는 임시 도우미는 같은 스크립트에 headless 초기화 분기를 만든다. 사례에 `preflight_args` 문자열 배열과 `preflight_success_marker`를 함께 지정한다. 예를 들어 `preflight_args: ["--fixture-precheck"]` 분기는 두 해상도에서 쓸 배치·자료형·메서드 호출을 실제 초기화한 뒤 성공 표식을 출력하고 종료한다. 인수는 엔진 옵션 뒤의 `--`로 전달한다. 기존 문법 검사 뒤 이 분기를 실행한다. 종료0·오류 없음·필수 표식을 모두 만족해야 게임을 연다. 실패·표식 누락·30초 초과는 실행을 막는다. 결과는 각 시도의 `fixture-preflight.log`에 남는다. 두 필드가 없는 기존 계획은 문법 검사만 실행한다. 이 초기화 검사는 실제 입력·원본 프레임 검수를 대체하지 않는다.

2. 도우미로 다음 미완료 사례 하나를 실행한다. 도우미가 실행 중일 때 파일을 수정하거나 다른 검사를 시작하지 않는다.

   ```sh
   python3 ~/.agents/tools/agent_workflow.py check -- \
     python3 scripts/manual_qa.py run /tmp/plan.json /tmp/bglike-qa-session-01
   ```

   macOS 창 실행은 모든 명령(`run`·`status`·`accept`·`reject`)에 `--mode macos`를 붙인다. 한 세션 폴더는 한 실행 방법만 쓴다. 다른 방법은 새 세션 폴더를 사용한다.

3. macOS 창 실행이면 해당 인스턴스에 연결한 CUA로 필수 입력을 수행한다. 실패한 단계 뒤에는 다음 입력을 보내지 않는다. 화면 밖 실행은 스크립트가 입력을 마친 뒤다. 성공 표식은 자동 검사 완료만 뜻한다. 상태는 `awaiting_review`로 남는다. 원본 PNG를 열고 입력·프레임 번호·이벤트·실행 조건을 작업 폴더 밖의 `review.md`에 기록한다.

4. 합격 기준을 모두 확인했으면 사례를 승인한다. 화면이나 입력이 실패했으면 `accept` 대신 `reject`를 사용한다. 실패 이유도 증거 파일에 적는다.

   ```sh
   python3 scripts/manual_qa.py accept /tmp/plan.json /tmp/bglike-qa-session-01 \
     --case capture-compact --evidence /tmp/review.md
   ```

5. 같은 `run` 명령으로 다음 미완료 사례만 실행한다. 모든 사례가 `passed`이면 종료한다. `status` 명령으로 현황을 확인한다. 계획·SHA·로컬 변경·임시 입력 파일이 바뀌면 기존 기록을 보존하고 새 세션 폴더를 사용한다. 범위를 추가할 때 유효한 기존 증거는 새 보고서에서 참조한다.

`state.json`은 `not_run`, `running`, `failed`, `interrupted`, `awaiting_review`, `passed`를 구분한다. 각 시도의 로그와 캡처를 덮어쓰지 않는다. 오류 뒤의 성공 표식도 성공으로 처리하지 않는다. 미검토 사례가 있으면 다음 사례를 열지 않는다.

`SIGINT`·`SIGTERM`은 현재 사례를 `interrupted`로 기록하고 소유한 프로세스나 컨테이너를 종료한다. 제어 프로세스가 강제 종료됐으면 재개 전에 기존 Godot 인스턴스나 컨테이너의 생존 여부를 확인한다. 살아 있으면 새 인스턴스를 열지 않는다. 기존 창과 전투 상태를 먼저 확인한다. 기존 인스턴스를 계속 검증할 수 없으면 해당 인스턴스만 종료한다. 이후 같은 `run` 명령은 해당 사례를 새 시도로 시작한다. 전투 중간 상태를 저장하거나 복원하지는 않는다.

### PNG 저장 픽셀 크기

실행 성공 뒤 소유 인스턴스를 종료하고, `frames/` 바로 아래 PNG의 IHDR 헤더에서 실제 저장 픽셀 크기를 읽는다. `state.json`의 해당 시도에 `"png_sizes": {"0001.png": [1280, 720]}`처럼 파일별 `[width, height]`를 남긴다. PNG signature·IHDR 길이·CRC 또는 크기 범위가 잘못됐으면 시도를 `failed`로 기록한다. 원본은 보존하며 `accept`할 수 없다. PNG가 없는 기존 사례는 빈 객체를 남긴다.

| 값 | 근거와 의미 |
| --- | --- |
| `png_sizes` | 저장한 PNG 헤더의 픽셀 크기 |
| 계획의 `resolution` | 요청한 창 크기. 실제 창·PNG 크기의 측정값이 아님 |
| 창·논리 viewport·배율·texture | 각 사례의 런타임 관찰 파일(`frames.json`, `frames.jsonl` 등)에 있는 별도 값. 실제 창은 `DisplayServer.window_get_size()`, 논리 영역은 `get_visible_rect()`, 배율은 `screen_get_scale()`, texture는 `get_texture().get_size()` 같은 해당 관찰의 출처를 확인 |

런타임 값이 없으면 미기록으로 두며 PNG 크기에서 역으로 추정하지 않는다. Retina 배율을 곱하거나 texture 크기를 복사해 PNG 크기로 보고하지 않는다. 헤더 확인은 전체 이미지 디코딩·화면 가독성 검토를 대신하지 않는다. 크기 기록 뒤에도 `awaiting_review`에서 원본 검토 후 별도 `accept`를 해야 통과한다. 기존 런타임 관찰 파일은 수정하지 않는다.

### 사례별 전제조건

입력이나 AI 진행 전에 사례의 유닛 구성·초상 수·턴 자원을 검사한다. 조건이 맞지 않으면 사례를 종료한다. 성공 이벤트나 `READY`를 출력하지 않는다. 임시 스크립트도 같은 기준을 따른다. 공통 fixture 검사기는 만들지 않는다.

통제 주사위 fixture는 실제 유닛의 `get_ability_sides()`·공격/방어 가산값·피해 능력치 주사위(`ScriptedDice.damage_sides()`)를 먼저 읽는다. 공격 능력치 → 방어 능력치 → 명중일 때 피해처럼 제품의 소비 순서를 적고 `ScriptedDice`의 값과 면수를 함께 준비한다. 유리/불리·반응·추가 피해·보상 확률도 순서에 포함한다. 의도한 명중·빗나감이 성립하는지 입력 전에 검사하고, 끝에는 기존 `ScriptedDice.finish()`로 면수 불일치·미소비·부족 난수를 확인한다. 통제하려는 분기의 부족한 난수를 `then_seeded()`로 숨기지 않는다. [#339](https://github.com/minjunkim-dev/BGLike/issues/339)의 개발 결정이며, 이동 기회 공격 사례가 이 작성 방식의 예다.

반복할 사례는 `tests/`의 추적 파일로 유지하고 기존 `manual_qa.py` 또는 아래 `qa_movement.py`로 실행한다. 실행별 SHA·입력 fingerprint·로그·실패 시도는 기존 도우미의 기록을 재사용한다. 구현 PR의 문서 누락 확인은 [PR 양식](../.github/pull_request_template.md)의 영향 문서 항목과 [Spec 리뷰](agents/review.md#별도-컨텍스트)에서 기획서·개발 요청서의 구현 상태와 갱신 내용 또는 유지 이유를 대조한다. 별도 검사기나 완료 기준을 중복해 만들지 않는다.

| 기존 사례 | 확인하는 전제조건과 증거 범위 |
| --- | --- |
| `presentation_qa.gd --transitions` | #351의 실제 Mac 입력 관찰. 정상 RNG seed351·자동 저장·실제 적 `_process`를 켠다. `--case=resume --save-path=<검수 저장>`은 새 프로세스 타이틀에서 이어하기를 기다린다. resume 사전 검사는 체크포인트의 복사본으로 실제 타이틀 복원 경로를 확인한다. 장면 전환 뒤 현재 장면을 다시 찾아 상태·원본·모달 버튼을 기록한다. 창 관리/OS 입력 도우미는 실행 입력 fingerprint와 함께 보존한다. 사용자 저장과 설정은 사용하지 않는다. |
| `soak_qa.gd` | #351의 3-1 장기 관찰. 현재 loot 데이터의 최대 허용 장비·정상 최대 HP·물약 한도와 고정 seed를 사용한다. 첫 전투 시작은 실제 입력, 이후 아군은 가까운 적 자동 정책·반응 승인이다. 적 AI는 실제 전투 `_process`가 시작하며 정상 연출/속도를 유지한다. 첫 시작 입력 뒤 300초는 관찰 종료일 뿐 게임 규칙/성능 통과선이 아니다. CSV 프레임·정적 메모리·동시 생존 수, 누적 생성·저장 비용을 기록한다. 반복 전투의 기존 장비는 다시 받지 않는다. 사람 플레이/승률로 해석하지 않는다. |
| `terrain_qa.gd` | #347의 실제9맵 초기/우클릭 이동 미리보기와1-1 상자 파괴·1-2 바위 충돌. 아군 차례/공격 위치만 통제하고 스크립트 GUI 입력·피해 능력치 주사위 면수를 사용. `--fixture-precheck`로 같은 초기화/입력을 먼저 확인. 자연 진행·OS 입력은 제외. |
| `preparation_qa.gd` | #366의 보상 2개·정비 상세·제품 한도까지 채운 가방·공간 부족·버리기 확인. 실제 아이템 정의와 `is_valid_item()`을 사용한다. 스크립트 포인터 입력·확인 창 신호로 취소 기본 선택과 아이템 수 보존을 확인하고 원본 PNG 6장을 남긴다. |
| `combat_capture_test.gd` | 3-3의 전사·궁수·고철로봇 3000, 초상 3개, 정상 HP·아군 턴 자원. 자동 모드의 반응 0과 직접 확인 모드의 정상 반응을 구분한다. |
| `combat_feedback_test.gd` | 유닛 3개와 초상 3개, 과부하 HP 25(행동 2는 보스 턴 시작에 받음), 인접 아군과 반응 0. 주사위·배치·HP를 고정한 재현이다. 자연 플레이나 정상 HP 표시의 증거로 사용하지 않는다. 밀집 사례는 3-1 유닛 7개, 새끼 거미 차례와 궁수 대상을 확인한다. |
| `combat_hud_test.gd`의 소환 사례 | 시작 7개체의 구성, 소환 로그 6건·새 개체 6개·초상 13개, 초상 입력 전후 아군 턴 자원 보존. HP 1000과 직접 `ai.play_turn()` 호출을 사용한 자동 HUD 검사다. 비활성 창 입력이나 전투 `_process`가 AI를 시작한다는 증거로 사용하지 않는다. |

유닛 몸통 클릭과 초상 클릭의 계약도 구분한다. 아군 몸통 클릭은 공격 선택을 취소한다. 밀치기를 선택했을 때는 아군 몸통도 대상 미리보기·확정을 받는다. 조작 유닛 전환은 아군 초상으로 확인한다. 빈 영역의 좌표는 실제 초상·스크롤 영역을 읽어 정한다.

### 가방·보상 반복 검수

[문구 변경 절차](WORKFLOW.md#화면-문구-변경)에서 가방·보상 화면을 바꾸면 `tests/preparation_qa.gd`를 기존 `manual_qa.py`로 실행한다. 아래 사례를 작업 폴더 밖 `plan.json`의 `cases`에 넣고 `source_sha`를 현재 HEAD로 정한다. `inputs`는 빈 배열이다.

```json
{
  "id": "preparation-compact",
  "script": "res://tests/preparation_qa.gd",
  "resolution": [1280, 720],
  "timeout": 60,
  "acceptance": "보상·정비 상세·가방 안내·버리기 확인이 읽히고, 하단 안내와 진행 버튼의 전체 영역이 화면 안에 있으며 아이콘·취소 기본 선택이 보인다.",
  "success_marker": "[PREPARATION_QA_PASS]",
  "preflight_args": ["--fixture-precheck"],
  "preflight_success_marker": "[PREPARATION_PREFLIGHT_PASS]"
}
```

위 [실행 기록](#직접-확인-실행-기록)의 `run`·원본 검토·`accept`/`reject` 흐름을 그대로 쓴다. 첫 사례를 통과하면 변경 영향에 따라 대표 16:9·16:10 해상도를 추가한다. `--capture-dir`은 도우미가 전달한다. 사전 검사는 같은 초기화와 입력을 headless로 실행하고 PNG를 만들지 않는다.

원본은 `reward-overview.png`, `maintenance-selected.png`, `finish-confirmation.png`, `bag-full-notice.png`, `bag-discard-button.png`, `discard-confirmation.png`다. `frames.json`은 캡처별 창·논리 화면 크기와 보이는 라벨의 문구·영역·줄 수를 남긴다. 공간 부족은 가방을 제품 한도까지 채우고 보상 2개를 남겨 재현한다. 확인 창의 취소 기본 선택과 버리기 취소 뒤 아이템 수 보존도 검사한다.

#367부터 각 캡처에서 하단 안내와 진행 버튼의 전체 영역이 논리 화면 안에 있는지 검사한다. `frames.json`의 `footer`는 진행 버튼 영역이다. 글꼴·창 크기를 실제로 적용한 렌더링 사례에서 확인하며 headless 초기화 통과만으로 영역 검사를 완료 처리하지 않는다.

자동 저장은 끄고 저장·설정 경로는 실행별 검사 경로로 격리한다. 글꼴은 실행 환경의 기본 대체 글꼴을 사용한다. 성공 표식은 화면 가독성 승인 전의 자동 검사 완료이며, 실제 macOS 입력·Retina·Metal·사람 플레이는 포함하지 않는다.

## PCK 이동 후조건의 재현

`tests/movement_qa.gd`와 `scripts/qa_movement.py`는 [#336](https://github.com/minjunkim-dev/BGLike/issues/336)의 검수 전용 하네스다. 정상 이동, 기회 공격 빗나감, 기회 공격으로 전투 불능, 이동 중 전투 종료, 확인 클릭 누락의 5개 통제 사례를 한 번 실행한다. 마지막 사례는 이동 검사기가 실패를 검출해야 통과한다. 초기화만 확인하고 성공하는 별도 fixture precheck는 없다. 기존 `ScriptedDice.finish()`가 면수·미소비·부족 난수를 확인한다.

먼저 [Draft 검증](DRAFT_RELEASE.md)의 `verify_draft.py`로 대상 artifact를 확인한다. 그 출력의 `assets/`와 전체 source SHA를 전달한다. 하네스는 기존 `verify_bundle()`로 bundle을 다시 확인하고 `manual_qa.load_plan()`으로 하네스 checkout·입력의 fingerprint를 기록한다. artifact source와 하네스 HEAD는 별도 식별자다.

```sh
python3 ~/.agents/tools/agent_workflow.py check -- \
  python3 scripts/qa_movement.py \
    --bundle /path/to/verified-draft/assets \
    --version v0.1.0-alpha.3 --source-sha <artifact의 전체 SHA> \
    --output /path/to/new-movement-evidence \
    --godot /Applications/Godot.app/Contents/MacOS/Godot
```

출력은 checkout 밖의 새 폴더만 받으며 기존 기록을 덮어쓰지 않는다. 복사한 하네스와 PCK를 headless·임시 HOME/XDG에서 실행한다. `inputs.json`, 엔진·문법·실행 로그, `fixtures.json`을 남기고, 다섯 사례와 negative control까지 통과해야 `result.json`을 만든다. 실패 원인과 로그는 보존하고 다른 폴더로 재시도한다. 고정 `/tmp` 경로나 원래 세션의 파일은 필요 없다.

이 결과는 통제된 배치의 이동 경로·비용·잠금 해제 증거다. 자연 진행·졸업·밸런스·실제 창 해상도·픽셀·사람의 직접 플레이 검수를 대신하지 않는다. 새 제품 입력·화면 변경의 검수는 위 실행 기록 절차를 따른다.

## 증거의 완료 기준

| 항목 | 필요한 증거 |
| --- | --- |
| 전투 진행 | 실제 적 차례 진입과 라운드 2 아군 차례 복귀 |
| 저장 | 이벤트 파일과 다시 읽을 수 있는 원본 PNG |
| 대응 | 이벤트 번호·실행 시간·유닛·라운드가 연결된 프레임 |
| 시각 확인 | 적 차례 전후 원본 PNG를 직접 열어 확인 |
| 실행 조건 | 소스 SHA·로컬 diff·실행 방법(화면 밖·macOS)·Forward+ 시작 로그·입력 기록(직접 입력 또는 스크립트 입력) |

캡처 관찰 Node의 제거는 전투 콜백과 신호 처리를 보존해야 한다. 저장 실패는 검사 실패로 보고한다. CUA의 흰 화면 캡처 원인을 고쳤다는 뜻으로 보고하지 않는다. 이 도구는 게임 Viewport를 저장하는 별도 경로다.

## 과부하 반복 공격 팝업 재현

`tests/combat_feedback_test.gd`는 실제 3-3 장면에서 고철로봇 3000의 과부하와 인접 아군 두 명을 준비한다. `ScriptedDice`로 회전회오리 두 번의 대상별 힘 내성 실패·성공과 피해를 고정한다. 아군 반응 횟수는 소진한다. 이 실행은 자연 주사위 플레이가 아닌 통제된 결함 재현이다. 실제 전투 `_process`, AI와 연출은 유지한다.

`make check`는 매 프레임 팝업끼리의 겹침, 화면 밖 이탈과 HUD 침범을 검사한다. 두 회전 공격의 횟수·피해, 차례 복귀와 팝업 제거도 검사한다.

같은 검사는 [#260](https://github.com/minjunkim-dev/BGLike/issues/260)의 밀집 배치도 재현한다. 3-1에서 궁수를 여섯 유닛이 둘러싸게 놓고 새끼 거미의 능력치 대결 공격을 같은 대상에게 두 번 실행한다. 배치는 위쪽 HUD와 떨어져 있어 위로 쌓을 공간이 있다. 연속 `1` 피해 팝업이 대상의 기준 자리에서 40 논리px 안인지 확인한다. 같은 대상의 다음 팝업이 이전 팝업 위에 놓이는지도 확인한다. 이 사례는 적 AI를 멈추고 통제한 공격 두 번만 실행한다.

직접 확인에는 위 계획의 `script`를 `res://tests/combat_feedback_test.gd`로 바꾼다. macOS 창 실행의 `success_marker`는 `[FEEDBACK_CHECK] PASS`, 화면 밖 실행은 `, 0 failures;`로 지정한다. 새 세션 폴더를 사용한다. macOS 창 실행이면 아군 두 명의 `턴 종료`를 누른다. 명중·빗나감이 포함된 두 회전 공격을 확인한다. 원본 PNG에서 팝업 배치와 사라지는 과정을 확인한다.
