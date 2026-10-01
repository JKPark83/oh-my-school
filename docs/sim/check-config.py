#!/usr/bin/env python3
"""sim-parts.py 상수와 src/shared/Config/*.luau 가 같은지 확인한다(기획서 §13.1 W8 게이트).

실행: python3 docs/sim/check-config.py      (어디서 돌려도 된다. 하나라도 다르면 종료 코드 1)
§5.7 다이얼을 돌린 뒤 시뮬과 Config 를 같이 고쳤는지 이 한 줄로 다시 확인한다.
Luau 는 정규식으로 숫자만 읽는다. 표 모양(키 = 값)이 바뀌면 여기 정규식도 같이 고친다.
학생 기여(CONTRIB)는 StudentConfig.luau 의 `["평범"] = 0.05` 행을 대조한다. 졸업 상수(GRAD_STEP·PRICE_SCALE)는 2026-10-01 폐기로 대조하지 않는다.
층 단계표는 RoomConfig.luau 의 `RoomConfig.STEPS` 안 `parts = { … }, income = N` 30행을 sim 의 STEP_TABLE 과 대조한다.
RoomConfig.luau 가 없으면(P2 전) 「RoomConfig 없음(P2)」 을 알리고 그 행은 건너뛴다(실패로 세지 않는다).
꾸미기 27개 가격은 DecorConfig.luau 의 `id = "planter"` 행 뒤 첫 `price = 123` 을 sim 의 DECOR_PRICES 와 대조한다.
DecorConfig.luau 가 없으면 「DecorConfig 없음」 으로 FAIL 하고 나머지는 끝까지 본다.
"""
import importlib.util
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # docs/sim 에 __pycache__ 를 남기지 않는다
HERE = Path(__file__).resolve().parent
CFG = HERE.parents[1] / "src" / "shared" / "Config"

spec = importlib.util.spec_from_file_location("sim_parts", HERE / "sim-parts.py")
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)


def read(name):
    return (CFG / name).read_text(encoding="utf-8")


def num(s):
    return float(s) if "." in s else int(s)


def scalar(src, table, key):
    m = re.search(rf"^{table}\.{key} = ([\d.]+)", src, re.M)
    return num(m.group(1)) if m else None


def block(src, name):
    """`local NAME ... = {` 부터 줄 맨 앞 `}` 까지(표 하나)"""
    m = re.search(rf"local {name}\b[^=]*= \{{(.*?)\n\}}", src, re.S)
    return m.group(1) if m else ""


eco, fac, mis, stu = (read("EconomyConfig.luau"), read("FacilityConfig.luau"), read("MissionConfig.luau"),
                      read("StudentConfig.luau"))

# 시설: 순서대로 (id, [부품 가격…], income, spawns)
facilities = [
    (fid, [int(x) for x in re.findall(r"\d+", parts)], int(inc), int(sp))
    for fid, parts, inc, sp in re.findall(
        r'id = "(\w+)",.*?parts = \{([\d,\s]*)\},\s*income = (\d+),.*?spawns = (\d+),',
        block(fac, "LIST"), re.S)
]


def decor_prices():
    """DecorConfig.luau 의 {id: price}. 파일이 없으면 None. 각 `id = "…"` 부터 다음 id 전까지에서 price 를 찾는다."""
    path = CFG / "DecorConfig.luau"
    if not path.exists():
        return None
    src = path.read_text(encoding="utf-8")
    ids = list(re.finditer(r'\bid = "(\w+)"', src))
    out = {}
    for i, m in enumerate(ids):
        end = ids[i + 1].start() if i + 1 < len(ids) else len(src)
        pm = re.search(r"\bprice = (\d+)", src[m.end():end])
        out[m.group(1)] = int(pm.group(1)) if pm else None
    return out


def room_steps():
    """RoomConfig.STEPS 의 [(부품 가격들, income)]. 파일이 없으면 None."""
    path = CFG / "RoomConfig.luau"
    if not path.exists():
        return None
    m = re.search(r"^RoomConfig\.STEPS\b[^=]*= \{(.*?)\n\}", path.read_text(encoding="utf-8"), re.S | re.M)
    rows = re.findall(r"parts = \{([\d,\s]*)\},\s*income = (\d+)", m.group(1) if m else "")
    return [([int(x) for x in re.findall(r"\d+", ps)], int(inc)) for ps, inc in rows]


def cum_spawns(adds, base=0):
    out, n = [], base
    for a in adds:
        n += a
        out.append(n)
    return out


rows = [(k, getattr(sim, k), scalar(eco, "EconomyConfig", k)) for k in
        ("START_COINS", "STICKER_MIN", "STICKER_SECONDS", "GOLD_EVERY", "GOLD_MULT", "RESPAWN",
         "BOARD_CELLS", "GIFT_COIN_VALUE")]
rows += [
    ("REWARD_CELLS", sim.REWARD_CELLS, scalar(mis, "MissionConfig", "REWARD_CELLS")),
    ("학생 기여(CONTRIB)", dict(sim.CONTRIB),
     {t: float(v) for t, v in re.findall(r'^\s*\["([^"]+)"\] = ([\d.]+),', block(stu, "CONTRIB"), re.M)}),
    ("시설 순서(id)", [f[0] for f in sim.FACILITIES], [f[0] for f in facilities]),
    ("시설 초당 수입", [f[2] for f in sim.FACILITIES], [f[2] for f in facilities]),
    ("스폰 누적(구매 후)", cum_spawns([f[3] for f in sim.FACILITIES], sim.BASE_SPAWNS), cum_spawns([f[3] for f in facilities])),
    ("시설별 부품 수", [f[4] for f in sim.FACILITIES], [len(f[1]) for f in facilities]),
    ("부품 가격(50개)", list(sim.PRICES), [p for f in facilities for p in f[1]]),
]
decor = decor_prices()
rows.append(("꾸미기 가격(27개)", dict(sim.DECOR_PRICES), decor if decor is not None else "DecorConfig 없음"))
steps = room_steps()
if steps is None:
    print("RoomConfig 없음(P2): 층 단계표 대조를 건너뛴다\n")
else:
    rows.append(("층 단계 부품 가격(30×4)", [r[5] for r in sim.STEP_TABLE], [s[0] for s in steps]))
    rows.append(("층 단계 수입(30개)", [r[2] for r in sim.STEP_TABLE], [s[1] for s in steps]))


def show(v):
    return str(v) if len(str(v)) <= 60 else str(v)[:57] + "..."


def diff(a, b):
    """긴 표에서 다른 칸만: 목록은 순번, 사전은 키"""
    if isinstance(a, list) and isinstance(b, list):
        n = max(len(a), len(b))
        pad = lambda xs: xs + [None] * (n - len(xs))
        return [(i + 1, x, y) for i, (x, y) in enumerate(zip(pad(a), pad(b))) if x != y]
    if isinstance(a, dict) and isinstance(b, dict):
        return [(k, a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
    return None


fails, details = 0, []
print("| 상수 | sim-parts.py | Config | 결과 |\n|---|---|---|---|")
for name, a, b in rows:
    ok = a == b
    fails += not ok
    print(f"| {name} | {show(a)} | {show(b)} | {'OK' if ok else 'FAIL'} |")
    if not ok and diff(a, b):
        details.append(f"- {name}: " + ", ".join(f"{k}: sim {x} ≠ Config {y}" for k, x, y in diff(a, b)))
print(f"\n{len(rows) - fails}/{len(rows)} 일치" + ("" if not fails else f" · 불일치 {fails}건"))
if details:
    print("\n".join(details))
sys.exit(1 if fails else 0)
