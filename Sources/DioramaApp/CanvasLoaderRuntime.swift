import Foundation

/// Small, dependency-free loader patterns for the isolated HTML document.
/// Author content opts in with data attributes; runtime state is never written to disk.
enum CanvasLoaderRuntime {
    static let content = #"""
    <style>
    [data-canvas-step-marker][hidden]{display:none!important}
    .diorama-loader{display:inline-flex;position:relative;color:var(--blue,var(--accent,#3459d4));flex:none;vertical-align:middle;pointer-events:none}
    .diorama-orbit{width:32px;height:32px;border:1px solid currentColor;border-radius:50%;opacity:.8}
    .diorama-orbit::after{content:"";position:absolute;inset:-3px;border:3px solid transparent;border-top-color:currentColor;border-radius:50%}
    [data-diorama-running="true"] .diorama-orbit::after{animation:diorama-spin 1.8s linear infinite}
    .diorama-dots{gap:3px;margin-right:8px;align-items:center;height:16px}.diorama-dots i{width:4px;height:4px;border-radius:50%;background:currentColor;opacity:.45}
    [data-diorama-running="true"] .diorama-dots i{animation:diorama-dot 1.8s cubic-bezier(.77,0,.175,1) infinite}
    .diorama-dots i:nth-child(2){animation-delay:.2s}.diorama-dots i:nth-child(3){animation-delay:.4s}
    [data-diorama-running="true"][data-canvas-loader="halo"]{position:relative;outline:1px solid var(--blue,var(--accent,#3459d4));outline-offset:3px}
    [data-diorama-running="true"][data-canvas-loader="halo"]::after{content:"";position:absolute;inset:-5px;border:1px solid var(--blue,var(--accent,#3459d4));border-radius:inherit;pointer-events:none;animation:diorama-halo 1.8s cubic-bezier(.77,0,.175,1) infinite}
    .diorama-image{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;width:100%;aspect-ratio:1;max-width:240px;padding:12px;border:1px solid currentColor;border-radius:8px;margin:12px 0}
    .diorama-image i{background:currentColor;opacity:.12;border-radius:3px;animation:diorama-tile 1.8s cubic-bezier(.77,0,.175,1) infinite;animation-delay:calc(var(--tile)*80ms)}
    .diorama-image-label{display:block;font:12px system-ui;color:inherit}.diorama-changed{animation:diorama-reveal 200ms cubic-bezier(.23,1,.32,1)}
    @keyframes diorama-spin{to{transform:rotate(360deg)}}@keyframes diorama-dot{50%{opacity:1;transform:translateY(-2px)}}@keyframes diorama-halo{50%{opacity:.25;transform:scale(1.025)}}@keyframes diorama-tile{50%{opacity:.5;transform:scale(.95)}}@keyframes diorama-reveal{from{opacity:.55}to{opacity:1}}
    @media(prefers-reduced-motion:reduce){.diorama-loader,.diorama-loader *,.diorama-orbit::after,[data-canvas-loader="halo"]::after,.diorama-changed{animation:none!important;transform:none!important}.diorama-dots i{opacity:1}}
    html[data-diorama-hidden="true"] .diorama-loader *,html[data-diorama-hidden="true"] .diorama-orbit::after,html[data-diorama-hidden="true"] [data-canvas-loader="halo"]::after{animation-play-state:paused}
    </style><script>
    (()=>{
      let revealed=false;
      const make=(name)=>{const el=document.createElement('span');el.className='diorama-loader diorama-'+name;el.setAttribute('aria-hidden','true');if(name==='dots'||name==='image'){for(let i=0;i<(name==='image'?16:3);i++){const dot=document.createElement('i');dot.style.setProperty('--tile',String(i%5));el.append(dot)}}return el};
      function update(e){
        if(e.source!==parent||e.data?.kind!=='diorama-execution')return;
        const active=['Working','Submitting'].includes(e.data.phase);
        if(e.data.observationLabel&&e.data.phase==='Working'){const heading=document.getElementById('empty-heading');const message=document.getElementById('empty-message');if(heading)heading.textContent='Agent activity detected…';if(message)message.textContent='Recent task activity was observed. Your first visual summary will appear when the agent saves it.'}const calls=Array.isArray(e.data.activities)?e.data.activities:[];
        // Upgrade only the known empty-state mark, never infer a diagram's ownership.
        const empty=document.querySelector('section[aria-label="Empty canvas"] .mark');
        if(empty&&!empty.dataset.canvasLoader){empty.replaceChildren(make('orbit'));empty.dataset.canvasLoader='orbit';empty.dataset.canvasActivity='any'}
        document.querySelectorAll('[data-canvas-loader]').forEach(el=>{
          const tools=(el.dataset.canvasActivity||'').split(',').map(v=>v.trim());
          const matching=calls.filter(c=>tools.includes(c.tool)&&(!el.dataset.canvasCall||el.dataset.canvasCall===c.id));
          const running=active&&((tools.includes('any')&&el.dataset.canvasLoader!=='image')||matching.length>0);
          el.dataset.dioramaRunning=String(running);
          const type=el.dataset.canvasLoader;
          if(type==='step'){
            let dots=el.querySelector(':scope > .diorama-dots');if(running&&!dots){dots=make('dots');el.prepend(dots)}if(!running)dots?.remove();
            const marker=el.querySelector('[data-canvas-step-marker]');if(marker)marker.hidden=running;
          }
          if(type==='image'){
            let tiles=el.querySelector(':scope > .diorama-image');let label=el.querySelector(':scope > .diorama-image-label');
            // The author supplies an image region only when a specific output is expected.
            if(running&&!el.querySelector('img')&&!tiles){tiles=make('image');el.append(tiles);label=document.createElement('span');label.className='diorama-image-label';label.textContent='Generating image…';el.append(label)}
            if(!running||el.querySelector('img')){tiles?.remove();label?.remove()}
          }
        });
        if(!revealed){revealed=true;for(const id of (e.data.changedSections||[])){const el=document.getElementById(id);if(el?.tagName==='SECTION')el.classList.add('diorama-changed')}}
      }
      addEventListener('message',update);
      document.addEventListener('visibilitychange',()=>document.documentElement.dataset.dioramaHidden=String(document.hidden));
    })();
    </script>
    """#
}
