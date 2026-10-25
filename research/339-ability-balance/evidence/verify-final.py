import collections,csv,hashlib,json,pathlib,sys
p=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(pathlib.Path('/Users/swifty/.codex/worktrees/terrain-balance-remeasure/BGLike/research/339-ability-balance')))
import run
s=p/'samples-v2';records=json.loads((s/'result.json').read_text())
assert len(records)==60 and {(r['policy'],r['seed']) for r in records}=={(p,n) for p in ['mother','nearest'] for n in range(1,31)}
h=hashlib.sha256((s/'plan.json').read_bytes())
for f in sorted((p/'v2-source').iterdir()):
 if f.is_file():h.update(('research/339-ability-balance/'+f.name).encode()+b'\0'+f.read_bytes())
assert h.hexdigest()==json.loads((s/'inputs.json').read_text())['fingerprint']
read=lambda f:list(csv.DictReader(f.open()))
runs=[];moves=[];sources=[]
for r in records:
 folder=s/r['policy']/str(r['seed']);d=json.loads((folder/'run.json').read_text());run.validate(d,r['exit_code'])
 assert d['reason']==r['reason'] and d['run']==r['seed'] and d['policy']==r['policy']
 log=(folder/'runtime.log').read_text();assert f"DONE code={r['exit_code']} {r['reason']}" in log and not run.ERROR.search(log)
 runs.append(d);moves.extend(d['movement_records']);sources.append({'policy':d['policy'],'seed':d['run'],'path':str(folder.relative_to(p)),'run_sha256':hashlib.sha256((folder/'run.json').read_bytes()).hexdigest()})
for name in ['attempts.csv','streaks.csv','enemy_segments.csv']:
 rows=[]
 for r in records:rows.extend(read(s/r['policy']/str(r['seed'])/name))
 counter=lambda rs:collections.Counter(json.dumps(r,sort_keys=True) for r in rs)
 assert counter(rows)==counter(read(s/'data'/name)),name
attempts=read(s/'data/attempts.csv')
stage3={}
for policy in ['mother','nearest']:
 rows=[r for r in attempts if r['policy']==policy and r['stage']=='3-1'];rounds=[int(r['rounds']) for r in rows]
 stage3[policy]={'attempts':len(rows),'outcomes':dict(collections.Counter(r['result'] for r in rows)),'round_mean':sum(rounds)/len(rounds),'round_max':max(rounds),'spawn_max':max(int(r['spawned']) for r in rows)}
summary={'source_sha':json.loads((s/'inputs.json').read_text())['plan']['source_sha'],'runs':len(records),'attempts':len(attempts),'outcomes':{policy:dict(collections.Counter(r['reason'] for r in runs if r['policy']==policy)) for policy in ['mother','nearest']},'stage3_1':stage3,'movement_total':len(moves),'movement_outcomes':dict(collections.Counter(m['outcome'] for m in moves)),'movement_failures':sum(len(r['movement_failures']) for r in runs),'field_click_failures':sum(len(r['field_click_failures']) for r in runs),'pointer_fallbacks':sum(r['pointer_fallbacks'] for r in runs),'source_fingerprint_verified':h.hexdigest(),'merged_csv_verified':['attempts','streaks','enemy_segments']}
(p/'report-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
(s/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
