// Public notice allowlist: exact procurement portals, never arbitrary URL retrieval.
export const GEOGRAPHIES = Object.freeze({
 us:{label:'United States',domains:['sam.gov','a856-cityrecord.nyc.gov','ogs.ny.gov'],coverage:'SAM.gov, NYC City Record and New York State OGS official notices; not a complete US state/local feed.'},
 ca:{label:'Canada',domains:['canadabuys.canada.ca'],coverage:'CanadaBuys public tender notices; search coverage may be incomplete.'},
 uk:{label:'United Kingdom',domains:['find-tender.service.gov.uk','contractsfinder.service.gov.uk'],coverage:'Find a Tender and Contracts Finder public notices; search coverage may be incomplete.'},
 jm:{label:'Jamaica',domains:['gojep.gov.jm','moh.gov.jm'],coverage:'GOJEP and Jamaica Ministry of Health public tender notices. Some GOJEP records require browser access; no complete automated feed.'},
});
export function noticeLink(value){
 let u;try{u=new URL(value);}catch{return null;}
 if(u.protocol!=='https:'||u.username||u.password||u.port)return null;
 const host=u.hostname.replace(/^www\./,'');let m;
 if(host==='sam.gov'&&(m=u.pathname.match(/^\/(?:workspace\/contract\/)?opp\/([a-f\d]{32}|[a-f\d-]{36})\/view\/?$/i)))return `https://sam.gov/opp/${m[1].toLowerCase()}/view`;
 if(host==='a856-cityrecord.nyc.gov'&&/^\/RequestDetail\/\d{11}\/?$/i.test(u.pathname)){u.search='';}
 else if(host==='ogs.ny.gov'&&/^\/(?:rf[qp]-\d+|[\w-]*bid[\w-]*-\d+)\/?$/i.test(u.pathname)){u.search='';}
 else if(host==='canadabuys.canada.ca'&&/^\/(?:en|fr)\/tender-opportunities\/tender-notice\/[\w-]+\/?$/i.test(u.pathname)){u.search='';}
 else if(host==='find-tender.service.gov.uk'&&/^\/Notice\/\d{6}-\d{4}\/?$/i.test(u.pathname)){u.search='';}
 else if(host==='contractsfinder.service.gov.uk'&&/^\/Notice\/[a-f\d-]{36}\/?$/i.test(u.pathname)){u.search='';}
 else if(host==='gojep.gov.jm'&&/^\/epps\/cft\/prepareViewCfTWS\.do$/i.test(u.pathname)&&/^\d+$/.test(u.searchParams.get('resourceId')||'')){u.search='?resourceId='+u.searchParams.get('resourceId');}
 else if(host==='moh.gov.jm'&&/^\/(?:tender|procurement|invitation|request)[\w-]+\/?$/i.test(u.pathname)){u.search='';}
 else return null;
 u.hash='';return u.href;
}
export const geographySources=code=>Object.hasOwn(GEOGRAPHIES,code)?GEOGRAPHIES[code]:GEOGRAPHIES.us;
