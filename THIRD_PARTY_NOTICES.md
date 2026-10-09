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

## 현재 추적된 이미지

| 파일 | 확인된 기여 기록·용도 | 권리 확인 기준 |
| --- | --- | --- |
| `scenes/combat/art/floor_tiles.svg` | 프로토타입의 도형 타일. `ba2fd4e`의 전투 기반 구현에 포함 | 프로젝트 기여 기록을 확인했습니다. 별도의 외부 원본 출처는 기록돼 있지 않습니다. |
| `docs/images/combat_ui_archer_turn.png` | `e89cf19`의 전투 기획 문서에 포함된 화면 참고 이미지 | 정이건의 기여 기록을 확인했습니다. 별도의 외부 원본 출처는 기록돼 있지 않습니다. |
| `docs/images/combat_ui_reaction.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |
| `docs/images/combat_ui_warrior_turn.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |

Git 기여 기록만으로 제3자 자료의 원저작권을 확정하지 않습니다.
외부 원본이나 생성 도구의 별도 조건이 있으면 원래 출처와 조건을 기록하고 우선 적용합니다.
공개 동의와 자산의 사용·공개 권한 확인은 별도로 기록합니다.
현재 추적 파일에는 음악·폰트 원본이나 구매한 자산 패키지가 없습니다.

## 현재 추적된 효과음

| 파일 | 원본·권리자 | 조건과 출처 |
| --- | --- | --- |
| `scenes/combat/audio/hit.ogg` | Kenney, Impact Sounds 1.0의 `Audio/impactPunch_medium_000.ogg`. 원본 그대로 사용. 피해 발생 시 임시 타격음 | CC0 1.0 Universal. 사용·수정·재배포와 원본 공개를 허용합니다. 출처 표시는 필수가 아닙니다. [자산 페이지](https://kenney.nl/assets/impact-sounds), [CC0](https://creativecommons.org/publicdomain/zero/1.0/), [패키지의 원래 고지](scenes/combat/audio/kenney_license.txt). 2026-10-09 확인 |

효과음의 CC0는 BGLike 자체 코드에 적용하지 않습니다.

## 새 자산과 출시 전 확인

새 이미지·음악·폰트·애드온을 추가할 때 원본 출처, 권리자, 라이선스와 원본 공개 허용 여부를 기록합니다.
게임에서 사용 가능한 구매 에셋이라도 원본 소스를 공개할 수 있는지 따로 확인합니다.
플랫폼별 출시 빌드에 포함된 엔진·외부 라이브러리·자산의 실제 목록을 다시 확인합니다.
각 조건이 요구하는 저작권 고지, 라이선스 전문, NOTICE와 필요한 소스 제공을 배포물에 포함합니다.
이 문서의 링크만으로 배포물의 고지 의무를 충족했다고 보고하지 않습니다.
