class_name SoundVariants
extends RefCounted
## 효과음 갈래(#630). 같은 소리의 갈래 파일들을 AudioStreamRandomizer 하나로 묶어,
## 재생할 때마다 갈래를 연속 반복 없이 고르고 높낮이를 무작위로 흔든다.
## AudioStreamRandomizer.get_length()는 0.0이라 길이는 longest()로 잰다.


## 갈래 파일 경로. 원본 `<cue>.ogg`가 첫 갈래, 이어서 `<cue>_2.ogg`, `<cue>_3.ogg`….
static func variant_paths(dir: String, cue: String, count: int) -> PackedStringArray:
	var paths: PackedStringArray = [dir + cue + ".ogg"]
	for number: int in range(2, count + 1):
		paths.append("%s%s_%d.ogg" % [dir, cue, number])
	return paths


## 경로가 하나면 그 OGG 그대로, 둘 이상이면 높낮이를 1/pitch~pitch배로 흔드는 Randomizer.
static func build(paths: PackedStringArray, pitch: float) -> AudioStream:
	if paths.size() == 1:
		return load(paths[0]) as AudioStream
	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = pitch
	randomizer.random_volume_offset_db = 0.0
	for path: String in paths:
		randomizer.add_stream(-1, load(path) as AudioStream)
	return randomizer


## 갈래 중 가장 긴 원래 길이(높낮이 1.0 기준). Randomizer가 아니면 스트림 자신의 길이.
static func longest(stream: AudioStream) -> float:
	var randomizer: AudioStreamRandomizer = stream as AudioStreamRandomizer
	if randomizer == null:
		return stream.get_length()
	var length: float = 0.0
	for index: int in range(randomizer.streams_count):
		length = maxf(length, randomizer.get_stream(index).get_length())
	return length
