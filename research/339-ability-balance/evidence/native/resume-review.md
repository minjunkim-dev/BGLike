# resume 검수 통과
소스 7d533b636e7db0bd39ac5e82463611ab7921d15e, 새 Godot PID 21511.
실제 main.tscn 제목 화면의 이어하기 버튼을 클릭하여 limits attempt 2의 격리 저장을 복원했다.
원본 0001.png와 JSON 대조: 가방11, 무기 +2/+3, 방어구 +1/HP+2, 전사 HP14/물약1, 궁수 HP14/물약3. 가방·party·units·props·waiting·preparation이 이전 final과 정확히 같다.
지도로 돌아가기 클릭 후 준비 화면, 전투 시작 클릭 후 라운드1 아군 턴/스킬 UI 확인. 마지막 원본 0006.png와 final 및 waiting=false/preparation=false 확인.
CUA 조회 timeout 뒤 입력을 반복하지 않고 원본 캡처로 확인. 마지막 창 크기는 3600×2196로 확대된 화면이므로 최초 1280x720 고정 크기 검수로 주장하지 않는다.
첫 resume 시도는 검수 스크립트의 존재하지 않는 title.tscn 경로 오류로 제외했다. 교정된 resume.gd와 별도 fingerprint/session 사용, 게임 본체 변경 없음.
