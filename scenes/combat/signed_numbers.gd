class_name CombatSignedNumbers
extends RefCounted
## 수치 가감(`힘 d20+2`, `공격 -1`)을 이로우면 초록, 해로우면 빨강으로 칠하는 BBCode를 만든다(#457).
## 색만으로 구분하지 않도록 부호는 그대로 둔다. +0은 칠하지 않는다.

const BENEFIT_COLOR: String = "70c76d"
const HARM_COLOR: String = "ff7b72"
# 숫자나 공백 바로 뒤의 부호 있는 수. 1~6칸 같은 범위와 이름 속 하이픈은 걸리지 않는다.
static var _signed: RegEx = RegEx.create_from_string("(?<=[\\d\\s])([+\\-])(\\d+)(?![\\d~])")


static func colorize(text: String) -> String:
	var result: String = text
	for found: RegExMatch in _signed.search_all(text):
		var amount: int = int(found.get_string(2))
		if amount == 0:
			continue
		var color: String = BENEFIT_COLOR if found.get_string(1) == "+" else HARM_COLOR
		result = result.replace(found.get_string(), "[color=#%s]%s[/color]" % [color, found.get_string()])
	return result
