--!strict
--[[
	부지 좌표의 단일 소스. 개선계획 §3.5 #2, §3.6 #2, §3.2 #4.
	좌표는 전부 부지 로컬(중심 0,0, +Z 가 교문 쪽)이고 바닥 윗면은 y=0 이다.
	PlotShell·auditorium(서버)과 스티커·꾸미기·탑(서버·클라)이 같은 값을 읽는다.

	로드 때 탑 배치를 assert 로 검사한다(§3.6 #2 (a)~(d)). 틀리면 require 가 실패해 부팅이 멈춘다.
]]

local FacilityConfig = require(script.Parent.Config.FacilityConfig)

local PlotLayout = {}

-- ── 부지 ─────────────────────────────────────────────────────────
PlotLayout.PLOT_HALF = 75
PlotLayout.GATE_Z = 67.5
PlotLayout.WALL_H = 18
PlotLayout.FLOOR_T = 1 -- 부지 바닥판 두께. 윗면이 y=0
PlotLayout.SPAWN = Vector3.new(0, 0, 60)
PlotLayout.CELL = 5 -- 꾸미기 격자 한 칸(§3.5 격자)
PlotLayout.GRID = 30 -- 꾸미기 격자 한 변 칸 수. CELL × GRID = 150 = 부지 한 변

-- ── 껍데기 고정물(PlotShell 이 짓고, 꾸미기 정적 마스크가 피한다) ──
PlotLayout.GATE_W = 12 -- 교문 기둥 안쪽 면 사이. 앞마당 길 폭과 같다
PlotLayout.GATE_PILLAR = 1.5 -- 교문 기둥 한 변
PlotLayout.SIGNPOST = Vector3.new(-12.5, 0, 62.5) -- 「우리 학교로」 팻말
PlotLayout.ADMISSION = Vector3.new(15, 0, 57.5) -- 접수대(몸통 4×4)
PlotLayout.FLAGPOLE = Vector3.new(-12.5, 0, 57.5)
PlotLayout.TREES = { Vector2.new(37.5, 50), Vector2.new(-10, 12.5) }
-- 현관 (0,-5) 30×25(계단·착지대가 안에 있다). 남문 (0,7.5), 북문 (0,-17.5)
PlotLayout.ENTRANCE = Vector3.new(0, 0, -5)
PlotLayout.ENTRANCE_SIZE = Vector3.new(30, PlotLayout.WALL_H, 25)
-- 교실1 (-60,-47.5) 30×30. 남문 (-60,-32.5)
PlotLayout.CLASS1 = Vector3.new(-60, 0, -47.5)
PlotLayout.CLASS1_SIZE = Vector3.new(30, PlotLayout.WALL_H, 30)

-- ── 2층 계단·착지대(§3.6 수치: 바꾸지 않는다) ──────────────────
-- 계단 11단(높이 1.5)을 x 5~14 · z 6 → -10.5 로 두고 12단째를 착지대(y18)로 삼는다
PlotLayout.STAIR_X0 = 5
PlotLayout.STAIR_X1 = 14 -- 현관 동쪽 벽 안쪽 면
PlotLayout.STAIR_Z_BOTTOM = 6
PlotLayout.STAIR_STEPS = 11 -- 1.5 × 12 = 18. 12단째가 착지대
PlotLayout.STAIR_RISE = 1.5
PlotLayout.STAIR_RUN = 1.5
-- 착지대 x -5~14 · z -16.5~-10.5. 윗면 y18(LANDING.Y 가 윗면)
PlotLayout.LANDING = Vector3.new(4.5, PlotLayout.WALL_H, -13.5)
PlotLayout.LANDING_SIZE = Vector3.new(19, 1, 6)
-- 현관 지붕·강당 바닥에 뚫는 구멍의 북쪽 끝(x STAIR_X0~STAIR_X1)
PlotLayout.STAIRWELL_Z0 = -10.5

-- ── 강당(2층) ────────────────────────────────────────────────────
PlotLayout.AUDITORIUM_FLOOR_T = 0.2 -- 강당 바닥판 두께. 바닥 윗면 = WALL_H + 0.2 = 18.2
PlotLayout.AUDITORIUM_ROOF_T = 1
-- 좌석 격자(부지 로컬). 5열 × 5줄 = S01…S25, index = (줄-1)*5 + 열. 줄마다 긴 벤치 하나
PlotLayout.AUDITORIUM_SEAT_COLS = { -17.9, -15.5, -13.1, -10.7, -8.3 }
PlotLayout.AUDITORIUM_SEAT_ROWS = { -23, -20, -17, -14, -11 }
PlotLayout.AUDITORIUM_BENCH_W = 12.4
PlotLayout.AUDITORIUM_BENCH_D = 1.6

-- ── 탑(3층부터, §3.6) ────────────────────────────────────────────
-- 3층 바닥 = 강당 지붕 윗면 = 1층 벽 18 + 강당 바닥 0.2 + 강당 높이 18 + 지붕 1
PlotLayout.TOWER_BASE_Y = PlotLayout.WALL_H
	+ PlotLayout.AUDITORIUM_FLOOR_T
	+ PlotLayout.WALL_H
	+ PlotLayout.AUDITORIUM_ROOF_T
PlotLayout.FLOOR_STEP = 19 -- n층 바닥 y = TOWER_BASE_Y + (n-3) × FLOOR_STEP
-- 탑 후보 40×30 = 8×6칸
PlotLayout.TOWER_FOOTPRINT = { x0 = -20, x1 = 20, z0 = -35, z1 = -5 }
-- 엘리베이터 칸(2층~꼭대기 같은 x·z). 강당 동쪽, 동쪽 커튼(z -28.5)과 착지대(x ≤14) 사이
PlotLayout.ELEVATOR = Vector2.new(17.5, -17.5)
-- 층 구매 패드. 2층 강당 바닥 윗면, 엘리베이터 칸 바로 남쪽 칸
PlotLayout.TOWER_PAD = Vector3.new(17.5, PlotLayout.WALL_H + PlotLayout.AUDITORIUM_FLOOR_T, -12.5)
PlotLayout.TOWER_PAD_SIZE = Vector2.new(4, 4) -- 시설 패드(PlotShell PAD_SIZE)와 같은 발자국

--- 루트 Y → 층 번호(1, 2, 3, …). 2층은 강당 바닥(18.2)부터, 3층은 TOWER_BASE_Y 부터
function PlotLayout.floorOf(y: number): number
	if y < PlotLayout.WALL_H then
		return 1
	end
	if y < PlotLayout.TOWER_BASE_Y then
		return 2
	end
	return 3 + math.floor((y - PlotLayout.TOWER_BASE_Y) / PlotLayout.FLOOR_STEP)
end

-- ── 스티커(§3.2 #4·#5·#10) ───────────────────────────────────────
PlotLayout.MIN_GAP = 8 -- 다른 활성 스티커와 최소 거리
PlotLayout.AVOID_OWNER = 10 -- 주인에게서 최소 거리

export type StickerZone = {
	name: string,
	facilityId: string?, -- 이 시설 바닥 위 구역. floorY 는 그 시설이 지어졌을 때의 바닥 윗면
	floorY: number,
	spots: { Vector2 },
}

-- 후보는 5 격자 칸 중심(x·z ≡ 2.5 mod 5). 건물·패드와 둘레·스폰·국기봉·팻말·접수대·나무·별·교문·문 앞·
-- 운동장 트랙·하프라인·골대·복도 줄무늬를 피했다. 홈 자리(HOME_SPOTS)와도 4 이상 떨어진다.
PlotLayout.STICKER_ZONES = {
	{
		name = "yard",
		floorY = 0,
		spots = {
			Vector2.new(-57.5, 12.5),
			Vector2.new(-37.5, 12.5),
			Vector2.new(-2.5, 17.5),
			Vector2.new(12.5, 17.5),
			Vector2.new(27.5, 17.5),
			Vector2.new(52.5, 12.5),
			Vector2.new(67.5, 12.5),
			Vector2.new(2.5, 27.5),
			Vector2.new(17.5, 27.5),
			Vector2.new(32.5, 27.5),
			Vector2.new(7.5, 37.5),
			Vector2.new(32.5, 37.5),
			Vector2.new(7.5, 47.5),
			Vector2.new(22.5, 47.5),
			Vector2.new(27.5, 57.5),
			Vector2.new(-27.5, 62.5),
			Vector2.new(-47.5, 62.5),
			Vector2.new(-67.5, 62.5),
			Vector2.new(57.5, 62.5),
		},
	},
	{
		name = "field",
		facilityId = "field",
		floorY = 0.2, -- field.luau GROUND_T
		spots = {
			Vector2.new(-67.5, 22.5),
			Vector2.new(-52.5, 27.5),
			Vector2.new(-37.5, 22.5),
			Vector2.new(-22.5, 27.5),
			Vector2.new(-57.5, 37.5),
			Vector2.new(-32.5, 37.5),
			Vector2.new(-67.5, 47.5),
			Vector2.new(-52.5, 52.5),
			Vector2.new(-37.5, 47.5),
			Vector2.new(-22.5, 52.5),
		},
	},
	{
		name = "hall",
		facilityId = "hall",
		floorY = 0.2, -- hall.luau FLOOR_T
		spots = {
			Vector2.new(-67.5, -27.5),
			Vector2.new(-42.5, -27.5),
			Vector2.new(-2.5, -27.5),
			Vector2.new(37.5, -27.5),
			Vector2.new(67.5, -27.5),
			Vector2.new(-47.5, -22.5),
			Vector2.new(-17.5, -22.5),
			Vector2.new(12.5, -22.5),
			Vector2.new(47.5, -22.5),
		},
	},
} :: { StickerZone }

-- 스티커 번호 1~8 의 홈 자리(켜기·끄기·튜토리얼 때). 앞마당 3 · 복도 2 · 운동장 3
PlotLayout.HOME_SPOTS = {
	Vector2.new(-7.5, 32.5),
	Vector2.new(0, 45),
	Vector2.new(25, 37.5),
	Vector2.new(-52.5, -27.5), -- 복도 줄무늬(z -25.8~-24.2)·북벽 문(x ±60, 폭 8) 밖
	Vector2.new(52.5, -27.5),
	Vector2.new(-60, 25),
	Vector2.new(-47.5, 42.5), -- 운동장 하프라인(x -45) 밖. 판 윗면이 하프라인 윗면과 겹치지 않게
	Vector2.new(-30, 50),
}
-- 방문객 별 2자리(고정, §7 질문 10). 마당 바닥이라 floorY 0
PlotLayout.STAR_SPOTS = { Vector2.new(-10, 52.5), Vector2.new(10, 52.5) }
PlotLayout.STAR_FLOOR_Y = 0

-- ── 꾸미기 격자(§3.5 #4) ────────────────────────────────────────
--- 칸 (cx, cz) 의 중심(부지 로컬 x, z)
function PlotLayout.cellCenter(cx: number, cz: number): Vector2
	local half, cell = PlotLayout.PLOT_HALF, PlotLayout.CELL
	return Vector2.new(-half + cx * cell + cell / 2, -half + cz * cell + cell / 2)
end

--- 부지 로컬 x, z → 칸. 부지 밖이면 가장자리 칸으로 붙인다
function PlotLayout.cellOf(localX: number, localZ: number): (number, number)
	local half, cell, last = PlotLayout.PLOT_HALF, PlotLayout.CELL, PlotLayout.GRID - 1
	local cx = math.clamp(math.floor((localX + half) / cell), 0, last)
	local cz = math.clamp(math.floor((localZ + half) / cell), 0, last)
	return cx, cz
end

export type DecorRect = { x0: number, x1: number, z0: number, z1: number }

local TREE_CLEAR = 2.5 -- 나무 줄기 둘레(반폭). 잎 아래 한 칸
local POLE_CLEAR = 0.5 -- 팻말·국기봉 기둥 둘레(반폭)

-- (x, z) 를 중심으로 반폭 hx·hz 인 사각형
local function around(x: number, z: number, hx: number, hz: number): DecorRect
	return { x0 = x - hx, x1 = x + hx, z0 = z - hz, z1 = z + hz }
end

--[[
	1층 꾸미기 정적 장애물(PlotShell 고정물만). 부지 로컬 사각형이고 칸과 면적이 조금이라도 겹치면 그 칸을 막는다.
	건물 14개·패드·스폰·스티커 후보·별·문 앞은 DecorGrid 가 FacilityConfig·위 표에서 따로 계산한다.
]]
do
	local frontZ = PlotLayout.ENTRANCE.Z + PlotLayout.ENTRANCE_SIZE.Z / 2 -- 7.5. 앞마당 길이 시작하는 곳
	local half = PlotLayout.PLOT_HALF
	local gateHalf = PlotLayout.GATE_PILLAR / 2
	PlotLayout.DECOR_STATIC = {
		-- 교문·현판·남쪽 생울타리 줄(교문 줄 z 67.5)과 그 바깥(담장 밖 인도). 물건이 담장을 뚫지 않게 막는다
		{ x0 = -half, x1 = half, z0 = PlotLayout.GATE_Z - gateHalf, z1 = half },
		-- 담장 안쪽 길(교문 → 현관 남문)
		{ x0 = -PlotLayout.GATE_W / 2, x1 = PlotLayout.GATE_W / 2, z0 = frontZ, z1 = PlotLayout.GATE_Z },
		-- 팻말·국기봉 기둥
		around(PlotLayout.SIGNPOST.X, PlotLayout.SIGNPOST.Z, 1.5, POLE_CLEAR), -- 팻말 판 폭 3
		around(PlotLayout.FLAGPOLE.X, PlotLayout.FLAGPOLE.Z, POLE_CLEAR, POLE_CLEAR),
		-- 접수대 몸통 4×4 + 앞 배출구
		around(PlotLayout.ADMISSION.X, PlotLayout.ADMISSION.Z, 2, 2.5),
		-- 나무 2그루
		around(PlotLayout.TREES[1].X, PlotLayout.TREES[1].Y, TREE_CLEAR, TREE_CLEAR),
		around(PlotLayout.TREES[2].X, PlotLayout.TREES[2].Y, TREE_CLEAR, TREE_CLEAR),
		-- 현관(계단·착지대 포함)·교실1
		around(
			PlotLayout.ENTRANCE.X,
			PlotLayout.ENTRANCE.Z,
			PlotLayout.ENTRANCE_SIZE.X / 2,
			PlotLayout.ENTRANCE_SIZE.Z / 2
		),
		around(PlotLayout.CLASS1.X, PlotLayout.CLASS1.Z, PlotLayout.CLASS1_SIZE.X / 2, PlotLayout.CLASS1_SIZE.Z / 2),
	} :: { DecorRect }
end

local SAME_SPOT = 0.01

type Candidate = { spot: Vector2, floorY: number }
local candidates: { Candidate } = {}
for _, zone in PlotLayout.STICKER_ZONES do
	for _, spot in zone.spots do
		table.insert(candidates, { spot = spot, floorY = zone.floorY })
	end
end

local function farFromAll(spot: Vector2, others: { Vector2 }, gap: number): boolean
	for _, other in others do
		if (spot - other).Magnitude < gap then
			return false
		end
	end
	return true
end

--[[
	다음 스티커 자리. 순수 함수(rng 만 소비한다).
	모든 구역 후보 중 무작위로 고르되 ① 직전 자리 제외 ② occupied(다른 활성 스티커)와 MIN_GAP 이상
	③ ownerPos 가 있으면 주인과 AVOID_OWNER 이상. 만족하는 후보가 없으면 ③ → ② 순으로 푼다.
	①은 끝까지 지킨다. 두 번째 값은 그 후보 구역의 floorY.
]]
function PlotLayout.pickStickerSpot(
	rng: Random,
	prev: Vector2?,
	ownerPos: Vector2?,
	occupied: { Vector2 }
): (Vector2, number)
	local notPrev: { Candidate } = {}
	for _, c in candidates do
		if prev == nil or (c.spot - prev).Magnitude > SAME_SPOT then
			table.insert(notPrev, c)
		end
	end

	local spaced: { Candidate } = {}
	for _, c in notPrev do
		if farFromAll(c.spot, occupied, PlotLayout.MIN_GAP) then
			table.insert(spaced, c)
		end
	end

	local best: { Candidate } = {}
	if ownerPos then
		for _, c in spaced do
			if (c.spot - ownerPos).Magnitude >= PlotLayout.AVOID_OWNER then
				table.insert(best, c)
			end
		end
	else
		best = spaced
	end

	local pool = if #best > 0 then best elseif #spaced > 0 then spaced else notPrev
	local pick = pool[rng:NextInteger(1, #pool)]
	return pick.spot, pick.floorY
end

-- ── 로드 assert(§3.6 #2) ─────────────────────────────────────────
type Rect = { x0: number, x1: number, z0: number, z1: number }

local function rectAt(center: Vector2, size: Vector2): Rect
	return {
		x0 = center.X - size.X / 2,
		x1 = center.X + size.X / 2,
		z0 = center.Y - size.Y / 2,
		z1 = center.Y + size.Y / 2,
	}
end

-- 면이 닿기만 하는 것은 겹침이 아니다
local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end

local function inside(inner: Rect, outer: Rect): boolean
	return inner.x0 >= outer.x0 and inner.x1 <= outer.x1 and inner.z0 >= outer.z0 and inner.z1 <= outer.z1
end

local function onGrid(v: number): boolean
	return v % PlotLayout.CELL == 0
end

do
	local aud = FacilityConfig.BY_ID.auditorium
	assert(aud, "PlotLayout: FacilityConfig 에 auditorium 행이 없다")
	local audRect = rectAt(Vector2.new(aud.center.X, aud.center.Z), Vector2.new(aud.size.X, aud.size.Z))
	local foot = PlotLayout.TOWER_FOOTPRINT :: Rect
	local cell = PlotLayout.CELL
	local elevator = rectAt(PlotLayout.ELEVATOR, Vector2.new(cell, cell))
	local stairwell: Rect = {
		x0 = PlotLayout.STAIR_X0,
		x1 = PlotLayout.STAIR_X1,
		z0 = PlotLayout.STAIRWELL_Z0,
		z1 = PlotLayout.STAIR_Z_BOTTOM,
	}
	local landing = rectAt(
		Vector2.new(PlotLayout.LANDING.X, PlotLayout.LANDING.Z),
		Vector2.new(PlotLayout.LANDING_SIZE.X, PlotLayout.LANDING_SIZE.Z)
	)
	local cols, rows = PlotLayout.AUDITORIUM_SEAT_COLS, PlotLayout.AUDITORIUM_SEAT_ROWS
	local benchW, benchD = PlotLayout.AUDITORIUM_BENCH_W, PlotLayout.AUDITORIUM_BENCH_D
	local benchCX = (cols[1] + cols[#cols]) / 2
	local seats: Rect = {
		x0 = math.min(benchCX - benchW / 2, cols[1]),
		x1 = math.max(benchCX + benchW / 2, cols[#cols]),
		z0 = rows[1] - benchD / 2,
		z1 = rows[#rows] + benchD / 2,
	}
	local towerPad = rectAt(Vector2.new(PlotLayout.TOWER_PAD.X, PlotLayout.TOWER_PAD.Z), PlotLayout.TOWER_PAD_SIZE)
	local audPad = rectAt(Vector2.new(aud.pad.X, aud.pad.Z), PlotLayout.TOWER_PAD_SIZE)

	-- (a) 엘리베이터 칸이 강당 안쪽·탑 발자국 안
	assert(inside(elevator, audRect), "PlotLayout(a): 엘리베이터 칸이 강당 밖이다")
	assert(inside(elevator, foot), "PlotLayout(a): 엘리베이터 칸이 TOWER_FOOTPRINT 밖이다")
	-- (b) 계단 구멍·착지대·좌석과 겹치지 않음
	assert(not overlaps(elevator, stairwell), "PlotLayout(b): 엘리베이터 칸이 계단 구멍과 겹친다")
	assert(not overlaps(elevator, landing), "PlotLayout(b): 엘리베이터 칸이 착지대와 겹친다")
	assert(not overlaps(elevator, seats), "PlotLayout(b): 엘리베이터 칸이 강당 좌석과 겹친다")
	-- (c) 탑 발자국이 CELL 격자에 맞음
	assert(
		onGrid(foot.x0) and onGrid(foot.x1) and onGrid(foot.z0) and onGrid(foot.z1),
		"PlotLayout(c): TOWER_FOOTPRINT 가 CELL 격자에 안 맞는다"
	)
	-- (d) 층 구매 패드가 강당 안, 강당 패드·좌석·착지대·2층 칸과 겹치지 않음
	assert(inside(towerPad, audRect), "PlotLayout(d): TOWER_PAD 가 강당 밖이다")
	assert(
		-- Vector3 는 float32 라 18.2 가 정확히 같지 않다
		math.abs(PlotLayout.TOWER_PAD.Y - (aud.center.Y + PlotLayout.AUDITORIUM_FLOOR_T)) < 1e-4,
		"PlotLayout(d): TOWER_PAD 높이가 강당 바닥 윗면이 아니다"
	)
	assert(not overlaps(towerPad, audPad), "PlotLayout(d): TOWER_PAD 가 강당 패드와 겹친다")
	assert(not overlaps(towerPad, seats), "PlotLayout(d): TOWER_PAD 가 강당 좌석과 겹친다")
	assert(not overlaps(towerPad, landing), "PlotLayout(d): TOWER_PAD 가 착지대와 겹친다")
	assert(not overlaps(towerPad, elevator), "PlotLayout(d): TOWER_PAD 가 엘리베이터 칸과 겹친다")
end

return PlotLayout
