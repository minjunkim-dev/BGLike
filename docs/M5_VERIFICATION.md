# M5 몬스터·9개 스테이지 통합 검수

기준은 [Issue #113](https://github.com/minjunkim-dev/BGLike/issues/113), [Issue #102 구현 명세](https://github.com/minjunkim-dev/BGLike/issues/102#issuecomment-6186728162)와 [D0 후속 결정](https://github.com/minjunkim-dev/BGLike/issues/102#issuecomment-6187007478)입니다.
2026-10-15 main `d1d6d25306163b92a2d502faf46c4e8e21265412`에서 소스·기획·기존 검사를 대조했습니다.
이 문서는 구현 감사와 자동 검사 범위를 기록한 초안입니다. 직접 플레이 결과는 아직 반영하지 않았습니다. #113과 #102의 전체 합격을 선언하지 않습니다.

## 구현 감사

`scenes/combat/battle.tscn`은 `stages/act1_stage1.tres`부터 `act3_stage3.tres`까지9개 데이터를 순서대로 사용합니다. 각 데이터는 해당 적 배치 장면을 연결합니다. 적 종류·수·좌표는 [확정 배치표](stages/README.md#3-2-스테이지별-좌표-)와 일치합니다.

- 모든 스테이지의 맵은10×10 뾰족한 위 헥사입니다. 전사는 (1, 4), 궁수는 (0, 5)에서 오른쪽을 보고 시작합니다.
- 몬스터7종은 `enemy_definitions.gd`의 고정 수치를 사용합니다. 막별 적 강화는 없습니다. 아군 수치와 스킬은 유지합니다.
- 처음 배치한 새끼는 각각 이니셔티브를 굴립니다. 생성한 새끼는 엄마 직전에 생성 순서대로 들어갑니다. 생성 라운드에는 행동하지 않습니다. 엄마가 전투 불능이어도 새끼는 남습니다. 남은 새끼까지 처치해야 승리합니다.
- 처음 배치한 새끼와 생성한 새끼는 추가 드랍에서 제외합니다. 승리 보장 아이템1개는 유지합니다. 엄마와 보스는 일반 몬스터와 같은35%를 사용합니다. 1-1은 보장1개뿐입니다. 3-1은 엄마2마리분만 추가 추첨합니다.
- 장비의 막별 범위, 추첨 비중2/2/3과 물약 한도3을 유지합니다. 보상·정비·막 재시작·다음 막·3막 졸업 연결을 유지합니다.
- 세 보스는 기절 면역과 과부하를 사용합니다. 2000·3000은 만능팔을 사용합니다. 3000은 회전회오리와 확정 연계를 사용합니다. 과부하 자기 피해로 HP0이 되면 즉시 전투 불능입니다. 다른 적이 없으면 승리합니다. 이 정책은 사용자와 D0 결정의 확정값입니다.

아래 값은 막과 관계없이 같습니다. 세부 능력치와 스킬은 [몬스터별 문서](monsters/README.md#6-몬스터-목록)를 따릅니다.

| 몬스터 | HP / AC | 이동력 | 명중 / 피해 / 사거리 / 내성 DC |
|---|---|---|---|
| 풋내기 야만인 | 12 / 12 | 6 | +5 / 1d4+1 / 1 / 11 |
| 풋내기 궁수 | 14 / 11 | 6 | +5 / 1d4+1 / 1~6 / 11 |
| 새끼 거미 | 1 / 6 | 6 | +4 / 고정1 / 1 / 10 |
| 엄마 거미 | 20 / 13 | 4 | +4 / 1d6+2 / 1 / 12 |
| 고철로봇-1000 | 40 / 14 | 4 | +5 / 1d8+2 / 1 / 13 |
| 고철로봇-2000 | 45 / 15 | 4 | +5 / 1d8+2 / 1 / 13 |
| 고철로봇-3000 | 50 / 16 | 4 | +5 / 1d8+2 / 1 / 13 |

## 자동 검사 경계

기존 전투 통합 검사와 `ScriptedDice`를 재사용합니다. 아래 함수는 해당 검사 파일의 진입점입니다. 소스 감사만으로 검사 실행 성공을 대신하지 않습니다. 최종 head·명령·검사 수·로그와 필수 CI는 PR의 Evidence와 작성자 인계 자료에서 확인합니다.

| 확인 항목 | 기존 검사와 연결 |
|---|---|
| 7종의 세 막 고정 수치·피해·동작 | `tests/combat_actions_test.gd`: `_test_novice_stats`, `_test_spiderling_stats_and_damage`, `_test_mother_stats_and_damage`, `_test_scrap_robot_stats`, `_test_scrap_robot_2000_stats`, `_test_scrap_robot_3000_stats` |
| 9개 실제 배치·10×10·아군 시작 좌표·방향 | `tests/combat_progression_test.gd`: `_test_spiderling_placement_and_turns`, `_test_novice_placements`, `_test_mother_stages`, 세 `_test_scrap_robot*_stage` |
| 생성 우선·기절·빈 칸 없음·복귀·보스 연계 | `tests/combat_ai_test.gd`와 `tests/combat_actions_test.gd` |
| 생성 라운드 대기·다음 라운드 순서·엄마 전투 불능 뒤 새끼 유지 | `tests/combat_turns_test.gd`: `_test_spawned_turn_insertion`; progression의 `_test_mother_stages` |
| 새끼 잔존 중 승리 금지·1-1 보장1개·3-1 엄마2마리분 추가 드랍 | loot의 `_test_spiderling_rewards`; progression의 `_test_mother_stages` |
| 세 보스 실제 승리 연결의35% 경계 | `tests/combat_loot_test.gd`: `_test_boss_reward_boundary` |
| 장비 범위·추첨 비중·장착·물약·보상·정비 | loot의 `_test_act_values`, `_test_reward_flow`, `_test_scaled_combat`, `_test_accidental_advance` |
| 막 재시작·같은 막 자원 유지·다음 막·졸업 | progression의 `_test_stage_transition`, `_test_act_and_defeat`, `_test_graduation`, 세 보스 stage 검사 |
| 초상 누적 뒤 스크롤·선택, 기존 전투 입력·반응·연출 | `tests/combat_hud_test.gd` |

#113에서 추가한 회귀는 실제1-3·2-3·3-3 승리를 사용합니다. `CombatLoot`의 검사 전용 adapter는 주사위 인자만 `ScriptedDice`로 바꿉니다. 실제 승리 신호·추가 드랍 대상 수·`roll_rewards` 계산을 유지합니다. 아이템 풀은 검사 물약1종으로 제한합니다. 제품의 추가 확률35%는 바꾸지 않습니다. 각 보스에서0.349는 성공하고0.35는 실패합니다. 보장1개와 보스1마리분의 추가 판정만 소비했는지도 확인합니다.

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot make check
```

이 명령은 공백·규칙 파일·Python 검사와 Godot import·메인 장면·7개 전투 검사 파일을 실행합니다. Godot 종료 코드와 함께 `SCRIPT ERROR`, `Failed to load script`, 오류·경고 로그를 확인합니다. 자동 입력·검사 fixture·렌더링은 사람의 직접 플레이나 조작감·가독성 검수가 아닙니다.

## 직접 플레이 기록 — 미확인

작성자는 이 초안에서9개 스테이지를 직접 조작하지 않았습니다. root의 별도 편집기·CUA 관측 결과를 받은 뒤 아래 표를 갱신합니다. 별도 stage 진입과 첫 이니셔티브 고정, 정상 HP 전투, HP0 경계 fixture, 정상9연속 승리를 구분해서 기록합니다.

| 스테이지 | 배치·방향·AI·동작·화면 직접 확인 | 승리·보상·정비 또는 진행 확인 |
|---|---|---|
| 1-1 | 미확인 | 미확인 |
| 1-2 | 미확인 | 미확인 |
| 1-3 | 미확인 | 미확인 |
| 2-1 | 미확인 | 미확인 |
| 2-2 | 미확인 | 미확인 |
| 2-3 | 미확인 | 미확인 |
| 3-1 | 미확인 | 미확인 |
| 3-2 | 미확인 | 미확인 |
| 3-3 | 미확인 | 미확인 |

엄마 거미 전투의 생성 누적 수·최대 동시 생존 새끼 수는 직접 기록을 아직 반영하지 않았습니다. 자동 검사의 고정 유닛 수를 실제 플레이의 관측값으로 사용하지 않습니다. 직접 검수 결과를 반영하기 전에는 전체 완료로 표시하지 않습니다.

## 정리한 차이와 남은 범위

구현 전·시험 전투 반복·막별 적 강화 잔존이라는 설명을 현재 소스에 맞췄습니다. 과부하 HP0과 회전회오리의 옛 미정 표시를 확정 명세와 구현 상태로 바꿨습니다. M1의 전사·궁수 AI 설명과 과거 검수 수치·캡처는 과거 기록임을 표시했습니다.

막별 장비 수치 재검토와 새 배치의 드랍 기대값 재계산은 후속 기획입니다. 지형·장애물·아트·번역도 이번 범위 밖입니다. 새끼 수 상한이나 별도 성능 합격 수치를 정하지 않습니다. 공개 배포와 Draft CD는 수행하지 않습니다.
