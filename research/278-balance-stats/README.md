# #278 밸런스 재검토용 자동 플레이 통계 (버리는 research 브랜치)

결과와 해석은 [#278 해결 코멘트](https://github.com/minjunkim-dev/BGLike/issues/278)에 있다. 이 브랜치는 병합하지 않는다.

- 기준: `main` f809ff0. 제품 `scenes/main.tscn`을 그대로 띄운다. HP·배치·수치·스테이지 순서를 바꾸지 않는다.
- 주사위: 게임이 전투마다 하는 `randomize()`를 그대로 쓴다. 실행마다 독립이고 seed로 재현하지 않는다.
- 창: `--headless --fixed-fps 60`. 화면을 열지 않는다. 시간은 프레임/60 = Space 없이 1배속으로 기다리는 초.
- 입력: 포인터·숫자 키 이벤트(`Input.parse_input_event`). 버튼 직접 호출 대체는 0회.

## 다시 돌리기

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot sh research/278-balance-stats/run_all.sh "$PWD" /tmp/r278 50 10
python3 research/278-balance-stats/aggregate.py /tmp/r278 /tmp/r278-merged > tables.md
```

## 파일

- `autoplay278.gd`: 하네스와 두 정책(`--policy=nearest|mother`).
- `run_all.sh`: 정책별 N회 병렬 실행.
- `aggregate.py`: 실행별 CSV를 합치고 Markdown 표를 만든다.
- `tables.md`: 코멘트에 넣은 표.
- `data/attempts.csv`: 스테이지 시도 1회 = 1행 (결과, 라운드, HP, 물약, 보상, 새끼 생성, 적 턴 시간, 공격·빗나감).
- `data/streaks.csv`: 연속 빗나감 1회 = 1행 (쪽, 길이). 스테이지 시도 경계에서 끊는다.
- `data/enemy_segments.csv`: 적 턴 한 번(아군 차례 사이) = 1행 (초).
- `data/runs.csv`: 실행 1회 = 1행 (종료 이유, 하네스 상한, 포인터 대체·클릭 실패 수).
