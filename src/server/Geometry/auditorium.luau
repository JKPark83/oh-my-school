--!strict
--[[
	강당(시설 14, 2층) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 26개(바닥을 계단 구멍 때문에 3조각으로 나눠 한도 25 를 1 넘김), 전부 BuildKit.part.
	  치수·위치는 FacilityConfig 행(center (0,18,-17.5) / size 50×18×35, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  바닥 판은 y=18 위에 얹히므로 방 바닥 높이 = 18 + FLOOR_T. 벽·지붕은 fade. 문은 남쪽(+Z) 폭 8 → 층계참 쪽.
	  무대는 북쪽 끝(부지 로컬 z -32.5 근처). 무대 위 Part "GraduationBell"(금색 공) 을 HUD 가 이름으로 찾는다.
	  좌석 S01…S25: 5줄 × 5 열, 모두 무대(-Z) 를 본다. 파트 25개 한도 때문에 의자 대신 줄마다 긴 벤치 하나(5개) 를 두고
	  Attachment 만 25개 둔다. Attachment 위치 = 벤치 아래 바닥 중심(방 바닥 높이). 벤치는 층계참(x 5~14, z -16.5~-10.5 부근) 을
	  피해 서쪽에 몰아 놓았다.
	  Door = 남문 중심 바닥(LookVector 가 안쪽 -Z).
	  Attachment 들은 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)

local auditorium = {}

local COLOR_PRIMARY = Color3.fromRGB(170, 30, 40)
local COLOR_SECONDARY = Color3.fromRGB(120, 20, 30)
local MATERIAL = Enum.Material.Fabric

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = PlotLayout.AUDITORIUM_FLOOR_T
local DOOR_W = 8
local DOOR_H = 8
local SEAT_H = 1.55 -- 벤치 윗면 = CharacterBuilder.SIT_HIP 와 같은 값. 학생 NPC 가 앉는 높이

local STAGE_Z = -32.5 -- 계획서 §3.6: 단상 (0, -32.5)
local STAGE_H = 1.2
local STAGE_W, STAGE_D = 30, 6
local BELL_R = 0.8

-- 좌석 격자(부지 로컬, PlotLayout). 5열 × 5줄 = S01…S25, index = (줄-1)*5 + 열
local SEAT_COLS = PlotLayout.AUDITORIUM_SEAT_COLS
local SEAT_ROWS = PlotLayout.AUDITORIUM_SEAT_ROWS
local BENCH_W = PlotLayout.AUDITORIUM_BENCH_W
local BENCH_D = PlotLayout.AUDITORIUM_BENCH_D

local COLOR_WALL = Color3.fromRGB(226, 220, 206)
local COLOR_ROOF = Color3.fromRGB(62, 64, 68)
local COLOR_FLOOR = Color3.fromRGB(120, 60, 50)
local COLOR_LABEL = Color3.fromRGB(44, 44, 48)
local COLOR_STAGE = Color3.fromRGB(140, 100, 60)
local COLOR_BENCH = Color3.fromRGB(110, 75, 45)
local COLOR_STEEL = Color3.fromRGB(190, 192, 198)
local COLOR_GOLD = Color3.fromRGB(230, 190, 60)
local COLOR_BANNER = Color3.fromRGB(250, 246, 230)

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

--- 바닥 · 벽 4(남벽은 문 양옆 두 조각 + 상인방) · 지붕 = 파트 8개. 바닥과 상인방을 돌려준다.
local function buildRoom(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility): (Part, Part)
	local cx, cz = row.center.X, row.center.Z
	local w, h, d = row.size.X, row.size.Y, row.size.Z
	local floorTop = row.center.Y + FLOOR_T
	local wallY = floorTop + h / 2
	local southZ = cz + d / 2 - WALL_T / 2
	local segW = (w - DOOR_W) / 2

	-- 바닥은 세 조각. PlotShell 의 계단(x 5~14, z 6→-10.5)이 올라오는 남동쪽 x 5~14·z -10.5~0 을 비워 둔다.
	-- 벽·지붕처럼 fade: 1층에서 카메라와 캐릭터 사이를 가리면 흐려진다(§3.6 #3)
	local floorY = row.center.Y + FLOOR_T / 2
	local floorOpts = { color = COLOR_FLOOR, material = Enum.Material.Fabric, fade = true }
	local x0, x1 = cx - w / 2, cx + w / 2
	local z0, z1 = cz - d / 2, cz + d / 2
	local holeX0, holeX1, holeZ0 = PlotLayout.STAIR_X0, PlotLayout.STAIR_X1, PlotLayout.STAIRWELL_Z0
	local floor = part(
		model,
		"Floor",
		Vector3.new(holeX0 - x0, FLOOR_T, d),
		at(plotCFrame, (x0 + holeX0) / 2, floorY, cz),
		table.clone(floorOpts)
	)
	part(
		model,
		"FloorNE",
		Vector3.new(x1 - holeX0, FLOOR_T, holeZ0 - z0),
		at(plotCFrame, (holeX0 + x1) / 2, floorY, (z0 + holeZ0) / 2),
		table.clone(floorOpts)
	)
	part(
		model,
		"FloorSE",
		Vector3.new(x1 - holeX1, FLOOR_T, z1 - holeZ0),
		at(plotCFrame, (holeX1 + x1) / 2, floorY, (holeZ0 + z1) / 2),
		table.clone(floorOpts)
	)
	part(model, "WallN", Vector3.new(w, h, WALL_T), at(plotCFrame, cx, wallY, cz - d / 2 + WALL_T / 2), wallOpts())
	part(
		model,
		"WallSW",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx - (DOOR_W + segW) / 2, wallY, southZ),
		wallOpts()
	)
	part(
		model,
		"WallSE",
		Vector3.new(segW, h, WALL_T),
		at(plotCFrame, cx + (DOOR_W + segW) / 2, wallY, southZ),
		wallOpts()
	)
	local lintel = part(
		model,
		"Lintel",
		Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
		at(plotCFrame, cx, floorTop + DOOR_H + (h - DOOR_H) / 2, southZ),
		wallOpts()
	)
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
		Vector3.new(w, ROOF_T, d),
		at(plotCFrame, cx, floorTop + h + ROOF_T / 2, cz),
		{ color = COLOR_ROOF, material = Enum.Material.Slate, fade = true, light = true }
	)
	return floor, lintel
end

function auditorium.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local cx, cz = row.center.X, row.center.Z
	local h, d = row.size.Y, row.size.Z
	local floorTop = row.center.Y + FLOOR_T
	local ceiling = floorTop + h
	local southZ = cz + d / 2 - WALL_T / 2
	local stageTop = floorTop + STAGE_H

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local floor, lintel = buildRoom(model, plotCFrame, row)
	model.PrimaryPart = floor
	BuildKit.surfaceText(lintel, Enum.NormalId.Front, row.name, COLOR_LABEL, 1.3)

	-- 무대 + 앞 계단. 무대는 북쪽 벽 안쪽 면(z = cz - d/2 + 1)에 붙는다
	local stageZ = cz - d / 2 + WALL_T + STAGE_D / 2
	local stageFront = stageZ + STAGE_D / 2
	part(model, "Stage", Vector3.new(STAGE_W, STAGE_H, STAGE_D), at(plotCFrame, cx, floorTop + STAGE_H / 2, stageZ), {
		color = COLOR_STAGE,
		material = Enum.Material.WoodPlanks,
	})
	part(
		model,
		"StageStep",
		Vector3.new(8, STAGE_H / 2, 1.5),
		at(plotCFrame, cx, floorTop + STAGE_H / 4, stageFront + 0.75),
		{
			color = COLOR_STAGE,
			material = Enum.Material.WoodPlanks,
		}
	)

	-- 커튼: 뒤 막(secondary) · 좌우 커튼(primary) · 상단 발(primary, "졸업식" 글자)
	local curtainH = ceiling - stageTop
	local curtainY = stageTop + curtainH / 2
	part(
		model,
		"Backdrop",
		Vector3.new(STAGE_W, curtainH, 0.1),
		at(plotCFrame, cx, curtainY, cz - d / 2 + WALL_T + 0.05),
		{
			color = COLOR_SECONDARY,
			material = MATERIAL,
			collide = false,
		}
	)
	for _, side in { { name = "W", dx = -19 }, { name = "E", dx = 19 } } do
		part(
			model,
			"Curtain" .. side.name,
			Vector3.new(8, curtainH, 0.3),
			at(plotCFrame, cx + side.dx, curtainY, stageFront - 0.5),
			{
				color = COLOR_PRIMARY,
				material = MATERIAL,
				collide = false,
			}
		)
	end
	local valance = part(
		model,
		"Valance",
		Vector3.new(row.size.X - WALL_T * 2, 2, 0.3),
		at(plotCFrame, cx, ceiling - 1, stageFront - 0.5),
		{
			color = COLOR_PRIMARY,
			material = MATERIAL,
			collide = false,
		}
	)
	BuildKit.surfaceText(valance, Enum.NormalId.Back, "졸업식", COLOR_BANNER, 1.6)

	-- 졸업 종: 기둥 둘 + 가로대 + 금색 공. 무대 뒤쪽 가운데(§3.6 (0, -32.5))
	local bellZ = STAGE_Z
	local frameH = 5
	for _, side in { { name = "W", dx = -1.5 }, { name = "E", dx = 1.5 } } do
		part(
			model,
			"BellPost" .. side.name,
			Vector3.new(0.3, frameH, 0.3),
			at(plotCFrame, cx + side.dx, stageTop + frameH / 2, bellZ),
			{
				color = COLOR_STEEL,
				material = Enum.Material.Metal,
			}
		)
	end
	part(model, "BellBeam", Vector3.new(3.6, 0.3, 0.3), at(plotCFrame, cx, stageTop + frameH, bellZ), {
		color = COLOR_STEEL,
		material = Enum.Material.Metal,
	})
	part(
		model,
		Keys.GRADUATION_BELL,
		Vector3.new(BELL_R * 2, BELL_R * 2, BELL_R * 2),
		at(plotCFrame, cx, stageTop + frameH - 1.2, bellZ),
		{
			color = COLOR_GOLD,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Ball,
			collide = false,
		}
	)

	-- 연단: 무대 앞 오른쪽
	part(model, "Podium", Vector3.new(2, 3.2, 1.4), at(plotCFrame, cx + 7, stageTop + 1.6, stageFront - 1.5), {
		color = COLOR_BENCH,
		material = Enum.Material.Wood,
	})

	-- 벤치 5줄 + 좌석 Attachment 25개. 모두 무대(-Z) 를 본다
	local benchX = (SEAT_COLS[1] + SEAT_COLS[#SEAT_COLS]) / 2
	for r, rz in SEAT_ROWS do
		part(
			model,
			"Bench" .. r,
			Vector3.new(BENCH_W, SEAT_H, BENCH_D),
			at(plotCFrame, benchX, floorTop + SEAT_H / 2, rz),
			{
				color = COLOR_BENCH,
				material = Enum.Material.Wood,
			}
		)
		for c, sx in SEAT_COLS do
			attachment(seats, seatName((r - 1) * #SEAT_COLS + c), at(plotCFrame, sx, floorTop, rz))
		end
	end

	-- 문(남쪽, 층계참 쪽)
	attachment(model, Keys.DOOR, at(plotCFrame, cx, floorTop, southZ))

	return model
end

return auditorium
