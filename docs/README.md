# docs 길잡이

`docs/`의 문서는 폴더가 문서의 성격을 알려 주도록 정리하는 중입니다. 이 문서는 폴더 헌장과 현재 문서의 분류를 적습니다. 작업 시작 순서는 [문서 길잡이](agents/domain.md)를 따릅니다.

> **정리 중입니다.** 아래 색인은 현재 위치와 이동 후 경로를 함께 적습니다. 이동이 끝나면 "이동 후 경로" 열을 지우고, 4장 "정리 계획"을 삭제합니다.
>
> 2장 규칙 2의 마커·개발 결정 문장은 아직 적용하지 않습니다. 4장 5단계가 `WORKFLOW.md`·`CONTRIBUTING.md`·`agents/domain.md`·`REVIEW.md`를 고치기 전까지는 그 문서들이 우선합니다.

## 1. 폴더 헌장

문서가 어느 폴더에 속하는지는 질문 하나로 정합니다. **"이 문서가 답하는 질문은 무엇인가?"**

| 폴더 | 답하는 질문 | 들어가는 것 | 수명 |
|---|---|---|---|
| `design/` | 게임은 어떠해야 하는가 | 규칙·수치, 콘텐츠(캐릭터·몬스터·스테이지·아이템), 화면 명세, 에셋 규격 | 현재 상태만 적는다 |
| `process/` | 어떻게 일하는가 | 브랜치·커밋·CI·검증·릴리스·저장소 설정·코딩 규칙 | 절차가 바뀌면 수정 |
| `adr/` | 왜 이 기술 결정을 했는가 | 되돌리기 어려운 기술·구조 결정과 근거 | 결정 시점에 고정. 번복하면 새 ADR |
| `planning/` | 무엇을 언제 만드는가 | 일정, 진행 중인 개발 요청서 | **끝나면 삭제** |
| `agents/` | AI 에이전트는 무엇을 먼저 읽는가 | 스킬 연결·작업 시작·리뷰·이슈 규칙 | 위치 불변. `AGENTS.md`가 경로를 고정 참조 |

## 2. 운영 규칙

1. 문서 하나는 폴더 하나에만 속한다. 두 성격이 섞이면 쪼갠다.
2. `design/`에는 **현재 규칙만** 적는다. 변경 이력과 논의 경위는 Issue에, 기술 결정은 `adr/`에 둔다.
   - 아직 정하지 않은 항목은 문서 하단 `## 미정` 표에만 둔다. 열은 `항목 | 임시 규칙 | 결정 Issue`다. 임시 규칙은 결정 전까지 구현이 따르는 값이고, 구현 금지면 "개발 금지"라고 적는다.
   - 본문에 ✅·❓·⏸·🟡 상태 마커를 쓰지 않는다. 기존 문서의 마커는 문서를 손볼 때 옮긴다.
   - 개발 결정은 구현 Issue의 `개발 결정` 항목에만 기록한다. 기획서에는 결정된 현재 규칙만 쓰고 `개발 결정` 표시를 달지 않는다.
3. `planning/`은 완료되면 삭제한다. 보관 폴더(`archive/`)는 없다. 삭제한 문서는 git 이력으로 복구한다.
4. 최상위는 위 5개 폴더만 둔다. 하위폴더는 필요할 때 만들고 개수·깊이 제한은 없다. 하위폴더마다 `README.md`에 "이 폴더가 답하는 질문"을 한 줄로 적는다. 적을 수 없으면 만들지 않는다. 직속 파일도 같은 주제가 모이면 폴더로 묶는다. 이동은 링크 검사를 통과해야 한다.
5. 이미지는 소유 문서와 같은 폴더에 둔다. 소유 문서가 없는 이미지는 두지 않는다.

## 3. 문서 색인

상태: **현역**은 지금 규칙의 기준, **축소 예정**은 확정 규칙만 남기도록 줄일 문서, **삭제 예정**은 현재 규칙이 아니고 다른 문서·Issue에 같은 정보가 있는 기록이다.

### 3-1. 게임 기획서 (`design/`)

| 현재 문서 | 상태 | 이동 후 경로 |
|---|---|---|
| [GAME_STRUCTURE.md](GAME_STRUCTURE.md) | 현역 | `design/game-structure.md` |
| [COMBAT_DESIGN.md](COMBAT_DESIGN.md) | 현역 | `design/combat/combat.md` |
| [ABILITY_SYSTEM.md](ABILITY_SYSTEM.md) | 현역 | `design/combat/ability.md` |
| [SKILL_TYPES.md](SKILL_TYPES.md) | 현역 | `design/combat/skill-types.md` |
| [COMBAT_UIUX.md](COMBAT_UIUX.md) | 현역 | `design/combat/combat-ui.md` |
| [DICE_PRESENTATION.md](DICE_PRESENTATION.md) | 현역 | `design/combat/dice-presentation.md` |
| [ITEM_LOOT.md](ITEM_LOOT.md) | 현역 | `design/growth/items-loot.md` |
| [ITEM_FORM.md](ITEM_FORM.md) | 현역 | `design/growth/item-form.md` |
| [DICE_GROWTH.md](DICE_GROWTH.md) | 축소 예정 | `design/growth/dice-growth.md` |
| [PIXEL_ART.md](PIXEL_ART.md) | 현역 (UNIT_IMAGE_TEMPLATE을 병합) | `design/pixel-art.md` |
| [TERRAIN_MAPS.md](TERRAIN_MAPS.md) | 현역 | `design/stages/terrain-maps.md` |
| [stages/README.md](stages/README.md) | 현역 | `design/stages/README.md` |
| [ENVIRONMENT_ELEMENTS.md](ENVIRONMENT_ELEMENTS.md) | 현역 | `design/combat/environment.md` |
| [characters/](characters/README.md) (README, 전사, 궁수) | 현역 | `design/characters/` |
| [monsters/](monsters/README.md) (README, 몬스터 8종) | 현역 | `design/monsters/` |

### 3-2. 작업 절차 (`process/`)

| 현재 문서 | 상태 | 이동 후 경로 |
|---|---|---|
| [WORKFLOW.md](WORKFLOW.md) | 현역 | `process/workflow.md` |
| [GIT_CONVENTIONS.md](GIT_CONVENTIONS.md) | 현역 | `process/git-conventions.md` (`pr-lint.yml`과 `commit-msg`의 안내 문구가 이 경로를 가리킨다. 워크플로·훅 수정이므로 사람 승인 후) |
| [coding-standards.md](coding-standards.md) | 현역 | `process/coding-standards.md` |
| [CAPTURE_VERIFICATION.md](CAPTURE_VERIFICATION.md) | 현역 | `process/capture-verification.md` |
| [CI.md](CI.md) | 현역 | `process/ci/ci.md` |
| [CI_CACHE.md](CI_CACHE.md) | 현역 | `process/ci/ci-cache.md` |
| [ENVIRONMENT.md](ENVIRONMENT.md) | 현역 | `process/ci/environment.md` |
| [REPOSITORY_SETUP.md](REPOSITORY_SETUP.md) | 현역 | `process/ci/repository-setup.md` |
| [DRAFT_RELEASE.md](DRAFT_RELEASE.md) | 현역 | `process/ci/draft-release.md` |

### 3-3. 기술 결정(`adr/`)과 에이전트 지침(`agents/`)

이동하지 않는다. `agents/`는 현재 위치가 곧 목표 위치이고 `AGENTS.md`·`REVIEW.md`가 직접 참조한다. `adr/`는 결정 시점에 고정하는 문서이고 스크립트·테스트 주석이 경로를 문자열로 참조한다.

| 문서 | 내용 |
|---|---|
| [adr/0001-gettext-localization.md](adr/0001-gettext-localization.md) | 화면 텍스트 번역 방식 |
| [adr/0002-resolution.md](adr/0002-resolution.md) | 기준 화면과 최소 창 크기 |
| [adr/0003-save-files.md](adr/0003-save-files.md) | 저장 파일 형식 |
| [agents/domain.md](agents/domain.md) | 작업 시작 시 읽을 문서와 기획 결정 기준 |
| [agents/development.md](agents/development.md) | 작업 크기별 진입 절차 |
| [agents/review.md](agents/review.md) | 독립 리뷰 절차 |
| [agents/office.md](agents/office.md) | repo-office로 PR 전 작업을 돌리는 방법 |
| [agents/issue-tracker.md](agents/issue-tracker.md) | 이슈 운영 규칙 |
| [agents/triage-labels.md](agents/triage-labels.md) | 분류 라벨 |

### 3-4. 일정 (`planning/`)

끝나면 삭제한다.

| 현재 문서 | 상태 | 이동 후 경로 | 삭제 시점 |
|---|---|---|---|
| [SCHEDULE_2026_Q4.md](SCHEDULE_2026_Q4.md) | 현역 | `planning/schedule-2026-q4.md` | 2026-12-24 이후 |
| [DEV_REQUEST_ABILITY.md](DEV_REQUEST_ABILITY.md) | 현역 | `planning/dev-request-ability.md` | 구현이 끝났을 때 |

### 3-5. 삭제 예정

삭제 전에 각 문서를 인용하는 위치를 점검한다. 인용된 결정이 현역 기획서나 Issue에 있는지 확인하고, 없으면 옮긴다. 인용은 대체 문서나 Issue로 바꾸거나 문장째 지운다.

| 문서 | 이유 |
|---|---|
| [DESIGN_STATUS.md](DESIGN_STATUS.md) | 결정 이력과 지난 스프린트 기록. 인용하는 곳이 많다. [ADR 0001](adr/0001-gettext-localization.md)은 링크만 제거하고, 나머지는 인용된 결정이 각 기획서에 있는지 확인한다 |
| [ROADMAP.md](ROADMAP.md) | 현황은 Issue #200과 일정 문서가 맡는다. 색인은 이 문서가 대체한다. 미정 항목의 인용은 해당 Issue로 바꾼다(예: [동작 유형 기획서](SKILL_TYPES.md)의 공격 속성 축은 Issue #357) |
| [M1_VERIFICATION.md](M1_VERIFICATION.md), [DEV_REQUEST_M1.md](DEV_REQUEST_M1.md) | M1 완료 기록 |
| [M5_VERIFICATION.md](M5_VERIFICATION.md) | 완료한 검수 기록. 9개 스테이지 관측과 병합 결과는 Issue #113 댓글에 있다. 병합 뒤의 후속 검증(정상 9전투 연속 진행, 확인 창 포커스 오류)은 git 이력에만 남는다. 인용하는 현역 문서는 Issue #113 링크로 바꾼다 |
| [HEX_GRID_PREVIEW.md](HEX_GRID_PREVIEW.md) | 격자 변경(Issue #136)으로 대체됨 |
| [ACT_PROGRESSION.md](ACT_PROGRESSION.md) | 규칙은 게임 구조 기획서 3장에 있고, 검사는 `tests/combat_progression_test.gd`가 한다. 사람이 확인하던 체크리스트는 시작 경로가 바뀌어 낡았으므로 옮기지 않는다 |
| [UNIT_IMAGE_TEMPLATE.md](UNIT_IMAGE_TEMPLATE.md) | 도트 아트 문서에 병합 |

### 3-6. 이미지

| 위치 | 처리 |
|---|---|
| `docs/images/`의 참조 없는 캡처 5개(`pixel_arrow_flight_640`, `pixel_units_poses_640`·`1280`, `terrain_maps_640`·`1280`) | 삭제 예정. `THIRD_PARTY_NOTICES.md`의 해당 행도 함께 지운다 |
| `docs/images/combat_ui_*.png` 3개 | 전투 기획서가 쓰므로 유지. 이동하면 `THIRD_PARTY_NOTICES.md`의 경로도 고친다 |
| `docs/assets/` 중 삭제 예정 문서 전용 5개(`act_progression_*` 3개, `hex_grid_*` 2개) | 문서와 함께 삭제 |
| `docs/assets/unit_template_grid.svg` | 병합하는 도트 아트 문서(`design/pixel-art.md`)로 이전 |
| `docs/assets/`의 나머지 | 규칙 5에 따라 소유 문서와 같은 폴더로 이동 |
| `docs/assets/pixel_art_1080p_before.png`·`after.png` | [도트 아트 문서](PIXEL_ART.md)와 [ADR 0002](adr/0002-resolution.md)가 함께 쓴다. 위치는 아래 "미정" 표 |

`REVIEW.md`의 "건너뛸 것"이 `docs/assets/`·`docs/images/` 경로를 적고 있으므로 이미지를 옮기면 이 줄도 고친다.

## 4. 정리 계획

정리가 끝나면 이 절을 삭제한다. PR은 아래 순서로 나눈다.

1. 이 문서 추가. 이동·삭제 없음.
2. 문서 링크 검사 스크립트 추가.
3. 삭제 예정 문서와 이미지 삭제. 삭제 전에 인용 위치를 `grep`으로 점검하고 링크를 정리한다.
4. 문서 이동과 하위폴더 `README.md` 작성. 개발 PR이 `docs/`를 고치기 전에 끝낸다. 경로를 바꿔야 하는 곳은 `AGENTS.md`, `REVIEW.md`, `CONTRIBUTING.md`, `GLOSSARY.md`, 루트 `README.md`, `agents/domain.md`, `agents/review.md`, `THIRD_PARTY_NOTICES.md`, 코드의 경로 문자열(스크립트·테스트 주석)이다. 코드가 `docs/` 아래 파일을 읽지는 않는다.
5. `WORKFLOW.md`·`CONTRIBUTING.md`·`agents/domain.md`·`REVIEW.md`의 마커·개발 결정 문장 수정, 구현 상태 표기 위치 결정, `DICE_GROWTH` 축소, `characters/`·`monsters/` 표 동기화.

## 미정

| 항목 | 임시 규칙 | 결정 |
|---|---|---|
| 여러 문서가 함께 쓰는 이미지(`pixel_art_1080p_*`)의 위치 | 이동하지 않고 현재 위치에 둔다 | 4단계 전에 정한다 |
| 구현 상태 표기("구현 전", "1단계 구현")를 두는 곳 | 지금처럼 기획서 본문에 둔다 | 5단계에서 정한다 |
