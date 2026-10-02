import {fail,id,text,integer,defaults} from './core.mjs';
export const INDUSTRIES = Object.freeze({general:'General business',construction:'Construction & trades',field_service:'Field services',retail:'Retail',hospitality:'Hospitality & food',healthcare:'Care & support services',logistics:'Logistics & delivery',professional:'Professional services',technology:'Technology & remote teams',education:'Education & training',nonprofit:'Nonprofit & volunteers',events:'Events & creative teams'});
export const MEMBER_KINDS=['employee','contractor','freelancer','volunteer','partner'];
export const WORK_MODES=['onsite','field','remote','hybrid'];
export const TASK_STATES=['todo','in_progress','blocked','done','cancelled'];
const choice=(v,options,fallback)=>{const s=v??fallback;if(!options.includes(s))fail('Choose a supported workspace setting.');return s;};
export function businessProfile(p={}){if(!p||typeof p!=='object'||Array.isArray(p))fail('Enter your business profile.');return {industry:choice(p.industry,Object.keys(INDUSTRIES),'general'),work_mode:choice(p.work_mode,WORK_MODES,'hybrid'),description:text(p.description,1000)};}
export function teamProfile(p={}){return {member_kind:choice(p.member_kind,MEMBER_KINDS,'employee'),job_title:text(p.job_title,100),worksite:text(p.worksite,100)};}
export function presetPolicy(industry){return {...defaults,output_unit:({construction:'jobs',field_service:'visits',retail:'orders',hospitality:'tasks',healthcare:'visits',logistics:'deliveries',professional:'deliverables',technology:'tasks',education:'sessions',nonprofit:'activities',events:'tasks'})[industry]||'tasks'};}
export function timestamp(v,{optional=false}={}){if(optional&&(v==null||v===''))return null;if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(v)||!Number.isFinite(Date.parse(v)))fail('Use a date and time with an explicit timezone.');return new Date(v).toISOString();}
export function taskData(p={}){return {title:text(p.title,160,true),details:text(p.details,2000),assignee_id:id(p.assignee_id),priority:choice(p.priority,['low','normal','high','urgent'],'normal'),project:text(p.project,100),worksite:text(p.worksite,100),due_at:timestamp(p.due_at,{optional:true})};}
export function workspacePayload(action,p={}){switch(action){case 'business':return {version:integer(p.version,1,2147483646),name:text(p.name,100,true),profile:businessProfile(p.profile)};
case 'team_profile':return {user_id:id(p.user_id),version:integer(p.version,1,2147483646),...teamProfile(p)};
case 'task_create':return {...taskData(p),request_id:id(p.request_id)};
case 'task_edit':return {...taskData(p),id:id(p.id),version:integer(p.version,1,2147483646)};
case 'task_status':return {id:id(p.id),version:integer(p.version,1,2147483646),status:choice(p.status,TASK_STATES),progress_note:text(p.progress_note,1000)};
default:return null;}}
