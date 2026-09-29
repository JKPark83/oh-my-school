--!strict
--[[
	꾸미기 격자 판정. 순수 함수(서버 DecorService 와 클라 배치 미리보기가 같은 답을 낸다). 개선계획 §3.5 #4.
	칸 (cx, cz) 는 0..GRID-1. 아이템 발자국은 (cx, cz) 칸에서 +x·+z 쪽으로 자란다.
	  rot 0·2 → w×d, rot 1·3 → d×w.

	1층 정적 마스크(로드 때 한 번 만든다). 칸과 면적이 조금이라도 겹치면 막는다.
	  - 1층 시설 방·가구(운동장·복도 제외) 사각형
	  - 복도·강당: 복도 안쪽에 중심이 있는 칸만 둔다(벽에 걸친 칸은 막는다)
	  - 문 앞: 문 폭 DOOR_W × 바깥 한 칸
	  - 구매 패드 4×4 와 그 둘레 한 칸, 스폰 8×8
	  - 스티커 후보·홈 자리·별 자리 판(3.4×3.4)
	  - PlotLayout.DECOR_STATIC(교문 줄·길·팻말·국기봉·접수대·나무·현관·교실1) + 교실1 남문 앞
	3층부터(탑 층): TOWER_FOOTPRINT 안만. 엘리베이터 칸과 그 앞(+z) 칸, 기본 가구 칸(발자국 x0·z0 모서리)은 막는다.
]]

local DecorConfig = require(script.Parent.Config.DecorConfig)
local FacilityConfig = require(script.Parent.Config.FacilityConfig)
local PlotLayout = require(script.Parent.PlotLayout)

local DecorGrid = {}

type Placement = { item: string, cx: number, cz: number, rot: number, f: number? }
type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Reason = "ok" | "item" | "cell" | "floor" | "blocked" | "overlap" | "limit"

local GRID = PlotLayout.GRID
local CELL = PlotLayout.CELL
local HALF = PlotLayout.PLOT_HALF
local PAD_SIZE = 4 -- PlotShell PAD_SIZE
local SPAWN_SIZE = 8
local STICKER_SIZE = 3.4 -- 스티커 판 + 여유
local DOOR_W = 8 -- 문 폭
local EDGE = 0.01 -- 벽 면에서 안쪽으로 살짝 들여 문 앞 사각형이 벽 칸까지 닿게 한다
local SEARCH = 6 -- nearestFree 가 찾는 맨해튼 거리

-- ── 1층 정적 마스크 ──────────────────────────────────────────────
local staticBlocked: { { boolean } } = {}
for cx = 0, GRID - 1 do
	local column = {}
	for cz = 0, GRID - 1 do
		column[cz] = false
	end
	staticBlocked[cx] = column
end

local function cellLow(c: number): number
	return -HALF + c * CELL
end

local function forCells(rect: Rect, fn: (cx: number, cz: number) -> ())
	for cx = 0, GRID - 1 do
		local x0 = cellLow(cx)
		if x0 < rect.x1 and rect.x0 < x0 + CELL then
			for cz = 0, GRID - 1 do
				local z0 = cellLow(cz)
				if z0 < rect.z1 and rect.z0 < z0 + CELL then
					fn(cx, cz)
				end
			end
		end
	end
end

local function blockRect(rect: Rect)
	forCells(rect, function(cx, cz)
		staticBlocked[cx][cz] = true
	end)
end

local function around(x: number, z: number, hx: number, hz: number): Rect
	return { x0 = x - hx, x1 = x + hx, z0 = z - hz, z1 = z + hz }
end

local function strictlyInside(x: number, z: number, r: Rect): boolean
	return x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1
end

-- 문 앞 사각형. wall 은 방 사각형, dir 은 문 방향
local function doorFront(room: Rect, cx: number, cz: number, dir: string): Rect?
	if dir == "S" then
		return { x0 = cx - DOOR_W / 2, x1 = cx + DOOR_W / 2, z0 = room.z1 - EDGE, z1 = room.z1 + CELL }
	elseif dir == "N" then
		return { x0 = cx - DOOR_W / 2, x1 = cx + DOOR_W / 2, z0 = room.z0 - CELL, z1 = room.z0 + EDGE }
	elseif dir == "W" then
		return { x0 = room.x0 - CELL, x1 = room.x0 + EDGE, z0 = cz - DOOR_W / 2, z1 = cz + DOOR_W / 2 }
	end
	return nil
end

do
	local hallRow = FacilityConfig.BY_ID.hall
	assert(hallRow, "DecorGrid: FacilityConfig 에 hall 이 없다")
	local hall = around(hallRow.center.X, hallRow.center.Z, hallRow.size.X / 2, hallRow.size.Z / 2)

	for _, fac in FacilityConfig.LIST do
		local room = around(fac.center.X, fac.center.Z, fac.size.X / 2, fac.size.Z / 2)
		if fac.id == "hall" or fac.floor ~= 1 then
			-- 복도(1층)와 그 위 강당(2층): 복도 안쪽 칸만 둔다
			forCells(room, function(cx, cz)
				local center = PlotLayout.cellCenter(cx, cz)
				if not strictlyInside(center.X, center.Y, hall) then
					staticBlocked[cx][cz] = true
				end
			end)
		elseif fac.id ~= "field" then
			blockRect(room)
		end
		if fac.floor == 1 then
			local door = fac.door
			if door then
				local front = doorFront(room, fac.center.X, fac.center.Z, door)
				if front then
					blockRect(front)
				end
			end
			-- 패드와 둘레 한 칸
			blockRect(around(fac.pad.X, fac.pad.Z, PAD_SIZE / 2 + CELL, PAD_SIZE / 2 + CELL))
		end
	end

	blockRect(around(PlotLayout.SPAWN.X, PlotLayout.SPAWN.Z, SPAWN_SIZE / 2, SPAWN_SIZE / 2))

	local spots: { Vector2 } = {}
	for _, zone in PlotLayout.STICKER_ZONES do
		for _, spot in zone.spots do
			table.insert(spots, spot)
		end
	end
	for _, spot in PlotLayout.HOME_SPOTS do
		table.insert(spots, spot)
	end
	for _, spot in PlotLayout.STAR_SPOTS do
		table.insert(spots, spot)
	end
	for _, spot in spots do
		blockRect(around(spot.X, spot.Y, STICKER_SIZE / 2, STICKER_SIZE / 2))
	end

	for _, rect in PlotLayout.DECOR_STATIC do
		blockRect(rect)
	end
	-- 교실1 남문 앞(PlotShell 이 짓는 방)
	local class1 =
		around(PlotLayout.CLASS1.X, PlotLayout.CLASS1.Z, PlotLayout.CLASS1_SIZE.X / 2, PlotLayout.CLASS1_SIZE.Z / 2)
	blockRect(doorFront(class1, PlotLayout.CLASS1.X, PlotLayout.CLASS1.Z, "S") :: Rect)
end

-- ── 탑 층 마스크 ─────────────────────────────────────────────────
local foot = PlotLayout.TOWER_FOOTPRINT
local towerX0, towerZ0 = PlotLayout.cellOf(foot.x0 + CELL / 2, foot.z0 + CELL / 2)
local towerX1, towerZ1 = PlotLayout.cellOf(foot.x1 - CELL / 2, foot.z1 - CELL / 2)
local elevatorX, elevatorZ = PlotLayout.cellOf(PlotLayout.ELEVATOR.X, PlotLayout.ELEVATOR.Y)

--- 1층 정적 장애물 칸인가. 격자 밖이면 true
function DecorGrid.isStaticBlocked(cx: number, cz: number): boolean
	local column = staticBlocked[cx]
	if not column then
		return true
	end
	local v = column[cz]
	return v == nil or v
end

--- f 층(1 또는 3 이상)에서 막힌 칸인가. 2층(강당)은 전부 막힌다
function DecorGrid.isFloorBlocked(f: number, cx: number, cz: number): boolean
	if f == 1 then
		return DecorGrid.isStaticBlocked(cx, cz)
	end
	if f < 3 then
		return true
	end
	if cx < towerX0 or cx > towerX1 or cz < towerZ0 or cz > towerZ1 then
		return true
	end
	if cx == elevatorX and (cz == elevatorZ or cz == elevatorZ + 1) then
		return true
	end
	-- 층 기본 가구(발자국 x0·z0 모서리 칸)
	return cx == towerX0 and cz == towerZ0
end

--- 발자국 크기(x 칸, z 칸). 아이템이 없으면 nil
function DecorGrid.size(itemId: string, rot: number): (number, number)
	local item = DecorConfig.byId(itemId)
	if not item then
		return 1, 1
	end
	if rot == 1 or rot == 3 then
		return item.d, item.w
	end
	return item.w, item.d
end

--- 발자국 칸 목록. (cx, cz) 에서 +x·+z 로 자란다
function DecorGrid.footprint(itemId: string, cx: number, cz: number, rot: number): { Vector2 }
	local sx, sz = DecorGrid.size(itemId, rot)
	local cells = {}
	for dx = 0, sx - 1 do
		for dz = 0, sz - 1 do
			table.insert(cells, Vector2.new(cx + dx, cz + dz))
		end
	end
	return cells
end

--- 발자국 가운데(부지 로컬 x, z). 클라가 DecorBuilder 에 넘길 CFrame 위치
function DecorGrid.footprintCenter(itemId: string, cx: number, cz: number, rot: number): Vector2
	local sx, sz = DecorGrid.size(itemId, rot)
	return Vector2.new(cellLow(cx) + sx * CELL / 2, cellLow(cz) + sz * CELL / 2)
end

local function isInt(v: number): boolean
	return v == math.floor(v)
end

local function floorOf(p: Placement): number
	return p.f or 1
end

-- 두 발자국 사각형이 겹치나(칸 단위)
local function hits(p: Placement, cx: number, cz: number, sx: number, sz: number): boolean
	local px, pz = DecorGrid.size(p.item, p.rot)
	return p.cx < cx + sx and cx < p.cx + px and p.cz < cz + sz and cz < p.cz + pz
end

--- 겹치는 배치 순번 목록(같은 층, ignoreSlot 제외). 인자 순서가 canPlace 와 다르다
function DecorGrid.blockers(
	placed: { Placement },
	f: number,
	cx: number,
	cz: number,
	rot: number,
	itemId: string,
	ignoreSlot: number?
): { number }
	local sx, sz = DecorGrid.size(itemId, rot)
	local slots = {}
	for slot, p in placed do
		if slot ~= ignoreSlot and floorOf(p) == f and hits(p, cx, cz, sx, sz) then
			table.insert(slots, slot)
		end
	end
	return slots
end

--[[
	놓을 수 있나. 검사 순서: item → cell → floor → blocked → overlap → limit.
	ignoreSlot 은 옮기는 중인 배치 순번(자기 자신과 겹침 무시, 개수 상한 무시).
]]
function DecorGrid.canPlace(
	placed: { Placement },
	towerFloors: number,
	itemId: string,
	cx: number,
	cz: number,
	rot: number,
	f: number,
	ignoreSlot: number?
): (boolean, Reason)
	if not DecorConfig.byId(itemId) then
		return false, "item"
	end
	if not (isInt(rot) and rot >= 0 and rot <= 3) then
		return false, "cell"
	end
	local sx, sz = DecorGrid.size(itemId, rot)
	if not (isInt(cx) and isInt(cz) and cx >= 0 and cz >= 0 and cx + sx <= GRID and cz + sz <= GRID) then
		return false, "cell"
	end
	if not (f == 1 or (isInt(f) and f >= 3 and f <= 2 + towerFloors)) then
		return false, "floor"
	end
	for dx = 0, sx - 1 do
		for dz = 0, sz - 1 do
			if DecorGrid.isFloorBlocked(f, cx + dx, cz + dz) then
				return false, "blocked"
			end
		end
	end
	if #DecorGrid.blockers(placed, f, cx, cz, rot, itemId, ignoreSlot) > 0 then
		return false, "overlap"
	end
	if ignoreSlot == nil and #placed >= DecorConfig.MAX_PLACED then
		return false, "limit"
	end
	return true, "ok"
end

--- (cx, cz) 에서 맨해튼 거리 SEARCH 안의 가장 가까운 빈 자리. 없으면 nil
function DecorGrid.nearestFree(
	placed: { Placement },
	towerFloors: number,
	itemId: string,
	cx: number,
	cz: number,
	rot: number,
	f: number,
	ignoreSlot: number?
): (number?, number?)
	for r = 0, SEARCH do
		for dx = -r, r do
			local rest = r - math.abs(dx)
			local dzs: { number } = if rest == 0 then { 0 } else { -rest, rest }
			for _, dz in dzs do
				local ok, reason = DecorGrid.canPlace(placed, towerFloors, itemId, cx + dx, cz + dz, rot, f, ignoreSlot)
				if ok then
					return cx + dx, cz + dz
				elseif reason == "item" or reason == "floor" or reason == "limit" then
					return nil, nil -- 자리를 옮겨도 안 풀린다
				end
			end
		end
	end
	return nil, nil
end

return DecorGrid
