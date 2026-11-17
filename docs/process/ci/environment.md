# 로컬과 CI의 공통 검사

Godot 버전과 공식 배포 파일의 SHA-256은 `scripts/godot.env`에서 관리합니다.
Linux x86_64·arm64와 macOS에서 같은 설치·검사 스크립트를 사용합니다.
설치·검사 도우미는 현재 Windows를 지원하지 않습니다.

## 처음 설치

저장소 루트에서 실행합니다. Python 3, Make, Bash, curl과 unzip이 필요합니다.

```bash
make godot-install
make check
```

설치 도우미는 `.cache/godot/`에 공식 배포 파일을 받습니다.
다운로드와 캐시 파일의 SHA-256을 확인한 후 압축을 풉니다.
캐시가 손상되면 다시 다운로드하고 검사합니다.
이미 편집기가 있으면 공통 검사를 직접 실행합니다.

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot make check
```

검사는 다른 버전의 엔진을 차단합니다.
Godot headless import, 메인 장면 실행과 전투 테스트 다섯 개를 수행합니다.
Python 검사와 `git diff --check`도 실행합니다.
워크플로 변경은 `actionlint`로 추가 검사합니다.

## 새 환경 확인

GitHub Actions의 Godot 워크플로는 Ubuntu 24.04에서 `make godot-install`과 `make godot-check`를 실행합니다.
수동 실행의 `use-cache=false`는 엔진 캐시 복원과 저장을 끕니다.
CI는 엔진 버전과 커밋을 로그에 남깁니다.
저장소의 정책 작업은 Python 검사도 수행합니다.
캐시는 설치 속도를 줄이며 검사 성공 조건을 바꾸지 않습니다.

OS와 CPU가 다르면 결과 파일이 바이트 단위로 같다는 뜻은 아닙니다.
엔진 버전과 검사 조건을 맞추고 플랫폼 차이를 별도로 확인합니다.
이 검사는 렌더링과 플레이 감각을 확인하는 사람의 플레이 테스트를 대체하지 않습니다.
현재 릴리스 패키지 생성과 배포는 자동화하지 않습니다.
배포를 추가할 때 검사한 패키지를 커밋·SHA-256과 연결하고 그대로 전달해야 합니다.
