import csv, hashlib, json, pathlib, shutil, subprocess, sys
p=pathlib.Path(__file__).resolve().parent
root=pathlib.Path('/Users/swifty/.codex/worktrees/terrain-balance-remeasure/BGLike').resolve()
sys.path.insert(0,str(root/'research/339-ability-balance'))
import run
out=p/'final';out.mkdir()
sources=[];results=[];moves=[]
for policy in ['mother','nearest']:
 for seed in range(1,31):
  src=p/('retry25' if (policy,seed)==('nearest',25) else 'samples')/policy/str(seed)
  r=json.loads((src/'run.json').read_text());run.validate(r,r['exit_code'])
  assert (r['policy'],r['run'])==(policy,seed)
  assert not run.ERROR.search((src/'runtime.log').read_text())
  shutil.copytree(src,out/policy/str(seed));sources.append({'policy':policy,'seed':seed,'source':str(src.relative_to(p)),'run_sha256':hashlib.sha256((src/'run.json').read_bytes()).hexdigest()});results.append(r);moves.extend(r['movement_records'])
a=p/'samples/nearest/25';b=p/'retry25/nearest/25'
read=lambda f:list(csv.DictReader(f.open()))
x=read(a/'attempts.csv');y=read(b/'attempts.csv')
# Fixed-fps simulated times are recorded, but gameplay-prefix identity excludes timing.
clean=lambda rows:[{k:v for k,v in row.items() if not k.endswith('_s')} for row in rows]
assert clean(x)==clean(y[:len(x)])
u=json.loads((a/'run.json').read_text())['movement_records'];v=json.loads((b/'run.json').read_text())['movement_records'];assert u==v[:len(u)]
(out/'sources.json').write_text(json.dumps({'sources':sources,'excluded':'samples/nearest/25 wall timeout240; pilot excluded','retry_prefix_equal':{'completed_attempts':len(x),'movement_records':len(u)},'source_sha':run.git('rev-parse','HEAD').decode().strip()},indent=2)+'\n')
with (out/'tables.md').open('w') as f: subprocess.run([sys.executable,str(root/'research/339-ability-balance/aggregate.py'),str(out),str(out/'data')],stdout=f,check=True)
from collections import Counter
summary={'runs':len(results),'attempts':len(read(out/'data/attempts.csv')),'outcomes':{policy:dict(Counter(r['reason'] for r in results if r['policy']==policy)) for policy in ['mother','nearest']},'movement_total':len(moves),'movement_outcomes':dict(Counter(m['outcome'] for m in moves)),'movement_failures':sum(len(r['movement_failures']) for r in results),'field_click_failures':sum(len(r['field_click_failures']) for r in results),'pointer_fallbacks':sum(r['pointer_fallbacks'] for r in results)}
(out/'result.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
