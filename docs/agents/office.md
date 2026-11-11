# claude-office로 작업 돌리기

[repo-baseline-office](https://github.com/minjunkim-dev/repo-baseline-office)의 `claude-office/`는 PR을 열기 전 작업(설계, 구현, 검사, 리뷰)을 단계로 나눠 돌립니다. 이 저장소에 복사하는 파일은 없습니다. office 체크아웃이 이 저장소를 `--repo`로 받아 `jobs/<과제>/repo/`에 worktree(브랜치 `office/<과제>`)를 만듭니다. 규칙은 office의 `claude-office/AGENTS.md`를 따릅니다.

## 과제 등록

leader 세션이 office 체크아웃의 `claude-office/`에서 한 번에 하나씩 실행합니다.

```bash
python3 ../pipeline/engine.py new <과제> --repo <BGLike 경로> --base origin/main --test 'mkdir -p "$TMPDIR/home" && HOME="$TMPDIR/home" GIT_CONFIG_GLOBAL=/dev/null GODOT=/Applications/Godot.app/Contents/MacOS/Godot sh -c "python3 scripts/check_whitespace.py && make godot-check"'
```

`--test`는 [AGENTS.md](../../AGENTS.md)의 check 칸 중 공백 검사와 test 칸(`make godot-check`)에 아래 환경을 붙인 것입니다. `make check`의 `repository-check` 중 Python 단위 테스트(`scripts/test_*.py`)는 넣지 않았습니다. 이 테스트는 시스템 임시 폴더와 `xcrun`을 쓰고 로컬 git 훅을 push로 돌려서, office의 검사 sandbox 안에서는 실패합니다. 그 테스트는 CI와 사람이 `make check`로 돌립니다. 작업자 sandbox와 검사 단계 sandbox는 홈 폴더 읽기·쓰기를 막으므로 아래 환경이 없으면 Godot 검사도 실패합니다.

| 값 | 이유 |
| --- | --- |
| `HOME="$TMPDIR/home"` | Godot가 `~/Library/Application Support/Godot`에 쓰려다 막힙니다. |
| `GIT_CONFIG_GLOBAL=/dev/null` | git이 `~/.gitconfig`를 못 읽어 `git rev-parse`가 실패합니다. |
| `GODOT=…/Godot` | `make godot-install`은 네트워크가 `github.com`뿐인 sandbox에서 받기 어렵습니다. 미리 설치한 4.7.2를 씁니다. `scripts/godot.env`의 버전과 다르면 검사가 실패합니다. |

## 알아둘 것

- 브랜치 이름 검사는 `office/…`를 면제합니다([브랜치·커밋 규칙](../GIT_CONVENTIONS.md)). 사람이 PR을 열 때 이름을 바꿀 필요는 없습니다.
- `.claude/settings.json`은 office가 `--setting-sources project`로 읽지 않습니다. 이 저장소의 거부 규칙은 office 작업자에게 적용되지 않고, office 단계표의 거부 목록이 대신합니다.
- 작업자는 `make check`를 `engine.py test <과제>`로만 돌립니다. `GODOT` 같은 환경은 `task.json`의 `test`에 이미 들어 있습니다.
- 이 저장소의 훅(`core.hooksPath=.githooks`)은 작업자 sandbox에서 `commit`·`push` 때 도는지 확인하지 않았습니다.
