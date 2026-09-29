#!/usr/bin/env python3
"""sim-final.py 상수와 src/shared/Config/*.luau 가 같은지 확인한다(기획서 §13.1 W8 게이트).

실행: python3 docs/sim/check-config.py      (어디서 돌려도 된다. 하나라도 다르면 종료 코드 1)
§5.7 다이얼을 돌린 뒤 시뮬과 Config 를 같이 고쳤는지 이 한 줄로 다시 확인한다.
Luau 는 정규식으로 숫자만 읽는다. 표 모양(키 = 값)이 바뀌면 여기 정규식도 같이 고친다.
"""
import importlib.util
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # docs/sim 에 __pycache__ 를 남기지 않는다
HERE = Path(__file__).resolve().parent
CFG = HERE.parents[1] / "src" / "shared" / "Config"

spec = importlib.util.spec_from_file_location("sim_final", HERE / "sim-final.py")
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


eco, fac, stu, gacha = read("EconomyConfig.luau"), read("FacilityConfig.luau"), read("StudentConfig.luau"), read("GachaConfig.luau")

# 시설: 순서대로 (id, price, income, student, spawns)
facilities = [
    (fid, int(p), int(inc), st or None, int(sp))
    for fid, p, inc, st, sp in re.findall(
        r'id = "(\w+)",.*?price = (\d+),\s*income = (\d+),\s*student = (?:"(\w+)"|nil),.*?spawns = (\d+),',
        block(fac, "LIST"), re.S)
]
# 학생: id → (tier, unlock 종류, 값)
students = {
    sid: (tier, kind.lower(), num(val.strip('"')) if val[0].isdigit() else val.strip('"'))
    for sid, tier, kind, val in re.findall(
        r'id = "(s\d+)",.*?tier = "([^"]+)",.*?unlock = by(Facility|Graduation|Gacha)\(([^)]+)\)',
        block(stu, "LIST"), re.S)
}
contrib = {t: num(v) for t, v in re.findall(r'\["([^"]+)"\] = ([\d.]+)', block(stu, "CONTRIB"))}
rates = [(t, num(p)) for t, p in re.findall(r'tier = "([^"]+)", p = ([\d.]+)', block(gacha, "RATES"))]
dupe = {t: num(v) for t, v in re.findall(r'\["([^"]+)"\] = (\d+)', block(gacha, "DUPE_CELLS")) if t != "평범"}
pity_student = re.search(r'PITY_STUDENT = "(\w+)"', gacha).group(1)


def cum_spawns(adds, base=0):
    out, n = [], base
    for a in adds:
        n += a
        out.append(n)
    return out


rows = [(k, getattr(sim, k), scalar(eco, "EconomyConfig", k)) for k in
        ("START_COINS", "GRAD_STEP", "STICKER_MIN", "STICKER_SECONDS", "GOLD_EVERY", "GOLD_MULT", "RESPAWN", "BOARD_CELLS")]
rows += [
    ("PRICE_SCALE", sim.PRICE_SCALE, scalar(fac, "FacilityConfig", "PRICE_SCALE")),
    ("PITY", sim.PITY, scalar(gacha, "GachaConfig", "PITY")),
    ("RATES", sim.RATES, rates),
    ("DUPE_CELLS", sim.DUPE_CELLS, dupe),
    ("CONTRIB", sim.CONTRIB, contrib),
    ("COSMO / PITY_STUDENT", sim.COSMO, pity_student),
    ("시설 순서(id)", [f[0] for f in sim.FACILITIES], [f[0] for f in facilities]),
    ("시설 가격", [f[2] for f in sim.FACILITIES], [f[1] for f in facilities]),
    ("시설 초당 수입", [f[3] for f in sim.FACILITIES], [f[2] for f in facilities]),
    ("시설 확정 학생", [f[4] and f[4][0] for f in sim.FACILITIES], [f[3] for f in facilities]),
    ("시설 학생 등급", [f[4] and f[4][1] for f in sim.FACILITIES],
     [f[3] and students.get(f[3], ("?",))[0] for f in facilities]),
    ("스폰 누적(구매 후)", cum_spawns([f[5] for f in sim.FACILITIES], sim.BASE_SPAWNS), cum_spawns([f[4] for f in facilities])),
    ("졸업 확정 학생", {sid: (tier, g) for g, sid, _, tier in sim.GRAD_CONFIRMED},
     {sid: (t, v) for sid, (t, k, v) in students.items() if k == "graduation"}),
    ("뽑기 풀(등급, 해금)", {sid: (tier, g) for sid, _, tier, g in sim.POOL},
     {sid: (t, v) for sid, (t, k, v) in students.items() if k == "gacha"}),
    ("도감 id 전체", sorted([f[4][0] for f in sim.FACILITIES if f[4]] + sim.ALL_IDS), sorted(students)),
]


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
print("| 상수 | sim-final.py | Config | 결과 |\n|---|---|---|---|")
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
