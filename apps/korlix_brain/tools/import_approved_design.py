"""One-time migration of the approved preview into the bundled native view."""
from pathlib import Path
from lxml import html, etree
import re
import sys

app = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
root = html.fromstring(source.read_text())
style = root.find('style')
script = root.find('script')
js = script.text
root.remove(script)
root.remove(style)
controls = root.xpath('./div[@class="kb-preview-controls"]')[0]
root.remove(controls)
product = root.xpath('.//div[contains(@class,"kb-product")]')[0]
def node(identifier):
    return root.xpath('.//*[@id=$id]', id='cinema-'+identifier)[0]
def text(identifier, value):
    n=node(identifier)
    for c in list(n): n.remove(c)
    n.text=value

replacements={
    'Design preview':'Brain+Voice',
    'BRAIN':'BRAIN+VOICE',
    'Preview ready':'Your brain is ready',
    'Preview only · sample entries stay in this preview':'Your memories. Your voice. Your KORLIX account.',
    'Scripted voice lighting · microphone off':'GPT-6 Astra · Max reasoning',
    'Scripted example · microphone is off':'Rici can make mistakes. Review important information.',
    'Planned inputs: voice, typing, or document upload.':'Say “Rici, remember this…” to save directly. Type or upload for review.',
    'Sample data only · no account connection':'Shared with your KORLIX general voice agent.',
    'This removes only the selected item from this preview.':'This removes the selected item from your shared KORLIX account.',
    'Preview only · no live account was changed':'Saved to your KORLIX account.',
    'Approved in this preview':'Saved to your account',
}
for n in root.iter():
    if n.text and n.text.strip() in replacements: n.text=replacements[n.text.strip()]
    if n.tail and n.tail.strip() in replacements: n.tail=replacements[n.tail.strip()]
for identifier,value in {
 'kb-approve':'Approve & save','kb-training-example':'Dictate behaviors',
 'kb-training-file-example':'Upload file','kb-memory-voice-example':'Dictate memory',
 'kb-memory-file-example':'Upload file','kb-replay-demo':'Start conversation',
 'kb-voice-phase':'Microphone off','kb-talk-review':'Review my last spoken memory',
 'kb-undo-deletion':'Undo last change',
}.items():text(identifier,value)
node('kb-talk-review').set('disabled','')
node('kb-training').set('maxlength','12000');node('kb-memory').set('maxlength','4000')
# Clear all scripted conversation bubbles before any account data is loaded.
bubbles=root.xpath('.//*[contains(concat(" ",normalize-space(@class)," ")," kb-bubble ")]')
parent=bubbles[0].getparent()
for bubble in bubbles:bubble.getparent().remove(bubble)
parent.set('id','cinema-kb-transcript');parent.set('aria-live','polite')
hint=etree.Element('p',{'class':'kb-caption'})
hint.text='Say “Rici, remember this: …” to save a memory or instruction directly. No extra password. Say the command on its own, then tell Rici what to remember.'
parent.addprevious(hint)
for form in ['kb-training-form','kb-memory-form']:
    b=etree.SubElement(node(form),'button',{'type':'button','class':'kb-link','data-stop-dictation':''})
    b.text='Stop dictation'
header=root.xpath('.//header')[0]
for badge in header.xpath('./span[@class="kb-preview"]'):header.remove(badge)
mark=header.xpath('./span[@class="kb-mark"]')[0]
for child in list(mark):mark.remove(child)
etree.SubElement(mark,'img',{'src':'../branding/brain-icon-1024.png','alt':'KORLIX','width':'42','height':'42'})
account=etree.SubElement(header,'div',{'class':'kb-account-actions'})
etree.SubElement(account,'span',{'id':'cinema-kb-account-status','role':'status'}).text='Connecting…'
etree.SubElement(account,'button',{'id':'cinema-kb-refresh','type':'button','class':'kb-link'}).text='Refresh'
etree.SubElement(account,'button',{'id':'cinema-kb-account','type':'button','class':'kb-link'}).text='Account'
banner=etree.SubElement(product,'div',{'class':'kb-live-banner','role':'status'})
etree.SubElement(banner,'button',{'id':'cinema-kb-return-voice','type':'button','class':'kb-link'}).text='Rici conversation active'
etree.SubElement(banner,'button',{'id':'cinema-kb-stop-voice','type':'button','class':'kb-link'}).text='Stop'

js=js.replace("let demoIndex = 0, demoTimer = null, demoDeadline = 0, demoRemaining = 0;","let demoIndex = 3;")
js=js.replace("label:'Listening · animation demo'","label:'Rici is listening'").replace("label:'Thinking · animation demo'","label:'Rici is thinking'").replace("label:'Speaking · animation demo'","label:'Rici is speaking'").replace("label:'Demo complete · microphone off'","label:'Microphone off'")
js=js.replace("const lightningPreview = stage.querySelector('#kb-preview-lightning');","const lightningPreview = document.createElement('button');")
js=js.replace("'Preview ready'","'Your brain is ready'").replace("'Brain activation demo'","'Activating your brain'")
js=js.replace("'Approved in this preview'","'Saved to your account'").replace("title+' in the preview.'","title+' to your account.'")
js=re.sub(r"    stage.querySelector\('#kb-replay-startup'\).*?    if\(typeof IntersectionObserver", "    if(typeof IntersectionObserver",js,flags=re.S)
start=js.index('  function pauseDemo()');end=js.index('  function syncMotion()',start)
js=js[:start]+"  function pauseDemo(){}\n  function scheduleDemo(){}\n  function setPhase(index){demoIndex=index;const phase=phases[index];get('kb-voice-scene').dataset.phase=phase.key;get('kb-voice-phase').textContent=phase.label;updateVoiceLight(0);}\n"+js[end:]
start=js.index("  let training=''");end=js.index('  const resize=',start)
js=js[:start]+(app/'tools/production_interactions.js').read_text()+'\n'+js[end:]
js=js.replace("if(currentScreen!=='home'||performance.now()<music.idleUntil)","if(root.dataset.voiceActive==='true'||currentScreen!=='home'||performance.now()<music.idleUntil)")
js=js.replace("else if(currentScreen==='home')music.idleTimer", "else if(currentScreen==='home'&&root.dataset.voiceActive!=='true')music.idleTimer")
css=style.text+'''
html,body{margin:0;background:#100b1b;color:#fff9e9;min-height:100%;font-family:'KB Rajdhani',sans-serif}
*{box-sizing:border-box}button,input,textarea{font:inherit}button{touch-action:manipulation}button:disabled{opacity:.55;cursor:wait}
#korlix-silent-storm{padding:0!important;max-width:none!important}
#korlix-silent-storm .kb-product{max-width:740px!important;margin:0 auto!important;padding:0!important}
#korlix-silent-storm .kb-app{border:0!important;border-radius:0!important;min-height:100dvh;box-shadow:none!important}
#korlix-silent-storm .kb-head{flex-wrap:wrap;gap:10px}
#korlix-silent-storm .kb-head .kb-account-actions{flex:1 0 100%;justify-content:flex-end}
#korlix-silent-storm .kb-account-actions{display:flex;align-items:center;gap:12px;flex-wrap:wrap;font-size:13px}
#korlix-silent-storm .kb-account-actions button{min-height:44px}
#korlix-silent-storm .kb-live-banner{display:none;position:sticky;bottom:0;background:#241436;border:1px solid #70e8ff;border-radius:12px;padding:8px 14px;z-index:40;justify-content:space-between}
#korlix-silent-storm [data-voice-active="true"]:not([data-screen="talk"]) .kb-live-banner{display:flex}
#korlix-silent-storm .kb-bubble p{white-space:pre-wrap;overflow-wrap:anywhere}
#korlix-silent-storm .kb-status{position:relative;z-index:50;white-space:pre-wrap}
'''
dest=app/'assets/web';dest.mkdir(parents=True,exist_ok=True)
(dest/'app.css').write_text(css)
(dest/'app.js').write_text('\n'.join(line.rstrip() for line in js.splitlines()).rstrip()+'\n')
markup=etree.tostring(root,encoding='unicode',method='html')
for lower,correct in {'fecolormatrix':'feColorMatrix','fecomposite':'feComposite','feflood':'feFlood'}.items():markup=markup.replace('<'+lower,'<'+correct).replace('</'+lower,'</'+correct)
document='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; media-src 'self' blob:; connect-src 'none'; base-uri 'none'; form-action 'none'"><title>KORLIX Brain+Voice</title><link rel="stylesheet" href="app.css"></head><body>'''+markup+'''<script src="lucide.min.js"></script><script src="app.js"></script><script src="icons.js"></script></body></html>'''
(dest/'index.html').write_text(document)
(dest/'icons.js').write_text("if(window.lucide)lucide.createIcons();\n")
print('Imported approved design into',dest)
