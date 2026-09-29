#!/usr/bin/env python3
"""「교장이 되어보자!」 최종 경제 시뮬레이션 — final.md §5 의 근거 (merged.md 판 sim-final.py 를 수정)

실행: python3 sim-final.py            (마크다운 표를 표준 출력 → sim-final-output.md)
      python3 sim-final.py --tune     (뽑기 확률·천장 변형 비교)

■ merged.md 판 대비 바뀐 점
  1. 학생 id 를 도감 번호(s01~s24)로 통일. 시설 확정 13명 = s01~s13, 뽑기 9명 + 졸업 확정 2명 = s14~s24.
     시설 id(desk … auditorium)는 FacilityConfig 의 id 와 같다.
  2. 원서는 받는 즉시 뽑고(instant gacha), 뽑은 학생의 기여는 그 초부터 수입에 반영한다.
     → 1회차 표가 뽑기 기여를 포함한다(완결성 렌즈 M4). '회차 끝에 몰아 뽑기' 가정은 하한 참고값으로만 남긴다.
     중복 = 칭찬스티커판 칸 보너스(반장 12 · 전교1등 24 · 전설 60칸 / 60칸 = 원서 1장) → 즉시 다시 뽑는다.
  3. 2회차를 「코스모 보유 / 미보유」 두 모드로 나눠 첫 2분 궤적까지 찍는다(완결성 렌즈 M3).
     회차 시작 시점의 보유 여부로 나눈다. 1회차도 같은 기준으로 갈라 보여 준다.
  4. 1초 루프를 사건 기반(다음 구매·다음 원서·다음 분 경계까지 점프)으로 바꿨다. 결과는 1초 루프와 같다.
  5. 미션 원서(하루 최대 3장)와 남의 부지 별은 0 으로 둔다(보수적). 문서 §2 의 원서 칩 값은 미션 원서를 따로 더한다.
     튜토리얼은 원서 3장을 1:05 에 몰아 뽑게 하므로 1분 안쪽에서는 시뮬(즉시 뽑기)과 최대 1분 차이가 난다.

■ 플레이 행동 가정
  - 그리디 구매(용돈이 닿는 즉시 트리 순서), 스킨 구매 없음.
  - 스티커 스폰 3 → 복도 +2 → 운동장 +3 = 8, 리스폰 15초, 활동형 회수율 55%, 방치형 0%.
  - 스티커 1개 = max(10 × 1.4^N, 초당 수입 × 1.2초), 12개마다 황금 ×5. 60개 = 원서 1장. 시설 1개 = 원서 1장.

■ 수입 공식
  초당 수입 = Σ(지은 시설 초당 수입) × (1 + Σ 재학생 기여) × (1 + 0.5 × 졸업 횟수)
  시설 가격(졸업 N회 후 = N+1회차) = 기본 가격 × 1.4^N,  졸업 시 용돈 → 10 × 1.4^N (책상값)
"""
import math
import random
import sys

STICKER_SECONDS = 1.2
STICKER_MIN = 10
GOLD_EVERY = 12
GOLD_MULT = 5
RESPAWN = 15.0
COLLECT_RATE = 0.55
BOARD_CELLS = 60          # 칭찬스티커판 60칸 = 입학원서 1장
GRAD_STEP = 0.5
PRICE_SCALE = 1.4
BASE_SPAWNS = 3
START_COINS = 10
ROUNDS = 12
PLAYERS = 2000
INF = float("inf")

# (id, 이름, 기본 가격, 초당 수입, 확정 전학생 (도감 id, 등급) 또는 None, 스티커 스폰 추가)
FACILITIES = [
    ("desk",       "책상",    10,        1,    ("s01", "평범"), 0),
    ("board",      "칠판",    60,        3,    ("s02", "평범"), 0),
    ("locker",     "사물함",  180,       6,    ("s03", "평범"), 0),
    ("hall",       "복도",    500,       12,   ("s04", "평범"), 2),
    ("class2",     "교실2",   1500,      25,   ("s05", "평범"), 0),
    ("cafeteria",  "급식실",  4000,      50,   ("s06", "평범"), 0),
    ("library",    "도서관",  11000,     90,   ("s07", "평범"), 0),
    ("nurse",      "보건실",  30000,     150,  ("s08", "평범"), 0),
    ("science",    "과학실",  70000,     260,  ("s09", "평범"), 0),
    ("music",      "음악실",  160000,    420,  ("s10", "평범"), 0),
    ("gym",        "체육관",  350000,    700,  ("s11", "반장"), 0),
    ("field",      "운동장",  750000,    1100, ("s12", "반장"), 3),
    ("principal",  "교장실",  1800000,   1800, ("s13", "반장"), 0),
    ("auditorium", "강당",    3800000,   3000, None,            0),
]
CONTRIB = {"평범": 0.05, "반장": 0.15, "전교1등": 0.40, "전설": 0.60}
FACILITY_MULT = sum(CONTRIB[f[4][1]] for f in FACILITIES if f[4])   # 13명 확정 = 0.95

# 졸업 확정: (졸업 횟수, 도감 id, 이름, 등급)
GRAD_CONFIRMED = [(1, "s18", "도현", "전교1등"), (5, "s23", "금동이", "전설")]
# 뽑기 풀 9명: (도감 id, 이름, 등급, 해금 졸업 횟수)
POOL = [
    ("s14", "채원",   "반장",    0),
    ("s17", "하율",   "전교1등", 0),
    ("s22", "코스모", "전설",    0),
    ("s15", "건우",   "반장",    2),
    ("s16", "서윤",   "반장",    3),
    ("s19", "지안",   "전교1등", 4),
    ("s20", "은우",   "전교1등", 6),
    ("s21", "서하",   "전교1등", 7),
    ("s24", "백호",   "전설",    8),
]
COSMO = "s22"
RATES = [("반장", 0.75), ("전교1등", 0.22), ("전설", 0.03)]
PITY = 50                                  # 전설 천장(50장째 확정)
DUPE_CELLS = {"반장": 12, "전교1등": 24, "전설": 60}
TIER_OF = {sid: tier for sid, _, tier, _ in POOL}
TIER_OF.update({sid: tier for _, sid, _, tier in GRAD_CONFIRMED})
NAME_OF = {sid: name for sid, name, _, _ in POOL}
NAME_OF.update({sid: name for _, sid, name, _ in GRAD_CONFIRMED})
ALL_IDS = [sid for sid, *_ in POOL] + [sid for _, sid, *_ in GRAD_CONFIRMED]


def fmt(n):
    return f"{int(round(n)):,}"


def clock(t):
    t = int(round(t))
    return f"{t // 60:02d}:{t % 60:02d}"


def roll_tier(rng, pity):
    if pity + 1 >= PITY:
        return "전설"
    x = rng.random()
    acc = 0.0
    for tier, p in RATES:
        acc += p
        if x < acc:
            return tier
    return RATES[-1][0]


def pull(rng, grads, owned, st):
    """한 장 뽑기. 같은 등급 안에서 미보유 우선. (등급, 도감 id, 중복 여부)"""
    tier = roll_tier(rng, st["pity"])
    st["pity"] = 0 if tier == "전설" else st["pity"] + 1
    unlocked = [sid for sid, _, tr, g in POOL if tr == tier and g <= grads]
    unowned = [sid for sid in unlocked if sid not in owned]
    if unowned:
        return tier, rng.choice(unowned), False
    return tier, rng.choice(unlocked), True


def simulate(grads=0, carried_mult=0.0, minutes=90, collect_rate=COLLECT_RATE, board=0.0, gacha=None, snap=True):
    """한 회차. 사건(다음 구매·다음 원서·다음 분 경계)까지 점프하며 돈다. 14번째 시설(강당) 구매 시각 = 졸업 가능 시각.
    gacha = {rng, owned(set), got_round, pity} 면 원서를 받는 즉시 뽑고 기여를 바로 반영한다. None 이면 원서만 센다."""
    earned_idle = earned_sticker = 0.0
    student_mult = carried_mult
    grad_mult = 1 + GRAD_STEP * grads
    price_scale = PRICE_SCALE ** grads
    coins = START_COINS * price_scale
    base = 0.0
    spawns = BASE_SPAWNS
    owned = 0
    sticker_acc = board
    stickers_total = 0.0
    tickets = pulls = new = 0
    buy_log, snapshots, pull_log = [], [], []
    t = 0
    end = minutes * 60

    def on_ticket():
        nonlocal tickets, pulls, new, sticker_acc, student_mult
        tickets += 1
        if gacha is None:
            return
        tier, sid, dupe = pull(gacha["rng"], grads, gacha["owned"], gacha)
        pulls += 1
        if dupe:
            sticker_acc += DUPE_CELLS[tier]
        else:
            gacha["owned"].add(sid)
            gacha["got_round"][sid] = grads + 1
            student_mult += CONTRIB[tier]
            new += 1
        pull_log.append((t, tier, sid, dupe))

    def drain_board():
        nonlocal sticker_acc
        while sticker_acc >= BOARD_CELLS:
            sticker_acc -= BOARD_CELLS
            on_ticket()

    while t < end and owned < len(FACILITIES):
        income = base * (1 + student_mult) * grad_mult
        rate = spawns / RESPAWN * collect_rate
        per_sticker = max(STICKER_MIN * price_scale, income * STICKER_SECONDS)
        ev = per_sticker * ((GOLD_EVERY - 1) + GOLD_MULT) / GOLD_EVERY
        gain = rate * ev
        per_sec = income + gain
        price = FACILITIES[owned][2] * price_scale
        if coins >= price - 1e-9:
            dt_buy = 0
        elif per_sec > 0:
            dt_buy = max(1, math.ceil((price - coins) / per_sec - 1e-9))
        else:
            dt_buy = INF
        dt_ticket = max(1, math.ceil((BOARD_CELLS - sticker_acc) / rate - 1e-9)) if rate > 0 else INF
        dt_snap = 60 - t % 60 if snap else INF
        dt = min(dt_buy, dt_ticket, dt_snap, end - t)
        if dt > 0:
            coins += per_sec * dt
            earned_idle += income * dt
            earned_sticker += gain * dt
            stickers_total += rate * dt
            sticker_acc += rate * dt
            t += dt
        drain_board()
        while owned < len(FACILITIES) and coins >= FACILITIES[owned][2] * price_scale - 1e-9:
            fid, name, price, inc, student, add_spawn = FACILITIES[owned]
            coins -= price * price_scale
            base += inc
            spawns += add_spawn
            if grads == 0 and student:
                student_mult += CONTRIB[student[1]]
            owned += 1
            on_ticket()
            drain_board()
            buy_log.append((t, name, price * price_scale, base * (1 + student_mult) * grad_mult, student_mult))
        if snap and t % 60 == 0 and t > 0 and (not snapshots or snapshots[-1][0] != t // 60):
            snapshots.append((t // 60, coins, base * (1 + student_mult) * grad_mult, owned, tickets, stickers_total))
    return dict(buy_log=buy_log, snapshots=snapshots, tickets=tickets, pulls=pulls, new=new, pull_log=pull_log,
                stickers=stickers_total, earned_idle=earned_idle, earned_sticker=earned_sticker,
                end=t, owned=owned, board=sticker_acc)


def run_player(rng, rounds=ROUNDS, collect_rate=COLLECT_RATE):
    owned = set()
    got_round = {}
    gacha = {"rng": rng, "owned": owned, "got_round": got_round, "pity": 0}
    board = 0.0
    rows = []
    for grads in range(rounds):
        for g, sid, _, _ in GRAD_CONFIRMED:
            if grads >= g and sid not in owned:
                owned.add(sid)
                got_round[sid] = grads + 1
        carried = (FACILITY_MULT if grads > 0 else 0.0) + sum(CONTRIB[TIER_OF[s]] for s in owned)
        cosmo_start = COSMO in owned
        r = simulate(grads=grads, carried_mult=carried, collect_rate=collect_rate, board=board, gacha=gacha, snap=(grads == 0))
        if len(r["buy_log"]) < len(FACILITIES):
            break
        board = r["board"]
        rows.append(dict(round=grads + 1, duration=r["buy_log"][-1][0], carried=carried, pulls=r["pulls"], new=r["new"],
                         tickets=r["tickets"], cosmo_start=cosmo_start, cosmo_end=(COSMO in owned),
                         buy_log=r["buy_log"], snapshots=r["snapshots"], stickers=r["stickers"],
                         earned_idle=r["earned_idle"], earned_sticker=r["earned_sticker"]))
    complete = max(got_round.values()) if len(got_round) == len(ALL_IDS) else None
    return rows, got_round, complete


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else None


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * q))] if xs else None


def trajectories(players=PLAYERS, collect_rate=COLLECT_RATE, seed=20260928, rounds=ROUNDS):
    rng = random.Random(seed)
    per_round = {}
    got = {sid: [] for sid in ALL_IDS}
    completes, complete_minutes = [], []
    first_round_cosmo = 0
    for _ in range(players):
        rows, got_round, complete = run_player(rng, rounds=rounds, collect_rate=collect_rate)
        cum = 0
        cum_by_round = {}
        for row in rows:
            cum += row["duration"]
            cum_by_round[row["round"]] = cum
            per_round.setdefault(row["round"], []).append(row)
        for sid, k in got_round.items():
            got[sid].append(k)
        if complete:
            completes.append(complete)
            complete_minutes.append(cum_by_round.get(complete, cum) / 60)
        if got_round.get(COSMO) == 1:
            first_round_cosmo += 1
    return per_round, got, completes, complete_minutes, first_round_cosmo / players


def print_mc_round(label, rows, grads, note=""):
    """몬테카를로 회차 표: 시설별 구매 시각·수입·배율의 중앙값."""
    n = len(rows)
    start = median([r["carried"] for r in rows])
    print(f"\n### {label} — 졸업 {grads}회 · 시작 재학생 배율 ×{1+start:.2f}(중앙값) · 졸업 배율 ×{1+GRAD_STEP*grads:.1f} · 가격 ×{PRICE_SCALE**grads:.2f} · 표본 {n}명{note}\n")
    print("| # | 시설 | 가격 | 구매 시각(중앙값) | 10%~90% | 직전 구매와 간격 | 구매 직후 초당 수입(중앙값) | 재학생 배율(중앙값) |")
    print("|---:|---|---:|---:|---:|---:|---:|---:|")
    prev = 0
    for i, (fid, name, price, *_ ) in enumerate(FACILITIES):
        ts = [r["buy_log"][i][0] for r in rows]
        med = median(ts)
        inc = median([r["buy_log"][i][3] for r in rows])
        sm = median([r["buy_log"][i][4] for r in rows])
        print(f"| {i+1} | {name} | {fmt(price * PRICE_SCALE**grads)} | {clock(med)} | {clock(pct(ts,0.1))}~{clock(pct(ts,0.9))} | {med-prev}초 | {inc:,.0f}/s | ×{1+sm:.2f} |")
        prev = med
    durs = [r["duration"] for r in rows]
    med = median(durs)
    share = median([r["earned_sticker"] / (r["earned_idle"] + r["earned_sticker"]) * 100 for r in rows])
    print(f"\n강당 완공(졸업 가능): **{med//60}분 {med%60}초**(10%~90% {clock(pct(durs,0.1))}~{clock(pct(durs,0.9))}) · 원서 {median([r['tickets'] for r in rows])}장 · 뽑기 {median([r['pulls'] for r in rows])}회 · 새 학생 {median([r['new'] for r in rows])}명 · 회수 스티커 {int(median([r['stickers'] for r in rows]))}개 · 스티커 비중 {share:.0f}%")
    return med


def print_minute_table(rows, upto=30):
    print("\n| 분 | 보유 용돈(중앙값) | 초당 수입(중앙값) | 지은 시설(중앙값) | 누적 원서(중앙값) | 누적 스티커 |")
    print("|---:|---:|---:|---:|---:|---:|")
    for m in range(1, upto + 1):
        snaps = [s for r in rows for s in r["snapshots"] if s[0] == m]
        if len(snaps) < len(rows) * 0.5:
            break
        print(f"| {m} | {fmt(median([s[1] for s in snaps]))} | {median([s[2] for s in snaps]):,.0f} | {median([s[3] for s in snaps])} | {median([s[4] for s in snaps])} | {int(median([s[5] for s in snaps]))} |")


def print_det_round(label, grads, carried, collect_rate=COLLECT_RATE):
    """뽑기 기여 0 의 결정론 하한(merged.md 판 표)."""
    r = simulate(grads=grads, carried_mult=carried, collect_rate=collect_rate)
    last = r["buy_log"][-1][0]
    print(f"- {label}: 강당 **{clock(last)}** · 원서 {r['tickets']}장 · 회수 스티커 {int(r['stickers'])}개")
    return r


def print_trajectories(per_round, got, completes, complete_minutes, cosmo1, players):
    print("\n| 회차 | 졸업 배율 | 가격 배율 | 시작 재학생 배율(중앙값) | 강당 완공 시각(중앙값) | 10%~90% | 누적 플레이(중앙값) | 원서(시설+판) | 뽑기 수(중복 환급 포함) | 새 학생 수(중앙값) | 회차 시작 시 코스모 보유 |")
    print("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    cum = 0
    for k in sorted(per_round):
        rows = per_round[k]
        durs = [r["duration"] for r in rows]
        med = median(durs)
        cum += med
        cosmo = sum(1 for r in rows if r["cosmo_start"]) / len(rows) * 100 if k > 1 else 0
        print(f"| {k} | ×{1+GRAD_STEP*(k-1):.1f} | ×{PRICE_SCALE**(k-1):.2f} | ×{1+median([r['carried'] for r in rows]):.2f} | {clock(med)} | {clock(pct(durs,0.1))}~{clock(pct(durs,0.9))} | {int(cum//60)}분 | {median([r['tickets'] for r in rows])} | {median([r['pulls'] for r in rows])} | {median([r['new'] for r in rows])} | {cosmo:.0f}% |")
    print("\n| 학생 | id | 등급 | 경로 | 획득 회차 중앙값 | 90% 이내 |")
    print("|---|---|---|---|---:|---:|")
    order = [sid for sid, *_ in POOL] + [sid for _, sid, *_ in GRAD_CONFIRMED]
    unlock = {sid: g for sid, _, _, g in POOL}
    unlock.update({sid: g for g, sid, _, _ in GRAD_CONFIRMED})
    confirmed = {s for _, s, *_ in GRAD_CONFIRMED}
    for sid in order:
        route = "졸업 확정" if sid in confirmed else ("뽑기(처음부터)" if unlock[sid] == 0 else f"뽑기(졸업 {unlock[sid]}회 해금)")
        print(f"| {NAME_OF[sid]} | {sid} | {TIER_OF[sid]} | {route} | {median(got[sid])}회차 | {pct(got[sid],0.9)}회차 |")
    print(f"\n도감 24명 완성: 중앙값 **{median(completes)}회차**(90% 이내 {pct(completes,0.9)}회차), 누적 활동 플레이 중앙값 **{median(complete_minutes):.0f}분**(90% {pct(complete_minutes,0.9):.0f}분), {len(completes)/players*100:.0f}% 가 {ROUNDS}회차 안에 완성")
    print(f"1회차 안에 전설 코스모를 뽑는 비율: {cosmo1*100:.0f}%")


def rate_check(n=100000, seed=7):
    rng = random.Random(seed)
    counts = {t: 0 for t, _ in RATES}
    pity, pity_hits, longest = 0, 0, 0
    for _ in range(n):
        tier = roll_tier(rng, pity)
        if pity + 1 >= PITY:
            pity_hits += 1
        pity = 0 if tier == "전설" else pity + 1
        longest = max(longest, pity)
        counts[tier] += 1
    print("\n" + ", ".join(f"{t} {c/n*100:.2f}%" for t, c in counts.items()) + f" (10만 회, 천장 발동 {pity_hits/n*100:.2f}%, 전설 없이 최장 {longest}장)")


def main():
    global RATES, PITY
    if "--tune" in sys.argv:
        variants = [
            ("기준 75/22/3 · 천장 50", [("반장", .75), ("전교1등", .22), ("전설", .03)], 50),
            ("70/25/5 · 천장 40", [("반장", .70), ("전교1등", .25), ("전설", .05)], 40),
            ("78/20/2 · 천장 60", [("반장", .78), ("전교1등", .20), ("전설", .02)], 60),
            ("75/22/3 · 천장 30", [("반장", .75), ("전교1등", .22), ("전설", .03)], 30),
        ]
        for label, rates, pity in variants:
            RATES, PITY = rates, pity
            per_round, got, completes, cm, cosmo1 = trajectories(players=600)
            print(f"{label}: 완성 중앙값 {median(completes)}회차 / 90% {pct(completes,0.9)}회차 / 누적 {median(cm):.0f}분 / 1회차 코스모 {cosmo1*100:.0f}% / 1회차 강당 {clock(median([r['duration'] for r in per_round[1]]))}")
        RATES, PITY = variants[0][1], variants[0][2]
        return

    print("# 최종 시뮬레이션 출력 (python3 sim-final.py)")
    print(f"\n원서 즉시 뽑기 · 기여 즉시 반영 · {PLAYERS}명 몬테카를로. 미션 원서·남의 부지 별은 0(보수적).")
    per_round, got, completes, cm, cosmo1 = trajectories()

    rows1 = per_round[1]
    print_mc_round("1회차(활동형 · 스티커 55% 회수)", rows1, 0)
    c_yes = [r["duration"] for r in rows1 if r["cosmo_end"]]
    c_no = [r["duration"] for r in rows1 if not r["cosmo_end"]]
    print(f"1회차 안에 코스모를 뽑은 {len(c_yes)/len(rows1)*100:.0f}%: 강당 {clock(median(c_yes))} · 못 뽑은 {len(c_no)/len(rows1)*100:.0f}%: 강당 {clock(median(c_no))}")
    print("\n#### 1회차 분 단위 곡선(활동형, 표본 중앙값)")
    print_minute_table(rows1, upto=30)

    print("\n#### 뽑기 기여 0 하한(결정론, merged.md 판 표) — 참고값")
    print_det_round("1회차 활동형(55%)", 0, 0.0)
    print_det_round("1회차 방치형(0%)", 0, 0.0, collect_rate=0.0)

    print("\n#### 회수율 민감도(1회차 강당 완공 중앙값, 500명)")
    for cr in (0.40, 0.55, 0.70):
        pr, *_ = trajectories(players=500, collect_rate=cr, rounds=1)
        print(f"- 회수율 {cr:.0%}: {clock(median([r['duration'] for r in pr[1]]))}")

    rows2 = per_round[2]
    yes = [r for r in rows2 if r["cosmo_start"]]
    no = [r for r in rows2 if not r["cosmo_start"]]
    print(f"\n### 2회차 — 두 모드(회차 시작 시 코스모 보유 {len(yes)/len(rows2)*100:.0f}% / 미보유 {len(no)/len(rows2)*100:.0f}%), 전체 중앙값 {clock(median([r['duration'] for r in rows2]))}")
    print_mc_round("2회차 A · 코스모 보유", yes, 1, note=" · 시설 13명 0.95 + 도현 0.40 + 채원 0.15 + 하율 0.40 + 코스모 0.60")
    print_mc_round("2회차 B · 코스모 미보유", no, 1, note=" · 시설 13명 0.95 + 도현 0.40 + 채원 0.15 + 하율 0.40")

    rows3 = per_round[3]
    print_mc_round("3회차(전체)", rows3, 2)

    print(f"\n#### 회차별 궤적 몬테카를로({PLAYERS}명, 원서 즉시 뽑기, 기여 즉시 반영)")
    print_trajectories(per_round, got, completes, cm, cosmo1, PLAYERS)

    print("\n#### 방치형(회수율 0%) 궤적 — 같은 뽑기 규칙, 300명")
    per_round_i, got_i, completes_i, cm_i, cosmo1_i = trajectories(players=300, collect_rate=0.0)
    print_trajectories(per_round_i, got_i, completes_i, cm_i, cosmo1_i, 300)

    print("\n#### 확률 띠 실측(천장 포함)")
    rate_check()


if __name__ == "__main__":
    main()
