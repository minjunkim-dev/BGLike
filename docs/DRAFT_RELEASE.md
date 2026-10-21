# 미공개 PCK 검증 Draft

[Verification Draft](../.github/workflows/draft-release.yml)는 `workflow_dispatch`만 받습니다.
`main`의 workflow로만 실행합니다.
입력은 `vX.Y.Z-alpha.N` 또는 `vX.Y.Z-beta.N`과 소문자 40자리 source commit SHA입니다.
이 workflow는 검증한 요청 JSON만 Actions artifact로 올립니다. 제품 source는 실행하지 않습니다.
[Verification Draft Build](../.github/workflows/draft-build.yml)가 요청의 성공한 `workflow_run`을 받아 빌드와 미공개 Draft 생성을 수행합니다.
요청 실행의 성공은 접수 완료입니다. 후속 Build 실행의 성공이 Draft 생성 완료입니다.
최초 검증 후보는 `v0.1.0-alpha.1`입니다.
실행 전 [협업 규칙](WORKFLOW.md)의 최종 head 승인 절차를 따릅니다.

## 실행 조건

1. 최종 PR의 독립 리뷰와 CI를 확인합니다.
2. 최종 head의 권한 변경과 Draft 생성에 대한 사람 승인을 받습니다.
3. 승인된 PR을 `main`에 병합합니다.
4. 병합 SHA의 `.github/workflows/godot.yml` `push` CI와 필수 `CI` 작업 성공을 확인합니다.
5. Actions에서 `Verification Draft`의 `main`을 선택합니다. 버전과 병합 SHA를 입력합니다.
6. 요청 실행과 연결된 `Verification Draft Build` 실행을 확인합니다. 요청만 성공한 상태를 Draft 완료로 처리하지 않습니다.

helper는 source SHA가 현재 `main`의 조상인지 확인합니다.
같은 SHA의 최신 `push main` CI만 인정합니다.
실패·취소·진행 중·누락된 CI는 허용하지 않습니다.
이미 있는 태그·Release·Draft 이름은 실패 처리합니다.
GitHub API 오류와 조회 한계도 실패 처리합니다.
모든 검증을 통과한 뒤에만 helper가 `GITHUB_OUTPUT`에 source SHA를 기록합니다.
제품 checkout은 raw 입력 대신 이 검증 출력만 사용합니다.
main 밖 SHA와 실패한 CI는 source 실행 전에 차단합니다.
`contents: read`만으로는 기본 브랜치 캐시 쓰기까지 차단하지 못하므로, source 검증을 생략하지 않습니다.

## 요청의 출처와 재실행

요청 artifact 이름은 `verification-request-<run_attempt>`입니다. 보관 기간은 7일입니다.
후속 helper는 run ID로 GitHub API를 조회합니다. 요청 workflow의 ID·path·활성 상태를 확인합니다.
저장소·`workflow_dispatch`·`main`·성공·완료·run attempt·head SHA를 확인합니다.
요청 head SHA도 현재 main에 포함되어야 합니다.
같은 run과 attempt의 정확한 artifact ID만 내려받습니다. 누락·중복·만료·출처 불일치는 거부합니다.
JSON은 helper checkout 밖의 임시 폴더에서 데이터로만 읽습니다.
`request.json` 하나와 4KiB 이하 크기, 허용한 필드·자료형을 검사합니다.
version·source SHA와 요청 run ID·attempt·head SHA를 다시 대조합니다.
읽기 build와 쓰기 draft는 원본 요청을 각각 다시 검증합니다. 쓰기 job은 build 출력의 source나 version만 신뢰하지 않습니다.
요청이 만료되거나 다른 attempt로 바뀌면 실패합니다. 실패한 검사나 이전 attempt의 요청을 재사용하지 않습니다.

## 패키지와 권한

읽기 권한 `build` 작업이 전체 SHA로 checkout합니다.
이 작업은 입력 source를 실행하지 않는 요청 workflow의 `workflow_run` 문맥에서 수행합니다.
GitHub는 이 문맥에 기본 브랜치 캐시의 읽기 권한만 부여합니다. source 실행은 공유 캐시를 쓸 수 없습니다.
캐시 읽기와 artifact 접근은 남습니다. token·Secret 전체 격리를 제공한다고 보고하지 않습니다.
tracked 변경이나 untracked 파일이 있으면 패키지를 만들지 않습니다.
Git LFS를 가져오고 `git lfs fsck`와 미해결 pointer 검사를 수행합니다.
기존 고정 Godot 4.7.2 설치 스크립트가 엔진 archive SHA-256을 확인합니다.
`Verification PCK` preset은 `--export-pack`에 필요한 exporter를 고릅니다.
`Linux` preset은 제품의 Linux 지원 선언이 아닙니다.
엔진 바이너리와 export template은 패키지에 포함하지 않습니다.

PCK는 `scenes/combat/item_data.json`을 명시적으로 포함합니다.
source checkout 밖의 임시 폴더에서 PCK의 JSON을 source SHA-256과 대조합니다.
PCK에서 메인 장면과 타격음을 읽습니다.
`--headless --main-pack --quit-after 3`으로 메인 장면을 실행합니다.
명령 실패와 Godot `ERROR:`·`WARNING:`는 패키지 실패입니다.
ZIP에는 PCK, metadata, 실행 안내와 COPYRIGHT·THIRD_PARTY·Kenney 고지가 있습니다.
metadata는 버전, 실제 checkout SHA, 엔진 버전·archive hash, preset hash, LFS 근거와 파일 hash를 기록합니다.
`SHA256SUMS`는 ZIP의 SHA-256을 제공합니다.

별도 `draft` 작업만 `contents: write`를 받습니다.
이 작업은 신뢰한 workflow SHA의 release helper와 엔진 pin만 checkout합니다.
제품 source와 dependency를 checkout하거나 실행하지 않습니다.
다운로드 ZIP을 build 출력 digest와 비교합니다.
ZIP 내부 metadata와 파일 hash를 다시 확인합니다.
생성 직전에 source·CI·버전·태그를 다시 조회합니다.
Release API 입력은 항상 `draft: true`, `prerelease: true`입니다.
`target_commitish`는 source 전체 SHA입니다.
공개·덮어쓰기·삭제 입력은 없습니다.
생성 후 미공개 상태, source SHA, asset 이름·크기와 제공된 GitHub digest를 확인합니다.

## 확인과 한계

GitHub는 태그 조회·Draft 생성·asset 업로드를 하나의 transaction으로 묶지 않습니다.
후속 Build workflow의 저장소 단위 concurrency는 Draft 생성의 겹침을 막습니다.
요청 workflow는 별도 concurrency 그룹을 사용합니다. 대기 실행이 취소되면 완료로 처리하지 않습니다.
외부 사용자와의 race는 생성 후 중복 Draft·태그·asset 검사로 탐지합니다.
실패 시 일부 Draft가 남을 수 있습니다.
자동 삭제·공개 전환은 수행하지 않습니다.
사람이 남은 Draft를 확인합니다.

Draft 생성이 성공하면 사람이 asset을 내려받아 `SHA256SUMS`를 확인합니다.
ZIP metadata의 source SHA와 GitHub asset digest도 대조합니다.
Godot 4.7.2 Standard로 `Godot --main-pack bglike.pck`을 실행합니다.
headless smoke는 조작감·화면 가독성·OS 지원·출시 준비·공개 배포를 검증하지 않습니다.

Action pin은 [upload-artifact v7.0.2](https://github.com/actions/upload-artifact/releases/tag/v7.0.2)와 [download-artifact v8.0.2](https://github.com/actions/download-artifact/releases/tag/v8.0.2)의 공식 tag commit입니다.
Godot 명령은 [공식 command line 문서](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)를 따릅니다.
기본 브랜치 캐시의 신뢰 경계는 [CodeQL의 cache poisoning 설명](https://codeql.github.com/codeql-query-help/actions/actions-cache-poisoning-poisonable-step/)을 따릅니다.
`workflow_run`의 캐시 읽기 전용 기본값은 [GitHub의 dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#cache-access-for-low-trust-workflow-triggers)를 따릅니다.
