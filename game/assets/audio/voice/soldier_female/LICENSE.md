# The female soldier's voice, generated with ElevenLabs text to speech

- Source: ElevenLabs Text to Speech API (`POST /v1/text-to-speech/{voice_id}`, **Free tier**, a new account with
  10,000 characters a month), generated 2026-11-02 by `tools/audio/elevenlabs_voice.py --voice female` from the lines
  in `tools/audio/soldier_voice_female.json`. Every file's text, model, voice, settings, seed, length and characters
  are in `manifest.json`.
- Model `eleven_v4`; voice **Sarah** ("Mature, Reassuring, Confident", an ElevenLabs premade voice,
  `EXAVITQu4vr4xnSDxMaL`); settings stability 0.0, similarity boost 0.8, style 0.6 (the male soldier's, so the two
  sets sound like one cast); output `mp3_44100_128`, then trimmed, levelled to -20 LUFS and encoded to Ogg Vorbis by the
  same script. The same 115 moments and takes as `voice/soldier/`, in her own words where a line reads better that
  way. The lines are original, written for Deadnight. Every line was requested once; none was retaken.
- Characters spent: **6,457 of the account's 10,000 for the month**, 3,543 left (read from the subscription endpoint
  after the last request; the counter lags the requests, so intermediate readings are too low). The 115 lines are
  5,953 characters written (audio tags are not billed, so about 5,300 billed); the rest is the speech-to-text check of
  every take that no tag was read aloud (0 of 115 flagged, so no line was requested twice).
- Licence: **generated with ElevenLabs on the Free tier; attribution required; no commercial licence; replace or
  relicense before any commercial release.** The maintainer accepted the Free tier's terms for this set on 2026-11-02
  (issue #679); the relicensing is tracked in #252. The premade voice is ElevenLabs'; no custom or cloned voice is used.
- Credit: ElevenLabs (the Credits screen names it for the soldiers' voices).
