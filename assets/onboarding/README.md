# Korlix welcome recording

`welcome-business-v1.wav` contains the approved Korlix introduction with a quiet
instrumental bed. The app uses this single bundled recording for synchronized
playback; there is no music download or separate background player at runtime.

## Music provenance

- Title: **MindStream**
- Artist: **DST / Deceased Superior Technician** (also present in the source MP3 tags)
- Publisher/artist release: https://opengameart.org/content/mindstream
- Source audio: https://opengameart.org/sites/default/files/DST-MindStream.mp3
- Release page checked: **October 17, 2026**. It identifies the artist as DST
  and lists the license as **CC0**.
- Terms: **CC0 1.0 Universal Public Domain Dedication**
  - Deed: https://creativecommons.org/publicdomain/zero/1.0/
  - Legal text: https://creativecommons.org/publicdomain/zero/1.0/legalcode.en
- CC0 permits adaptation, distribution and commercial use, including advertising
  and promotion, without royalty payments. This record retains voluntary credit;
  it does not imply that the artist endorses Korlix. The music is not exclusive
  to Korlix. CC0 applies to the sourced music, not automatically to the narration,
  Korlix branding or the entire application.
- Downloaded MP3: 10,756,137 bytes, SHA-256
  `50e3306a36eabead31dc702bb7654ff935351d19b9ef40421e89b4e037f92bb9`.

## Narration and mix

The spoken words and timing are unchanged. The voice-only source is available
in commit `3b284011c67c36e78dfdc4decd8490f4ca9cd636` at this same WAV path.
Its SHA-256 is
`d1e6aff7432f5cca5a7f6a0ddf3a4eb6b4dbc97ebefed398a3f689607120050c`.

The mix uses the first 30.72 seconds of MindStream, downmixed to mono, filtered
from 140 Hz to 6.5 kHz, and lowered beneath the voice. Speech detection adds a
further 6 dB reduction, with lookahead, a hold and a smooth release. Music fades
in over 0.45 seconds and out over the final 1.25 seconds. A single master gain
preserves peak headroom; the narrator is not time-stretched or compressed.

Measured delivery:

- PCM WAV, 24 kHz, mono, 16 bit; canonical 44-byte header
- 737,280 samples, **30.72 seconds**, **1,474,604 bytes**
- Music averages **20.14 dB below active speech**
- Integrated loudness **-17.37 LUFS**; true peak **-1.50 dBTP**, sample peak **-1.50 dBFS**
- **Zero clipped samples**
- Mixed WAV SHA-256:
  `139feee7e6513c06c2a1cb1d24f407a2b2844015ba78a2e2ddc758cee95dfa20`

`scripts/audio/mix_welcome_bed.py` reproduces the mix from the two checked source
recordings. It requires Python, NumPy and FFmpeg for editing only; it adds no app
dependency. Pass the voice-only WAV, original music MP3 and desired output path.
The script refuses unexpected source hashes and never overwrites an input.

Before release, listen on a phone speaker and headphones to confirm intelligibility,
music balance and pronunciation. Automated signal checks do not replace listening.
