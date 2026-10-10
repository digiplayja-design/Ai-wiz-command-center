import QRCode from 'qrcode';
import {fail,text} from './core.mjs';

export const passportUrl = slug => `https://www.korlixdeveloper.com/business-directory/passport.html?business=${encodeURIComponent(slug)}`;
export function directoryPassport(database, environment = process.env) {
  const bookingRoot = (environment.KORLIX_SCHEDULING_PUBLIC_URL || 'https://chee-chai-chee-backend.onrender.com').replace(/\/$/, '');
  async function events(owner) {
    if (!database) return [];
    const {data,error} = await database.from('korlix_schedule_events')
      .select('id,slug,title,duration_minutes,price_cents,currency,state')
      .eq('owner_id',owner).eq('state','published').order('title').limit(100);
    if (error) fail('Your booking pages could not be loaded. Please retry.',503);
    return (data || []).map(e => ({...e,url:`${bookingRoot}/book/${e.slug}`}));
  }
  async function validate(owner, details) {
    if (!details.booking_slug) return;
    if (!(await events(owner)).some(e => e.slug === details.booking_slug))
      fail('Choose one of your published KORLIX 2MEETU booking pages.',409);
  }
  async function enrich(card) {
    const result = {...card,passportUrl:passportUrl(card.slug),booking:null};
    if (!card.details?.booking_slug || !database) return result;
    const {data:business,error} = await database.from('korlix_directory_businesses')
      .select('owner_id').eq('id',card.id).maybeSingle();
    if (error) fail('Booking information could not be checked. Please retry.',503);
    if (business) {
      const match = (await events(business.owner_id)).find(e=>e.slug===card.details.booking_slug);
      if (match) result.booking = {title:match.title,url:match.url,durationMinutes:match.duration_minutes};
    }
    return result;
  }
  async function qr(card) {
    const slug = text(card.slug,120,true);
    return QRCode.toBuffer(passportUrl(slug),{type:'png',width:600,margin:4,errorCorrectionLevel:'M',color:{dark:'#102b4d',light:'#ffffff'}});
  }
  return {events,validate,enrich,qr};
}
