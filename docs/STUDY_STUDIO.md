# KORLIX Study Studio

## Experience

Study / learn, Estudiar and Étudier now open Study Studio instead of placing a partial study-guide prompt in chat. Tools → Study Studio opens the same screen. KORLIX is the text AI name; NOVA remains reserved for voice.

Start with a topic and optional pasted reference notes. Choose a starting level, an understanding/test-preparation/practical-use goal, and an approximate 5/10/20-minute study session. Three authored starter packs—everyday percentages, photosynthesis basics and clear paragraphs—open immediately without an AI request or generation credit.

A pack includes short lesson sections with worked examples and takeaways, flashcards, four-choice practice questions with hints and explanations, learning goals and a recap. Text remains selectable and is rendered as plain text. There is no generated executable content, web iframe or external active link in the study material.

Reading progress is marked explicitly. Flashcard answers stay hidden until revealed. Learners rate recall as Review again or I knew this. Practice questions reveal an explanation after checking an answer; incorrect answers can be retried. First-choice correctness is retained separately from corrections. A confirmed Restart quiz clears the current quiz answers and first-try result while retaining reading/card progress. This is self-study, not a secure exam or certification system; the complete answer key is part of the saved pack and its export.

My learning searches up to 50 saved packs, displays reading progress and cards ready to review, and resumes a saved pack. Reading resumes at the first unread section; question/card selection is local UI state. A simple optional focus timer can start and pause while this workspace remains open. It is not an alarm or background notification. The guide export is plain UTF-8 text with lessons, flashcards, practice questions and an answer key.

The workspace inherits KORLIX themes, including light themes, and supports phone/desktop layouts. The workspace chrome is English; all three existing study entry labels route here. AI instructions ask for the user's requested language, but there is no automatic course translation or language selector in this release.

## Generation and limits

Uses the existing gpt-6-astra / xhigh policy through OpenAI Responses, strict structured JSON, store:false, no tools, no provider retries and a five-minute deadline. There are no new packages, keys, paid plans or hosted services.

Every AI response is validated: title/summary/field length caps, 3–6 sections, 4–12 flashcards, 4–10 quiz questions, exactly four distinct choices and a valid zero-based answer per question, and no duplicate card prompts/questions. The prompt requests narrower 5/10/20-minute pack sizes and recalculation of numerical examples. Structural validation does not establish factual accuracy.

Pasted notes are treated as reference data, not controlling instructions. The model is asked to use the notes, disclose missing/conflicting information, avoid fabricated sources and teach stable general knowledge when notes are absent. There is no browsing, source verification, document upload, OCR, video/course ingestion or guarantee of grades. Users should check important facts against course materials. Study Studio does not automatically talk through NOVA or listen to a microphone.

AI sharing consent is required before submitting topics/notes. One generation and one credit are reserved atomically against the existing usage counter and tier limits. Definite failure or stale interruption refunds the reservation once. Starters, reading, quizzes, flashcard ratings, timer, review and export use no AI credit.

Limits: 50 non-deleted packs per account, 40 creations/hour including deleted receipts, 12 AI creations/hour, one preparing AI pack per owner and three starts/active jobs per backend process. Existing app features keep their own concurrency limits.

## Durable jobs and recovery

The backend commits a preparing pack and its usage reservation before returning HTTP 202. It continues generation if the frontend is closed, and returning users reload saved state. Client request UUID plus a hash of normalized input makes creation retries idempotent, even if the account allowance has since changed. Changed input cannot reuse a request key. Failed/completed requests replay their saved result rather than calling the provider again.

No separate durable queue/worker was introduced. Process restarts can interrupt an active provider request. On the next Study Studio access, that owner's preparing records older than 12 minutes are failed, source notes removed and allowance refunded exactly once. Late provider results cannot replace failed records. No automatic reissue occurs.

The client freezes unknown-outcome creation and progress requests for retry. It offers explicit Refresh saved progress when a progress response is uncertain. No score or progress change is presented as saved before the server confirms it. Progress has an optimistic revision and a last-event UUID/hash; repeating the immediately previous event is idempotent. A stale revision from another tab returns 409 and requires refresh.

## Review dates

Unrated cards and cards whose due timestamp has passed are ready to review. Review again resets the interval and schedules ten minutes later. I knew this schedules 1, 3, 7, 14, 28, then at most 30 days across successive ratings. These are simple review suggestions based on self-rating, not a scientific prediction of mastery. Review dates are saved on the server and shown in the viewer's local timezone. They create no scheduled notifications. Practice all cards remains available.

## Private storage and deletion

The additive *_study_studio.sql migration adds public.korlix_study_sets and the security-invoker korlix_study_studio_v1 RPC. The table has RLS enabled. Anonymous and authenticated roles have no direct table or RPC privileges; only the verified backend service role calls it. Ownership is checked on every operation. Actor identity comes from the existing requireUser verifier; identity headers/body fields and editable user metadata confer no access.

Content, progress, input parameters and build state are stored per account. Pasted source notes are stored only while generation is preparing, then removed on completion/failure/stale recovery. The generated pack may still contain information derived from the notes. API responses never include the raw source notes or internal quota/hash fields.

Pack deletion requires confirmation, is blocked while preparing, and scrubs the lesson, progress, input, errors and last-event metadata. A minimal deleted receipt retains owner, hash, source category, timestamps and usage bookkeeping so deletion cannot reset quota or replay a charged request. Deleting the auth account cascades all Study Studio rows. Downloaded guides remain under the user's control.

All API responses are no-store. Export uses text/plain and nosniff. The client pins issuer/user/session ID; account changes erase private on-screen state, close private confirmations and reject late results/downloads. No secrets are put into user files or public source.

## API

All paths are under /api/study-studio and require verified sign-in.

- GET / — own saved packs and bounded summaries.
- POST /sets — create an AI or starter pack using request_key, topic, notes, level, goal, minutes, starter and explicit consent for AI.
- GET /sets/:id — own saved content, state, settings and progress.
- PUT /sets/:id/progress — revision/request_key with a read, card, answer or confirmed resetQuiz event.
- DELETE /sets/:id — confirmed private-content removal.
- GET /sets/:id/export — owned plain-text study guide with answer key.

## Deployment and verification

Apply only the Study Studio migration, then deploy the existing backend release branch and frontend release branch. Keep the App Studio, Music Studio, Tax Prep and other previously released work. No service plan, environment variable or unrelated migration needs changing.

Backend tests run the actual migration in PGlite and actual Express routes with a fixture AI provider. They cover ownership, grants, RLS, quota reservations/refunds, request replay, stale recovery, deleted receipts, account cascade, progress concurrency, quiz first-choice semantics, review intervals, content validation and exports.

Flutter tests exercise the actual workspace with a fixture client: creation/consent/retry, preparing/failed states, reading, cards, hints, quiz corrections, reset confirmation, progress recovery, library/search/delete, export and account-change isolation. Larger text and phone/desktop layouts are checked and actual Flutter screenshots are inspected. A production web build and related App Studio/Music Studio/privacy regressions must pass.

No owner account is impersonated and no owner AI credits are spent during testing. Paid-provider factual quality and the complete signed-in production flow remain owner acceptance checks. This release upgrades self-study utilities; it does not alter the separate K136S AI-agent memory/learning panel.

