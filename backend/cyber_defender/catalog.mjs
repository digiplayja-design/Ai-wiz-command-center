export const SOURCES = [
 {id:'phishing',title:'FTC · Recognize phishing',url:'https://consumer.ftc.gov/articles/how-recognize-avoid-phishing-scams'},
 {id:'recovery',title:'FTC · If you were scammed',url:'https://consumer.ftc.gov/articles/what-do-if-you-were-scammed'},
 {id:'business',title:'CISA · Secure your business',url:'https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business'},
 {id:'ransomware',title:'CISA · Ransomware response',url:'https://www.cisa.gov/stopransomware/ransomware-guide'},
];
export const HABITS = [
 {id:'mfa',title:'Add a second layer to sign-in',detail:'Enable passkeys or multifactor authentication on email, banking and important accounts. Prefer phishing-resistant options when available.',business:false},
 {id:'passwords',title:'Use unique passwords',detail:'Use a trusted password manager. Replace passwords reused across accounts.',business:false},
 {id:'updates',title:'Keep software up to date',detail:'Turn on automatic updates for your phone, computer, browser and trusted security software.',business:false},
 {id:'backups',title:'Make recovery possible',detail:'Keep a separate backup of important files and check that you can restore one.',business:false},
 {id:'verify',title:'Verify unexpected requests',detail:'Use a known phone number or an app you already trust before sharing information or changing payments.',business:false},
 {id:'recovery',title:'Check account recovery options',detail:'Keep recovery details current and store backup sign-in codes somewhere secure. Do not paste them here.',business:false},
 {id:'sessions',title:'Review signed-in devices',detail:'Check important accounts for unfamiliar sessions and security alerts using their official settings.',business:false},
 {id:'devices',title:'Check device security',detail:'Use the security settings and trusted protection software supplied or recommended by your device provider.',business:false},
 {id:'admins',title:'Separate administrator access',detail:'Give staff only the access they need. Use a separate administrator account for privileged work.',business:true},
 {id:'staff',title:'Give staff a reporting path',detail:'Make it easy to report suspicious messages and regularly practice spotting unusual requests.',business:true},
 {id:'payments',title:'Verify payment changes by callback',detail:'Confirm new bank details or payment instructions with a known contact using a previously trusted number.',business:true},
 {id:'plan',title:'Write a recovery plan',detail:'List your IT, bank and key provider contacts, recovery responsibilities and backup restoration steps.',business:true},
];
const action=(id,title,detail)=>({id,title,detail});
export const CHECK_ACTIONS = [
 action('pause','Pause before responding','Do not use the message’s links, attachments or contact details until you verify the request independently.'),
 action('verify','Use a trusted channel','Open the official app you already use or contact the organization using a number you already know is genuine.'),
 action('report','Keep and report the message','If it appears suspicious, use your email provider’s phishing report option or your organization’s IT reporting process. Keep evidence if money or access was lost.'),
];
export const INCIDENTS = [
 {id:'clicked',title:'I clicked a suspicious link',description:'Take the next step based on what happened.',source:'phishing',actions:[
 action('close','Close the suspicious page','Stop interacting with the page. A click alone does not prove your device or account was compromised.'),
 action('details','Check what you shared or installed','If you entered a password or code, open the shared-password guide. If you installed software or allowed remote access, open the device-warning guide.'),
 action('update','Check your device','Update trusted security software and run its scan if a file downloaded or you suspect malware. Contact your IT team for a work device.'),
 action('watch','Review and report','Check important accounts through their official apps for unfamiliar activity. Report the message through your provider or IT team.') ]},
 {id:'credentials',title:'I shared a password or code',description:'Recover access and review active sessions.',source:'recovery',actions:[
 action('recover','Use the official recovery process','From a device you trust, open the real provider’s app or website. If locked out, use its account recovery steps.'),
 action('password','Replace exposed or reused passwords','Choose a unique password for the affected account and any other account using that password. Prioritize your email account.'),
 action('sessions','Review access and recovery settings','Revoke unfamiliar sessions and connected apps in the provider’s settings. Check recovery details and email forwarding rules for changes.'),
 action('mfa','Strengthen sign-in','Enable passkeys or multifactor authentication. If you shared a one-time code, tell the provider and review recent activity even if your password did not change.'),
 action('notify','Contact the right support team','For work accounts, contact IT promptly. For financial activity, contact your bank through a known number. Keep evidence of unauthorized changes.') ]},
 {id:'money',title:'I sent money or payment details',description:'Contact the payment provider promptly.',source:'recovery',actions:[
 action('contact','Contact your bank or payment provider now','Use a known number from your card, statement or official app. Explain the suspected scam and ask what payment reversal or account protection options are available.'),
 action('evidence','Preserve the payment evidence','Keep transaction references and the original messages. Avoid sending more money, including fees from anyone promising guaranteed recovery.'),
 action('accounts','Review affected accounts','Follow the provider’s steps for exposed card or account details. If a password or code was shared, also use the shared-password guide.'),
 action('report','Find your local reporting service','Use the official consumer protection or cybercrime service in your country. The FTC guidance below includes US reporting options. Refunds are not guaranteed.') ]},
 {id:'device',title:'My device shows a warning',description:'Handle pop-ups, remote access or possible ransomware.',source:'ransomware',actions:[
 action('stop','Stop interacting with the warning','Do not call numbers in pop-ups or install their suggested tools. A browser pop-up alone is not a malware diagnosis.'),
 action('isolate','Contain suspected device compromise','If there are signs of ransomware, malware or unwanted remote access, disconnect the affected device from Wi-Fi and wired networks. Contact your IT team for work equipment.'),
 action('help','Get trusted technical help','Use a separate trusted device to contact IT or the device manufacturer through official support. Avoid factory resets or deleting evidence before getting advice.'),
 action('recover','Plan recovery with trusted support','Follow their instructions for scanning, account recovery and restoring verified backups. Do not reconnect a suspected infected device until your support team says it is ready.') ]},
];
export function catalog(){return {habits:HABITS,incidents:INCIDENTS.map(({actions,...x})=>({...x,steps:actions.length})),sources:SOURCES,reviewedOn:'2026-09-28'};}
