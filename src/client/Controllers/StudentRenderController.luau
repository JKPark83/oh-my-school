--!strict
--[[
	전학생 렌더. 기획서 §10.

	서버는 학생을 만들지 않는다. ReplicatedStorage.PlotState.PlotNN 의 Students/Facilities 어트리뷰트만
	바뀌고, 클라이언트가 그걸 읽어 Seats.occupants 로 자리를 정한 뒤 CharacterBuilder 로 앉힌다.
	모델은 Workspace.NpcRender.PlotNN 아래(클라이언트 전용), Humanoid 없이 Anchored 파트뿐이다.

	★ 예산(§10.3). 카메라에서 가까운 부지 4개(저사양 2개)만 그린다. 1초마다 거리를 다시 잰다.
	  학생은 60 스터드 안이면 매 틱, 60~120 은 4틱에 한 번, 120 밖은 멈추고 5초 지나면 지운다.
	  움직임은 workspace:BulkMoveTo 한 번(틱당 ≤300 CFrame)으로 끝낸다. 파트마다 CFrame 을 쓰지 않는다.

	★ 파트 CFrame 은 모델 피벗 기준 상대값을 한 번 구워 두고(rel), 매 틱 pivot * rel 만 계산한다.
	  손 들기(CharacterBuilder.setHandRaised)는 모델 피벗 기준으로 팔을 놓으므로
	  부른 뒤 그 팔의 rel 만 다시 굽는다.

	★ 전학 등장(§9.2)은 내 부지·walk=true 일 때만. 제자리에서 "짠" — 작게 나타나 살짝 넘치게 커졌다 자리 잡는다.
	  걸어 들어오기는 가구·벽을 뚫고 지나가 보여서 없앴다. 다른 부지·재접속은 0.3초 페이드인.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Seats = require(ReplicatedStorage.Shared.Seats)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local SoundController = require(script.Parent.SoundController)

-- 클라이언트 전용 이름과 CharacterBuilder 가 만드는 파트 이름
local RENDER_FOLDER = "NpcRender" -- Workspace.NpcRender.PlotNN (클라이언트 전용)
local PART_TORSO = "Torso"
local PART_ARM_LEFT = "ArmLeft"

local FACILITY_DESK = "desk"
local FACILITY_PRINCIPAL = "principal"
local FACILITY_AUDITORIUM = "auditorium"
local FACILITY_CAFETERIA = "cafeteria"
local FACILITY_LIBRARY = "library"
local FACILITY_MUSIC = "music"

local TEACHER_F_NAME = "TeacherF"
local TEACHER_M_NAME = "TeacherM"
local TEACHER_F_SEED = 2 -- CharacterBuilder.teacherConfig: 짝수 = 여
local TEACHER_M_SEED = 1

local WAIT_ROOT = 10
local WAIT_MODEL = 5

-- §10.3 예산
local LOD_INTERVAL = 1
local PLOTS_NEAR = 4
local PLOTS_NEAR_LOW = 2
local PLOT_ENTER = 230
local PLOT_EXIT = 260
local LOW_QUALITY_MAX = 3
local LOW_FPS = 30 -- 이 FPS 아래가
local LOW_FPS_SECONDS = 10 -- 이만큼(평균) 이어지면 저사양으로 바꾼다
local NEAR_DIST = 60
local MID_DIST = 120
local MID_EVERY = 4
local FAR_DESTROY_SECONDS = 5
local ANIM_MAX = 48
local ANIM_MAX_LOW = 24
local MOVE_BUDGET = 300

-- §10.2 움직임
local IDLE_STEP = 1 / 30
local BOB = 0.04
local SWAY = 0.05
local PHASE_STEP = 0.7
local HAND_MIN = 8
local HAND_MAX = 20
local HAND_SECONDS = 1.5
local HAND_RANGE = 8
local HEAD_RANGE = 12
local HEAD_MAX_YAW = 0.6
local HEAD_TURN_SECONDS = 0.3
local EAT_PERIOD = 1.2
local EAT_PITCH = 0.35
local MUSIC_SWAY = math.rad(4)
local MUSIC_RATE = 1.5
local LIBRARY_PITCH = math.rad(15)
local LEGEND_RATE = 2

-- §9.2 전학 등장("짠")
local POP_SECONDS = 0.45
local POP_MIN_SCALE = 0.05
local POP_OVERSHOOT = 1.70158 -- Back 이징 기본값. 최고 약 1.1배까지 넘쳤다 돌아온다
local POP_SPARKLES = 24
local POP_SPARKLE_LIFE = 1.2
local ARRIVE_HAND_DELAY = 0.5
local FADE_SECONDS = 0.3

-- §9.5 졸업식
local CEREMONY_HAND_DELAY = 2
local CEREMONY_HAND_SECONDS = 3

-- 장식 선생님
local TEACHER_F_DISTANCE = 8 -- 책상 평균 위치에서 학생이 보는 방향으로 이만큼 앞(교탁 옆)
local TEACHER_M_SIDE = 3.5 -- 교장실 손님 의자 오른쪽으로 이만큼

-- 소품·표식 색
local COLOR_PINK = Color3.fromRGB(244, 114, 182)
local COLOR_RED = Color3.fromRGB(220, 38, 38)
local COLOR_NAVY = Color3.fromRGB(30, 58, 138)
local COLOR_BLACK = Color3.fromRGB(30, 30, 30)
local COLOR_GOLD = Color3.fromRGB(250, 204, 21)
local COLOR_BROWN = Color3.fromRGB(120, 72, 32)
local COLOR_CYAN = Color3.fromRGB(34, 211, 238)
local COLOR_SILVER = Color3.fromRGB(203, 213, 225)
local COLOR_ORANGE = Color3.fromRGB(249, 115, 22)
local COLOR_GREEN = Color3.fromRGB(34, 197, 94)

local player = Players.LocalPlayer

local StudentRenderController = {}

type Arrive = {
	model: Model, -- 커지는 동안만 쓰는 임시 모델. 끝나면 attachSeated 로 바꾼다
	t0: number,
	scale: number, -- build 가 정한 최종 스케일(전설은 1.05)
}

type Person = {
	plotId: number,
	studentId: string,
	facilityId: string, -- 자리 시설
	seatIndex: number,
	room: string, -- 행동 기준 시설. 졸업식이면 auditorium
	index: number, -- 도감 순서 1..24. 위상·강당 좌석 번호
	phase: number,
	seat: CFrame, -- 지금 자리(Attachment WorldCFrame)
	home: CFrame, -- 원래 자리
	sitOffset: CFrame, -- build 가 내린 만큼. pivotBase = seat * sitOffset
	pivotBase: CFrame,
	model: Model?,
	parts: { BasePart },
	rel: { CFrame }, -- 피벗 기준. onHead 면 머리 파트 기준
	onHead: { [number]: boolean },
	headIndex: number?,
	armIndex: number?,
	emitter: ParticleEmitter?,
	tier: number, -- 0 멈춤, 1 4틱마다, 2 매 틱
	distance: number,
	farSince: number?,
	handFrom: number,
	handUntil: number,
	nextHand: number,
	handRaised: boolean,
	yaw: number,
	fadeT0: number?,
	arrive: Arrive?,
}

type Plot = {
	id: number,
	persons: { [string]: Person },
	folder: Folder?,
	teachers: { [string]: Model },
	rendered: boolean,
	ceremony: boolean,
	distance: number,
	waiting: { [string]: boolean },
	watched: boolean,
}

type PropDef = {
	on: "head" | "torso",
	shape: Enum.PartType,
	color: Color3,
	size: (Vector3) -> Vector3,
	at: (Vector3) -> CFrame,
}

-- 실린더 축은 X 다. 세로로 세우려면 Z 로 90°, 앞뒤로 눕히려면 Y 로 90°
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local FACING = CFrame.Angles(0, math.pi / 2, 0)

local function topOfHead(h: Vector3, lift: number): CFrame
	return CFrame.new(0, h.Y / 2 + lift, 0)
end

local function faceOfHead(h: Vector3, y: number): CFrame
	return CFrame.new(0, h.Y * y, -h.Z / 2 - 0.08)
end

local function chest(t: Vector3, x: number, y: number, out: number): CFrame
	return CFrame.new(t.X * x, t.Y * y, -t.Z / 2 - out)
end

-- StudentConfig.prop 문자열 → 머리·몸통에 붙는 상징 파트 하나
local PROPS: { [string]: PropDef } = {
	hairpin = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_PINK,
		size = function(_)
			return Vector3.new(0.6, 0.15, 0.15)
		end,
		at = function(h)
			return CFrame.new(h.X * 0.35, h.Y * 0.35, -h.Z * 0.1)
		end,
	},
	cap = {
		on = "head",
		shape = Enum.PartType.Cylinder,
		color = COLOR_RED,
		size = function(h)
			return Vector3.new(0.25, h.X * 1.15, h.X * 1.15)
		end,
		at = function(h)
			return topOfHead(h, 0.1) * UPRIGHT
		end,
	},
	capBaseball = {
		on = "head",
		shape = Enum.PartType.Cylinder,
		color = COLOR_NAVY,
		size = function(h)
			return Vector3.new(0.25, h.X * 1.15, h.X * 1.15)
		end,
		at = function(h)
			return topOfHead(h, 0.1) * UPRIGHT
		end,
	},
	glasses = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_BLACK,
		size = function(h)
			return Vector3.new(h.X * 0.95, 0.25, 0.1)
		end,
		at = function(h)
			return faceOfHead(h, 0.1)
		end,
	},
	goldGlasses = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_GOLD,
		size = function(h)
			return Vector3.new(h.X * 0.95, 0.25, 0.1)
		end,
		at = function(h)
			return faceOfHead(h, 0.1)
		end,
	},
	goggles = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_CYAN,
		size = function(h)
			return Vector3.new(h.X * 0.95, 0.35, 0.2)
		end,
		at = function(h)
			return faceOfHead(h, 0.28)
		end,
	},
	headband = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_GREEN,
		size = function(h)
			return Vector3.new(h.X * 1.05, 0.2, h.Z * 1.05)
		end,
		at = function(h)
			return CFrame.new(0, h.Y * 0.3, 0)
		end,
	},
	scarf = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_RED,
		size = function(h)
			return Vector3.new(h.X * 0.9, 0.4, h.Z * 0.9)
		end,
		at = function(h)
			return CFrame.new(0, -h.Y / 2 - 0.1, 0)
		end,
	},
	helmet = {
		on = "head",
		shape = Enum.PartType.Cylinder,
		color = COLOR_SILVER,
		size = function(h)
			return Vector3.new(0.5, h.X * 1.15, h.X * 1.15)
		end,
		at = function(h)
			return topOfHead(h, 0.05) * UPRIGHT
		end,
	},
	crown = {
		on = "head",
		shape = Enum.PartType.Cylinder,
		color = COLOR_GOLD,
		size = function(h)
			return Vector3.new(0.5, h.X * 0.9, h.X * 0.9)
		end,
		at = function(h)
			return topOfHead(h, 0.2) * UPRIGHT
		end,
	},
	tigerEars = {
		on = "head",
		shape = Enum.PartType.Block,
		color = COLOR_ORANGE,
		size = function(h)
			return Vector3.new(h.X * 1.1, 0.5, 0.4)
		end,
		at = function(h)
			return topOfHead(h, 0.2)
		end,
	},
	bag = {
		on = "torso",
		shape = Enum.PartType.Block,
		color = COLOR_NAVY,
		size = function(t)
			return Vector3.new(t.X * 0.8, t.Y * 0.6, 0.5)
		end,
		at = function(t)
			return CFrame.new(0, 0, t.Z / 2 + 0.3)
		end,
	},
	trophy = {
		on = "torso",
		shape = Enum.PartType.Cylinder,
		color = COLOR_GOLD,
		size = function(_)
			return Vector3.new(0.7, 0.5, 0.5)
		end,
		at = function(t)
			return chest(t, 0.3, 0.1, 0.3) * UPRIGHT
		end,
	},
	books = {
		on = "torso",
		shape = Enum.PartType.Block,
		color = COLOR_BROWN,
		size = function(_)
			return Vector3.new(0.9, 0.7, 0.3)
		end,
		at = function(t)
			return chest(t, 0, 0.1, 0.2)
		end,
	},
	violin = {
		on = "torso",
		shape = Enum.PartType.Block,
		color = COLOR_BROWN,
		size = function(_)
			return Vector3.new(0.5, 1.4, 0.25)
		end,
		at = function(t)
			return chest(t, -0.3, 0.2, 0.2) * CFrame.Angles(0, 0, math.rad(20))
		end,
	},
}

local plots: { [number]: Plot } = {}
local dirty: { [number]: boolean } = {}
local flushScheduled = false
local flushing = false
local flushAgain = false
local pendingArrive: { [string]: boolean } = {} -- 내 부지에서 "짠" 하고 나타날 학생(모델보다 이벤트가 먼저 온 경우)

local renderRoot: Folder? = nil
local plotsFolder: Instance? = nil
local stateRoot: Instance? = nil

local nearLimit = PLOTS_NEAR
local animLimit = ANIM_MAX
local lowSpec = false
local fpsFrames = 0
local fpsTime = 0

local frame = 0
local idleAccum = 0
local lodAccum = 0
local moveCursor = 0
local animated: { Person } = {}
local arriving: { Person } = {}
local fading: { Person } = {}

-- 매 틱 재사용하는 BulkMoveTo 버퍼
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-------------------------------------------------------------------------------
-- 조회
-------------------------------------------------------------------------------

local function attrString(inst: Instance, name: string): string
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else ""
end

local function myPlot(): number?
	local v = player:GetAttribute(Keys.ATTR_PLOT)
	return if typeof(v) == "number" then v else nil
end

local function cameraPosition(): Vector3
	local cam = Workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else Vector3.zero
end

local function playerPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function ensurePlot(plotId: number): Plot
	local plot = plots[plotId]
	if not plot then
		plot = {
			id = plotId,
			persons = {},
			folder = nil,
			teachers = {},
			rendered = false,
			ceremony = false,
			distance = math.huge,
			waiting = {},
			watched = false,
		}
		plots[plotId] = plot
	end
	return plot
end

local function plotModel(plotId: number): Model?
	local root = plotsFolder
	if not root then
		return nil
	end
	local model = root:FindFirstChild(Keys.plotName(plotId))
	return if model and model:IsA("Model") then model else nil
end

local function stateFolder(plotId: number): Instance?
	local root = stateRoot
	return if root then root:FindFirstChild(Keys.plotName(plotId)) else nil
end

local function renderFolder(plot: Plot): Folder
	local folder = plot.folder
	if folder and folder.Parent then
		return folder
	end
	local root = renderRoot
	if not root then
		local made = Instance.new("Folder")
		made.Name = RENDER_FOLDER
		made.Parent = Workspace
		renderRoot = made
		root = made
	end
	local created = Instance.new("Folder")
	created.Name = Keys.plotName(plot.id)
	created.Parent = root
	plot.folder = created
	return created
end

local flushDirty: () -> () -- 아래에서 정의(reconcile 뒤)

local function markDirty(plotId: number)
	dirty[plotId] = true
	if flushScheduled then
		return
	end
	flushScheduled = true
	task.defer(function()
		flushScheduled = false
		flushDirty()
	end)
end

--- 시설 모델. 없으면 5초 기다렸다가 다시 맞춰 본다(스트리밍·건설 지연)
local function facilityModel(plot: Plot, facilityId: string): Model?
	local root = plotModel(plot.id)
	if not root then
		return nil
	end
	local model = root:FindFirstChild(facilityId)
	if model and model:IsA("Model") then
		return model
	end
	if not plot.waiting[facilityId] then
		plot.waiting[facilityId] = true
		task.spawn(function()
			local found = root:WaitForChild(facilityId, WAIT_MODEL)
			plot.waiting[facilityId] = nil
			if found then
				markDirty(plot.id)
			end
		end)
	end
	return nil
end

--- 시설 모델의 Seats/S0n Attachment WorldCFrame
local function seatCFrame(model: Model, index: number): CFrame?
	local seats = model:FindFirstChild(Keys.SEATS_FOLDER)
	local att = if seats then seats:FindFirstChild(Seats.attachmentName(index)) else nil
	return if att and att:IsA("Attachment") then att.WorldCFrame else nil
end

-------------------------------------------------------------------------------
-- 모델 만들기: 소품·표식·rel 굽기
-------------------------------------------------------------------------------

local function makePart(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	cf: CFrame
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function findPart(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

--- 소품 하나 + 등급 표식 하나. 파트 수 ≤ 5 + 1 + 1
local function decorate(model: Model, row: StudentConfig.Student): ParticleEmitter?
	local head = findPart(model, CharacterBuilder.HEAD_MESH)
	local torso = findPart(model, PART_TORSO)

	-- 전용 메시에는 소품이 이미 들어 있다. 대체 원형으로 그릴 때만 붙인다
	local propName = if model:GetAttribute("Variant") == row.fallbackVariant then row.prop else nil
	local def = if propName then PROPS[propName] else nil
	if def then
		local host = if def.on == "head" then head else torso
		if host then
			makePart(
				model,
				propName :: string,
				def.shape,
				def.size(host.Size),
				def.color,
				host.CFrame * def.at(host.Size)
			)
		end
	end

	if row.tier == "반장" then
		local arm = findPart(model, PART_ARM_LEFT) or torso
		if arm then
			local s = arm.Size
			makePart(
				model,
				"Armband",
				Enum.PartType.Block,
				Vector3.new(s.X * 1.15, 0.35, s.Z * 1.15),
				COLOR_RED,
				arm.CFrame * CFrame.new(0, s.Y * 0.3, 0)
			)
		end
	elseif row.tier == "전교1등" then
		if torso then
			makePart(
				model,
				"Medal",
				Enum.PartType.Cylinder,
				Vector3.new(0.1, 0.7, 0.7),
				COLOR_GOLD,
				torso.CFrame * chest(torso.Size, 0, 0.15, 0.05) * FACING
			)
		end
	elseif row.tier == "전설" then
		local host = torso or head
		if host then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Legend"
			emitter.Rate = LEGEND_RATE
			emitter.Color = ColorSequence.new(StudentConfig.TIER_STYLE[row.tier].color)
			emitter.Size = NumberSequence.new(0.5, 0)
			emitter.Transparency = NumberSequence.new(0.2, 1)
			emitter.Lifetime = NumberRange.new(0.8, 1.2)
			emitter.Speed = NumberRange.new(1, 2)
			emitter.SpreadAngle = Vector2.new(40, 40)
			emitter.LightEmission = 0.8
			emitter.Enabled = false -- 페이드인이 끝나면 켠다
			emitter.Parent = host
			return emitter
		end
	end
	return nil
end

--- 렌더 전용 파트 플래그. build 가 collide/shadow 는 잡지만 CanQuery/CanTouch 는 여기서 끈다
local function silenceParts(model: Model)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
end

--- 파트 목록과 피벗 기준 상대 CFrame 을 굽는다. 머리에 붙은 소품은 머리 기준
local function bake(person: Person, model: Model)
	local pivot = person.pivotBase
	local parts: { BasePart } = {}
	local rel: { CFrame } = {}
	local onHead: { [number]: boolean } = {}
	local head = findPart(model, CharacterBuilder.HEAD_MESH)
	person.headIndex = nil
	person.armIndex = nil

	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local i = #parts + 1
			parts[i] = child
			if child == head then
				person.headIndex = i
				rel[i] = pivot:ToObjectSpace(child.CFrame)
			elseif head and PROPS[child.Name] and PROPS[child.Name].on == "head" then
				onHead[i] = true
				rel[i] = head.CFrame:ToObjectSpace(child.CFrame)
			else
				rel[i] = pivot:ToObjectSpace(child.CFrame)
			end
			if child.Name == CharacterBuilder.ARM_RIGHT then
				person.armIndex = i
			end
		end
	end
	person.parts = parts
	person.rel = rel
	person.onHead = onHead
end

local function destroyModel(person: Person)
	local model = person.model
	if model then
		model:Destroy()
	end
	person.model = nil
	person.parts = {}
	person.rel = {}
	person.onHead = {}
	person.headIndex = nil
	person.armIndex = nil
	person.emitter = nil
	person.handRaised = false
	person.fadeT0 = nil
end

local function destroyArrive(person: Person)
	local arrive = person.arrive
	if arrive then
		arrive.model:Destroy()
		person.arrive = nil
		local i = table.find(arriving, person)
		if i then
			table.remove(arriving, i)
		end
	end
end

--- 앉은 모델을 만들어 자리에 놓는다. fade 면 0.3초 페이드인
local function attachSeated(plot: Plot, person: Person, fade: boolean)
	local row = StudentConfig.BY_ID[person.studentId]
	local model =
		CharacterBuilder.build(person.studentId, person.seat, CharacterBuilder.studentConfig(person.studentId))
	if not model then
		warn(`[StudentRender] {person.studentId} 모델을 만들 수 없다`)
		return
	end
	person.sitOffset = person.seat:ToObjectSpace(model:GetPivot())
	person.pivotBase = model:GetPivot()
	person.emitter = decorate(model, row)
	silenceParts(model)
	model.Parent = renderFolder(plot)
	person.model = model
	bake(person, model)

	if fade then
		for _, part in person.parts do
			part.LocalTransparencyModifier = 1
		end
		person.fadeT0 = os.clock()
		table.insert(fading, person)
	else
		local emitter = person.emitter
		if emitter then
			emitter.Enabled = true
		end
	end
end

--- 손 올리기/내리기. 모델 피벗 기준으로 팔을 놓고 그 팔의 rel 만 다시 굽는다
local function setHand(person: Person, raised: boolean)
	local model = person.model
	if not model then
		return
	end
	person.handRaised = raised
	model:PivotTo(person.pivotBase)
	CharacterBuilder.setHandRaised(model, raised)
	local i = person.armIndex
	if i then
		person.rel[i] = person.pivotBase:ToObjectSpace(person.parts[i].CFrame)
	end
end

local function newPerson(plotId: number, studentId: string, facilityId: string, seatIndex: number, seat: CFrame): Person
	local index = table.find(StudentConfig.ORDER, studentId) or 1
	local now = os.clock()
	return {
		plotId = plotId,
		studentId = studentId,
		facilityId = facilityId,
		seatIndex = seatIndex,
		room = facilityId,
		index = index,
		phase = index * PHASE_STEP,
		seat = seat,
		home = seat,
		sitOffset = CFrame.identity,
		pivotBase = seat,
		model = nil,
		parts = {},
		rel = {},
		onHead = {},
		headIndex = nil,
		armIndex = nil,
		emitter = nil,
		tier = 0,
		distance = (seat.Position - cameraPosition()).Magnitude,
		farSince = nil,
		handFrom = 0,
		handUntil = 0,
		nextHand = now + math.random(HAND_MIN, HAND_MAX),
		handRaised = false,
		yaw = 0,
		fadeT0 = nil,
		arrive = nil,
	}
end

local function removePerson(plot: Plot, person: Person)
	destroyArrive(person)
	destroyModel(person)
	plot.persons[person.studentId] = nil
end

-------------------------------------------------------------------------------
-- 전학 등장(§9.2)
-------------------------------------------------------------------------------

--- Back 이징(ease-out). 0→1 로 가다 1 을 살짝 넘긴 뒤 1 에 선다
local function easeOutBack(t: number): number
	local u = t - 1
	return 1 + (POP_OVERSHOOT + 1) * u * u * u + POP_OVERSHOOT * u * u
end

--- 자리 위 반짝이 한 번. 파티클이 다 사라지면 지운다
local function sparkleBurst(plot: Plot, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "ArriveSparkle"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(at)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(COLOR_GOLD, COLOR_PINK)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.6, POP_SPARKLE_LIFE)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.LightEmission = 0.8
	emitter.Enabled = false
	emitter.Parent = anchor
	anchor.Parent = renderFolder(plot)
	emitter:Emit(POP_SPARKLES)
	task.delay(POP_SPARKLE_LIFE + 0.2, function()
		anchor:Destroy()
	end)
end

local function beginArrive(plot: Plot, person: Person)
	local model =
		CharacterBuilder.build(person.studentId, person.seat, CharacterBuilder.studentConfig(person.studentId))
	if not model then
		warn(`[StudentRender] {person.studentId} 등장 모델을 만들 수 없다`)
		if not person.model then
			attachSeated(plot, person, true)
		end
		return
	end
	destroyModel(person)
	destroyArrive(person)
	decorate(model, StudentConfig.BY_ID[person.studentId])
	silenceParts(model)
	local scale = model:GetScale()
	model:ScaleTo(scale * POP_MIN_SCALE)
	model.Parent = renderFolder(plot)
	person.arrive = {
		model = model,
		t0 = os.clock(),
		scale = scale,
	}
	table.insert(arriving, person)
	sparkleBurst(plot, (person.seat * CFrame.new(0, CharacterBuilder.SIT_HIP + 1.5, 0)).Position)
	SoundController.play("arrive")
end

local function finishArrive(plot: Plot, person: Person)
	destroyArrive(person)
	attachSeated(plot, person, false)
	SoundController.play("sit")
	local now = os.clock()
	person.handFrom = now + ARRIVE_HAND_DELAY
	person.handUntil = person.handFrom + HAND_SECONDS
	lodAccum = LOD_INTERVAL -- 바로 움직임 등급을 매겨 손을 들게 한다
end

--- ScaleTo 는 모델 피벗(발 아래)을 축으로 줄였다 늘린다. 자리에서 솟아나듯 커진다
local function updateArrive(person: Person, now: number)
	local arrive = person.arrive
	if not arrive then
		return
	end
	local alpha = math.clamp((now - arrive.t0) / POP_SECONDS, 0, 1)
	arrive.model:ScaleTo(arrive.scale * math.max(POP_MIN_SCALE, easeOutBack(alpha)))

	if alpha >= 1 then
		local plot = plots[person.plotId]
		if plot and plot.persons[person.studentId] == person then
			finishArrive(plot, person)
		else
			destroyArrive(person)
		end
	end
end

-------------------------------------------------------------------------------
-- 장식 선생님
-------------------------------------------------------------------------------

local function teacherPose(plot: Plot, name: string): CFrame?
	if name == TEACHER_F_NAME then
		local desk = facilityModel(plot, FACILITY_DESK)
		if not desk then
			return nil
		end
		local sum = Vector3.zero
		local look = Vector3.zero
		local n = 0
		for i = 1, (FacilityConfig.BY_ID[FACILITY_DESK] and FacilityConfig.BY_ID[FACILITY_DESK].seats) or 0 do
			local cf = seatCFrame(desk, i)
			if cf then
				sum += cf.Position
				look += cf.LookVector
				n += 1
			end
		end
		if n == 0 or look.Magnitude < 0.01 then
			return nil
		end
		local center = sum / n
		local forward = look.Unit
		local pos = center + forward * TEACHER_F_DISTANCE
		return CFrame.lookAt(pos, pos - forward) -- 학생 쪽(+Z)을 본다
	end
	local office = facilityModel(plot, FACILITY_PRINCIPAL)
	local seat = if office then seatCFrame(office, 1) else nil
	if not seat then
		return nil
	end
	local pos = seat.Position + seat.RightVector * TEACHER_M_SIDE
	return CFrame.lookAt(pos, pos + seat.LookVector)
end

local function ensureTeacher(plot: Plot, name: string, seed: number)
	local existing = plot.teachers[name]
	if existing and existing.Parent then
		return
	end
	local pose = teacherPose(plot, name)
	if not pose then
		return
	end
	local model = CharacterBuilder.build(name, pose, CharacterBuilder.teacherConfig(seed))
	if not model then
		return
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.Parent = renderFolder(plot)
	plot.teachers[name] = model
end

local function ensureTeachers(plot: Plot)
	ensureTeacher(plot, TEACHER_F_NAME, TEACHER_F_SEED)
	ensureTeacher(plot, TEACHER_M_NAME, TEACHER_M_SEED)
end

local function clearPlot(plot: Plot)
	for _, person in plot.persons do
		removePerson(plot, person)
	end
	for name, model in plot.teachers do
		model:Destroy()
		plot.teachers[name] = nil
	end
	local folder = plot.folder
	if folder then
		folder:Destroy()
		plot.folder = nil
	end
end

-------------------------------------------------------------------------------
-- 상태 → 모델 맞추기
-------------------------------------------------------------------------------

type Want = { facilityId: string, index: number, model: Model }

local function reconcile(plot: Plot)
	if not plot.rendered then
		clearPlot(plot)
		return
	end

	local wanted: { [string]: Want } = {}
	local state = stateFolder(plot.id)
	if state then
		local students = StudentConfig.fromCsv(attrString(state, Keys.ATTR_STUDENTS))
		local built = FacilityConfig.fromCsv(attrString(state, Keys.ATTR_FACILITIES))
		for facilityId, room in Seats.occupants(students, built) do
			local model = facilityModel(plot, facilityId)
			if model then
				for index, studentId in room do
					wanted[studentId] = { facilityId = facilityId, index = index, model = model }
				end
			end
		end
	end

	for studentId, person in plot.persons do
		local want = wanted[studentId]
		if not want or want.facilityId ~= person.facilityId or want.index ~= person.seatIndex then
			removePerson(plot, person)
		end
	end

	local mine = myPlot() == plot.id
	local camPos = cameraPosition()
	for studentId, want in wanted do
		local person = plot.persons[studentId]
		if not person then
			local seat = seatCFrame(want.model, want.index)
			if seat then
				person = newPerson(plot.id, studentId, want.facilityId, want.index, seat)
				plot.persons[studentId] = person
			else
				warn(`[StudentRender] {want.facilityId} 에 {Seats.attachmentName(want.index)} 자리가 없다`)
			end
		end
		if person and not person.model and not person.arrive then
			if mine and pendingArrive[studentId] then
				pendingArrive[studentId] = nil
				beginArrive(plot, person)
			else
				person.distance = (person.seat.Position - camPos).Magnitude
				if person.distance <= MID_DIST then
					attachSeated(plot, person, true)
				end
			end
		end
	end

	ensureTeachers(plot)
end

function flushDirty()
	if flushing then
		flushAgain = true
		return
	end
	flushing = true
	repeat
		flushAgain = false
		local batch = dirty
		dirty = {}
		for plotId in batch do
			reconcile(ensurePlot(plotId))
		end
	until not flushAgain and next(dirty) == nil
	flushing = false
end

-------------------------------------------------------------------------------
-- LOD (1초마다)
-------------------------------------------------------------------------------

--- 부지 거리 = 지어진 시설 모델들의 S01 자리 중 가장 가까운 것. 시설이 없으면 무한대
local function plotDistance(plot: Plot, camPos: Vector3): number
	local state = stateFolder(plot.id)
	local root = plotModel(plot.id)
	if not state or not root then
		return math.huge
	end
	local best = math.huge
	for facilityId in FacilityConfig.fromCsv(attrString(state, Keys.ATTR_FACILITIES)) do
		local model = root:FindFirstChild(facilityId)
		local cf = if model and model:IsA("Model") then seatCFrame(model, 1) else nil
		if cf then
			best = math.min(best, (cf.Position - camPos).Magnitude)
		end
	end
	return best
end

local function lodTick(now: number)
	local camPos = cameraPosition()

	local order: { Plot } = {}
	for plotId = 1, Keys.PLOT_COUNT do
		local plot = ensurePlot(plotId)
		plot.distance = plotDistance(plot, camPos)
		table.insert(order, plot)
	end
	table.sort(order, function(a, b)
		return a.distance < b.distance
	end)

	local count = 0
	for _, plot in order do
		local limit = if plot.rendered then PLOT_EXIT else PLOT_ENTER
		local keep = plot.distance <= limit and count < nearLimit
		if keep then
			count += 1
		end
		if keep ~= plot.rendered then
			plot.rendered = keep
			markDirty(plot.id)
		end
	end

	local list: { Person } = {}
	for _, plot in order do
		if plot.rendered then
			for _, person in plot.persons do
				if not person.arrive then
					person.distance = (person.seat.Position - camPos).Magnitude
					table.insert(list, person)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)

	table.clear(animated)
	for _, person in list do
		local tier = 0
		if #animated < animLimit then
			if person.distance <= NEAR_DIST then
				tier = 2
			elseif person.distance <= MID_DIST then
				tier = 1
			end
		end
		person.tier = tier
		if tier > 0 and person.model then
			table.insert(animated, person)
		end

		if person.distance > MID_DIST then
			if not person.farSince then
				person.farSince = now
			elseif person.model and now - person.farSince > FAR_DESTROY_SECONDS then
				destroyModel(person)
			end
		else
			person.farSince = nil
			if not person.model then
				markDirty(person.plotId)
			end
		end
	end
	moveCursor = 0
end

-------------------------------------------------------------------------------
-- 움직임 (30Hz)
-------------------------------------------------------------------------------

local function animate(person: Person, t: number, now: number, dt: number, playerPos: Vector3?)
	local phase = person.phase
	local pivot = person.pivotBase
		* CFrame.new(0, math.sin(t + phase) * BOB, 0)
		* CFrame.Angles(0, math.sin(t * 0.6 + phase) * SWAY, 0)
	local room = person.room
	if room == FACILITY_MUSIC then
		pivot = pivot * CFrame.Angles(0, 0, math.sin(t * MUSIC_RATE + phase) * MUSIC_SWAY)
	end

	local pitch = 0
	if room == FACILITY_LIBRARY then
		pitch = -LIBRARY_PITCH
	elseif room == FACILITY_CAFETERIA then
		pitch = -EAT_PITCH * math.max(0, math.sin(2 * math.pi * t / EAT_PERIOD + phase))
	end

	local targetYaw = 0
	local near = false
	if playerPos then
		local toPlayer = playerPos - pivot.Position
		local d = toPlayer.Magnitude
		near = d <= HAND_RANGE
		if person.tier == 2 and d <= HEAD_RANGE then
			local localDir = pivot:VectorToObjectSpace(toPlayer)
			targetYaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -HEAD_MAX_YAW, HEAD_MAX_YAW)
		end
	end
	person.yaw += (targetYaw - person.yaw) * math.min(1, dt / HEAD_TURN_SECONDS)

	local wantHand = now >= person.handFrom and now < person.handUntil
	if not wantHand and now >= person.nextHand then
		person.nextHand = now + math.random(HAND_MIN, HAND_MAX)
		if near then
			person.handFrom = now
			person.handUntil = now + HAND_SECONDS
			wantHand = true
		end
	end
	if wantHand ~= person.handRaised then
		setHand(person, wantHand)
	end

	local headIndex = person.headIndex
	local headCF = if headIndex then pivot * person.rel[headIndex] * CFrame.Angles(pitch, person.yaw, 0) else pivot
	for i, part in person.parts do
		local cf
		if i == headIndex then
			cf = headCF
		elseif person.onHead[i] then
			cf = headCF * person.rel[i]
		else
			cf = pivot * person.rel[i]
		end
		table.insert(moveParts, part)
		table.insert(moveCFrames, cf)
	end
end

local function updateFades(now: number)
	for i = #fading, 1, -1 do
		local person = fading[i]
		local t0 = person.fadeT0
		if not t0 or not person.model then
			table.remove(fading, i)
		else
			local alpha = math.clamp((now - t0) / FADE_SECONDS, 0, 1)
			for _, part in person.parts do
				part.LocalTransparencyModifier = 1 - alpha
			end
			if alpha >= 1 then
				person.fadeT0 = nil
				local emitter = person.emitter
				if emitter then
					emitter.Enabled = true
				end
				table.remove(fading, i)
			end
		end
	end
end

local function idleTick(dt: number)
	frame += 1
	local now = os.clock()
	local playerPos = playerPosition()

	for i = #arriving, 1, -1 do
		updateArrive(arriving[i], now)
	end

	table.clear(moveParts)
	table.clear(moveCFrames)
	local budget = MOVE_BUDGET
	local n = #animated
	local stopped = 0
	for k = 1, n do
		local i = (moveCursor + k - 1) % n + 1
		local person = animated[i]
		if person.model and (person.tier == 2 or (frame + i) % MID_EVERY == 0) then
			if #person.parts > budget then
				stopped = i
				break
			end
			budget -= #person.parts
			animate(person, now, now, dt, playerPos)
		end
	end
	moveCursor = if stopped > 0 then stopped - 1 else 0

	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	updateFades(now)
end

--- 저사양 다이얼(§12.1). 한 번 켜면 끄지 않는다(오르내리며 부지가 깜빡이지 않게). 다음 lodTick 부터 적용된다
local function enterLowSpec(reason: string)
	if lowSpec then
		return
	end
	lowSpec = true
	nearLimit = PLOTS_NEAR_LOW
	animLimit = ANIM_MAX_LOW
	print(`[StudentRender] 저사양 다이얼 켬: {reason}`)
end

--- LOW_FPS_SECONDS 구간마다 평균 FPS 를 본다. 순간 끊김 하나로는 바뀌지 않는다
local function watchFps(dt: number)
	if lowSpec then
		return
	end
	fpsFrames += 1
	fpsTime += dt
	if fpsTime < LOW_FPS_SECONDS then
		return
	end
	local fps = fpsFrames / fpsTime
	fpsFrames = 0
	fpsTime = 0
	if fps < LOW_FPS then
		enterLowSpec(`평균 {math.floor(fps)} FPS`)
	end
end

local function onHeartbeat(dt: number)
	watchFps(dt)
	lodAccum += dt
	if lodAccum >= LOD_INTERVAL then
		lodAccum = 0
		lodTick(os.clock())
	end
	idleAccum += dt
	if idleAccum >= IDLE_STEP then
		local step = idleAccum
		idleAccum = 0
		idleTick(step)
	end
end

-------------------------------------------------------------------------------
-- 공개 API
-------------------------------------------------------------------------------

--- 저사양 다이얼이 켜졌나. FeedbackController 가 파티클 예산을 줄일 때 본다
function StudentRenderController.isLowSpec(): boolean
	return lowSpec
end

--- GameEvent StudentJoined { plot, studentId, walk }. 내 부지·walk 면 제자리에서 "짠" 하고 나타난다
function StudentRenderController.onStudentJoined(payload: { plot: number, studentId: string, walk: boolean? })
	local plotId = payload.plot
	local studentId = payload.studentId
	if typeof(plotId) ~= "number" or typeof(studentId) ~= "string" then
		return
	end
	local plot = ensurePlot(plotId)
	if payload.walk and myPlot() == plotId then
		local person = plot.persons[studentId]
		if person then
			beginArrive(plot, person)
		else
			pendingArrive[studentId] = true
		end
	end
	markDirty(plotId)
end

--- 졸업식(§9.5). true 면 그 부지 학생 전원을 강당 S01~S24 로 옮기고 2초 뒤 손을 든다. false 면 제자리
function StudentRenderController.ceremony(plotId: number, active: boolean)
	local plot = plots[plotId]
	if not plot then
		return
	end
	plot.ceremony = active
	local auditorium = if active then facilityModel(plot, FACILITY_AUDITORIUM) else nil
	if active and not auditorium then
		warn(`[StudentRender] Plot{plotId} 에 강당 모델이 없어 졸업식 좌석 이동을 건너뛴다`)
	end

	for _, person in plot.persons do
		if person.arrive then
			continue
		end
		if active then
			local cf = if auditorium then seatCFrame(auditorium, person.index) else nil
			if cf then
				person.seat = cf
				person.room = FACILITY_AUDITORIUM
			end
		else
			person.seat = person.home
			person.room = person.facilityId
		end
		person.pivotBase = person.seat * person.sitOffset
		local model = person.model
		if model then
			model:PivotTo(person.pivotBase)
			if not active and person.handRaised then
				setHand(person, false)
			end
		end
	end

	if active then
		task.delay(CEREMONY_HAND_DELAY, function()
			if not plot.ceremony then
				return
			end
			local now = os.clock()
			for _, person in plot.persons do
				person.handFrom = now
				person.handUntil = now + CEREMONY_HAND_SECONDS
				if person.model and not person.handRaised then
					setHand(person, true)
				end
			end
		end)
	end
	lodAccum = LOD_INTERVAL
end

--- 한 학생이 seconds 동안 손을 든다
function StudentRenderController.raiseHand(plotId: number, studentId: string, seconds: number)
	local plot = plots[plotId]
	local person = if plot then plot.persons[studentId] else nil
	if not person then
		return
	end
	local now = os.clock()
	person.handFrom = now
	person.handUntil = now + seconds
	if person.model and not person.handRaised then
		setHand(person, true)
	end
	-- 멈춘 등급(tier 0)은 틱이 안 내리므로 여기서 내린다
	task.delay(seconds, function()
		if person.handRaised and os.clock() >= person.handUntil then
			setHand(person, false)
		end
	end)
end

-------------------------------------------------------------------------------
-- 시작
-------------------------------------------------------------------------------

local function watchState(folder: Instance)
	local plotId = Keys.plotIdOf(folder.Name)
	if not plotId then
		return
	end
	folder:GetAttributeChangedSignal(Keys.ATTR_STUDENTS):Connect(function()
		markDirty(plotId)
	end)
	folder:GetAttributeChangedSignal(Keys.ATTR_FACILITIES):Connect(function()
		markDirty(plotId)
	end)
	markDirty(plotId)
end

local function watchPlotModel(model: Instance)
	local plotId = Keys.plotIdOf(model.Name)
	if not plotId then
		return
	end
	local plot = ensurePlot(plotId)
	if plot.watched then
		return
	end
	plot.watched = true
	local function onChild(child: Instance)
		if FacilityConfig.BY_ID[child.Name] then
			markDirty(plotId)
		end
	end
	model.ChildAdded:Connect(onChild)
	model.ChildRemoved:Connect(onChild)
	markDirty(plotId)
end

local function qualityIsLow(): boolean
	local ok, quality = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok then
		return false
	end
	return quality ~= Enum.SavedQualitySetting.Automatic and quality.Value <= LOW_QUALITY_MAX
end

function StudentRenderController.Start()
	if qualityIsLow() then
		enterLowSpec("그래픽 품질 설정")
	end

	task.spawn(function()
		local plotsRoot = Workspace:WaitForChild(Keys.PLOTS_FOLDER, WAIT_ROOT)
		local states = ReplicatedStorage:WaitForChild(Keys.PLOT_STATE_FOLDER, WAIT_ROOT)
		if not plotsRoot or not states then
			warn("[StudentRender] Plots / PlotState 폴더를 찾지 못해 학생을 그리지 않는다")
			return
		end
		plotsFolder = plotsRoot
		stateRoot = states

		for _, child in states:GetChildren() do
			watchState(child)
		end
		states.ChildAdded:Connect(watchState)

		for _, child in plotsRoot:GetChildren() do
			watchPlotModel(child)
		end
		plotsRoot.ChildAdded:Connect(watchPlotModel)

		RunService.Heartbeat:Connect(onHeartbeat)
	end)
end

return StudentRenderController
