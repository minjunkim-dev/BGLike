# 외부 구성 요소와 자산의 권리 고지

자체 코드의 권리 방침은 [COPYRIGHT](COPYRIGHT.md)에 있습니다.
외부 구성 요소에는 해당 권리자의 라이선스가 적용됩니다. 이 문서가 그 조건을 변경하지 않습니다.

확인 기준: 2026-11-17의 추적 파일과 Git 기여 기록(효과음 표는 2026-11-17 #628). 출시 패키지의 전체 고지를 완료했다는 뜻은 아닙니다.

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

버전 근거: [전투 기획서](docs/design/combat/combat.md)의 밀치기는 양쪽이 d20을 굴리는 대결입니다. SRD 5.1의 방식이며, SRD 5.2는 대상의 내성 굴림으로 바꿨습니다.
표기 원문: [SRD 5.1 CC PDF](https://media.dndbeyond.com/compendium-images/srd/5.1/SRD_CC_v5.1.pdf) 1쪽. 2026-10-21 확인.
게임 안 표기는 타이틀 화면의 `출처` 화면(`scenes/main.tscn`)에 있습니다. `tests/title_test.gd`가 위 인용문과 같은지 검사합니다. 이 문서와 Draft 배포 묶음의 이 파일은 저장소·배포물 고지입니다.

## 현재 추적된 이미지

| 파일 | 확인된 기여 기록·용도 | 권리 확인 기준 |
| --- | --- | --- |
| `scenes/combat/art/terrain/*.png`, `scenes/combat/art/props/*.png`, `scenes/combat/art/sources/terrain/*.png` | 2026-10-21 사용자 위임으로 내장 `image_gen`에서 독자 생성한 재질5종·오브젝트5종. 실제64px 도트와 원본10개·나무 첫 원본/투명도 교정 기록을 보존 | 정확한 프롬프트·원본·가공 규격은 `scenes/combat/art/sources/world_generation.json`, `normalize_terrain.py`와 [맵 제작 기준](docs/design/stages/terrain-maps.md)에 기록했습니다. 레퍼런스 게임 이미지를 입력·복제하지 않았습니다. 생성 도구의 별도 조건을 적용합니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/units/**/*.png`, `scenes/combat/art/sources/units/*.png` | 2026-10-21 사용자 요청으로 내장 `image_gen`에서 독자 생성한 유닛9종. 생성 기준 시안과 전체 상태·방향 시트를 보존. 런타임108프레임은 시트를 자르고 nearest-neighbor 축소·투명도 정규화 | 원본과 프롬프트·도구 모드는 `scenes/combat/art/sources/unit_generation.json`에 기록했습니다. 레퍼런스 게임 이미지를 입력·복제하지 않았습니다. 생성 도구의 별도 조건을 함께 적용합니다. 생성 결과에 대한 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/icons/skills/*.png`, `scenes/combat/art/sources/icons/draw_skill_icons.py` | 2026-10-27 [#384](https://github.com/minjunkim-dev/BGLike/issues/384)의 스킬 아이콘11종(2026-10-21 #225의 도형 아이콘을 대체). 2026-11-15 [#560](https://github.com/minjunkim-dev/BGLike/issues/560)에서 기름병 던지기 아이콘 `oil_throw.png`를, [#500](https://github.com/minjunkim-dev/BGLike/issues/500) 2b에서 장난스러운 화살·폭죽 화살 아이콘 `trick_arrow.png`·`firework_arrow.png`를, #500 3단계에서 효시 아이콘 `whistle.png`를 같은 스크립트로 더함. `draw_skill_icons.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물. 공격·물약은 아이템 검·물약과 같은 그림 | 아이콘별 설명과 규격은 `scenes/combat/art/sources/icons/skill_icon_generation.json`에 기록했습니다. 팔레트·윤곽은 `draw_item_icons.py`에서 가져옵니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 생성 모델·외부 이미지·레퍼런스 게임 이미지를 입력하지 않았습니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/effects/hit_flash/*.png`, `scenes/combat/art/sources/effects/draw_hit_effects.py`, `scenes/combat/art/sources/effects/hit_effect_generation.json` | 2026-11-16 [#559](https://github.com/minjunkim-dev/BGLike/issues/559)의 타격 섬광 3프레임. `draw_hit_effects.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 규격은 `hit_effect_generation.json`에 기록했습니다. 팔레트는 `draw_item_icons.py`에서 가져왔습니다. 생성 모델·외부 이미지·외부 이펙트 모음(pixelfx 등)·레퍼런스 게임 이미지를 입력하지 않았습니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. |
| `scenes/combat/art/icons/passives/*.png`, `scenes/combat/art/sources/icons/draw_passive_icons.py` | 2026-11-16 [#517](https://github.com/minjunkim-dev/BGLike/issues/517)의 패시브 칸 아이콘 3종(팔랑크스·괴력의 사내·무빙샷, 32×32). `draw_passive_icons.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 아이콘별 설명과 규격은 `scenes/combat/art/sources/icons/passive_icon_generation.json`에 기록했습니다. 팔레트·윤곽은 `draw_item_icons.py`에서 가져옵니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 생성 모델·외부 이미지·레퍼런스 게임 이미지를 입력하지 않았습니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/combat/art/icons/items/*.png`, `scenes/combat/art/sources/icons/draw_item_icons.py`, `scenes/combat/art/sources/icons/item_icon_generation.json` | 2026-10-21 [#224](https://github.com/minjunkim-dev/BGLike/issues/224)의 임시 아이템 아이콘4종(검·활·방어구·물약). 2026-11-15 [#575](https://github.com/minjunkim-dev/BGLike/issues/575)에서 기름병 아이콘 `oil_bottle.png`를 같은 스크립트로 더함. 2026-11-16 [#577](https://github.com/minjunkim-dev/BGLike/issues/577)에서 물약 칸용 작은 아이콘 `oil_bottle_pip.png`를 더함. `scenes/combat/art/sources/icons/draw_item_icons.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 설명문·팔레트·규격은 `scenes/combat/art/sources/icons/item_icon_generation.json`에 기록했습니다. 생성 모델·외부 이미지·레퍼런스 게임 이미지를 입력하지 않았습니다. 팔레트는 위 유닛 프레임에서 추출했습니다. |
| `scenes/combat/art/dice/*.png`, `docs/design/combat/images/dice_states.png`, `scenes/combat/art/sources/dice/draw_dice.py`, `scenes/combat/art/sources/dice/dice_generation.json` | 2026-11-16 [#519](https://github.com/minjunkim-dev/BGLike/issues/519)의 판정 주사위 상태 그림(d4~d20 × 굴리는 중·성공·실패·절대성공·절대실패 30개와 액체 마스크 6개, 48×48)과 비교 시트. `draw_dice.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 설명문·팔레트·규격은 `scenes/combat/art/sources/dice/dice_generation.json`에 기록했습니다. 생성 모델·외부 이미지·레퍼런스 이미지·Baldur's Gate 3의 자산을 입력하지 않았습니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `docs/design/combat/images/combat_ui_archer_turn.png` | `e89cf19`의 전투 기획 문서에 포함된 화면 참고 이미지 | 정이건의 기여 기록을 확인했습니다. 별도의 외부 원본 출처는 기록돼 있지 않습니다. |
| `docs/design/combat/images/combat_ui_reaction.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |
| `docs/design/combat/images/combat_ui_warrior_turn.png` | 같은 기획 문서의 화면 참고 이미지 | 같은 기준을 적용합니다. |

Git 기여 기록만으로 제3자 자료의 원저작권을 확정하지 않습니다.
외부 원본이나 생성 도구의 별도 조건이 있으면 원래 출처와 조건을 기록하고 우선 적용합니다.
공개 동의와 자산의 사용·공개 권한 확인은 별도로 기록합니다.
현재 추적 파일에는 구매한 자산 패키지가 없습니다. 음악은 아래 [현재 추적된 배경음](#현재-추적된-배경음)의 CC0 음원 네 곡입니다. 글꼴 원본은 아래 [현재 추적된 글꼴](#현재-추적된-글꼴)의 Galmuri11입니다.

## 현재 추적된 효과음

| 파일 | 원본·권리자 | 조건과 출처 |
| --- | --- | --- |
| `scenes/combat/audio/hit_wood.ogg` | Kenney, Impact Sounds 1.0의 `Audio/impactWood_heavy_000.ogg`. 원본 그대로 사용(옛 이름 `hit.ogg`). 나무 상자 피해 소리 | CC0 1.0 Universal. 사용·수정·재배포와 원본 공개를 허용합니다. 출처 표시는 필수가 아닙니다. [자산 페이지](https://kenney.nl/assets/impact-sounds), [CC0](https://creativecommons.org/publicdomain/zero/1.0/), [패키지의 원래 고지](scenes/combat/audio/kenney_license.txt). 2026-10-09 확인 |
| `scenes/combat/audio/dice_roll.ogg` | BGLike 자체 합성 임시음. 짧은 잡음 클릭과 사인파를 Python·numpy로 합성했고 외부 샘플을 쓰지 않았습니다. 아군 주사위 굴림 시작음 | 외부 조건 없음. [COPYRIGHT](COPYRIGHT.md)의 자체 콘텐츠 조건을 따릅니다. 자산 선정 전까지 쓰는 임시음이며 교체할 수 있습니다. 2026-10-31 |
| `scenes/combat/audio/roll_success.ogg` | BGLike 자체 합성 임시음. 사인파 두 음(660Hz→990Hz). 주사위 굴림 성공 결과음 | 위와 같음 |
| `scenes/combat/audio/roll_fail.ogg` | BGLike 자체 합성 임시음. 사인파 두 음(300Hz→200Hz). 주사위 굴림 실패 결과음 | 위와 같음 |
| `scenes/combat/audio/hit_flesh.ogg`, `hit_metal.ogg`, `hit_stone.ogg`, `critical.ogg`, `downed.ogg` | 2026-11-17 [#628](https://github.com/minjunkim-dev/BGLike/issues/628). Kenney, Impact Sounds 1.0의 `impactPunch_medium_000`(살), `impactMetal_medium_000`(금속 로봇), `impactMining_000`(바위), `impactPunch_heavy_000`+`impactMetal_heavy_000`을 겹친 치명타(꺼 둠), `impactSoft_heavy_000`(전투 불능)을 모노로 바꾸고 길이를 잘라 끝을 줄이고 정규화했습니다. 원본은 `scenes/combat/audio/sources/kenney/`, 가공은 `make_sfx.py` | CC0 1.0 Universal. 사용·수정·재배포와 원본 공개를 허용합니다. 출처 표시는 필수가 아닙니다. [Impact Sounds](https://kenney.nl/assets/impact-sounds), [RPG Audio](https://kenney.nl/assets/rpg-audio), [CC0](https://creativecommons.org/publicdomain/zero/1.0/), [Kenney 패키지의 원래 고지](scenes/combat/audio/kenney_license.txt)(두 패키지 모두 같은 CC0 고지). 2026-11-17 확인(zip sha256 Impact Sounds `029d734a…`, RPG Audio `6dbeaf85…`) |
| `scenes/combat/audio/miss.ogg`, `shield.ogg`, `heal.ogg`, `shout.ogg`, `step_water.ogg` | 같은 #628. BGLike 자체 합성음. 빗나감 휘두름, 성스러운 장막, 회복, 전투의 함성, 물 칸 발소리. 잡음·사인파·감쇠 곡선을 Python·numpy로 합성했고 외부 샘플을 쓰지 않았습니다 | 외부 조건 없음. [COPYRIGHT](COPYRIGHT.md)의 자체 콘텐츠 조건을 따릅니다. 만드는 법과 변수는 `scenes/combat/audio/sources/make_sfx.py`와 `sfx_generation.json`에 있고 다시 실행하면 같은 소리를 만듭니다 |
| `scenes/combat/audio/step_dirt.ogg`, `step_stone.ogg`, `jump.ogg`, `land.ogg` | 같은 #628. Kenney, RPG Audio의 `footstep00`(흙)·`cloth1`(점프)과 Impact Sounds 1.0의 `footstep_concrete_000`(돌)·`impactSoft_medium_000`(착지)을 위와 같이 가공했습니다 | 위 Kenney 행과 같음 |
| `scenes/combat/audio/turn_ally.ogg`, `turn_enemy.ogg` | 같은 #628. BGLike 자체 합성 칩튠풍 음. 아군·적 진영 턴 시작 신호 | 위와 같음 |
| `scenes/combat/audio/ambient_water.ogg`, `ambient_wind.ogg` | 같은 #628. BGLike 자체 합성 반복음(필터를 건 순환 잡음). 물 칸이 있는 스테이지의 물소리와 그 밖의 바람소리 | 위와 같음 |
| `scenes/ui/audio/ui_hover.ogg`, `ui_click.ogg`, `ui_cancel.ogg`, `ui_disabled.ogg` | 같은 #628. BGLike 자체 합성 칩튠풍 음. 버튼 호버·클릭·취소·사용 불가 | 위와 같음 |

효과음의 CC0는 BGLike 자체 코드에 적용하지 않습니다.
음원 조건: CC0·MIT·CC-BY만 쓰고 비상업(NC)·변경 금지(ND)는 쓰지 않습니다(2026-11-17 소유자 결정, #558). 지금 외부 원본은 Kenney의 CC0 소리(Impact Sounds, RPG Audio)뿐이라 출처 표시 의무가 있는 음원은 없습니다.

## 현재 추적된 배경음

2026-11-17 [#629](https://github.com/minjunkim-dev/BGLike/issues/629)의 화면별 배경음 네 곡입니다. 모두 CC0 1.0 Universal이고 OpenGameArt 페이지의 License 칸이 `CC0`인 것을 2026-11-17에 확인했습니다. 사용·수정·재배포와 원본 공개를 허용하며 출처 표시는 필수가 아닙니다. 그래도 게임 안 `출처` 화면에 작가와 곡명을 적었습니다. 재생기는 `scenes/audio/game_music.gd`입니다.

| 파일 | 원본·권리자 | 조건과 출처 |
| --- | --- | --- |
| `scenes/audio/music/calm.ogg` | Juhani Junkala(SubspaceAudio), JRPG Music Pack #4 [Calm]의 `Calm2 - Childhood Friends.ogg`. 원본 그대로 사용(파일 이름만 바꿈). 타이틀·정비의 반복 곡(102.9초) | CC0 1.0 Universal. [페이지](https://opengameart.org/content/jrpg-pack-4-calm), 원본 sha256 `dc536901748772e4822118887d6f164343b1d9e4fea3a7c197ac2fcb06d6f344`. 2026-11-17 확인 |
| `scenes/audio/music/battle.ogg` | Juhani Junkala(SubspaceAudio), JRPG Music Pack #5 [Action]의 `Action1 - Encounter With The Witches.ogg`. 원본 그대로 사용(파일 이름만 바꿈). 전투의 반복 곡(113.5초) | CC0 1.0 Universal. [페이지](https://opengameart.org/content/jrpg-pack-5-action), 원본 sha256 `f957434432f49f5cc0a4d81351304d7daa646af5bcbeaccc29d47224cd40fb8f`. 2026-11-17 확인 |
| `scenes/audio/music/victory.ogg` | celestialghost8, "Victory"(2A03 승리 팡파르)의 `Victory.wav`. WAV 원본(모노)을 스테레오 OGG로 바꿨습니다(`ffmpeg -ac 2 -c:a vorbis -q:a 6`). 승리 결과 화면에서 한 번 울리는 곡(4.9초) | CC0 1.0 Universal. [페이지](https://opengameart.org/content/victory), 원본 WAV sha256 `a045e252f9dd7a6d4781daa1aa9e0cc7357ea73700f53e3d99d0d4654f32c804`. WAV 원본은 저장소에 넣지 않습니다. 2026-11-17 확인 |
| `scenes/audio/music/defeat.ogg` | Kosmo The Cat, "Game over short jingle"의 `Game over jingle.ogg`. 원본 그대로 사용(파일 이름만 바꿈). 패배 결과 화면에서 한 번 울리는 곡(7.7초) | CC0 1.0 Universal. [페이지](https://opengameart.org/content/game-over-short-jingle), 원본 sha256 `7b5a71fd270c407bcfc8e558a2594b36f0172894c474359826acb1bc38330762`. 2026-11-17 확인 |

배경음의 CC0는 BGLike 자체 코드에 적용하지 않습니다.

## 현재 추적된 글꼴

| 파일 | 버전·용도 | 조건과 출처 |
| --- | --- | --- |
| `scenes/ui/fonts/Galmuri11.ttf` | Galmuri v2.40.4의 `dist/Galmuri11.ttf`. 게임 UI 글꼴(기본 크기 11). 한글 도트 글꼴 | SIL Open Font License 1.1. 원본 라이선스 전문은 `scenes/ui/fonts/LICENSE-Galmuri.txt`(Galmuri 저장소의 `ofl.md` 그대로, Copyright © 2019–2025 Lee Minseo). 예약 글꼴 이름(Reserved Font Name) 지정은 없습니다. 출처는 Galmuri v2.40.4 태그입니다. [OFL 1.1 전문](https://openfontlicense.org/open-font-license-official-text/). 2026-11-13 leader 확인 |

글꼴 파일을 수정하거나 나누어 배포하면 OFL 1.1의 조건을 따릅니다. 게임 안 `출처` 화면에도 같은 고지를 둡니다.

## 현재 추적된 UI 프레임

| 파일 | 원본·용도 | 조건과 출처 |
| --- | --- | --- |
| `scenes/ui/art/frames/panel.png`, `accent_panel.png`, `button.png` | 프로젝트 자체 제작 9-slice UI 프레임 3종(16×16). `scenes/ui/art/sources/draw_ui_frames.py`가 코드로 픽셀을 찍어 만든 자체 제작물. 색은 `scenes/ui_theme.tres`의 modulate로 정함 | 규격은 `scenes/ui/art/sources/ui_frame_generation.json`에 기록했습니다. 생성 모델·외부 이미지·글꼴을 입력하지 않았습니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |
| `scenes/ui/art/frames/slider_track.png`, `slider_grabber.png`, `slider_grabber_highlight.png`, `scenes/ui/art/title/logo.png`, `scenes/ui/art/sources/draw_menu_art.py`, `scenes/ui/art/sources/menu_art_generation.json` | 2026-11-16 [#557](https://github.com/minjunkim-dev/BGLike/issues/557)의 볼륨 슬라이더 막대·손잡이 3종(8×8, 8×12)과 임시 이름 `BGLike`의 도트 로고(108×24). `draw_menu_art.py`가 코드로 픽셀을 찍어 만든 프로젝트 자체 제작물 | 규격·팔레트·글자 모양은 `scenes/ui/art/sources/menu_art_generation.json`에 기록했습니다. 생성 모델·외부 이미지·글꼴을 입력하지 않았습니다. 스크립트를 다시 실행하면 같은 PNG를 만듭니다. 타이틀 배경은 새 그림 파일 없이 기존 전투 지형·유닛 자산을 런타임에 조합하므로 따로 적지 않습니다. 제3자의 원저작권 부재나 독점권을 확정하는 기록은 아닙니다. |

## 새 자산과 출시 전 확인

새 이미지·음악·폰트·애드온을 추가할 때 원본 출처, 권리자, 라이선스와 원본 공개 허용 여부를 기록합니다.
게임 안 `출처` 화면에도 같은 고지를 짧게 더합니다.
게임에서 사용 가능한 구매 에셋이라도 원본 소스를 공개할 수 있는지 따로 확인합니다.
플랫폼별 출시 빌드에 포함된 엔진·외부 라이브러리·자산의 실제 목록을 다시 확인합니다.
각 조건이 요구하는 저작권 고지, 라이선스 전문, NOTICE와 필요한 소스 제공을 배포물에 포함합니다.
이 문서의 링크만으로 배포물의 고지 의무를 충족했다고 보고하지 않습니다.
