#!/usr/bin/env python3
"""simulate.gd 결과(JSON Lines) 집계.

    python3 client/tools/analyze_sim.py exp1.jsonl exp2.jsonl ...
"""
import json
import statistics
import sys
from collections import Counter, defaultdict

NAMES = {
    1: "1. 둘 다 공격형",
    2: "2. 둘 다 방어형",
    3: "3. 매 판 각자 무작위 성향",
    4: "4. 4×4 채울 때까지 돌만 + 무작위 성향",
}


def pct(n, total):
    return f"{100 * n / total:5.1f}%" if total else "  -  "


def summarize(rows):
    n = len(rows)
    winners = Counter(r["winner"] for r in rows)
    turns = [r["turns"] for r in rows]
    lines = sum(r["black_stats"]["lines"] + r["white_stats"]["lines"] for r in rows)
    places = sum(r["black_stats"]["places"] + r["white_stats"]["places"] for r in rows)
    line_fives = sum(r["black_stats"]["line_fives"] + r["white_stats"]["line_fives"] for r in rows)
    cuts = sum(r["black_stats"]["cuts"] + r["white_stats"]["cuts"] for r in rows)
    blocks = sum(r["black_stats"]["blocks"] + r["white_stats"]["blocks"] for r in rows)
    win_kinds = Counter(r["win_kind"] for r in rows if r["winner"] != "draw")
    first_lines = [r["first_line_turn"] for r in rows if r["first_line_turn"] >= 0]
    cells = [r["width"] * r["height"] for r in rows]
    out = []
    out.append(f"  판 수 {n}")
    out.append(f"  흑 승 {pct(winners['black'], n)}  백 승 {pct(winners['white'], n)}  무승부 {pct(winners['draw'], n)}")
    out.append(
        f"  게임 길이(총 수) 평균 {statistics.mean(turns):.1f}  중앙값 {statistics.median(turns):.0f}"
        f"  최소 {min(turns)}  최대 {max(turns)}"
    )
    out.append(f"  행동 비율: 돌 놓기 {pct(places, places + lines)}  줄 긋기 {pct(lines, places + lines)}")
    if first_lines:
        out.append(f"  첫 줄 긋기 시점(수) 평균 {statistics.mean(first_lines):.1f}")
    out.append(f"  최종 판 크기(칸 수) 평균 {statistics.mean(cells):.0f}  최대 {max(cells)}")
    out.append(
        f"  승리 방식: 착수로 5목 {win_kinds['placement']}판, 줄로 만든 5목 {win_kinds['line_five']}판"
    )
    early = sum(1 for r in rows if 17 <= r["turns"] <= 22)
    out.append(f"  오프닝 직후(17~22수) 승부 {pct(early, n)}")
    lb = sum(r["black_stats"].get("line_blocks", 0) + r["white_stats"].get("line_blocks", 0) for r in rows)
    la = sum(r["black_stats"].get("line_attacks", 0) + r["white_stats"].get("line_attacks", 0) for r in rows)
    streaks = [r.get("max_line_streak", 0) for r in rows]
    out.append(f"  줄로 막기 {lb}회 (판당 {lb / n:.1f})  ·  줄 공격 {la}회 (판당 {la / n:.1f})  ·  연속 줄 공방 최대 평균 {statistics.mean(streaks):.1f}")
    attacked = [r for r in rows if r.get("first_line_attack_by")]
    if attacked:
        first_wins = sum(1 for r in attacked if r["winner"] == r["first_line_attack_by"])
        out.append(f"  줄 공격을 먼저 한 쪽의 승률 {pct(first_wins, len(attacked))} ({len(attacked)}판)")
    out.append(
        f"  줄로 5목 만들기 {line_fives}회 ({sum(1 for r in rows if r['black_stats']['line_fives'] + r['white_stats']['line_fives'])}판)"
        f"  ·  상대 5목을 줄로 끊기 {cuts}회  ·  4목 막기 {blocks}회 (판당 {blocks / n:.1f})"
    )
    return "\n".join(out)


def by_matchup(rows):
    groups = defaultdict(list)
    for r in rows:
        groups[(r["black"], r["white"])].append(r)
    out = ["  흑 성향 vs 백 성향:  판수  흑승  백승  무  평균 수"]
    for key in sorted(groups):
        g = groups[key]
        w = Counter(r["winner"] for r in g)
        out.append(
            f"  {key[0][:3]} vs {key[1][:3]}:  {len(g):4d}  {pct(w['black'], len(g))} {pct(w['white'], len(g))}"
            f" {pct(w['draw'], len(g))}  {statistics.mean(r['turns'] for r in g):.1f}"
        )
    # 서로 다른 성향끼리 붙었을 때 어느 성향이 이기나 (색 무관)
    mixed = [r for r in rows if r["black"] != r["white"]]
    if mixed:
        agg = sum(1 for r in mixed if (r["winner"] == "black" and r["black"] == "aggressive") or (r["winner"] == "white" and r["white"] == "aggressive"))
        dfn = sum(1 for r in mixed if (r["winner"] == "black" and r["black"] == "defensive") or (r["winner"] == "white" and r["white"] == "defensive"))
        out.append(f"  공격형 vs 방어형 맞대결 {len(mixed)}판: 공격형 승 {pct(agg, len(mixed))}  방어형 승 {pct(dfn, len(mixed))}")
    return "\n".join(out)


def main(paths):
    rows_by_exp = defaultdict(list)
    for path in paths:
        with open(path) as f:
            for line in f:
                if line.strip():
                    r = json.loads(line)
                    rows_by_exp[(r.get("opening", True), r.get("freeze", False), r["experiment"])].append(r)
    for key in sorted(rows_by_exp):
        opening, freeze, exp = key
        rows = rows_by_exp[key]
        tags = ("" if opening else "[오프닝 없음] ") + ("[새 줄 잠금] " if freeze else "")
        print(f"== {tags}{NAMES.get(exp, exp)}")
        print(summarize(rows))
        if exp in (3, 4):
            print(by_matchup(rows))
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
