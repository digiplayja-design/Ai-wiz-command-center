# Korlix welcome recording

`welcome-business-music-v3.wav` contains the approved Korlix introduction with an
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

All spoken words and the narration's internal timing are unchanged. The original
30.72-second narration begins after a 1.5-second music-only opening and is followed
by a 0.5-second music tail. The voice-only source is available in commit
`3b284011c67c36e78dfdc4decd8490f4ca9cd636` at
`assets/onboarding/welcome-business-v1.wav`.
Its SHA-256 is
`d1e6aff7432f5cca5a7f6a0ddf3a4eb6b4dbc97ebefed398a3f689607120050c`.

The mix uses a fuller 32.72-second excerpt starting 32 seconds into MindStream,
downmixed to mono and filtered from 120 Hz to 9 kHz. The music is set 4 dB below
active speech before speech detection adds a further 3 dB reduction, with
lookahead, a hold and a smooth release. Music fades in over 0.15 seconds and out
over the final 0.75 seconds. A single master gain preserves peak headroom; the
narrator is not time-stretched or compressed.

The owner reported that the prior mix's music was not audible on October 17.
This revision raises music relative to active speech by a further **7.14 dB**, uses
the fuller excerpt, and establishes the music before the voice begins. A new asset
filename avoids reusing the previous preview URL; the app asset declaration and
controller both reference this revision.

Measured delivery:

- PCM WAV, 24 kHz, mono, 16 bit; canonical 44-byte header
- 785,280 samples, **32.72 seconds**, **1,570,604 bytes**
- Music averages **7.00 dB below active speech**
- Music-only opening RMS **-23.48 dBFS**
- Integrated loudness **-18.75 LUFS**; true peak **-1.46 dBTP**, sample peak **-1.50 dBFS**
- **Zero clipped samples**
- Mixed WAV SHA-256:
  `b867c2215c7471f996d5dc6627a2e4896de237df95618ecbcb8f9658a4d1da07`

`scripts/audio/mix_welcome_bed.py` reproduces the mix from the two checked source
recordings. It requires Python, NumPy and FFmpeg for editing only; it adds no app
dependency. Pass the voice-only WAV, original music MP3 and desired output path.
The script refuses unexpected source hashes and never overwrites an input.

Before release, listen on a phone speaker and headphones to confirm intelligibility,
music balance and pronunciation. Automated signal checks do not replace listening.
