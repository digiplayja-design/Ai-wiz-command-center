# Backend snapshot in the frontend release branch

This directory is a historical source snapshot retained in the frontend branch.
It is not the source for the deployed KORLIX API, and its dependency lockfile does
not describe the running backend. Do not deploy this copy or treat dependency
changes here as a fix for the production API.

The backend deployment source is the `backend/` directory on
`release/k135z-backend-render-20260919` in
[`digiplayja-design/Ai-wiz-command-center`](https://github.com/digiplayja-design/Ai-wiz-command-center).
Backend security fixes, dependency maintenance, tests and database migrations
belong on that branch. The repository-root `server.js` is also a legacy entry
point, not the backend Render service entry point.

The paired frontend release branch is `release/k135z-frontend-20260919`. Its
Render build runs `bash scripts/render_build_option_a_app.sh` and publishes
`website/`, including the Flutter web build at `/app/`. It does not install or
execute the Node packages in this snapshot.

Before a backend release, verify the service's configured branch, root directory
and start command against the current deployment records. Retaining this
snapshot preserves source history; it does not make the snapshot a supported
standalone backend.
