"""Opt-in live probe: synthetic PNG only, new disposable thread, no tool approvals."""
import json, pathlib, struct, time, zlib, subprocess
from probe_rpc import RPC, BIN
folder = pathlib.Path('.local/attachment-probe').resolve()
folder.mkdir(parents=True, exist_ok=True)
png = folder / 'red.png'
def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
png.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B',64,64,8,2,0,0,0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\0\0'*64)*64)) + chunk(b'IEND', b''))
rpc = RPC(['--stdio'])
try:
    thread = rpc.call('thread/start', {'cwd': str(folder), 'approvalPolicy': 'never'})['thread']['id']
    turn = rpc.call('turn/start', {'threadId': thread, 'input': [{'type':'text','text':'What solid color is this image? Reply with the color name only. Do not use tools.'},{'type':'localImage','path':str(png)}], 'effort':'low'})['turn']['id']
    end = time.monotonic() + 90
    while not any(e.get('method')=='turn/completed' and e.get('params',{}).get('turn',{}).get('id')==turn for e in rpc.events):
        rpc.next(max(.01,end-time.monotonic()))
    history = rpc.call('thread/read', {'threadId':thread,'includeTurns':True})['thread']
    response = '\n'.join(i.get('text','') for t in history.get('turns',[]) if t['id']==turn for i in t.get('items',[]) if i.get('type')=='agentMessage')
    result = {'version':subprocess.check_output([BIN,'--version'],text=True).strip(),'thread':thread,'response':response,'passed':response.strip().lower().strip('.')=='red'}
    (folder/'evidence.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
finally:
    rpc.close()
