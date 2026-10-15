#!/usr/bin/env bash
# Run in Google Cloud Shell as an administrator of the existing korlix-ai project.
# Creates no keys and changes no Play products, prices, releases or app accounts.
set -euo pipefail

for korlix_tool in gcloud python3; do
  command -v "$korlix_tool" >/dev/null || { printf 'Missing command: %s\n' "$korlix_tool" >&2; exit 1; }
done

readonly KORLIX_PROJECT_ID='korlix-ai'
readonly KORLIX_TOPIC='korlix-play-billing'
readonly KORLIX_SUBSCRIPTION='korlix-play-billing-render'
readonly KORLIX_PUSH_ACCOUNT_ID='korlix-play-rtdn'
readonly KORLIX_PUSH_ACCOUNT="${KORLIX_PUSH_ACCOUNT_ID}@${KORLIX_PROJECT_ID}.iam.gserviceaccount.com"
readonly KORLIX_PUSH_URL='https://chee-chai-chee-backend.onrender.com/api/billing/google/notifications'
readonly KORLIX_TOPIC_RESOURCE="projects/${KORLIX_PROJECT_ID}/topics/${KORLIX_TOPIC}"
readonly KORLIX_SUBSCRIPTION_RESOURCE="projects/${KORLIX_PROJECT_ID}/subscriptions/${KORLIX_SUBSCRIPTION}"
KORLIX_SETUP_TMP=$(mktemp -d)
readonly KORLIX_SETUP_TMP
trap 'rm -rf -- "$KORLIX_SETUP_TMP"' EXIT

korlix_gcloud() { gcloud --project="$KORLIX_PROJECT_ID" "$@"; }
korlix_check_subscription() {
  python3 - "$KORLIX_SETUP_TMP/subscription.json" "$KORLIX_TOPIC_RESOURCE" "$KORLIX_PUSH_URL" "$KORLIX_PUSH_ACCOUNT" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    subscription = json.load(stream)
push = subscription.get('pushConfig', {})
identity = push.get('oidcToken', {})
valid = (
    subscription.get('topic') == sys.argv[2]
    and push.get('pushEndpoint') == sys.argv[3]
    and identity.get('audience') == sys.argv[3]
    and identity.get('serviceAccountEmail') == sys.argv[4]
    and 'noWrapper' not in push
    and not subscription.get('filter')
    and not subscription.get('messageTransforms')
    and not subscription.get('expirationPolicy', {}).get('ttl')
    and 'expirationPolicy' in subscription
)
if not valid:
    sys.exit('Existing subscription settings differ. Stopped without replacing them; share this error for review.')
PY
}

printf 'Checking the existing Google Cloud project %s...\n' "$KORLIX_PROJECT_ID"
KORLIX_PROJECT_NUMBER=$(korlix_gcloud projects describe "$KORLIX_PROJECT_ID" --format='value(projectNumber)')
[[ "$KORLIX_PROJECT_NUMBER" =~ ^[0-9]+$ ]] || { printf 'Could not verify the project number.\n' >&2; exit 1; }
readonly KORLIX_PROJECT_NUMBER
readonly KORLIX_PUBSUB_AGENT="service-${KORLIX_PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
korlix_gcloud services enable pubsub.googleapis.com --quiet

# A failed list exits the script: lack of permission must not mean "missing".
KORLIX_EXISTING_ACCOUNT=$(korlix_gcloud iam service-accounts list --filter="email=${KORLIX_PUSH_ACCOUNT}" --format='value(email)')
KORLIX_EXISTING_TOPIC=$(korlix_gcloud pubsub topics list --filter="name=${KORLIX_TOPIC_RESOURCE}" --format='value(name)')
KORLIX_EXISTING_SUBSCRIPTION=$(korlix_gcloud pubsub subscriptions list --filter="name=${KORLIX_SUBSCRIPTION_RESOURCE}" --format='value(name)')

if [[ -n "$KORLIX_EXISTING_ACCOUNT" ]]; then
  [[ "$KORLIX_EXISTING_ACCOUNT" == "$KORLIX_PUSH_ACCOUNT" ]] || exit 1
  korlix_gcloud iam service-accounts describe "$KORLIX_PUSH_ACCOUNT" --format=json > "$KORLIX_SETUP_TMP/account.json"
  python3 - "$KORLIX_SETUP_TMP/account.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    account = json.load(stream)
if account.get('disabled'):
    sys.exit('The existing push service account is disabled. Stopped without changing it.')
PY
fi
if [[ -n "$KORLIX_EXISTING_TOPIC" ]]; then
  [[ "$KORLIX_EXISTING_TOPIC" == "$KORLIX_TOPIC_RESOURCE" ]] || exit 1
  korlix_gcloud pubsub topics describe "$KORLIX_TOPIC" --format=json > "$KORLIX_SETUP_TMP/topic.json"
  python3 - "$KORLIX_SETUP_TMP/topic.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    topic = json.load(stream)
if any(topic.get(field) for field in ('schemaSettings', 'messageTransforms', 'ingestionDataSourceSettings')):
    sys.exit('The existing topic has additional message settings. Stopped without changing them.')
PY
fi
if [[ -n "$KORLIX_EXISTING_SUBSCRIPTION" ]]; then
  [[ "$KORLIX_EXISTING_SUBSCRIPTION" == "$KORLIX_SUBSCRIPTION_RESOURCE" ]] || exit 1
  korlix_gcloud pubsub subscriptions describe "$KORLIX_SUBSCRIPTION" --format=json > "$KORLIX_SETUP_TMP/subscription.json"
  korlix_check_subscription
fi

printf 'Preparing the dedicated notification identity and topic...\n'
if [[ -z "$KORLIX_EXISTING_ACCOUNT" ]]; then
  korlix_gcloud iam service-accounts create "$KORLIX_PUSH_ACCOUNT_ID" \
    --display-name='KORLIX Play notification delivery' \
    --description='OIDC identity for Pub/Sub delivery to the KORLIX Render backend; no Play purchase API access.' --quiet
fi
if [[ -z "$KORLIX_EXISTING_TOPIC" ]]; then
  korlix_gcloud pubsub topics create "$KORLIX_TOPIC" --quiet
fi
korlix_gcloud beta services identity create --service=pubsub.googleapis.com --quiet
korlix_gcloud iam service-accounts add-iam-policy-binding "$KORLIX_PUSH_ACCOUNT" \
  --member="serviceAccount:${KORLIX_PUBSUB_AGENT}" \
  --role=roles/iam.serviceAccountTokenCreator --condition=None --quiet >/dev/null
korlix_gcloud pubsub topics add-iam-policy-binding "$KORLIX_TOPIC" \
  --member='serviceAccount:google-play-developer-notifications@system.gserviceaccount.com' \
  --role=roles/pubsub.publisher --quiet >/dev/null

if [[ -z "$KORLIX_EXISTING_SUBSCRIPTION" ]]; then
  korlix_gcloud pubsub subscriptions create "$KORLIX_SUBSCRIPTION" \
    --topic="$KORLIX_TOPIC_RESOURCE" \
    --push-endpoint="$KORLIX_PUSH_URL" \
    --push-auth-service-account="$KORLIX_PUSH_ACCOUNT" \
    --push-auth-token-audience="$KORLIX_PUSH_URL" \
    --ack-deadline=120 --expiration-period=never \
    --min-retry-delay=10s --max-retry-delay=600s --quiet
fi
korlix_gcloud pubsub subscriptions describe "$KORLIX_SUBSCRIPTION" --format=json > "$KORLIX_SETUP_TMP/subscription.json"
korlix_check_subscription

printf '\nGoogle Cloud notification setup is ready. Delivery still needs a Play Console test.\n'
printf 'In Play Console > Monetization setup:\n'
printf '1. Enable real-time notifications.\n'
printf '2. Topic name: %s\n' "$KORLIX_TOPIC_RESOURCE"
printf '3. Keep "Subscriptions and voided purchases only" selected.\n'
printf '4. Save changes, then send a test notification.\n'
printf 'The Render backend must have these exact non-secret settings:\n'
printf 'KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE=%s\n' "$KORLIX_PUSH_URL"
printf 'KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT=%s\n' "$KORLIX_PUSH_ACCOUNT"
printf 'KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION=%s\n' "$KORLIX_SUBSCRIPTION_RESOURCE"
printf 'Keep new purchases disabled until notification delivery and the signed Android test are ready.\n'
