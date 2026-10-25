import sys,json,pathlib,hashlib
root=pathlib.Path('/Users/swifty/.codex/worktrees/terrain-balance-remeasure/BGLike').resolve()
sys.path.insert(0,str(root/'research/339-ability-balance'))
import run
out=pathlib.Path(__file__).parent/'diagnostic2'
out.mkdir()
meta={'source_sha':run.git('rev-parse','HEAD').decode().strip(),'policy':'nearest','seed':25,'timeout':1200,'reason':'Original 240-second wall timeout; unchanged round/attempt caps and RNG policy','initial':'samples/nearest/25','script_sha256':{n:hashlib.sha256((root/'research/339-ability-balance'/n).read_bytes()).hexdigest() for n in ['run.py','autoplay.gd','aggregate.py']}}
(out/'inputs.json').write_text(json.dumps(meta,indent=2))
r=run.run_one('/Applications/Godot.app/Contents/MacOS/Godot',out,'nearest',25,timeout=1200)
(out/'result.json').write_text(json.dumps(r,indent=2))
