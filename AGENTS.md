# BGLike 작업 지침

Godot 4 싱글 플레이 PC 게임입니다. GitHub 품질 운영은 1인 개발 기준입니다. 미확정 제품 결정은 관련 Issue에서 확인합니다.

프로필: 1인
이 파일은 사람, Claude Code, Codex의 공통 길잡이입니다. 도구별 프로젝트 지침 파일을 만들지 않습니다. Claude Code는 `CLAUDE.md`가 없으면 이 파일을 읽으므로 `CLAUDE.md`·`.claude/CLAUDE.md`·`CLAUDE.local.md`를 두지 않습니다. 기본 설정에서는 하나라도 있으면 Claude Code가 이 파일을 읽지 않습니다.

## 명령

모든 에이전트와 사람이 같은 명령을 쓴다. 엔진 경로는 `GODOT=<Godot 4.7.2 실행 파일>`로 지정한다.

- setup: `make godot-install`  (Git LFS와 `git config core.hooksPath .githooks`는 [README](README.md#시작))
- check: `make repository-check`  (공백·Python 검사)
- test: `make godot-check`  (Godot import·메인 장면·회귀 검사. 전체는 `make check`)
- build: N/A: 출시 빌드 없음. 검증용 PCK는 [Draft 절차](docs/DRAFT_RELEASE.md)

## 길잡이

| 경로 | 무엇 |
| --- | --- |
| `scenes/`, `project.godot` | 게임 장면·GDScript·자산 |
| `tests/` | Godot 회귀 검사 |
| `scripts/` | 검사·CI·Draft 도구와 Python 테스트 |
| `docs/` | 기획·ADR·작업 규칙. [문서 길잡이](docs/agents/domain.md) |
| `REVIEW.md` | 리뷰 기준. 리뷰할 때만 읽는다 |

- 작업 시작: [협업 규칙](docs/WORKFLOW.md)과 [브랜치·커밋 규칙](docs/GIT_CONVENTIONS.md)을 읽습니다. 다른 작업자의 변경을 보존합니다.
- 브랜치를 만들기 전에 [브랜치·커밋 규칙](docs/GIT_CONVENTIONS.md)을 먼저 읽습니다. 도구가 `claude/…`처럼 자동 이름을 지정해도 이름 검사가 면제될 뿐이므로, 새 작업은 최신 `main`에서 `<type>/<issue번호>-<짧은-설명>` 형식의 브랜치로 시작합니다.
- 제품 사양: 관련 Issue의 목표·완료 조건과 연결한 기획 문서를 읽습니다. 용어·ADR은 [문서 길잡이](docs/agents/domain.md)를 따릅니다.
- 검증: [CI 구성](docs/CI.md)의 범위 규칙을 확인합니다. 플레이 변경의 직접 확인 기준은 [협업 규칙](docs/WORKFLOW.md#검증과-보고)을 따릅니다.
- 작업 진입·초기 설정 확인·명세와 티켓의 통합: [개발 절차](docs/agents/development.md). 작은 수정에는 전체 명세 절차를 강제하지 않습니다.
- 코드를 바꾸는 Issue 작업은 repo-office 파이프라인으로 돌립니다. 코드를 바꾸는 작업은 [브랜치 규칙](docs/GIT_CONVENTIONS.md#브랜치-이름)의 코드 type(`feat`, `fix`, `refactor`, `perf`, `test`, `revert`)입니다.
  - 에이전트는 이 저장소에서 직접 구현하지 않습니다. 사람에게 "#번호는 repo-office leader 세션에 주세요"라고 알리고 멈춥니다. 다른 세션에 메시지를 보낼 수 있는 에이전트는 사람이 허락하면 떠 있는 leader 세션에 직접 보냅니다.
  - leader 세션은 사람이 repo-office 체크아웃의 `leader/` 폴더에서 하나만 띄웁니다. leader는 방향 선택과 설계 승인을 사람에게 묻습니다. 등록 명령은 [office 절차](docs/agents/office.md)에 있습니다.
  - 이 규칙은 [협업 규칙](docs/WORKFLOW.md)의 "로컬 앱으로 구현"과 [개발 절차](docs/agents/development.md)의 `implement`보다 먼저입니다. office 과제의 브랜치는 `office/<과제>`이고, 위 브랜치 이름 규칙을 따르지 않습니다.
  - 예외: 문서·설정 작업(`docs`, `build`, `ci`, `chore`), 이미 열린 PR의 리뷰 수정과 CI 실패 수정, 사람이 여기서 하라고 한 작업.
- GitHub 설정: [설정 기준선](docs/REPOSITORY_SETUP.md). 권리·외부 자산: [COPYRIGHT](COPYRIGHT.md)와 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).

## Agent skills

- Issue tracker: GitHub `minjunkim-dev/BGLike`. `docs/agents/issue-tracker.md`를 읽습니다.
- Triage labels: `docs/agents/triage-labels.md`에서 다섯 역할과 라벨을 확인합니다.
- Domain docs: [문서 길잡이](docs/agents/domain.md)를 따릅니다.

## 작업 방식

- 기준 브랜치는 `main` 하나다. 작업 브랜치는 짧게, 병합은 squash다. 끝나지 않은 기능은 꺼진 진입점 뒤에 둔다.
- 완료 주장은 위 명령의 실제 출력이다. PR 본문 Evidence에 명령과 결과, 확인하지 못한 것을 적는다.
- 병합 전에 구현과 다른 컨텍스트의 리뷰어가 `REVIEW.md`로 변경분을 본다. 절차는 [리뷰 절차](docs/agents/review.md), 결과는 PR 본문 Review에 적는다. 되돌리기 쉬움이고 `REVIEW.md`에 적은 민감한 파일을 건드리지 않으면 이 대화를 물려받지 않는 하위 에이전트 하나에게 로컬 repo-baseline 클론의 `prompts/review.md` 경로와 PR 링크만 주어 맡길 수 있다. 결과가 마음에 들지 않는다고 하위 에이전트를 새로 띄우지 않는다. 그 리뷰가 끝날 때까지 작업 트리를 고치거나 push하지 않고, 리뷰어가 고친 커밋과 Review 칸을 고치지 않는다. 되돌리기 어려움이거나 `REVIEW.md`에 적은 민감한 파일을 건드리면 새 세션이 리뷰한다. PR을 연 세션은 소유자에게 묻지 않고 되돌리기 판정에 맞는 리뷰(하위 에이전트 또는 새 세션)를 시작한다. 병합은 소유자가 정한다.
- PR 본문 Merge Danger에 되돌리기 쉬움/어려움, 영향 범위, 되돌리는 법을 적는다. 애매하면 되돌리기 어려움이다.
- 되돌리기 어려움이거나 `REVIEW.md`에 적은 민감한 파일을 건드리면 보안 리뷰를 더하고, 사람이 diff를 읽고 그 head에서 병합한다.
- 같은 실수가 두 번 나오면 린트·검사로 막고, 그다음 `REVIEW.md` 한 줄, 그다음 이 파일의 길잡이 순서로 고친다.
- 작업 추적은 GitHub Issue 하나만 쓴다. 내부 트래커(예: Linear)는 쓰지 않는다. 일정·우선순위·기획 판단도 공개 Issue와 `docs/`에 적는다. repo-baseline 코어 `AGENTS.md`의 "우선순위·일정·내부 판단을 공개 이슈·PR·커밋에 적지 않는다" 줄은 이 저장소에 적용하지 않는다.

## 하지 않는 것

- 비밀값(`.env*`, 키, 토큰, 웹훅 URL)을 읽거나 커밋하지 않는다. `.env.example`은 예외다.
- 취약점 설명·익스플로잇을 공개 Issue·PR·커밋·댓글에 적지 않는다. 취약점은 [SECURITY.md](SECURITY.md)의 비공개 취약점 보고로 받는다.
- `main`에 직접 push하지 않는다. PR을 병합하지 않는다. 병합은 사람이 한다.
- 브랜치 보호·저장소 설정·CI workflow를 사람 승인 없이 바꾸지 않는다.
