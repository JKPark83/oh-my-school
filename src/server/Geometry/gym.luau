--!strict
--[[
	체육관(시설 12) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 23개(≤25), 전부 BuildKit.part·wedge.
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  별동 30×45, 높이 20. 문은 서쪽(-X, 본관 쪽) 폭 8·높이 9: 서벽을 두 조각 + 상인방으로 비운다. 벽·지붕은 fade.
	  지붕은 아치(가운데 판 + 양옆 쐐기 = 3파트). 문 없는 북·남·동벽 바깥 면에 창 텍스처(PropAssets, id 0 이면 없음).
	  코트는 남북(Z) 방향이라 골대 둘이 북·남 끝에 선다. 좌석 없음(Seats 폴더는 비어 있다).
	  Door = 서문 중심 바닥(LookVector 가 안쪽 +X).
	  부품 4개(PartIndex): (1) 코트 바닥+벽 (2) 상인방(이름판)+지붕 (3) 코트 선·골대 둘 (4) 매트·뜀틀·공.
	  Door Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local gym = {}

local COLOR_PRIMARY = Color3.fromRGB(200, 160, 100)
local COLOR_SECONDARY = Color3.fromRGB(150, 110, 60)
local MATERIAL = Enum.Material.WoodPlanks

local WALL_T = 1
local ARCH_RISE = 4 -- 아치 지붕: 벽 윗면 → 가운데 판 윗면
local ARCH_SIDE = 0.25 -- 양옆 쐐기 폭 = 지붕 전체 폭 × 이 비율
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 9
local LINE_T = 0.06 -- 코트 선 두께(바닥 위에 얹는다)
local HOOP_H = 8 -- 림 높이

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_WHITE = Color3.fromRGB(245, 245, 245)
local COLOR_BOARD = Color3.fromRGB(235, 235, 235)
local COLOR_ORANGE = Color3.fromRGB(230, 120, 40)
local COLOR_BALL = Color3.fromRGB(200, 100, 40)
local COLOR_LEATHER = Color3.fromRGB(110, 75, 45)

local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

-- 지금 짓는 부품 번호. build 가 1 로 시작해 부품 경계마다 올린다
local partIndex = 1

--- BuildKit.part 를 월드 CFrame 으로 부르고 부품 번호(Keys.ATTR_PART_INDEX)를 붙인다
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	local p = BuildKit.part(parent, name, size, cf.Position, opts)
	p:SetAttribute(Keys.ATTR_PART_INDEX, partIndex)
	return p
end

local function attachment(parent: Instance, name: string, cf: CFrame): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

local function wallOpts(): BuildKit.Opts
	return { color = COLOR_WALL, material = Enum.Material.Plaster, fade = true }
end

--- 벽 4(서벽은 문 양옆 두 조각 + 상인방) · 아치 지붕 3 = 파트 9개. 상인방을 돌려준다.
local function buildShell(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility): Part
	local cx, cz = row.center.X, row.center.Z
	local w, h, d = row.size.X, row.size.Y, row.size.Z
	local floorTop = row.center.Y + FLOOR_T
	local wallY = floorTop + h / 2
	local westX = cx - w / 2 + WALL_T / 2
	local segD = (d - DOOR_W) / 2 - WALL_T -- 남북 벽이 모서리를 차지하므로 그만큼 짧다

	partIndex = 1 -- 벽
	local wallN =
		part(model, "WallN", Vector3.new(w, h, WALL_T), at(plotCFrame, cx, wallY, cz - d / 2 + WALL_T / 2), wallOpts())
	local wallS =
		part(model, "WallS", Vector3.new(w, h, WALL_T), at(plotCFrame, cx, wallY, cz + d / 2 - WALL_T / 2), wallOpts())
	local wallE = part(
		model,
		"WallE",
		Vector3.new(WALL_T, h, d - 2 * WALL_T),
		at(plotCFrame, cx + w / 2 - WALL_T / 2, wallY, cz),
		wallOpts()
	)
	part(
		model,
		"WallWN",
		Vector3.new(WALL_T, h, segD),
		at(plotCFrame, westX, wallY, cz - (DOOR_W + segD) / 2),
		wallOpts()
	)
	part(
		model,
		"WallWS",
		Vector3.new(WALL_T, h, segD),
		at(plotCFrame, westX, wallY, cz + (DOOR_W + segD) / 2),
		wallOpts()
	)
	-- 문 없는 세 벽 바깥 면에 창(§3.1 #8). id 0 이면 안 붙는다
	BuildKit.window(wallN, Enum.NormalId.Front)
	BuildKit.window(wallS, Enum.NormalId.Back)
	BuildKit.window(wallE, Enum.NormalId.Right)
	partIndex = 2 -- 상인방 + 지붕
	local lintel = part(
		model,
		"Lintel",
		Vector3.new(WALL_T, h - DOOR_H, DOOR_W),
		at(plotCFrame, westX, floorTop + DOOR_H + (h - DOOR_H) / 2, cz),
		wallOpts()
	)
	-- 아치 지붕(§3.1 #7) = 가운데 판 1 + 양옆 쐐기 2 의 3단. 용마루는 긴 변(Z) 방향, 처마 EAVE.
	-- 원통 1개를 반만 묻는 쪽이 파트는 적지만, 지름 31 의 아래 반쪽(15.5)이 높이 20 인 체육관 안으로 내려와 골대를 가린다.
	-- 판·쐐기 밑면이 모두 벽 윗면에 얹혀 방 안에서는 평평한 천장이다. 천장등은 가운데 판에만(조명 수 그대로)
	local eave = BuildKit.EAVE
	local span, length = w + eave * 2, d + eave * 2
	local top = floorTop + h
	local sideW = span * ARCH_SIDE
	local roofOpts = function(light: boolean): BuildKit.Opts
		return { color = COLOR_ROOF, material = Enum.Material.Slate, fade = true, light = light }
	end
	part(
		model,
		"Roof",
		Vector3.new(span - sideW * 2, ARCH_RISE, length),
		at(plotCFrame, cx, top + ARCH_RISE / 2, cz),
		roofOpts(true)
	)
	-- 쐐기의 높은 변(로컬 +Z)이 가운데를 보게 돌린다: 서쪽은 +X, 동쪽은 -X
	for _, side in { { name = "RoofW", dir = -1, yaw = math.pi / 2 }, { name = "RoofE", dir = 1, yaw = -math.pi / 2 } } do
		local x = cx + side.dir * (span / 2 - sideW / 2)
		local cf = at(plotCFrame, x, top + ARCH_RISE / 2, cz, CFrame.Angles(0, side.yaw, 0))
		local opts = roofOpts(false)
		opts.cframe = cf.Rotation
		local wedge = BuildKit.wedge(model, side.name, Vector3.new(length, ARCH_RISE, sideW), cf.Position, opts)
		wedge:SetAttribute(Keys.ATTR_PART_INDEX, partIndex)
	end
	return lintel
end

--- 골대 3파트: 기둥 · 백보드 · 림. dir = 코트 안쪽 방향(+1 남쪽, -1 북쪽)
local function buildHoop(
	model: Model,
	plotCFrame: CFrame,
	suffix: string,
	x: number,
	floorTop: number,
	z: number,
	dir: number
)
	part(
		model,
		"HoopPole" .. suffix,
		Vector3.new(0.5, HOOP_H + 2.5, 0.5),
		at(plotCFrame, x, floorTop + (HOOP_H + 2.5) / 2, z),
		{
			color = COLOR_STEEL,
			material = Enum.Material.Metal,
		}
	)
	part(
		model,
		"Backboard" .. suffix,
		Vector3.new(6, 4, 0.2),
		at(plotCFrame, x, floorTop + HOOP_H + 1, z + dir * 0.6),
		{
			color = COLOR_BOARD,
			transparency = 0.2,
		}
	)
	part(
		model,
		"Rim" .. suffix,
		Vector3.new(0.1, 1.8, 1.8),
		at(plotCFrame, x, floorTop + HOOP_H, z + dir * 1.6, CFrame.Angles(0, 0, math.pi / 2)),
		{ color = COLOR_ORANGE, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, collide = false }
	)
end

function gym.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local cx, cz = row.center.X, row.center.Z
	local w, d = row.size.X, row.size.Z
	local floorTop = row.center.Y + FLOOR_T
	local westX = cx - w / 2 + WALL_T / 2
	local lineY = floorTop + LINE_T / 2

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	-- 부품 1. 코트 바닥(primary)
	partIndex = 1
	local floor = part(model, "Floor", Vector3.new(w, FLOOR_T, d), at(plotCFrame, cx, row.center.Y + FLOOR_T / 2, cz), {
		color = COLOR_PRIMARY,
		material = MATERIAL,
	})
	model.PrimaryPart = floor

	local lintel = buildShell(model, plotCFrame, row)
	BuildKit.surfaceText(lintel, Enum.NormalId.Left, row.name, COLOR_LABEL, 1.3)

	-- 부품 3. 코트 선: 센터 라인 + 자유투 라인 둘
	partIndex = 3
	local lineOpts = function(): BuildKit.Opts
		return { color = COLOR_WHITE, collide = false, cast = false }
	end
	part(model, "CenterLine", Vector3.new(w - 2, LINE_T, 0.5), at(plotCFrame, cx, lineY, cz), lineOpts())
	part(model, "FreeThrowN", Vector3.new(8, LINE_T, 0.5), at(plotCFrame, cx, lineY, cz - 12.5), lineOpts())
	part(model, "FreeThrowS", Vector3.new(8, LINE_T, 0.5), at(plotCFrame, cx, lineY, cz + 12.5), lineOpts())

	-- 골대 둘: 북·남 끝
	buildHoop(model, plotCFrame, "N", cx, floorTop, cz - d / 2 + 2.5, 1)
	buildHoop(model, plotCFrame, "S", cx, floorTop, cz + d / 2 - 2.5, -1)

	-- 부품 4. 매트 둘(secondary) · 뜀틀 · 공: 동쪽 벽 쪽
	partIndex = 4
	for _, side in { { name = "N", dz = -15 }, { name = "S", dz = 15 } } do
		part(model, "Mat" .. side.name, Vector3.new(6, 0.3, 4), at(plotCFrame, cx + 7, floorTop + 0.15, cz + side.dz), {
			color = COLOR_SECONDARY,
			material = Enum.Material.Fabric,
		})
	end
	part(model, "VaultBox", Vector3.new(3, 3.5, 2), at(plotCFrame, cx + 7, floorTop + 1.75, cz), {
		color = COLOR_LEATHER,
		material = Enum.Material.Leather,
	})
	part(model, "Ball", Vector3.new(1.2, 1.2, 1.2), at(plotCFrame, cx - 6, floorTop + 0.6, cz + 4), {
		color = COLOR_BALL,
		shape = Enum.PartType.Ball,
	})

	-- 문(서쪽)
	attachment(model, Keys.DOOR, at(plotCFrame, westX, floorTop, cz, CFrame.Angles(0, -math.pi / 2, 0)))

	BuildKit.assertPartIndex(model, FacilityConfig.partCount(row.id))
	return model
end

return gym
