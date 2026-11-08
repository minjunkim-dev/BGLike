# 외부 구성 요소와 자산의 권리 고지

자체 코드의 권리 방침은 [COPYRIGHT](COPYRIGHT.md)에 있습니다.
외부 구성 요소에는 해당 권리자의 라이선스가 적용됩니다. 이 문서가 그 조건을 변경하지 않습니다.

확인 기준: 2026-10-04의 추적 파일과 Git 기여 기록. 출시 패키지의 전체 고지를 완료했다는 뜻은 아닙니다.

## 엔진과 개발 도구

| 구성 요소 | 버전·용도 | 조건과 출처 |
| --- | --- | --- |
| Godot Engine | 4.7.2 Standard, 편집·검사·향후 게임 실행 | MIT. 엔진 바이너리를 저장소에 포함하지 않습니다. [엔진 LICENSE](https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt), [엔진의 외부 구성 요소](https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt), [고지 안내](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html) |
| Git LFS | 바이너리 원본 자산 관리 도구 | MIT. 도구 바이너리를 저장소에 포함하지 않습니다. [Git LFS LICENSE](https://github.com/git-lfs/git-lfs/blob/main/LICENSE.md) |

Godot의 MIT 조건은 BGLike 자체 코드에 MIT를 부여하는 의미가 아닙니다.
엔진과 엔진의 외부 라이브러리를 포함한 게임 배포물에는 원래 요구되는 고지를 포함합니다.

## 게임 규칙

전투 규칙은 SRD 5.1을 근거로 하며 게임에 맞게 수정해 사용합니다.
SRD 5.1은 CC-BY-4.0과 OGL 1.0a 중 하나를 고를 수 있습니다. BGLike는 CC-BY-4.0을 따르며, SRD 5.1 머리말의 Legal Information이 요구하는 표기를 그대로 옮깁니다.

> This work includes material taken from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.

버전 근거: [전투 기획서](docs/COMBAT_DESIGN.md)의 밀치기는 양쪽이 d20을 굴리는 대결입니다. SRD 5.1의 방식이며, SRD 5.2는 대상의 내성 굴림으로 바꿨습니다.
표기 원문: [SRD 5.1 CC PDF](https://media.dndbeyond.com/compendium-images/srd/5.1/SRD_CC_v5.1.pdf) 1쪽. 2026-10-21 확인.
게임 안 표기는 타이틀 화면의 `출처` 화면(`scenes/main.tscn`)에 있습니다. `tests/title_test.gd`가 위 인용문과 같은지 검사합니다. 이 문서와 Draft 배포 묶음의 이 파일은 저장소·배포물 고지입니다.

## 현재 추적된 이미지

| 파일 | 확인된 기여 기록·용도 | 권리 확인 기준 |
| --- | --- | --- |
| `scenes/combat/art/terrain/*.png`, `scenes/combat/art/props/*.png`, `scenes/combat/art/sources/terrain/*.png` | 2026-10-21 사용자 위임으로 내장 `image_gen`에서 독자 생성한 재질5종·오브젝트5종. 실제64px 도트와 원본10개·나무 첫 원본/투명도 교정 기록을 보존 | 정확한 프롬프트·원본·가공 규격은 `scenes/combat/art/sources/world_generation.json`, `normalize_terrain.py`와 [맵 제작 기준](docs/TERRAIN_MAPS.md)에 기록했습니다. 레퍼런스 게임 이미지를 입력·복제하지 않았습니다. 생성 도구의 별도 조건을 적용합니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/units/**/*.png`, `scenes/combat/art/sources/units/*.png` | 2026-10-21 사용자 요청으로 내장 `image_gen`에서 독자 생성한 유닛9종. 생성 기준 시안과 전체 상태·방향 시트를 보존. 런타임108프레임은 시트를 자르고 nearest-neighbor 축소·투명도 정규화 | 원본과 프롬프트·도구 모드는 `scenes/combat/art/sources/unit_generation.json`에 기록했습니다. 레퍼런스 게임 이미지를 입력·복제하지 않았습니다. 생성 도구의 별도 조건을 함께 적용합니다. 생성 결과에 대한 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/icons/skills/*.png`, `scenes/combat/art/sources/icons/draw_skill_icons.py` | 2026-10-27 [#384](https://github.com/minjunkim-dev/BGLike/issues/384)의 스킬 아이콘11종(2026-10-21 #225의 도형 아이콘을 대체). `draw_skill_icons.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물. 공격·물약은 아이템 검·물약과 같은 그림 | 아이콘별 설명과 규격은 `scenes/combat/art/sources/icons/skill_icon_generation.json`에 기록했습니다. 팔레트·윤곽은 `draw_item_icons.py`에서 가져옵니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 생성 모델·외부 이미지·레퍼런스 게임 이미지를 입력하지 않았습니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/icons/items/*.png`, `scenes/combat/art/sources/icons/draw_item_icons.py`, `scenes/combat/art/sources/icons/item_icon_generation.json` | 2026-10-21 [#224](https://github.com/minjunkim-dev/BGLike/issues/224)의 임시 아이템 아이콘4종(검·활·방어구·물약). `scenes/combat/art/sources/icons/draw_item_icons.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 설명문·팔레트·규격은 `scenes/combat/art/sources/icons/item_icon_generation.json`에 기록했습니다. 생성 모델·외부 이미지·레퍼런스 게임 이미지를 입력하지 않았습니다. 팔레트는 위 유닛 프레임에서 추출했습니다. |
| `docs/images/combat_ui_archer_turn.png` | `e89cf19`의 전투 기획 문서에 포함된 화면 참고 이미지 | 정이건의 기여 기록을 확인했습니다. 별도의 외부 원본 출처는 기록돼 있지 않습니다. |
| `docs/images/combat_ui_reaction.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |
| `docs/images/combat_ui_warrior_turn.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |
| `docs/images/pixel_*.png`, `docs/images/terrain_maps_*.png` | #194·#195 최종 직접 확인의 실제 게임 화면 캡처. 위 유닛·지형 이미지를 표시한 원본 Viewport PNG와 그 contact sheet(1280×720 캡처는 nearest 축소) | 표시된 유닛·지형 이미지의 기준을 그대로 적용합니다. 화면 UI는 프로젝트 자체 구현입니다. |

Git 기여 기록만으로 제3자 자료의 원저작권을 확정하지 않습니다.
외부 원본이나 생성 도구의 별도 조건이 있으면 원래 출처와 조건을 기록하고 우선 적용합니다.
공개 동의와 자산의 사용·공개 권한 확인은 별도로 기록합니다.
현재 추적 파일에는 음악·폰트 원본이나 구매한 자산 패키지가 없습니다.

## 현재 추적된 효과음

| 파일 | 원본·권리자 | 조건과 출처 |
| --- | --- | --- |
| `scenes/combat/audio/hit.ogg` | Kenney, Impact Sounds 1.0의 `Audio/impactWood_heavy_000.ogg`. 원본 그대로 사용. 피해 발생 시 임시 타격음 | CC0 1.0 Universal. 사용·수정·재배포와 원본 공개를 허용합니다. 출처 표시는 필수가 아닙니다. [자산 페이지](https://kenney.nl/assets/impact-sounds), [CC0](https://creativecommons.org/publicdomain/zero/1.0/), [패키지의 원래 고지](scenes/combat/audio/kenney_license.txt). 2026-10-09 확인 |
| `scenes/combat/audio/dice_roll.ogg` | BGLike 자체 합성 임시음. 짧은 잡음 클릭과 사인파를 Python·numpy로 합성했고 외부 샘플을 쓰지 않았습니다. 아군 주사위 굴림 시작음 | 외부 조건 없음. [COPYRIGHT](COPYRIGHT.md)의 자체 콘텐츠 조건을 따릅니다. 자산 선정 전까지 쓰는 임시음이며 교체할 수 있습니다. 2026-10-31 |
| `scenes/combat/audio/roll_success.ogg` | BGLike 자체 합성 임시음. 사인파 두 음(660Hz→990Hz). 주사위 굴림 성공 결과음 | 위와 같음 |
| `scenes/combat/audio/roll_fail.ogg` | BGLike 자체 합성 임시음. 사인파 두 음(300Hz→200Hz). 주사위 굴림 실패 결과음 | 위와 같음 |

효과음의 CC0는 BGLike 자체 코드에 적용하지 않습니다.

## 새 자산과 출시 전 확인

새 이미지·음악·폰트·애드온을 추가할 때 원본 출처, 권리자, 라이선스와 원본 공개 허용 여부를 기록합니다.
게임 안 `출처` 화면에도 같은 고지를 짧게 더합니다.
게임에서 사용 가능한 구매 에셋이라도 원본 소스를 공개할 수 있는지 따로 확인합니다.
플랫폼별 출시 빌드에 포함된 엔진·외부 라이브러리·자산의 실제 목록을 다시 확인합니다.
각 조건이 요구하는 저작권 고지, 라이선스 전문, NOTICE와 필요한 소스 제공을 배포물에 포함합니다.
이 문서의 링크만으로 배포물의 고지 의무를 충족했다고 보고하지 않습니다.
