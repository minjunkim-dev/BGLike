import json, pathlib, re, struct
p=pathlib.Path(__file__).resolve().parent
read=lambda q:[json.loads(l) for l in q.read_text().splitlines()]
a=read(p/'session/limits/2/frames/frames.jsonl'); b=read(p/'resume-session/resume/1/frames/frames.jsonl')
assert a[0]['party'][0]['weapon']['stats']=={'attack_bonus':1,'damage_bonus':1}
assert all(r['bag']==a[0]['bag'] and r['party']==a[0]['party'] and not r['pause'] for r in a[:10])
assert a[10]['party'][0]['weapon']['stats']=={'attack_bonus':2,'damage_bonus':3} and len(a[10]['bag'])==12
assert a[21]['dialog'] and len(a[21]['bag'])==12
assert not a[23]['dialog'] and a[23]['bag']==a[21]['bag'] and a[23]['party']==a[21]['party']
assert a[-1]['bag']==a[23]['bag'][:1]+a[23]['bag'][2:] and a[-1]['party']==a[23]['party']
for k in ['bag','party','units','props','waiting','preparation']: assert a[-1][k]==b[0][k],k
assert b[0]['preparation'] and b[0]['waiting'] and not b[-1]['preparation'] and not b[-1]['waiting']
for folder in ['session/limits/2','resume-session/resume/1']:
 log=(p/folder/'game.log').read_text(); assert '[NATIVE_CASE_DONE]' in log and not re.search(r'SCRIPT ERROR|^ERROR:',log,re.M)
 for r in read(p/folder/'frames/frames.jsonl'):
  img=p/folder/'frames'/pathlib.Path(r['image']).name
  data=img.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n';w,h=struct.unpack('>II',data[16:24]); assert w>0 and h>0
result={'status':'passed','source_sha':'7d533b636e7db0bd39ac5e82463611ab7921d15e','accepted_pngs':len(a)+len(b),'restore_equal_fields':['bag','party','units','props','waiting','preparation'],'limits_attempt':2,'resume_session':'resume-session','excluded':'original limits attempt1 user interaction; original resume1 harness scene path error','product_changes':False}
(p/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
