# docs 길잡이

`docs/`의 문서는 폴더가 문서의 성격을 알려 주도록 정리합니다. 이 문서는 폴더 헌장과 현재 문서의 분류를 적습니다. 작업 시작 순서는 [문서 길잡이](agents/domain.md)를 따릅니다.

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
   - 본문에 ✅·❓·⏸·🟡 상태 마커를 쓰지 않는다. 구현 상태("구현", "개발 금지")는 현재 상태이므로 해당 규칙 옆에 문장으로 쓴다. 이력(누가 언제 어떤 단계에서)은 Issue에 둔다.
   - 개발 결정은 구현 Issue의 `개발 결정` 항목에만 기록한다. 기획서에는 결정된 현재 규칙만 쓰고 `개발 결정` 표시를 달지 않는다.
3. `planning/`은 완료되면 삭제한다. 보관 폴더(`archive/`)는 없다. 삭제한 문서는 git 이력으로 복구한다.
4. 최상위는 위 5개 폴더만 둔다. 하위폴더는 필요할 때 만들고 개수·깊이 제한은 없다. 하위폴더마다 `README.md`에 "이 폴더가 답하는 질문"을 한 줄로 적는다. 적을 수 없으면 만들지 않는다. 직속 파일도 같은 주제가 모이면 폴더로 묶는다. 이동은 링크 검사를 통과해야 한다.
5. 이미지는 소유 문서와 같은 폴더에 둔다. 소유 문서가 없는 이미지는 두지 않는다.

## 3. 문서 색인

상태: **현역**은 지금 규칙의 기준이다.

### 3-1. 게임 기획서 (`design/`)

| 문서 | 상태 |
|---|---|
| [game-structure.md](design/game-structure.md) | 현역 |
| [combat.md](design/combat/combat.md) | 현역 |
| [ability.md](design/combat/ability.md) | 현역 |
| [skill-types.md](design/combat/skill-types.md) | 현역 |
| [combat-ui.md](design/combat/combat-ui.md) | 현역 |
| [dice-presentation.md](design/combat/dice-presentation.md) | 현역 |
| [items-loot.md](design/growth/items-loot.md) | 현역 |
| [item-form.md](design/growth/item-form.md) | 현역 |
| [dice-growth.md](design/growth/dice-growth.md) | 현역 |
| [pixel-art.md](design/pixel-art.md) | 현역 (유닛 이미지 납품 규격 포함) |
| [terrain-maps.md](design/stages/terrain-maps.md) | 현역 |
| [stages/README.md](design/stages/README.md) | 현역 |
| [environment.md](design/combat/environment.md) | 현역 |
| [characters/](design/characters/README.md) (README, 전사, 궁수) | 현역 |
| [monsters/](design/monsters/README.md) (README, 몬스터 8종) | 현역 |

### 3-2. 작업 절차 (`process/`)

| 문서 | 상태 |
|---|---|
| [workflow.md](process/workflow.md) | 현역 |
| [git-conventions.md](process/git-conventions.md) | 현역 |
| [coding-standards.md](process/coding-standards.md) | 현역 |
| [capture-verification.md](process/capture-verification.md) | 현역 |
| [ci.md](process/ci/ci.md) | 현역 |
| [ci-cache.md](process/ci/ci-cache.md) | 현역 |
| [environment.md](process/ci/environment.md) | 현역 |
| [repository-setup.md](process/ci/repository-setup.md) | 현역 |
| [draft-release.md](process/ci/draft-release.md) | 현역 |

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

| 문서 | 상태 | 삭제 시점 |
|---|---|---|
| [schedule-2026-q4.md](planning/schedule-2026-q4.md) | 현역 | 2026-12-24 이후 |
| [dev-request-ability.md](planning/dev-request-ability.md) | 현역 | 구현이 끝났을 때 |

### 3-5. 이미지

이미지는 소유 문서가 있는 폴더의 하위 `images/`에 둔다.

| 위치 | 소유 문서 |
|---|---|
| `design/images/` | [pixel-art.md](design/pixel-art.md): 타격 효과, 아이콘, 유닛 템플릿, 해상도 비교(`pixel_art_1080p_*`는 [ADR 0002](adr/0002-resolution.md)도 쓴다) |
| `design/combat/images/` | [combat.md](design/combat/combat.md)의 `combat_ui_*`, [combat-ui.md](design/combat/combat-ui.md)의 `uiux_*`, [dice-presentation.md](design/combat/dice-presentation.md)의 `dice_states.png` |
| `design/growth/images/` | [items-loot.md](design/growth/items-loot.md): 준비 화면, 보상, 버리기 확인 |
| `design/stages/images/` | [terrain-maps.md](design/stages/terrain-maps.md): 높이 모서리 |
| `adr/images/` | [ADR 0002](adr/0002-resolution.md)만 쓰는 카메라·HUD·준비 화면·외곽선 캡처 |

`REVIEW.md`의 "건너뛸 것"은 `docs/` 아래 `images/` 폴더를 적는다.

## 미정

| 항목 | 임시 규칙 | 결정 |
|---|---|---|
| 여러 문서가 함께 쓰는 이미지(`pixel_art_1080p_*`)의 위치 | 도트 아트 문서 폴더(`design/images/`)에 두고 ADR 0002가 링크한다 | 4a에서 그렇게 옮겼다. 바꾸려면 개발자와 정한다 |
| 이미지를 소유 문서와 같은 폴더에 둔다는 규칙 5의 폴더 모양 | 소유 문서 폴더의 하위 `images/` | 4a에서 그렇게 옮겼다 |
