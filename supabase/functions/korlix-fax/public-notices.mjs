// The mobile privacy page and the public notice have a matching-content regression test.
const paragraphs = [
  "Fax by Korlix",
  "Privacy policy",
  "Korlix INC operates Fax by Korlix. This notice describes how the mobile apps and fax service use information when you create an account, request a fax line, or send and receive documents.",
  "Your account and mailbox",
  "We use your account email, sign-in information, and a device-specific identifier to authenticate you and manage your fax sessions. When you register, Korlix records your age-range declaration and policy acknowledgments. Your fax workspace is associated with your account.",
  "Documents, numbers and receipts",
  "If you scan paper or choose a PDF, you can preview it before sending. When you send, the service receives your document, its name and the recipient’s fax number. Incoming documents, sender and recipient numbers, page counts, timestamps, delivery status and contacts you choose to save support your mailbox and activity reports.",
  "On Android, the Google ML Kit document scanner processes scanned images on your device. Google receives scanner usage and performance information, including device and installation identifiers, app and operating system versions, and technical details about scanner operations. Google uses these metrics to maintain the scanner and diagnose problems. Google’s ML Kit privacy information",
  "If you choose to dictate a request where supported, your device’s speech-recognition service processes your voice to produce text. You can type the same request instead.",
  "Service providers and recipients",
  "We use Render to host the Korlix registration service, Supabase for account, database and document services, and Telnyx for fax numbers and transmission. The app uses encrypted connections to Korlix services. Fax delivery beyond the carrier follows the recipient’s fax network. When you send a fax, the document goes to the number you select. When you download or share a document or report, the copy is handled by the destination you choose.",
  "Access and retention",
  "We retain fax documents, contacts and delivery records to provide your mailbox and reports. Access to records is tied to your authenticated account. Access to document downloads uses time-limited links. We may retain information as required for legal obligations, resolving disputes, or records held by service providers. Copies already delivered to a fax recipient remain with that recipient.",
  "Privacy and deletion requests",
  "You can request deletion of your Korlix account and associated fax documents, receipts, saved contacts, and sessions. Email support@korlixdeveloper.com from your account email with the subject “Fax account deletion.” In the customer app, you can also open Your account and choose Request account deletion. We may verify ownership to protect the mailbox. Requests for deletion of a shared Korlix account also affect other Korlix apps tied to that account. Korlix processes verified shared-account requests within 72 hours after ownership verification, or sooner when required. Limited transaction, tax, fraud, security, and dispute records may be kept as long as the applicable obligation requires. Backup copies may take longer to expire.",
  "For questions about fax data or the scope of a deletion request, contact support@korlixdeveloper.com."
];

const fullNotice = paragraphs.join('\n\n') + '\n';
const deletionHeading = paragraphs.indexOf('Privacy and deletion requests');
const deletionNotice = ['Fax by Korlix · Korlix INC', ...paragraphs.slice(deletionHeading)].join('\n\n') + '\n';

export function publicNotice(path) {
  if (path === '/privacy') return fullNotice;
  if (path === '/account-deletion') return deletionNotice;
  return null;
}
