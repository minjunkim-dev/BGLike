# GitHub 저장소 설정

대상은 `minjunkim-dev/BGLike` / ID `1397933288` / public / `main`이다. GitHub 품질 운영은 1인 개발 기준이다. 제품 협업·권리 기록은 유지한다.

## 기준선 검증

`.github/repository-settings.json`은 기대값이다. GitHub 자동 적용 파일이 아니다. 검사기와 적용 도구는 이 저장소에 복사하지 않고 공개 [`minjunkim-dev/repo-baseline`](https://github.com/minjunkim-dev/repo-baseline)의 `tools/`를 쓴다. 관리 설정 조회 권한이 있는 로컬 `gh` 인증으로, repo-baseline을 clone한 곳에서 실행한다.

```sh
python3 <repo-baseline>/tools/apply_github_settings.py <BGLike 경로>
```

인자 없이 실행하면 읽기만 한다. 다른 값마다 현재값 → 기대값과 고칠 쓰기를 보여 준다. 소유자만 결과를 확인한 뒤 같은 명령에 `--apply`를 붙여 적용한다. 에이전트는 `--apply`와 branch protection 쓰기를 실행하지 않는다.
`codeql_main_source.sha`는 main의 `.github/workflows/codeql.yml` blob이다. Dependabot이 codeql.yml을 바꾸면 이 값이 drift로 나온다. `git hash-object .github/workflows/codeql.yml` 값으로 갱신한다. 이 비교는 PR CI가 아니라 위 명령에서만 한다.

## 공통 정책

서버 목표값은 기준선 파일을 따른다. 1인 개발의 필수 승인은 0명이다. 필수 CI 뒤 사람이 exact-head 병합한다. `allow_auto_merge`는 `false`다.
필수 체크 기대값은 `policy / PR conventions and scope`, `smoke`, `CI`다. 셋 다 App `15368`이고 `strict`는 true다. 이 파일은 기대값이며 branch protection을 쓰지 않는다. 기존 보호·보안·주간 Dependabot을 유지한다. 미래 공개 Release immutability를 켠다.

## CodeQL

[workflow](../.github/workflows/codeql.yml)는 Actions·Python을 분석한다. default setup은 not-configured다. 검증 전 필수 체크에 추가하지 않는다.
[공식 지원 목록](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-code-scanning)에 GDScript가 없다. 게임 코드는 기존 Godot 검사와 독립 리뷰로 확인한다.
같은 저장소 PR·main·주간·수동 분석을 사용한다. fork는 제외한다. 기본 token은 read다. 분석 job만 security-events: write다. credential persistence는 Off다.
분석·업로드의 ref·SHA를 확인한다. PR과 main 경고를 구분한다. 결함은 수정하고 오탐은 기록한다. 자동 dismissal은 하지 않는다.

## 리뷰·배포 경계

2026-10-26부터 Bugbot 전용 파일·검사·실행 요구를 제거하고 자체 리뷰를 사용한다. 고유 기준은 [REVIEW.md](../REVIEW.md)와 리뷰 자료 선택 표에 보존한다. 서버 서비스·계정 연결은 변경하지 않는다.
기존 [Draft 절차](DRAFT_RELEASE.md)는 유지한다. 이번 작업에서 Draft를 실행하거나 공개하지 않는다. 공개·production job이 없어 Environment는 추가하지 않는다. 새 쓰기 권한은 사람이 최종 head를 승인한다.

## 공통 기준과 관측 기록

2026-11에 repo-baseline 재설계([repo-baseline#71](https://github.com/minjunkim-dev/repo-baseline/issues/71))에 맞춰 해시 복사(`.github/repo-baseline.json`)·`Review status`·`PR policy` workflow와 그 검사기를 지웠다. 리뷰 기준은 [REVIEW.md](../REVIEW.md)다. 기준선의 `observations`는 설명용 관측 기록이며 감사 항목을 제외하지 않는다.

## 과거 Bugbot 확인 기록

2026-10-14 대시보드는 조회 오류로 미확인이었다. 당시 YAML은 실제 실행 방식·결제의 증거로 사용하지 않았다. 기존 기준선의 Cursor 조회 기록도 `observations`에 보존하며, 이 과거 미확인을 현재 설정이나 새 실행 요구로 바꾸지 않는다.
