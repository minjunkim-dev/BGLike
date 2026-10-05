# CI 구성과 실행 범위

Godot 워크플로는 main push, main 대상 PR과 수동 실행을 검사합니다.
문서 변경에도 워크플로 자체는 실행합니다. 워크플로 전체의 paths-ignore로 필수 상태 검사를 대기 상태에 두지 않습니다.

## 검사 선택

첫 작업은 재사용 PR lint의 `PR conventions and scope`입니다.
선택기는 PR 기준 SHA 또는 main push의 before SHA에서 가져옵니다. PR이 수정한 선택기로 자신의 엔진 검사를 생략하지 않습니다.
기준 선택기가 없으면 엔진 검사를 선택합니다. 새 선택기 규칙은 main 반영 뒤 후속 변경부터 사용합니다.
전체 PR diff와 main push의 before SHA를 기준으로 공백과 변경 범위를 확인하고 Python 회귀 테스트를 실행합니다.
PR에서는 제목과 브랜치 규칙도 검사합니다.

- Markdown, `docs/` 자료와 `scripts/ci_scope.py`에 명시된 관리 파일만 바뀌면 Godot 작업을 선택하지 않습니다.
- 게임 코드·장면·자산·프로젝트 설정, CI 선택기와 게임 검사 워크플로 변경은 모든 기존 Godot 검사를 선택합니다.
- 파일 이동은 이동 전·후 경로를 모두 확인합니다. 게임 파일을 문서 폴더로 옮겨도 게임 검사를 수행합니다.
- 알 수 없는 파일, 유효하지 않은 기준 SHA나 누락된 Git 이력은 게임 검사를 수행합니다.
- 수동 실행은 항상 Godot 검사를 수행합니다. PR의 edited 이벤트는 별도 PR lint workflow에서 처리합니다.
- 제목·본문 수정은 실행 중인 Godot workflow를 취소하거나 같은 이름의 smoke 검사를 skipped로 덮어쓰지 않습니다.
- main push 실행은 후속 문서 push로 취소하지 않습니다. PR 실행만 같은 PR의 후속 실행으로 취소합니다.
- main과 수동 실행은 실행 ID별 concurrency 그룹을 사용합니다. 대기 중인 기능 검사도 후속 문서 push로 대체하지 않습니다.

제목 수정만으로 재사용 policy 검사의 과거 실패가 바뀌지는 않습니다.
제목 수정 후 새 커밋을 push하여 최신 제목의 policy 검사를 실행합니다. 기존 실행의 재실행은 과거 이벤트의 제목을 사용합니다.
edited 전용 lint 검사는 제목 변경을 빠르게 확인하는 보조 검사입니다.

Godot 작업은 headless import, 메인 장면 시작과 기존 전투 회귀 테스트를 모두 수행합니다.
Ubuntu 24.04에서 로컬과 같은 `make godot-install`, `make godot-check`를 호출합니다.
엔진 버전·해시는 `scripts/godot.env`를 따릅니다. [공통 환경](ENVIRONMENT.md)에 새 환경 설치와 캐시 없는 실행을 기록합니다.
검사 실패를 통과로 처리하지 않습니다. PR 병합 전에 `PR conventions and scope`와 선택된 `smoke` 결과를 함께 확인합니다.
공개 후 main 보호를 설정할 때도 두 검사 모두 필수로 지정합니다. 문서 변경의 smoke skipped는 정상입니다.
재사용 작업의 실제 check 이름은 호출 작업 이름을 포함할 수 있습니다. GitHub의 해당 실행에서 이름을 확인한 뒤 보호 규칙에 지정합니다.
현재 CI는 PC 출시 패키지를 내보내거나 배포하지 않습니다.
외부 Action은 전체 커밋 SHA로 고정합니다. Dependabot이 매주 수요일 Action 업데이트 PR을 엽니다.

## 알림과 권한

Discord는 비-Draft PR의 열림·재열림·ready 전환과 PR 종료를 알립니다.
Godot 워크플로의 별도 알림 작업은 정책 또는 게임 검사 실패에만 실행합니다.
정상 실행마다 별도 runner를 할당하거나 제목 수정·검토자 요청마다 반복 알림을 보내지 않습니다.
알림 작업은 PR 코드를 checkout하거나 실행하지 않습니다. 외부 fork에는 Secret 알림을 실행하지 않습니다.

Claude의 공개 저장소용 신뢰 경계는 [협업 규칙](WORKFLOW.md)의 AI 자동화 절차를 따릅니다.
