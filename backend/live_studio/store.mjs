import {LiveStudioError} from './core.mjs';

export function createLiveStore(database) {
  return {async call(actor, action, id = null, data = {}) {
    if (!database) throw new LiveStudioError('Live Studio storage is unavailable.', 503);
    let r;
    try { r = await database.rpc('korlix_live_studio_v1', {p_actor: actor, p_action: action, p_id: id, p_data: data}); }
    catch { throw new LiveStudioError('Studio status could not be confirmed. Refresh before retrying.', 503); }
    if (r.error) {
      const status = {P0002: 404, '40001': 409, '23505': 409, '54000': 429, '22023': 400, '42501': 403}[r.error.code];
      throw new LiveStudioError(status ? r.error.message : 'Live Studio storage is temporarily unavailable.', status || 503);
    }
    return r.data;
  }};
}
