"""Bounded stdio client for designated, tool-free local probes."""
import json, pathlib, subprocess, queue, threading, time
BIN=str(pathlib.Path.home()/".local/bin/codex")
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
