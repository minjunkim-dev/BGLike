# repo-office로 작업 돌리기

[repo-office](https://github.com/minjunkim-dev/repo-office)의 파이프라인(`pipeline/`)은 PR을 열기 전 작업(설계, 구현, 검사, 리뷰)을 단계로 나눠 돌립니다. 이 저장소에 복사하는 파일은 없습니다. office 체크아웃이 이 저장소를 `--repo`로 받아 `jobs/<과제>/repo/`에 worktree(브랜치 `office/<과제>`)를 만듭니다. 규칙은 office 체크아웃 루트의 `AGENTS.md`를 따릅니다.

## 과제 등록

leader 세션이 office 체크아웃의 `leader/` 폴더에서 한 번에 하나씩 실행합니다([leader 규칙](https://github.com/minjunkim-dev/repo-office/blob/main/leader/AGENTS.md)).

```bash
python3 ../pipeline/engine.py new <과제> --repo <BGLike 경로> --base origin/main --test 'GODOT=/Applications/Godot.app/Contents/MacOS/Godot sh -c "python3 scripts/check_whitespace.py && python3 scripts/check_translation_strings.py && make godot-check"'
```

`--test`는 [AGENTS.md](../../AGENTS.md)의 check 칸 중 공백 검사, 번역 글자열 검사, test 칸(`make godot-check`)에 `GODOT`를 붙인 것입니다. 번역 글자열 검사(`check_translation_strings.py`)는 `tr()` 없이 쓴 한국어 글자열을 막습니다. `scripts/test_*.py` 안에서도 돌지만 따로 넣었습니다. [#526](https://github.com/minjunkim-dev/BGLike/pull/526)에서 이 검사가 빠져 CI에서야 실패를 봤기 때문입니다. 나머지 Python 단위 테스트(`scripts/test_*.py`)는 넣지 않았습니다. 이 테스트는 시스템 임시 폴더와 `xcrun`을 쓰고 로컬 git 훅을 push로 돌려서, office의 검사 sandbox 안에서는 실패합니다. 그 테스트는 CI와 사람이 `make check`로 돌립니다. 검사 단계 sandbox(`sandbox-exec`)는 office 엔진이 `HOME=<과제>/tmp/home`과 `GIT_CONFIG_GLOBAL=/dev/null`을 기본으로 주므로(office를 옮기기 전 저장소의 [repo-baseline-office#32](https://github.com/minjunkim-dev/repo-baseline-office/pull/32)) 이 값은 `--test`에 붙이지 않습니다. 번역 글자열 검사를 넣기 전 명령은 #526 과제에서 작업자와 검사 단계 모두 통과했습니다. 작업자의 `engine.py test`도 같은 `HOME`을 받습니다([repo-office#16](https://github.com/minjunkim-dev/repo-office/pull/16)). 번역 글자열 검사는 repo-office 엔진의 `run_test`(sandbox 켬)로 따로 돌려, 통과하는 경우와 `tr()` 없는 글자열을 잡는 경우를 확인했습니다.

| 값 | 이유 |
| --- | --- |
| `GODOT=…/Godot` | `make godot-install`은 네트워크가 `github.com`뿐인 sandbox에서 받기 어렵습니다. 미리 설치한 4.7.2를 씁니다. `scripts/godot.env`의 버전과 다르면 검사가 실패합니다. |

## 알아둘 것

- 브랜치 이름 검사는 `office/…`를 면제합니다([브랜치·커밋 규칙](../GIT_CONVENTIONS.md)). 사람이 PR을 열 때 이름을 바꿀 필요는 없습니다.
- `.claude/settings.json`은 office가 `--setting-sources project`로 읽지 않습니다. 이 저장소의 거부 규칙은 office 작업자에게 적용되지 않고, office 단계표의 거부 목록이 대신합니다.
- 작업자는 `make check`를 `engine.py test <과제>`로만 돌립니다. `GODOT` 같은 환경은 `task.json`의 `test`에 이미 들어 있습니다.
- 이 저장소의 훅(`core.hooksPath=.githooks`)은 작업자 sandbox에서 `commit`·`push` 때 도는지 확인하지 않았습니다.
