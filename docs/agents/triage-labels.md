# Triage Labels

분류 스킬이 사용하는 다섯 역할을 GitHub 라벨 이름에 연결합니다. 사용자 선택에 따라 기본 이름을 사용합니다.

| 스킬의 역할 | GitHub 라벨 이름 | 의미 |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | 담당자가 작업과 처리 방법을 검토해야 합니다. |
| `needs-info` | `needs-info` | 판단에 필요한 답이나 자료를 기다립니다. |
| `ready-for-agent` | `ready-for-agent` | 범위와 완료 조건이 정해져 에이전트가 구현할 수 있습니다. |
| `ready-for-human` | `ready-for-human` | 사람이 수행해야 하는 작업입니다. |
| `wontfix` | `wontfix` | 이 작업을 진행하지 않습니다. |

## 적용 범위

- 위 다섯 라벨은 [협업 규칙](../process/workflow.md)이 허용한 상태 라벨입니다. 분류 스킬은 Issue에 이 라벨을 붙이고, 판단 근거는 Issue 코멘트로 남깁니다.
- 라벨은 시작할 준비가 됐는지만 뜻합니다. 진행(작업 중, 리뷰 중)을 라벨로 적지 않습니다.
- 이 다섯 개 말고 분류 라벨(기능·버그 등)은 새로 만들지 않습니다. 같은 역할의 라벨을 중복으로 만들지 않습니다.
- `ready-for-agent` 라벨이 있어도 선행 Issue가 닫혔는지 봅니다. 라벨로 GitHub Claude를 실행하지 않습니다.
- 트래커는 GitHub입니다. 다른 트래커 연결이 있어도 스킬이 거기에 쓰지 않습니다.
