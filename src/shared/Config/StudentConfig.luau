--!strict
--[[
	전학생 28명. 기획서 §4.1·§4.2·§4.4, 개선계획(2026-10-01 층 쌓기) §3.1·§3.4.
	  mesh            CharacterAssets.VARIANTS 키. 없으면(아직 안 만든 희귀 메시) fallbackVariant + tint 로 그린다
	  tint            fallbackVariant 로 그릴 때 몸 전체에 곱하는 색. nil 이면 원본 텍스처
	  prop            fallbackVariant 로 그릴 때 붙이는 소품 하나(≤1. 전용 메시엔 이미 있다). 등급 표식(완장·메달·파티클)은 tier 가 정하므로 여기 없다
	  seat            정해진 자리. facilityId 는 시설 id 또는 방 id. 그 시설·방이 없으면 자리 없음(Seats.seatOf)
	  unlock          kind = "facility" (시설을 지으면) | "room" (그 방을 처음 완공하면) | "friend" (처음부터 진열된 친구 아이템을 사면)
]]

local Types = require(script.Parent.Parent.Types)

local StudentConfig = {}

export type Unlock = {
	kind: "facility" | "room" | "friend",
	value: string, -- facility → 시설 id, room → 방 id, friend → ""
}

export type Student = {
	id: Types.StudentId,
	name: string,
	tier: Types.Tier,
	mesh: string,
	fallbackVariant: string,
	tint: Color3?,
	prop: string?,
	seat: Types.Seat,
	unlock: Unlock,
}

-- 등급별 수입 기여(합산해서 배율에 더한다)
local CONTRIB: { [Types.Tier]: number } = {
	["평범"] = 0.05,
	["반장"] = 0.15,
	["전교1등"] = 0.40,
	["전설"] = 0.60,
}

-- 등급별 도감 테두리(색, 두께 px)
local TIER_STYLE: { [Types.Tier]: { color: Color3, stroke: number } } = {
	["평범"] = { color = Color3.fromRGB(156, 163, 175), stroke = 2 },
	["반장"] = { color = Color3.fromRGB(96, 165, 250), stroke = 3 },
	["전교1등"] = { color = Color3.fromRGB(167, 139, 250), stroke = 4 },
	["전설"] = { color = Color3.fromRGB(245, 158, 11), stroke = 6 },
}

local TIER_ORDER: { Types.Tier } = { "평범", "반장", "전교1등", "전설" }
StudentConfig.CONTRIB = CONTRIB
StudentConfig.TIER_STYLE = TIER_STYLE
StudentConfig.TIER_ORDER = TIER_ORDER

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function seat(facilityId: string, index: number): Types.Seat
	return { facilityId = facilityId, index = index }
end

local function byFacility(id: string): Unlock
	return { kind = "facility", value = id }
end

local function byRoom(roomId: string): Unlock
	return { kind = "room", value = roomId }
end

local function byFriend(): Unlock
	return { kind = "friend", value = "" }
end

local LIST: { Student } = {
	-- 평범 (시설 확정)
	{
		id = "s01",
		name = "김하늘",
		tier = "평범",
		mesh = "GIRL_A",
		fallbackVariant = "GIRL_A",
		tint = nil,
		prop = "hairpin",
		seat = seat("desk", 1),
		unlock = byFacility("desk"),
	},
	{
		id = "s02",
		name = "이준서",
		tier = "평범",
		mesh = "BOY_A",
		fallbackVariant = "BOY_A",
		tint = nil,
		prop = nil, -- 모자류는 조각 머리에 떠 보여서 벗겼다(2026-10-01)
		seat = seat("desk", 2),
		unlock = byFacility("board"),
	},
	{
		id = "s03",
		name = "박서연",
		tier = "평범",
		mesh = "GIRL_B",
		fallbackVariant = "GIRL_B",
		tint = nil,
		prop = "glasses",
		seat = seat("desk", 3),
		unlock = byFacility("locker"),
	},
	{
		id = "s04",
		name = "최민준",
		tier = "평범",
		mesh = "BOY_B",
		fallbackVariant = "BOY_B",
		tint = nil,
		prop = "scarf",
		seat = seat("desk", 4),
		unlock = byFacility("hall"),
	},
	{
		id = "s05",
		name = "정수아",
		tier = "평범",
		mesh = "GIRL_C",
		fallbackVariant = "GIRL_C",
		tint = nil,
		prop = "bag",
		seat = seat("class2", 2),
		unlock = byFacility("class2"),
	},
	{
		id = "s06",
		name = "강도윤",
		tier = "평범",
		mesh = "BOY_C",
		fallbackVariant = "BOY_C",
		tint = C(190, 235, 190),
		prop = nil,
		seat = seat("cafeteria", 1),
		unlock = byFacility("cafeteria"),
	},
	{
		id = "s07",
		name = "윤지우",
		tier = "평범",
		mesh = "GIRL_D",
		fallbackVariant = "GIRL_D",
		tint = nil,
		prop = nil, -- 모자류는 조각 머리에 떠 보여서 벗겼다(2026-10-01)
		seat = seat("library", 1),
		unlock = byFacility("library"),
	},
	{
		id = "s08",
		name = "임하린",
		tier = "평범",
		mesh = "GIRL_E",
		fallbackVariant = "GIRL_E",
		tint = C(220, 200, 245),
		prop = "glasses",
		seat = seat("nurse", 1),
		unlock = byFacility("nurse"),
	},
	{
		id = "s09",
		name = "오시우",
		tier = "평범",
		mesh = "BOY_D",
		fallbackVariant = "BOY_D",
		tint = C(245, 235, 180),
		prop = nil, -- 모자류는 조각 머리에 떠 보여서 벗겼다(2026-10-01)
		seat = seat("science", 1),
		unlock = byFacility("science"),
	},
	{
		id = "s10",
		name = "한예린",
		tier = "평범",
		mesh = "GIRL_A",
		fallbackVariant = "GIRL_A",
		tint = C(200, 230, 250),
		prop = "glasses",
		seat = seat("music", 1),
		unlock = byFacility("music"),
	},
	-- 반장
	{
		id = "s11",
		name = "송태양",
		tier = "반장",
		mesh = "BOY_B",
		fallbackVariant = "BOY_B",
		tint = C(250, 200, 200),
		prop = nil,
		seat = seat("science", 2),
		unlock = byFacility("gym"),
	},
	{
		id = "s12",
		name = "문유나",
		tier = "반장",
		mesh = "GIRL_B",
		fallbackVariant = "GIRL_B",
		tint = C(250, 240, 190),
		prop = nil,
		seat = seat("music", 2),
		unlock = byFacility("field"),
	},
	{
		id = "s13",
		name = "배준혁",
		tier = "반장",
		mesh = "BOY_C",
		fallbackVariant = "BOY_C",
		tint = C(200, 215, 250),
		prop = nil,
		seat = seat("principal", 1),
		unlock = byFacility("principal"),
	},
	{
		id = "s14",
		name = "채원",
		tier = "반장",
		mesh = "GIRL_C",
		fallbackVariant = "GIRL_C",
		tint = C(200, 245, 205),
		prop = nil,
		seat = seat("desk", 5),
		unlock = byFriend(),
	},
	{
		id = "s15",
		name = "건우",
		tier = "반장",
		mesh = "BOY_D",
		fallbackVariant = "BOY_D",
		tint = C(225, 205, 250),
		prop = nil,
		seat = seat("computer", 1),
		unlock = byRoom("computer"),
	},
	{
		id = "s16",
		name = "서윤",
		tier = "반장",
		mesh = "GIRL_D",
		fallbackVariant = "GIRL_D",
		tint = C(250, 215, 180),
		prop = nil,
		seat = seat("art", 1),
		unlock = byRoom("art"),
	},
	-- 전교1등
	{
		id = "s17",
		name = "하율",
		tier = "전교1등",
		mesh = "HAYUL",
		fallbackVariant = "GIRL_C",
		tint = C(215, 195, 245),
		prop = "goldGlasses",
		seat = seat("desk", 6),
		unlock = byFriend(),
	},
	{
		id = "s18",
		name = "권도현",
		tier = "전교1등",
		mesh = "DOHYUN",
		fallbackVariant = "BOY_B",
		tint = C(180, 190, 230),
		prop = "trophy",
		seat = seat("staff", 1),
		unlock = byRoom("staff"),
	},
	{
		id = "s19",
		name = "지안",
		tier = "전교1등",
		mesh = "JIAN",
		fallbackVariant = "GIRL_D",
		tint = C(195, 225, 250),
		prop = "books",
		seat = seat("english", 1),
		unlock = byRoom("english"),
	},
	{
		id = "s20",
		name = "은우",
		tier = "전교1등",
		mesh = "EUNWOO",
		fallbackVariant = "BOY_A",
		tint = C(195, 240, 200),
		prop = "goggles",
		seat = seat("robot", 1),
		unlock = byRoom("robot"),
	},
	{
		id = "s21",
		name = "서하",
		tier = "전교1등",
		mesh = "SEOHA",
		fallbackVariant = "GIRL_A",
		tint = C(250, 205, 225),
		prop = "violin",
		seat = seat("broadcast", 1),
		unlock = byRoom("broadcast"),
	},
	-- 전설
	{
		id = "s22",
		name = "코스모",
		tier = "전설",
		mesh = "COSMO",
		fallbackVariant = "BOY_A",
		tint = C(215, 220, 230),
		prop = "helmet",
		seat = seat("class2", 1),
		unlock = byFriend(),
	},
	{
		id = "s23",
		name = "금동이",
		tier = "전설",
		mesh = "GEUMDONG",
		fallbackVariant = "GIRL_E",
		tint = C(250, 215, 120),
		prop = "crown",
		seat = seat("exhibit", 1),
		unlock = byRoom("exhibit"),
	},
	{
		id = "s24",
		name = "백호",
		tier = "전설",
		mesh = "BAEKHO",
		fallbackVariant = "BOY_D",
		tint = C(245, 245, 245),
		prop = "tigerEars",
		seat = seat("garden", 1),
		unlock = byRoom("garden"),
	},
	-- 새 방 학생(2026-10-01 층 쌓기). 전용 메시 없이 fallbackVariant + tint
	{
		id = "s25",
		name = "다온",
		tier = "평범",
		mesh = "GIRL_B",
		fallbackVariant = "GIRL_B",
		tint = C(250, 230, 200),
		prop = nil,
		seat = seat("cooking", 1),
		unlock = byRoom("cooking"),
	},
	{
		id = "s26",
		name = "시온",
		tier = "반장",
		mesh = "BOY_A",
		fallbackVariant = "BOY_A",
		tint = C(250, 210, 240),
		prop = nil,
		seat = seat("dance", 1),
		unlock = byRoom("dance"),
	},
	{
		id = "s27",
		name = "새봄",
		tier = "평범",
		mesh = "GIRL_E",
		fallbackVariant = "GIRL_E",
		tint = C(215, 245, 225),
		prop = "bag",
		seat = seat("care", 1),
		unlock = byRoom("care"),
	},
	{
		id = "s28",
		name = "별하",
		tier = "반장",
		mesh = "BOY_C",
		fallbackVariant = "BOY_C",
		tint = C(200, 205, 245),
		prop = "glasses",
		seat = seat("observatory", 1),
		unlock = byRoom("observatory"),
	},
}

local BY_ID: { [Types.StudentId]: Student } = {}
local ORDER: { Types.StudentId } = {}
for i, row in LIST do
	BY_ID[row.id] = row
	ORDER[i] = row.id
end

StudentConfig.LIST = LIST
StudentConfig.BY_ID = BY_ID
StudentConfig.ORDER = ORDER -- 도감 순서(s01 → s28)
StudentConfig.COUNT = #LIST
assert(StudentConfig.COUNT == 28, `StudentConfig: 학생이 28명이 아니다({StudentConfig.COUNT})`)

--- 시설을 지을 때 오는 학생. 없으면 nil
function StudentConfig.byFacility(facilityId: Types.FacilityId): Student?
	for _, row in LIST do
		if row.unlock.kind == "facility" and row.unlock.value == facilityId then
			return row
		end
	end
	return nil
end

--- 방을 처음 완공할 때 오는 학생. 없으면 nil
function StudentConfig.byRoom(roomId: string): Student?
	for _, row in LIST do
		if row.unlock.kind == "room" and row.unlock.value == roomId then
			return row
		end
	end
	return nil
end

--- 보유 학생 수(중복 제외)
function StudentConfig.ownedCount(students: { [Types.StudentId]: number }): number
	local n = 0
	for id, count in students do
		if BY_ID[id] and count > 0 then
			n += 1
		end
	end
	return n
end

--- 보유 학생 기여 합(중복 제외)
function StudentConfig.contribSum(students: { [Types.StudentId]: number }): number
	local sum = 0
	for id, count in students do
		local row = BY_ID[id]
		if row and count > 0 then
			sum += CONTRIB[row.tier]
		end
	end
	return sum
end

--- "s01,s02" CSV. 도감 순서대로
function StudentConfig.toCsv(students: { [Types.StudentId]: number }): string
	local parts = {}
	for _, id in ORDER do
		if (students[id] or 0) > 0 then
			table.insert(parts, id)
		end
	end
	return table.concat(parts, ",")
end

--- CSV → { [id] = true }
function StudentConfig.fromCsv(csv: string): { [Types.StudentId]: boolean }
	local set = {}
	for id in string.gmatch(csv, "[^,]+") do
		if BY_ID[id] then
			set[id] = true
		end
	end
	return set
end

return StudentConfig
