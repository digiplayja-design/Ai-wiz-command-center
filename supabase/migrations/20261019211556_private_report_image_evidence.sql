-- A private review copy, committed atomically with its report. The existing
-- server-only grants/RLS also protect this column; no public storage URL exists.
alter table public.korlix_ai_output_reports
  add column image_evidence jsonb;

alter table public.korlix_ai_output_reports
  add constraint korlix_report_image_evidence_valid check (
    (image_evidence is null and not (report ? 'imageEvidence')) or coalesce((
      jsonb_typeof(image_evidence) = 'object'
      and octet_length(image_evidence::text) <= 700000
      and image_evidence->>'version' = '1'
      and image_evidence->>'mimeType' = 'image/jpeg'
      and jsonb_typeof(image_evidence->'base64') = 'string'
      and image_evidence->>'base64' ~ '^[A-Za-z0-9+/]+={0,2}$'
      and (image_evidence->>'byteLength')::integer between 1 and 524288
      and octet_length(decode(image_evidence->>'base64', 'base64')) = (image_evidence->>'byteLength')::integer
      and (image_evidence->>'width')::integer between 1 and 1280
      and (image_evidence->>'height')::integer between 1 and 1280
      and image_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
      and report->>'contentType' = 'image'
      and report->'imageEvidence' = image_evidence - 'base64'
    ), false)
  );

comment on column public.korlix_ai_output_reports.image_evidence is
  'Private JPEG review copy; no EXIF. Service role only. Deleted with the report/user.';
