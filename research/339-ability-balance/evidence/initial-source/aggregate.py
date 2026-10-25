"""Issue #278: merge per-run CSVs from autoplay278.gd and print Markdown tables.

Usage: python3 aggregate.py <runs root> <merged csv dir>
"""
import csv
import glob
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

STAGES = [f"{a}-{s}" for a in (1, 2, 3) for s in (1, 2, 3)]
EXTRA = 0.35
POLICIES = ["nearest", "mother"]
NAMES = {"nearest": "A 가까운 적", "mother": "B 엄마 거미 우선"}


def load(root, name):
    rows = []
    for path in sorted(glob.glob(os.path.join(root, "*", "*", name))):
        with open(path, newline="") as f:
            rows.extend(csv.DictReader(f))
    return rows


def num(row, key):
    return float(row[key])


def mean(values):
    return statistics.fmean(values) if values else float("nan")


def pct(part, whole):
    return f"{100 * part / whole:.0f}%" if whole else "-"


def table(header, body):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in body]
    return "\n".join(out)


def quantile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))] if values else float("nan")


def main():
    root, merged = sys.argv[1], sys.argv[2]
    os.makedirs(merged, exist_ok=True)
    attempts = load(root, "attempts.csv")
    streaks = load(root, "streaks.csv")
    segments = load(root, "enemy_segments.csv")
    runs = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(root, "*", "*", "run.json")))]
    for name, rows in (("attempts.csv", attempts), ("streaks.csv", streaks), ("enemy_segments.csv", segments)):
        with open(os.path.join(merged, name), "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
    with open(os.path.join(merged, "runs.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["policy", "run", "exit_code", "reason", "wall_s", "game_s", "pointer_fallbacks", "field_click_failures"])
        for r in runs:
            writer.writerow([r["policy"], r["run"], r["exit_code"], r["reason"], round(r["wall_s"], 1),
                             round(r["game_s"], 1), r["pointer_fallbacks"], len(r["field_click_failures"])])

    out = []
    # 1. run outcomes
    body = []
    for p in POLICIES:
        rs = [r for r in runs if r["policy"] == p]
        if not rs:
            continue
        done = [r for r in rs if r["exit_code"] == 0]
        stops = Counter(r["reason"] for r in rs if r["exit_code"] != 0)
        restarts = Counter()
        for a in attempts:
            if a["policy"] == p and a["result"] == "wipe":
                restarts[a["run"]] += 1
        per_run = [restarts.get(str(r["run"]), 0) for r in rs]
        body.append([NAMES[p], len(rs), f"{len(done)} ({pct(len(done), len(rs))})",
                     ", ".join(f"{k} {v}" for k, v in sorted(stops.items())) or "-",
                     f"{mean(per_run):.2f}", max(per_run), pct(sum(1 for x in per_run if x), len(rs)),
                     sum(r["pointer_fallbacks"] for r in rs), sum(len(r["field_click_failures"]) for r in rs)])
    out.append("### 실행 결과\n\n" + table(
        ["정책", "실행", "졸업", "중단(하네스 상한)", "전멸·막 재시작/실행 평균", "최대", "재시작 1회 이상 실행",
         "포인터 대체 클릭", "클릭 실패"], body))

    # 2. per-stage table
    for p in POLICIES:
        body = []
        for s in STAGES:
            rows = [a for a in attempts if a["policy"] == p and a["stage"] == s]
            if not rows:
                body.append([s] + ["-"] * 13)
                continue
            wins = [a for a in rows if a["result"] == "win"]
            wipes = sum(1 for a in rows if a["result"] == "wipe")
            stops = sum(1 for a in rows if a["result"] == "timeout")
            rounds = [num(a, "rounds") for a in rows]
            hp = [(num(a, "warrior_hp") + num(a, "archer_hp")) / (num(a, "warrior_max") + num(a, "archer_max")) for a in wins]
            downed = sum(1 for a in wins if num(a, "downed") > 0)
            body.append([
                s, len(rows), f"{len(wins)}/{len(rows)} ({pct(len(wins), len(rows))})", f"{wipes} / {stops}",
                f"{mean(rounds):.1f} / {max(rounds):.0f}",
                f"{100 * mean(hp):.0f}%" if hp else "-", pct(downed, len(wins)),
                f"{mean([num(a, 'potions_used') for a in rows]):.2f}",
                f"{mean([num(a, 'potions_warrior') + num(a, 'potions_archer') for a in rows]):.1f}",
                f"{mean([num(a, 'rewards') for a in wins]):.2f}" if wins else "-",
                f"{mean([num(a, 'spawned') for a in rows]):.1f} / {max(num(a, 'spawned') for a in rows):.0f}",
                f"{mean([num(a, 'enemy_time_s') for a in rows]):.0f} / {max(num(a, 'enemy_time_s') for a in rows):.0f}",
                f"{mean([num(a, 'enemy_time_s') / max(1, num(a, 'rounds')) for a in rows]):.1f}",
                f"{max(num(a, 'enemy_segment_max_s') for a in rows):.1f}",
            ])
        out.append(f"### 스테이지별 · {NAMES[p]}\n\n" + table(
            ["스테이지", "시도", "승리", "전멸 / 60라운드 중단", "라운드 평균/최대",
             "승리 시 아군 HP 합", "승리 시 전투 불능 있음", "물약 사용/시도", "끝 물약 보유(2명 합)",
             "받은 보상/승리", "새끼 생성 평균/최대", "적 턴 합계 s 평균/최대", "라운드당 적 턴 s",
             "적 턴 한 번 최대 s"], body))

    # 3. miss streaks
    body = []
    for p in POLICIES:
        for side, label in (("ally", "아군"), ("enemy", "적")):
            rows = [a for a in attempts if a["policy"] == p]
            atk = sum(num(a, f"{side}_attacks") for a in rows)
            miss = sum(num(a, f"{side}_misses") for a in rows)
            lengths = Counter(int(x["length"]) for x in streaks if x["policy"] == p and x["side"] == side)
            per_run = defaultdict(int)
            for a in rows:
                per_run[a["run"]] = max(per_run[a["run"]], int(a[f"{side}_streak_max"]))
            maxes = list(per_run.values())
            if not maxes:
                continue
            hist = " · ".join(f"{k}회 {lengths[k]}" for k in sorted(lengths) if k <= 5)
            longer = sum(v for k, v in lengths.items() if k > 5)
            body.append([NAMES[p], label, int(atk), pct(miss, atk), hist + (f" · 6회 이상 {longer}" if longer else ""),
                         f"{statistics.median(maxes):.0f}", quantile(maxes, 0.9), max(maxes),
                         dict(sorted(Counter(maxes).items()))])
    out.append("### 연속 빗나감\n\n" + table(
        ["정책", "쪽", "공격 굴림", "빗나감 비율", "연속 빗나감 길이별 횟수", "실행별 최장 중앙값", "실행별 최장 90%",
         "최장", "실행별 최장 분포 {길이: 실행 수}"], body))

    # 4. drops vs expectation
    body = []
    for s in STAGES:
        row = [s]
        for p in POLICIES:
            wins = [a for a in attempts if a["policy"] == p and a["stage"] == s and a["result"] == "win"]
            if not wins:
                row += ["-", "-"]
                continue
            n = int(wins[0]["extra_eligible"])
            row += [f"{mean([num(a, 'rewards') for a in wins]):.2f} (승리 {len(wins)})", f"{1 + EXTRA * n:.2f}"]
        body.append(row)
    out.append("### 드랍 실측 · 승리 1회당\n\n" + table(
        ["스테이지", "A 실측", "기대", "B 실측", "기대"], body))
    body = []
    for p in POLICIES:
        done = {str(r["run"]) for r in runs if r["policy"] == p and r["exit_code"] == 0}
        wins = [a for a in attempts if a["policy"] == p and a["result"] == "win" and a["run"] in done]
        total = Counter()
        wins_per_run = Counter()
        first = Counter()
        seen = set()
        kinds = Counter()
        for a in wins:
            total[a["run"]] += int(a["rewards"])
            wins_per_run[a["run"]] += 1
            if (a["run"], a["stage"]) not in seen:  # first clear of each stage = the 9-battle path
                seen.add((a["run"], a["stage"]))
                first[a["run"]] += int(a["rewards"])
            for k in ("weapon", "armor", "potion"):
                kinds[k] += int(a[f"rewards_{k}"])
        act1_potions = Counter()
        for a in wins:
            if a["stage"].startswith("1-"):
                act1_potions[a["run"]] += int(a["rewards_potion"])
        no_potion = sum(1 for r in done if act1_potions[r] == 0)
        f = list(first.values())
        t = list(total.values())
        k = sum(kinds.values())
        if not f:
            continue
        body.append([NAMES[p], len(done), f"{mean(f):.1f} / {min(f)} / {max(f)}", f"{mean(t):.1f} / {max(t)}",
                     f"{mean(list(wins_per_run.values())):.1f}",
                     f"{pct(kinds['weapon'], k)} / {pct(kinds['armor'], k)} / {pct(kinds['potion'], k)}",
                     f"{no_potion}/{len(done)} ({pct(no_potion, len(done))})"])
    out.append("### 드랍 실측 · 졸업한 실행 전체\n\n" + table(
        ["정책", "졸업 실행", "9전투 첫 승리 보상 평균/최소/최대 (기대 13.2 / 9 / 21)",
         "재시작 포함 받은 보상 평균/최대", "실행당 승리 수", "무기/방어구/물약 (기대 29/29/43%)",
         "1막 물약 0개 (기대 약 13%)"], body))

    # 5. enemy single-phase distribution
    body = []
    for p in POLICIES:
        for s in STAGES:
            secs = [float(x["seconds"]) for x in segments if x["policy"] == p and x["stage"] == s]
            if secs:
                body.append([NAMES[p], s, len(secs), f"{statistics.median(secs):.1f}", f"{quantile(secs, 0.9):.1f}",
                             f"{max(secs):.1f}", pct(sum(1 for x in secs if x >= 5), len(secs))])
    out.append("### 적 턴 한 번(아군 차례 사이)의 시간\n\n" + table(
        ["정책", "스테이지", "적 턴 수", "중앙값 s", "90% s", "최대 s", "5초 이상"], body))
    print("\n\n".join(out))


if __name__ == "__main__":
    main()
