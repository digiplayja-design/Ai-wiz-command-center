// KORLIX preparation bounds, not a guarantee of provider eligibility.
export function radiusAreaValid(v,maxMeters=200000) {
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==4||!['label','latitude_micro','longitude_micro','radius_meters'].every(k=>Object.hasOwn(v,k)))return false;
  if(typeof v.label!=='string'||!v.label.length||[...v.label].length>80||v.label.startsWith(' ')||v.label.endsWith(' ')||/[\u0000-\u001f\u007f-\u009f\u2028\u2029<>\p{Cs}]/u.test(v.label))return false;
  return Number.isInteger(v.latitude_micro)&&Math.abs(v.latitude_micro)<=90000000&&Number.isInteger(v.longitude_micro)&&Math.abs(v.longitude_micro)<=180000000&&Number.isInteger(v.radius_meters)&&v.radius_meters>=1000&&v.radius_meters<=maxMeters;
}
export function radiusAreasValid(values,maxMeters=200000) {
  return Array.isArray(values)&&values.length<=10&&values.every(v=>radiusAreaValid(v,maxMeters))&&new Set(values.map(v=>`${v.latitude_micro}:${v.longitude_micro}:${v.radius_meters}`)).size===values.length;
}
