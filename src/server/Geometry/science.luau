--!strict
--[[
	과학실(시설 9) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 23개(≤25), 전부 BuildKit.part(의자 판은 BuildKit.seat).
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  방 30×25: 벽(북벽은 문 폭 8 을 비운 두 조각 + 상인방)·지붕은 fade. 바닥은 Shell 바닥 위 얇은 판이라
	  방 바닥 높이 = center.Y + FLOOR_T 이고 좌석·문 Attachment 는 그 높이에 둔다.
	  Seats/S01·S02 = 실험대 앞 스툴 둘(북쪽 -Z 를 본다). Attachment 위치 = 스툴 아래 바닥 중심.
	  Door = 북문 중심 바닥(LookVector 가 방 안쪽 +Z).
	  부품 4개(PartIndex): (1) 바닥+벽 (2) 상인방(이름판)+지붕 (3) 실험대·스툴 (4) 플라스크·비커·개수대·선반·포스터.
	  두 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)

local science = {}

local COLOR_PRIMARY = Color3.fromRGB(120, 125, 130)
-- 실험대 수납장. 수납장 그림(PropAssets.INTERIOR.CABINET)이 투명 덧그림이라 이 색이 문짝 색이 된다
local COLOR_SECONDARY = Color3.fromRGB(200, 214, 222)
local MATERIAL = Enum.Material.Metal

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8
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
local COLOR_WAINSCOT = Color3.fromRGB(150, 190, 170) -- 벽 아래 띠(연두 회색)

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

--- part 의 Seat 판. 학생 자리(seatIndex)는 Disabled 라 플레이어가 학생과 겹쳐 앉지 않는다
local function partSeat(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	opts: BuildKit.Opts,
	seatIndex: number
): Seat
	opts.cframe = cf.Rotation
	local p = BuildKit.seat(parent, name, size, cf.Position, opts, BuildKit.studentSeat(script.Name, seatIndex))
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

local function seatName(index: number): string
	return string.format("S%02d", index)
end

local function wallOpts(): BuildKit.Opts
	return { color = COLOR_WALL, material = Enum.Material.Plaster, fade = true }
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

	partIndex = 1 -- 바닥 + 벽
	local floor = part(
		model,
		"Floor",
		Vector3.new(w, FLOOR_T, d),
		at(plotCFrame, cx, row.center.Y + FLOOR_T / 2, cz),
		{ color = COLOR_FLOOR }
	)
	BuildKit.floorTile(floor)
	local wallNW = part(
		model,
		"WallNW",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx - (DOOR_W + segW) / 2, wallY, northZ),
		wallOpts()
	)
	local wallNE = part(
		model,
		"WallNE",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx + (DOOR_W + segW) / 2, wallY, northZ),
		wallOpts()
	)
	local wallS =
		part(model, "WallS", Vector3.new(w, h, WALL_T), at(plotCFrame, cx, wallY, cz + d / 2 - WALL_T / 2), wallOpts())
	local wallE = part(
		model,
		"WallE",
		Vector3.new(WALL_T, h, d - 2 * WALL_T),
		at(plotCFrame, cx + w / 2 - WALL_T / 2, wallY, cz),
		wallOpts()
	)
	local wallW = part(
		model,
		"WallW",
		Vector3.new(WALL_T, h, d - 2 * WALL_T),
		at(plotCFrame, cx - w / 2 + WALL_T / 2, wallY, cz),
		wallOpts()
	)
	-- 문 없는 바깥 벽 면에 창(§3.1 #8). id 0 이면 안 붙는다 — 동쪽은 현관, 서쪽은 보건실 벽과 맞닿아 남쪽만(맞닿은 면은 가려져 Texture 만 늘고, 페이드 때 벽 속에 비친다)
	BuildKit.window(wallS, Enum.NormalId.Back)
	-- 벽 안쪽 면 아래 띠. 북벽 −Z 는 문 쪽이라 안쪽 면이 Back
	BuildKit.wainscot(wallNW, Enum.NormalId.Back, COLOR_WAINSCOT)
	BuildKit.wainscot(wallNE, Enum.NormalId.Back, COLOR_WAINSCOT)
	BuildKit.wainscot(wallS, Enum.NormalId.Front, COLOR_WAINSCOT)
	BuildKit.wainscot(wallE, Enum.NormalId.Left, COLOR_WAINSCOT)
	BuildKit.wainscot(wallW, Enum.NormalId.Right, COLOR_WAINSCOT)
	partIndex = 2 -- 상인방 + 지붕
	local lintel = part(
		model,
		"Lintel",
		Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
		at(plotCFrame, cx, floorTop + DOOR_H + (h - DOOR_H) / 2, northZ),
		wallOpts()
	)
	part(
		model,
		"Roof",
		-- 벽 안쪽만 덮는다. 벽 위에 얹으면 강당 바닥을 뚫고 올라온다(그래서 박공도 못 얹는다. §3.1 #7)
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
	seatIndex: number
): CFrame
	part(model, "BenchTop" .. suffix, Vector3.new(8, 0.5, 3), at(plotCFrame, x, floorTop + SIT_DESK - 0.25, z), {
		color = COLOR_PRIMARY,
		material = MATERIAL,
	})
	local base = part(
		model,
		"BenchBase" .. suffix,
		Vector3.new(7.4, SIT_DESK - 0.5, 2.6),
		at(plotCFrame, x, floorTop + (SIT_DESK - 0.5) / 2, z),
		{ color = COLOR_SECONDARY, material = Enum.Material.SmoothPlastic }
	)
	BuildKit.decal(base, Enum.NormalId.Front, PropAssets.INTERIOR.CABINET)
	BuildKit.decal(base, Enum.NormalId.Back, PropAssets.INTERIOR.CABINET)

	-- 스툴: 실험대 남쪽, 북쪽(-Z)을 보고 앉는다
	local sz = z + 2.9
	partSeat(
		model,
		"Stool" .. suffix,
		Vector3.new(0.3, 1.6, 1.6),
		at(plotCFrame, x, floorTop + SIT_HIP - 0.15, sz, CFrame.Angles(0, 0, math.pi / 2)),
		{ color = COLOR_DARK, shape = Enum.PartType.Cylinder },
		seatIndex
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

function science.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
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

	-- 부품 3. 실험대 둘 + 스툴 둘(S01 서쪽, S02 동쪽)
	partIndex = 3
	local benchZ = cz - 2
	attachment(seats, seatName(1), buildBench(model, plotCFrame, "W", cx - 6, floorTop, benchZ, 1))
	attachment(seats, seatName(2), buildBench(model, plotCFrame, "E", cx + 6, floorTop, benchZ, 2))

	-- 부품 4. 서쪽 실험대 위 플라스크(원뿔 대신 구 + 목) 와 동쪽 실험대 위 비커
	partIndex = 4
	local topY = floorTop + SIT_DESK
	part(model, "Flask", Vector3.new(1.2, 1.2, 1.2), at(plotCFrame, cx - 8, topY + 0.6, benchZ), {
		color = COLOR_GLASS,
		material = Enum.Material.Glass,
		transparency = 0.4,
		shape = Enum.PartType.Ball,
	})
	part(model, "FlaskNeck", Vector3.new(0.4, 0.8, 0.4), at(plotCFrame, cx - 8, topY + 1.5, benchZ), {
		color = COLOR_GLASS,
		material = Enum.Material.Glass,
		transparency = 0.4,
	})
	part(model, "Beaker", Vector3.new(1, 1.2, 1), at(plotCFrame, cx + 8, topY + 0.6, benchZ), {
		color = COLOR_LIQUID,
		material = Enum.Material.Glass,
		transparency = 0.3,
	})

	-- 개수대: 남쪽 벽 앞
	part(model, "SinkBase", Vector3.new(4, 2.6, 2), at(plotCFrame, cx + 6, floorTop + 1.3, southZ - 1), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
	part(model, "SinkTap", Vector3.new(0.3, 1.2, 0.3), at(plotCFrame, cx + 6, floorTop + 3.2, southZ - 0.4), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})

	-- 시약 선반: 서쪽 벽. 주기율표 포스터: 남쪽 벽
	local shelf = part(
		model,
		"Shelf",
		Vector3.new(0.6, 5, 6),
		at(plotCFrame, westX + 0.3, floorTop + 5, cz),
		{ color = COLOR_WOOD, material = Enum.Material.Wood }
	)
	BuildKit.decal(shelf, Enum.NormalId.Right, PropAssets.INTERIOR.REAGENT_SHELF) -- 로컬 +X = 방 쪽
	local poster =
		part(model, "Poster", Vector3.new(8, 5, 0.1), at(plotCFrame, cx - 5, floorTop + 6.5, southZ - 0.05), {
			color = COLOR_PAPER,
			collide = false,
			cast = false,
		})
	-- 그림에 제목이 들어 있다. id 0 이면 글자만
	if not BuildKit.decal(poster, Enum.NormalId.Front, PropAssets.INTERIOR.POSTER_PERIODIC) then
		BuildKit.surfaceText(poster, Enum.NormalId.Front, "원소 주기율표", COLOR_LABEL, 1.2)
	end

	-- 문
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, northZ, CFrame.Angles(0, math.pi, 0)))

	BuildKit.assertPartIndex(model, FacilityConfig.partCount(row.id))
	return model
end

return science
