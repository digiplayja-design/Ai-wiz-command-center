import { fail, uuid } from './rules.mjs';

const pageSize = 50;

export function reportPeriod(month = new Date().toISOString().slice(0, 7)) {
  if (!/^[1-9]\d{3}-(0[1-9]|1[0-2])$/.test(month) || month > new Date().toISOString().slice(0, 7))
    fail(400, 'Choose the current month or an earlier month.');
  const [year, number] = month.split('-').map(Number);
  return {
    start: new Date(Date.UTC(year, number - 1, 1)).toISOString(),
    end: new Date(Date.UTC(year, number, 1)).toISOString(),
  };
}

export function monthlyUsage(svc, userId, period) {
  return svc.rpc('monthly_usage', { p_user: userId, p_start: period.start, p_end: period.end });
}

export async function activity(svc, userId, params) {
  const period = reportPeriod(params.get('month') ?? undefined);
  const filters = {
    user_id: 'eq.' + userId,
    status: 'in.(delivered,received)',
    and: '(updated_at.gte.' + period.start + ',updated_at.lt.' + period.end + ')',
    select: 'id,direction,sender,recipient,name,status,pages,updated_at',
    order: 'updated_at.desc,id.desc',
    limit: String(pageSize + 1),
  };
  const cursor = params.get('cursor');
  if (cursor !== null) {
    const [time, id, ...rest] = cursor.split('|');
    // Keep Postgres microseconds intact when several receipts share the same millisecond.
    const instant = Date.parse(time);
    if (rest.length || !uuid.test(id) ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(time) ||
        !Number.isFinite(instant) || instant < Date.parse(period.start) || instant >= Date.parse(period.end))
      fail(400, 'Invalid activity page. Reopen the report.');
    filters.or = '(updated_at.lt.' + time + ',and(updated_at.eq.' + time + ',id.lt.' + id + '))';
  }
  const [rows, summary] = await Promise.all([
    svc.db('korlix_fax_documents', filters),
    cursor === null ? monthlyUsage(svc, userId, period) : null,
  ]);
  const items = rows.slice(0, pageSize);
  const last = items.at(-1);
  return {
    ...(summary ? { summary } : {}),
    items,
    next: rows.length > pageSize ? last.updated_at + '|' + last.id : null,
  };
}
