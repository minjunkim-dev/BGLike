# BGLike

두 사람이 만드는 Godot 4 싱글 플레이 전술 RPG의 개발 작업명입니다. 게임의 정식 이름과 세계관은 첫 플레이 가능 구간을 만든 뒤 결정합니다.

## 시작

- Godot 4.7.2 Standard와 Git LFS가 필요합니다. 이미 설치돼 있으면 그대로 씁니다.
- `git lfs install`을 한 번 실행하고 저장소를 복제합니다.
- 저장소 안에서 `git config core.hooksPath .githooks`를 한 번 실행합니다. 커밋 제목 형식 검사와 Git LFS hook이 함께 켜집니다.
- `project.godot`을 Godot에서 엽니다.
- F6으로 현재 장면을, F5로 메인 장면을 실행합니다.

명령줄에서는 다음으로 확인합니다.

```sh
godot --headless --path . --import
godot --headless --path . --quit-after 2
git diff --check
godot --headless --path . --script tests/combat_turns_test.gd
```

`godot`이 PATH에 없다면 설치된 Godot 앱의 실행 파일 경로를 사용합니다. macOS 외장 SSD 설치 예시는 `/Volumes/P41_USB4/Godot.app/Contents/MacOS/Godot`입니다.

## 협업 규칙

- 처음이라면 [참여 안내](CONTRIBUTING.md)를 읽습니다. Issue, 브랜치, 커밋, 문서, 개발 규칙을 한 장으로 요약했습니다.
- 작업은 GitHub Issue에 목표와 완료 조건을 적고 시작합니다. 작은 브랜치에서 PR을 열고 동료 검토 후 squash merge합니다.
- [협업 절차](docs/WORKFLOW.md)와 [AI 에이전트 지침](AGENTS.md)을 따릅니다. Claude Code는 `CLAUDE.md`에서 같은 지침을 읽습니다.
- 비공개 저장소의 현재 GitHub 요금제로는 `main` 보호 규칙을 켤 수 없습니다. 자세한 상태와 대신 지키는 운영 규칙은 협업 절차에 있습니다.
- `.godot/` 캐시는 커밋하지 않습니다. 장면과 스크립트 등 원본 파일은 커밋합니다. `.gitattributes`에 지정된 바이너리는 Git LFS로 관리합니다.

## 현재 범위

Issue #12의 M1 전투 프로토타입을 단계별로 만듭니다. 기반은 640×360 기준 화면, 정수 배율과 픽셀 필터, 10×10 평지 아이소메트릭 격자, 아군·적 각 전사와 궁수의 고정 배치입니다. 메인 장면을 실행하면 임시 도형 격자와 유닛 4명이 바로 보입니다.

현재 2단계는 `d20 + 민첩` 이니셔티브, 연속한 같은 편의 턴 묶음, 유닛별 이동·행동·보조 행동·반응 자원, 턴 종료입니다. 아군 묶음에서는 왼쪽 위 초상을 눌러 유닛을 전환합니다. 선택 테두리와 오른쪽 위의 자원 표시가 함께 바뀝니다. 전환은 자원을 회복하지 않습니다. 턴 종료는 현재 유닛만 끝내며, 묶음의 전원이 끝내면 다음 묶음으로 넘어갑니다.

아군은 파랑, 적은 빨강입니다. 유닛 안의 검과 활로 전사와 궁수를 구분합니다. 이동·공격·스킬 입력과 AI는 이후 단계입니다. 이번에는 적도 순서대로 턴 종료 버튼을 눌러 넘깁니다. 아직 실행 가능한 동작이 없어 턴 종료 버튼은 강조되며, 누르기 전에는 턴이 끝나지 않습니다. 자원 소비와 회복 규칙은 위 자동 검사로 확인합니다. 전체 전투 UI는 5단계에서 추가합니다.

규칙은 [전투 시스템 기획서](docs/COMBAT_DESIGN.md), 검수 기준은 [M1 개발 요청서](docs/DEV_REQUEST_M1.md), 용어는 [CONTEXT.md](CONTEXT.md)를 따릅니다. 대화, 저장, 플랫폼별 내보내기는 이번 단계에 포함하지 않습니다.
