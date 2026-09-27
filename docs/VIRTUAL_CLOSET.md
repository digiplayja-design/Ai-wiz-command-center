# KORLIX Virtual Closet — first release

Open **Virtual Closet** from the home quick actions or Utility tools. The responsive
white/navy workspace contains My Closet, Try On, Nova Stylist, and Saved Looks.
Upload your photo, add individually photographed wardrobe items, select up to four,
and choose Try it on. Nova can suggest an outfit from the saved wardrobe when given
an occasion, dress code or preference. Clothing names/categories are editable at
upload; this release does not automatically recognize garment categories.

## Working scope

- Signed-in users can upload, browse, filter, remove and reopen their private
  wardrobe. Input is a still JPG/PNG/WEBP up to 15 MiB and 45 megapixels. Images are
  orientation-corrected, resized within 2048 pixels, and saved as JPEG without EXIF;
  thumbnails are bounded to 480×640. Uploading is not AI generation.
- Existing Ultra Premium/Enterprise and daily usage checks gate try-on and Nova
  styling. The UI discloses one existing generation credit per successful request.
  No billing plan or Stripe configuration changes are introduced.
- Try-on uses the real person photo plus 1–4 garment references. Astra xhigh plans
  the edit, and the existing Sunburst maximum-quality image model renders a portrait
  PNG. A decoded, valid PNG is required. Instructions preserve the face, hairline,
  skin tone, body shape and garment details; likeness and actual fit are not guaranteed.
- Nova styling is typed text in this release. It uses item names/categories and up
  to 16 wardrobe thumbnails, returns only existing item IDs, and selects those items
  for try-on. This is not retailer search, affiliate checkout or sizing prediction.
- Results save automatically to Saved Looks. They can be reopened, compared with
  the available source photo, downloaded as PNG, or removed. Limits are five person
  photos, 100 garments, 50 looks and 250 MiB per account. Cloud data can be reopened
  on another signed-in device. No model photos or sample wardrobe are seeded.

## Privacy and reliability

Migration `20260927145553_virtual_closet.sql` adds two RLS-enabled tables, a private
`korlix-virtual-closet` bucket and a server-only, security-invoker RPC. Anonymous and
authenticated client roles have no table or RPC privileges. A restrictive Storage
policy prevents broader legacy policies from exposing this bucket. Every API action
derives the actor from verified account authentication; caller-supplied user IDs and
storage paths are never accepted. Signed URLs expire after ten minutes; the open UI
refreshes them every eight minutes and offers manual refresh. Responses are no-store.

AI consent is checked before starting a job. Try-on sends the chosen person photo
and clothing; Nova styling sends wardrobe photos and item details. Astra requests
use `store:false`. Successful output and wardrobe images persist in the account
until removed. Removal deletes both stored image and thumbnail before releasing the
metadata/quota; failures remain visible and retryable. Existing account deletion is
a support-request workflow; operators must purge this bucket's user prefix before
completing account erasure. Deleting a database user alone does not remove Storage
objects. New image storage must be included in the public privacy/store disclosures.

Jobs are recorded before provider execution and return immediately. Reopening the
workspace finds an active job and resumes polling. One job per user, three active
jobs per server and twenty attempts per hour bound demand. Uploads have a global
three-request concurrency limit. Request UUIDs prevent duplicate dispatch on replay.
Provider calls have no automatic retries. There is no new worker service: an existing
backend process runs each job, so a process restart can interrupt it. After twelve
minutes interrupted jobs become failed, with an explicit manual retry and no charge.
Navigation and connection loss do not cancel a still-running backend job.

Successful job completion and a single usage increment happen in one transaction;
replaying completion does not charge twice. Provider failure does not charge. Uploads
reserve quota and a three-minute lease before transfer; retry of the same bytes can
resume an expired upload. Incomplete photos/looks stay visible for later deletion.
In-flight frontend responses are rejected when the account or session changes;
token rotation in the same session is permitted. Account changes clear displayed
photos, selections and prompts.

## Verification and deployment

Automated tests exercise real Express routes against the migration in PGlite with
injected storage/provider fixtures: private ownership, restrictive RLS, malformed
images, upload/deletion recovery, quotas, replay, parallel requests, recovery,
atomic usage, reference-image construction and model-response validation.
Flutter checks cover desktop/phone/enlarged text, first use, consent denial,
duplicate prevention, reopened jobs, upload retry, PNG download and account changes.
Adjacent picture/chat/theme/Nova regression suites and a web release build are run.
These fixtures do not establish real-user try-on image quality.

Apply the migration to the existing KORLIX Supabase project, deploy the tested
backend on its existing Render service, verify health/auth rejection, and then
deploy the tested frontend. Keep automatic deployment off. No new infrastructure,
credentials or subscriptions are required. Rollback uses the prior application
commits while retaining additive tables/private media; do not drop customer data.

Acceptance: upload your own full-length photo and one clear garment photo, generate
a try-on, inspect face/clothing accuracy, reopen Saved Looks, download the PNG,
and ask Nova for an occasion-based outfit. Verify this on the user's actual device.

References:
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/storage/buckets/fundamentals
- https://developers.openai.com/api/reference/resources/images/methods/edit
