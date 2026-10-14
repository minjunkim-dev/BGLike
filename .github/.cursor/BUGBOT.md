# BGLike GitHub 자동화 영역 리뷰

- 토큰은 기본 read다. 쓰기 권한·Secret은 필요한 job에만 둔다. Secret 환경에서 PR 코드를 실행하지 않는다. 외부 Action은 전체 SHA로 고정한다.
- scope와 집계의 trusted base를 유지한다. 선택된 smoke·policy의 실패·취소·누락을 CI 성공으로 숨기지 않는다.
- Draft CD는 main source SHA·같은 SHA의 CI·archive를 확인한다. 빌드와 게시를 분리한다. 기존 Release·태그·asset을 덮어쓰지 않는다.
- Bugbot YAML·개인 override·대시보드·실제 출력과 결제 근거를 구분한다. Manual Only·Autofix Off·On-demand Off를 보존한다.
