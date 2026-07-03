# KORLIX Render Option A Deployment

Goal:

www.korlixdeveloper.com/      -> existing KORLIX static website and policy pages
www.korlixdeveloper.com/app/  -> Flutter web app

Render Static Site settings:

Branch:
build90-integrated-improve-picture

Root Directory:
leave blank

Build Command:
bash scripts/render_build_option_a_app.sh

Publish Directory:
website

Environment variables:

KORLIX_WEB_BASE_HREF=/app/
KORLIX_FLUTTER_CHANNEL=stable

Optional public Supabase web values:

SUPABASE_URL
SUPABASE_ANON_KEY

Do not put backend-only secrets in the static site:

OPENAI_API_KEY
RESEND_API_KEY
SUPABASE_SERVICE_ROLE_KEY

Render rewrite:

Source: /app/*
Destination: /app/index.html
Action: Rewrite

Test URLs:

https://www.korlixdeveloper.com/
https://www.korlixdeveloper.com/privacy-policy.html
https://www.korlixdeveloper.com/support.html
https://www.korlixdeveloper.com/delete-account.html
https://www.korlixdeveloper.com/app/
