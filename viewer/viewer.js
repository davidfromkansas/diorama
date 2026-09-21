const token = location.hash.slice(1) || sessionStorage.getItem('diorama-token');
if (token) sessionStorage.setItem('diorama-token', token);
history.replaceState(null, '', '/');
let data = null, selected = 0, rendered = '', navRendered = '';
const el = (tag, text, className) => { const e = document.createElement(tag); e.textContent = text; if (className) e.className = className; return e; };
function render() {
  const nav = document.getElementById('sources');
  const navSignature = JSON.stringify([selected, data.sources.map(s => [s.label, s.client, s.state])]);
  if (navSignature !== navRendered) {
    navRendered = navSignature; nav.replaceChildren();
    data.sources.forEach((s, i) => { const b = el('button', s.label + '\n' + s.client + ' · ' + s.state, i === selected ? 'selected' : ''); b.onclick = () => { selected = i; rendered = ''; render(); }; nav.append(b); });
  }
  const source = data.sources[selected];
  if (!source) { document.getElementById('metadata').textContent = 'No sources configured. Add an exact transcript path to your manifest.'; return; }
  const signature = JSON.stringify([selected, source, document.getElementById('filter').value]);
  if (signature === rendered) return; rendered = signature;
  const meta = document.getElementById('metadata'); meta.replaceChildren(el('h2', source.label));
  for (const [name, value] of [['Session',source.session_id],['Project',source.project],['Parent agent',source.parent_id],['Last recorded state', source.state],['Method',source.method],['Source',source.path],['Observation', source.error || `${source.bytes_read} bytes read · ${source.malformed} malformed records`]]) meta.append(el('p', name + ': ' + (value || 'Unavailable')));
  meta.append(el('p', source.limitations, 'muted'));
  const entries = document.getElementById('entries'); entries.replaceChildren();
  const filter = document.getElementById('filter').value;
  for (const item of source.entries) {
    if (filter === 'messages' && !['user','assistant'].includes(item.kind)) continue;
    if (filter === 'tools' && !item.kind.startsWith('tool')) continue;
    if (filter === 'event' && item.kind !== 'event') continue;
    const box = el('article',''); box.append(el('div', item.kind.toUpperCase() + ' · ' + (item.timestamp || 'timestamp unavailable'), 'eyebrow'), el('pre', item.text)); entries.append(box);
  }
  if (!entries.children.length) entries.append(el('p','No readable entries yet.'));
}
async function refresh() {
  const status = document.getElementById('connection');
  try {
    const response = await fetch('/api/snapshot', {headers: {Authorization: 'Bearer ' + (token || '')}});
    if (!response.ok) throw new Error(response.status === 401 ? 'Open the full link printed by the server to connect.' : 'HTTP ' + response.status);
    data = await response.json(); render(); status.textContent = 'Connected · ' + new Date().toLocaleTimeString();
  } catch (e) { status.textContent = 'Disconnected · ' + e.message; }
  setTimeout(refresh, 1000);
}
document.getElementById('filter').onchange = () => { if (data) render(); };
refresh();
