--!strict
--[[
	시설 14개. 기획서 §3.1 표를 그대로 옮겼다.
	좌표는 전부 부지 로컬(부지 CFrame 기준, +Z 가 교문 쪽). y 는 바닥 높이.
	Geometry/<id>.luau 가 center·size·pad 를 읽어 짓는다. 코드에 좌표를 직접 적지 않는다.
]]

local Types = require(script.Parent.Parent.Types)

local FacilityConfig = {}

export type Facility = {
	id: Types.FacilityId,
	name: string,
	price: number, -- 졸업 0회 기준. priceOf 로 배율 적용
	income: number, -- 초당
	student: Types.StudentId?, -- 지으면 전학 오는 학생
	skins: { string }, -- A/B/C/D 이름. 색·재질은 SkinConfig
	center: Vector3, -- 부지 로컬
	size: Vector3, -- 방이면 벽 바깥 치수, 가구면 대략 바운딩박스
	pad: Vector3, -- 구매 패드 중심(바닥)
	door: string?, -- "S" | "N" | "W" (방 기준 문 방향). nil = 문 없음
	seats: number, -- Seats/S01… 개수
	spawns: number, -- 이 시설이 여는 칭찬스티커 스폰 수
	floor: number, -- 1 | 2
}

FacilityConfig.PRICE_SCALE = 1.4 -- 졸업 1회마다 가격 ×1.4

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local LIST: { Facility } = {
	{
		id = "desk",
		name = "책상 세트",
		price = 10,
		income = 1,
		student = "s01",
		skins = { "나무", "하늘색", "분홍", "황금" },
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
		price = 60,
		income = 3,
		student = "s02",
		skins = { "초록", "검정", "화이트보드", "황금 테" },
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
		price = 180,
		income = 6,
		student = "s03",
		skins = { "회색", "파랑", "무지개", "황금" },
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
		price = 500,
		income = 12,
		student = "s04",
		skins = { "타일", "나무마루", "파란 카펫", "황금 카펫" },
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
		price = 1500,
		income = 25,
		student = "s05",
		skins = { "크림", "하늘", "연두", "황금" },
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
		price = 4000,
		income = 50,
		student = "s06",
		skins = { "흰 식탁", "주황", "체크", "황금" },
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
		price = 11000,
		income = 90,
		student = "s07",
		skins = { "나무 책장", "파랑", "보라", "황금" },
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
		price = 30000,
		income = 150,
		student = "s08",
		skins = { "흰 커튼", "분홍", "민트", "황금" },
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
		price = 70000,
		income = 260,
		student = "s09",
		skins = { "회색 실험대", "초록", "네온", "황금" },
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
		price = 160000,
		income = 420,
		student = "s10",
		skins = { "갈색 피아노", "흰 피아노", "빨강", "황금" },
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
		price = 350000,
		income = 700,
		student = "s11",
		skins = { "나무 바닥", "파란 매트", "빨간 매트", "황금" },
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
		price = 750000,
		income = 1100,
		student = "s12",
		skins = { "흙", "잔디", "파란 트랙", "황금 트랙" },
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
		price = 1800000,
		income = 1800,
		student = "s13",
		skins = { "갈색 책상", "흰 가죽", "검정", "황금" },
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
		price = 3800000,
		income = 3000,
		student = nil,
		skins = { "빨간 커튼", "파란 커튼", "보라", "황금" },
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

--- 졸업 횟수를 반영한 가격
function FacilityConfig.priceOf(id: Types.FacilityId, graduations: number): number
	local row = BY_ID[id]
	assert(row, `모르는 시설: {id}`)
	return math.floor(row.price * FacilityConfig.PRICE_SCALE ^ graduations + 0.5)
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

--- 다음 시설의 다음(실루엣 30% 로 보여 줄 것). 없으면 nil
function FacilityConfig.afterNextOf(built: { [Types.FacilityId]: boolean }): Facility?
	local seen = false
	for _, id in ORDER do
		if not built[id] then
			if seen then
				return BY_ID[id]
			end
			seen = true
		end
	end
	return nil
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
