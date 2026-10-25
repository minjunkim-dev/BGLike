# 새 장애물 배치 기준 정책별 seed 30회 관찰

#205의 결정 입력이다. 제품 기준은 main `7d533b636e7db0bd39ac5e82463611ab7921d15e`이다. 밸런스 수치·거미 증식 규칙·승률 목표·통과 기준은 바꾸거나 정하지 않는다. 이 research 브랜치는 원자료 보존용이며 제품 main에 병합하지 않는다.

기존 연구 커밋 `6c1c4667abbf31423f67f785e96327497a58d113`의 정책·집계·이동 후조건을 재사용했다. 새 전투 준비 단계의 ‘전투 시작’ 입력, 실행 시간 상한, 애니메이션 프레임이 바뀌어도 유지되는 몸통 클릭점 선택을 보완했다. 정책과 전투의 60라운드·10회 재시도 상한은 그대로다.

## 실행

공식 Godot 4.7.2와 import가 완료된 제품 소스 checkout에서 이 연구 스크립트를 사용한다. 출력은 checkout 밖 새 폴더여야 한다.

```sh
python3 ~/.agents/tools/agent_workflow.py check -- /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script research/339-ability-balance/test_click_point.gd
python3 ~/.agents/tools/agent_workflow.py check -- python3 -m unittest discover -s research/339-ability-balance -p 'test_*.py'
python3 ~/.agents/tools/agent_workflow.py check -- python3 research/339-ability-balance/run.py \
  --output /path/to/new-samples --godot /Applications/Godot.app/Contents/MacOS/Godot
```

기본은 정책별 seed1~30, 4개 동시 실행, 최종 실행당 wall timeout1200초다. `--count 1`은 pilot이며 최종60회에 포함하지 않았다. 임시 HOME/XDG·headless·고정60fps를 사용했다. 입력 지문·엔진·소스 SHA·RNG 배정식·각 실행 JSON/CSV/로그를 보존했다.

최초 실행의 nearest seed25는240초 제한에 도달했고,1200초로 재실행하자 몸통 클릭 실패1건이 검출됐다. 진단에서 같은 점이 클릭 전에는 idle 프레임1의 거미 몸통이지만 클릭 후에는 어떤 몸통에도 포함되지 않았다. GUI·자원·HP·선택 대상 변경은 원인이 아니었다. 하네스의 `_stable_body_point`가 현재 애니메이션의 모든 프레임에 남아 있는 픽셀을 고르도록 고쳤다. 제품의 픽셀 판정·애니메이션·게임 규칙은 그대로다.

회귀 검사 `test_click_point.gd`에서 기존 선택은 불안정 픽셀4개를 허용해실패했고, 수정 후4개를모두배제하며안정픽셀77개를유지했다. 교정된 동일 하네스로 두 정책60개 전체를 `evidence/samples-v2/`에 새로 실행했다. **최초59개와 교정seed25를 섞어 최종표를 만들지 않았다.**

`evidence/samples/`, `retry25/`, `diagnostic25/`, `diagnostic2/`, `corrected25/`는 최초·실패·진단·중단 이력이며 최종통계에서제외한다. `final/`은 이전 시도에서 검증실패로 중단된 미완성집계여서제외한다. `initial-source/`와 진단GDScript·실행어댑터를 보존했다. 로컬 절대경로는 실행당시근거이며 다른 머신에서는 checkout/출력경로를 바꿔야 한다.

## 난수와 정책

전투·이니셔티브 두 RNG를 검수 전용으로 고정한다. 진입별 전투 seed는 `run * 100000 + 진입 순번(0부터)`, 이니셔티브는 여기에50000을 더한다. 주사위 굴림·유닛 값·맵·HP·장비·드랍률은 제품 구현이다. 같은 seed 번호라도 정책별 행동과 소비 순서는 달라질 수 있다.

- mother: 어미 거미 → 궁수 표식 대상 → 낮은 HP 순. 전사는 어미 쪽으로 이동한다.
- nearest: 공격 가능한 가까운 적, 동률이면 낮은 HP 순.
- 공통: HP50% 미만 숨 고르기,40% 미만 물약, 기존 궁수 스킬 조건·전사 몰아치기, 반응 항상 승인, 기존 장비 점수 정책.
- 화면 입력점 탐색이 가능한 이동 후보로 제한한 기존 정책 변형이다. 점프·밀치기·상자/바위 활용은 포함하지 않는다.

## 해석 경계

졸업과 분류된 하네스 상한만 통계에 넣는다. 크래시·입력 실패·버튼 fallback·이동 후조건 실패·wall timeout은 유효 표본으로 취급하지 않는다. 라운드61 기록은60라운드 상한 검사 시점의 표시이며 자연 종료 전투 길이가 아니다.

과거 측정 이후 main에는 장애물 배치 외에도 전투 준비·혼합 광역 유리 조건·UI 수정 등이 포함돼 있다. 전후 차이를 장애물만의 인과효과로 단정할 수 없다. 준비 버튼 입력에 따른 시뮬레이션 시간도 추가된다. wall 시간은 기기/동시 실행 부하에 영향을 받는다.

자동 정책 결과는 사람의 승률·실제 체감 시간·재미·청취·기획 검수 완료가 아니다. Mac 실제 입력 검수는 별도의 통제 fixture로 수행했고 `evidence/native/README.md`에 범위를 구분했다. 목표 승률·전투 길이·증식 유지/변경은 #205의 답 대기로 남긴다.
