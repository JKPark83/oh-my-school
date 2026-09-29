--!strict
--[[
	보건실(시설 8) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 23개(≤25), 전부 BuildKit.part.
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  방 30×25: 벽(북벽은 문 폭 8 을 비운 두 조각 + 상인방)·지붕은 fade. 바닥은 Shell 바닥 위에 얹는 얇은 판이라
	  방 바닥 높이 = center.Y + FLOOR_T 이고 좌석·문 Attachment 는 그 높이에 둔다.
	  Seats/S01 = 침대 옆 의자. Attachment 위치 = 의자 아래 바닥 중심, LookVector = 학생이 보는 방향(침대 쪽 -X).
	  Door = 북문 중심 바닥(LookVector 가 방 안쪽 +Z). SkinSign = 문 옆 복도 쪽 눈높이.
	  세 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
	  스킨: SkinRole "primary" = 커튼, "secondary" = 이불. 색과 재질 모두 스킨 것을 쓴다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local nurse = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local WALL_T = 1 -- 벽 두께
local ROOF_T = 1
local FLOOR_T = 0.2 -- Shell 바닥 위에 얹는 방 바닥 판 두께
local DOOR_W = 8
local DOOR_H = 8
local SIGN_EYE = 4.5 -- 페인트 롤러 팻말 눈높이
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_FLOOR = Color3.fromRGB(214, 214, 210)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_WHITE = Color3.fromRGB(245, 245, 245)
local COLOR_LIGHT = Color3.fromRGB(228, 228, 226)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_WOOD = Color3.fromRGB(150, 110, 70)
local COLOR_RED = Color3.fromRGB(200, 40, 40)

--- 부지 로컬 위치(+회전) → 월드 CFrame
local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

--- BuildKit.part 를 월드 CFrame 으로 부른다
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

--- 월드 CFrame 을 그대로 가진 Attachment(부모가 BasePart 가 아니다)
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

function nurse.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local skin = SkinConfig.get(row.id, skinIndex)
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + FLOOR_T
	local northZ = cz - row.size.Z / 2 + WALL_T / 2
	local eastX = cx + row.size.X / 2 - WALL_T -- 동쪽 벽 안쪽 면

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local floor, lintel = buildRoom(model, plotCFrame, row)
	model.PrimaryPart = floor
	BuildKit.surfaceText(lintel, Enum.NormalId.Front, row.name, COLOR_LABEL, 1.3)

	-- 침대: 서쪽 벽 쪽, 머리가 북쪽. 발치에 이불(secondary)
	local bx, bz = cx - 8, cz + 1.5
	part(model, "BedFrame", Vector3.new(3.2, 0.8, 6.6), at(plotCFrame, bx, floorTop + 0.4, bz), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
	part(model, "Mattress", Vector3.new(3, 0.5, 6.2), at(plotCFrame, bx, floorTop + 1.05, bz), { color = COLOR_WHITE })
	part(
		model,
		"Pillow",
		Vector3.new(2.4, 0.4, 1.2),
		at(plotCFrame, bx, floorTop + 1.5, bz - 2.3),
		{ color = COLOR_WHITE }
	)
	local blanket = part(model, "Blanket", Vector3.new(3.1, 0.25, 3.8), at(plotCFrame, bx, floorTop + 1.42, bz + 1.1), {
		color = skin.secondary,
		material = skin.material,
	})
	blanket:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_SECONDARY)

	-- 커튼(primary): 침대와 방 사이에 레일에서 늘어뜨린다
	local curtainX = cx - 2.4
	part(model, "CurtainRail", Vector3.new(0.2, 0.2, 8), at(plotCFrame, curtainX, floorTop + 8.6, bz), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
	local curtain = part(model, "Curtain", Vector3.new(0.3, 7, 7.6), at(plotCFrame, curtainX, floorTop + 5, bz), {
		color = skin.primary,
		material = skin.material,
		collide = false,
		cast = false,
	})
	curtain:SetAttribute(Keys.ATTR_SKIN_ROLE, ROLE_PRIMARY)

	-- 의자 S01: 침대 옆에서 침대(-X)를 본다
	local chairX, chairZ = cx - 4.6, cz + 3
	buildChair(model, "Chair", plotCFrame, chairX, floorTop, chairZ, math.pi / 2, COLOR_WOOD, Enum.Material.Wood)
	attachment(seats, seatName(1), at(plotCFrame, chairX, floorTop, chairZ, CFrame.Angles(0, math.pi / 2, 0)))

	-- 보건 선생님 책상: 동쪽, 문 옆
	local dx, dz = cx + 6, cz - 6
	part(model, "DeskTop", Vector3.new(5, 0.4, 2.4), at(plotCFrame, dx, floorTop + SIT_DESK - 0.2, dz), {
		color = COLOR_WHITE,
	})
	part(
		model,
		"DeskBase",
		Vector3.new(4.6, SIT_DESK - 0.4, 2),
		at(plotCFrame, dx, floorTop + (SIT_DESK - 0.4) / 2, dz),
		{
			color = COLOR_LIGHT,
		}
	)

	-- 약장 + 빨간 십자: 동쪽 벽
	part(
		model,
		"Cabinet",
		Vector3.new(0.6, 3, 3),
		at(plotCFrame, eastX - 0.3, floorTop + 6, cz),
		{ color = COLOR_WHITE }
	)
	part(model, "CrossH", Vector3.new(0.1, 0.5, 1.8), at(plotCFrame, eastX - 0.65, floorTop + 6, cz), {
		color = COLOR_RED,
		collide = false,
		cast = false,
	})
	part(model, "CrossV", Vector3.new(0.1, 1.8, 0.5), at(plotCFrame, eastX - 0.65, floorTop + 6, cz), {
		color = COLOR_RED,
		collide = false,
		cast = false,
	})

	-- 체중계
	part(model, "Scale", Vector3.new(1.6, 0.3, 1.6), at(plotCFrame, cx + 8, floorTop + 0.15, cz + 3), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})

	-- 문(복도 쪽 북벽) 과 팻말
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, northZ, CFrame.Angles(0, math.pi, 0)))
	attachment(model, Keys.SKIN_SIGN, at(plotCFrame, cx + 6, floorTop + SIGN_EYE, northZ - 1.2))

	return model
end

return nurse
