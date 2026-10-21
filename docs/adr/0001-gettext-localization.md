# 0001. 화면 텍스트는 gettext PO로 번역하고 한국어 원문을 msgid로 쓴다

- 상태: 채택 (2026-10-22)
- 구분: 개발 결정. 기획자가 나중에 바꿀 수 있다.
- 관련: [Issue #217](https://github.com/minjunkim-dev/BGLike/issues/217), [기획 현황 2-2-2](../DESIGN_STATUS.md#2-2-2-2026-10-15-기획-논의-결정)

## 맥락

한국어만 출시하지만 화면 텍스트를 코드에서 분리해 다른 언어를 나중에 추가할 수 있어야 한다. 화면 문구는 약 220개이고 대부분 GDScript에 있다.

## 결정

[Godot 4.7 gettext 문서](https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_gettext.html)의 PO 방식을 쓴다. 한국어 원문을 그대로 msgid로 쓴다.

- `locale/messages.pot`: Godot 편집기의 Project Settings > Localization > Template Generation이 만든 템플릿이다. 대상은 `project.godot`의 `internationalization/locale/translations_pot_files`에 적은 게임 장면과 스크립트 전부다.
- `locale/ko.po`: 템플릿에서 만든 한국어 메시지 파일이다. msgstr은 msgid와 같다. `internationalization/locale/translations`에 등록한다.
- 스크립트의 화면 문자열은 `tr()`로 감싼다. 개수에 따라 말이 바뀌는 문장은 `tr_n()`을 쓴다. 형식 문자열은 `tr("...") % 값`으로 쓴다. 템플릿 생성기는 상수 문자열 인자만 읽기 때문이다.
- 정적 함수와 이름·설명 표는 인스턴스가 없으므로 `TranslationServer.tr()`을 쓴다. 템플릿 생성기는 `const` 초기값을 읽지 않는다. 그래서 화면 문자열이 든 표(`CombatActionRules.NAMES`·`EFFECTS`, `CombatLoot.STAT_NAMES`, 몬스터 정의)는 `static var`로 둔다.
- 장면의 Control 문구(`text`, `tooltip_text`, 대화상자 제목·버튼)는 Godot가 자동 번역한다. 지금 장면은 모두 `auto_translate_mode` 기본값(상속)을 쓴다.

### 화면 문자열과 로그·디버그 전용 문자열

| 구분 | 기준 | 처리 |
| --- | --- | --- |
| 화면 | 라벨·버튼·툴팁·대화상자, 전투 기록 패널에 쌓이는 `logged`, 유닛 위 팝업 `feedback`, 사용 불가 이유처럼 플레이어에게 보이는 문자열 | `tr()`·`tr_n()` |
| 로그·디버그 전용 | `assert`·`push_error`·`push_warning`·`print` 계열 메시지. 데이터 오류를 개발자에게 알린다 | 감싸지 않음 |
| 검사 | `tests/`의 문자열 | 감싸지 않음 |

전투 기록(`logged`)은 화면 패널에 보이므로 화면 문자열이다.

### 검사

`scripts/check_translation_strings.py`가 다음을 실패로 처리한다. `scripts/test_translation_strings.py`가 이 검사를 실행하므로 `make check`와 CI policy의 Python 회귀 검사에 포함된다.

- `tests/` 밖의 GDScript에서 `tr()`·`tr_n()`의 직접 인자가 아닌 한글 문자열 리터럴. 위 디버그 호출 안의 문자열은 제외한다. 화면에 보이지 않는 한글 값이 꼭 필요하면 같은 줄에 Godot 규약인 `# NO_TRANSLATE`를 붙인다.
- 템플릿 생성 대상에 없는 게임 장면·스크립트.

## 한계와 후속

- 검사는 한글이 든 리터럴만 찾는다. `"HP %d / %d"`처럼 영문만 있는 화면 문자열은 리뷰로 확인한다.
- `item_data.json`의 아이템 이름은 표시할 때 `TranslationServer.tr()`을 거치지만 템플릿 생성기가 JSON을 읽지 않는다. 다른 언어를 추가할 때 PO에 직접 넣거나 JSON용 `EditorTranslationParserPlugin`을 만든다.
- `static var` 표는 클래스를 처음 불러올 때 한 번 번역한다. 실행 중 언어 변경은 범위 밖이다. 언어 선택을 만들 때 다시 본다.
- CI는 POT가 최신인지 검사하지 않는다. 문구를 바꾸면 편집기에서 템플릿을 다시 생성하고 `msgmerge --update --backup=none locale/ko.po locale/messages.pot` 뒤 새 항목의 msgstr을 msgid로 채운다. 갱신을 빠뜨려도 화면에는 msgid가 그대로 나온다.

## 대안

- CSV와 문자열 키: 약 220개 키를 손으로 관리해야 하고 코드에서 원문을 읽기 어렵다. 택하지 않았다.
- 영어 msgid: 지금 출시 언어가 한국어뿐이라 원문을 두 번 관리하게 된다. 택하지 않았다.
