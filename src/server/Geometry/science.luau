--!strict
--[[
	과학실(시설 9) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 23개(≤25), 전부 BuildKit.part.
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  방 30×25: 벽(북벽은 문 폭 8 을 비운 두 조각 + 상인방)·지붕은 fade. 바닥은 Shell 바닥 위 얇은 판이라
	  방 바닥 높이 = center.Y + FLOOR_T 이고 좌석·문 Attachment 는 그 높이에 둔다.
	  Seats/S01·S02 = 실험대 앞 스툴 둘(북쪽 -Z 를 본다). Attachment 위치 = 스툴 아래 바닥 중심.
	  Door = 북문 중심 바닥(LookVector 가 방 안쪽 +Z). SkinSign = 문 옆 복도 쪽 눈높이.
	  세 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
	  스킨: SkinRole "primary" = 실험대 상판 둘, "secondary" = 실험대 몸통 둘.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local science = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8
local SIGN_EYE = 4.5
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_FLOOR = Color3.fromRGB(206, 208, 206)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_DARK = Color3.fromRGB(60, 60, 64)
local COLOR_GLASS = Color3.fromRGB(210, 230, 240)
local COLOR_LIQUID = Color3.fromRGB(80, 200, 120)
local COLOR_PAPER = Color3.fromRGB(250, 248, 236)
local COLOR_WOOD = Color3.fromRGB(150, 110, 70)

local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

local function attachment(parent: Instance, name: string, cf: CFrame): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

local function seatName(index: number): string
	return string.format("S%02d", index)
end

local function wallOpts(): BuildKit.Opts
	return { color = COLOR_WALL, material = Enum.Material.Concrete, fade = true }
end

--- 벽 4(북벽은 문 양옆 두 조각 + 상인방) · 지붕 · 바닥 = 파트 8개. 바닥과 상인방을 돌려준다.
local function buildRoom(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility): (Part, Part)
	local cx, cz = row.center.X, row.center.Z
	local w, d = row.size.X, row.size.Z
	-- 벽 윗면을 부지 y+size.Y 에 맞춘다. 바닥 판 두께만큼 더 올리면 위에 얹히는 강당 바닥 윗면과 같은 평면이 되어 깜빡인다
	local h = row.size.Y - FLOOR_T
	local floorTop = row.center.Y + FLOOR_T
	local wallY = floorTop + h / 2
	local northZ = cz - d / 2 + WALL_T / 2
	local segW = (w - DOOR_W) / 2

	local floor = part(
		model,
		"Floor",
		Vector3.new(w, FLOOR_T, d),
		at(plotCFrame, cx, row.center.Y + FLOOR_T / 2, cz),
		{ color = COLOR_FLOOR }
	)
	part(
		model,
		"WallNW",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx - (DOOR_W + segW) / 2, wallY, northZ),
		wallOpts()
	)
	part(
		model,
		"WallNE",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx + (DOOR_W + segW) / 2, wallY, northZ),
		wallOpts()
	)
	local lintel = part(
		model,
		"Lintel",
		Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
		at(plotCFrame, cx, floorTop + DOOR_H + (h - DOOR_H) / 2, northZ),
		wallOpts()
	)
	part(model, "WallS", Vector3.new(w, h, WALL_T), at(plotCFrame, cx, wallY, cz + d / 2 - WALL_T / 2), wallOpts())
	part(
		model,
		"WallE",
		Vector3.new(WALL_T, h, d - 2 * WALL_T),
		at(plotCFrame, cx + w / 2 - WALL_T / 2, wallY, cz),
		wallOpts()
	)
	part(
		model,
		"WallW",
		Vector3.new(WALL_T, h, d - 2 * WALL_T),
		at(plotCFrame, cx - w / 2 + WALL_T / 2, wallY, cz),
		wallOpts()
	)
	part(
		model,
		"Roof",
		-- 벽 안쪽만 덮는다. 벽 위에 얹으면 강당 바닥을 뚫고 올라온다
		Vector3.new(w - WALL_T * 2, ROOF_T, d - WALL_T * 2),
		at(plotCFrame, cx, floorTop + h - ROOF_T / 2, cz),
		{ color = COLOR_ROOF, material = Enum.Material.Slate, fade = true, light = true }
	)
	return floor, lintel
end

--- 실험대(상판 primary + 몸통 secondary) 와 그 남쪽의 스툴(원판 + 기둥). 좌석 Attachment 위치를 돌려준다.
local function buildBench(
	model: Model,
	plotCFrame: CFrame,
	suffix: string,
	x: number,
	floorTop: number,
	z: number,
	skin: SkinConfig.Skin
): CFrame
	local top =
		part(model, "BenchTop" .. suffix, Vector3.new(8, 0.5, 3), at(plotCFrame, x, floorTop + SIT_DESK - 0.25, z), {
			color = skin.primary,
			material = skin.material,
		})
	top:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_PRIMARY)
	local base = part(
		model,
		"BenchBase" .. suffix,
		Vector3.new(7.4, SIT_DESK - 0.5, 2.6),
		at(plotCFrame, x, floorTop + (SIT_DESK - 0.5) / 2, z),
		{ color = skin.secondary, material = skin.material }
	)
	base:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_SECONDARY)

	-- 스툴: 실험대 남쪽, 북쪽(-Z)을 보고 앉는다
	local sz = z + 2.9
	part(
		model,
		"Stool" .. suffix,
		Vector3.new(0.3, 1.6, 1.6),
		at(plotCFrame, x, floorTop + SIT_HIP - 0.15, sz, CFrame.Angles(0, 0, math.pi / 2)),
		{ color = COLOR_DARK, shape = Enum.PartType.Cylinder }
	)
	part(
		model,
		"StoolPost" .. suffix,
		Vector3.new(0.4, SIT_HIP - 0.3, 0.4),
		at(plotCFrame, x, floorTop + (SIT_HIP - 0.3) / 2, sz),
		{
			color = COLOR_STEEL,
			material = Enum.Material.Metal,
		}
	)
	return at(plotCFrame, x, floorTop, sz)
end

function science.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local skin = SkinConfig.get(row.id, skinIndex)
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + FLOOR_T
	local northZ = cz - row.size.Z / 2 + WALL_T / 2
	local southZ = cz + row.size.Z / 2 - WALL_T -- 남쪽 벽 안쪽 면
	local westX = cx - row.size.X / 2 + WALL_T

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local floor, lintel = buildRoom(model, plotCFrame, row)
	model.PrimaryPart = floor
	BuildKit.surfaceText(lintel, Enum.NormalId.Front, row.name, COLOR_LABEL, 1.3)

	-- 실험대 둘 + 스툴 둘(S01 서쪽, S02 동쪽)
	local benchZ = cz - 2
	attachment(seats, seatName(1), buildBench(model, plotCFrame, "W", cx - 6, floorTop, benchZ, skin))
	attachment(seats, seatName(2), buildBench(model, plotCFrame, "E", cx + 6, floorTop, benchZ, skin))

	-- 서쪽 실험대 위 플라스크(원뿔 대신 구 + 목) 와 동쪽 실험대 위 비커
	local topY = floorTop + SIT_DESK
	part(model, "Flask", Vector3.new(1.2, 1.2, 1.2), at(plotCFrame, cx - 8, topY + 0.6, benchZ), {
		color = COLOR_GLASS,
		material = Enum.Material.Glass,
		transparency = 0.4,
		shape = Enum.PartType.Ball,
		collide = false,
	})
	part(model, "FlaskNeck", Vector3.new(0.4, 0.8, 0.4), at(plotCFrame, cx - 8, topY + 1.5, benchZ), {
		color = COLOR_GLASS,
		material = Enum.Material.Glass,
		transparency = 0.4,
		collide = false,
	})
	part(model, "Beaker", Vector3.new(1, 1.2, 1), at(plotCFrame, cx + 8, topY + 0.6, benchZ), {
		color = COLOR_LIQUID,
		material = Enum.Material.Glass,
		transparency = 0.3,
		collide = false,
	})

	-- 개수대: 남쪽 벽 앞
	part(model, "SinkBase", Vector3.new(4, 2.6, 2), at(plotCFrame, cx + 6, floorTop + 1.3, southZ - 1), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
	part(model, "SinkTap", Vector3.new(0.3, 1.2, 0.3), at(plotCFrame, cx + 6, floorTop + 3.2, southZ - 0.4), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
		collide = false,
	})

	-- 시약 선반: 서쪽 벽. 주기율표 포스터: 남쪽 벽
	part(
		model,
		"Shelf",
		Vector3.new(0.6, 5, 6),
		at(plotCFrame, westX + 0.3, floorTop + 5, cz),
		{ color = COLOR_WOOD, material = Enum.Material.Wood }
	)
	local poster =
		part(model, "Poster", Vector3.new(8, 5, 0.1), at(plotCFrame, cx - 5, floorTop + 6.5, southZ - 0.05), {
			color = COLOR_PAPER,
			collide = false,
			cast = false,
		})
	BuildKit.surfaceText(poster, Enum.NormalId.Front, "원소 주기율표", COLOR_LABEL, 1.2)

	-- 문과 팻말
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, northZ, CFrame.Angles(0, math.pi, 0)))
	attachment(model, Keys.SKIN_SIGN, at(plotCFrame, cx + 6, floorTop + SIGN_EYE, northZ - 1.2))

	return model
end

return science
