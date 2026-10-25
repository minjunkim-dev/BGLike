"""Replay the existing two autoplay policies with paired, recorded RNG seeds."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from manual_qa import ERROR, git, load_plan


def validate(result, code):
    expected = (code == 0 and result['reason'] == 'graduated'
                or code == 4 and result['reason'].startswith('round cap 60 at ')
                or code == 6 and result['reason'].startswith('attempt cap 10 at '))
    if (not expected or result['exit_code'] != code or result['pointer_fallbacks']
            or result['field_click_failures'] or result['movement_failures']
            or not result['movement_records'] or not all(r['passed'] for r in result['movement_records'])):
        raise ValueError('Invalid autoplay execution; preserve logs and exclude from balance results')


def run_one(engine, output, policy, seed):
    folder = output / policy / str(seed)
    folder.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix='bglike-balance-') as home:
        env = dict(PATH=os.defpath, HOME=home, TMPDIR=home, XDG_DATA_HOME=home + '/data',
                   XDG_CONFIG_HOME=home + '/config', XDG_CACHE_HOME=home + '/cache')
        args = [engine, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT),
                '--fixed-fps', '60', '--resolution', '1280x720', '--script',
                str(Path(__file__).with_name('autoplay.gd')), '--', f'--out={folder}',
                f'--policy={policy}', f'--run={seed}']
        with (folder / 'runtime.log').open('x') as log:
            process = subprocess.run(args, cwd=home, env=env, stdout=log,
                                     stderr=subprocess.STDOUT, timeout=240)
        if ERROR.search((folder / 'runtime.log').read_text(errors='replace')):
            raise ValueError(f'Runtime error: {folder}')
        result = json.loads((folder / 'run.json').read_text())
        validate(result, process.returncode)
        print(f"{policy}/{seed}: {result['reason']}", flush=True)
        return dict(policy=policy, seed=seed, exit_code=process.returncode, reason=result['reason'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--count', type=int, default=30)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.output.exists() or args.output.is_symlink() or output.is_relative_to(ROOT):
        parser.error('Use a new output folder outside the checkout')
    if not 1 <= args.count <= 1000000:
        parser.error('count must be between 1 and 1000000')
    engine = str(Path(args.godot).resolve())
    output.mkdir(parents=True)
    version = subprocess.check_output([engine, '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.official.'):
        raise ValueError('Pinned official Godot required')
    plan = dict(source_sha=git('rev-parse', 'HEAD').decode().strip(),
                inputs=[str(p.relative_to(ROOT)) for p in sorted(Path(__file__).parent.glob('*.py'))],
                cases=[dict(id='balance', script='res://research/339-ability-balance/autoplay.gd',
                            resolution=[1280, 720], timeout=240,
                            acceptance='Two unchanged policies; valid movement; graduation or classified cap',
                            success_marker='DONE code=')])
    plan_path = output / 'plan.json'
    plan_path.write_text(json.dumps(plan, indent=2) + '\n')
    _, fingerprint = load_plan(plan_path)
    (output / 'inputs.json').write_text(json.dumps(dict(plan=plan, fingerprint=fingerprint,
        godot=engine, engine_version=version, seeds=list(range(1, args.count + 1)),
        action_seed='run * 100000 + stage-entry ordinal (zero-based)',
        initiative_seed='run * 100000 + 50000 + stage-entry ordinal (zero-based)',
        policy_source='research/278-balance-stats + movement-postcondition-20261024'), indent=2) + '\n')
    script = Path(__file__).with_name('autoplay.gd')
    with (output / 'parse.log').open('x') as log:
        subprocess.run([engine, '--headless', '--path', str(ROOT), '--script', str(script), '--check-only'],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
    if ERROR.search((output / 'parse.log').read_text()):
        raise ValueError('Autoplay parse error')
    jobs = [(policy, seed) for policy in ('mother', 'nearest') for seed in range(1, args.count + 1)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda job: run_one(engine, output, *job), jobs))
    with (output / 'tables.md').open('x') as report:
        subprocess.run([sys.executable, str(Path(__file__).with_name('aggregate.py')), str(output),
                        str(output / 'data')], stdout=report, check=True)
    (output / 'result.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
