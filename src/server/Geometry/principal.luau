--!strict
--[[
	교장실(시설 11) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 22개(≤25).
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  방 30×25: 벽(북벽은 문 폭 8 을 비운 두 조각 + 상인방)·지붕은 fade. 바닥은 Shell 바닥 위 얇은 판이라
	  방 바닥 높이 = center.Y + FLOOR_T 이고 좌석·문 Attachment 는 그 높이에 둔다.
	  PrincipalChair = 진짜 Roblox Seat(부지 로컬 (60, -10), 앉는 면 = 바닥 + SIT_HIP, 남쪽 +Z 를 본다).
	    Anchored · CanCollide · Disabled=false. 미션 "교장 의자에 앉기" 가 이름으로 찾는다(Keys.PRINCIPAL_CHAIR).
	    BuildKit.part 는 Part 만 만들므로 이 하나만 Instance.new("Seat") 로 같은 속성을 준다.
	  Seats/S01 = 손님 의자(부지 로컬 (50, -2.5), 교장 의자를 바라본다).
	  Door = 북문 중심 바닥(LookVector 가 방 안쪽 +Z).
	  두 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local principal = {}

local COLOR_PRIMARY = Color3.fromRGB(110, 70, 40)
local COLOR_SECONDARY = Color3.fromRGB(60, 40, 25)
local MATERIAL = Enum.Material.Wood

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

-- 계획서 §3.6 고정 좌표(부지 로컬)
local CHAIR_X, CHAIR_Z = 60, -10
local GUEST_X, GUEST_Z = 50, -2.5

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_FLOOR = Color3.fromRGB(120, 60, 50)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_WOOD = Color3.fromRGB(110, 75, 45)
local COLOR_LEATHER = Color3.fromRGB(70, 50, 40)
local COLOR_POT = Color3.fromRGB(170, 110, 80)
local COLOR_LEAF = Color3.fromRGB(70, 140, 70)
local COLOR_GOLD = Color3.fromRGB(230, 190, 60)
local COLOR_PLAQUE = Color3.fromRGB(240, 236, 220)

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
		{ color = COLOR_FLOOR, material = Enum.Material.Fabric }
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

--- 의자 3파트: 앉는 면(윗면 = 바닥 + SIT_HIP) · 등받이 · 기둥. base 의 LookVector 가 얼굴 방향, 등받이는 그 반대편.
local function buildChair(parent: Instance, name: string, base: CFrame, color: Color3, material: Enum.Material)
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

--- 교장 의자: 진짜 Seat + 등받이 + 기둥. base = 바닥 중심, LookVector = 앉은 사람이 보는 방향(남쪽).
local function buildPrincipalChair(parent: Instance, base: CFrame)
	local seat = Instance.new("Seat")
	seat.Name = Keys.PRINCIPAL_CHAIR
	seat.Size = Vector3.new(2.6, 0.5, 2.6)
	seat.CFrame = base * CFrame.new(0, SIT_HIP - 0.25, 0)
	seat.Color = COLOR_SECONDARY
	seat.Material = MATERIAL
	seat.Anchored = true
	seat.CanCollide = true
	seat.Disabled = false
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = parent

	part(parent, "PrincipalChairBack", Vector3.new(2.6, 3.2, 0.5), base * CFrame.new(0, SIT_HIP + 1.6, 1.55), {
		color = COLOR_SECONDARY,
		material = MATERIAL,
	})
	part(
		parent,
		"PrincipalChairPost",
		Vector3.new(0.8, SIT_HIP - 0.5, 0.8),
		base * CFrame.new(0, (SIT_HIP - 0.5) / 2, 0),
		{
			color = COLOR_STEEL,
			material = Enum.Material.Metal,
		}
	)
end

function principal.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + FLOOR_T
	local northZ = cz - row.size.Z / 2 + WALL_T / 2
	local southZ = cz + row.size.Z / 2 - WALL_T
	local eastX = cx + row.size.X / 2 - WALL_T

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local floor, lintel = buildRoom(model, plotCFrame, row)
	model.PrimaryPart = floor
	BuildKit.surfaceText(lintel, Enum.NormalId.Front, row.name, COLOR_LABEL, 1.3)

	-- 교장 의자(남쪽을 본다) 와 그 앞의 큰 책상(primary)
	buildPrincipalChair(model, at(plotCFrame, CHAIR_X, floorTop, CHAIR_Z, CFrame.Angles(0, math.pi, 0)))
	local deskZ = CHAIR_Z + 3.8
	part(model, "DeskTop", Vector3.new(9, 0.5, 3.6), at(plotCFrame, CHAIR_X, floorTop + SIT_DESK - 0.25, deskZ), {
		color = COLOR_PRIMARY,
		material = MATERIAL,
	})
	for _, side in { { name = "W", dx = -3.4 }, { name = "E", dx = 3.4 } } do
		part(
			model,
			"DeskCabinet" .. side.name,
			Vector3.new(2, SIT_DESK - 0.5, 3.2),
			at(plotCFrame, CHAIR_X + side.dx, floorTop + (SIT_DESK - 0.5) / 2, deskZ),
			{ color = COLOR_PRIMARY, material = MATERIAL }
		)
	end

	-- 손님 의자 S01: 교장 의자 쪽을 바라본다
	local guestCF = CFrame.lookAt(
		at(plotCFrame, GUEST_X, floorTop, GUEST_Z).Position,
		at(plotCFrame, CHAIR_X, floorTop, CHAIR_Z).Position
	)
	buildChair(model, "GuestChair", guestCF, COLOR_LEATHER, Enum.Material.Leather)
	attachment(seats, seatName(1), guestCF)

	-- 책장(동쪽 벽) · 화분 · 트로피 · 남쪽 벽 액자
	part(model, "Bookshelf", Vector3.new(1, 8, 8), at(plotCFrame, eastX - 0.5, floorTop + 4, cz + 2), {
		color = COLOR_WOOD,
		material = Enum.Material.Wood,
	})
	part(
		model,
		"PlantPot",
		Vector3.new(1.6, 1.4, 1.6),
		at(plotCFrame, cx - 9, floorTop + 0.7, cz - 7),
		{ color = COLOR_POT }
	)
	part(model, "PlantLeaves", Vector3.new(2.6, 2.6, 2.6), at(plotCFrame, cx - 9, floorTop + 2.7, cz - 7), {
		color = COLOR_LEAF,
		material = Enum.Material.Grass,
		shape = Enum.PartType.Ball,
		collide = false,
	})
	part(
		model,
		"Trophy",
		Vector3.new(0.8, 1.4, 0.8),
		at(plotCFrame, CHAIR_X + 3.4, floorTop + SIT_DESK + 0.7, deskZ - 0.8),
		{
			color = COLOR_GOLD,
			material = Enum.Material.Metal,
			collide = false,
		}
	)
	local plaque = part(model, "Plaque", Vector3.new(7, 3, 0.1), at(plotCFrame, cx, floorTop + 7.5, southZ - 0.05), {
		color = COLOR_PLAQUE,
		collide = false,
		cast = false,
	})
	BuildKit.surfaceText(plaque, Enum.NormalId.Front, "교훈: 바르게 슬기롭게", COLOR_LABEL, 1.1)

	-- 문
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, northZ, CFrame.Angles(0, math.pi, 0)))

	return model
end

return principal
