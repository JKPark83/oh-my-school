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
	parts: { number }, -- 부품 가격(졸업 0회 기준, 구매 순서). partPriceOf 로 배율 적용. 길이 3 또는 4
	income: number, -- 초당
	student: Types.StudentId?, -- 지으면 전학 오는 학생
	center: Vector3, -- 부지 로컬
	size: Vector3, -- 방이면 벽 바깥 치수, 가구면 대략 바운딩박스
	pad: Vector3, -- 구매 패드 중심(바닥)
	door: string?, -- "S" | "N" | "W" (방 기준 문 방향). nil = 문 없음
	seats: number, -- Seats/S01… 개수
	spawns: number, -- 이 시설이 여는 칭찬스티커 스폰 수
	floor: number, -- 1 | 2
}

FacilityConfig.PRICE_SCALE = 1.35 -- 졸업 1회마다 가격 ×1.35

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
		door = nil,
		seats = 6,
		spawns = 3,
		floor = 1,
	},
	{
		id = "board",
		name = "칠판",
		parts = { 14, 14, 15 },
		income = 3,
		student = "s02",
		center = V(-60, 0, -61.5),
		size = V(12, 4, 0.6),
		pad = V(-70, 0, -57.5),
		door = nil,
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "locker",
		name = "사물함",
		parts = { 35, 37, 39 },
		income = 6,
		student = "s03",
		center = V(-46, 0, -47.5),
		size = V(1.6, 6, 12),
		pad = V(-50, 0, -57.5),
		door = nil,
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "hall",
		name = "복도",
		parts = { 88, 92, 97 },
		income = 12,
		student = "s04",
		center = V(0, 0, -25),
		size = V(150, 18, 15),
		pad = V(0, 0, -13.75),
		door = nil,
		seats = 0,
		spawns = 2,
		floor = 1,
	},
	{
		id = "class2",
		name = "교실2",
		parts = { 250, 260, 270 },
		income = 25,
		student = "s05",
		center = V(-20, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(-20, 0, -28.75),
		door = "S",
		seats = 6,
		spawns = 0,
		floor = 1,
	},
	{
		id = "cafeteria",
		name = "급식실",
		parts = { 610, 640, 680 },
		income = 50,
		student = "s06",
		center = V(20, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(20, 0, -28.75),
		door = "S",
		seats = 4,
		spawns = 0,
		floor = 1,
	},
	{
		id = "library",
		name = "도서관",
		parts = { 1500, 1500, 1600, 1700 },
		income = 90,
		student = "s07",
		center = V(60, 0, -47.5),
		size = V(30, 18, 30),
		pad = V(60, 0, -28.75),
		door = "S",
		seats = 3,
		spawns = 0,
		floor = 1,
	},
	{
		id = "nurse",
		name = "보건실",
		parts = { 3500, 3600, 3800, 4000 },
		income = 150,
		student = "s08",
		center = V(-60, 0, -5),
		size = V(30, 18, 25),
		pad = V(-60, 0, -21.25),
		door = "N",
		seats = 1,
		spawns = 0,
		floor = 1,
	},
	{
		id = "science",
		name = "과학실",
		parts = { 7600, 8000, 8400, 8800 },
		income = 260,
		student = "s09",
		center = V(-30, 0, -5),
		size = V(30, 18, 25),
		pad = V(-30, 0, -21.25),
		door = "N",
		seats = 2,
		spawns = 0,
		floor = 1,
	},
	{
		id = "music",
		name = "음악실",
		parts = { 16000, 17000, 18000, 19000 },
		income = 420,
		student = "s10",
		center = V(30, 0, -5),
		size = V(30, 18, 25),
		pad = V(30, 0, -21.25),
		door = "N",
		seats = 2,
		spawns = 0,
		floor = 1,
	},
	{
		id = "gym",
		name = "체육관",
		parts = { 34000, 36000, 38000, 40000 },
		income = 700,
		student = "s11",
		center = V(60, 0, 37.5),
		size = V(30, 20, 45),
		pad = V(41.25, 0, 37.5),
		door = "W",
		seats = 0,
		spawns = 0,
		floor = 1,
	},
	{
		id = "field",
		name = "운동장",
		parts = { 71000, 74000, 78000, 82000 },
		income = 1100,
		student = "s12",
		center = V(-45, 0, 37.5),
		size = V(60, 1, 45),
		pad = V(-11.25, 0, 37.5),
		door = nil,
		seats = 0,
		spawns = 3,
		floor = 1,
	},
	{
		id = "principal",
		name = "교장실",
		parts = { 160000, 170000, 180000, 190000 },
		income = 1800,
		student = "s13",
		center = V(60, 0, -5),
		size = V(30, 18, 25),
		pad = V(60, 0, -21.25),
		door = "N",
		seats = 1,
		spawns = 0,
		floor = 1,
	},
	{
		id = "auditorium",
		name = "강당",
		parts = { 320000, 340000, 350000, 370000 },
		income = 3000,
		student = nil,
		center = V(0, 18, -17.5),
		size = V(50, 18, 35),
		pad = V(0, 18, -13.75),
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

--- 졸업 횟수를 반영한 부품 k 가격
function FacilityConfig.partPriceOf(id: Types.FacilityId, k: number, graduations: number): number
	local row = BY_ID[id]
	assert(row, `모르는 시설: {id}`)
	local base = row.parts[k]
	assert(base, `{id} 에 부품 {k} 이 없다`)
	return math.floor(base * FacilityConfig.PRICE_SCALE ^ graduations + 0.5)
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
