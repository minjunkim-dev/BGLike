<!-- PR 제목 예시: feat(combat): add turn order. 규칙: docs/GIT_CONVENTIONS.md -->

## 관련 Issue

Refs # (Issue를 끝내는 마지막 PR이면 Closes #)

## 변경 내용

### Summary

변경 이유와 결과를 적습니다. before/after 또는 작은 도식을 사용합니다.

- 변경 전:
- 변경 후:

## 검증

### Evidence

- [ ] `git diff --check`
- [ ] `python3 -m unittest discover -s scripts -p 'test_*.py'`
- [ ] 워크플로 변경 시 `actionlint` (해당 없음이면 이유 기록)
- [ ] Godot headless import와 메인 장면 실행
- [ ] 필요한 Godot 회귀 검사 (문서·관리 파일만 변경하면 범위 규칙과 생략 이유 기록)
- [ ] 최종 head의 필수 CI 통과
- [ ] 플레이 변경 시 편집기에서 직접 조작 확인 (해당 없음이면 이유 기록)

실제 명령, 결과와 로그 링크:

- base SHA / 최종 head SHA:
- Standards / Spec / 필요한 Security: 별도 컨텍스트, 실제 모델, 결과, 수정 커밋
- 합격 기준과 읽은 문서 경로·SHA-256:
- 확인하지 못한 항목:

<!-- 같은 모델이면 같은 모델의 별도 컨텍스트로 기록합니다. 실행하지 못한 리뷰는 미완료입니다. -->

## 검토자에게

중점적으로 볼 장면, 충돌 가능 파일, 미완성 기능의 노출 조건을 적습니다.

### Merge Danger

- two-way / one-way와 이유:
- blast radius: 영향을 받는 사용자·데이터·권한·외부 시스템:
- 되돌리는 방법과 남는 외부 상태:
- 병합 주체·위임 근거 / 사람이 승인해야 하는 최종 head:

<!-- diff 크기로 위험을 판단하지 않습니다. 권한 확대·되돌리기 어려운 데이터 변경·외부 대량 발송은 위험 변경입니다. one-way/broad 변경에는 사람이 최종 head를 승인해야 합니다. -->
