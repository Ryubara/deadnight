class_name PcmStream
extends RefCounted
## Short sounds decoded once into 16-bit samples. Starting a player on an Ogg Vorbis stream makes
## the engine read the file's headers and codebooks again for that play: about 0.8 ms in the web
## build for every shot, impact and voice, six or more in the frame of a kill. A stream of samples
## starts in about 0.3 ms, and costs the audio mixer less while it plays. So a sound that is
## short (`MAX_SECONDS`) is decoded when the night loads (`AudioService.preload_sound`), behind
## its loading screen, and plays from the samples. The beds and loops stay Ogg (they start once).

## Longest sound decoded to samples, in seconds: 2.5 s of mono is 240 KB.
const MAX_SECONDS := 2.5
## Frames compared to tell a mono sound from a stereo one.
const MONO_PROBES := 64
const MONO_TOLERANCE := 1.0e-5
const PEAK := 32767.0


## Whether `stream` is short enough to be decoded.
static func fits(stream: AudioStream) -> bool:
	return stream is AudioStreamOggVorbis and stream.get_length() <= MAX_SECONDS


## The file a stream came from: its own path, or for a decoded copy the Ogg it was made from (a
## copy in memory has no path of its own). Tests use it to tell which take played.
static func source(stream: AudioStream) -> String:
	return stream.resource_path if stream.resource_path != "" else stream.resource_name


## `ogg` as samples at `mix_rate` (the audio server's rate): one channel when both of its channels
## are the same, as the mono files are, two otherwise.
static func decode(ogg: AudioStream, mix_rate: int) -> AudioStreamWAV:
	var playback := ogg.instantiate_playback()
	playback.start(0.0)
	var wanted := ceili(ogg.get_length() * mix_rate) + mix_rate / 20
	var frames := playback.mix_audio(1.0, wanted)
	var mono := _is_mono(frames)
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * (2 if mono else 4))
	# The loop runs once for every sample of every sound (millions when the night loads, in a browser
	# that is most of the time the decode takes), so it calls nothing it can write out.
	var at := 0
	if mono:
		for frame in frames:
			bytes.encode_s16(at, clampi(roundi(frame.x * PEAK), -32768, 32767))
			at += 2
	else:
		for frame in frames:
			bytes.encode_s16(at, clampi(roundi(frame.x * PEAK), -32768, 32767))
			bytes.encode_s16(at + 2, clampi(roundi(frame.y * PEAK), -32768, 32767))
			at += 4
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = not mono
	wav.data = bytes
	wav.resource_name = ogg.resource_path
	return wav


static func _is_mono(frames: PackedVector2Array) -> bool:
	var step := maxi(frames.size() / MONO_PROBES, 1)
	for i in range(0, frames.size(), step):
		if absf(frames[i].x - frames[i].y) > MONO_TOLERANCE:
			return false
	return true
