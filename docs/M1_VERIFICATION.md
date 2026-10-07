# M1 전체 검수 기록

Issue #12의 7단계 자료입니다. 규칙은 [전투 기획서](COMBAT_DESIGN.md), 완료 기준은 [개발 요청서 5장](DEV_REQUEST_M1.md#5-기획-검수-기준)을 따릅니다. 이 문서는 규칙이나 수치를 바꾸지 않습니다.

## 기준과 상태

- 최초 게임 기준: PR #36 병합 커밋 `85e63b5c55f6aa19f6c7769bb7c9ab8407786b8e` (2026-10-04).
- 이번 후속 작업은 최신 main `6c708bb5b5676e961f578b59599e68c3cf7afb92`에서 시작했다. PR #46의 자기 턴 반응 결정과 PR #47의 궁수 수치를 검사에 반영한다.
- 1~6단계 구현이 main에 있습니다. 아래 표는 검수 기준 28개와 기존 자동 검사의 연결을 기록합니다.
- 자동 검사는 자원·판정·장면 입력·UI 상태를 확인합니다. 화면의 실제 가독성과 사람의 조작감은 확인하지 않습니다.
- 개발자 직접 플레이와 2026-10-11 기획 검수는 미완료입니다. 원본 개발 요청서의 체크박스를 자동 검사 결과만으로 채우지 않습니다. Issue #12도 열어 둡니다.

## 자동 검사 실행

저장소 루트에서 [README의 검사 명령](../README.md#시작)을 실행합니다. Godot은 4.7.2 Standard를 사용합니다. 다섯 스크립트는 모두 headless로 실행할 수 있으며 실패하면 0이 아닌 종료 코드를 반환합니다. `--import`를 먼저 실행해 새 체크아웃의 전역 클래스와 리소스를 등록합니다.

| 검사 | 확인 수 | 범위 |
|---|---:|---|
| `combat_turns_test.gd` | 2366 | 이니셔티브, 턴 묶음, 자원, 라운드와 탈락 |
| `combat_checks_test.gd` | 59 | 명중, 유리/불리, 내성, 대결, 확률과 미리보기 |
| `combat_actions_test.gd` | 176 | 이동, 공격, 스킬, 공용 동작, 반응과 두 번 클릭 입력 |
| `combat_hud_test.gd` | 267 | 자원 기호, 비용·횟수 배지, 좌·우클릭과 초상 정보, 로그·팝업과 결과 |
| `combat_ai_test.gd` | 67 | 적 우선순위, 자동 반응, 아군 반응 대기와 전체 전투 |

검사 수 합계는 2935입니다. 이는 검수 기준 28개의 수와 다릅니다. 각 스크립트는 여러 경계 조건과 조합도 확인합니다. Python 관리 검사 51개, `git diff --check`, import와 메인 장면 실행도 별도로 확인합니다. 검사를 바꾸면 이 표와 실행 증거를 함께 갱신합니다.

2026-10-04 실행 증거:

- 병합된 게임 기준의 로컬 Godot 4.7.2 import, 메인 장면과 기존 2832개 검사 통과. Python 50개도 통과했습니다.
- 병합된 main의 [Godot CI 실행 37210424407](https://github.com/minjunkim-dev/BGLike/actions/runs/37210424407)이 기준 커밋 `85e63b5`에서 기존 2832개 검사와 Python 50개에 성공했습니다.
- 7단계에서 아군의 몰아치기 후 추가 공격을 실제 장면 클릭으로 확인하는 검사 2개를 보완했습니다. 로컬 동작 검사는 105개에 성공했습니다. 나머지 검사와 합한 로컬 확인 수는 2834개입니다. 이 변경의 CI 결과는 관련 PR에 기록합니다.
- [PR #36 검증·리뷰 기록](https://github.com/minjunkim-dev/BGLike/pull/36)과 실행 결과는 소스·자동 검사 증거입니다. 직접 플레이 증거는 아직 없습니다.

2026-10-07 후속 실행 증거:

- `GODOT=/Applications/Godot.app/Contents/MacOS/Godot make check`를 실행했다. Godot `4.7.2.stable.official.ed1daf0bf`의 import, 메인 장면 실행, 회귀 검사 2905개와 Python 검사 51개가 통과했다. `git diff --check`도 통과했다. 이 기록은 이번 PR의 로컬 변경에 대한 실행 결과다.
- A `_test_own_turn_parry`는 실제 장면에서 자기 턴 이동 중 기회 공격을 받는다. 흘려내기 성공·실패·넘기기, 확인 창, 입력 잠금, 피해, 반응·횟수 소비와 이동 재개를 확인한다. 아군 선택 전환과 적 턴은 반응을 회복하지 않는다. 다음 자기 턴 시작에는 반응만 회복한다.
- A `_test_archer_balance`는 아군과 적 궁수의 HP14, 기본 피해 고정값1, 일반·치명타·표식의 피해와 로그를 확인한다. 민첩+3, 공격 보너스+5와 DC13은 유지한다. 기존 충격 화살 피해 검사와 실제 HP 미리보기 검사도 새 수치에 맞췄다.
- GitHub CI 결과는 이번 PR에 별도로 기록한다. 실제 장면 검사는 자동 입력이다. 개발자 직접 플레이와 기획 검수는 미완료다.

2026-10-07 입력·초상 후속 검사:

- [Issue #12의 승인된 입력 변경](https://github.com/minjunkim-dev/BGLike/issues/12#issuecomment-6039883383)을 반영했다. 로컬 `make check`에서 Godot 회귀 검사 2935개와 Python 검사 51개가 통과했다. import, 메인 장면 실행과 `git diff --check`도 통과했다.
- H `_test_mouse_controls_and_inspection`은 빈 칸 좌클릭의 이동 금지, 첫 우클릭 범위·경로, 다른 칸 미리보기 변경, 같은 칸 우클릭 확정과 이동력 소비를 실제 입력으로 확인한다. 필드의 적 좌클릭 미리보기·공격과 초상 클릭의 정보 조회를 구분한다.
- 같은 검사는 적 초상 반복 클릭, 조작 가능한 아군 전환, 턴 완료·기절 아군과 적 턴의 정보 조회, 실제 능력치·자원 표시, UI 갱신의 조회 유지, 반응 대기 잠금을 확인한다. T `_test_scene`의 턴 완료 초상 기준도 정보 조회와 조작 전환 거부로 갱신했다.
- 첫 Linux CI에서 글꼴 높이 차이로 정보와 공격 예측이 겹치는 문제를 찾았다. 세로 컨테이너가 정보 패널의 실제 최소 높이에 맞춰 공격 예측을 배치하도록 고쳤다. H `_test_layout`은 창 크기별 겹침과 늘어난 줄 높이도 확인한다.
- 별도 복사본의 실제 Metal/Forward+ 렌더링에서 동작 검사 176개와 화면·입력 검사 322개를 통과했다. 아군 자동 입력 12턴, 반응 선택 4회, 전투 결과와 재시작을 확인했다. PNG 15개를 직접 관찰했다. 테스트 앱 전경 전환과 창 포커스 획득은 0회였다. 원본 편집기와 실행 게임을 조작하지 않았다. 이 기록은 자동 입력·에이전트 화면 관찰이며 사람의 조작감이나 기획 수용 판단은 포함하지 않는다.

### 검수 기준과 검사 위치

아래의 `T`, `C`, `A`, `H`, `E`는 각각 [턴](../tests/combat_turns_test.gd), [판정](../tests/combat_checks_test.gd), [동작](../tests/combat_actions_test.gd), [HUD](../tests/combat_hud_test.gd), [AI](../tests/combat_ai_test.gd) 스크립트입니다. 함수명은 확인 경로이며, 사람이 직접 플레이했다는 증거가 아닙니다. 입력 검사는 장면에 이벤트를 보내거나 연결된 신호를 사용합니다.

| 번호 | 개발 요청서 5장 기준 | 자동 검사 위치 |
|---|---|---|
| T1 | 나눈 이동, 행동 1회, 보조 행동 1회 | A `_test_movement`, `_test_attacks`, `_test_self_actions`; T `_test_resources_and_groups` |
| T2 | 할 일이 없으면 종료 버튼 강조, 수동 종료 | H `_test_resources`; T `_test_available_actions`, `_test_scene` |
| T3 | 소비 자원의 ● ▲ ◆가 ○ △ ◇로 변경 | H `_test_resources` |
| T4 | 연속 아군 초상으로 조작 순서 전환 | T `_test_resources_and_groups`; H `_test_order_bar_input` |
| R1 | 전사 옆에서 벗어나는 적의 기회 공격 창 | A `_test_reactions`; H `_test_reaction_flow`; E `_test_reaction_pause` |
| R2 | 궁수 옆에서는 기회 공격 없음 | A `_test_reactions` |
| R3 | 자기 턴 포함 흘려내기 창, DC13·45%, 피해·추가 효과 무효 | A `_test_reactions`, `_test_own_turn_parry`, `_test_scene_input` |
| R4 | 기회 공격과 흘려내기의 반응 공유 | A `_test_reactions` |
| R5 | 물러서며 쏘기 후 기회 공격 없음 | A `_test_reactions`; E `_test_archer` |
| C1 | 인접 적이 있는 궁수는 불리, 로그에 두 주사위 | C `_test_preview_conditions`; H `_test_log_and_status` |
| C2 | 기절 대상 공격은 유리 | C `_test_preview_conditions`; H `_test_log_and_status` |
| C3 | 명중률 미리보기의 유리/불리 반영 | C `_test_probabilities`, `_test_preview_conditions`, `_test_scene_input` |
| C4 | 적 첫 좌클릭의 공격 미리보기와 적 정보, 초상 정보 조회 | C `_test_scene_input`; H `_test_archer_and_enemy`, `_test_mouse_controls_and_inspection` |
| S1 | 현재 유닛 스킬의 자원별 분리, 궁수 반응 숨김 | H `_test_warrior`, `_test_archer_and_enemy` |
| S2 | 비용 기호와 모서리 횟수 배지 | H `_test_warrior`, `_test_layout` |
| S3 | 적 턴의 적 정보와 회색 스킬 패널 | H `_test_archer_and_enemy` |
| S4 | 스킬 6개의 효과·횟수·자원과 비활성화 | A `_test_self_actions`, `_test_mark_and_stun`, `_test_reactions`; H `_test_warrior`, `_test_resources`, `_test_archer_and_enemy` |
| S5 | 충격 화살의 정신 DC13 실패 시 다음 턴 건너뜀 | A `_test_mark_and_stun` |
| S6 | 충격 화살 빗나감도 자원·횟수 소비, 피해·기절 없음 | A `_test_mark_and_stun`, `_test_scene_shock` |
| S7 | 표식의 추가 피해 로그 | A `_test_mark_and_stun`; H `_test_log_and_status` |
| S8 | 몰아치기 후 행동 기호 회복과 추가 공격 | A `_test_self_actions`, `_test_scene_input`; H `_test_resources`; E `_test_warrior` |
| S9 | 행동이 남으면 몰아치기 비활성화 | A `_test_self_actions`; H `_test_warrior` |
| G1 | 밀치기 승리 시 1칸, 막힌 도착 칸은 거부 | A `_test_shove`; C `_test_saves_and_contests` |
| G2 | 물약 회복, 유닛당 1회 | A `_test_self_actions` |
| E1 | 인접 위협이 있는 적 궁수 후퇴 | E `_test_archer` |
| E2 | HP 절반 이하 적 전사 회복 후 몰아치기 미사용 | E `_test_warrior` |
| E3 | 적 기회 공격과 흘려내기 자동 사용 | E `_test_enemy_reactions`; A `_test_reactions` |
| F1 | 처음부터 결과 화면까지 전투 진행 | E `_test_default_scene`, `_test_scene`; H `_test_results_and_restart` |

고정된 주사위와 경계 조건을 쓰므로 빗나감, 내성 실패와 성공을 우연히 기다릴 필요가 없습니다. 기본 10×10 고정 배치의 전체 전투는 실제 장면의 프레임 실행과 AI를 켜고 진행합니다. 그 검사는 아군 조작을 자동으로 수행하며 사람이 플레이한 결과와 구분합니다.

## 직접 플레이 기록

개발자와 기획 담당의 결과를 별도로 기록합니다. 개발자는 먼저 아래 흐름을 확인하고, 기획 담당은 2026-10-11에 개발 요청서 5장의 기준 전체를 검수합니다. 자동 검사 항목을 사용자에게 하나씩 반복 실행하도록 요구하지 않습니다. 실제 플레이 중 나온 문제는 관련 기준 번호와 함께 기록하고, 검수에서 보지 못한 기준은 미확인으로 남깁니다.

1. **선택과 이동**: F5로 시작하고 칸을 우클릭합니다. 첫 우클릭의 이동 범위·경로와 같은 칸의 두 번째 우클릭 확정을 확인합니다. 이동 후 공격 안내를 읽을 수 있는지 봅니다. 아군·적 초상으로 정보를 조회합니다. 조작 가능한 아군 초상은 기존 조작 전환도 유지합니다.
2. **동작 선택**: 사거리에 들어간 뒤 공격과 사용할 수 있는 스킬을 고릅니다. 효과, 비용, 횟수, 사용할 수 없는 이유를 구분할 수 있는지 봅니다. 긴 설명을 휠로 읽습니다.
3. **반응과 적 턴**: 기회 공격 또는 흘려내기 창이 뜨면 사용이나 넘기기를 고릅니다. 질문을 이해할 수 있는지, 선택 후 전투가 이어지는지, 적 행동 순서와 속도를 따라갈 수 있는지 봅니다.
4. **판정과 상태**: 발생한 판정의 로그·숫자 팝업, HP·기절·표식을 읽습니다. 주사위 결과가 원하는 형태로 나오지 않으면 자동 검사 근거를 유지하고 그 상황의 직접 확인은 보류합니다.
5. **결과와 재시작**: 승리 또는 패배까지 진행하고 재시작을 누릅니다. 새 전투로 돌아오는지 확인합니다. 걸린 시간과 이해하기 어려웠던 화면을 기록합니다.

이 흐름은 전체 검수 기준을 대체하지 않습니다. 한 전투에서 나오지 않은 규칙은 개발 요청서 기준 번호별로 미확인 상태를 유지합니다. 기획 담당은 필요하면 추가 전투에서 그 상황을 만듭니다. 별도 디버그 조작이나 게임 수치 변경은 추가하지 않습니다.

| 기록 | 현재 상태 | 남길 증거 |
|---|---|---|
| 개발자 직접 플레이 | 미완료 | 날짜, 실행 커밋, 확인한 기준 번호, 미확인 번호와 문제 |
| 기획 검수 | 2026-10-11 예정, 미완료 | 기준 28개의 판정, 유지·변경 결정, 관련 Issue 코멘트 |
| M1 종료 | 보류 | 개발자 확인과 기획 검수 후 최종 PR에서 `Closes #12` |

기록 양식:

```text
역할: 개발자 / 기획
날짜와 실행 커밋:
확인한 기준 번호:
미확인 기준 번호:
플레이 시간:
문제: 발생 입력 → 보인 결과 → 기대 결과
유지·변경 결정: (기획 검수 시)
```
