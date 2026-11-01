# An onset detector found nothing on a mix with a bed under it

2026-11-01

- **Symptom:** the audio analysis of a night capture found one onset, so no sound could be checked against its event.
- **Cause:** the ambient bed never goes below the detector's absolute floor, so the level never "rises through" it.
- **Fix:** compare the short-term level with its own median over two seconds and call a rise of 9 dB an onset;
  `tools/audio/analyze.py capture --expect seconds:name` then checks every logged sound within a tolerance.
- **Documented:** [audio research](../research/audio.md).
