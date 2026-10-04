# Issue tracker: GitHub

작업은 GitHub `minjunkim-dev/BGLike`의 Issues에서 관리합니다. GitHub 작업에는 `gh` CLI를 사용합니다.

아래 명령 예시는 RTK가 설치된 로컬 환경 기준입니다. RTK가 없는 환경에서는 `rtk proxy` 접두어를 제외하고 같은 `gh` 명령을 실행합니다. 저장소 조회의 `rtk git remote -v`도 `rtk`를 제외하면 기본 Git 명령입니다. RTK 설치를 필수로 요구하지 않습니다. GitHub Actions의 실행 권한과 명령 제한은 [협업 규칙](../WORKFLOW.md)을 따릅니다.

기획의 규칙과 수치는 `docs/` 문서가 기준입니다. Issue에는 목표, 완료 조건, 문서 링크, 결정과 진행을 기록합니다.

## Conventions

먼저 [AGENTS.md](../../AGENTS.md), [협업 규칙](../WORKFLOW.md), [브랜치와 커밋 규칙](../GIT_CONVENTIONS.md)을 읽습니다.

- 작업할 Issue의 본문, 라벨과 코멘트를 읽습니다. Issue에 연결된 기획 문서도 직접 엽니다.
- 새 Issue는 [Issue 양식](../../.github/ISSUE_TEMPLATE/task.md)의 `목표`, `완료 조건`, `범위와 참고` 제목을 사용합니다.
- 기존 Issue의 목표나 범위를 본문에서 다시 쓰지 않습니다. 결정과 변경은 코멘트에 남깁니다. 큰 범위 변경은 새 Issue로 나눕니다.
- 기존 GitHub 운영에는 `claude` 라벨을 사용합니다. 분류 역할의 이름은 [triage-labels.md](triage-labels.md)를 따릅니다. 이 설정 작업은 원격 라벨을 만들거나 Issue에 붙이지 않습니다.
- 최신 `main`에서 짧은 브랜치를 만듭니다. PR은 [PR 양식](../../.github/pull_request_template.md)을 사용합니다. 관련 Issue는 `Refs #번호`, 해당 Issue를 끝내는 마지막 PR은 `Closes #번호`를 씁니다.
- Issue는 완료 조건과 검수 결과를 확인한 뒤 닫습니다. 다단계 작업은 한 단계가 끝났다는 이유만으로 닫지 않습니다.

저장소는 `rtk git remote -v`로 확인합니다. 명령의 저장소가 모호하면 `--repo minjunkim-dev/BGLike`를 지정합니다.

## CLI operations

여러 줄의 본문이나 코멘트는 정확한 내용을 파일에 저장하고 `--body-file`로 전달합니다.

```sh
rtk proxy gh issue view <번호> --repo minjunkim-dev/BGLike --json number,title,body,labels,comments,state
rtk proxy gh issue list --repo minjunkim-dev/BGLike --state open --json number,title,body,labels
rtk proxy gh issue create --repo minjunkim-dev/BGLike --title "<제목>" --body-file <본문 파일>
rtk proxy gh issue comment <번호> --repo minjunkim-dev/BGLike --body-file <코멘트 파일>
rtk proxy gh issue edit <번호> --repo minjunkim-dev/BGLike --add-label "<라벨>"
rtk proxy gh issue edit <번호> --repo minjunkim-dev/BGLike --remove-label "<라벨>"
rtk proxy gh issue close <번호> --repo minjunkim-dev/BGLike
```

## Pull requests as a triage surface

**PRs as a request surface: no.**

기능 요청과 작업의 입력은 Issue입니다. PR은 변경을 검토하고 병합하는 곳입니다. GitHub에서 Issue와 PR은 번호를 공유하므로, 번호가 가리키는 대상을 확인합니다.

## When a skill says "publish to the issue tracker"

정해진 Issue 양식으로 GitHub Issue를 만듭니다. 기존 Issue에 기록할 결정이나 진행이면 본문을 바꾸지 않고 코멘트를 남깁니다.

## When a skill says "fetch the relevant ticket"

`rtk proxy gh issue view <번호> --repo minjunkim-dev/BGLike --json number,title,body,labels,comments,state`를 실행합니다. 코멘트의 결정 기록과 연결된 기획 문서도 읽습니다.
