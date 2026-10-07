import {randomUUID} from 'node:crypto';

export class ReportSubmissionError extends Error {
  constructor(statusCode, code, message, retryAfter) {
    super(message);
    this.statusCode=statusCode; this.code=code; this.retryAfter=retryAfter;
  }
}
const maxBytes=32*1024;
function boundedPayload(value) {
  let encoded;
  try { encoded=JSON.stringify(value); } catch {
    throw new ReportSubmissionError(400,'report_invalid','Invalid report.');
  }
  if (typeof encoded!=='string') throw new ReportSubmissionError(400,'report_invalid','Invalid report.');
  if (Buffer.byteLength(encoded,'utf8')>maxBytes) throw new ReportSubmissionError(413,'report_too_large','Keep the report under 32 KiB.');
}
function text(value,fallback='') {
  if (value===null || value===undefined) return fallback;
  return typeof value==='string'?value:JSON.stringify(value);
}
const line=(value,limit=250)=>text(value).replace(/[\r\n\x00-\x1f\x7f]/g,' ').trim().slice(0,limit);

/** Small bounded per-process limiter; it never evicts active users to allow a bypass. */
export function createReportSubmissionGuard({now=Date.now,idFactory=randomUUID,windowMs=10*60*1000,maxPerWindow=5,maxTrackedUsers=10000}={}) {
  const attempts=new Map();
  let lastSweep=0;
  return function prepareReport({req,user}) {
    if (!user || typeof user.id!=='string' || !user.id) throw new ReportSubmissionError(401,'sign_in_required','Sign in required.');
    const body=req.body??{};
    if (typeof body!=='object' || Array.isArray(body)) throw new ReportSubmissionError(400,'report_invalid','Invalid report.');
    boundedPayload(body);
    const timestamp=now();
    const reportId='korlix_report_'+idFactory();
    const headers=req.headers??{};
    const report={
      id:reportId,reportId,createdAt:new Date(timestamp).toISOString(),
      userId:user.id,userEmail:line(user.email,320),
      contentType:line(body.contentType||body.type||'ai_output',100),
      reason:line(body.reason||'Other',200),
      details:text(body.details||body.message||body.notes),
      prompt:text(body.prompt),outputSummary:text(body.outputSummary||body.output||body.summary),
      contentId:line(body.contentId||body.generationId),
      imageUrl:line(body.imageUrl||body.image_url,2048),
      videoId:line(body.videoId||body.video_id),videoUrl:line(body.videoUrl||body.video_url,2048),
      language:line(body.language,50),appVersion:line(body.appVersion||body.version,100),
      platform:line(body.platform||headers['x-korlix-platform'],100),
      appArea:line(body.appArea||'ai_generated_content_report',100),
      deviceId:line(body.deviceId||body.device_id||headers['x-korlix-device-id']),
      deviceLabel:line(body.deviceLabel||body.device_label||headers['x-korlix-device-label']),
      ip:line(req.ip||req.socket?.remoteAddress,100),userAgent:line(headers['user-agent'],500),
    };
    boundedPayload(report);
    if (timestamp-lastSweep>=windowMs || attempts.size>=maxTrackedUsers) {
      for(const [id,entries] of attempts) {
        const recent=entries.filter(time=>timestamp-time<windowMs);
        if(recent.length) attempts.set(id,recent); else attempts.delete(id);
      }
      lastSweep=timestamp;
    }
    const recent=(attempts.get(user.id)||[]).filter(time=>timestamp-time<windowMs);
    if(recent.length>=maxPerWindow) throw new ReportSubmissionError(429,'report_rate_limit','Too many reports. Please try again later.',Math.max(1,Math.ceil((recent[0]+windowMs-timestamp)/1000)));
    if(!attempts.has(user.id) && attempts.size>=maxTrackedUsers) throw new ReportSubmissionError(503,'report_temporarily_unavailable','Reports are temporarily unavailable. Please try again later.');
    recent.push(timestamp); attempts.set(user.id,recent);
    return report;
  };
}
