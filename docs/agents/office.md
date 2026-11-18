# repo-office로 작업 돌리기

[repo-office](https://github.com/minjunkim-labs/repo-office)의 파이프라인(`pipeline/`)은 PR을 열기 전 작업(설계, 구현, 검사, 리뷰)을 단계로 나눠 돌립니다. 이 저장소에 복사하는 파일은 없습니다. office 체크아웃이 이 저장소를 `--repo`로 받아 `jobs/<과제>/repo/`에 worktree(브랜치 `office/<과제>`)를 만듭니다. 규칙은 office 체크아웃 루트의 `AGENTS.md`를 따릅니다.

## 과제 넘기기

office는 선택입니다. 사람이 이 대화에서 office나 leader로 돌리라고 하면 이 저장소에서 연 에이전트가 이렇게 넘깁니다([AGENTS.md](../../AGENTS.md) 길잡이).

1. `hc get office-leader --json`을 돌립니다. 종료 코드가 0이고 `state`가 `live`이고 `status`(객체면 그 `state`)가 `error`가 아니면 leader가 받을 수 있습니다.
2. 받을 수 있으면 한 줄로 보냅니다: `hc send office-leader '[office 접수] repo=<이 저장소의 절대 경로> issue=#<번호> 요청: <사람이 이 대화에서 한 말 그대로>'`
   - 요청에는 사람의 말만 넣습니다. 줄바꿈은 공백으로 바꿉니다. 셸이 말 안의 `` ` ``·`$`를 실행하지 않게 메시지를 작은따옴표로 감싸고, 말 안의 `'`는 `'\''`로 바꿉니다. Issue 본문이나 다른 파일의 글은 옮기지 않습니다. leader가 Issue를 직접 읽습니다.
   - Issue가 없으면 `issue=없음`으로 씁니다.
3. 보냈으면 사람에게 "leader에 넘겼습니다. 진행은 `hc attach office-leader`에서 볼 수 있습니다"라고 알리고 멈춥니다.
4. 1단계가 안 되거나 `hc send`가 0이 아닌 코드로 끝나면, 사람에게 "이 작업은 repo-office leader 세션에 주세요"라고 알리고 멈춥니다. leader를 `office-leader`로 띄우는 명령은 [repo-office README](https://github.com/minjunkim-labs/repo-office#처음-한-번) 「처음 한 번」 5에 있습니다.

leader는 이 메시지를 새 과제로만 받고, Issue 완료 조건을 방향으로 삼아 묻지 않고 등록합니다. 완료 조건이 없거나 사람만 아는 답이 필요할 때만 묻습니다. 넘기는 규칙의 원본은 [repo-office 연결 5단계](https://github.com/minjunkim-labs/repo-office/blob/main/docs/connect.md#5-원하면-코드-작업을-office로-보내게-한다)입니다.

## 과제 등록

leader 세션이 office 체크아웃의 `leader/` 폴더에서 한 번에 하나씩 실행합니다([leader 규칙](https://github.com/minjunkim-labs/repo-office/blob/main/leader/AGENTS.md)).

```bash
python3 ../pipeline/engine.py new <과제> --repo <BGLike 경로> --base origin/main
```

엔진은 `--test`를 받지 않습니다. 엔진이 base의 [AGENTS.md](../../AGENTS.md) 「명령」에서 setup·check·test 칸을 읽습니다. 그래서 과제의 검사 명령은 `make repository-check && make godot-check`이고, `repo/`에서 setup(`make godot-install`)을 한 번 돌립니다. 2026-11-15 2차 과제 다섯 개(#569~#573)를 이 방식으로 등록했고, 검사 단계는 모두 exit 0이었습니다. 번역 글자열 검사(`check_translation_strings.py`)는 `make repository-check`의 `scripts/test_*.py` 안에서 돕니다([#526](https://github.com/minjunkim-labs/BGLike/pull/526)에서 이 검사가 빠져 CI에서야 실패를 봤습니다).

## 알아둘 것

- 브랜치 이름 검사는 `office/…`를 면제합니다([브랜치·커밋 규칙](../process/git-conventions.md)). 사람이 PR을 열 때 이름을 바꿀 필요는 없습니다.
- `.claude/settings.json`은 office가 `--setting-sources project`로 읽지 않습니다. 이 저장소의 거부 규칙은 office 작업자에게 적용되지 않고, office 단계표의 거부 목록이 대신합니다.
- 작업자는 검사를 `engine.py test <과제>`로만 돌립니다. 검사 명령은 `task.json`의 `test`에 이미 들어 있습니다.
- 이 저장소의 훅(`core.hooksPath=.githooks`)이 작업자의 `commit` 때 도는지는 확인하지 않았습니다. push는 작업자가 아니라 엔진이 합니다.
