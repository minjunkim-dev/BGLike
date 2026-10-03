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
```

`godot`이 PATH에 없다면 설치된 Godot 앱의 실행 파일 경로를 사용합니다. macOS 외장 SSD 설치 예시는 `/Volumes/P41_USB4/Godot.app/Contents/MacOS/Godot`입니다.

## 협업 규칙

- 처음이라면 [참여 안내](CONTRIBUTING.md)를 읽습니다. Issue, 브랜치, 커밋, 문서, 개발 규칙을 한 장으로 요약했습니다.
- 작업은 GitHub Issue에 목표와 완료 조건을 적고 시작합니다. 작은 브랜치에서 PR을 열고 동료 검토 후 squash merge합니다.
- [협업 절차](docs/WORKFLOW.md)와 [AI 에이전트 지침](AGENTS.md)을 따릅니다. Claude Code는 `CLAUDE.md`에서 같은 지침을 읽습니다.
- 비공개 저장소의 현재 GitHub 요금제로는 `main` 보호 규칙을 켤 수 없습니다. 자세한 상태와 대신 지키는 운영 규칙은 협업 절차에 있습니다.
- `.godot/` 캐시는 커밋하지 않습니다. 장면과 스크립트 등 원본 파일은 커밋합니다. `.gitattributes`에 지정된 바이너리는 Git LFS로 관리합니다.

## 현재 범위

저장소에는 아직 실행 가능한 시작 장면과 CI 확인만 있습니다. 전투, 대화, 저장 기능과 플랫폼별 내보내기는 첫 플레이 가능 구간을 정한 뒤 추가합니다.
