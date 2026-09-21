"""Disposable official-protocol probes. Never accesses unrelated conversations."""
import json, pathlib, subprocess, queue, threading, time, uuid, datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
WORK=ROOT/'.local'/('handoff-options-'+str(uuid.uuid4())); WORK.mkdir(parents=True)
BIN=str(pathlib.Path.home()/'.local/bin/codex')
REPORT={'tested_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':subprocess.check_output([BIN,'--version'],text=True).strip(),'checks':{}}
class RPC:
 def __init__(self,args):
  self.p=subprocess.Popen([BIN,'app-server']+args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True);self.q=queue.Queue();self.seq=0;self.events=[]
  def read():
   for line in self.p.stdout:
    try:self.q.put(json.loads(line))
    except ValueError:pass
  threading.Thread(target=read,daemon=True).start()
  try:self.call('initialize',{'clientInfo':{'name':'diorama_handoff_probe','version':'1'},'capabilities':{'experimentalApi':True}})
  except Exception:self.close();raise
  self.write({'method':'initialized','params':{}})
 def write(self,x):self.p.stdin.write(json.dumps(x)+'\n');self.p.stdin.flush()
 def next(self,timeout):
  x=self.q.get(timeout=timeout)
  if 'method' in x and 'id' in x: self.write({'id':x['id'],'error':{'code':-32601,'message':'No client tools or approvals in this tool-free probe'}})
  self.events.append(x);return x
 def call(self,m,p):
  self.seq+=1;i=self.seq;self.write({'id':i,'method':m,'params':p});end=time.monotonic()+30
  while time.monotonic()<end:
   x=self.next(max(.01,end-time.monotonic()))
   if x.get('id')==i and 'method' not in x:
    if 'error' in x:raise RuntimeError(x['error']['message'])
    return x['result']
  raise TimeoutError(m)
 def turn(self,id,text):
  start=len(self.events);r=self.call('turn/start',{'threadId':id,'input':[{'type':'text','text':text}],'effort':'low'});tid=r['turn']['id'];end=time.monotonic()+90
  while not any(e.get('method')=='turn/completed' and e.get('params',{}).get('turn',{}).get('id')==tid for e in self.events[start:]):self.next(max(.01,end-time.monotonic()))
  t=self.call('thread/read',{'threadId':id,'includeTurns':True})['thread']
  return '\n'.join(i.get('text','') for turn in t.get('turns',[]) if turn.get('id')==tid for i in turn.get('items',[]) if i.get('type')=='agentMessage')
 def close(self):
  self.p.terminate()
  try:self.p.wait(timeout=5)
  except subprocess.TimeoutExpired:self.p.kill();self.p.wait()
def check(name,fn):
 try: REPORT['checks'][name]={'ok':True,'result':fn()}
 except Exception as e: REPORT['checks'][name]={'ok':False,'error':type(e).__name__+': '+str(e)}
 print(name, json.dumps(REPORT['checks'][name]),flush=True)
 (ROOT/'evidence/handoff-options.json').write_text(json.dumps(REPORT,indent=2)+'\n')
clients=[];server=None
try:
 a=RPC(['--stdio']);b=RPC(['--stdio']);clients += [a,b]
 source=a.call('thread/start',{'cwd':str(WORK),'threadSource':'user','approvalsReviewer':'user'})['thread']['id'];REPORT['source_id']=source
 check('seed',lambda:{'remembered': 'CEDAR-9281' in a.turn(source,'Disposable test. No tools or file changes. Remember token CEDAR-9281 and reply with it.')})
 check('separate_server_resume_while_owner_open',lambda:b.call('thread/resume',{'threadId':source}) and {'resumed':True})
 fork={}
 def fork_open():
  t=b.call('thread/fork',{'threadId':source,'cwd':str(WORK),'approvalsReviewer':'user'})['thread'];fork['id']=t['id'];REPORT['fork_id']=t['id']
  answer=b.turn(t['id'],'No tools. Repeat the token from the original conversation.')
  return {'distinct_id':t['id']!=source,'remembered': 'CEDAR-9281' in answer,'forkedFromId':t.get('forkedFromId')}
 check('fork_while_owner_open',fork_open)
 check('owner_unsubscribe',lambda:a.call('thread/unsubscribe',{'threadId':source}))
 check('resume_immediately_after_unsubscribe',lambda:b.call('thread/resume',{'threadId':source}) and {'resumed':True})
 a.close()
 def after_exit():
  t=b.call('thread/resume',{'threadId':source})['thread'];answer=b.turn(source,'No tools. Repeat the remembered token, followed by HANDOFF_OK.')
  return {'same_id':t['id']==source,'remembered':'CEDAR-9281' in answer,'new_turn':'HANDOFF_OK' in answer}
 check('resume_after_owner_process_exit',after_exit)
 b.close()
 c=RPC(['--stdio']);clients.append(c)
 def return_original():
  t=c.call('thread/resume',{'threadId':source})['thread'];answer=c.turn(source,'No tools. What marker followed the token in your previous reply? Reply with that marker only.')
  return {'same_id':t['id']==source,'roundtrip_context':'HANDOFF_OK' in answer}
 check('return_to_new_original_client',return_original)
 c.close()
 socket_dir=pathlib.Path('/private/tmp')/('dh-'+uuid.uuid4().hex[:8]);socket_dir.mkdir(mode=0o700)
 sock=str(socket_dir/'server.sock')
 server=subprocess.Popen([BIN,'app-server','--listen','unix://'+sock],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 end=time.monotonic()+15
 while not pathlib.Path(sock).exists() and time.monotonic()<end:time.sleep(.1)
 x=RPC(['proxy','--sock',sock]);y=RPC(['proxy','--sock',sock]);clients += [x,y]
 shared=x.call('thread/start',{'cwd':str(WORK),'threadSource':'user','approvalsReviewer':'user'})['thread']['id'];REPORT['shared_id']=shared
 def shared_test():
  y.call('thread/resume',{'threadId':shared})
  ans=x.turn(shared,'No tools. Reply SHARED_SERVER_FIRST.')
  ans2=y.turn(shared,'No tools. Repeat the marker from the previous assistant reply and add SECOND_CLIENT_OK.')
  return {'second_client_resumed':True,'first_reply':'SHARED_SERVER_FIRST' in ans,'second_remembered':'SHARED_SERVER_FIRST' in ans2,'second_reply':'SECOND_CLIENT_OK' in ans2}
 check('two_clients_same_server',shared_test)
except Exception as e:REPORT['fatal']=type(e).__name__+': '+str(e)
finally:
 for client in clients:
  if client.p.poll() is None:client.close()
 if server and server.poll() is None:
  server.terminate()
  try:server.wait(timeout=5)
  except subprocess.TimeoutExpired:server.kill();server.wait()
 (ROOT/'evidence/handoff-options.json').write_text(json.dumps(REPORT,indent=2)+'\n')
