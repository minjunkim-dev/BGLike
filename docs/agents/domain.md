# Domain Docs

이 저장소는 하나의 Godot 게임 프로젝트입니다. 단일 문서 구조를 사용합니다.

## Before exploring, read these

1. [AGENTS.md](../../AGENTS.md), [협업 규칙](../WORKFLOW.md), [브랜치와 커밋 규칙](../GIT_CONVENTIONS.md)을 읽습니다.
2. 루트의 [CONTEXT.md](../../CONTEXT.md)를 읽고 관련 용어를 확인합니다.
3. 작업할 Issue의 목표, 완료 조건과 코멘트의 결정 기록을 읽습니다. Issue가 연결한 기획 문서도 직접 엽니다.
4. `docs/adr/`에 관련 결정 기록이 있으면 읽습니다.

`CONTEXT-MAP.md`가 나중에 생기면 그 문서가 가리키는 관련 `CONTEXT.md`를 읽습니다. 현재는 다중 문서 구조를 만들지 않습니다.

`CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`의 파일이 없으면 해당 읽기만 건너뛰고 작업을 계속합니다. 파일이 없다는 이유로 생성부터 제안하지 않습니다.

## File structure

```text
/
├── CONTEXT.md          # 게임 용어집
└── docs/
    ├── 기획 문서       # 규칙과 수치의 기준
    ├── agents/         # 스킬 설정과 문서 읽기 규칙
    └── adr/            # 결정이 생겼을 때 추가하는 기록
```

기존 `CONTEXT.md`를 유지합니다. 폴더나 예시 ADR을 미리 만들지 않습니다. 용어나 구조의 결정이 생기면 해당 문서를 갱신합니다.

## Use the glossary's vocabulary

Issue 제목, 설명, 코드, 테스트, 리뷰에서는 `CONTEXT.md`의 용어를 사용합니다. `_Avoid_`에 적힌 다른 이름으로 바꾸지 않습니다.

필요한 용어가 없으면 기존 용어로 설명할 수 있는지 먼저 확인합니다. 실제 결정이 필요하면 Issue 코멘트에 질문을 남깁니다. 기획에서 정하지 않은 게임 규칙이나 이야기를 임의로 확정하지 않습니다.

## Flag ADR conflicts

기획 문서나 기존 ADR과 다른 변경이 필요하면 충돌하는 문서와 이유를 명시합니다. Issue 코멘트에 질문을 남기고 결정을 확인한 뒤 구현합니다. 문서와 다른 수치나 규칙을 코드에서 먼저 확정하지 않습니다.
