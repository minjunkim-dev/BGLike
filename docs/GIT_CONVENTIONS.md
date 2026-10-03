# 브랜치와 커밋 규칙

브랜치 전략, 브랜치 이름, 커밋 메시지 규칙입니다. 검토와 병합 절차는 [협업 규칙](WORKFLOW.md)을 따릅니다.

## 브랜치 전략: GitHub Flow

[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)를 사용합니다. [Trunk-Based Development](https://trunkbaseddevelopment.com/short-lived-feature-branches/)의 짧은 기능 브랜치 방식과 같습니다.

- 오래 사는 브랜치는 `main` 하나입니다. `main`은 항상 Godot에서 열리고 메인 장면이 실행되는 상태를 유지합니다.
- 모든 작업은 최신 `main`에서 만든 짧은 브랜치에서 합니다. 목표는 1~2일 안에 병합하는 것입니다. 길어지면 Issue 범위를 나눕니다.
- 병합은 squash merge만 씁니다. `main`에는 PR 하나당 커밋 하나가 남습니다. 병합한 브랜치는 GitHub가 자동으로 삭제합니다.
- 브랜치가 오래되면 `main`을 병합하거나 rebase합니다. 다른 사람이 함께 쓰는 브랜치는 강제 push하지 않습니다.

`develop`, `release/*`, `hotfix/*`를 두는 Git Flow는 쓰지 않습니다. 두 사람이 한 `main`에 자주 병합하는 구조에서는 브랜치 동기화 비용만 늘어납니다. 출시 플랫폼과 버전 체계를 정하면 `v0.1.0` 같은 태그로 출시 시점을 표시하는 방식을 별도 Issue에서 논의합니다.

## 브랜치 이름

```text
<type>/<issue 번호>-<짧은 설명>
```

| 예시 | 뜻 |
| --- | --- |
| `feat/4-combat-prototype` | Issue #4 전투 프로토타입 |
| `fix/12-unit-stuck-on-tile` | Issue #12 버그 수정 |
| `docs/git-conventions` | Issue 없는 문서 작업 |
| `chore/ai-agents` | Issue 없는 설정 작업 |

- `type`은 아래 커밋 `type` 중 하나를 씁니다. 주로 `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`를 씁니다.
- 코드를 바꾸는 브랜치(`feat`, `fix`, `refactor`, `perf`, `test`, `revert`)는 Issue 번호를 반드시 넣습니다. 브랜치 목록에서 Issue를 바로 찾을 수 있습니다. 문서·설정 브랜치(`docs`, `build`, `ci`, `chore`)는 Issue가 없으면 번호를 생략합니다.
- 소문자 영어, 숫자, `-`만 씁니다. 슬래시는 `type` 뒤에 한 번만 씁니다. 공백, 한글, 대문자, `_`는 쓰지 않습니다. 대문자를 금지하면 대소문자를 구분하지 않는 macOS 파일 시스템에서 `Feat/x`와 `feat/x`가 충돌하는 문제를 피합니다.
- 설명은 2~5단어로 짧게 씁니다.
- 도구가 자동으로 만든 `claude/…`, `codex/…` 브랜치는 이름을 바꾸지 않아도 됩니다. 사람이 이어받아 오래 작업하면 위 형식으로 새 브랜치를 만듭니다.
- 이 규칙 이전에 만든 브랜치는 이름을 바꾸지 않습니다.

## 커밋 메시지: Conventional Commits

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)을 따릅니다. 제목 작성법은 [Git 프로젝트의 커밋 지침](https://git-scm.com/docs/SubmittingPatches#describe-changes)과 [How to Write a Git Commit Message](https://cbea.ms/git-commit/)를 따릅니다.

```text
<type>(<scope>): <설명>

<본문: 무엇을 왜 바꿨는지>

<꼬리말: Closes #4, BREAKING CHANGE: ...>
```

### 제목

- 영어 명령형 현재 시제로 씁니다. `add`, `fix`처럼 씁니다. `added`, `fixes`는 쓰지 않습니다.
- `:` 뒤 설명은 소문자로 시작하고 마침표를 찍지 않습니다.
- 제목 전체를 50자 안팎으로 씁니다. 72자를 넘기지 않습니다.
- `scope`는 선택입니다. 바뀐 기능 폴더 이름을 그대로 씁니다. 예시는 `combat`, `ui`, `map`, `turn_order`입니다. 여러 기능에 걸치면 생략합니다.

### type

| type | 쓰는 경우 |
| --- | --- |
| `feat` | 플레이어가 느끼는 기능, 장면, 규칙 추가 |
| `fix` | 버그 수정 |
| `refactor` | 동작은 그대로 두고 코드와 장면 구조 정리 |
| `perf` | 프레임, 로딩 시간, 메모리 개선 |
| `test` | 검증 스크립트나 테스트 장면 추가·수정 |
| `docs` | 문서만 변경 |
| `build` | `project.godot`, 내보내기 설정, 엔진 버전 등 빌드 설정 변경 |
| `ci` | `.github/workflows` 변경 |
| `chore` | 위에 해당하지 않는 유지 작업. 예시는 `.gitignore`, 에이전트 설정입니다 |
| `revert` | 이전 커밋 되돌리기 |

- 그림, 소리, 타일셋 같은 자산은 목적을 따라 분류합니다. 새 기능에 쓰는 자산은 `feat`, 잘못된 자산을 고치면 `fix`입니다.
- 스타일 전용 `style` type은 쓰지 않습니다. GDScript 서식 정리는 `refactor`로 씁니다.

### 본문과 꼬리말

- 제목과 본문 사이에 빈 줄을 둡니다. 본문은 72자에서 줄을 바꿉니다.
- 본문에는 무엇을, 왜 바꿨는지 씁니다. 어떻게 바꿨는지는 diff가 보여줍니다. 본문은 한국어로 써도 됩니다.
- 관련 Issue는 꼬리말에 `Closes #4` 또는 `Refs #4`로 적습니다.
- 기존 저장 파일, 입력 매핑, 다른 사람이 쓰는 장면의 호환성을 깨면 제목의 `type` 뒤에 `!`를 붙이고 꼬리말에 `BREAKING CHANGE: 설명`을 적습니다.

### 예시

```text
feat(combat): add initiative-based turn order
fix(combat): keep unit selected after failed move
docs: add branch and commit conventions
ci: cache Godot export templates
refactor(map)!: store tile height in custom data

BREAKING CHANGE: 기존 map.tres의 높이 레이어는 다시 칠해야 합니다.
Refs #4
```

## PR 제목과 squash merge

squash merge를 하면 `main`에는 PR 제목이 커밋 제목으로 남습니다. 저장소 설정에서 squash 커밋 제목은 커밋 수와 관계없이 항상 PR 제목(`PR_TITLE`)을 쓰고, 본문은 브랜치 커밋 메시지(`COMMIT_MESSAGES`)를 씁니다. 그래서 **PR 제목은 반드시** 위 커밋 제목 규칙을 따릅니다.

- 좋은 예시: `feat(combat): add BG3-style turn-based combat prototype`
- 나쁜 예시: `전투 프로토타입`, `Add combat prototype`

브랜치 안의 개별 커밋은 병합하면서 하나로 합쳐지므로 같은 규칙을 권장만 합니다. 다만 검토자가 읽기 쉽도록 한 커밋에 한 가지 변경을 담습니다.

## 강제 방식

| 대상 | 검사 | 어긋나면 |
| --- | --- | --- |
| PR 제목, 브랜치 이름 | [PR lint 워크플로우](../.github/workflows/pr-lint.yml). PR을 열거나 제목을 고칠 때마다 실행 | CI 실패. 제목이나 브랜치 이름을 고치면 다시 검사 |
| 커밋 제목 | `.githooks/commit-msg`. `git config core.hooksPath .githooks`를 한 번 실행해 켬 | 커밋 거부. 급하면 `git commit --no-verify` |
| 병합 방식 | 저장소 설정: squash merge만 허용, 병합 후 브랜치 자동 삭제 | 다른 방식은 선택할 수 없음 |

`claude/…`, `codex/…` 브랜치는 이름 검사를 건너뜁니다. `main` 보호 규칙은 현재 요금제에서 켤 수 없으므로, 검토 없는 병합과 직접 push를 하지 않는 것은 팀의 약속입니다.
