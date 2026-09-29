--!strict
--[[
	복도(시설 4) — 1층 가로 복도 150×15. 계획서 §3.6 규약, 기획서 §7.2.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 25개(≤25), 전부 BuildKit.part.
	  바닥판(primary) + 가운데 줄무늬(secondary) + 북벽·남벽(문 자리마다 끊고 상인방) + 양 끝벽 + 지붕.
	  북벽 z=−26 쪽 문: 교실1·교실2·급식실·도서관(뒷줄 방 남문). 남벽 z=−14 쪽 문: 현관 북문·보건실·과학실·음악실·교장실.
	  문 x 는 FacilityConfig 의 방 center.X 에서 읽고, 교실1·현관은 Shell 소유라 기획서 §7.2 상수를 쓴다.
	  벽은 사실 톤 크림 고정색. 스킨은 바닥에만 간다. 자리·문 Attachment 없음, SkinSign 은 현관 북문 옆 복도 안 눈높이.
	  뒷줄 방 남벽(z −27~−26)과 이 복도 북벽(z −26~−25)은 등을 맞댄 별개 벽이다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local hall = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local FACILITY_ID = script.Name
local SIGN_EYE = 4.5

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local FLOOR_INSET = 0.05 -- 바닥 끝면이 벽 바깥면과 같은 평면이면 깜빡인다. 벽 속으로 조금 들인다
local STRIPE_W = 1.6
local DOOR_W = 8
local DOOR_H = 8

-- Shell 이 짓는 방의 문 x(기획서 §7.2). 교실 1 남문 (−60,−32.5), 현관 북문 (0,−17.5)
local CLASS1_DOOR_X = -60
local ENTRANCE_DOOR_X = 0
local NORTH_ROOMS = { "class2", "cafeteria", "library" } -- 뒷줄, 남문이 복도 북벽에 닿는다
local SOUTH_ROOMS = { "nurse", "science", "music", "principal" } -- 앞줄, 북문이 복도 남벽에 닿는다

local C = {
	wall = Color3.fromRGB(228, 222, 208),
	roof = Color3.fromRGB(70, 72, 76),
}

--- 부지 로컬 위치 → 월드 CFrame
local function at(plotCFrame: CFrame, x: number, y: number, z: number): CFrame
	return plotCFrame * CFrame.new(x, y, z)
end

--- BuildKit.part 를 월드 CFrame 으로 부른다
local function put(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

--- 월드 CFrame 을 그대로 가진 Attachment(부모가 BasePart 가 아니다)
local function attach(parent: Instance, name: string, cf: CFrame): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

local function wallOpts(): BuildKit.Opts
	return { color = C.wall, material = Enum.Material.Concrete, fade = true }
end

--- X 방향 긴 벽 하나를 문 자리마다 끊는다. 문 n개 → 벽 조각 n+1 + 상인방 n
local function wallRow(
	model: Model,
	plotCFrame: CFrame,
	name: string,
	z: number,
	x0: number,
	x1: number,
	floorY: number,
	h: number,
	doors: { number }
)
	table.sort(doors)
	local y = floorY + h / 2
	local cursor = x0
	local index = 0
	local function seg(a: number, b: number)
		if b - a <= 0 then
			return
		end
		index += 1
		put(
			model,
			string.format("%s%02d", name, index),
			Vector3.new(b - a, h, WALL_T),
			at(plotCFrame, (a + b) / 2, y, z),
			wallOpts()
		)
	end
	for i, doorX in doors do
		local a, b = doorX - DOOR_W / 2, doorX + DOOR_W / 2
		seg(cursor, a)
		put(
			model,
			string.format("%sLintel%02d", name, i),
			Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
			at(plotCFrame, doorX, floorY + (DOOR_H + h) / 2, z),
			wallOpts()
		)
		cursor = b
	end
	seg(cursor, x1)
end

function hall.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	local skin = SkinConfig.get(FACILITY_ID, skinIndex)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)
	model:SetAttribute(Keys.ATTR_SKIN, skinIndex)

	local cx, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local h = row.size.Y

	-- 바닥판 + 줄무늬. 줄무늬 윗면이 바닥판보다 0.03 높아 면이 겹치지 않는다
	local floor = put(
		model,
		"Floor",
		Vector3.new(row.size.X - FLOOR_INSET * 2, FLOOR_T, row.size.Z - FLOOR_INSET * 2),
		at(plotCFrame, cx, floorY + FLOOR_T / 2, cz),
		{
			color = skin.primary,
			material = skin.material,
		}
	)
	floor:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_PRIMARY)
	local stripe = put(
		model,
		"Stripe",
		Vector3.new(row.size.X - FLOOR_INSET * 4, FLOOR_T + 0.06, STRIPE_W), -- 양끝이 바닥 끝면과 겹치지 않게 더 들인다
		at(plotCFrame, cx, floorY + FLOOR_T / 2, cz),
		{
			color = skin.secondary,
			material = skin.material,
		}
	)
	stripe:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_SECONDARY)

	-- 북벽(뒷줄 방 남문) · 남벽(앞줄 방 북문 + 현관 북문)
	local northDoors = { CLASS1_DOOR_X }
	for _, id in NORTH_ROOMS do
		table.insert(northDoors, FacilityConfig.BY_ID[id].center.X)
	end
	local southDoors = { ENTRANCE_DOOR_X }
	for _, id in SOUTH_ROOMS do
		table.insert(southDoors, FacilityConfig.BY_ID[id].center.X)
	end
	wallRow(model, plotCFrame, "WallN", cz - hz + WALL_T / 2, cx - hx, cx + hx, floorY, h, northDoors)
	wallRow(model, plotCFrame, "WallS", cz + hz - WALL_T / 2, cx - hx, cx + hx, floorY, h, southDoors)

	-- 양 끝벽: 북·남벽 사이만 채운다(모서리 겹침 없음)
	local endLen = row.size.Z - WALL_T * 2
	put(
		model,
		"WallW",
		Vector3.new(WALL_T, h, endLen),
		at(plotCFrame, cx - hx + WALL_T / 2, floorY + h / 2, cz),
		wallOpts()
	)
	put(
		model,
		"WallE",
		Vector3.new(WALL_T, h, endLen),
		at(plotCFrame, cx + hx - WALL_T / 2, floorY + h / 2, cz),
		wallOpts()
	)

	-- 지붕은 벽 안쪽만 덮는다. 벽 위까지 덮으면 벽 윗면·바깥면과 겹쳐 깜빡인다(z-fighting)
	local roofSize = Vector3.new(row.size.X - WALL_T * 2, ROOF_T, row.size.Z - WALL_T * 2)
	put(model, "Roof", roofSize, at(plotCFrame, cx, floorY + h - ROOF_T / 2, cz), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = true,
	})

	-- 팻말 자리: 현관 북문 옆, 복도 안쪽(남벽 안쪽 면에서 0.5)
	attach(
		model,
		Keys.SKIN_SIGN,
		at(plotCFrame, ENTRANCE_DOOR_X + DOOR_W / 2 + 1.5, floorY + SIGN_EYE, cz + hz - WALL_T - 0.5)
	)

	return model
end

return hall
