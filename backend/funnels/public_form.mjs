import {esc as e, inquiryQuestions, visibleQuestions} from './core.mjs';
import {metaWebsitePolicy,metaWebsiteDisclosure} from './meta_website_consent.mjs';
import {measurementDisclosure} from './conversion_intake.mjs';
import {questionScript} from './question_visibility.mjs';
export const utmFields=['utm_source','utm_medium','utm_campaign','utm_content','utm_term'];
const answerKeys=['answer_q-1','answer_q-2','answer_q-3','answer_q-4'];
const limits={...Object.fromEntries(answerKeys.map(k=>[k,500])),name:160,email:254,phone:60,message:2000,...Object.fromEntries(utmFields.map(k=>[k,120]))};
// Bounded values for redisplay only. Validation always uses the original input.
export const formValues=body=>Object.fromEntries(Object.entries(limits).map(([k,n])=>[k,typeof body?.[k]==='string'?body[k].slice(0,n).replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,''):'']));
const hidden=(name,value)=>`<input type="hidden" name="${e(name)}" value="${e(value)}">`;
const hiddenValues=(values,keys)=>keys.map(k=>hidden(k,values[k]??'')).join('');
const consentText=d=>`I agree that ${e(d.brand)} may contact me about this request.`;
const privacy=d=>d.privacy_url?` <a href="${e(d.privacy_url)}" target="_blank" rel="noopener noreferrer">Privacy policy</a>`:'';
const contactFields=v=>`<label>Name *<input name="name" maxlength="160" autocomplete="name" value="${e(v.name)}" required></label><label>Email *<input type="email" name="email" maxlength="254" autocomplete="email" value="${e(v.email)}" required></label><label>Telephone (optional)<input type="tel" name="phone" maxlength="60" autocomplete="tel" value="${e(v.phone)}"></label>`;
const questionFields=(d,v)=>{
 const active=new Set(visibleQuestions(d.questions,v).map(q=>q.id));
 return inquiryQuestions(d.questions).map(q=>{
  const key='answer_'+q.id,shown=active.has(q.id),required=shown&&q.required?'required':shown?'':'disabled',label=e(q.label)+(q.required?' *':' (optional)');
  const rule=q.show_when,attrs=rule?` data-show-question="${e(rule.question_id)}" data-show-value="${e(rule.equals)}"`:'';
  return `<label data-question-id="${q.id}" data-required="${q.required}"${attrs}${shown?'':' hidden'}>${label}${q.type==='choice'?`<select name="${key}" ${required}><option value="">Choose an answer</option>${q.options.map(o=>`<option value="${e(o)}"${shown&&v[key]===o?' selected':''}>${e(o)}</option>`).join('')}</select>`:`<textarea name="${key}" maxlength="500" ${required}>${e(shown?v[key]:'')}</textarea>`}</label>`;
 }).join('');
};
const requestFields=(d,v)=>`<label>How can we help? (optional)<textarea name="message" maxlength="2000">${e(v.message)}</textarea></label>${questionFields(d,v)}<label class="consent"><input type="checkbox" name="consent" value="yes" required>${consentText(d)}${privacy(d)}</label><p class="note">This does not subscribe you to marketing messages.</p>`;
export const formStyles=`[hidden]{display:none!important}select{display:block;width:100%;max-width:100%;border:1px solid #b8c7d9;border-radius:10px;padding:13px;font:inherit;margin-top:7px;background:#fff;color:#10203b}.form-steps{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:10px;font-size:13px}.form-steps li{border:1px solid #c9d4e0;padding:8px 12px;border-radius:20px;color:#53667c}.form-steps [aria-current=step]{background:#10203b;color:white;border-color:#10203b}.form-actions{display:flex;flex-wrap:wrap;align-items:center;gap:12px}.form-actions .secondary{background:#eef2f7;color:#243951;border:1px solid #c9d4e0}.review-details{background:#f7f9fc;border-radius:14px;padding:18px}.review-details dt{font-size:13px;font-weight:700;color:#53667c;margin-top:12px}.review-details dt:first-child{margin-top:0}.review-details dd{margin:4px 0 0;white-space:pre-wrap}button:focus-visible,a:focus-visible{outline:3px solid #10203b;outline-offset:4px}button:disabled{opacity:.55;cursor:not-allowed}`;
export function renderInquiryForm(d,{action='',stepAction='',token='',utm={},preview=false,step='contact',values={},reviewToken='',error='',measurement=null,measurementConsent=false}={}) {
 const guided=d.form_mode==='guided',v=formValues(values),disabled=preview?'disabled':'';
 const questions=inquiryQuestions(d.questions),conditional=questions.some(q=>q.show_when);
 const active=visibleQuestions(questions,v),answerFields=active.map(q=>'answer_'+q.id);
 const attributes=conditional?' data-conditional-questions':'';
 const enhancement=conditional&&!preview?`<script>${questionScript}</script>`:'';
 const update=conditional?`<div data-update-questions><p class="note">After choosing an answer, update the questions to see any follow-ups. This does not send your inquiry.</p><button type="submit" name="step" value="refresh_questions" formaction="${e(stepAction)}" formnovalidate ${disabled}>Update questions</button></div>`:'';
 const current=guided?['contact','request','review'].indexOf(step):0;
 const progress=guided?`<ol class="form-steps" aria-label="Inquiry progress">${['1 · Contact details','2 · Your request','3 · Review & send'].map((label,i)=>`<li${i===current?' aria-current="step"':''}>${label}</li>`).join('')}</ol>`:'';
 const heading=guided?['Your contact details','Your request','Review your inquiry'][Math.max(current,0)]:d.cta;
 const opening=`${progress}<h2>${e(heading)}</h2><p class="note">${guided?'Your inquiry is sent only after the final review. ':''}Share your details with ${e(d.brand)}. Fields marked * are required.</p>${error?`<p role="alert" class="error">${e(error)}</p>`:''}`;
 const choice=measurement?`<label class="consent"><input type="checkbox" name="measurement_consent" value="yes"${measurementConsent?' checked':''}>${e(measurement.policy_version===metaWebsitePolicy?metaWebsiteDisclosure(d.brand):measurementDisclosure(d.brand,measurement.platform))}${privacy(d)}</label>`:'';
 const savedChoice=measurement&&measurementConsent?hidden('measurement_consent','yes'):'';
 const shared=hidden('token',token)+(measurement?hidden('measurement_token',measurement.token):'')+hiddenValues(utm,utmFields)+`<div class="trap" aria-hidden="true"><label>Website<input name="website" tabindex="-1" autocomplete="off"></label></div>`;
 if(!guided)return `${opening}<form method="post" action="${e(action)}"${attributes}>${shared}${contactFields(v)}${requestFields(d,v)}${choice}${update}<button type="submit" ${disabled}>${e(d.cta)}</button></form>${enhancement}`;
 if(step==='contact')return `${opening}<form method="post" action="${e(stepAction)}">${shared}${savedChoice}${hidden('message',v.message)}${hiddenValues(v,answerFields)}${contactFields(v)}<button type="submit" name="step" value="request" ${disabled}>Continue to request →</button></form>`;
 if(step==='request')return `${opening}<form method="post" action="${e(stepAction)}"${attributes}>${shared}${hiddenValues(v,['name','email','phone'])}${requestFields(d,v)}${choice}${update}<div class="form-actions"><button class="secondary" type="submit" name="step" value="edit_contact" formnovalidate ${disabled}>Back to contact details</button><button type="submit" name="step" value="review" ${disabled}>Review inquiry →</button></div></form>${enhancement}`;
 return `${opening}<dl class="review-details">${[['Name',v.name],['Email',v.email],['Telephone',v.phone||'Not provided'],['Your request',v.message||'No message provided'],...active.map(q=>[q.label,v['answer_'+q.id]||'Not provided'])].map(([label,value])=>`<dt>${e(label)}</dt><dd>${e(value)}</dd>`).join('')}</dl><p class="consent">You agreed: ${consentText(d)}${privacy(d)}</p><p class="note">This does not subscribe you to marketing messages. Press “${e(d.cta)}” to send this inquiry.</p>${measurement?`<p class="note">Advertising measurement: ${measurementConsent?'Allowed':'Not allowed'}. ${e(measurement.policy_version===metaWebsitePolicy?metaWebsiteDisclosure(d.brand):measurementDisclosure(d.brand,measurement.platform))}</p>`:''}<form method="post" action="${e(action)}">${shared}${savedChoice}${hiddenValues(v,['name','email','phone','message',...answerFields])}${hidden('consent','yes')}${hidden('review_token',reviewToken)}<div class="form-actions"><button class="secondary" type="submit" name="step" value="edit_contact" formaction="${e(stepAction)}" formnovalidate ${disabled}>Edit contact details</button><button class="secondary" type="submit" name="step" value="edit_request" formaction="${e(stepAction)}" formnovalidate ${disabled}>Edit request</button><button type="submit" ${disabled}>${e(d.cta)}</button></div></form>`;
}
