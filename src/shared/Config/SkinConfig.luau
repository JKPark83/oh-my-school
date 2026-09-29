--!strict
--[[
	시설 스킨 56개(시설 14 × A/B/C/D). 기획서 §3.2.
	  A 무료 / B 시설가 × 0.5 / C 시설가 × 1.0 / D 시설가 × 1.0 + 졸업 1회 이상. 전부 ×1.4^졸업.
	  서버는 Skins 어트리뷰트만 바꾸고, 색 적용은 클라이언트가 이 표를 읽어서 한다.
	  Geometry 빌더는 build(plotCFrame, skinIndex) 로 primary/secondary/material 을 받아 쓴다.
]]

local Types = require(script.Parent.Parent.Types)
local FacilityConfig = require(script.Parent.FacilityConfig)

local SkinConfig = {}

export type Skin = {
	name: string,
	primary: Color3,
	secondary: Color3,
	material: Enum.Material,
}

local PRICE_MULT = { 0, 0.5, 1.0, 1.0 }
SkinConfig.COUNT = 4
SkinConfig.GRADUATION_INDEX = 4 -- D 는 졸업 1회 이상

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function S(name: string, primary: Color3, secondary: Color3, material: Enum.Material?): Skin
	return { name = name, primary = primary, secondary = secondary, material = material or Enum.Material.SmoothPlastic }
end

local GOLD = C(255, 200, 60)
local GOLD_DARK = C(200, 150, 30)
local GOLD_LIGHT = C(255, 240, 180)
local M = Enum.Material

local ROWS: { [Types.FacilityId]: { Skin } } = {
	desk = {
		S("나무", C(160, 110, 60), C(90, 60, 30), M.Wood),
		S("하늘색", C(135, 206, 235), C(230, 240, 250)),
		S("분홍", C(255, 170, 200), C(255, 230, 240)),
		S("황금", GOLD, GOLD_LIGHT, M.Metal),
	},
	board = {
		S("초록", C(40, 90, 60), C(120, 80, 40), M.Wood),
		S("검정", C(30, 30, 30), C(120, 80, 40), M.Wood),
		S("화이트보드", C(240, 240, 240), C(180, 180, 190)),
		S("황금 테", C(40, 90, 60), GOLD, M.Metal),
	},
	locker = {
		S("회색", C(150, 150, 155), C(100, 100, 105), M.Metal),
		S("파랑", C(70, 120, 220), C(40, 70, 160), M.Metal),
		S("무지개", C(255, 120, 120), C(120, 200, 255), M.Metal),
		S("황금", GOLD, GOLD_DARK, M.Metal),
	},
	hall = {
		S("타일", C(200, 195, 185), C(170, 165, 155)),
		S("나무마루", C(180, 130, 80), C(150, 100, 60), M.WoodPlanks),
		S("파란 카펫", C(60, 90, 180), C(40, 60, 140), M.Fabric),
		S("황금 카펫", C(230, 180, 60), GOLD_DARK, M.Fabric),
	},
	class2 = {
		S("크림", C(245, 235, 215), C(200, 180, 150)),
		S("하늘", C(190, 220, 245), C(150, 190, 230)),
		S("연두", C(200, 235, 180), C(160, 210, 140)),
		S("황금", C(250, 215, 120), GOLD, M.Metal),
	},
	cafeteria = {
		S("흰 식탁", C(240, 240, 240), C(180, 180, 180)),
		S("주황", C(255, 160, 80), C(200, 110, 40)),
		S("체크", C(220, 60, 60), C(240, 240, 240)),
		S("황금", GOLD, GOLD_LIGHT, M.Metal),
	},
	library = {
		S("나무 책장", C(140, 95, 55), C(100, 65, 35), M.Wood),
		S("파랑", C(60, 100, 190), C(40, 70, 150)),
		S("보라", C(140, 90, 200), C(100, 60, 160)),
		S("황금", GOLD, GOLD_DARK, M.Metal),
	},
	nurse = {
		S("흰 커튼", C(245, 245, 245), C(200, 220, 240), M.Fabric),
		S("분홍", C(255, 190, 210), C(240, 150, 180), M.Fabric),
		S("민트", C(170, 235, 215), C(120, 200, 180), M.Fabric),
		S("황금", C(255, 215, 130), GOLD, M.Metal),
	},
	science = {
		S("회색 실험대", C(120, 125, 130), C(80, 85, 90), M.Metal),
		S("초록", C(60, 150, 100), C(40, 110, 70), M.Metal),
		S("네온", C(60, 255, 180), C(20, 20, 30), M.Neon),
		S("황금", GOLD, GOLD_DARK, M.Metal),
	},
	music = {
		S("갈색 피아노", C(90, 55, 30), C(40, 25, 15), M.Wood),
		S("흰 피아노", C(245, 245, 245), C(200, 200, 200)),
		S("빨강", C(200, 40, 50), C(120, 20, 30)),
		S("황금", GOLD, GOLD_LIGHT, M.Metal),
	},
	gym = {
		S("나무 바닥", C(200, 160, 100), C(150, 110, 60), M.WoodPlanks),
		S("파란 매트", C(60, 110, 220), C(40, 80, 170), M.Fabric),
		S("빨간 매트", C(220, 60, 60), C(160, 40, 40), M.Fabric),
		S("황금", GOLD, GOLD_DARK, M.Metal),
	},
	field = {
		S("흙", C(170, 130, 90), C(130, 100, 60), M.Sand),
		S("잔디", C(90, 170, 70), C(60, 130, 50), M.Grass),
		S("파란 트랙", C(60, 110, 220), C(200, 60, 60)),
		S("황금 트랙", GOLD, C(230, 160, 40), M.Metal),
	},
	principal = {
		S("갈색 책상", C(110, 70, 40), C(60, 40, 25), M.Wood),
		S("흰 가죽", C(240, 240, 240), C(200, 200, 200), M.Fabric),
		S("검정", C(30, 30, 30), C(90, 90, 90)),
		S("황금", GOLD, GOLD_LIGHT, M.Metal),
	},
	auditorium = {
		S("빨간 커튼", C(170, 30, 40), C(120, 20, 30), M.Fabric),
		S("파란 커튼", C(40, 70, 160), C(30, 50, 120), M.Fabric),
		S("보라", C(120, 70, 180), C(90, 50, 140), M.Fabric),
		S("황금", GOLD, C(230, 160, 40), M.Metal),
	},
}

SkinConfig.ROWS = ROWS

--- 스킨 행. 없는 번호면 A
function SkinConfig.get(facilityId: Types.FacilityId, index: number): Skin
	local rows = ROWS[facilityId]
	assert(rows, `모르는 시설: {facilityId}`)
	return rows[index] or rows[1]
end

--- 프로필 skinsOwned 키. "desk:2"
function SkinConfig.key(facilityId: Types.FacilityId, index: number): string
	return `{facilityId}:{index}`
end

--- 가격. A 는 0
function SkinConfig.priceOf(facilityId: Types.FacilityId, index: number, graduations: number): number
	local base = FacilityConfig.BY_ID[facilityId].price
	local mult = PRICE_MULT[index] or 0
	return math.floor(base * mult * FacilityConfig.PRICE_SCALE ^ graduations + 0.5)
end

--- 번호가 1~4 정수인가
function SkinConfig.isValidIndex(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= SkinConfig.COUNT
end

--- 적용 중 스킨 → "desk:2,board:1" CSV
function SkinConfig.toCsv(applied: { [Types.FacilityId]: number }): string
	local parts = {}
	for _, id in FacilityConfig.ORDER do
		local idx = applied[id]
		if idx and idx > 1 then
			table.insert(parts, `{id}:{idx}`)
		end
	end
	return table.concat(parts, ",")
end

--- CSV → { desk = 2 }. 없는 시설은 1
function SkinConfig.fromCsv(csv: string): { [Types.FacilityId]: number }
	local applied = {}
	for id, idx in string.gmatch(csv, "([^,:]+):(%d+)") do
		if ROWS[id] then
			applied[id] = tonumber(idx) or 1
		end
	end
	return applied
end

return SkinConfig
