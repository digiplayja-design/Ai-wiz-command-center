# Session loading regression — 7 October 2026

The security release rejected valid Supabase-authenticated sessions whose stable device ID had no matching device row. Released clients sent device IDs on protected requests but omitted them at sign-in and refresh, so the backend registered inferred fallback devices instead. Production requests then returned 403 from `/api/me` and authentication failures across tools.

The correction accepts a verified provider session when only the historical device row is missing. It continues to reject known revoked devices, disabled accounts, device lookup failures, and concurrent revocation. Refresh no longer enrolls an inferred device or consumes another device slot. Fresh sign-in remains the device-enrollment point. Frontend sign-in, signup and refresh must consistently carry the stable device metadata.

The new missing-device checks reproduce failures against the security release and pass with this correction. All 14 authorization checks and 20 existing video/report route checks pass against the corrected backend. The initial audit's synthetic fixtures covered registered devices but missed this released-client compatibility case.

This preserves the existing compatibility model for legacy bearer sessions; a client-supplied device ID is not a cryptographic session binding. RLS, tenant ownership, billing and upload protections are unchanged. No customer rows were changed to recover access.
