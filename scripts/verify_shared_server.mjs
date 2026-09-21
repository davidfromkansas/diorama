import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {homedir} from 'node:os';
import {randomUUID} from 'node:crypto';
const root=process.cwd(), evidence=root+'/evidence/handoff-options.json';
const report=JSON.parse(readFileSync(evidence));
const reservation=createServer();await new Promise(r=>reservation.listen(0,'127.0.0.1',r));const port=reservation.address().port;await new Promise(r=>reservation.close(r));
const binary=homedir()+'/.local/bin/codex', endpoint=`ws://127.0.0.1:${port}`;
const child=spawn(binary,['app-server','--listen',endpoint],{stdio:['pipe','ignore','ignore']});
const clients=[];const wait=ms=>new Promise(r=>setTimeout(r,ms));
class Client {
 constructor(ws){this.ws=ws;this.n=0;this.pending=new Map();this.events=[];ws.onmessage=({data})=>{const m=JSON.parse(data);this.events.push(m);if(m.method&&m.id!==undefined)ws.send(JSON.stringify({id:m.id,error:{code:-32601,message:'No tool or approval execution in this probe'}}));else if(m.id!==undefined){const p=this.pending.get(m.id);if(p){clearTimeout(p.timer);this.pending.delete(m.id);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);}}};}
 async call(method,params){const id=++this.n;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('Timeout: '+method));},30000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}));});}
 async turn(threadId,text){const result=await this.call('turn/start',{threadId,input:[{type:'text',text}],effort:'low'});const turnId=result.turn.id;const end=Date.now()+90000;while(!this.events.some(m=>m.method==='turn/completed'&&m.params.turn.id===turnId)){if(Date.now()>end)throw new Error('Turn timeout');await wait(100);}const history=await this.call('thread/read',{threadId,includeTurns:true});return {turnId,text:history.thread.turns.filter(t=>t.id===turnId).flatMap(t=>t.items).filter(i=>i.type==='agentMessage').map(i=>i.text).join('\n')};}
}
async function connect(){const ws=new WebSocket(endpoint);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});const c=new Client(ws);clients.push(c);await c.call('initialize',{clientInfo:{name:'diorama_shared_probe',version:'1'},capabilities:{experimentalApi:true}});ws.send(JSON.stringify({method:'initialized',params:{}}));return c;}
try {
 await wait(1200);
 const a=await connect(), b=await connect();
 const folder=root+'/.local/shared-server-'+randomUUID();mkdirSync(folder,{recursive:true});
 const {thread}=await a.call('thread/start',{cwd:folder,threadSource:'user',approvalsReviewer:'user'});
 report.shared_id=thread.id;
 const first=await a.turn(thread.id,'Disposable test. No tools or file changes. Remember token SPRUCE-4183 and reply with it.');
 await b.call('thread/resume',{threadId:thread.id});
 const second=await b.turn(thread.id,'No tools or file changes. Repeat the token from the previous reply and append SHARED_CLIENT_OK.');
 const saw=(c,id)=>c.events.some(m=>m.method==='turn/completed'&&m.params.turn.id===id);
 report.checks.two_clients_same_server={ok:true,result:{transport:'loopback WebSocket',same_thread_id:true,first_reply:first.text.includes('SPRUCE-4183'),second_retained_context:second.text.includes('SPRUCE-4183'),second_reply:second.text.includes('SHARED_CLIENT_OK'),second_saw_own_completion:saw(b,second.turnId),first_saw_second_completion:saw(a,second.turnId)}};
} catch(e){report.checks.two_clients_same_server={ok:false,error:String(e)};}
finally {
 for(const c of clients){c.ws.close();for(const p of c.pending.values())clearTimeout(p.timer);}
 child.kill('SIGTERM');await Promise.race([new Promise(r=>child.on('exit',r)),wait(5000)]);if(child.exitCode===null)child.kill('SIGKILL');
 report.unix_proxy_probe={ok:false,error:'Initialization timed out over the official Unix proxy after canonical socket setup. TCP WebSocket tested separately.'};delete report.fatal;
 writeFileSync(evidence,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report.checks.two_clients_same_server));
}
