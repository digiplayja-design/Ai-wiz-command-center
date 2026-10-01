# Live Studio: Google setup

This creates the **KORLIX business application's Google connection**. The owner's personal YouTube channel is not required. Customers authorize their own channels inside Live Studio. A dedicated, authorized test channel is needed later to prove broadcasting works.

Activation update, October 1, 2026: the user saved the Google client ID and secret directly in Render. The approved US$25/month worker is live and idle, and the API's `LIVE_STUDIO_YOUTUBE_ENABLED` is now `true`. Database heartbeat and API configuration checks passed. Google Cloud Console was unavailable in the assisted browser, so actual Google client validity and consent configuration still need the first authorized channel connection. The next user action is step 8; steps 1–7 remain the setup reference. Preserve the installed shared encryption key.

1. Open [Google Cloud Console](https://console.cloud.google.com/) in your browser and select the Google Cloud project owned by the KORLIX business. In **APIs & Services → Library**, enable **YouTube Data API v3**.
2. Open **Google Auth Platform → Branding**. Use the application's actual name, an accessible support address and monitored developer contact details. Set these public URLs:

   | Field | Value |
   | --- | --- |
   | Homepage | `https://www.korlixdeveloper.com/` |
   | Privacy policy | `https://www.korlixdeveloper.com/privacy-policy.html` |
   | Terms of service | `https://www.korlixdeveloper.com/terms.html` |

   Ensure the homepage describes Live Studio before submitting it for verification. Use domains controlled by the business; production verification requires ownership verification for the project's authorized domains. If Google rejects the Render callback domain, resolve that explicitly with a verified custom API domain and matching application configuration.
3. In **Audience**, choose **External** and keep **Testing** for acceptance work. Add only the Google accounts participating in testing under **Test users**. Testing permits up to 100 listed test users, and this YouTube authorization expires after seven days; scheduled shows may therefore require reconnection. This is not broad customer access.
4. In **Data Access**, add `https://www.googleapis.com/auth/youtube.force-ssl`. The implemented feature uses this permission to create/manage broadcasts and read live chat. Review Google's displayed permission description; it covers more YouTube actions than KORLIX currently performs.
5. In **Clients → Create Client**, select **Web application**, name it **KORLIX Live Studio**, and add this exact **Authorized redirect URI**:

   ```text
   https://chee-chai-chee-backend.onrender.com/api/live-studio/connect/youtube/callback
   ```

   This server-based flow needs the redirect URI, not a browser-only JavaScript client. Keep the new client secret secure when Google displays it; it may not be viewable again.
6. Open [Render](https://dashboard.render.com/) → **chee-chai-chee-backend → Environment**. Enter the client ID and secret directly as `LIVE_STUDIO_YOUTUBE_CLIENT_ID` and `LIVE_STUDIO_YOUTUBE_CLIENT_SECRET`. Do not send either through chat or commit credentials. Preserve the existing `LIVE_STUDIO_TOKEN_KEY`; the API and worker must share it. Keep the API's enabled flag `false` while preparing deployment.
7. After the current connection/retention changes are deployed, create the worker using `deploy/live-studio-worker.render.yaml` on `release/k135z-backend-render-20260919`. The Blueprint references the API's shared secret settings and configures one worker slot. Confirm it starts successfully. Then set the API's `LIVE_STUDIO_YOUTUBE_ENABLED=true`, deploy the API, and verify Live Studio reports connection setup and worker readiness correctly.
8. In [KORLIX](https://www.korlixdeveloper.com/app/) → **Tools → Live Studio**, connect the dedicated test channel, review its identity, and confirm it. Channel connection does not start a broadcast. The channel must independently qualify for YouTube live streaming. Complete the planned unlisted broadcast acceptance tests before enabling customer sales.

Before broad release, finish Google branding/data-access verification, including a working consent/feature demonstration and scope justification. Review YouTube metadata controls: the current 80-character title cap, fixed description and unlisted-only acceptance setting need assessment against YouTube's required functionality and users' final publication control. Verify retention/revocation behavior and remaining billing/capacity tests. Configuration does not establish Google approval or completed compliance.

Official references: [server OAuth and API/client setup](https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps), [testing audience limits](https://support.google.com/cloud/answer/15549945), [verification preparation](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification), [YouTube developer policies](https://developers.google.com/youtube/terms/developer-policies).

Remaining customer-ready MVP estimate: **2–4 development weeks, plus external approval time**.
