"""Reuse repository QA lifecycle; foreground is allowed only for this user-requested run."""
import importlib.util, json, sys
from pathlib import Path
ROOT=Path('/Volumes/P41_USB4/Developer/worktrees/codex/ability-balance-samples/BGLike')
OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('manual_qa',ROOT/'scripts/manual_qa.py')
qa=importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
original_preflight=qa.preflight
original_front=qa.frontmost_pid
original_launch=qa.launch
active_log=None

def preflight(godot,project,case,log):
    adapted=dict(case)
    adapted['preflight_args']=[*case['args'],*case['preflight_args'],f'--capture-dir={log.parent}/preflight-frames']
    original_preflight(godot,project,adapted,log)

def launch(app,case,log,frames):
    global active_log
    active_log=log
    return original_launch(app,case,log,frames)

def foreground():
    front=original_front()
    if active_log is not None and front in qa.native_pids(Path('/Applications/Godot.app'),active_log):
        report=active_log.parent/'foreground-approved.json'
        if not report.exists(): report.write_text(json.dumps({'allowed':True,'scope':'current native main input QA only','reason':'direct user authorization 2026-10-25','pid':front}))
        return None
    return front
qa.preflight=preflight
qa.launch=launch
qa.frontmost_pid=foreground
if __name__=='__main__': sys.exit(qa.main())
