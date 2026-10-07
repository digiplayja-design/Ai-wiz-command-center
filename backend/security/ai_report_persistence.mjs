// Durable intake and protected review use the existing server-only database client.
// Never return provider diagnostics, credentials, or report text in an error.
const table = 'korlix_ai_output_reports';
const unavailable = () => Object.assign(new Error('Reports are temporarily unavailable. Please try again later.'), {statusCode:503});
const deadline = () => AbortSignal.timeout(8000);

export async function persistAiReport(database, report) {
  if (!database) throw unavailable();
  try {
    const {error} = await database.from(table).insert({
      id:report.id, user_id:report.userId, report, created_at:report.createdAt,
    }).abortSignal(deadline());
    if (error) throw unavailable();
    return {saved:true};
  } catch { throw unavailable(); }
}

export async function markAiReportNotification(database, id, delivered) {
  try {
    const {error} = await database.from(table).update({
      notification_state:delivered ? 'delivered' : 'failed',
    }).eq('id', id).abortSignal(deadline());
    return !error;
  } catch { return false; }
}

export async function listAiReports(database, limit = 25) {
  if (!database) throw unavailable();
  const boundedLimit = Number.isFinite(limit) ? Math.max(1, Math.min(100, Math.floor(limit))) : 25;
  try {
    const {data, error, count} = await database.from(table)
      .select('report,state,notification_state,created_at,resolved_at', {count:'exact'})
      .order('created_at', {ascending:false}).order('id', {ascending:false})
      .limit(boundedLimit).abortSignal(deadline());
    if (error || !Array.isArray(data)) throw unavailable();
    return {reportCount:count ?? data.length, reports:data.map(row => ({
      ...row.report, reviewState:row.state, notificationState:row.notification_state,
      resolvedAt:row.resolved_at,
    }))};
  } catch { throw unavailable(); }
}
