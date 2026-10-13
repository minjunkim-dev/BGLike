# 미공개 PCK 검증 Draft

[Verification Draft](../.github/workflows/draft-release.yml)는 `workflow_dispatch`만 받습니다.
`main`의 workflow로만 실행합니다.
입력은 `vX.Y.Z-alpha.N` 또는 `vX.Y.Z-beta.N`과 소문자 40자리 source commit SHA입니다.
최초 검증 후보는 `v0.1.0-alpha.1`입니다.
실행 전 [협업 규칙](WORKFLOW.md)의 최종 head 승인 절차를 따릅니다.

## 실행 조건

1. 최종 PR의 독립 리뷰와 CI를 확인합니다.
2. 최종 head의 권한 변경과 Draft 생성에 대한 사람 승인을 받습니다.
3. 승인된 PR을 `main`에 병합합니다.
4. 병합 SHA의 `.github/workflows/godot.yml` `push` CI와 필수 `CI` 작업 성공을 확인합니다.
5. Actions에서 `Verification Draft`의 `main`을 선택합니다. 버전과 병합 SHA를 입력합니다.

helper는 source SHA가 현재 `main`의 조상인지 확인합니다.
같은 SHA의 최신 `push main` CI만 인정합니다.
실패·취소·진행 중·누락된 CI는 허용하지 않습니다.
이미 있는 태그·Release·Draft 이름은 실패 처리합니다.
GitHub API 오류와 조회 한계도 실패 처리합니다.

## 패키지와 권한

읽기 권한 `build` 작업이 전체 SHA로 checkout합니다.
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
workflow concurrency는 이 workflow의 겹침만 막습니다.
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
