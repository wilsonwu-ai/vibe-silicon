/* vibe-silicon -- public demo endpoint.
 *
 *   Justin's PC ──POST /ingest──► Worker ──SSE /stream──► anyone's browser
 *
 * Deliberately outbound-only: the board's host machine POSTs out over HTTPS.
 * Nothing listens on the venue network, so there is no inbound port, no tunnel,
 * and nothing for conference wifi to block. It also means the page survives
 * Wilson's laptop sleeping, changing networks, or leaving the building.
 *
 * Routes
 *   GET  /              the page
 *   POST /ingest        {text} or raw body, Bearer auth. From bridge.py.
 *   GET  /stream        SSE: replay of everything so far, then live
 *   GET  /tail?after=N  polling fallback for when SSE is blocked
 *   POST /reset         clear the buffer (Bearer auth)
 *   GET  /healthz
 */

const MAX_CHARS = 200_000; // a demo, not a database

export class TokenStream {
  constructor(state) {
    this.state = state;
    this.clients = new Set();
    this.buf = '';
    this.startedAt = null;
    this.lastAt = null;
    this.chars = 0;
    this.loaded = this.state.storage.get(['buf', 'startedAt', 'chars']).then((m) => {
      this.buf = m.get('buf') || '';
      this.startedAt = m.get('startedAt') || null;
      this.chars = m.get('chars') || 0;
    });
  }

  async fetch(request) {
    await this.loaded;
    const url = new URL(request.url);

    if (url.pathname === '/do/append') {
      const text = await request.text();
      const src = new URL(request.url).searchParams.get('src') || 'board';
      if (text) {
        this.src = src;
        if (!this.startedAt) this.startedAt = Date.now();
        this.lastAt = Date.now();
        this.buf += text;
        this.chars += text.length;
        // Trim from the front rather than dropping the newest — the tail is
        // what anyone is actually watching.
        if (this.buf.length > MAX_CHARS) this.buf = this.buf.slice(-MAX_CHARS);
        this.broadcast(text);
        await this.state.storage.put({ buf: this.buf, startedAt: this.startedAt, chars: this.chars });
      }
      return json(this.stats());
    }

    if (url.pathname === '/do/reset') {
      this.buf = '';
      this.chars = 0;
      this.startedAt = null;
      this.lastAt = null;
      await this.state.storage.deleteAll();
      this.broadcast(null, 'reset');
      return json({ ok: true });
    }

    if (url.pathname === '/do/tail') {
      const after = Math.max(0, parseInt(url.searchParams.get('after') || '0', 10) || 0);
      return json({ ...this.stats(), text: this.buf.slice(after), at: this.buf.length });
    }

    if (url.pathname === '/do/stats') return json(this.stats());

    if (url.pathname === '/do/stream') {
      const { readable, writable } = new TransformStream();
      const writer = writable.getWriter();
      const enc = new TextEncoder();
      const client = { writer, enc };
      this.clients.add(client);

      // Send everything so far, then stay open for live output. A viewer who
      // arrives mid-demo sees the whole story, not just the next word.
      this.send(client, 'seed', JSON.stringify({ text: this.buf, ...this.stats() }));

      const ping = setInterval(() => this.send(client, 'ping', String(Date.now())), 20_000);
      writer.closed.catch(() => {}).finally(() => {
        clearInterval(ping);
        this.clients.delete(client);
      });

      return new Response(readable, {
        headers: {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache, no-transform',
          connection: 'keep-alive',
          'access-control-allow-origin': '*',
        },
      });
    }

    return new Response('not found', { status: 404 });
  }

  stats() {
    const ms = this.startedAt && this.lastAt ? this.lastAt - this.startedAt : 0;
    return {
      chars: this.chars,
      len: this.buf.length,
      clients: this.clients.size,
      src: this.src || 'board',
      startedAt: this.startedAt,
      lastAt: this.lastAt,
      elapsedMs: ms,
      live: this.lastAt ? Date.now() - this.lastAt < 15_000 : false,
    };
  }

  send(client, event, data) {
    try {
      client.writer.write(client.enc.encode(`event: ${event}\ndata: ${data}\n\n`));
    } catch {
      this.clients.delete(client);
    }
  }

  broadcast(text, event = 'token') {
    const payload = event === 'token' ? JSON.stringify({ text, ...this.stats() }) : '{}';
    for (const c of [...this.clients]) this.send(c, event, payload);
  }
}

function json(o, status = 200) {
  return new Response(JSON.stringify(o), {
    status,
    headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' },
  });
}

function authed(request, env) {
  const h = request.headers.get('authorization') || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : new URL(request.url).searchParams.get('token');
  return t && t === env.INGEST_TOKEN;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const room = url.searchParams.get('room') || 'main';
    const id = env.STREAM.idFromName(room);
    const stub = env.STREAM.get(id);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET,POST,OPTIONS',
          'access-control-allow-headers': 'authorization,content-type',
        },
      });
    }

    if (url.pathname === '/healthz') {
      const r = await stub.fetch('https://do/do/stats');
      return json({ ok: true, room, ...(await r.json()) });
    }

    if (url.pathname === '/ingest' && request.method === 'POST') {
      if (!authed(request, env)) return json({ error: 'unauthorized' }, 401);
      const ct = request.headers.get('content-type') || '';
      let text = '';
      if (ct.includes('application/json')) {
        const body = await request.json().catch(() => ({}));
        text = String(body.text ?? '');
      } else {
        text = await request.text();
      }
      const src = encodeURIComponent(url.searchParams.get('src') || 'board');
      return stub.fetch('https://do/do/append?src=' + src, { method: 'POST', body: text });
    }

    if (url.pathname === '/reset' && request.method === 'POST') {
      if (!authed(request, env)) return json({ error: 'unauthorized' }, 401);
      return stub.fetch('https://do/do/reset', { method: 'POST' });
    }

    if (url.pathname === '/stream') return stub.fetch('https://do/do/stream');
    if (url.pathname === '/tail') return stub.fetch(`https://do/do/tail?after=${url.searchParams.get('after') || 0}`);

    if (url.pathname === '/' || url.pathname === '/index.html') {
      return new Response(PAGE, {
        headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
      });
    }

    return new Response('not found', { status: 404 });
  },
};

/* The replay text is the real, verified output of run_baremetal.c on the host,
 * md5 8e6e99ed83fc476e1a33bc0940ecffa1 -- byte-identical to upstream llama2.c.
 * It plays when the board is not streaming, so the page is never blank, and it
 * is labelled REPLAY on screen. We do not pass off a recording as live. */
const REPLAY = `Once upon a time, there was a little girl named Lily. She loved to play outside in the sun. One day, her mom asked her to teach him a nice way to play in the sun. Lily was so excited to go outside and jump in the sky. \nAs she walked, she saw a tall toy car that was much carrots. The toys asked her to buy some cars and Lily all nicely. The car was curious and said, "What's wrong?" Lily said, "I am sorry, I want to help you." \nThey both ate the cards and toys and had a brilliant, bunnys. They put the car and ate the ball together. Lily was happy that the ball could read`;

const PAGE = `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><title>vibe-silicon &middot; a language model on an FPGA</title>
<style>
:root{--bg:#06080b;--panel:#0e1319;--line:#1d2733;--fg:#eaf2fb;--dim:#8496a9;--lime:#7cff4f;--amber:#ffc247;--cyan:#2ce8d0;
--mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--fg);font-family:var(--sans)}
.wrap{max-width:1100px;margin:0 auto;padding:26px 20px 60px}
h1{font-size:clamp(26px,4.6vw,46px);letter-spacing:-.03em;margin:0 0 6px;font-weight:800}
h1 em{font-style:normal;color:var(--lime)}
.sub{color:var(--dim);font-size:clamp(14px,1.7vw,18px);margin:0 0 22px;line-height:1.5}
.bar{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:18px}
.chip{background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:8px 14px;font-family:var(--mono);font-size:13px;color:var(--dim)}
.chip b{color:var(--fg)}
#status{font-weight:700;letter-spacing:.1em;text-transform:uppercase}
.live{color:var(--lime)}.replay{color:var(--amber)}.wait{color:var(--dim)}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:8px;vertical-align:1px;background:currentColor;box-shadow:0 0 12px currentColor}
@keyframes beat{0%,100%{opacity:.35}50%{opacity:1}}.dot{animation:beat 1.6s ease-in-out infinite}
#out{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:26px 28px;min-height:320px;
font-size:clamp(17px,2.3vw,24px);line-height:1.65;white-space:pre-wrap;word-wrap:break-word}
#cursor{display:inline-block;width:.6em;height:1.1em;background:var(--lime);vertical-align:-.18em;animation:beat 1s steps(2) infinite}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin:20px 0}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px 16px}
.card .k{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--dim);font-weight:700}
.card .v{font-family:var(--mono);font-size:19px;margin-top:6px}
.note{color:var(--dim);font-size:14px;line-height:1.7;margin-top:22px;border-top:1px solid var(--line);padding-top:18px}
.note b{color:var(--fg)}
a{color:var(--cyan)}
footer{margin-top:26px;color:var(--dim);font-size:13px;line-height:1.8;border-top:1px solid var(--line);padding-top:18px}

/* ---- presentation mode: readable from the back of a room ---- */
body.present .wrap{ max-width:1700px; padding:18px 34px 24px }
body.present h1{ font-size:clamp(30px,3.4vw,52px); margin-bottom:4px }
body.present .sub{ font-size:clamp(14px,1.25vw,20px); margin-bottom:14px; max-width:none }
body.present .note{ display:none }
body.present footer{ margin-top:14px; font-size:13px }
body.present .chip{ font-size:15px; padding:9px 16px }
body.present #out{
  font-size:clamp(26px,2.55vw,44px); line-height:1.5;
  min-height:52vh; padding:30px 36px;
}
body.present .card .v{ font-size:30px }
body.present .card .k{ font-size:12px }
body.present #cursor{ width:.55em; height:1.05em }
/* The nios2-terminal banner is EVIDENCE -- it names a physical USB-Blaster and
   proves this is real silicon, not a simulator. Keep it visible, but demote it
   so it does not compete with the model's own words on a projector. */
.sysline{ display:block; font-family:var(--mono); color:var(--dim);
  font-size:.52em; line-height:1.5; opacity:.75 }
.sysline.first{ margin-top:0 }
#presentHint{
  position:fixed; right:14px; bottom:12px; font-size:12px; color:var(--dim);
  font-family:var(--mono); opacity:.55; pointer-events:none;
}
</style></head><body><div class="wrap">
<h1>A language model running on an <em>FPGA</em></h1>
<p class="sub">Karpathy's <code>llama2.c</code> &mdash; math unmodified &mdash; on a Nios&nbsp;II soft core
programmed onto an Intel MAX&nbsp;10. No ARM, no operating system, no filesystem.
The processor did not exist until we configured it into the fabric this afternoon.</p>

<div class="bar">
  <span class="chip" id="status"><span class="dot"></span><span id="statusTxt">connecting</span></span>
  <span class="chip">model <b>stories260K</b> &middot; 292K params</span>
  <span class="chip">board <b>DE10-Lite</b> &middot; MAX 10 10M50</span>
  <span class="chip">weights <b>1,056,540 B</b> &middot; 2.6% of SDRAM</span>
</div>

<div id="out"><span id="text"></span><span id="cursor"></span></div>

<div class="grid">
  <div class="card"><div class="k">characters</div><div class="v" id="mChars">0</div></div>
  <div class="card"><div class="k">elapsed</div><div class="v" id="mTime">0.0 s</div></div>
  <div class="card"><div class="k">chars / sec</div><div class="v" id="mRate">&mdash;</div></div>
  <div class="card"><div class="k">MACs / token</div><div class="v">259,328</div></div>
</div>

<p class="note"><b>What you are looking at.</b> A MAX&nbsp;10 FPGA has no processor. We program one into it &mdash;
Intel's Nios&nbsp;II/f soft core, which exists only as configured logic &mdash; give it the board's 64&nbsp;MB of SDRAM,
and run a 292,000-parameter transformer on it. There is no SD card and no filesystem, so the weights are
compiled into the executable as a C array.<br><br>
<b>We are not claiming to run a large language model on an FPGA.</b> We are running a small one, precisely,
and saying exactly what it is. The Nios&nbsp;II core and its SDRAM controller are Intel's prebuilt design; what we
wrote is the bare-metal port and the measurements.</p>

<footer>
<b>Built at <a href="https://www.sundai.club">Sundai Club</a></b> &mdash; Hack 135, Foundation Models for the Physical World, August&nbsp;9&nbsp;2026<br>
Justin Pacella &middot; <a href="https://www.linkedin.com/in/jtp75/">LinkedIn</a> &middot; <a href="https://github.com/jtp75">@jtp75</a><br>
Wilson Wu &middot; <a href="https://www.linkedin.com/in/wilson1wu/">LinkedIn</a> &middot; <a href="https://github.com/wilsonwu-ai">@wilsonwu-ai</a><br>
Source: <a href="https://github.com/wilsonwu-ai/vibe-silicon">github.com/wilsonwu-ai/vibe-silicon</a> (MIT)
</footer>
<div id="presentHint">P present &middot; F fullscreen</div>
</div>
<script>
var REPLAY = ${JSON.stringify(REPLAY)};
var el = {text:document.getElementById('text'), status:document.getElementById('status'),
          statusTxt:document.getElementById('statusTxt'), chars:document.getElementById('mChars'),
          time:document.getElementById('mTime'), rate:document.getElementById('mRate')};
var live=false, started=null, chars=0, replayTimer=null, at=0;
var lastRx=0, frozenMs=null, srcMode='board';

function setStatus(cls, txt){ el.status.className = 'chip ' + cls; el.statusTxt.textContent = txt; }
function fmt(n){ return n.toLocaleString(); }
function tick(){
  if(!started) return;
  // Freeze the clock once the stream goes quiet, or elapsed keeps growing after
  // generation finished and quietly deflates the chars/sec number on screen.
  if(live && lastRx && Date.now()-lastRx > 3000 && frozenMs===null) frozenMs = lastRx-started;
  var s=(frozenMs!==null ? frozenMs : Date.now()-started)/1000;
  el.time.textContent = s.toFixed(1)+' s';
  el.chars.textContent = fmt(chars);
  el.rate.textContent = s>0.4 ? (chars/s).toFixed(1) : '\\u2014';
}
setInterval(tick, 200);

var rawBuf = '';
function esc(x){ return x.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
// Split nios2-terminal's own chatter from the model's output. The banner stays
// on screen as proof of hardware -- it names a physical USB-Blaster, which a
// simulator cannot do -- just smaller and dimmer so it does not compete.
// NOTE: no regular expressions and no backslash escapes in here. This whole
// page is a JS template literal inside worker.js, and the template literal
// consumes backslashes before the browser sees them. Cost us one broken deploy.
var CR = String.fromCharCode(13), LF = String.fromCharCode(10);
function render(){
  var lines = rawBuf.split(CR + LF).join(LF).split(LF);
  var head = '', body = [], stillHead = true;
  for (var i = 0; i < lines.length; i++){
    var ln = lines[i];
    if (stillHead && ln.indexOf('nios2-terminal:') === 0){
      head += '<span class="sysline' + (head ? '' : ' first') + '">' + esc(ln) + '</span>';
    } else if (stillHead && ln.trim() === ''){
      continue;                      // blank lines between banner and story
    } else {
      stillHead = false;
      body.push(ln);
    }
  }
  el.text.innerHTML = head + esc(body.join(LF));
}
function append(t){
  if(!t) return;
  if(!started) started = Date.now();
  lastRx = Date.now(); frozenMs = null;
  chars += t.length;
  rawBuf += t;
  render();
  window.scrollTo(0, document.body.scrollHeight);
}
function goLive(){
  if(live) return;
  live = true;
  if(replayTimer){ clearInterval(replayTimer); replayTimer=null; }
  rawBuf=''; el.text.innerHTML=''; chars=0; started=Date.now(); frozenMs=null;
  paintSrc();
}
// The page cannot tell where ingested bytes came from, so the bridge declares
// it. Calling replayed output "live from the board" would be a lie we would
// have to defend on stage.
function paintSrc(){
  if(!live) return;
  if(srcMode === 'board') setStatus('live','live from the board');
  else setStatus('replay','streaming \u00b7 recorded run');
}
// Never show a blank page. Until the board streams, play the verified host
// output, clearly labelled -- a recording presented as a recording.
function startReplay(){
  if(live || replayTimer) return;
  setStatus('replay','replay \\u00b7 verified host output');
  rawBuf=''; el.text.innerHTML=''; chars=0; started=Date.now();
  var i=0;
  replayTimer = setInterval(function(){
    if(live){ clearInterval(replayTimer); replayTimer=null; return; }
    if(i>=REPLAY.length){ i=0; rawBuf=''; el.text.innerHTML=''; chars=0; started=Date.now(); return; }
    var n = 1 + Math.floor(Math.random()*3);
    append(REPLAY.slice(i, i+n)); i+=n;
  }, 90);
}

function connect(){
  var es;
  try { es = new EventSource('/stream'); } catch(e){ return pollLoop(); }
  es.addEventListener('seed', function(ev){
    var d = JSON.parse(ev.data);
    at = (d.text||'').length;
    if(d.text){ srcMode = d.src || 'board'; goLive(); rawBuf = d.text; render();
                chars = d.text.length; started = d.startedAt || Date.now();
                lastRx = d.lastAt || Date.now(); paintSrc(); }
    else { startReplay(); }
  });
  es.addEventListener('token', function(ev){
    var d = JSON.parse(ev.data);
    if(d.src) srcMode = d.src;
    goLive(); paintSrc(); append(d.text); at += (d.text||'').length;
  });
  es.addEventListener('reset', function(){ live=false; rawBuf=''; el.text.innerHTML=''; chars=0; at=0; startReplay(); });
  es.onerror = function(){ setStatus('wait','reconnecting'); };
}
// Polling fallback, in case something between here and the edge eats SSE.
function pollLoop(){
  setInterval(function(){
    fetch('/tail?after='+at).then(function(r){return r.json();}).then(function(d){
      if(d.text){ goLive(); append(d.text); at = d.at; }
    }).catch(function(){});
  }, 400);
}
// Presentation mode. Same URL -- ?present=1, or press P. Kept as a class on
// body so nothing about the data path changes; this is purely type size.
function setPresent(on){
  document.body.classList.toggle('present', !!on);
  try{
    var u = new URL(location.href);
    if(on) u.searchParams.set('present','1'); else u.searchParams.delete('present');
    history.replaceState(null,'',u);
  }catch(e){}
}
if(new URLSearchParams(location.search).get('present')==='1') setPresent(true);

document.addEventListener('keydown', function(e){
  if(e.metaKey||e.ctrlKey||e.altKey) return;
  var k=(e.key||'').toLowerCase();
  if(k==='p'){ setPresent(!document.body.classList.contains('present')); }
  if(k==='f'){
    if(document.fullscreenElement) document.exitFullscreen();
    else if(document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
  }
});

connect();
setTimeout(function(){ if(!live) startReplay(); }, 1200);
</script></body></html>`;
