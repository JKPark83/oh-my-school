#!/usr/bin/env python3
"""「교장이 되어보자!」 안 A(부품 50개) 경제 시뮬레이션 — 개선계획 2026-09-29 §3.4 · §3.6 #4 의 근거

실행: python3 docs/sim/sim-parts.py            > docs/sim/sim-parts-output.md
      python3 docs/sim/sim-parts.py --tower    (기본 출력 뒤에 층 가격 표를 덧붙인다)

■ 규칙(개선계획 §3.4 안 A)
  - 시설 14개를 부품 50개로 쪼갠다. 앞 6개 시설(책상·칠판·사물함·복도·교실2·급식실)은 3개씩,
    나머지 8개 시설은 4개씩 = 18 + 32 = 50.
  - 수입은 시설이 완공될 때(마지막 부품)만 붙는다(§3.4 #12). 부품마다 나누지 않는다.
  - CONTRIB(학생 기여) 없음. 초당 수입 = Σ 완공 시설 income × (1 + GRAD_STEP × 졸업), GRAD_STEP 1.0.
  - 가격·스티커 최소값·시작 용돈 × PRICE_SCALE^졸업, PRICE_SCALE 1.35.
  - 목표 간격 gap(k) = 5초 × 11^((k-2)/48). k=2 에서 5초, k=50 에서 55초.
    부품 k 가격 = 「부품 k-1 까지 산 뒤의 활동형 수입(완공 시설 수입 + 활동형 스티커 기대 수입)」 × gap(k).
    k=1 은 START_COINS 10. 이 표는 1회차(졸업 0) 기준 상수표이고, N회 졸업 뒤에는 표 × 1.35^N 을 반올림해 쓴다.
  - 스티커: 스폰 3(처음부터) → 복도 완공 +2 → 운동장 완공 +3, 리스폰 15초, 활동형 회수율 55%, 방치형 0%.
    1장 = max(10 × 1.35^N, 초당 수입 × 1.2), 12장마다 황금 ×5 → 기대값 = 1장 × (11 + 5) / 12.
    스티커는 기대값 흐름(초당 스폰/15 × 회수율 × 기대값)으로 더한다. 무작위가 없어 결과는 항상 같다(결정적).
  - 그리디 구매: 1초 틱마다 수입을 더한 뒤, 살 수 있으면 부품 1개만 산다(§3.4 #5).
  - 졸업 = 강당 마지막 부품(50번째) 완공 즉시. 다음 회차 시작 용돈 10 × 1.35^N.
  - 원서·뽑기·선물판 없음. 선물판 보상 0, 꾸미기 지출 0(W3 게이트 가정). 「수입 20% 를 꾸미기」는 참고 행.

■ 가격 반올림 규칙(nice_price)
  유효숫자 2자리 반올림(사사오입). 10 보다 작으면 10(START_COINS·STICKER_MIN 과 같은 바닥값).
  예: 7.3 → 10, 13.4 → 13, 346,812 → 350,000, 7,387 → 7,400.
  N회 졸업 뒤 가격은 이 표 값 × 1.35^N 을 정수로 반올림한다(FacilityConfig.partPriceOf 와 같은 floor(x + 0.5)).
  주의: 개선계획 §3.4 의 부품 가격 예(책상 10·10·20, 강당 400,000·490,000·600,000·730,000, 합계 3,963,430)는
  「완공 때만 수입(#12) + gap 식」으로는 나오지 않는다. 한 시설 안에서는 수입이 그대로라 부품 사이 가격 비가
  gap 비 11^(1/48) ≈ 1.051 뿐인데, 문서 예는 시설 안에서 약 1.22배씩 오른다. 반올림 규칙으로 메울 수 없는 차이라
  규칙(§3.4)을 따르고 예·합계는 문서 쪽에서 고친다(책상 k3 반올림 전 7.7, 강당 321k~373k, 합계 2,660,171).

■ 방치형 첫 부품 가정
  수입이 완공 때만 붙으므로 책상(3부품)이 서기 전 시설 수입은 0 이다. 회수율 0% 그대로면 방치형은
  부품 2 에서 영원히 멈춘다. 그래서 방치형도 튜토리얼 빛기둥 스티커 3장(STICKER_HOME_UNTIL 3)은
  3·6·9초에 줍는다고 둔다. 그 뒤 회수율 0%.
"""
import math
import sys

START_COINS = 10
STICKER_MIN = 10
STICKER_SECONDS = 1.2
GOLD_EVERY = 12
GOLD_MULT = 5
RESPAWN = 15.0
BASE_SPAWNS = 3
COLLECT_ACTIVE = 0.55
COLLECT_IDLE = 0.0
GRAD_STEP = 1.0
PRICE_SCALE = 1.35
GAP_FIRST = 5.0          # k=2 목표 간격(초)
GAP_LAST = 55.0          # k=50 목표 간격(초)
IDLE_TUTORIAL_STICKERS = (3, 6, 9)   # 방치형이 줍는 튜토리얼 스티커 3장의 시각(초)
MAX_SECONDS = 90 * 60
GOLD_EV = ((GOLD_EVERY - 1) + GOLD_MULT) / GOLD_EVERY

# (id, 이름, 초당 수입, 스티커 스폰 추가, 부품 수). 수입·스폰은 FacilityConfig.luau 와 같다.
# 책상의 spawns 3 은 Config 에서 책상에 붙어 있지만 여기서는 처음부터 있는 BASE_SPAWNS 로 본다.
FACILITIES = [
    ("desk",       "책상",   1,    0, 3),
    ("board",      "칠판",   3,    0, 3),
    ("locker",     "사물함", 6,    0, 3),
    ("hall",       "복도",   12,   2, 3),
    ("class2",     "교실2",  25,   0, 3),
    ("cafeteria",  "급식실", 50,   0, 3),
    ("library",    "도서관", 90,   0, 4),
    ("nurse",      "보건실", 150,  0, 4),
    ("science",    "과학실", 260,  0, 4),
    ("music",      "음악실", 420,  0, 4),
    ("gym",        "체육관", 700,  0, 4),
    ("field",      "운동장", 1100, 3, 4),
    ("principal",  "교장실", 1800, 0, 4),
    ("auditorium", "강당",   3000, 0, 4),
]

# 부품 목록: (k, 시설 순번 0.., 시설 안 부품 순번 1.., 그 시설 마지막 부품인가)
PARTS = []
for fi, (_, _, _, _, n) in enumerate(FACILITIES):
    for j in range(1, n + 1):
        PARTS.append((len(PARTS) + 1, fi, j, j == n))
assert len(PARTS) == 50

# 층(§3.6 #4). completedIncome = 14 시설 income 원시 합
TOWER_GAP_SECONDS = 60
TOWER_COMPLETED_INCOME = sum(f[2] for f in FACILITIES)
TOWER_FIRST_FLOOR = 3
TOWER_TOP_FLOOR = 20     # 잠정 상한. 층 번호 20(바닥 y 360.2)까지
TOWER_STEPS = (1.5, 1.3, 1.2, 1.1, 1.0)
TOWER_IDLE_SECONDS = 30 * 60


def gap(k):
    return GAP_FIRST * (GAP_LAST / GAP_FIRST) ** ((k - 2) / 48)


def nice_price(x):
    """유효숫자 2자리 반올림, 바닥 10."""
    if x < 10:
        return 10
    mag = 10 ** (int(math.floor(math.log10(x))) - 1)
    return int(math.floor(x / mag + 0.5)) * mag


def scaled(price, grads):
    return int(math.floor(price * PRICE_SCALE ** grads + 0.5))


def state_after(k_done):
    """부품 k_done 개를 산 뒤 (완공 시설 수, 시설 수입 원시 합, 스폰 수)."""
    built = sum(1 for k, fi, j, last in PARTS if k <= k_done and last)
    base = sum(f[2] for f in FACILITIES[:built])
    spawns = BASE_SPAWNS + sum(f[3] for f in FACILITIES[:built])
    return built, base, spawns


def sticker_value(income, grads):
    return max(STICKER_MIN * PRICE_SCALE ** grads, income * STICKER_SECONDS)


def sticker_flow(income, spawns, grads, collect):
    """초당 스티커 기대 수입."""
    return spawns / RESPAWN * collect * sticker_value(income, grads) * GOLD_EV


def price_table():
    """1회차 기준 부품 가격 상수표. 행 = (k, 시설 순번, 부품 순번, 원가, 가격, 그 시점 활동형 수입, 목표 간격)."""
    rows = []
    for k, fi, j, _ in PARTS:
        if k == 1:
            rows.append((k, fi, j, START_COINS, START_COINS, 0.0, 0.0))
            continue
        _, base, spawns = state_after(k - 1)
        active = base + sticker_flow(base, spawns, 0, COLLECT_ACTIVE)
        raw = active * gap(k)
        rows.append((k, fi, j, raw, nice_price(raw), active, gap(k)))
    return rows


TABLE = price_table()
PRICES = [r[4] for r in TABLE]


def simulate(grads=0, collect=COLLECT_ACTIVE, spend=0.0, tutorial=False, curve=False):
    """한 회차를 1초 틱으로 돈다. spend = 수입 중 꾸미기로 빠지는 비율(참고 행용)."""
    grad_mult = 1 + GRAD_STEP * grads
    prices = [scaled(p, grads) for p in PRICES]
    coins = float(scaled(START_COINS, 0) if grads == 0 else scaled(START_COINS, grads))
    bought = 0
    buy_times = []
    snaps = []
    t = 0

    def income_now():
        _, base, spawns = state_after(bought)
        inc = base * grad_mult
        return inc, sticker_flow(inc, spawns, grads, collect)

    def try_buy():
        nonlocal coins, bought
        if bought < len(PARTS) and coins >= prices[bought] - 1e-9:
            coins -= prices[bought]
            bought += 1
            buy_times.append(t)

    def snap():
        inc, st = income_now()
        built, _, _ = state_after(bought)
        snaps.append((t // 60, bought, built, coins, inc, inc + st))

    try_buy()
    if curve:
        snap()
    while bought < len(PARTS) and t < MAX_SECONDS:
        t += 1
        inc, st = income_now()
        gain = inc + st
        if tutorial and t in IDLE_TUTORIAL_STICKERS:
            gain += round(sticker_value(inc, grads))
        coins += gain * (1 - spend)
        try_buy()
        if curve and t % 60 == 0:
            snap()
    return dict(buy_times=buy_times, done=buy_times[-1] if bought == len(PARTS) else None,
                snaps=snaps, coins=coins, bought=bought)


def clock(t):
    if t is None:
        return "미완료"
    t = int(round(t))
    return f"{t // 60:02d}:{t % 60:02d}"


def fmt(n):
    return f"{int(round(n)):,}"


def max_gap(times):
    gaps = [b - a for a, b in zip(times, times[1:])]
    i = max(range(len(gaps)), key=lambda x: gaps[x])
    return gaps[i], i + 2


def count_at(times, sec):
    parts = sum(1 for x in times if x <= sec)
    built, _, _ = state_after(parts)
    return parts, built


def facility_done_time(times, fi):
    k = max(k for k, f, j, last in PARTS if f == fi)
    return times[k - 1]


def print_curve(label, r):
    print(f"\n#### 분 단위 곡선 — {label}\n")
    print("| 분 | 산 부품 | 완공 시설 | 보유 용돈 | 초당 시설 수입 | 초당 수입(스티커 기대값 포함) |")
    print("|---:|---:|---:|---:|---:|---:|")
    for m, parts, built, coins, inc, total in r["snaps"]:
        if m > 30:
            break
        print(f"| {m} | {parts} | {built} | {fmt(coins)} | {fmt(inc)} | {fmt(total)} |")
    if r["done"] is not None and r["done"] <= 30 * 60:
        print(f"\n{clock(r['done'])} 에 50번째 부품(강당) 완공 = 졸업. 이후 행 없음.")


def main():
    active = simulate(curve=True)
    idle = simulate(collect=COLLECT_IDLE, tutorial=True, curve=True)
    at = active["buy_times"]
    it = idle["buy_times"]

    print("# 안 A 부품 50개 시뮬레이션 출력 (python3 docs/sim/sim-parts.py)")
    print("\n**가정(W3 게이트)**: 선물판 보상 0 · 꾸미기 지출 0 · 원서·뽑기 없음 · CONTRIB 없음. "
          "수입은 시설 완공 때만 붙는다. GRAD_STEP 1.0, PRICE_SCALE 1.35. "
          "스티커 스폰 3 → 복도 +2 → 운동장 +3, 리스폰 15초, 회수율 활동형 55%·방치형 0%, "
          "1장 = max(10×1.35^N, 초당 수입×1.2), 12장마다 황금 ×5(기대값 흐름). "
          "그리디 구매, 1초 틱에 부품 1개. 방치형은 튜토리얼 스티커 3장(3·6·9초)만 줍는다(책상이 서기 전 수입 0 이라 없으면 멈춘다). "
          "무작위 없음(결정적).")
    print("\n**가격 규칙**: 부품 k 가격 = (부품 k-1 까지 산 뒤 활동형 수입) × gap(k), gap(k) = 5 × 11^((k-2)/48) 초, k=1 = 10. "
          "유효숫자 2자리 반올림, 10 미만은 10. N회 졸업 뒤 가격 = 표 × 1.35^N 반올림.")
    print("\n**개선계획 예와 다름**: 개선계획 §3.4 의 가격 예(책상 10·10·20, 강당 400,000·490,000·600,000·730,000, 합계 3,963,430)는 "
          "완공 때만 수입 + gap 식으로는 나오지 않는다. 시설 안 부품 사이 가격 비는 gap 비 11^(1/48) ≈ 1.051 이고 문서 예는 약 1.22 다. "
          "이 출력은 규칙을 따른다. 문서 예와 합계는 상위 단계에서 고친다.")

    print("\n## 부품 50개 가격표(1회차 기준 상수표)\n")
    print("| 시설 | k | 부품 | 가격 | 반올림 전 | 그 시점 활동형 수입(/s) | 목표 간격 | 실제 간격(활동형 1회차) | 구매 시각 |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for (k, fi, j, raw, price, inc, g), t in zip(TABLE, at):
        real = "—" if k == 1 else f"{t - at[k - 2]}초"
        gtxt = "—" if k == 1 else f"{g:.1f}초"
        print(f"| {FACILITIES[fi][1]} | {k} | {j}/{FACILITIES[fi][4]} | {fmt(price)} | {raw:,.1f} | {inc:,.1f} | {gtxt} | {real} | {clock(t)} |")
    total = sum(PRICES)
    print(f"\n가격 합계: **{total:,}**")
    print("\n시설별 부품 수: " + " · ".join(f"{f[1]} {f[4]}" for f in FACILITIES) + f" = {len(PARTS)}")
    print("\nConfig 옮김용 가격 배열: `{" + ", ".join(str(p) for p in PRICES) + "}`")

    g_act, k_act = max_gap(at)
    g_idle, k_idle = max_gap(it)
    p5, f5 = count_at(at, 300)
    p5i, f5i = count_at(it, 300)
    r2 = simulate(grads=1)
    r10 = simulate(grads=9)
    da = simulate(spend=0.2)
    di = simulate(collect=COLLECT_IDLE, tutorial=True, spend=0.2)
    print("\n## 요약\n")
    print("「개선계획 목표」는 개선계획 §3.4 표의 수치다(재현 스크립트 없이 적힌 값). 다르면 규칙대로 낸 이 출력을 기준으로 문서를 고친다.\n")
    print("| 지표 | 값 | 개선계획 목표 |")
    print("|---|---|---|")
    print(f"| 1회차 활동형 강당 완공(졸업) | **{clock(active['done'])}** · 최대 간격 {g_act}초(k={k_act}) | 17:31 ±1분 · 최대 간격 55초 |")
    print(f"| 1회차 방치형 강당 완공(졸업) | **{clock(idle['done'])}** · 최대 간격 {g_idle}초(k={k_idle}) | 23:37 |")
    print(f"| 2회차 활동형 강당 완공 | {clock(r2['done'])} | 11:53 |")
    print(f"| 10회차 활동형 강당 완공 | {clock(r10['done'])} | 25:56 |")
    print(f"| 첫 5분(5:00) 활동형 | 부품 {p5}개 · 시설 {f5}개 | 부품 28개 · 시설 7개, FIVE_PARTS ≥24 |")
    print(f"| 첫 5분(5:00) 방치형 | 부품 {p5i}개 · 시설 {f5i}개 | FIVE_PARTS ≥24 |")
    print(f"| 급식실(6번째 시설) 완공 | 활동형 {clock(facility_done_time(at, 5))} · 방치형 {clock(facility_done_time(it, 5))} | 2:52 |")
    print(f"| 가격 합계(1회차) | {total:,} | 3,963,430 |")
    print(f"| 참고: 수입 20% 꾸미기 | 활동형 {clock(da['done'])} · 방치형 {clock(di['done'])} | 21:52 / 29:31 |")
    print("\n차이: 급식실 활동형 완공은 목표 2:52 보다 빠르고(방치형이 2:52), 첫 5분 활동형 시설 수는 목표 7 보다 많다. "
          "둘 다 규칙(§3.4 gap 식 + 완공 때만 수입)을 그대로 따른 결과라 문서의 2:52 게이트·시설 7 을 고칠 후보다. "
          "가격 합계 차이는 위 「개선계획 예와 다름」과 같은 원인이다.")

    print("\n## 회차별(활동형 55%, 졸업 즉시 다음 회차)\n")
    print("| 회차 | 졸업 수 | 수입 배율 | 가격 배율 | 시작 용돈 | 강당 완공 | 최대 간격 | 방치형 강당 완공 |")
    print("|---:|---:|---:|---:|---:|---:|---:|---:|")
    for n in range(10):
        ra = simulate(grads=n)
        ri = simulate(grads=n, collect=COLLECT_IDLE, tutorial=True)
        mg, _ = max_gap(ra["buy_times"])
        print(f"| {n + 1} | {n} | ×{1 + GRAD_STEP * n:.0f} | ×{PRICE_SCALE ** n:.2f} | {scaled(START_COINS, n)} | "
              f"{clock(ra['done'])} | {mg}초 | {clock(ri['done'])} |")

    print_curve("1회차 활동형(55%)", active)
    print_curve("1회차 방치형(0%, 튜토리얼 스티커 3장만)", idle)

    print("\n## 참고: 수입 20% 를 꾸미기에 쓴다(게이트 아님)\n")
    print(f"- 1회차 활동형: {clock(da['done'])}")
    print(f"- 1회차 방치형: {clock(di['done'])}")

    if "--tower" in sys.argv:
        print_tower(active)


def tower_price(n, grads, completed_income, step):
    """TowerConfig.priceOf 와 같은 식: round(GAP_SECONDS × completedIncome × STEP^(n-3) × PRICE_SCALE^graduations)."""
    return int(math.floor(TOWER_GAP_SECONDS * completed_income * step ** (n - 3) * PRICE_SCALE ** grads + 0.5))


def print_tower(active):
    """1회차 활동형으로 강당을 끝낸 직후 남은 용돈에서 시작해, 방치(시설 수입만, 스티커 0) 30분 동안 층을 산다.
    졸업하지 않고 머문다고 본다. 1초 틱에 1층, 층 수입 0."""
    start = active["coins"]
    inc = TOWER_COMPLETED_INCOME
    print(f"\n## --tower: 층 가격(§3.6 #4)\n")
    print(f"priceOf(n, 졸업, completedIncome) = round({TOWER_GAP_SECONDS} × completedIncome × STEP^(n−3) × 1.35^졸업), "
          f"completedIncome = {inc:,}(14 시설 income 원시 합). 1회차(졸업 0) 강당 완공 직후 남은 용돈 {fmt(start)} 에서 시작, "
          f"방치 = 초당 {inc:,}(스티커 0), 30분. 층 번호는 3층부터, 상한 {TOWER_TOP_FLOOR}층.\n")
    print("| STEP | 3층 | 4층 | 5층 | 10층 | 20층 | 30분 안 마지막 층 | 산 층 수 | 마지막 층 산 시각 | 다음 층까지 남은 시간(30분 시점) |")
    print("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for step in TOWER_STEPS:
        coins = start
        n = TOWER_FIRST_FLOOR
        last_t = None
        t = 0
        while t < TOWER_IDLE_SECONDS and n <= TOWER_TOP_FLOOR:
            t += 1
            coins += inc
            p = tower_price(n, 0, inc, step)
            if coins >= p:
                coins -= p
                last_t = t
                n += 1
        floors = n - TOWER_FIRST_FLOOR
        top = n - 1 if floors else "—"
        if n <= TOWER_TOP_FLOOR:
            remain = max(0, math.ceil((tower_price(n, 0, inc, step) - coins) / inc))
            rtxt = f"{remain // 60}분 {remain % 60}초"
        else:
            rtxt = "상한 도달"
        print(f"| {step} | {fmt(tower_price(3, 0, inc, step))} | {fmt(tower_price(4, 0, inc, step))} | "
              f"{fmt(tower_price(5, 0, inc, step))} | {fmt(tower_price(10, 0, inc, step))} | {fmt(tower_price(20, 0, inc, step))} | "
              f"{top}층 | {floors} | {clock(last_t)} | {rtxt} |")
    print("\n층 n 을 사는 데 드는 방치 시간 = 60 × STEP^(n−3) 초(수입 = completedIncome 이므로). 졸업 N회 뒤에는 가격 ×1.35^N, "
          "수입 ×(1+N) 이라 층당 시간은 ×1.35^N/(1+N) 로 줄어든다.")


if __name__ == "__main__":
    main()
