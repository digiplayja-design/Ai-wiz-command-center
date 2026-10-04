# App Studio customer portals

App Studio now includes a guided publishing path for a complete customer portal. A saved project provides its branding; it does not convert arbitrary prototype collections into a production application.

## Owner setup

1. Open an existing App Studio project or start from a template.
2. Choose **Customer portal**. Add the portal name and welcome message. The saved project's color and theme carry over.
3. Review the feature checklist and save a private draft or choose **Publish portal**. Publishing and updating a live portal require confirmation. The screen shows both the saved source version and the live source version.
4. Under **People & invitations**, enter a customer's or staff member's KORLIX email and choose their role. Invitations last seven days and are bound to that verified email. Copy the link or code immediately; the code is shown once. Creating an invitation does not send an email.
5. Use **Open portal** for a secure owner session. **Copy public link** shares only the sign-in landing page, never a session credential.

The **My portals** button lists portals you own or have joined. An invitation link opens KORLIX sign-in, then asks the recipient to accept it. A code can also be entered in My portals. Customers can only read their own requests, replies and files. Staff can work across the portal's requests. Owners control publishing, invitations and access removal.

Publishing snapshots the current saved branding. Later App Studio builds remain private until the owner updates the live portal. Updating publication invalidates active portal sessions; users reopen through KORLIX. Unpublishing turns off member access while retaining records and memberships. Deleting the App Studio project removes its portal and records; the project deletion confirmation makes that consequence explicit.

## Hosted workflow

- Customers create requests and follow their status.
- Staff and owners update status and exchange replies with the request's customer.
- Request attachments accept PDF and common photo formats, up to 5 MB per file. Files are available only to that customer and the portal's team.
- An optional secure checkout link opens the owner's external payment provider. KORLIX does not process the payment or confirm payment status.

Prototype screens and sample records remain in the preview and ZIP export. Publishing does not import sample data or promise arbitrary custom live features. No payment provider account is created, no KORLIX merchant account receives customer funds, and no invitation is automatically emailed.

## Client behavior and verification

Portal screens bind to the existing App Studio client account/session scope. Account changes clear private forms, invitations and membership data, close confirmation dialogs, and reject late network results. Child portal screens share access-denied listeners without replacing the parent App Studio callback.

Settings use optimistic portal and source project versions. A failed save leaves entered form values visible. Refreshing or leaving an edited form asks before discarding changes. Publishing, unpublishing and removing access show their consequences before submission. Invitation acceptance is explicit.

Hosted sessions use a single-use, short-lived launch code in the URL fragment. The frontend validates HTTPS, backend origin, portal path and launch-code shape before opening. It navigates in the same browser tab, avoiding asynchronous popup blocking. Launch credentials are never offered for copying or sharing. Public landing URLs do not include query strings or fragments. Invitation codes also use fragments.

Tests cover publish confirmation, draft defaults, source revisions, save conflicts, account changes, explicit invitation acceptance, email/role payloads, private invitation sharing, launch-link validation, and public/session link separation. Existing App Studio build, preview and local export tests remain intact. Portal setup and people screens are checked at 320 px with 200% text in light and dark themes, with phone/desktop captures. All provider and account interactions in tests use fixtures; no real customer portal or invitation is published by the tests.
