// Public Esha-specific notices. These routes need no account, cookies or script.
// Keep the data descriptions aligned with the native app and dedicated Esha API.
const POLICY_DATE = 'November 15, 2026';
const SUPPORT = 'support@korlixdeveloper.com';

function page(title, introduction, content) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${title} | Esha by Korlix</title>
<style>
:root{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#392033;background:#fff9f5;font-size:17px;line-height:1.7}
*{box-sizing:border-box}body{margin:0}main{max-width:850px;margin:auto;padding:34px 24px 60px}header{padding-bottom:22px;border-bottom:1px solid #e5cfd7}.brand{font-size:12px;font-weight:800;letter-spacing:.16em;color:#873d5c;margin:0 0 16px}h1{font-family:Georgia,serif;font-weight:400;font-size:clamp(32px,7vw,47px);line-height:1.15;margin:0 0 18px}h2{font-size:23px;line-height:1.35;margin:34px 0 12px}h3{font-size:18px;margin:22px 0 8px}p{margin:12px 0}a{color:#8b2d56;text-underline-offset:3px;overflow-wrap:anywhere}a:focus-visible{outline:3px solid #a83b69;outline-offset:4px;border-radius:2px}nav{display:flex;gap:8px 20px;flex-wrap:wrap;margin-top:16px}nav a{display:inline-flex;align-items:center;min-height:44px}.date{font-size:14px;color:#68515f}ul,ol{padding-left:25px}li{margin-bottom:10px}.notice{padding:17px 20px;background:#f7e5ec;border-left:4px solid #ac4b73;border-radius:0 12px 12px 0}footer{border-top:1px solid #e5cfd7;margin-top:36px;padding-top:20px;font-size:14px}.skip{position:absolute;left:16px;top:-80px;background:#fff;padding:10px}.skip:focus{top:10px}section{scroll-margin-top:18px}@media(max-width:360px){main{padding:25px 18px 45px}h2{font-size:21px}}
</style>
</head>
<body>
<a class="skip" href="#content">Skip to policy</a>
<main>
<header>
<p class="brand">ESHA BY KORLIX</p>
<h1>${title}</h1>
<p class="date">Effective date: ${POLICY_DATE}</p>
<p>${introduction}</p>
<nav aria-label="Esha policies">
<a href="/esha/privacy">Privacy Policy</a>
<a href="/esha/terms">Terms &amp; Membership</a>
<a href="/esha/privacy#deletion">Delete account &amp; data</a>
<a href="mailto:${SUPPORT}">Contact support</a>
</nav>
</header>
<div id="content">${content}</div>
<footer>
<p><strong>Korlix INC</strong><br>7965 N High St, STE 350-41, Columbus, OH 43235, United States</p>
<p>Questions about Esha: <a href="mailto:${SUPPORT}">${SUPPORT}</a></p>
<p>This notice covers the Esha native app. Other Korlix services have their own feature notices and the <a href="https://www.korlixdeveloper.com/privacy-policy.html">shared Korlix Privacy Policy</a> and <a href="https://www.korlixdeveloper.com/terms.html">Terms of Use</a>.</p>
</footer>
</main>
</body>
</html>`;
}

const privacy = page('Privacy Policy',
  'This notice explains how Korlix INC handles information in the independently installed Esha by Korlix app for iPhone, iPad and Android. It covers the features you actually choose to use, including your beauty collection, Korlix account, live AI consultations and store membership.', `
<section aria-labelledby="choices-heading">
<h2 id="choices-heading">Your choices at a glance</h2>
<p class="notice"><strong>New membership purchases and live voice are currently unavailable.</strong> The optional voice description below applies only when that feature is enabled in the app. Reading or accepting this notice does not start a call or enable your microphone.</p>
<ul>
<li>Esha's product catalog, routine builder, vanity, illustrated look studio and consultations require a signed-in account with a freshly server-verified active Esha trial or paid membership. A subscription prompt or local purchase status alone does not unlock these features.</li>
<li>Signing in opens a separate account collection that syncs with Korlix. Any existing device-only guest collection remains separate and is not automatically imported. Saved collections are kept when membership access is paused.</li>
<li>Text consultations send your question and recent conversation to Korlix and OpenAI after your permission. Sharing saved beauty preferences is a separate, optional setting that starts off.</li>
<li>Optional voice, when enabled, shares microphone audio and conversation transcripts with Korlix and OpenAI. Before each call, you choose whether to allow audio sharing; optional deep thinking requires a separate choice and uses its own consultation allowance.</li>
<li>Account sign-in and recovery, purchase restoration, subscription management, legal notices, support and account-deletion requests remain available without an active subscription. Account-specific actions still require sign-in and verification where applicable.</li>
<li>You can request deletion of your shared Korlix account from Esha or by email. A deletion request does not cancel an App Store or Google Play subscription.</li>
</ul>
</section>
<section aria-labelledby="information-heading">
<h2 id="information-heading">Information we process and why</h2>
<h3>Account access</h3>
<p>When you sign up or sign in, your email address and password are sent to Korlix's authentication service. The app does not save your password. Signup records the age range, Terms acceptance, Privacy acknowledgment and, for ages 16–17, parent or guardian permission that you declare. These are your declarations, not independent age verification.</p>
<p>The app sends a randomly generated installation identifier, app label and platform. Korlix associates verified sessions with your account and app to maintain access, renew sessions, sign out and protect account boundaries. Native access and refresh tokens are stored using the device's secure storage.</p>
<h3>Your beauty collection</h3>
<p>Your collection can include favorite and owned-product identifiers, budget and routine preferences, a chosen undertone, saved product edits and illustrated looks. Saved edits retain the selected products, their source links and the price estimates shown when saved. Any existing guest collection stays on the device; it does not grant access without an active, verified membership. Account collections sync to Korlix's database and also keep local copies and drafts so changes can be reconciled when connectivity returns.</p>
<p>Local collection copies use the app's ordinary device storage; they are not stored in the same secure token store and are not represented as end-to-end encrypted. Signing out changes the active collection and removes the active session, but local guest collections and account drafts can remain on that device.</p>
<h3>Text AI consultations</h3>
<p>After you give permission, the question you send and recent messages in that Esha conversation are processed by Korlix and OpenAI to produce the answer. A public product-catalog snapshot is included to ground product suggestions. If you turn on <strong>Share preferences with Esha</strong>, the request also includes your selected beauty preferences, undertone, selected product edit and owned-product identifiers. Leave that setting off to omit saved preferences from future questions; anything you type into a question is still part of that submitted question.</p>
<p>Your AI-sharing permission applies to the current signed-in account in the current app session. You can withdraw it for future requests, and changing accounts requires fresh permission. Declining permission leaves the non-AI collection and catalog features available while your Esha trial or paid membership remains active and verified. Withdrawal does not recall content already sent or stop a request that is already processing. An unresolved request keeps its original submitted context when you explicitly retry it; changing a preference does not rewrite that earlier request.</p>
<p>A pending question, its selected context and request identifier are saved in secure device storage so you can deliberately retry after an interrupted response. The service records request identifiers, a fingerprint of the submitted request, processing/allowance status and completed answers so it can recognize retries and return an existing answer without counting a second completed consultation. An answer can itself contain information from your question. The dedicated native consultation service does not read or write your main Korlix conversation memory.</p>
<p>Do not include passwords, payment-card details or other people's confidential information in questions. Esha provides cosmetic guidance, not diagnosis or medical treatment. Its illustrated looks do not request photos or device location, analyze a face or infer skin tone. Optional microphone use is described below.</p>
<h3>Optional live voice, when enabled</h3>
<p>Live voice is an optional AI conversation feature. When it is enabled and you choose to start a call, your microphone audio and conversation transcripts are processed by Korlix and OpenAI to provide spoken answers, manage the call and account for usage. OpenAI supplies the live voice model; Korlix manages your account, access and session. Voice does not use a camera.</p>
<p><strong>Before each call</strong>, you must explicitly allow audio and conversation sharing. Your device may separately ask for microphone permission; device permission alone does not start a call. Audio-sharing permission is reset when a call ends and when your signed-in account session changes. Resume or Restart requires fresh permission for a new call. Declining voice permission leaves other membership features available while your membership remains active and verified.</p>
<p><strong>Deep thinking during a call is a separate, optional choice that starts off.</strong> If you allow it for that call, relevant conversation text can be sent through Korlix to OpenAI's deep-thinking model, and a completed deep-thinking consultation uses its disclosed allowance. Allowing live audio does not by itself allow deep thinking. The call's transcript can contain information you say aloud even when sharing saved beauty preferences is off.</p>
<p>Pause, Stop or turning off audio sharing turns off the local microphone and asks the service to end the call. Leaving the voice screen, putting the app in the background or changing accounts also stops local audio. The app may wait for the service to confirm closure before allowing another call; turning off the microphone does not recall information already sent. Korlix retains session identifiers, consent choices and duration/allowance status to reconcile usage and interrupted calls. The device's pending-call recovery record contains a request identifier, not an audio recording or transcript. Provider processing and retention are described below.</p>
<h3>Membership and purchases</h3>
<p>Apple or Google handles the store purchase. Korlix receives and verifies product identifiers, transaction or purchase-token references, the account association and trial, renewal, expiry, refund or revocation information needed to supply your Esha membership. We retain the relevant receipt references privately to refresh entitlement status and prevent the same purchase from being attached to another Korlix account. The native app does not collect your full payment-card number through an Esha payment form.</p>
<h3>Reports, support and technical records</h3>
<p>If you choose to report an answer, the report sends the selected answer, its paired question, your chosen reason and any details you enter to Korlix for support and safety review. You review the disclosure before sending. Reports are associated with your verified account and can include app, platform, request and network information. Support messages and account-deletion requests contain the information you provide and the account details needed to handle them.</p>
<p>Korlix and its infrastructure providers process network requests, IP addresses, timestamps, session and transaction identifiers, and diagnostic or security information as needed to deliver the service, protect accounts, reconcile purchases and investigate failures. A request to the server can produce operational records even if an action does not complete.</p>
</section>
<section aria-labelledby="sharing-heading">
<h2 id="sharing-heading">Who receives information</h2>
<ul>
<li><strong>Korlix INC</strong> operates the account, collection, consultation, membership and support services.</li>
<li><strong>Supabase</strong> supports authentication and database storage. <strong>Render</strong> hosts the Korlix backend that processes requests.</li>
<li><strong>OpenAI</strong> receives the consultation content described above to generate answers, including live audio and transcripts when you choose enabled voice, and relevant conversation text for separately permitted deep thinking. Provider processing and retention depend on the service configuration and applicable provider terms; this notice does not promise zero provider retention.</li>
<li><strong>Apple and Google</strong> process purchases and supply transaction/entitlement information under their store terms and privacy policies.</li>
<li>Service providers used for support, security and delivery may process the information needed for those functions. Information may also be handled to meet a legal obligation or protect the service and its users.</li>
</ul>
<p>Manufacturer links open external websites when you choose them. Those sites handle their own browsing and checkout information under their own policies. Cosmetics are not purchased through Esha's membership checkout.</p>
<p>This Esha release does not contain an advertising SDK, and it does not publish your collection or questions to a social feed. The shared Korlix account can also be used in other Korlix apps; using those features is governed by their own notices.</p>
</section>
<section aria-labelledby="retention-heading">
<h2 id="retention-heading">Storage and retention</h2>
<p>Account collections are retained to provide sync until you change or remove them, or the account is deleted. Local copies and drafts can persist separately on your device. Removing a saved routine or look updates the active collection; it does not remove a prior consultation from Korlix's service or recall a request sent to an AI provider.</p>
<p>The initial native release does not apply a scheduled expiry to completed consultation replies retained for replay. You may request account or selected-data deletion as described below. Purchase references and allowance records are retained to manage membership, recognize retries and reconcile store events.</p>
<p>When the Korlix account is actually deleted, its linked Esha collection, purchase-token and consultation records are removed from the active account database. Hash-only records identifying confirmed refunded purchase periods can remain after their account link is removed, to prevent a refunded transaction from granting access again. These records do not contain the raw purchase token or consultation text.</p>
<p>Store records, provider-held information, support/security records and any information that must be retained for a legal or payment-accounting reason may be handled separately from active account data. This notice does not promise a fixed deletion or backup-expiry period. Contact support about the records relevant to your request.</p>
</section>
<section id="deletion" aria-labelledby="deletion-heading">
<h2 id="deletion-heading">Delete your Esha / Korlix account or request data removal</h2>
<p class="notice"><strong>Esha uses your shared Korlix account.</strong> Requesting whole-account deletion affects that account and its associated Korlix services, not just the Esha app. Deleting an account, signing out or uninstalling does not cancel a store subscription.</p>
<ol>
<li><strong>In Esha:</strong> sign in, open <strong>Your beauty space</strong>, then <strong>About your data → Request Korlix account deletion</strong>. Review the shared-account notice and confirm the request.</li>
<li><strong>Outside the app:</strong> email <a href="mailto:${SUPPORT}?subject=Esha%20account%20deletion">${SUPPORT}</a> with the subject <strong>Esha account deletion</strong>. Use your registered email if possible, identify Esha by Korlix and say whether you request whole-account deletion or removal of specified Esha data. Do not send your password or sign-in code.</li>
<li><strong>Stop future renewals:</strong> separately open <strong>Manage subscription</strong> in Esha, or the subscription settings in the Apple or Google account that purchased the membership.</li>
</ol>
<p>Korlix may need to verify that the request belongs to the account holder and clarify its scope. The in-app confirmation acknowledges receipt of your request; it does not mean deletion has already finished. Support can explain any information that must be retained and the status of the request.</p>
<p>While your Esha membership access is active and verified, you can change collection preferences and remove individual saved looks, routines, favorites and owned-product selections in the app. Account-deletion requests, privacy information and support remain available without an active subscription. To request access, correction, a copy of account-held information or removal of specific consultation data, contact the same support address. Local device copies are separate; use your device's app-data controls or remove the app when you want to remove local storage, taking care not to lose records you need.</p>
</section>
<section aria-labelledby="age-heading">
<h2 id="age-heading">Age and account eligibility</h2>
<p>Korlix accounts are for people aged 16 and older. Users aged 16–17 need permission from a parent or guardian. Do not create an account if you do not meet these requirements. Contact support if you believe information from someone under 16 was submitted.</p>
</section>
<section aria-labelledby="updates-heading">
<h2 id="updates-heading">Questions and updates</h2>
<p>Contact <a href="mailto:${SUPPORT}">${SUPPORT}</a> about this policy or your information. We update this notice when Esha's practices change and show the effective date above. New uses requiring permission are presented in the app before the relevant sharing.</p>
</section>`);

const terms = page('Terms & Membership',
  'These terms describe the independently installed Esha by Korlix app and its app-wide store membership, provided by Korlix INC. They supplement the shared Korlix Terms of Use for your Korlix account. Review the actual store offer before subscribing.', `
<section aria-labelledby="service-heading">
<h2 id="service-heading">What Esha provides</h2>
<p class="notice"><strong>New membership purchases and live voice are currently unavailable.</strong> The planned voice and deep-thinking inclusions below apply only when the services are enabled and the actual offer is shown in the app before purchase.</p>
<p>Esha helps you explore makeup, lipstick, lip gloss, lashes, body wash and lotion; build product edits around a budget; and save favorites, owned products, routines and illustrated looks. These features and AI consultations require an eligible signed-in account with a freshly server-verified active Esha trial or paid membership. AI features also require an available service, remaining allowance and your permission to send the relevant content to Korlix and OpenAI. Enabled live voice requires explicit audio-sharing permission for each call; optional deep thinking during that call requires separate permission.</p>
<p>An account opens a separate collection that can sync to Korlix. Any existing device-only guest collection remains separate and is not automatically imported or available for continued use while membership access is locked. Saved collection data is kept when access is paused. Protect your sign-in credentials and use an account you control. Korlix account signup requires age 16 or older; ages 16–17 also require parent or guardian permission.</p>
<p>Account sign-in and recovery, purchase restoration, subscription management, legal notices, support and account-deletion requests remain available without an active subscription. Account-specific actions still require sign-in and verification where applicable.</p>
<p>Review the <a href="/esha/privacy">Esha Privacy Policy</a> for account, collection, AI, purchase, support and deletion details. Permissions for AI sharing are separate from accepting these terms.</p>
</section>
<section aria-labelledby="offer-heading">
<h2 id="offer-heading">The Esha monthly membership</h2>
<p class="notice"><strong>U.S. launch offer: 3 days free for eligible subscribers, then $4.99 USD per month.</strong> Your App Store or Google Play purchase sheet confirms whether the offer is available to you, its local currency and price, taxes where applicable, and the renewal terms before you confirm.</p>
<p>The trial begins only when you confirm an eligible subscription with the store. Installing Esha, creating a Korlix account or viewing this page does not start a trial or charge you. A previously used introductory offer may not be available again. If you are not eligible for a trial, the store shows the applicable paid offer.</p>
<p>The app displays the configured trial and monthly consultation counts before enabling a new purchase. Those stated counts are part of the offer you review; this policy does not replace them with an unspecified unlimited allowance. Purchases remain unavailable while the store product, consultation limits or membership service are being configured.</p>
<p><strong>Planned launch inclusions, once enabled:</strong> the eligible three-day trial includes <strong>5 voice minutes and 2 Sol deep-thinking consultations</strong>; a monthly membership includes <strong>30 voice minutes and 10 Sol deep-thinking consultations</strong> per verified monthly billing period. Voice time and deep-thinking consultations are separate allowances. These planned inclusions do not make voice, consultations or purchases available before the services and actual store offer are ready.</p>
<p>An active, verified Esha trial or paid membership provides access to the product catalog, routine builder, vanity and illustrated look studio, plus its disclosed AI allowances when the relevant services are available. Using all included voice time or consultations does not remove access to those other Esha features while membership remains active and verified. It does not upgrade another Korlix plan or include cosmetic products. Product purchases, tax and shipping are separate.</p>
</section>
<section aria-labelledby="renewal-heading">
<h2 id="renewal-heading">Billing, renewal and cancellation</h2>
<p>After an eligible free trial, the subscription automatically renews monthly at the store's disclosed price unless you cancel under the store's terms. Apple or Google handles billing through the purchasing store account. Regional prices may differ from the U.S. launch price, and the final store confirmation controls the purchase you accept.</p>
<p>Use <strong>Manage subscription</strong> in Esha, or open the subscription settings in the Apple or Google account that purchased the membership, to review renewal details and cancel future billing. For an Apple free trial, cancel at least 24 hours before it ends if you do not want it to renew. Review the store's cancellation screen for when access ends.</p>
<p>Cancellation, account deletion and refunds are different actions. Uninstalling Esha, signing out or requesting deletion of a Korlix account does not cancel a subscription. Cancel through the original store to stop future renewals. A refund is handled under that store's rules and applicable consumer rights; no automatic refund is promised by deleting the app or an answer.</p>
</section>
<section aria-labelledby="restore-heading">
<h2 id="restore-heading">Restore and verify an existing purchase</h2>
<p>Use the same Apple or Google purchasing account and the same Korlix account associated with the Esha purchase, then select <strong>Restore purchases</strong>. Restore checks an existing transaction; it does not start a second subscription or replenish consultations already used in the same period.</p>
<p>App access is restored only after the server verifies an active trial or paid membership for the currently signed-in Korlix account. Esha periodically refreshes that verification; stale or unavailable verification pauses access while preserving saved collection data. Pending approval, refunds, revocations or expiry can also affect access. If a transaction is pending or unverified, use the displayed retry or restore controls instead of purchasing again. Contact <a href="mailto:${SUPPORT}">${SUPPORT}</a> with the store and transaction reference if you need help; never send full payment-card details or passwords.</p>
</section>
<section aria-labelledby="allowance-heading">
<h2 id="allowance-heading">Voice time, consultations and interrupted requests</h2>
<p>The membership screen shows the included trial/monthly voice time and deep-thinking consultation counts and, when available, your remaining allowances and period end. Allowance follows the verified store billing period. Unused time or consultations do not automatically carry into a later period.</p>
<p>When voice is enabled, voice time includes silence and time waiting for answers, as well as speaking and listening. Pause and Stop turn off the microphone and request closure of the current call; Resume starts a new call after closure is confirmed and you give fresh permission. Some time can remain reserved while an interrupted call is being reconciled. A microphone-off indicator does not mean final service usage has already been confirmed.</p>
<p>A submitted consultation reserves one available use while it is processing. A successfully completed consultation uses one allowance unit. If the connection is interrupted, retry the same pending question with its existing request identifier so the service can return a completed result without another completed-use charge. Do not start duplicate questions to recover a missing response.</p>
<p>A pending question can retain the preferences you chose when it was first submitted. Review the sharing disclosure before retrying. A store refund or revoked entitlement may remove access and the corresponding allowance.</p>
</section>
<section aria-labelledby="guidance-heading">
<h2 id="guidance-heading">Product information and AI limitations</h2>
<p>Catalog prices are dated manufacturer snapshots for the described sizes or shades, before tax and shipping. Stock and current prices are not guaranteed. An unknown price is shown for you to check and is excluded from a claimed new-purchase budget total; a product you mark as already owned may have no additional purchase cost in a routine.</p>
<p>Check the manufacturer's current product page, complete ingredients, shade and instructions before buying or using a product. The catalog is limited; it is not a comprehensive market comparison. The color studio uses illustrations and does not predict an exact real-world shade match.</p>
<p>AI answers, including spoken answers when voice is enabled, may be inaccurate, incomplete or unsuitable for you. Review them before acting. Esha gives cosmetic guidance; it does not diagnose a condition, prescribe treatment or guarantee that an ingredient or product is safe for an allergy or skin concern. Consult an appropriate qualified professional for symptoms or reactions. Esha does not provide camera analysis, medical assessment or real-time stock checks.</p>
</section>
<section aria-labelledby="use-heading">
<h2 id="use-heading">Your content and responsible use</h2>
<p>Only submit information that you are entitled to provide. You keep the rights you hold in your content and authorize the processing needed to provide the feature you choose, handle retries and usage, and review reports. Do not submit unlawful content, other people's confidential information or material intended to harass, exploit, defraud or bypass access controls.</p>
<p>You can report a problematic AI answer using its in-app report control. Review the report disclosure and submit only the details needed for review. Korlix may restrict abusive activity or suspend access where necessary to protect users or the service, consistent with applicable rights and the shared Korlix terms.</p>
</section>
<section aria-labelledby="account-heading">
<h2 id="account-heading">Account deletion and support</h2>
<p>Esha uses a shared Korlix account. A whole-account deletion request can affect your account and associated Korlix services. See <a href="/esha/privacy#deletion">Delete account &amp; data</a> for in-app and outside-app request instructions, what happens to Esha data and the need to cancel store renewals separately. A request acknowledgment is not confirmation that deletion has finished.</p>
<p>For support, privacy requests or billing problems, email <a href="mailto:${SUPPORT}">${SUPPORT}</a>. Include Esha by Korlix, your app version, device platform and a description of the problem. Keep passwords, verification codes and payment-card numbers out of support messages.</p>
</section>
<section aria-labelledby="store-heading">
<h2 id="store-heading">Store terms and service changes</h2>
<p>Apple and Google store terms apply to their respective purchases. For the iOS application, review <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple's standard Licensed Application End User License Agreement</a> where it applies. Esha is provided by Korlix INC, not endorsed or operated by Apple or Google.</p>
<p>Available features, verified products and supported app versions may change. We display the current offer before purchase and update this notice when relevant terms change. No statement here limits rights that applicable law does not allow to be excluded.</p>
</section>`);

export function registerEshaPolicyRoutes(app) {
  for (const [path, html] of [['/esha/privacy', privacy], ['/esha/terms', terms]]) {
    app.get(path, (_req, res) => {
      res.set({
        'Cache-Control': 'no-store',
        'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff',
      });
      res.type('html').send(html);
    });
  }
}
