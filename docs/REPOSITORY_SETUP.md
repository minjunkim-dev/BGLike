# GitHub 저장소 설정

대상은 `minjunkim-dev/BGLike` / ID `1397933288` / public / `main`이다. GitHub 품질 운영은 1인 개발 기준이다. 제품 협업·권리 기록은 유지한다.

## 기준선 검증

`.github/repository-settings.json`은 기대값이다. GitHub 자동 적용 파일이 아니다. 관리 설정 조회 권한이 있는 로컬 `gh` 인증으로 실행한다.

```sh
python3 scripts/check_github_settings.py
```

GET으로 ID·자료형·체크/App·main blob을 확인한다. exit 0은 일치, 1은 drift, 2는 미확인이다. 누락 기준선은 중단한다. PR과 main을 구분한다. 회귀 검사는 repository-check에 있다.
PR의 unittest는 codeql.yml blob과 `codeql_main_source.sha`를 비교한다. Dependabot이 codeql.yml만 바꾸면 이 검사가 실패한다. 기준선 SHA를 `git hash-object .github/workflows/codeql.yml` 값으로 갱신한다.
공통 검사기(`check_github_settings.py`·`check_repo_baseline.py`·`check_review_status.py`)와 테스트는 공개 `minjunkim-dev/repo-baseline`에서 복사한다. 이 저장소에서 직접 고치지 않는다. 원본을 고친 뒤 `tools/apply_baseline.py`로 다시 적용한다. 복사본이 `.github/repo-baseline.json`의 해시와 다르면 `python3 scripts/check_repo_baseline.py`가 실패한다. CodeQL 단계들이 서로 다른 `github/codeql-action` commit을 쓰는 것도 거부한다.

## 공통 정책

서버 목표값은 기준선 파일을 따른다. 1인 개발의 필수 승인은 0명이다. one-way/broad는 사람이 최종 head를 승인한다. [독립 리뷰](agents/review.md)와 최종 CI 뒤 exact-head 병합한다. auto-merge는 사용 가능 상태만 켜고 일괄 예약하지 않는다.
필수 체크는 기존 `policy / PR conventions and scope`, `smoke`, `CI`와 App `15368`을 유지한다. 기존 보호·보안·주간 Dependabot을 유지한다. 미래 공개 Release immutability를 켠다.

## CodeQL

[workflow](../.github/workflows/codeql.yml)는 Actions·Python을 분석한다. default setup은 not-configured다. 검증 전 필수 체크에 추가하지 않는다.
[공식 지원 목록](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-code-scanning)에 GDScript가 없다. 게임 코드는 기존 Godot 검사와 독립 리뷰로 확인한다.
같은 저장소 PR·main·주간·수동 분석을 사용한다. fork는 제외한다. 기본 token은 read다. 분석 job만 security-events: write다. credential persistence는 Off다.
분석·업로드의 ref·SHA를 확인한다. PR과 main 경고를 구분한다. 결함은 수정하고 오탐은 기록한다. 자동 dismissal은 하지 않는다.

## 리뷰·배포 경계

2026-10-26부터 Bugbot 전용 파일·검사·실행 요구를 제거하고 자체 리뷰를 사용한다. 고유 기준은 코딩 규칙·리뷰 자료 선택 표에 보존한다. 서버 서비스·계정 연결은 변경하지 않는다.
기존 [Draft 절차](DRAFT_RELEASE.md)는 유지한다. 이번 작업에서 Draft를 실행하거나 공개하지 않는다. 공개·production job이 없어 Environment는 추가하지 않는다. 새 쓰기 권한은 사람이 최종 head를 승인한다.

## 공통 기준 갱신과 설정 관측 기록

적용 원본은 `minjunkim-dev/repo-baseline`의 main `e8c5224e33d8ebe3aa915fd741702ee75c77ecc2`다. 복사본의 경로와 Dependabot `ecosystems`(빈 목록)를 유지하며 원본 도구로 갱신했다. 다시 적용하기 전에 기록된 해시와 파일이 같았고, 이 저장소만의 수정은 없었다. 로컬 스킬 설정과 일상 작업 진입은 [개발 절차](agents/development.md), 자체 리뷰와 사용자 요청 회고는 [리뷰 절차](agents/review.md)를 따른다.

`scripts/workflow_policy.py`, `scripts/pr_author.py`, `scripts/test_workflow_policy.py`, `scripts/rerun_review_status.py`와 PR 양식을 manifest에 더했다. `scripts/check_review_status.py`와 테스트는 같은 도구로 다시 복사했다. `.claude/settings.json`과 `matt-code-review` 스킬 사본은 원본과 같아 바뀌지 않았다. `.github/workflows/review-status.yml`과 `.github/workflows/pr-policy.yml`은 템플릿과 같은 별도 파일이고, 다른 workflow와 합치지 않았다. `actions/checkout` pin은 `3d3c42e5aac5ba805825da76410c181273ba90b1` `# v7.0.1`이다. Review status의 이벤트는 `pull_request_target`과 `issue_comment`뿐이다. `ready_for_review`는 `pull_request_target`의 활동 유형이다.

`.github/workflow-policy.json`은 이 저장소 설정이다. manifest가 복사하지 않는다. `reject_claude_md`는 거짓이다. `@AGENTS.md`만 있는 `CLAUDE.md`를 유지한다. `feature_flags`는 거짓이다. [협업 규칙](WORKFLOW.md)이 공통 기능 플래그 시스템을 만들지 않으므로 `config/feature-flags.json`을 두지 않는다. 봇 브랜치 접두사는 기존과 같이 `claude`, `codex`, `dependabot`이다.

`.github/workflows/review-status.yml`의 `pull_request_target`은 기본 브랜치의 workflow와 검사기만 실행한다. GitHub는 공개 저장소에서 이 이벤트를 2026-12-02부터 기본으로 막는다. 그 전에 2026-11-09 16:00–18:00 UTC와 2026-11-16 16:00–18:00 UTC(한국 시간 2026-11-10과 2026-11-17 01:00–03:00)에 같은 차단을 잠시 적용한다. 공식 공지는 [pull_request_target blocked by default December 2](https://github.blog/changelog/2026-11-02-pull_request_target-blocked-by-default-december-2/)다. 허용 정책이 기본 브랜치 병합 전에 보이기 전에는 이 workflow를 병합하지 않는다. 이 갱신은 그 정책을 만들지 않았고 필수 체크 `Review status`도 등록하지 않았다. 현재 필수 체크는 기존 `policy / PR conventions and scope`, `smoke`, `CI`다. `PR policy`는 필수 체크가 아니다.

기존 기준선의 설명용 `exceptions` 배열은 내용을 보존해 `observations`로 옮겼다. 관측 기록은 API 감사 항목을 제외하지 않는다. 실제 기능 미지원·비해당을 감사 범위에서 제외하려면 원본의 [설정 기준선 형식](https://github.com/minjunkim-dev/repo-baseline/blob/e8c5224e33d8ebe3aa915fd741702ee75c77ecc2/docs/github-settings-profile.md)에 맞는 `exceptions` 객체와 사유·근거가 필요하다. 예외가 있으면 exit 0이어도 결과는 전체 PASS가 아닌 LIMITED다. 미선언 403·404·누락·권한 오류는 계속 실패한다.

이번 갱신은 GitHub 서버 기대값·권한·필수 체크·CodeQL·배포를 변경하지 않는다. 과거 실행 기록을 현재 검증 결과로 바꾸지 않는다.

## 과거 Bugbot 확인 기록

2026-10-14 대시보드는 조회 오류로 미확인이었다. 당시 YAML은 실제 실행 방식·결제의 증거로 사용하지 않았다. 기존 기준선의 Cursor 조회 기록도 `observations`에 보존하며, 이 과거 미확인을 현재 설정이나 새 실행 요구로 바꾸지 않는다.
