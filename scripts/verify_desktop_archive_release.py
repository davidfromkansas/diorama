"""Explicit user-archived disposable conversation: restore, resume, tool-free reply."""
import datetime, json, pathlib, subprocess
from probe_rpc import RPC, BIN
ROOT=pathlib.Path(__file__).resolve().parents[1]
ID='01a0b6cc-6ea4-7f51-842c-112fe57860db'
r={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'thread_id':ID,'cli_version':subprocess.check_output([BIN,'--version'],text=True).strip(),'desktop_open_evidence':'User reports archiving designated conversation and leaving Desktop open; no Desktop control performed by probe.','prior_held_writer_evidence':'desktop-release-baseline.json'}
c=None
try:
 archived=list((pathlib.Path.home()/'.codex/archived_sessions').glob('*'+ID+'*'))
 r['archived_transcript_confirmed']=len(archived)==1
 assert r['archived_transcript_confirmed'], 'Designated archived transcript not found'
 c=RPC(['--stdio'])
 r['unarchive_same_id']=c.call('thread/unarchive',{'threadId':ID})['thread']['id']==ID
 t=c.call('thread/read',{'threadId':ID,'includeTurns':True})['thread']
 assert t['id']==ID
 assert not any(x.get('status')=='inProgress' for x in t.get('turns',[])), 'Recorded active turn'
 assert c.call('thread/goal/get',{'threadId':ID}).get('goal','unknown') is None, 'Active or unknown goal'
 r['turn_count_before']=len(t.get('turns',[]))
 t=c.call('thread/resume',{'threadId':ID,'approvalsReviewer':'user'})['thread']
 r['resume_same_id']=t['id']==ID
 prompt='Disposable continuation test. Do not use any tools or change any files. Repeat the earlier DESKTOP marker from this conversation and append ARCHIVE_RELEASE_VERIFIED.'
 answer=c.turn(ID,prompt)
 r['assistant_reply']=answer
 r['retained_context']='DESKTOP-CEDAR-8426' in answer
 r['new_marker']='ARCHIVE_RELEASE_VERIFIED' in answer
 ends=[e['params']['turn'] for e in c.events if e.get('method')=='turn/completed']
 r['turn_completed']=bool(ends) and ends[-1].get('status')=='completed'
 if ends:r['turn_id']=ends[-1]['id']
 r['tool_items']=[e.get('params',{}).get('item',{}).get('type') for e in c.events if e.get('method')=='item/started' and e.get('params',{}).get('item',{}).get('type') in ['commandExecution','fileChange','mcpToolCall','dynamicToolCall']]
except Exception as e:r['error']=str(e)
finally:
 if c:c.close();r['probe_connection_closed']=True
 r['scope']='Manual Desktop archive followed by official standalone App Server unarchive/resume and one synthetic prompt. Same ID; no fork, Desktop quit, lock-file changes, or product integration.'
 (ROOT/'evidence/desktop-archive-release.json').write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps(r,indent=2))
