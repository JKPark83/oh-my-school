#!/usr/bin/env python3
"""「교장이 되어보자!」 경제 시뮬레이션 — 시설 부품 50개 + 층 단계 30개(개선계획 2026-10-01 §4)

실행: python3 docs/sim/sim-parts.py            > docs/sim/sim-parts-output.md

■ 수입(코드와 같다, EconomyConfig.incomePerSecond)
  초당 수입 = (Σ 완공 시설 income + Σ 완공 단계 income) × (1 + 보유 학생 기여 합). 졸업은 없다(2026-10-01 폐기).
  학생 기여(StudentConfig.CONTRIB): 평범 0.05 · 반장 0.15 · 전교1등 0.40 · 전설 0.60.
  - 시설 학생: 시설을 완공하면 그 시설 학생이 온다(StudentConfig unlock kind "facility"). 강당은 학생이 없다.
    14시설 완공 시점 기여 합 = 10 × 0.05 + 3 × 0.15 = 0.95.
  - 방 학생: 개선계획 §3.1 표 순서대로 방을 짓는다고 가정한다. 옥상 방은 6번째(옥상정원)·12번째(천문대) 단계.
    단계 1~12 를 처음 완공할 때 그 방 학생이 온다. 13단계부터는 새 학생이 없다(같은 방을 또 짓는다).
  - 친구 학생 3명(s14 반장·s17 전교1등·s22 전설, 친구 아이템 bookcart·telescope·rocket): 기준선은 사지 않는다.
    민감도 행 「친구 3명」은 살 수 있는 즉시 산다(부품보다 먼저, 같은 틱에 부품도 살 수 있으면 산다).

■ 시설 부품 50개(FacilityConfig parts)
  - 시설 14개 = 앞 6개 3부품 + 뒤 8개 4부품 = 50. 수입·학생은 시설 마지막 부품을 살 때만 붙는다.
  - 목표 간격 gap(k) = GAP_FIRST × (GAP_LAST/GAP_FIRST)^((k-2)/48). k=2 에서 5초, 단조 증가.
    부품 k 가격 = 「부품 k-1 까지 산 뒤의 활동형 수입(학생 기여 포함 + 스티커 기대 수입)」 × gap(k). k=1 = START_COINS.

■ 층 단계 30개(RoomConfig.STEPS) = 층 방 28개 + 옥상 방 2개
  - 단계 s 를 완공하면 base 수입(배율 전 Σ income)이 STEP_GROWTH(1.10)배가 되게 단계 수입 = nice(직전 base × 0.10).
  - 걸리는 시간 t(s) = T_FIRST + (T_PEAK − T_FIRST) × ((s−1)/19)^T_POW (s ≤ 20), 그 뒤 T_PEAK. 5분 → 60분, 단조 증가.
  - 단계 가격 = 직전(단계 s−1 완공 뒤) 활동형 초당 수입 × t(s). PART_WEIGHTS 0.1/0.2/0.3/0.4 로 나눠 각각 nice_price.
  - 단계 수입·학생은 부품 4(마무리 장식)를 살 때 붙는다. 스티커 스폰은 운동장 뒤 8 그대로다.

■ 스티커·구매
  스폰 3(처음부터) → 복도 완공 +2 → 운동장 완공 +3, 리스폰 15초, 활동형 회수율 55%, 방치형 0%.
  1장 = max(10, 초당 수입 × 1.2), 12장마다 황금 ×5 → 기대값 = 1장 × (11 + 5) / 12.
  스티커는 기대값 흐름(초당 스폰/15 × 회수율 × 기대값)으로 더한다. 무작위가 없어 결과는 항상 같다(결정적).
  그리디 구매: 1초 틱마다 수입을 더한 뒤, 살 수 있으면 부품 1개만 산다. 시설 50개 뒤 바로 단계 부품으로 넘어간다
  (방 고르기는 시간 0). 선물판 보상 0, 꾸미기 지출 0(보수적).

■ 꾸미기 가격표(decor_prices → DECOR_PRICES, DecorConfig.LIST 의 price). 회차 인자 없음.
  「초당수입」은 활동형 기준선 궤적에서 그 시각(또는 그 단계 완공) 뒤 시설·단계 수입 × 배율 + 스티커 기대 수입.
  - general 18: 싼 것(planter·flowerbed·signpost·mailbox) = 3:00 × 20초, 중간(bench·lamp·tree·bikerack) = 6:00 × 30초,
    큰 것(swing·slide·fountain·pond) = 10:00 × 45초. 옛 친구 아이템 6개는 큰 것보다 한 단계 위:
    ballbin·easel = 14:00 × 60초, globe·piano = 18:00 × 60초, labtable = 2단계 완공 × 60초, tiger = 4단계 완공 × 60초.
  - friend 3(bookcart·telescope·rocket) = 8:00 × 60초. gift 6 = 0(선물판 순번 1·2·3·5·8·12 에서만, GIFT_ORDER).

■ 선물판 코인 선물(gift_coin_basis → GIFT_COIN_VALUE)
  활동형 기준선에서 스티커 누적 기대 장수가 40장(BOARD_CELLS)이 되는 시각까지 스티커로 번 코인을 nice_price.

■ 가격 반올림(nice_price): 유효숫자 2자리 반올림(사사오입). 10 보다 작으면 10.

■ 방치형 첫 부품 가정: 책상이 서기 전 수입이 0 이라 방치형도 튜토리얼 스티커 3장(3·6·9초)은 줍는다. 그 뒤 회수율 0%.
"""
import math

START_COINS = 10
STICKER_MIN = 10
STICKER_SECONDS = 1.2
GOLD_EVERY = 12
GOLD_MULT = 5
RESPAWN = 15.0
BASE_SPAWNS = 3
COLLECT_ACTIVE = 0.55
COLLECT_IDLE = 0.0
GAP_FIRST = 5.0          # k=2 목표 간격(초)
GAP_LAST = 68.0          # k=50 목표 간격(초). 14시설 완공 19~21분에 맞춘 값
T_FIRST = 5 * 60         # 단계 1 목표 시간(초)
T_PEAK = 60 * 60         # 단계 20 이후 목표 시간(초)
T_POW = 1.8              # t(s) 곡선 지수. 20단계 누적 8.0~9.5시간에 맞춘 값
STEP_GROWTH = 1.10       # 단계 완공마다 base 수입 배수
STEPS = 30
PART_WEIGHTS = (0.1, 0.2, 0.3, 0.4)
IDLE_TUTORIAL_STICKERS = (3, 6, 9)   # 방치형이 줍는 튜토리얼 스티커 3장의 시각(초)
MAX_SECONDS = 72 * 3600
BOARD_CELLS = 40         # 선물판 40칸 = 선물 1개(EconomyConfig.BOARD_CELLS)
REWARD_CELLS = 20        # 미션 완료 = 선물판 +20칸(MissionConfig.REWARD_CELLS)
GIFT_COIN_VALUE = 6900   # 코인 선물(EconomyConfig.GIFT_COIN_VALUE). 근거는 gift_coin_basis()
GOLD_EV = ((GOLD_EVERY - 1) + GOLD_MULT) / GOLD_EVERY
DECOR_SPEND = 0.2        # 참고 행: 수입 중 꾸미기 지갑으로 떼는 비율

CONTRIB = {"평범": 0.05, "반장": 0.15, "전교1등": 0.40, "전설": 0.60}

# 꾸미기 27개(DecorConfig.LIST 순서): (id, 이름, 종류, 가격 근거)
# 근거 = ("time", 초, 곱할 초) | ("step", 완공 단계 수, 곱할 초) | ("gift",)
DECOR_ITEMS = [
    ("planter",   "화분",       "general", ("time", 180, 20)),
    ("bench",     "벤치",       "general", ("time", 360, 30)),
    ("lamp",      "가로등",     "general", ("time", 360, 30)),
    ("mailbox",   "우체통",     "general", ("time", 180, 20)),
    ("fountain",  "분수",       "general", ("time", 600, 45)),
    ("tree",      "나무",       "general", ("time", 360, 30)),
    ("flowerbed", "꽃밭",       "general", ("time", 180, 20)),
    ("signpost",  "표지판",     "general", ("time", 180, 20)),
    ("bikerack",  "자전거대",   "general", ("time", 360, 30)),
    ("swing",     "그네",       "general", ("time", 600, 45)),
    ("slide",     "미끄럼틀",   "general", ("time", 600, 45)),
    ("pond",      "연못",       "general", ("time", 600, 45)),
    ("balloons",  "풍선",       "gift",    ("gift",)),
    ("trophy",    "트로피",     "gift",    ("gift",)),
    ("teddy",     "곰인형",     "gift",    ("gift",)),
    ("rainbow",   "무지개깃발", "gift",    ("gift",)),
    ("starlamp",  "별조명",     "gift",    ("gift",)),
    ("cake",      "케이크",     "gift",    ("gift",)),
    ("bookcart",  "책수레",     "friend",  ("time", 480, 60)),
    ("telescope", "망원경",     "friend",  ("time", 480, 60)),
    ("rocket",    "로켓모형",   "friend",  ("time", 480, 60)),
    ("ballbin",   "공바구니",   "general", ("time", 840, 60)),
    ("easel",     "이젤",       "general", ("time", 840, 60)),
    ("globe",     "지구본",     "general", ("time", 1080, 60)),
    ("piano",     "피아노",     "general", ("time", 1080, 60)),
    ("labtable",  "실험탁자",   "general", ("step", 2, 60)),
    ("tiger",     "호랑이석상", "general", ("step", 4, 60)),
]
assert len(DECOR_ITEMS) == 27
assert [sum(1 for i in DECOR_ITEMS if i[2] == k) for k in ("general", "gift", "friend")] == [18, 6, 3]
GIFT_ORDER = {1: "balloons", 2: "trophy", 3: "teddy", 5: "rainbow", 8: "starlamp", 12: "cake"}
# 친구 아이템 → 학생 등급(DecorConfig student, StudentConfig tier). 민감도 행에서 이 순서로 산다
FRIENDS = [("bookcart", "s14", "반장"), ("telescope", "s17", "전교1등"), ("rocket", "s22", "전설")]

# (id, 이름, 초당 수입, 스티커 스폰 추가, 부품 수, 학생 등급 또는 None). 수입·스폰은 FacilityConfig.luau 와 같다.
# 책상의 spawns 3 은 Config 에서 책상에 붙어 있지만 여기서는 처음부터 있는 BASE_SPAWNS 로 본다.
FACILITIES = [
    ("desk",       "책상",   1,    0, 3, "평범"),
    ("board",      "칠판",   3,    0, 3, "평범"),
    ("locker",     "사물함", 6,    0, 3, "평범"),
    ("hall",       "복도",   12,   2, 3, "평범"),
    ("class2",     "교실2",  25,   0, 3, "평범"),
    ("cafeteria",  "급식실", 50,   0, 3, "평범"),
    ("library",    "도서관", 90,   0, 4, "평범"),
    ("nurse",      "보건실", 150,  0, 4, "평범"),
    ("science",    "과학실", 260,  0, 4, "평범"),
    ("music",      "음악실", 420,  0, 4, "평범"),
    ("gym",        "체육관", 700,  0, 4, "반장"),
    ("field",      "운동장", 1100, 3, 4, "반장"),
    ("principal",  "교장실", 1800, 0, 4, "반장"),
    ("auditorium", "강당",   3000, 0, 4, None),
]

# 단계 1~12 에 짓는다고 가정한 방(개선계획 §3.1 표 순서, 옥상 방은 6·12번째): (id, 이름, 학생, 등급)
ROOM_ORDER = [
    ("art",         "미술실",     "s16", "반장"),
    ("computer",    "컴퓨터실",   "s15", "반장"),
    ("broadcast",   "방송실",     "s21", "전교1등"),
    ("cooking",     "요리실",     "s25", "평범"),
    ("dance",       "댄스실",     "s26", "반장"),
    ("garden",      "옥상정원",   "s24", "전설"),
    ("robot",       "코딩로봇실", "s20", "전교1등"),
    ("english",     "영어체험실", "s19", "전교1등"),
    ("care",        "돌봄교실",   "s27", "평범"),
    ("staff",       "교무실",     "s18", "전교1등"),
    ("exhibit",     "전시실",     "s23", "전설"),
    ("observatory", "천문대",     "s28", "반장"),
]

# 부품 목록: (k, 시설 순번 0.., 시설 안 부품 순번 1.., 그 시설 마지막 부품인가)
PARTS = []
for fi, f in enumerate(FACILITIES):
    for j in range(1, f[4] + 1):
        PARTS.append((len(PARTS) + 1, fi, j, j == f[4]))
assert len(PARTS) == 50
NF = len(PARTS)
# 산 부품 수 n → 완공 시설 수(누적표)
BUILT_AFTER = [sum(1 for k, _, _, last in PARTS if k <= n and last) for n in range(NF + 1)]


def gap(k):
    return GAP_FIRST * (GAP_LAST / GAP_FIRST) ** ((k - 2) / 48)


def step_time(s):
    if s >= 20:
        return T_PEAK
    return T_FIRST + (T_PEAK - T_FIRST) * ((s - 1) / 19) ** T_POW


def nice_price(x):
    """유효숫자 2자리 반올림, 바닥 10."""
    if x < 10:
        return 10
    mag = 10 ** (int(math.floor(math.log10(x))) - 1)
    return int(math.floor(x / mag + 0.5)) * mag


STEP_INCOME = []   # 단계 s 완공 수입(step_table 이 채운다)


def state(n, friends=0):
    """구매 n 개(시설 부품 50 + 단계 부품 4 × 단계) 뒤 (base, 배율, 스폰, 완공 시설 수, 완공 단계 수)."""
    built = BUILT_AFTER[min(n, NF)]
    steps = max(0, n - NF) // len(PART_WEIGHTS)
    base = sum(f[2] for f in FACILITIES[:built]) + sum(STEP_INCOME[:steps])
    contrib = sum(CONTRIB[f[5]] for f in FACILITIES[:built] if f[5])
    contrib += sum(CONTRIB[r[3]] for r in ROOM_ORDER[:steps])
    contrib += sum(CONTRIB[f[2]] for f in FRIENDS[:friends])
    spawns = BASE_SPAWNS + sum(f[3] for f in FACILITIES[:built])
    return base, 1 + contrib, spawns, built, steps


def sticker_value(income):
    return max(STICKER_MIN, income * STICKER_SECONDS)


def sticker_flow(income, spawns, collect):
    """초당 스티커 기대 수입."""
    return spawns / RESPAWN * collect * sticker_value(income) * GOLD_EV


def active_income(n, friends=0):
    """구매 n 개 뒤 활동형 초당수입(시설·단계 × 배율 + 스티커 기대값)."""
    base, mult, spawns, _, _ = state(n, friends)
    inc = base * mult
    return inc + sticker_flow(inc, spawns, COLLECT_ACTIVE)


def price_table():
    """시설 부품 가격표. 행 = (k, 시설 순번, 부품 순번, 원가, 가격, 그 시점 활동형 수입, 목표 간격)."""
    rows = []
    for k, fi, j, _ in PARTS:
        if k == 1:
            rows.append((k, fi, j, START_COINS, START_COINS, 0.0, 0.0))
            continue
        active = active_income(k - 1)
        raw = active * gap(k)
        rows.append((k, fi, j, raw, nice_price(raw), active, gap(k)))
    return rows


def step_table():
    """단계표. 행 = (s, 직전 base, 단계 수입, 직전 활동형 수입, t(s), 부품 4개 가격). STEP_INCOME 을 채운다."""
    rows = []
    for s in range(1, STEPS + 1):
        n = NF + (s - 1) * len(PART_WEIGHTS)
        base = state(n)[0]
        income = nice_price(base * (STEP_GROWTH - 1))
        act = active_income(n)
        parts = [nice_price(act * step_time(s) * w) for w in PART_WEIGHTS]
        STEP_INCOME.append(income)
        rows.append((s, base, income, act, step_time(s), parts))
    return rows


TABLE = price_table()
PRICES = [r[4] for r in TABLE]
STEP_TABLE = step_table()
STEP_PRICES = [p for r in STEP_TABLE for p in r[5]]
ALL_PRICES = PRICES + STEP_PRICES
NALL = len(ALL_PRICES)


def simulate(collect=COLLECT_ACTIVE, tutorial=False, friends=False, goal=NALL, spend=0.0, decor=False):
    """1초 틱으로 구매 goal 개까지 돈다. friends=True 면 친구 아이템 3개를 살 수 있는 즉시 산다.
    spend·decor 는 참고 행: 뗀 몫을 꾸미기 지갑에 모아 DECOR_BUY_ORDER 를 한 번씩 사고, 선물판(GIFT_ORDER)도 돈다."""
    coins = float(START_COINS)
    bought = 0
    nfriend = 0
    buy_times = []
    friend_times = []
    t = 0
    stickers = 0.0        # 누적 기대 장수(튜토리얼 스티커 포함)
    sticker_coins = 0.0   # 스티커로 번 코인 합
    board_at = None       # 누적 장수가 BOARD_CELLS 에 닿은 시각
    board_coins = None    # 그때까지 스티커로 번 코인
    wallet = 0.0          # 꾸미기 지갑(decor)
    decor_times = []      # (시각, id)
    gifts = []            # (시각, 순번, id 또는 None=코인)

    def try_buy():
        nonlocal coins, bought, nfriend
        if friends and nfriend < len(FRIENDS):
            fp = DECOR_PRICES[FRIENDS[nfriend][0]]
            if coins >= fp - 1e-9:
                coins -= fp
                nfriend += 1
                friend_times.append(t)
        if bought < goal and coins >= ALL_PRICES[bought] - 1e-9:
            coins -= ALL_PRICES[bought]
            bought += 1
            buy_times.append(t)

    try_buy()
    while bought < goal and t < MAX_SECONDS:
        t += 1
        base, mult, spawns, _, _ = state(bought, nfriend)
        inc = base * mult
        st = sticker_flow(inc, spawns, collect)
        gain = inc + st
        stickers += spawns / RESPAWN * collect
        sticker_coins += st
        if tutorial and t in IDLE_TUTORIAL_STICKERS:
            gain += round(sticker_value(inc))
            stickers += 1
            sticker_coins += round(sticker_value(inc))
        if board_at is None and stickers >= BOARD_CELLS:
            board_at, board_coins = t, sticker_coins
        if decor:
            while stickers >= BOARD_CELLS * (len(gifts) + 1):
                idx = len(gifts) + 1
                item = GIFT_ORDER.get(idx)
                gifts.append((t, idx, item))
                if item is None:
                    gain += GIFT_COIN_VALUE
            if len(decor_times) < len(DECOR_BUY_ORDER):
                wallet += gain * spend
                coins += gain * (1 - spend)
                nxt = DECOR_BUY_ORDER[len(decor_times)]
                if wallet >= DECOR_PRICES[nxt] - 1e-9:
                    wallet -= DECOR_PRICES[nxt]
                    decor_times.append((t, nxt))
                    if len(decor_times) == len(DECOR_BUY_ORDER):
                        coins += wallet
                        wallet = 0.0
            else:
                coins += gain
        else:
            coins += gain
        try_buy()
    return dict(buy_times=buy_times, done=buy_times[-1] if bought == goal else None, bought=bought,
                board_at=board_at, board_coins=board_coins, decor_times=decor_times, gifts=gifts,
                friend_times=friend_times)


def baseline_buy_times():
    """활동형 기준선(친구 없음·꾸미기 없음) 구매 시각. decor_prices 가 쓴다(DECOR_PRICES 전에 돈다)."""
    t, coins, bought, times = 0, float(START_COINS), 0, []
    while True:
        if coins >= ALL_PRICES[bought] - 1e-9:
            coins -= ALL_PRICES[bought]
            bought += 1
            times.append(t)
        if bought == NALL:
            return times
        t += 1
        coins += active_income(bought)


BASE_TIMES = baseline_buy_times()


def decor_prices():
    """꾸미기 27개 가격. {id: (가격, 반올림 전, 근거 문구)}."""
    out = {}
    for iid, _, kind, basis in DECOR_ITEMS:
        if basis[0] == "gift":
            out[iid] = (0, 0.0, "선물판 전용(상점 없음)")
        elif basis[0] == "time":
            sec, mult = basis[1], basis[2]
            n = sum(1 for x in BASE_TIMES if x <= sec)
            inc = active_income(n)
            raw = inc * mult
            out[iid] = (nice_price(raw), raw, f"활동형 {sec // 60}:{sec % 60:02d} 초당 {inc:,.1f} × {mult}초")
        else:
            s, mult = basis[1], basis[2]
            inc = active_income(NF + s * len(PART_WEIGHTS))
            raw = inc * mult
            out[iid] = (nice_price(raw), raw, f"활동형 {s}단계 완공 초당 {inc:,.1f} × {mult}초")
    return out


DECOR_TABLE = decor_prices()
DECOR_PRICES = {k: v[0] for k, v in DECOR_TABLE.items()}
# 참고 행이 사는 순서: 옛 general 12(3:00~10:00 근거)를 싼 것부터, 같은 값이면 LIST 순
DECOR_BUY_ORDER = sorted((i[0] for i in DECOR_ITEMS if i[2] == "general" and i[3][0] == "time" and i[3][1] <= 600),
                         key=lambda x: DECOR_PRICES[x])


def gift_coin_basis():
    """활동형 첫 선물판(스티커 40장)이 차는 시각과 그때까지 스티커로 번 코인. (시각, 코인, 반올림 값)"""
    r = simulate(goal=NF)
    return r["board_at"], r["board_coins"], nice_price(r["board_coins"])


def clock(t):
    if t is None:
        return "미완료"
    t = int(round(t))
    if t >= 3600:
        return f"{t // 3600}:{t % 3600 // 60:02d}:{t % 60:02d}"
    return f"{t // 60:02d}:{t % 60:02d}"


def hours(t):
    return "미완료" if t is None else f"{t / 3600:.2f}시간"


def fmt(n):
    return f"{int(round(n)):,}"


def max_gap(times):
    gaps = [b - a for a, b in zip(times, times[1:])]
    i = max(range(len(gaps)), key=lambda x: gaps[x])
    return gaps[i], i + 2


def step_done(times, s):
    """단계 s 완공 시각(마지막 부품 구매 시각)."""
    k = NF + s * len(PART_WEIGHTS)
    return times[k - 1] if len(times) >= k else None


def count_at(times, sec):
    parts = sum(1 for x in times if x <= sec)
    return parts, BUILT_AFTER[min(parts, NF)]


def facility_done_time(times, fi):
    k = max(k for k, f, j, last in PARTS if f == fi)
    return times[k - 1]


def self_check():
    assert len(PRICES) == 50 and len(STEP_TABLE) == 30 and len(STEP_PRICES) == 120
    gaps = [gap(k) for k in range(2, NF + 1)]
    assert gaps[0] == GAP_FIRST and all(a < b for a, b in zip(gaps, gaps[1:])), "부품 목표 간격이 단조 증가가 아니다"
    ts = [step_time(s) for s in range(1, STEPS + 1)]
    assert all(a < b for a, b in zip(ts[:20], ts[1:20])) and all(x == T_PEAK for x in ts[19:]), "t(s) 가 단조가 아니다"
    fac = BASE_TIMES[NF - 1]
    s20 = step_done(BASE_TIMES, 20)
    assert 19 * 60 <= fac <= 21 * 60, f"14시설 완공 {clock(fac)} 이 19~21분 밖"
    assert 8.0 * 3600 <= s20 <= 9.5 * 3600, f"20단계 누적 {hours(s20)} 이 8.0~9.5시간 밖"


def main():
    self_check()
    active = simulate()
    assert active["buy_times"] == BASE_TIMES, "baseline_buy_times 가 simulate 궤적과 다르다"
    idle = simulate(collect=COLLECT_IDLE, tutorial=True)
    friend = simulate(friends=True)
    board_at, board_coins, gift = gift_coin_basis()
    assert gift == GIFT_COIN_VALUE, f"GIFT_COIN_VALUE {GIFT_COIN_VALUE} ≠ 근거 {gift}"
    at = BASE_TIMES

    print("# 경제 시뮬레이션 출력 — 시설 부품 50개 + 층 단계 30개 (python3 docs/sim/sim-parts.py)")
    print("\n**가정**: 초당 수입 = (Σ 시설 income + Σ 단계 income) × (1 + 학생 기여 합), 졸업 없음. "
          "시설 학생 13명(강당 제외)은 시설 완공 때, 방 학생 12명은 단계 1~12 완공 때(개선계획 §3.1 순서, 옥상 방 6·12번째) 온다. "
          "친구 학생 3명은 기준선에서 사지 않는다. 선물판 보상 0 · 꾸미기 지출 0 · 미션·별·콤보 0(보수적). "
          "스티커 스폰 3 → 복도 +2 → 운동장 +3, 리스폰 15초, 회수율 활동형 55%·방치형 0%, "
          "1장 = max(10, 초당 수입×1.2), 12장마다 황금 ×5(기대값 흐름). 그리디 구매, 1초 틱에 부품 1개. "
          "방치형은 튜토리얼 스티커 3장(3·6·9초)만 줍는다. 무작위 없음(결정적).")
    print(f"\n**가격 규칙**: 시설 부품 k = (k-1 까지 산 뒤 활동형 수입) × gap(k), gap(k) = {GAP_FIRST:g} × "
          f"({GAP_LAST:g}/{GAP_FIRST:g})^((k-2)/48) 초, k=1 = {START_COINS}. "
          f"단계 s = (단계 s-1 완공 뒤 활동형 수입) × t(s), t(s) = {T_FIRST // 60}분 + {(T_PEAK - T_FIRST) // 60}분 × "
          f"((s-1)/19)^{T_POW:g} (s ≤ 20), 그 뒤 {T_PEAK // 60}분. 부품 4개 = × {'/'.join(f'{w:g}' for w in PART_WEIGHTS)}. "
          f"단계 수입 = 직전 base × {STEP_GROWTH - 1:.2f}. 전부 유효숫자 2자리 반올림(10 미만은 10).")

    # 핵심 숫자
    print("\n## 요약(활동형 기준선)\n")
    print("| 지표 | 값 | 목표 |")
    print("|---|---|---|")
    g_act, k_act = max_gap(at[:NF])
    print(f"| 14시설(강당) 완공 | **{clock(at[NF - 1])}** · 시설 구간 최대 간격 {g_act}초(k={k_act}) | 19:00~21:00 |")
    print(f"| 3층(1단계) 완공 | **{clock(step_done(at, 1))}** | 약 25분 |")
    for s in (10, 20, 30):
        print(f"| {s}단계 완공 | **{clock(step_done(at, s))}** ({hours(step_done(at, s))}) |"
              f"{' 8.0~9.5시간 |' if s == 20 else ' — |'}")
    last = STEP_TABLE[-1]
    print(f"| 마지막 단계(30) 가격 | 부품 {' · '.join(fmt(p) for p in last[5])} = **{fmt(sum(last[5]))}** | — |")
    p5, f5 = count_at(at, 300)
    print(f"| 첫 5분(5:00) | 부품 {p5}개 · 시설 {f5}개 | — |")
    print(f"| GIFT_COIN_VALUE | {GIFT_COIN_VALUE:,}(스티커 {BOARD_CELLS}장이 {clock(board_at)} 에 차고 그때까지 {fmt(board_coins)}) | — |")

    print("\n## (a) 시설 부품 50개 가격표\n")
    print("| 시설 | k | 부품 | 가격 | 반올림 전 | 그 시점 활동형 수입(/s) | 목표 간격 | 실제 간격(활동형) | 구매 시각 |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for (k, fi, j, raw, price, inc, g), t in zip(TABLE, at):
        real = "—" if k == 1 else f"{t - at[k - 2]}초"
        gtxt = "—" if k == 1 else f"{g:.1f}초"
        print(f"| {FACILITIES[fi][1]} | {k} | {j}/{FACILITIES[fi][4]} | {fmt(price)} | {raw:,.1f} | {inc:,.1f} | {gtxt} | {real} | {clock(t)} |")
    print(f"\n가격 합계: **{sum(PRICES):,}**")

    print("\n## (b) 층 단계표 30행\n")
    print("방은 단계 1~12 를 개선계획 §3.1 순서(옥상 방 6·12번째)로 짓는다고 가정한다. 「층」은 옥상 방을 빼고 센 층 번호. "
          "「예상 간격」= t(s), 「실제」= 활동형 기준선에서 직전 단계 완공부터 걸린 시간.\n")
    print("| s | 방(가정) | 층 | 부품1 | 부품2 | 부품3 | 부품4 | 합계 | 단계 수입 | base 배수 | 배율 뒤 | 예상 간격 | 실제 | 누적 완공 |")
    print("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    floor = 2
    for s, base, inc, act, ts, parts in STEP_TABLE:
        room = ROOM_ORDER[s - 1] if s <= len(ROOM_ORDER) else None
        roof = room is not None and room[0] in ("garden", "observatory")
        if not roof:
            floor += 1
        name = f"{room[1]}({room[2]} {room[3]})" if room else "(반복, 학생 없음)"
        mult = state(NF + s * len(PART_WEIGHTS))[1]
        prev = step_done(at, s - 1) if s > 1 else at[NF - 1]
        print(f"| {s} | {name} | {'옥상' if roof else floor} | " + " | ".join(fmt(p) for p in parts) +
              f" | {fmt(sum(parts))} | {fmt(inc)} | ×{(base + inc) / base:.3f} | ×{mult:.2f} | "
              f"{ts / 60:.1f}분 | {(step_done(at, s) - prev) / 60:.1f}분 | {clock(step_done(at, s))} |")

    print_decor_prices()

    print("\n## (d) 민감도\n")
    rows = [("활동형 55%(기준선)", active), ("방치형 0%", idle), ("친구 3명 즉시 구매(활동형)", friend),
            ("회수율 40%", simulate(collect=0.40)), ("회수율 70%", simulate(collect=0.70))]
    print("| 궤적 | 14시설 완공 | 3층(1단계) | 10단계 | 20단계 | 30단계 |")
    print("|---|---:|---:|---:|---:|---:|")
    for label, r in rows:
        bt = r["buy_times"]
        fac = bt[NF - 1] if len(bt) >= NF else None
        print(f"| {label} | {clock(fac)} | {clock(step_done(bt, 1))} | {hours(step_done(bt, 10))} | "
              f"{hours(step_done(bt, 20))} | {hours(step_done(bt, 30))} |")
    fr_fac = friend["buy_times"][NF - 1]
    print(f"\n친구 3명 구매 시각: " + " · ".join(f"{f[0]}({f[1]} {f[2]}) {clock(t)}" for f, t in zip(FRIENDS, friend["friend_times"]))
          + f". 친구 3명이어도 14시설 완공 {clock(fr_fac)} — 16분 {'아래로 내려가지 않는다' if fr_fac >= 16 * 60 else '**아래로 내려간다**'}.")

    da = simulate(goal=NF, spend=DECOR_SPEND, decor=True)
    di = simulate(goal=NF, collect=COLLECT_IDLE, tutorial=True, spend=DECOR_SPEND, decor=True)
    print_decor_ref(da, di)
    print_luau()


def print_decor_ref(da, di):
    print("\n### 참고: 수입 20% 를 꾸미기에 쓴다(게이트 아님, 14시설 완공까지)\n")
    print(f"수입(시설·스티커·코인 선물)의 {DECOR_SPEND:.0%} 를 꾸미기 지갑에 모아 일반 소품 중 3:00~10:00 근거 12개를 싼 것부터 한 번씩 산다"
          f"(순서: {' → '.join(DECOR_BUY_ORDER)}, 합계 {sum(DECOR_PRICES[x] for x in DECOR_BUY_ORDER):,}). "
          "12개를 다 사면 남은 지갑은 부품 쪽으로 돌리고 더 떼지 않는다. "
          f"선물판은 스티커 누적 기대 {BOARD_CELLS}장마다 선물 1개(미션 +{REWARD_CELLS}칸·콤보 칸 무시), "
          f"순번 {'·'.join(str(k) for k in sorted(GIFT_ORDER))} 은 소품, 나머지는 코인 {GIFT_COIN_VALUE:,}.\n")
    print("| 궤적 | 강당 완공 | 일반 12개 다 산 시각 | 첫 선물 | 선물 수(완공까지) | 그중 코인 선물 |")
    print("|---|---:|---:|---:|---:|---:|")
    for label, r in (("활동형(55%)", da), ("방치형(0%)", di)):
        dt = r["decor_times"]
        d_done = clock(dt[-1][0]) if len(dt) == len(DECOR_BUY_ORDER) else f"미완료({len(dt)}/{len(DECOR_BUY_ORDER)})"
        gs = [g for g in r["gifts"] if r["done"] is None or g[0] <= r["done"]]
        first = clock(gs[0][0]) if gs else "없음"
        coin_n = sum(1 for g in gs if g[2] is None)
        print(f"| {label} | **{clock(r['done'])}** | {d_done} | {first} | {len(gs)} | {coin_n} |")


def print_decor_prices():
    print("\n## (c) 꾸미기 가격표(DecorConfig.LIST price)\n")
    print("선물 소품은 0(상점 없음). 회차 인자 없음(priceOf = 표 값).\n")
    print("| # | id | 이름 | 종류 | 가격 | 반올림 전 | 근거 |")
    print("|---:|---|---|---|---:|---:|---|")
    for i, (iid, name, kind, _) in enumerate(DECOR_ITEMS, 1):
        price, raw, why = DECOR_TABLE[iid]
        print(f"| {i} | {iid} | {name} | {kind} | {fmt(price)} | {raw:,.1f} | {why} |")
    gen = sum(DECOR_PRICES[i[0]] for i in DECOR_ITEMS if i[2] == "general")
    fr = sum(DECOR_PRICES[i[0]] for i in DECOR_ITEMS if i[2] == "friend")
    print(f"\n합계: 일반 18개 {gen:,} · 친구 3개 {fr:,} · 전부 1회 구매 {gen + fr:,}")


def print_luau():
    print("\n## (e) Luau 붙여 넣기용\n")
    print("FacilityConfig.LIST 의 `parts`(시설 순서대로 14줄):\n")
    print("```lua")
    for fi, f in enumerate(FACILITIES):
        ps = [PRICES[k - 1] for k, f2, _, _ in PARTS if f2 == fi]
        print(f"\t\tparts = {{ {', '.join(str(p) for p in ps)} }}, -- {f[0]} {f[1]}")
    print("```\n")
    print("RoomConfig.STEPS(30줄):\n")
    print("```lua")
    print("RoomConfig.STEPS = {")
    for s, _, inc, _, _, parts in STEP_TABLE:
        print(f"\t{{ parts = {{ {', '.join(str(p) for p in parts)} }}, income = {inc} }}, -- {s}")
    print("}")
    print("```\n")
    print("DecorConfig.LIST 의 `price`(LIST 순서, id = price):\n")
    print("```lua")
    print("{")
    for iid, name, kind, _ in DECOR_ITEMS:
        print(f"\t{iid} = {DECOR_PRICES[iid]}, -- {name} {kind}")
    print("}")
    print("```\n")
    print("EconomyConfig 상수:\n")
    print("```lua")
    print(f"EconomyConfig.START_COINS = {START_COINS}")
    print(f"EconomyConfig.GIFT_COIN_VALUE = {GIFT_COIN_VALUE}")
    print("```")


if __name__ == "__main__":
    main()
