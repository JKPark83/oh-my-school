--!strict
--[[
	시설 14개. 기획서 §3.1 표를 그대로 옮겼다.
	시설마다 부품 3~4개(합계 50)를 차례로 사서 짓는다. 수입은 마지막 부품을 넣어 완공될 때만 붙는다.
	부품 가격은 docs/sim/sim-parts.py 의 표(sim-parts-output.md 「Config 옮김용 가격 배열」)와 같아야 한다.
	좌표는 전부 부지 로컬(부지 CFrame 기준, +Z 가 교문 쪽). y 는 바닥 높이.
	Geometry/<id>.luau 가 center·size·pad 를 읽어 짓는다. 코드에 좌표를 직접 적지 않는다.
]]

local Types = require(script.Parent.Parent.Types)

local FacilityConfig = {}

export type Facility = {
	id: Types.FacilityId,
	name: string,
	parts: { number }, -- 부품 가격(구매 순서). 길이 3 또는 4
	income: number, -- 초당
	student: Types.StudentId?, -- 지으면 전학 오는 학생
	center: Vector3, -- 부지 로컬
	size: Vector3, -- 방이면 벽 바깥 치수, 가구면 대략 바운딩박스
	pad: Vector3, -- 구매 패드 중심(바닥). 부품 1 자리(시설 입구)
	partPads: { Vector3 }, -- 부품 2..n 패드 자리(바닥). 길이 = 부품 수 - 1. 산 부품·다른 패드·스티커 자리와 겹치지 않는 빈 바닥
	door: string?, -- "S" | "N" | "W" (방 기준 문 방향). nil = 문 없음
	seats: number, -- Seats/S01… 개수
	spawns: number, -- 이 시설이 여는 칭찬스티커 스폰 수
	floor: number, -- 1 | 2
}

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local LIST: { Facility } = {
	{
		id = "desk",
		name = "책상 세트",
		parts = { 10, 10, 10 },
		income = 1,
		student = "s01",
		center = V(-60, 0, -50),
		size = V(18, 3, 10),
		pad = V(-60, 0, -37.5),
		partPads = { V(-66, 0, -49), V(-54, 0, -45) },
		door = nil,
		seats = 6,
		spawns = 3,
		floor = 1,
	},
	{
		id = "board",
		name = "칠판",
		parts = { 14, 15, 16 },
		income = 3,
		student = "s02",
		center = V(-60, 0, -61.5),
		size = V(12, 4, 0.6),
		pad = V(-70, 0, -57.5),
		partPads = { V(-66, 0, -51.5), V(-54, 0, -51.5) },
		door = nil,
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "locker",
		name = "사물함",
		parts = { 38, 41, 43 },
		income = 6,
		student = "s03",
		center = V(-46, 0, -47.5),
		size = V(1.6, 6, 12),
		pad = V(-50, 0, -57.5),
		partPads = { V(-51, 0, -47.5), V(-51, 0, -40.5) },
		door = nil,
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "hall",
		name = "복도",
		parts = { 100, 110, 120 },
		income = 12,
		student = "s04",
		center = V(0, 0, -25),
		size = V(150, 18, 15),
		pad = V(0, 0, -13.75),
		partPads = { V(0, 0, -23), V(4.5, 0, -28.5) },
		door = nil,
		seats = 0,
		spawns = 2,
		floor = 1,
	},
	{
		id = "class2",
		name = "교실2",
		parts = { 310, 330, 350 },
		income = 25,
		student = "s05",
		center = V(-20, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(-20, 0, -28.75),
		partPads = { V(-20, 0, -38), V(-26, 0, -46.5) },
		door = "S",
		seats = 6,
		spawns = 0,
		floor = 1,
	},
	{
		id = "cafeteria",
		name = "급식실",
		parts = { 810, 860, 910 },
		income = 50,
		student = "s06",
		center = V(20, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(20, 0, -28.75),
		partPads = { V(20, 0, -40.5), V(20, 0, -48.5) },
		door = "S",
		seats = 4,
		spawns = 0,
		floor = 1,
	},
	{
		id = "library",
		name = "도서관",
		parts = { 2100, 2200, 2300, 2400 },
		income = 90,
		student = "s07",
		center = V(60, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(60, 0, -28.75),
		partPads = { V(60, 0, -40), V(63.5, 0, -57), V(51, 0, -44) },
		door = "S",
		seats = 3,
		spawns = 0,
		floor = 1,
	},
	{
		id = "nurse",
		name = "보건실",
		parts = { 5100, 5400, 5700, 6000 },
		income = 150,
		student = "s08",
		center = V(-60, 0, -5),
		size = V(30, 18, 25),
		pad = V(-60, 0, -21.25),
		partPads = { V(-60, 0, -9), V(-67, 0, -10), V(-55.5, 0, -3.5) },
		door = "N",
		seats = 1,
		spawns = 0,
		floor = 1,
	},
	{
		id = "science",
		name = "과학실",
		parts = { 12000, 13000, 13000, 14000 },
		income = 260,
		student = "s09",
		center = V(-30, 0, -5),
		size = V(30, 18, 25),
		pad = V(-30, 0, -21.25),
		partPads = { V(-30, 0, -11.5), V(-30, 0, -2.5), V(-35.5, 0, 2) },
		door = "N",
		seats = 2,
		spawns = 0,
		floor = 1,
	},
	{
		id = "music",
		name = "음악실",
		parts = { 27000, 29000, 30000, 32000 },
		income = 420,
		student = "s10",
		center = V(30, 0, -5),
		size = V(30, 18, 25),
		pad = V(30, 0, -21.25),
		partPads = { V(30, 0, -11), V(25, 0, -1), V(33, 0, -2) },
		door = "N",
		seats = 2,
		spawns = 0,
		floor = 1,
	},
	{
		id = "gym",
		name = "체육관",
		parts = { 59000, 63000, 66000, 70000 },
		income = 700,
		student = "s11",
		center = V(60, 0, 37.5),
		size = V(30, 20, 45),
		pad = V(41.25, 0, 37.5),
		partPads = { V(56.5, 0, 37.5), V(62.5, 0, 33.5), V(63.5, 0, 41.5) },
		door = "W",
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "field",
		name = "운동장",
		parts = { 140000, 140000, 150000, 160000 },
		income = 1100,
		student = "s12",
		center = V(-45, 0, 37.5),
		size = V(60, 1, 45),
		pad = V(-11.25, 0, 37.5),
		partPads = { V(-45, 0, 37.5), V(-71, 0, 37.5), V(-26, 0, 37.5) },
		door = nil,
		seats = 0,
		spawns = 3,
		floor = 1,
	},
	{
		id = "principal",
		name = "교장실",
		parts = { 350000, 370000, 390000, 410000 },
		income = 1800,
		student = "s13",
		center = V(60, 0, -5),
		size = V(30, 18, 25),
		pad = V(60, 0, -21.25),
		partPads = { V(55.5, 0, -11), V(57.5, 0, -1), V(64.5, 0, -11) },
		door = "N",
		seats = 1,
		spawns = 0,
		floor = 1,
	},
	{
		id = "auditorium",
		name = "강당",
		parts = { 760000, 810000, 850000, 900000 },
		income = 3000,
		student = nil,
		center = V(0, 18, -17.5),
		size = V(50, 18, 35),
		pad = V(0, 18, -13.75),
		partPads = { V(0, 18, -6.5), V(-3.5, 18, -20.5), V(3, 18, -23.5) },
		door = "S",
		seats = 25,
		spawns = 0,
		floor = 2,
	},
}

local BY_ID: { [Types.FacilityId]: Facility } = {}
local ORDER: { Types.FacilityId } = {}
local INDEX: { [Types.FacilityId]: number } = {}
for i, row in LIST do
	BY_ID[row.id] = row
	ORDER[i] = row.id
	INDEX[row.id] = i
end

FacilityConfig.LIST = LIST
FacilityConfig.BY_ID = BY_ID
FacilityConfig.ORDER = ORDER -- 구매 순서. 선형 트리라 i 번째는 i-1 번째가 있어야 산다
FacilityConfig.COUNT = #LIST

-- 다음에 살 부품. index 는 1..count
export type NextPart = {
	facility: Facility,
	index: number,
	count: number,
}

local partTotal = 0
for _, row in LIST do
	assert(#row.parts == 3 or #row.parts == 4, `{row.id} 부품 수는 3 또는 4 여야 한다`)
	partTotal += #row.parts
end
assert(partTotal == 50, `부품 합계가 50 이 아니다: {partTotal}`)
FacilityConfig.PART_COUNT = partTotal -- 14 시설 부품 합(50)

-- 층별 바닥 높이(부지 로컬 y). [2] 는 PlotLayout.WALL_H 와 같아야 한다(PlotLayout 이 확인한다. 순환 require 때문에 여기서 못 읽는다)
FacilityConfig.STORY_Y = { 0, 18 }

-- #14: 각 행의 floor 가 pad.Y·center.Y 의 높이 띠와 맞는지(개선계획 §3.6 #14). 층 사이 절반을 넘으면 다른 층이다
do
	local band = FacilityConfig.STORY_Y[2] / 2
	for _, row in LIST do
		local base = FacilityConfig.STORY_Y[row.floor]
		assert(base, `{row.id}: floor 는 1 또는 2 여야 한다({row.floor})`)
		assert(math.abs(row.pad.Y - base) < band, `{row.id}: pad.Y {row.pad.Y} 가 {row.floor}층 높이 띠 밖이다`)
		assert(
			math.abs(row.center.Y - base) < band,
			`{row.id}: center.Y {row.center.Y} 가 {row.floor}층 높이 띠 밖이다`
		)
		assert(#row.partPads == #row.parts - 1, `{row.id}: partPads 는 부품 수 - 1 개여야 한다`)
		for k, spot in row.partPads do
			assert(math.abs(spot.Y - row.pad.Y) < 1e-3, `{row.id}: partPads[{k}] 높이가 pad 와 다르다`)
		end
	end
end

--- 구매 순서 번호(1~14)
function FacilityConfig.indexOf(id: Types.FacilityId): number
	return INDEX[id] or 0
end

--- 지은 시설 수
function FacilityConfig.count(built: { [Types.FacilityId]: boolean }): number
	local n = 0
	for _, id in ORDER do
		if built[id] then
			n += 1
		end
	end
	return n
end

--- 다음에 살 시설. 다 지었으면 nil
function FacilityConfig.nextOf(built: { [Types.FacilityId]: boolean }): Facility?
	for _, id in ORDER do
		if not built[id] then
			return BY_ID[id]
		end
	end
	return nil
end

--- 시설의 부품 수(3 또는 4)
function FacilityConfig.partCount(id: Types.FacilityId): number
	local row = BY_ID[id]
	assert(row, `모르는 시설: {id}`)
	return #row.parts
end

--- 부품 k 를 사는 패드 자리(부지 로컬 바닥). 1 은 입구 pad, 2 부터 partPads.
--- 한 번 밟아 부품이 서면 패드가 다음 자리로 옮겨 간다(같은 곳을 계속 밟지 않게)
function FacilityConfig.padOf(id: Types.FacilityId, k: number): Vector3
	local row = BY_ID[id]
	assert(row, `모르는 시설: {id}`)
	return if k <= 1 then row.pad else row.partPads[k - 1] or row.pad
end

--- 부품 k 가격
function FacilityConfig.partPriceOf(id: Types.FacilityId, k: number): number
	local row = BY_ID[id]
	assert(row, `모르는 시설: {id}`)
	local price = row.parts[k]
	assert(price, `{id} 에 부품 {k} 이 없다`)
	return price
end

--- 다음에 살 부품. index = buildParts + 1, count = 그 시설 부품 수. 다 지었으면 nil(호출처가 W6 「다음 층」 분기를 둔다)
function FacilityConfig.nextPartOf(built: { [Types.FacilityId]: boolean }, buildParts: number): NextPart?
	local row = FacilityConfig.nextOf(built)
	if not row then
		return nil
	end
	return { facility = row, index = buildParts + 1, count = #row.parts }
end

--- 지금까지 산 부품 수(0..PART_COUNT) = 완공 시설 부품 합 + 다음 시설의 산 부품 수
function FacilityConfig.partsBuilt(built: { [Types.FacilityId]: boolean }, buildParts: number): number
	local n = 0
	for _, row in LIST do
		if built[row.id] then
			n += #row.parts
		end
	end
	return n + buildParts
end

--- 지을 수 있는 순서인가(바로 앞 시설까지 전부 있어야 한다)
function FacilityConfig.isNext(id: Types.FacilityId, built: { [Types.FacilityId]: boolean }): boolean
	local nextRow = FacilityConfig.nextOf(built)
	return nextRow ~= nil and nextRow.id == id
end

--- "desk,board" CSV. 구매 순서대로
function FacilityConfig.toCsv(built: { [Types.FacilityId]: boolean }): string
	local parts = {}
	for _, id in ORDER do
		if built[id] then
			table.insert(parts, id)
		end
	end
	return table.concat(parts, ",")
end

--- CSV → { [id] = true }
function FacilityConfig.fromCsv(csv: string): { [Types.FacilityId]: boolean }
	local built = {}
	for id in string.gmatch(csv, "[^,]+") do
		if BY_ID[id] then
			built[id] = true
		end
	end
	return built
end

return FacilityConfig
