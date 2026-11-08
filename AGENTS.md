# BGLike 작업 지침

Godot 4 싱글 플레이 PC 게임입니다. GitHub 품질 운영은 1인 개발 기준입니다. 미확정 제품 결정은 관련 Issue에서 확인합니다.

프로필: 1인
이 파일은 사람, Claude Code, Codex의 공통 길잡이입니다. 도구별 프로젝트 지침 파일을 만들지 않습니다.

## 구현 길잡이

- 작업 시작: [협업 규칙](docs/WORKFLOW.md)과 [브랜치·커밋 규칙](docs/GIT_CONVENTIONS.md)을 읽습니다. 다른 작업자의 변경을 보존합니다.
- 브랜치를 만들기 전에 [브랜치·커밋 규칙](docs/GIT_CONVENTIONS.md)을 먼저 읽습니다. 도구가 `claude/…`처럼 자동 이름을 지정해도 이름 검사가 면제될 뿐이므로, 새 작업은 최신 `main`에서 `<type>/<issue번호>-<짧은-설명>` 형식의 브랜치로 시작합니다.
- 제품 사양: 관련 Issue의 목표·완료 조건과 연결한 기획 문서를 읽습니다. 용어·ADR은 [문서 길잡이](docs/agents/domain.md)를 따릅니다.
- 검증: [README](https://github.com/minjunkim-dev/BGLike/blob/main/README.md)의 명령과 [CI 구성](docs/CI.md)의 범위 규칙을 확인합니다. 플레이 변경의 직접 확인 기준은 [협업 규칙](docs/WORKFLOW.md#검증과-보고)을 따릅니다.
- GitHub 설정: [설정 기준선과 읽기 전용 검증](docs/REPOSITORY_SETUP.md)을 따릅니다.
- 권리·외부 자산: [COPYRIGHT](COPYRIGHT.md)와 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)를 확인합니다.

## 독립 리뷰와 병합

리뷰 에이전트는 [코딩 규칙](docs/coding-standards.md)과 [독립 리뷰 절차](docs/agents/review.md)를 읽습니다. 코딩 규칙은 구현 컨텍스트에 일괄 주입하지 않습니다.
필수 CI와 완료 조건을 통과하면 병합합니다. 독립 리뷰와 사람 승인은 병합 조건이 아닙니다. 자세한 조건은 [병합 정책](docs/WORKFLOW.md#브랜치와-병합)을 따릅니다.

## Agent skills

- Issue tracker: GitHub `minjunkim-dev/BGLike`. `docs/agents/issue-tracker.md`를 읽습니다.
- Triage labels: `docs/agents/triage-labels.md`에서 다섯 역할과 라벨을 확인합니다.
- Domain docs: [문서 길잡이](docs/agents/domain.md)를 따릅니다.

### 작업 진입

작업 진입·초기 설정 확인·명세와 티켓의 통합: [개발 절차](docs/agents/development.md)를 읽습니다. 작은 수정에는 전체 명세 절차를 강제하지 않습니다.
