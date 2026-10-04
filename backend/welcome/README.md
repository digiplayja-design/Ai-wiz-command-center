# K-Nova sign-in welcome

The web app prepares a fixed K-Nova greeting at sign-in and plays it after a successful explicit sign-in. Session restoration, token refresh, navigation and widget rebuilds do not trigger repeat greetings. The welcome card includes the complete transcript, Stop/Replay, dismissal and a device-local preference also available in Sounds & alerts.

The existing `marin` K-Nova voice reads the fixed introduction. `GET /api/welcome/knova-v1.wav` is intentionally public: it accepts no user text or identity and serves one shared clip. It sends no customer information to the speech provider and does not consume customer AI GAS. Speech uses the existing OpenAI server configuration, with one coalesced warmup per process, a bounded 40-second PCM response, no provider retries, five-minute failure backoff and a one-day client cache. Provider errors are redacted. No new keys, dependencies or database migration are required.

The login tap requests silent browser audio activation synchronously, before authentication awaits. Playback waits for successful sign-in. If the browser blocks audio, the visible Listen button provides a user-gesture retry. A failed login never plays the greeting. Cached audio is preloaded before sign-in; a cold provider or slow connection can delay playback without blocking login.

The welcome respects master sound settings, volume, welcome preference, quiet hours, app foreground, incoming calls and existing microphone/media quiet leases. Sign-out, closing the card, turning off the preference or leaving the foreground cancels pending playback. A stopped greeting does not automatically resume. The card does not open the microphone or perform feature actions.

Checks: `node --test backend/test/welcome_audio.test.mjs`, Flutter `test/knova_welcome_test.dart`, CRM directory widget tests, existing auth and sound suites, and a production web release build. Tests use mocked provider/audio/auth transports. Native source uses the existing audioplayers dependency; native app distribution still follows the usual store build process.
