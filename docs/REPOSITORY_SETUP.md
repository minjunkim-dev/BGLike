# GitHub 저장소 설정

대상은 `minjunkim-dev/BGLike` / ID `1397933288` / public / `main`이다. GitHub 품질 운영은 1인 개발 기준이다. 제품 협업·권리 기록은 유지한다.

## 기준선 검증

`.github/repository-settings.json`은 기대값이다. GitHub 자동 적용 파일이 아니다. 관리 설정 조회 권한이 있는 로컬 `gh` 인증으로 실행한다.

```sh
python3 scripts/check_github_settings.py
```

GET으로 ID·자료형·체크/App·main blob을 확인한다. exit 0은 일치, 1은 drift, 2는 미확인이다. 누락 기준선은 중단한다. PR과 main을 구분한다. 회귀 검사는 repository-check에 있다.
PR의 unittest는 codeql.yml blob과 `codeql_main_source.sha`를 비교한다. Dependabot이 codeql.yml만 바꾸면 이 검사가 실패한다. 기준선 SHA를 `git hash-object .github/workflows/codeql.yml` 값으로 갱신한다.

## 공통 정책

서버 목표값은 기준선 파일을 따른다. 1인 개발의 필수 승인은 0명이다. one-way/broad는 사람이 최종 head를 승인한다. [독립 리뷰](agents/review.md)와 최종 CI 뒤 exact-head 병합한다. auto-merge는 사용 가능 상태만 켜고 일괄 예약하지 않는다.
필수 체크는 기존 `policy / PR conventions and scope`, `smoke`, `CI`와 App `15368`을 유지한다. 기존 보호·보안·주간 Dependabot을 유지한다. 미래 공개 Release immutability를 켠다.

## CodeQL

[workflow](../.github/workflows/codeql.yml)는 Actions·Python을 분석한다. default setup은 not-configured다. 검증 전 필수 체크에 추가하지 않는다.
[공식 지원 목록](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-code-scanning)에 GDScript가 없다. 게임 코드는 기존 Godot 검사와 독립 리뷰로 확인한다.
같은 저장소 PR·main·주간·수동 분석을 사용한다. fork는 제외한다. 기본 token은 read다. 분석 job만 security-events: write다. credential persistence는 Off다.
분석·업로드의 ref·SHA를 확인한다. PR과 main 경고를 구분한다. 결함은 수정하고 오탐은 기록한다. 자동 dismissal은 하지 않는다.

## 리뷰·배포 경계

Bugbot은 기존 규칙과 Manual Only·Autofix·On-demand Off를 유지한다. 2026-10-14 대시보드는 조회 오류로 미확인이다. YAML은 실행 방식과 결제를 증명하지 않는다.
기존 [Draft 절차](DRAFT_RELEASE.md)는 유지한다. 이번 작업에서 Draft를 실행하거나 공개하지 않는다. 공개·production job이 없어 Environment는 추가하지 않는다. 새 쓰기 권한은 사람이 최종 head를 승인한다.
