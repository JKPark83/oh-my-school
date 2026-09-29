--!strict
--[[
	음악실(시설 10) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 21개(≤25), 전부 BuildKit.part.
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  방 30×25: 벽(북벽은 문 폭 8 을 비운 두 조각 + 상인방)·지붕은 fade. 바닥은 Shell 바닥 위 얇은 판이라
	  방 바닥 높이 = center.Y + FLOOR_T 이고 좌석·문 Attachment 는 그 높이에 둔다.
	  Seats/S01 = 피아노 의자(피아노 앞, 북쪽 -Z 를 본다), S02 = 피아노 옆 의자(북쪽을 본다).
	  Door = 북문 중심 바닥(LookVector 가 방 안쪽 +Z). SkinSign = 문 옆 복도 쪽 눈높이.
	  세 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
	  스킨: SkinRole "primary" = 피아노 몸통, "secondary" = 피아노 의자 · 큰북.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local music = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8
local SIGN_EYE = 4.5
local SIT_HIP = CharacterBuilder.SIT_HIP

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_FLOOR = Color3.fromRGB(196, 168, 130)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_WHITE = Color3.fromRGB(245, 245, 245)
local COLOR_DARK = Color3.fromRGB(40, 40, 44)
local COLOR_WOOD = Color3.fromRGB(150, 110, 70)
local COLOR_NOTE = Color3.fromRGB(70, 60, 90)

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
		{ color = COLOR_FLOOR, material = Enum.Material.WoodPlanks }
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

--- 의자 3파트: 앉는 면(윗면 = 바닥 + SIT_HIP) · 등받이 · 기둥. yaw 가 얼굴 방향, 등받이는 그 반대편.
local function buildChair(
	parent: Instance,
	name: string,
	plotCFrame: CFrame,
	x: number,
	floorTop: number,
	z: number,
	yaw: number,
	color: Color3,
	material: Enum.Material
)
	local base = at(plotCFrame, x, floorTop, z, CFrame.Angles(0, yaw, 0))
	part(parent, name .. "Seat", Vector3.new(1.8, 0.4, 1.8), base * CFrame.new(0, SIT_HIP - 0.2, 0), {
		color = color,
		material = material,
	})
	part(parent, name .. "Back", Vector3.new(1.8, 1.8, 0.3), base * CFrame.new(0, SIT_HIP + 0.9, 0.75), {
		color = color,
		material = material,
	})
	part(parent, name .. "Post", Vector3.new(0.6, SIT_HIP - 0.4, 0.6), base * CFrame.new(0, (SIT_HIP - 0.4) / 2, 0), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
end

function music.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local skin = SkinConfig.get(row.id, skinIndex)
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + FLOOR_T
	local northZ = cz - row.size.Z / 2 + WALL_T / 2
	local southZ = cz + row.size.Z / 2 - WALL_T

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local floor, lintel = buildRoom(model, plotCFrame, row)
	model.PrimaryPart = floor
	BuildKit.surfaceText(lintel, Enum.NormalId.Front, row.name, COLOR_LABEL, 1.3)

	-- 업라이트 피아노(primary): 서쪽. 건반은 몸통 남쪽 면에서 앞으로 나온다
	local px, pz = cx - 6, cz - 3.5
	local body = part(model, "PianoBody", Vector3.new(6, 4.6, 2), at(plotCFrame, px, floorTop + 2.3, pz), {
		color = skin.primary,
		material = skin.material,
	})
	body:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_PRIMARY)
	part(model, "PianoKeys", Vector3.new(5.6, 0.3, 1.2), at(plotCFrame, px, floorTop + 2.6, pz + 1.55), {
		color = COLOR_WHITE,
	})
	part(model, "PianoBlackKeys", Vector3.new(5.4, 0.12, 0.5), at(plotCFrame, px, floorTop + 2.8, pz + 1.25), {
		color = COLOR_DARK,
		collide = false,
		cast = false,
	})

	-- 피아노 의자(secondary) S01: 건반 앞에서 북쪽(피아노)을 본다
	local bz = pz + 3.4
	local benchSeat =
		part(model, "PianoBenchSeat", Vector3.new(3, 0.4, 1.4), at(plotCFrame, px, floorTop + SIT_HIP - 0.2, bz), {
			color = skin.secondary,
			material = skin.material,
		})
	benchSeat:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_SECONDARY)
	part(
		model,
		"PianoBenchBase",
		Vector3.new(2.6, SIT_HIP - 0.4, 1),
		at(plotCFrame, px, floorTop + (SIT_HIP - 0.4) / 2, bz),
		{
			color = COLOR_WOOD,
			material = Enum.Material.Wood,
		}
	)
	attachment(seats, seatName(1), at(plotCFrame, px, floorTop, bz))

	-- 의자 S02: 피아노 옆(동쪽), 보면대를 향해 북쪽을 본다
	local chairX, chairZ = cx + 5, cz - 1
	buildChair(model, "Chair", plotCFrame, chairX, floorTop, chairZ, 0, COLOR_WOOD, Enum.Material.Wood)
	attachment(seats, seatName(2), at(plotCFrame, chairX, floorTop, chairZ))

	-- 보면대: 의자 앞
	part(model, "StandPost", Vector3.new(0.2, 3.6, 0.2), at(plotCFrame, chairX, floorTop + 1.8, chairZ - 3), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
		collide = false,
	})
	part(
		model,
		"StandBoard",
		Vector3.new(2, 1.6, 0.1),
		at(plotCFrame, chairX, floorTop + 4, chairZ - 3.2, CFrame.Angles(-0.4, 0, 0)),
		{ color = COLOR_DARK, collide = false }
	)

	-- 큰북(secondary): 동쪽 구석. 스피커: 남서쪽
	local drum = part(
		model,
		"Drum",
		Vector3.new(2.4, 3.2, 3.2),
		at(plotCFrame, cx + 8, floorTop + 1.2, cz - 6, CFrame.Angles(0, 0, math.pi / 2)),
		{ color = skin.secondary, material = skin.material, shape = Enum.PartType.Cylinder }
	)
	drum:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_SECONDARY)
	part(model, "Speaker", Vector3.new(2, 4, 2), at(plotCFrame, cx - 9, floorTop + 2, cz + 6), { color = COLOR_DARK })

	-- 남쪽 벽 안쪽 면 음표 장식(파트 없이 글자)
	local banner = part(model, "NoteBanner", Vector3.new(10, 4, 0.1), at(plotCFrame, cx, floorTop + 7, southZ - 0.05), {
		color = COLOR_WHITE,
		collide = false,
		cast = false,
	})
	BuildKit.surfaceText(banner, Enum.NormalId.Front, "♪ ♫ ♪", COLOR_NOTE, 2)

	-- 문과 팻말
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, northZ, CFrame.Angles(0, math.pi, 0)))
	attachment(model, Keys.SKIN_SIGN, at(plotCFrame, cx + 6, floorTop + SIGN_EYE, northZ - 1.2))

	return model
end

return music
