# 능력치 개편 뒤의 재현 가능한 밸런스 관찰

#205의 결정 입력이다. 수치·승률 목표·통과 기준을 정하지 않는다. 이 research 브랜치는 병합하지 않는다.

기존 `research/278-balance-stats`의 두 정책·집계기를 재사용했다. 이후 실행 검수에서 보완한 이동 후조건(방문 경로 prefix·비용·잠금 해제)과 입력점이 있는 이동 후보 제한을 유지한다. 원본 하네스는 2026-10-24 이동 검수 백업의 `autoplay.gd`이며 게임 코드는 변경하지 않는다.

## 실행

Godot 공식 4.7.2와 import가 된 checkout에서 실행한다. 출력은 checkout 밖의 새 폴더를 지정한다.

```sh
python3 ~/.agents/tools/agent_workflow.py check -- python3 -m unittest discover -s research/339-ability-balance -p 'test_*.py'
python3 ~/.agents/tools/agent_workflow.py check -- python3 research/339-ability-balance/run.py \
  --output /path/to/new-balance-samples --godot /Applications/Godot.app/Contents/MacOS/Godot
```

기본은 정책별 seed 1~30이다. `--count 1`은 재현 점검용이다. 각 실행은 임시 HOME/XDG와 headless·고정 60fps를 사용하며 네 개씩 실행한다. `inputs.json`에 전체 소스 SHA·로컬 변경과 입력 fingerprint·엔진·seed·난수 배정식을 남긴다. 각 실행의 로그·CSV·`run.json`과 전체 표 `tables.md`를 보존한다. 실패하면 출력 폴더를 유지하고 새 폴더에서 재시도한다.

## 난수와 정책

검수 전용 `SeededDice`와 `SeededTurns`를 장면이 시작되기 전에 주입한다. 제품의 전투 주사위와 이니셔티브 주사위는 서로 다른 RNG이므로 두 경로를 모두 고정한다. 전투 진입 때마다 `run * 100000 + 진입 순번(0부터)`, 이니셔티브는 여기에 50000을 더한다. 주사위 굴림·유닛 값·순서 계산·맵·HP·장비·드랍률은 제품 구현을 사용한다. 제품의 일반 실행에는 seed 옵션을 추가하지 않는다.

- mother: 어미 거미 → 궁수의 표식 대상 → 낮은 HP 순. 전사는 어미 거미 쪽으로 이동한다.
- nearest: 공격 가능한 가까운 적, 동률이면 낮은 HP 순.
- 공통: HP 50% 미만 숨 고르기, 40% 미만 물약, 기존 궁수 스킬 조건과 전사 몰아치기, 반응 항상 승인. 장비는 기존 점수 정책을 사용한다.

## 해석 경계

60라운드·전투별 재시도 10회는 하네스 상한이며 도달하면 미완주로 남긴다. 졸업과 상한만 통계에 넣는다. 크래시·입력 실패·버튼 fallback·이동 후조건 실패는 실행 결함으로 거부한다. 원래 #278과 달리 입력점 탐색이 가능한 이동 후보로 제한한 정책 변형이다. 두 정책의 같은 seed 번호는 같은 초기 RNG 배정을 뜻하지만 행동과 소비 순서가 달라 동일 굴림을 같은 대상에게 보장하지 않는다.

사람의 실력·체감·실제 창·음향·저장 복원 검증이 아니다. 점프·밀치기·환경 오브젝트 활용은 정책에 없다. 기존 d20 통계와 수치만 직접 비교해 개편의 인과효과로 해석하지 않는다. 공급원·배치와 밸런스 결정 대기는 유지한다.

다중 seed 사전 실행에서 seed6·11의 사망 중단을 실패로 기록했다. 원인은 이동이 해제된 뒤 한 프레임을 더 기다리며 다음 적 AI의 새 busy 상태를 읽은 하네스 경쟁이었다. `_settle()`은 관측한 해제 시점에 즉시 돌아오도록 고쳤고 같은 두 seed에서 전체 진행과 모든 이동 후조건이 통과했다. 실패 기록은 버리지 않고 최종 표본과 구분해 보존한다.
