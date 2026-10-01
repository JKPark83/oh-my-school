--!strict
--[[
	층·방 수치의 단일 소스. 개선계획(2026-10-01 층 쌓기) §3.1~§3.4.
	  floors[i] = (i+2)층의 방 id. 옥상 방(kind "roof")은 층 수를 늘리지 않고 맨 위 옥상에 그려진다.
	  단계(step) = 완공한 방 수 + 1. 가격·수입은 방 종류가 아니라 단계로 정한다(STEPS, docs/sim/sim-parts.py 산출).
	  방 로컬 좌표: 원점 = TOWER_FOOTPRINT 중심·그 층 바닥 윗면(origin(n)). +Z 가 남쪽(교문 쪽).
	서버(구매 판정)와 클라(패널·렌더·HUD)가 같은 함수를 쓴다. STEPS 는 check-config.py 가 시뮬과 대조한다.
]]

local Types = require(script.Parent.Parent.Types)
local PlotLayout = require(script.Parent.Parent.PlotLayout)
local StudentConfig = require(script.Parent.StudentConfig)

local RoomConfig = {}

export type Room = {
	id: string,
	name: string,
	kind: "floor" | "roof",
	student: string?, -- 처음 완공하면 오는 학생
	wall: Color3, -- 외벽 색(빨강 계열 금지)
	accent: Color3, -- 포인트 색
	icon: string, -- 간판·카드 이모지 한 글자
	seats: { Vector3 }, -- 방 로컬 좌표(바닥 높이 y 0). 학생 자리는 StudentConfig seat 번호
	seatYaw: number?, -- 좌석 방향(도). 기본 0 = −Z(북쪽) 보고 앉는다
	zone: Zone?, -- 옥상 방만: 이 방 가구를 놓는 옥상 구역(방 로컬). 층 방은 벽 안쪽 전체
}
export type Zone = { x0: number, x1: number, z0: number, z1: number }

RoomConfig.FIRST_FLOOR = 3
RoomConfig.MAX_FLOOR = 30 -- P2 실측으로 확정
RoomConfig.PARTS = 4
RoomConfig.PART_NAMES = { "뼈대", "큰 가구", "소품", "마무리 장식" }
RoomConfig.PART_WEIGHTS = { 0.1, 0.2, 0.3, 0.4 } -- 단계 가격을 부품 4개로 나눈 비율(시뮬이 이미 나눠 STEPS 에 넣었다)

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- 도감·패널 순서. 색은 색상환을 따라 서로 구분되는 밝은 파스텔.
-- 방마다 seats 블록을 따로 둔다(방 레시피 담당이 자기 블록만 고친다). 규칙은 맨 아래 자기 검사·tools/check_rooms.luau.
-- 층 방 공통 임시 배치: 서쪽 3열 × 2줄. 가운데(0, 0)와 엘리베이터 도착 → 가운데 통로를 비운다
local LIST: { Room } = {
	{
		id = "art",
		name = "미술실",
		kind = "floor",
		student = "s16",
		wall = C(255, 222, 180),
		accent = C(240, 160, 80),
		icon = "🎨",
		-- 1~3 = 이젤 앞 스툴(1 가운데 이젤), 4·5 = 작업 탁자 남쪽 스툴
		seats = {
			Vector3.new(-8, 0, -6),
			Vector3.new(-14, 0, -6),
			Vector3.new(-2, 0, -6),
			Vector3.new(-13, 0, 8.6),
			Vector3.new(-7, 0, 8.6),
		},
	},
	{
		id = "computer",
		name = "컴퓨터실",
		kind = "floor",
		student = "s15",
		wall = C(185, 215, 250),
		accent = C(70, 130, 220),
		icon = "💻",
		-- 컴퓨터 책상 2줄 × 3(1 = 앞줄 가운데)
		seats = {
			Vector3.new(-9, 0, -6),
			Vector3.new(-14, 0, -6),
			Vector3.new(-4, 0, -6),
			Vector3.new(-14, 0, 4),
			Vector3.new(-9, 0, 4),
			Vector3.new(-4, 0, 4),
		},
	},
	{
		id = "broadcast",
		name = "방송실",
		kind = "floor",
		student = "s21",
		wall = C(225, 205, 250),
		accent = C(140, 100, 210),
		icon = "🎤",
		-- 남쪽(카메라)을 본다. 1·2 = 방송 데스크 앵커, 3 = 믹서 콘솔, 4·5 = 미리보기 모니터
		seats = {
			Vector3.new(-7, 0, -9),
			Vector3.new(-3, 0, -9),
			Vector3.new(-15, 0, 0),
			Vector3.new(-9, 0, 6),
			Vector3.new(-4, 0, 6),
		},
		seatYaw = 180,
	},
	{
		id = "cooking",
		name = "요리실",
		kind = "floor",
		student = "s25",
		wall = C(255, 240, 175),
		accent = C(225, 185, 50),
		icon = "🍳",
		seats = { -- [1]~[4] 조리대 남쪽 스툴, [5]·[6] 시식 탁자
			Vector3.new(-13, 0, -6),
			Vector3.new(-5, 0, -6),
			Vector3.new(-13, 0, 6),
			Vector3.new(-5, 0, 6),
			Vector3.new(3.5, 0, -2.9),
			Vector3.new(6.5, 0, -2.9),
		},
	},
	{
		id = "dance",
		name = "댄스실",
		kind = "floor",
		student = "s26",
		wall = C(245, 210, 250),
		accent = C(200, 120, 220),
		icon = "💃",
		seats = { -- 서쪽 벽 긴 벤치(학생 메시가 앉은 포즈뿐이라 서 있지 않는다)
			Vector3.new(-16.5, 0, -6),
			Vector3.new(-16.5, 0, -2),
			Vector3.new(-16.5, 0, 2),
			Vector3.new(-16.5, 0, 6),
		},
		seatYaw = 270, -- 동쪽(춤추는 마루)을 본다
	},
	{
		id = "robot",
		name = "코딩로봇실",
		kind = "floor",
		student = "s20",
		wall = C(190, 240, 225),
		accent = C(50, 170, 150),
		icon = "🤖",
		seats = { -- [1]·[2] 로봇 경기장 앞, [3]~[5] 노트북 책상
			Vector3.new(-9, 0, 1.6),
			Vector3.new(-5, 0, 1.6),
			Vector3.new(-14, 0, 10),
			Vector3.new(-8, 0, 10),
			Vector3.new(-2, 0, 10),
		},
	},
	{
		id = "english",
		name = "영어체험실",
		kind = "floor",
		student = "s19",
		wall = C(205, 210, 255),
		accent = C(100, 110, 220),
		icon = "🌍",
		-- 1 가게 계산대 뒤, 2 공항 체크인 데스크 뒤, 3~5 남쪽 책상(세계 지도를 본다)
		seats = {
			Vector3.new(-13, 0, -4.5),
			Vector3.new(10, 0, -6),
			Vector3.new(-15, 0, 8),
			Vector3.new(-9, 0, 8),
			Vector3.new(-3, 0, 8),
		},
	},
	{
		id = "care",
		name = "돌봄교실",
		kind = "floor",
		student = "s27",
		wall = C(210, 245, 195),
		accent = C(100, 180, 80),
		icon = "🧸",
		-- 1·2 낮은 원탁 방석, 3·4 책 읽는 빈백, 5 간식 탁자
		seats = {
			Vector3.new(-12, 0, -2),
			Vector3.new(-8, 0, -2),
			Vector3.new(-4.5, 0, 10),
			Vector3.new(-0.5, 0, 10),
			Vector3.new(8, 0, 11.5),
		},
	},
	{
		id = "staff",
		name = "교무실",
		kind = "floor",
		student = "s18",
		wall = C(235, 228, 210),
		accent = C(150, 125, 95),
		icon = "📋",
		-- 1·6 회의 탁자(남쪽), 2~5 선생님 책상 2줄
		seats = {
			Vector3.new(-1.5, 0, 12),
			Vector3.new(-15, 0, -5),
			Vector3.new(-10, 0, -5),
			Vector3.new(-15, 0, 3),
			Vector3.new(-10, 0, 3),
			Vector3.new(1.5, 0, 12),
		},
	},
	{
		id = "exhibit",
		name = "전시실",
		kind = "floor",
		student = "s23",
		wall = C(185, 235, 245),
		accent = C(40, 160, 195),
		icon = "🦕",
		-- 공룡 앞 관람 벤치: 앞줄 3(1번 = 가운데) + 뒷줄 2
		seats = {
			Vector3.new(-9, 0, 1),
			Vector3.new(-13, 0, 1),
			Vector3.new(-5, 0, 1),
			Vector3.new(-11, 0, 8),
			Vector3.new(-7, 0, 8),
		},
	},
	{
		id = "garden",
		name = "옥상정원",
		kind = "roof",
		student = "s24",
		wall = C(230, 250, 185),
		accent = C(130, 195, 50),
		icon = "🌻",
		zone = { x0 = -18.9, x1 = -2, z0 = -13.9, z1 = 13.9 }, -- 옥상 서쪽(난간 충돌 벽 안쪽 면 ±18.95·±13.95 안)
		-- 1번 = 텃밭 앞 스툴, 2~4 = 남쪽 등받이 벤치
		seats = {
			Vector3.new(-11, 0, -5.5),
			Vector3.new(-16, 0, 6),
			Vector3.new(-13, 0, 6),
			Vector3.new(-10, 0, 6),
		},
	},
	{
		id = "observatory",
		name = "천문대",
		kind = "roof",
		student = "s28",
		wall = C(195, 195, 230),
		accent = C(70, 75, 165),
		icon = "🔭",
		zone = { x0 = 0, x1 = 11, z0 = -13.9, z1 = -3 }, -- 옥상 가운데~동쪽 북편(금지 구역·기둥·난간 비킴)
		-- 1번 = 망원경 접안렌즈 뒤 스툴, 2·3 = 별자리 판 앞 벤치, 4 = 동쪽 스툴
		seats = {
			Vector3.new(7.5, 0, -6),
			Vector3.new(1.8, 0, -5.5),
			Vector3.new(4.4, 0, -5.5),
			Vector3.new(10, 0, -8.8),
		},
	},
}

local BY_ID: { [string]: Room } = {}
local FLOOR_KINDS = 0
for _, room in LIST do
	BY_ID[room.id] = room
	if room.kind == "floor" then
		FLOOR_KINDS += 1
	end
end
RoomConfig.LIST = LIST
RoomConfig.BY_ID = BY_ID

-- 단계표(docs/sim/sim-parts-output.md 「(e) Luau 붙여 넣기용」 그대로). 단계 s 의 부품 가격 4개와 완공 수입
RoomConfig.STEPS = {
	{ parts = { 650000, 1300000, 2000000, 2600000 }, income = 760 }, -- 1
	{ parts = { 820000, 1600000, 2500000, 3300000 }, income = 840 }, -- 2
	{ parts = { 1100000, 2200000, 3300000, 4400000 }, income = 920 }, -- 3
	{ parts = { 1700000, 3300000, 5000000, 6600000 }, income = 1000 }, -- 4
	{ parts = { 2200000, 4400000, 6600000, 8800000 }, income = 1100 }, -- 5
	{ parts = { 3100000, 6100000, 9200000, 12000000 }, income = 1200 }, -- 6
	{ parts = { 4900000, 9700000, 15000000, 19000000 }, income = 1300 }, -- 7
	{ parts = { 7100000, 14000000, 21000000, 28000000 }, income = 1500 }, -- 8
	{ parts = { 10000000, 20000000, 30000000, 40000000 }, income = 1600 }, -- 9
	{ parts = { 13000000, 26000000, 39000000, 52000000 }, income = 1800 }, -- 10
	{ parts = { 18000000, 36000000, 54000000, 73000000 }, income = 2000 }, -- 11
	{ parts = { 26000000, 52000000, 78000000, 100000000 }, income = 2200 }, -- 12
	{ parts = { 33000000, 67000000, 100000000, 130000000 }, income = 2400 }, -- 13
	{ parts = { 41000000, 83000000, 120000000, 170000000 }, income = 2600 }, -- 14
	{ parts = { 51000000, 100000000, 150000000, 200000000 }, income = 2900 }, -- 15
	{ parts = { 62000000, 120000000, 190000000, 250000000 }, income = 3200 }, -- 16
	{ parts = { 76000000, 150000000, 230000000, 300000000 }, income = 3500 }, -- 17
	{ parts = { 92000000, 180000000, 280000000, 370000000 }, income = 3800 }, -- 18
	{ parts = { 110000000, 220000000, 330000000, 450000000 }, income = 4200 }, -- 19
	{ parts = { 130000000, 270000000, 400000000, 540000000 }, income = 4600 }, -- 20
	{ parts = { 150000000, 290000000, 440000000, 590000000 }, income = 5100 }, -- 21
	{ parts = { 160000000, 320000000, 490000000, 650000000 }, income = 5600 }, -- 22
	{ parts = { 180000000, 360000000, 530000000, 710000000 }, income = 6200 }, -- 23
	{ parts = { 200000000, 390000000, 590000000, 780000000 }, income = 6800 }, -- 24
	{ parts = { 220000000, 430000000, 650000000, 860000000 }, income = 7500 }, -- 25
	{ parts = { 240000000, 470000000, 710000000, 950000000 }, income = 8200 }, -- 26
	{ parts = { 260000000, 520000000, 780000000, 1000000000 }, income = 9000 }, -- 27
	{ parts = { 290000000, 570000000, 860000000, 1100000000 }, income = 9900 }, -- 28
	{ parts = { 320000000, 630000000, 950000000, 1300000000 }, income = 11000 }, -- 29
	{ parts = { 350000000, 690000000, 1000000000, 1400000000 }, income = 12000 }, -- 30
}

local MAX_FLOORS = RoomConfig.MAX_FLOOR - RoomConfig.FIRST_FLOOR + 1 -- 지을 수 있는 층 방 수

local function roofCount(rooftop: { [string]: boolean }): number
	local n = 0
	for id, built in rooftop do
		if built and BY_ID[id] then
			n += 1
		end
	end
	return n
end

--- 층 쌓기가 열렸는가(강당 완공)
function RoomConfig.isOpen(profile: Types.Profile): boolean
	return profile.facilities.auditorium == true
end

--- 지금(다음에 완공할) 단계 = 완공한 방 수 + 1
function RoomConfig.stepOf(profile: Types.Profile): number
	return #profile.floors + roofCount(profile.rooftop) + 1
end

--- 다음에 지을 단계. 층 방을 더 못 짓고 옥상 방도 다 지었으면 nil
function RoomConfig.nextStep(profile: Types.Profile): number?
	if #profile.floors >= MAX_FLOORS and roofCount(profile.rooftop) >= #LIST - FLOOR_KINDS then
		return nil
	end
	return RoomConfig.stepOf(profile)
end

--- 단계 step 의 k 번째 부품 가격
function RoomConfig.partPrice(step: number, k: number): number
	return RoomConfig.STEPS[step].parts[k]
end

--- 완공한 단계들의 초당 수입 합(배율 전)
function RoomConfig.incomeOf(profile: Types.Profile): number
	local sum = 0
	for s = 1, math.min(RoomConfig.stepOf(profile) - 1, #RoomConfig.STEPS) do
		sum += RoomConfig.STEPS[s].income
	end
	return sum
end

--- 지금 그 방을 고를 수 있는가(§3.2). 강당 완공 + 짓는 방 없음 포함 — 서버 ChooseRoom 판정이 그대로 쓴다
function RoomConfig.canChoose(profile: Types.Profile, roomId: string): boolean
	local room = BY_ID[roomId]
	if not room or not RoomConfig.isOpen(profile) or profile.towerRoom ~= "" then
		return false
	end
	if room.kind == "roof" then
		return not profile.rooftop[roomId]
	end
	if #profile.floors >= MAX_FLOORS then
		return false
	end
	-- 안 지은 층 방 종류가 남아 있으면 그중에서만
	local built: { [string]: boolean } = {}
	for _, id in profile.floors do
		built[id] = true
	end
	local unbuiltLeft = false
	for _, other in LIST do
		if other.kind == "floor" and not built[other.id] then
			unbuiltLeft = true
			break
		end
	end
	return not unbuiltLeft or not built[roomId]
end

--- 고를 수 있는 방(LIST 순서)
function RoomConfig.choices(profile: Types.Profile): { Room }
	local out = {}
	for _, room in LIST do
		if RoomConfig.canChoose(profile, room.id) then
			table.insert(out, room)
		end
	end
	return out
end

--- n층 바닥 윗면 y(부지 로컬). 1층 0, 2층 강당 바닥, 3층부터 TOWER_BASE_Y + (n-3) × FLOOR_STEP
function RoomConfig.floorY(n: number): number
	if n <= 1 then
		return 0
	elseif n == 2 then
		return PlotLayout.WALL_H + PlotLayout.AUDITORIUM_FLOOR_T
	end
	return PlotLayout.TOWER_BASE_Y + (n - RoomConfig.FIRST_FLOOR) * PlotLayout.FLOOR_STEP
end

--- n층 방의 로컬 원점(부지 로컬) = 발자국 중심·바닥 윗면. 부지 로컬 = origin(n) + 방 로컬
function RoomConfig.origin(n: number): Vector3
	local f = PlotLayout.TOWER_FOOTPRINT
	return Vector3.new((f.x0 + f.x1) / 2, RoomConfig.floorY(n), (f.z0 + f.z1) / 2)
end

--- 맨 위 완공 층 번호(층이 0 이면 2 = 강당). 옥상은 그 위(topFloor + 1)
function RoomConfig.topFloor(floorCount: number): number
	return 2 + floorCount
end

--- n층의 방 id. 3층 미만이거나 아직 없으면 nil
function RoomConfig.roomOfFloor(floors: { string }, n: number): string?
	return floors[n - 2]
end

--- 방 id 목록 → CSV(어트리뷰트 Floors·Rooftop)
function RoomConfig.toCsv(ids: { string }): string
	return table.concat(ids, ",")
end

--- CSV → 방 id 목록(모르는 id 는 버린다)
function RoomConfig.fromCsv(csv: string): { string }
	local out = {}
	for id in string.gmatch(csv, "[^,]+") do
		if BY_ID[id] then
			table.insert(out, id)
		end
	end
	return out
end

--- 옥상 방 집합 → 정렬된 id 목록(Rooftop CSV 는 toCsv(rooftopList(rooftop)))
function RoomConfig.rooftopList(rooftop: { [string]: boolean }): { string }
	local out = {}
	for id, built in rooftop do
		if built and BY_ID[id] then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- ── 자기 검사 ─────────────────────────────────────────────────────
do
	assert(#LIST == 12, `RoomConfig: 방이 12개가 아니다({#LIST})`)
	assert(FLOOR_KINDS == 10, `RoomConfig: floor 방이 10개가 아니다({FLOOR_KINDS})`)
	assert(
		#RoomConfig.STEPS >= MAX_FLOORS + (#LIST - FLOOR_KINDS),
		"RoomConfig: STEPS 가 층 상한 + 옥상 방 수보다 적다"
	)
	local wsum = 0
	for _, w in RoomConfig.PART_WEIGHTS do
		wsum += w
	end
	assert(math.abs(wsum - 1) < 1e-9, "RoomConfig: PART_WEIGHTS 합이 1 이 아니다")
	for _, step in RoomConfig.STEPS do
		assert(#step.parts == RoomConfig.PARTS, "RoomConfig: STEPS 부품 수가 PARTS 와 다르다")
	end
	-- 방 로컬로 옮긴 가구 금지 구역·벽에서 3 안쪽
	local o, f, clear = RoomConfig.origin(RoomConfig.FIRST_FLOOR), PlotLayout.TOWER_FOOTPRINT, PlotLayout.TOWER_CLEAR
	local hx, hz = (f.x1 - f.x0) / 2 - 3, (f.z1 - f.z0) / 2 - 3
	for _, room in LIST do
		local row = room.student and StudentConfig.BY_ID[room.student]
		assert(row, `RoomConfig: {room.id} 학생이 StudentConfig 에 없다`)
		assert(
			row.unlock.kind == "room" and row.unlock.value == room.id and row.seat.facilityId == room.id,
			`RoomConfig: {room.id} 학생 {row.id} 의 unlock·seat 가 이 방이 아니다`
		)
		assert(room.seats[row.seat.index], `RoomConfig: {room.id} 에 학생 좌석 {row.seat.index} 이 없다`)
		assert(#room.seats >= 4 and #room.seats <= 6, `RoomConfig: {room.id} 좌석이 4~6개가 아니다`)
		local zone = room.zone
		assert(
			(room.kind == "roof") == (zone ~= nil),
			`RoomConfig: {room.id} zone 은 옥상 방에만(옥상 방은 꼭) 둔다`
		)
		for _, s in room.seats do
			local x, z = s.X + o.X, s.Z + o.Z
			assert(
				not zone or (s.X > zone.x0 and s.X < zone.x1 and s.Z > zone.z0 and s.Z < zone.z1),
				`RoomConfig: {room.id} 좌석이 옥상 구역 밖이다`
			)
			assert(
				math.abs(s.X) <= hx and math.abs(s.Z) <= hz,
				`RoomConfig: {room.id} 좌석이 벽에서 3 안쪽이 아니다`
			)
			assert(
				not (x >= clear.x0 and z >= clear.z0),
				`RoomConfig: {room.id} 좌석이 가구 금지 구역 안이다`
			)
		end
	end
	-- StudentConfig 의 room 해금이 전부 이 표의 방이다
	for _, s in StudentConfig.LIST do
		if s.unlock.kind == "room" then
			assert(BY_ID[s.unlock.value], `RoomConfig: 학생 {s.id} 의 방 {s.unlock.value} 가 없다`)
		end
	end
end

return RoomConfig
