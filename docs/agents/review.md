# 독립 리뷰 절차

기본 흐름은 `구현 → 자동 검사 → 독립 리뷰 → 결함 수정·커밋 → 최종 전체 diff 리뷰·CI → 위험별 승인`입니다. Bugbot은 필요한 PR의 수동 보조 리뷰입니다. 필수 CI와 독립 리뷰를 대체하지 않습니다.

## 리뷰 입력 고정

작성자는 리뷰어에게 다음 자료를 전달합니다.

- 저장소와 작업 브랜치, 고정한 전체 base SHA와 head SHA.
- Issue의 목표·합격 기준·범위·제외 범위와 결정 코멘트.
- base에서 head까지의 전체 diff, 관련 호출자·테스트·fixture·설정 경로.
- 실제 검사 명령·결과·로그 경로와 사람이 확인하지 못한 항목.
- [AGENTS.md](../../AGENTS.md), [코딩 규칙](../coding-standards.md), [협업 규칙](../WORKFLOW.md), 관련 기획 문서와 ADR의 경로·SHA-256. 없거나 읽지 못한 문서는 누락으로 기록합니다.

`git diff <base_sha> <head_sha>`로 리뷰 범위를 고정합니다. head, base, 합격 기준이나 문서 내용이 바뀌면 기존 리뷰를 최종 리뷰로 사용하지 않습니다. 변경된 입력과 문서 fingerprint를 갱신합니다.

## 별도 컨텍스트

| 리뷰 | 확인할 내용 |
| --- | --- |
| Standards | [코딩 규칙과 리뷰 우선순위](../coding-standards.md#리뷰-우선순위), 기존 interface, 오류·취소·자원 처리, 검사 품질 |
| Spec | Issue 합격 기준, 기획 규칙·수치, 관련 ADR, 구현 범위와 누락 |
| Security | 권한·trust·승인·비밀값·외부 명령·경로·삭제·dependency·workflow 권한의 변경 |

Standards와 Spec은 작성자와 분리한 각각의 컨텍스트에서 수행합니다. 위험 변경에는 Security도 별도 컨텍스트에서 수행합니다. 같은 모델을 쓰면 `같은 모델의 별도 컨텍스트`와 실제 모델명을 기록합니다. 다른 모델을 실행하지 않았으면 다른 모델의 리뷰로 보고하지 않습니다. 실행하지 못한 리뷰는 미완료로 기록합니다.

## 지적 처리와 최종 검증

1. 파일 소유권을 먼저 나눕니다. 리뷰어는 승인된 범위와 소유 파일 안의 확실한 결함을 직접 수정하고 커밋합니다. 다른 작업자의 변경을 되돌리지 않습니다. 읽기 전용으로 승인한 리뷰어는 수정하지 않고 소유 작업자에게 전달합니다.
2. 지적마다 위치, 실패 조건, 영향과 수정 근거를 적습니다. 불확실하거나 범위 밖인 문제는 근거와 함께 보고합니다. 구현 범위를 늘리거나 제품 규칙을 확정하지 않습니다.
3. 확실한 결함에는 수정 전 실패하는 동작 검사를 재사용하거나 추가합니다. 수정한 범위의 검사와 저장소 필수 검사를 실행합니다.
4. 모든 수정을 커밋한 뒤 최종 head의 전체 diff를 다시 독립 검토합니다. Bugbot의 Incremental Review로 이 단계를 대체하지 않습니다. 같은 SHA에서 이미 통과한 검사는 근거를 재사용합니다. 입력 변경이나 실패가 없으면 반복하지 않습니다.
5. PR의 Evidence에 각 리뷰의 컨텍스트·모델·base·head·문서 fingerprint·결과·수정 커밋을 기록합니다. 최종 필수 CI와 합격 기준을 확인한 뒤 [병합 정책](../WORKFLOW.md#브랜치와-병합)을 적용합니다.

## CI 실패 처리

담당 로컬 에이전트는 맡은 PR의 CI가 완료될 때까지 결과를 확인한다.

1. PR의 head·base SHA와 실패한 run·attempt를 기록한다. `gh run view <RUN_ID> --repo <OWNER/REPO> --log-failed`로 실패 로그를 확인한다.
2. 코드 결함과 인프라 장애를 구분한다. 가능한 실패는 로컬에서 재현한다. 재현하지 못한 범위는 기록한다.
3. 범위 안의 원인을 수정하고 관련 검사를 실행한다. 검사 삭제·skip·조건 완화로 실패를 숨기지 않는다. 같은 실패를 근거 없이 반복 재실행하지 않는다.
4. 수정 내용을 커밋·푸시한다. 새 head의 CI를 확인한다. 이전 커밋의 성공을 새 head의 근거로 사용하지 않는다.
5. 최종 head의 전체 diff를 별도 Standards·Spec 컨텍스트에서 다시 검토한다. 필요한 Security 리뷰, 티켓 검증과 필수 CI를 확인한 뒤 위험별 병합 조건을 적용한다.

접근 권한 부족이나 해결하지 못한 실패가 남으면 원인과 미확인 범위를 보고하고 병합하지 않는다.
이 절차는 담당 에이전트의 작업 중 수행한다. 별도 상시 감시 프로그램을 뜻하지 않는다.

## 병합 실행

저장소 `Allow auto-merge`는 On으로 둔다. 모든 PR에 자동 병합을 예약하지 않는다.
기본 흐름은 담당 로컬 에이전트가 최종 독립 리뷰·필수 CI·티켓 검증 후 직접 병합하는 방식이다.
`two-way/narrow`는 맡긴 작업의 조건 충족 후 별도 병합 위임 없이 병합할 수 있다.
`one-way/broad`는 사람이 최종 head SHA와 영향 범위를 승인해야 한다.

병합 직전에 GitHub API로 head·base와 검사 결과를 다시 확인한다.
CodeQL 경고 수정 PR은 workflow 성공이 아니라 code scanning API로 판정한다.
`refs/pull/<PR>/merge`의 Actions·Python 분석은 최종 base와 최종 head를 부모로 둔 merge 커밋에서 끝나야 한다. 각 분석의 `error`·`warning` 필드는 비어 있어야 한다. 그 ref의 열린 경고는 0건이어야 한다.
code scanning API는 분석이 없는 ref에도 열린 경고 0건을 반환한다. 경고 수만 보고 판정하지 않는다.
head나 base가 바뀌면 최종 독립 리뷰와 영향받는 검증을 갱신한다.
`gh pr merge <PR> --repo <OWNER/REPO> --squash --match-head-commit <FINAL_HEAD_SHA>`로 병합한다.
`--admin`으로 보호를 우회하지 않는다. 사용자가 병합을 금지한 PR은 열어 둔다.
독립 리뷰와 위험별 사람 승인은 현재 에이전트 절차다. GitHub가 자동 강제한다고 주장하지 않는다.
GitHub 자동 병합 예약은 독립 리뷰 결과를 대상 SHA의 필수 체크로 연결한 뒤 별도 구성한다.

## Bugbot 보조 리뷰

설정 기준은 [Cursor 공식 문서](https://cursor.com/docs/bugbot)입니다. 저장소 규칙은 [BUGBOT.md](../../.cursor/BUGBOT.md)에 있습니다.

| 항목 | 설정 위치와 목표 |
| --- | --- |
| Trigger Mode / Effort | 대시보드 `Manual Only` / `Default` |
| PR Summary / Risk Score | `As Comment` / `On` |
| Draft / Autofix | 자동 Draft 리뷰 `Off` / Autofix `Off` |
| On-demand | 계정 단위 `Disabled` 유지. 유료 사용량을 활성화하지 않음 |
| Incremental Review | 현재 값 유지. YAML에 필드를 추가하지 않음 |

[bugbot.yaml](../../.cursor/config/bugbot.yaml)은 지원되는 저장소 설정만 담습니다. `Manual Only`와 결제 설정은 YAML이 강제하지 않습니다. 로그인 계정과 이 저장소 연결을 대시보드에서 확인합니다. 계정 단위 설정의 영향 범위를 확인합니다. 다른 프로젝트와 계정의 설정을 바꾸지 않습니다.

설정 우선순위는 작성자의 personal override, base branch의 YAML, 대시보드 순입니다. PR head의 YAML은 해당 PR 리뷰에 적용하지 않습니다. 병합 전의 파일 준비와 병합 후 base branch 적용을 구분합니다.

실제 수동 시험은 적절한 PR에서 `bugbot run verbose=true`로 한 번 요청합니다. 요청 ID 또는 요청 코멘트 ID, 관측한 head, 규칙 포함 여부, 지적과 사용량을 기록합니다. 새 요약 코멘트를 직접 확인한 경우에만 출력 검증으로 기록합니다. `neutral`이나 지적 0건은 결함 부재의 증거가 아닙니다.

로컬 작업자는 지적을 `실제 결함`, `오탐`, `판단 보류`로 분류합니다. 확실한 실제 결함만 승인된 범위 안에서 수정합니다. Bugbot 설정 파일 작성, 대시보드 반영과 실제 리뷰 출력을 각각 기록합니다.

## Bugbot 입력과 로컬 문서 선택

Bugbot에는 root `.cursor/BUGBOT.md`의 핵심 규칙과 변경 경로의 하위 `.cursor/BUGBOT.md`만 전달한다.
규칙 파일에는 상세 문서·다른 영역 규칙으로 향하는 상대 Markdown 링크를 두지 않는다.
상세 문서 원문을 복제하거나 모든 문서를 읽도록 일괄 지시하지 않는다.
영역 규칙은 변경 경로에 따라 적용한다. root에서 모든 영역을 연결하지 않는다.

로컬 독립 리뷰 에이전트는 `docs/coding-standards.md`와 티켓의 확정 완료 조건을 읽는다.
그다음 변경 영역에 필요한 원문만 선택한다. 아래 표는 로컬 리뷰의 길잡이다. Bugbot 입력 목록이 아니다.

| 변경 영역 | 로컬 리뷰가 선택할 상세 문서 |
| --- | --- |
| 게임·입력·화면 | `CONTEXT.md`, `docs/COMBAT_UIUX.md`, 관련 Issue가 연결한 기획 문서·ADR |
| 게임 검사 | `docs/M1_VERIFICATION.md`의 과거 근거 범위, 현재 티켓의 합격 조건·재현 기록 |
| GitHub·CI·Draft | `docs/CI.md`, `docs/DRAFT_RELEASE.md`, `docs/REPOSITORY_SETUP.md`, 엔진 잠금 값 |
| 작업·검증 | `docs/WORKFLOW.md`, `docs/GIT_CONVENTIONS.md`, `docs/agents/domain.md` |
| 문서·권리 | 변경한 기준 문서, `COPYRIGHT.md`, `THIRD_PARTY_NOTICES.md` |


CI는 모든 추적된 root·영역 규칙을 합쳐 95,000자 이하인지 확인한다. 개별 규칙은 30,000자 이하로 유지한다.
필수 규칙 파일 누락·빈 파일·symlink와 상세 문서의 로컬 링크도 거부한다.
상세 문서 길이는 이 Bugbot 예산에 포함하지 않는다. 새 영역을 추가하면 필수 규칙 목록을 갱신한다.
이 합계는 모든 영역을 더한 보수적인 값이다. 특정 PR의 서버 입력·팀 규칙·학습 규칙 전체를 증명하지 않는다.
서버 포함·생략·잘림은 필요한 수동 리뷰의 `bugbot run verbose=true` 표로 확인한다.
Manual Only·Autofix Off·On-demand Off를 유지한다. 이 정리로 새 Bugbot 실행이나 결제 설정 변경을 시작하지 않는다.
