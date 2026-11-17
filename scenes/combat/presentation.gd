class_name CombatPresentation
## 유닛 이동·연출 시간의 전체 속도(#516 5절). 1보다 작으면 느려진다. 플레이로 조정하는 곳은 이 상수 하나다.
## 피해 팝업·주사위·HUD 시간과 Engine.time_scale에는 적용하지 않는다.
const PRESENTATION_SPEED: float = 0.7


## 기본 시간(초)을 전체 속도로 늘린 값.
static func duration(base: float) -> float:
	return base / PRESENTATION_SPEED


## 기본 fps를 전체 속도로 늦춘 값.
static func fps(base: float) -> float:
	return base * PRESENTATION_SPEED
