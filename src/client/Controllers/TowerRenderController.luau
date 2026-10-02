--!strict
--[[
	TowerRenderController — 층 쌓기 탑의 벽·간판·짓는 층·방 안·옥상을 그리는 클라 렌더. 개선계획 §5.3.

	서버는 부지 모델 안 Tower 폴더에 바닥판(FloorNN)·Roof·TowerPad·1·2층 엘리베이터 앵커만 둔다(§5.2).
	나머지는 전부 여기서 Workspace.TowerFx/PlotNN 아래 로컬 파트로 그린다. 12부지 모두 PlotState 어트리뷰트
	Floors·Rooftop·TowerRoom·TowerParts·Rank·Facilities 를 스스로 구독한다(강당이 없으면 아무것도 안 그린다).

	조각(key)마다 서명(sig)을 기억해 바뀐 조각만 다시 짓는다. 조각은 모두 Model(WorldPivot = 그 층 바닥 가운데).
	  F{n}   n층 외관. 가까운 부지(내 부지 + 가까운 부지, 모두 NEAR_COUNT)는 벽 4 + 띠 1(창 Texture·간판 SurfaceGui 는
	         파트가 아님) = 층당 5 파트. 먼 부지는 상자 1(남쪽 면 창 Texture). 거리와 무관하게 모든 층을 그린다.
	         짓는 층(TowerRoom 이 층 방, 층 번호 topFloor+1): 부품 0 = 반투명 실루엣 1, 1~3 = 벽·창(띠·간판 없음).
	  Roof   옥상: 엘리베이터 기둥(발자국 북동 모서리, 3층 바닥 ~ 옥상 위) 1 + 깃대 1 + 깃발 1(Rank 1 금·2 은·3 동·그 밖
	         학교 색) + 난간 4(가까운 부지만, 보기만. 충돌 없음).
	         옥상 높이 = topFloor+1, 층 방을 짓는 중(부품 ≥ 1)이면 그 위 한 층(서버 지붕과 같은 규칙).
	  R{id}  옥상 방(정원·천문대, 자기 옥상 구역 RoomConfig zone 안): 부품 0 = 구역 실루엣 1, 1 = 반투명 구역 상자 1.
	         가까운 부지 부품 2~4 = Rooms 레시피 big/+props/+finish(≤ 45 파트, assert), 완공이면 "Sign" 파트에 이름 간판.
	         먼 부지 부품 ≥ 2 = 구역 바닥판 1 + 완공이면 학생 의자 1(옥상 학생은 어디서나 보인다).
	  I{n}   방 안(Rooms.get 레시피): 캐릭터가 서 있는 부지의 그 층 ±1 층만(옥상은 R{id} 가 그린다).
	         부품 2 = big, 3 = +props, 완공 = +finish. 방 하나 ≤ 60 파트(assert). 바닥 큰 가구(opts.collide)만 충돌한다.
	  E{n}   엘리베이터 문(9 파트, 서버 프롬프트 자리 뒤 벽에 등을 댄다): 가까운 부지는 1층·2층·옥상, 캐릭터가 선 부지는 그 층 ±1.
	         프롬프트가 뜨면 문이 열리고 사라지면 닫힌다(PromptShown·PromptHidden, 내 화면만).
	  레시피 파트에 opts.mesh 가 있으면 MeshPart(처음엔 파트로 짓고 메시가 준비되면 다시 짓는다. id 0·실패 = 파트).
	부지 하나 최악(30층 + 옥상) 가까움 5 × 28 + 7 + 옥상 방 2 × 45 + 방 안 3 × 60 + 엘리베이터 문 6 × 9 ≈ 471, 먼 부지 28 + 3 + 2 × 2 = 35.

	가림 페이드(옛 "TowerFade" 그대로)
	  RenderStep "TowerFade"(Camera + 3, CameraController "CameraFade" +2 뒤)에서 HumanoidRootPart → 카메라 쪽으로
	  레이(Include = TowerFx + 각 부지 Tower 폴더)를 맞은 곳 너머로 이어 쏘아 맞은 파트를 LocalTransparencyModifier FADE.
	  방 안에 있으면 남쪽 벽과 천장(서버 위층 바닥판·Roof)이 이 레이에 걸려 흐려진다.
	  ★ Popper 는 CanCollide 이고 투명도 < 0.25 인 파트 앞으로 카메라를 당긴다. 레이를 max(지금 거리, 최대 줌) 까지
	    쏘아 당기기 전 자리까지 닿게 하고, 흐린 파트(0.88)는 다음 프레임부터 Popper 가림막이 아니다.
	  SurfaceGui 는 LocalTransparencyModifier 를 따르지 않아 흐린 동안 Enabled false, Texture 는 Transparency FADE.
	  방 안 가구·실루엣·난간은 CanQuery false 라 레이에 걸리지 않는다.

	공개 API: Start(), onEvent(kind, payload)(FloorPart·FloorBuilt·RoomChosen. FloorPart·FloorBuilt 는 내 부지면 그 조각을
	  짧게 튀긴다), partCount(): number(TowerFx 안 BasePart 수).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)
local MeshCache = require(script.Parent.Parent.MeshCache)
local Rooms = require(script.Parent.Parent.Rooms)

-- 형제 컨트롤러는 형태만 선언하고 any 로 받는다(StudentRenderController 는 이 모듈을 require 하지 않는다)
type StudentRenderApi = { isLowSpec: () -> boolean }
local StudentRenderController = (require(script.Parent.StudentRenderController) :: any) :: StudentRenderApi

local TowerRenderController = {}

-- ── 수치(렌더 전용. 옛 TowerConfig.RENDER 값) ──
local TICK = 0.25 -- 캐릭터 층 확인 주기(엘리베이터 도착 뒤 방 안이 빨리 뜨게)
local NEAR_EVERY = 4 -- TICK × 4 = 1초마다 가까운 부지 순위
local WALL_T = 0.6
local WALL_H = PlotLayout.FLOOR_STEP - 1 -- 위층 바닥판(두께 1) 아랫면까지
local BAND_H = 3 -- 간판 띠
local RAIL_H = 3
local PILLAR = 3 -- 엘리베이터 기둥 굵기
local PILLAR_ABOVE = 8 -- 옥상 위로 솟는 높이
-- 엘리베이터 문(타는 곳 칸 끝에 붙여 PlotLayout.elevatorFacing 쪽을 본다. 도착 자리가 그쪽이라 문에서 걸어 나오는 모양)
local ELEV_W = 5 -- 문틀 전체 폭
local ELEV_H = 8.1
local ELEV_D = 1.4 -- 뒤 상자 깊이
local OPEN_W = 2.6 -- 문 구멍 폭(문 한 짝 = 절반)
local OPEN_H = 6.5
local FACADE_T = 0.5 -- 문틀 두께. 문은 그 안 0.05~0.25 에 있어 열리면 옆 문틀 속으로 숨는다
local DOOR_SLIDE = (ELEV_W - OPEN_W) / 2
local DOOR_SECONDS = 0.45
local SPOT_MATCH = 2 -- 프롬프트 자리와 문 조각의 Spot 이 이만큼 안이면 같은 타는 곳
local ELEV_PIXELS_PER_STUD = 40
local DOOR_STEEL = Color3.fromRGB(196, 204, 214)
local ATTR_SPOT = "ElevatorSpot" -- 문 조각 Model: 프롬프트 자리(월드)
local ATTR_CLOSED = "ClosedCFrame" -- 문 짝: 닫힌 CFrame
local ATTR_SIDE = "SlideSide" -- 문 짝: 열리는 쪽(-1 서·+1 동)
local POLE_H = 7
local FLAG_SIZE = Vector3.new(4, 2.5, 0.2)
local GHOST = 0.7 -- 실루엣 투명도
local FADE = 0.88 -- CameraController FADE 와 같은 값
local GUI_MAX_DISTANCE = 150
local SIGN_PIXELS_PER_STUD = 16
local FADE_MAX_HITS = 8
local FADE_STEP = 0.01
local POP_FROM = 0.85
local POP_SECONDS = 0.35
local MAX_ROOM_PARTS = 60
local MAX_ROOF_PARTS = 45 -- 옥상 방 하나(가까운 부지는 늘 그리니 층 방보다 적게)
local DECK_H = 0.3 -- 먼 부지 옥상 방 바닥판
local SIGN_FORMAT = "%s %d층 %s" -- 「{icon} {n}층 {방이름}」
local RANK_COLORS = {
	Color3.fromRGB(255, 200, 40), -- 금
	Color3.fromRGB(205, 215, 230), -- 은
	Color3.fromRGB(205, 140, 80), -- 동
}
local FOOT = PlotLayout.TOWER_FOOTPRINT
local FOOT_CENTER = Vector2.new((FOOT.x0 + FOOT.x1) / 2, (FOOT.z0 + FOOT.z1) / 2)
local LONG_LEN = FOOT.x1 - FOOT.x0
local DEPTH = FOOT.z1 - FOOT.z0
local SHORT_LEN = DEPTH - WALL_T * 2
local WALLS: { { name: string, c: Vector2, s: Vector2 } } = { -- 가운데(x, z), 크기(x, z)
	{ name = "WallN", c = Vector2.new(FOOT_CENTER.X, FOOT.z0 + WALL_T / 2), s = Vector2.new(LONG_LEN, WALL_T) },
	{ name = "WallS", c = Vector2.new(FOOT_CENTER.X, FOOT.z1 - WALL_T / 2), s = Vector2.new(LONG_LEN, WALL_T) },
	{ name = "WallW", c = Vector2.new(FOOT.x0 + WALL_T / 2, FOOT_CENTER.Y), s = Vector2.new(WALL_T, SHORT_LEN) },
	{ name = "WallE", c = Vector2.new(FOOT.x1 - WALL_T / 2, FOOT_CENTER.Y), s = Vector2.new(WALL_T, SHORT_LEN) },
}

local player = Players.LocalPlayer
local started = false
local fxRoot: Folder? = nil
local plotsFolder: Instance? = nil
local stateRoot: Instance? = nil
local myPlotId: number? = nil
local lowSpec = false

type Entry = { folder: Folder, sigs: { [string]: string }, nodes: { [string]: Model } }
local rendered: { [number]: Entry } = {}
local near: { [number]: boolean } = {}
local pivots: { [number]: CFrame } = {}
local watched: { [Instance]: boolean } = {}
local popPending: { [number]: string } = {} -- 부지 → 튀길 조각 key(이벤트가 어트리뷰트보다 먼저 온 경우)
local herePlot: number? = nil -- 캐릭터가 서 있는 탑 부지
local hereFloor = 0
local faded: { [BasePart]: true } = {}
-- 레시피 메시(PutOpts.mesh, MeshCache). 새 메시가 준비되면 meshVersion 이 올라 방 서명이 바뀐다
local meshVersion = 0
local renderAll: () -> ()
local fadeParams: RaycastParams? = nil

-- ── 부지 읽기 ────────────────────────────────────────────────────

local function plotPivot(plotId: number): CFrame?
	local known = pivots[plotId]
	if known then
		return known
	end
	local folder = plotsFolder
	local model = if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
	if not model or not model:IsA("Model") then
		return nil
	end
	local pivot = model:GetPivot()
	pivots[plotId] = pivot
	return pivot
end

type State = { floors: { string }, rooftop: { string }, room: string, parts: number, rank: number }

local function readState(plotId: number): State?
	local folder = stateRoot
	local state = if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
	if not state then
		return nil
	end
	local function str(name: string): string
		local v = state:GetAttribute(name)
		return if type(v) == "string" then v else ""
	end
	local function num(name: string): number
		local v = state:GetAttribute(name)
		return if type(v) == "number" then v else 0
	end
	if not (FacilityConfig.fromCsv(str(Keys.ATTR_FACILITIES)) :: any).auditorium then
		return nil
	end
	return {
		floors = RoomConfig.fromCsv(str(Keys.ATTR_FLOORS)),
		rooftop = RoomConfig.fromCsv(str(Keys.ATTR_ROOFTOP)),
		room = str(Keys.ATTR_TOWER_ROOM),
		parts = math.clamp(math.floor(num(Keys.ATTR_TOWER_PARTS)), 0, RoomConfig.PARTS),
		rank = num(Keys.ATTR_RANK),
	}
end

--- 짓는 층 방(없으면 nil)과 옥상 층 번호
local function layout(st: State): (RoomConfig.Room?, number)
	local top = RoomConfig.topFloor(#st.floors)
	local room = RoomConfig.BY_ID[st.room]
	local building = if room and room.kind == "floor" then room else nil
	return building, top + 1 + (if building and st.parts >= 1 then 1 else 0)
end

-- ── 만들기 ───────────────────────────────────────────────────────

local function newModel(pivot: CFrame, n: number, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.WorldPivot = pivot * CFrame.new(FOOT_CENTER.X, RoomConfig.floorY(n), FOOT_CENTER.Y)
	return m
end

--- 부지 로컬 가운데(center)·크기로 파트. 기본은 고정·충돌 없음·레이 안 맞음
local function part(parent: Instance, name: string, pivot: CFrame, center: Vector3, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = pivot * CFrame.new(center)
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = not lowSpec
	p.Parent = parent
	return p
end

local function addWindows(p: BasePart, width: number)
	if lowSpec or PropAssets.WINDOW_TEXTURE.id <= 0 then
		return
	end
	local tileU, offsetV = PropAssets.windowTile(width, WALL_H)
	local t = Instance.new("Texture")
	t.Name = "Windows"
	t.Texture = "rbxassetid://" .. PropAssets.WINDOW_TEXTURE.id
	t.Face = Enum.NormalId.Back -- +Z = 남쪽(교문 쪽)
	t.StudsPerTileU = tileU
	t.StudsPerTileV = PropAssets.WINDOW_TEXTURE.studsPerTile.Y
	t.OffsetStudsV = offsetV
	t.Parent = p
end

local function addSign(p: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	gui.MaxDistance = GUI_MAX_DISTANCE
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = WorldPalette.lightText
	label.TextStrokeColor3 = WorldPalette.darkText
	label.TextStrokeTransparency = 0
	label.Parent = gui
end

--- n층 외관. stage 0 실루엣, 1~3 뼈대, 4 완공(+띠·간판)
local function buildFloor(
	pivot: CFrame,
	key: string,
	n: number,
	room: RoomConfig.Room,
	stage: number,
	isNear: boolean
): Model
	local m = newModel(pivot, n, key)
	local bottom = RoomConfig.floorY(n)
	local boxCenter = Vector3.new(FOOT_CENTER.X, bottom + WALL_H / 2, FOOT_CENTER.Y)
	local boxSize = Vector3.new(LONG_LEN, WALL_H, DEPTH)
	if stage == 0 then
		local ghost = part(m, "Ghost", pivot, boxCenter, boxSize, WorldPalette.ghost)
		ghost.Transparency = GHOST
		ghost.CastShadow = false
	elseif not isNear then
		local block = part(m, "Block", pivot, boxCenter, boxSize, room.wall)
		block.CanQuery = true
		addWindows(block, LONG_LEN)
	else
		for _, spec in WALLS do
			local name, c, s = spec.name, spec.c, spec.s
			local wall = part(
				m,
				name,
				pivot,
				Vector3.new(c.X, bottom + WALL_H / 2, c.Y),
				Vector3.new(s.X, WALL_H, s.Y),
				room.wall
			)
			wall.CanCollide = true -- 내 캐릭터가 층 밖으로 걸어 나가지 않게(클라 물리)
			wall.CanQuery = true -- 가림 페이드 레이
			if name == "WallS" then
				addWindows(wall, LONG_LEN)
			end
		end
	end
	if stage >= RoomConfig.PARTS and isNear then
		local band = part(
			m,
			"Band",
			pivot,
			Vector3.new(FOOT_CENTER.X, bottom + WALL_H - BAND_H / 2 - 0.5, FOOT.z1 + 0.2),
			Vector3.new(LONG_LEN + 0.4, BAND_H, 0.4),
			room.accent
		)
		band.CanQuery = true
		addSign(band, string.format(SIGN_FORMAT, room.icon, n, room.name))
	end
	return m
end

--- 옥상: 엘리베이터 기둥 + 깃발 + 난간(가까운 부지만)
local function buildRoof(pivot: CFrame, roofN: number, rank: number, isNear: boolean): Model
	local m = newModel(pivot, roofN, "Roof")
	local y0 = RoomConfig.floorY(RoomConfig.FIRST_FLOOR)
	local y1 = RoomConfig.floorY(roofN) + PILLAR_ABOVE
	local pillar = part(
		m,
		"Pillar",
		pivot,
		Vector3.new(FOOT.x1, (y0 + y1) / 2, FOOT.z0),
		Vector3.new(PILLAR, y1 - y0, PILLAR),
		WorldPalette.stone
	)
	pillar.CanQuery = true
	part(
		m,
		"Pole",
		pivot,
		Vector3.new(FOOT.x1, y1 + POLE_H / 2, FOOT.z0),
		Vector3.new(0.4, POLE_H, 0.4),
		WorldPalette.pole
	)
	part(
		m,
		"Flag",
		pivot,
		Vector3.new(FOOT.x1 - FLAG_SIZE.X / 2 - 0.2, y1 + POLE_H - FLAG_SIZE.Y / 2, FOOT.z0),
		FLAG_SIZE,
		RANK_COLORS[rank] or WorldPalette.flag
	)
	if isNear then
		local y = RoomConfig.floorY(roofN) + RAIL_H / 2
		for _, spec in WALLS do
			local name, c, s = spec.name, spec.c, spec.s
			part(m, "Rail" .. name, pivot, Vector3.new(c.X, y, c.Y), Vector3.new(s.X, RAIL_H, s.Y), WorldPalette.trim)
		end
	end
	return m
end

--- n층 엘리베이터 문. 뒤 상자 1 + 문틀 3(간판·층 표시등 SurfaceGui) + 문 2 + 문턱 1 + 호출 버튼 2 = 9 파트.
--- 벽에 등을 댄다(PlotLayout.elevatorFacing). 아래 좌표는 타는 곳 바닥 가운데에서 문이 보는 쪽이 +Z 인 틀 기준
local function buildElevator(pivot: CFrame, n: number, label: string): Model
	local m = newModel(pivot, n, `E{n}`)
	local spot = if n <= 1
		then PlotLayout.ELEVATOR_F1
		elseif n == 2 then PlotLayout.ELEVATOR_F2
		else Vector3.new(PlotLayout.ELEVATOR_XZ.X, RoomConfig.floorY(n), PlotLayout.ELEVATOR_XZ.Y)
	local frame = pivot * CFrame.lookAlong(spot, -PlotLayout.elevatorFacing(n))
	local x, y = 0, 0
	local zf = -PlotLayout.ELEVATOR_BACK + ELEV_D -- 문틀 뒷면 = 뒤 상자 앞면(타는 곳 4×4 칸 끝에서 문틀 두께만큼 뒤)
	local zm = zf + FACADE_T / 2
	local side = (ELEV_W - OPEN_W) / 2
	local frameColor = WorldPalette.gateBeam

	local box = part(
		m,
		"Box",
		frame,
		Vector3.new(x, y + ELEV_H / 2, zf - ELEV_D / 2),
		Vector3.new(ELEV_W, ELEV_H, ELEV_D),
		WorldPalette.trim
	)
	box.CanCollide = true
	box.CanQuery = true -- 가림 페이드 레이(벽과 같다)
	for i, dx in { -1, 1 } do
		part(
			m,
			if i == 1 then "FrameW" else "FrameE",
			frame,
			Vector3.new(x + dx * (OPEN_W + side) / 2, y + OPEN_H / 2, zm),
			Vector3.new(side, OPEN_H, FACADE_T),
			frameColor
		)
		-- 문 한 짝. 위·아래를 살짝 띄워 문틀·문턱과 면이 겹치지 않게
		local doorH = OPEN_H - 0.12 - 0.05
		local door = part(
			m,
			if i == 1 then "DoorW" else "DoorE",
			frame,
			Vector3.new(x + dx * OPEN_W / 4, y + 0.12 + doorH / 2, zf + 0.15),
			Vector3.new(OPEN_W / 2 - 0.04, doorH, 0.2),
			DOOR_STEEL
		)
		door.Material = Enum.Material.Metal
		door:SetAttribute(ATTR_CLOSED, door.CFrame)
		door:SetAttribute(ATTR_SIDE, dx)
	end
	local header = part(
		m,
		"Header",
		frame,
		Vector3.new(x, y + (OPEN_H + ELEV_H) / 2, zm),
		Vector3.new(ELEV_W, ELEV_H - OPEN_H, FACADE_T),
		frameColor
	)
	-- 문턱: 방 안 마루(윗면 +0.07)보다 높게
	local sill = part(
		m,
		"Sill",
		frame,
		Vector3.new(x, y + 0.06, zf + 0.4),
		Vector3.new(OPEN_W + 0.4, 0.12, 0.8),
		WorldPalette.lampIron
	)
	sill.Material = Enum.Material.Metal
	-- 호출 버튼(문 앞에서 봐서 오른쪽 문틀 앞면, 저학년 손 높이)
	local bx = x + (OPEN_W + side) / 2
	part(m, "CallPlate", frame, Vector3.new(bx, y + 3.4, zf + FACADE_T + 0.04), Vector3.new(0.5, 1, 0.08), DOOR_STEEL)
	local button = part(
		m,
		"CallButton",
		frame,
		Vector3.new(bx, y + 3.4, zf + FACADE_T + 0.12),
		Vector3.new(0.1, 0.36, 0.36),
		WorldPalette.lampGlow
	)
	button.Shape = Enum.PartType.Cylinder
	button.Material = Enum.Material.Neon
	button.CFrame *= CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 앞(Z)으로

	-- 간판 「엘리베이터」 + 층 표시등
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Back -- +Z = 문 앞(타는 곳 쪽)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ELEV_PIXELS_PER_STUD
	gui.MaxDistance = GUI_MAX_DISTANCE
	gui.Parent = header
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.06)
	title.Size = UDim2.fromScale(0.9, 0.44)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Text = "엘리베이터"
	title.TextColor3 = WorldPalette.lightText
	title.Parent = gui
	local led = Instance.new("TextLabel")
	led.AnchorPoint = Vector2.new(0.5, 0)
	led.Position = UDim2.fromScale(0.5, 0.56)
	led.Size = UDim2.fromScale(0.5, 0.36)
	led.BackgroundColor3 = WorldPalette.boardDark
	led.Font = Enum.Font.GothamBold
	led.TextScaled = true
	led.Text = `▲▼ {label}`
	led.TextColor3 = WorldPalette.lampGlow
	led.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = led

	-- 서버 프롬프트 자리(앵커 가운데·바닥판 Attachment 모두 바닥 + 3)
	m:SetAttribute(ATTR_SPOT, (frame * CFrame.new(0, 3, 0)).Position)
	return m
end

--- 엘리베이터 프롬프트가 뜨면 그 타는 곳 문을 열고, 사라지면 닫는다(내 화면만)
local function slideDoors(prompt: ProximityPrompt, open: boolean)
	if prompt.Name ~= Keys.ELEVATOR_PROMPT then
		return
	end
	local at = prompt.Parent
	local pos = if at and at:IsA("Attachment")
		then at.WorldPosition
		elseif at and at:IsA("BasePart") then at.Position
		else nil
	if not pos then
		return
	end
	for _, entry in rendered do
		for _, node in entry.nodes do
			local spot = node:GetAttribute(ATTR_SPOT)
			if typeof(spot) == "Vector3" and (spot - pos).Magnitude <= SPOT_MATCH then
				for _, door in node:GetChildren() do
					local closed, dx = door:GetAttribute(ATTR_CLOSED), door:GetAttribute(ATTR_SIDE)
					if door:IsA("BasePart") and typeof(closed) == "CFrame" and type(dx) == "number" then
						local goal = if open then closed * CFrame.new(dx * DOOR_SLIDE, 0, 0) else closed
						TweenService:Create(door, TweenInfo.new(DOOR_SECONDS, Enum.EasingStyle.Quad), { CFrame = goal })
							:Play()
					end
				end
			end
		end
	end
end

local function meshReady(asset: PropAssets.MeshAsset): boolean
	return MeshCache.get(asset) ~= nil
end

--- 레시피 put. origin = 방 로컬 원점(월드). 만든 파트 수는 두 번째 반환 함수로
local function recipePut(m: Model, origin: CFrame): (Rooms.Put, () -> number)
	local count = 0
	local function put(name: string, size: Vector3, pos: Vector3, color: Color3, opts: Rooms.PutOpts?): BasePart
		count += 1
		local o: Rooms.PutOpts = opts or {}
		local mesh = if o.mesh then MeshCache.get(o.mesh) else nil
		local p: BasePart
		if mesh then
			p = mesh:Clone()
		else
			local plain = Instance.new("Part")
			plain.Shape = o.shape or Enum.PartType.Block
			plain.TopSurface = Enum.SurfaceType.Smooth
			plain.BottomSurface = Enum.SurfaceType.Smooth
			p = plain
		end
		p.Name = name
		p.Size = size
		p.CFrame = origin * CFrame.new(pos) * (o.rot or CFrame.identity)
		p.Color = color
		p.Material = o.material or Enum.Material.SmoothPlastic
		p.Transparency = o.transparency or 0
		p.Anchored = true
		p.CanCollide = o.collide == true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = m
		return p
	end
	return put, function()
		return count
	end
end

--- 레시피를 부품 단계까지(2 = big, 3 = +props, 4 = +finish). 만든 파트 수를 돌려준다
local function runRecipe(m: Model, origin: CFrame, room: RoomConfig.Room, n: number, stage: number): number
	local put, count = recipePut(m, origin)
	local recipe = Rooms.get(room.id)
	local ctx = { room = room, floor = n, ready = meshReady }
	if stage >= 2 then
		recipe.big(put, ctx)
	end
	if stage >= 3 then
		recipe.props(put, ctx)
	end
	if stage >= RoomConfig.PARTS then
		recipe.finish(put, ctx)
	end
	return count()
end

--- 옥상 방(자기 구역 안). 머리말 R{id}
local function buildRoofRoom(pivot: CFrame, roofN: number, room: RoomConfig.Room, stage: number, isNear: boolean): Model
	local m = newModel(pivot, roofN, "R" .. room.id)
	local o = RoomConfig.origin(roofN)
	local z = Rooms.Kit.zone(room)
	local zc = Vector3.new((z.x0 + z.x1) / 2, 0, (z.z0 + z.z1) / 2)
	local zs = Vector3.new(z.x1 - z.x0, 0, z.z1 - z.z0)
	local done = stage >= RoomConfig.PARTS
	if stage <= 1 then
		local h = Rooms.Kit.SIT_DESK
		local box =
			part(m, "Ghost", pivot, o + zc + Vector3.new(0, h / 2, 0), zs + Vector3.new(0, h, 0), WorldPalette.ghost)
		box.Transparency = GHOST
		box.CastShadow = false
		if stage == 1 then
			box.Color = room.wall
		end
	elseif isNear then
		local count = runRecipe(m, pivot * CFrame.new(o), room, roofN, stage)
		assert(count <= MAX_ROOF_PARTS, `TowerRender {room.id}: 옥상 방 {count}개 > {MAX_ROOF_PARTS}`)
		local sign = m:FindFirstChild("Sign")
		if done and sign and sign:IsA("BasePart") then
			addSign(sign, `{room.icon} {room.name}`)
		end
	else
		part(m, "Deck", pivot, o + zc + Vector3.new(0, DECK_H / 2, 0), zs + Vector3.new(0, DECK_H, 0), room.wall)
		-- 옥상 학생은 어디서나 보인다. 먼 부지에서도 허공에 앉지 않게 의자 하나(바닥판 위)
		local row = if done and room.student then StudentConfig.BY_ID[room.student] else nil
		local s = if row then room.seats[row.seat.index] else nil
		if s then
			local h = CharacterBuilder.SIT_HIP - 0.15 - DECK_H
			part(
				m,
				"Chair",
				pivot,
				o + s + Vector3.new(0, DECK_H + h / 2, 0.2),
				Vector3.new(2, h, 2),
				WorldPalette.wood
			)
		end
	end
	return m
end

--- 방 안. Rooms 레시피를 부품 단계까지(2 = big, 3 = +props, 4 = +finish)
local function buildInterior(pivot: CFrame, key: string, n: number, room: RoomConfig.Room, stage: number): Model
	local m = newModel(pivot, n, key)
	local count = runRecipe(m, pivot * CFrame.new(RoomConfig.origin(n)), room, n, stage)
	assert(count <= MAX_ROOM_PARTS, `TowerRender {room.id}: 방 안 {count}개 > {MAX_ROOM_PARTS}`)
	-- 천장등. 위층 바닥판이 그림자를 드리워 방 안이 Ambient 만으로는 새카맣다(BuildKit 천장등과 같은 색·밝기).
	-- 방 안은 캐릭터가 있는 층 ±1 만 그리니 켜지는 등도 그만큼뿐이다
	local lamp = part(
		m,
		"CeilingLight",
		pivot,
		RoomConfig.origin(n) + Vector3.new(0, WALL_H - 1, 0),
		Vector3.one,
		WorldPalette.stone
	)
	lamp.Transparency = 1
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 244, 226)
	light.Brightness = 1.2
	light.Range = 40
	light.Shadows = false
	light.Parent = lamp
	return m
end

-- ── 렌더 ─────────────────────────────────────────────────────────

local function pop(model: Model)
	-- 튀기는 동안 충돌 벽이 캐릭터를 쓸고 지나가 탑 밖으로 밀지 않게 잠깐 끈다
	local solid: { BasePart } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide then
			p.CanCollide = false
			table.insert(solid, p)
		end
	end
	local value = Instance.new("NumberValue")
	value.Value = POP_FROM
	model:ScaleTo(POP_FROM)
	value.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(v)
		end
	end)
	local tween =
		TweenService:Create(value, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Value = 1,
		})
	tween.Completed:Once(function()
		for _, p in solid do
			p.CanCollide = true
		end
		value:Destroy()
	end)
	tween:Play()
end

local function unrenderPlot(plotId: number)
	local entry = rendered[plotId]
	if entry then
		entry.folder:Destroy()
		rendered[plotId] = nil
	end
end

type Want = { sig: string, build: () -> Model }

--- 그 부지를 지금 어트리뷰트에 맞춘다. 서명이 바뀐 조각만 다시 짓는다
local function renderPlot(plotId: number)
	local root = fxRoot
	local st = readState(plotId)
	local pivot = plotPivot(plotId)
	if not root or not st or not pivot then
		unrenderPlot(plotId)
		return
	end
	local isNear = near[plotId] == true
	local lod = (if isNear then "n" else "f") .. (if lowSpec then "l" else "")
	local building, roofN = layout(st)
	local top = RoomConfig.topFloor(#st.floors)
	local want: { [string]: Want } = {}

	local function floorRoom(n: number): (RoomConfig.Room?, number)
		local id = RoomConfig.roomOfFloor(st.floors, n)
		if id then
			return RoomConfig.BY_ID[id], RoomConfig.PARTS
		elseif building and n == top + 1 then
			return building, st.parts
		end
		return nil, 0
	end

	for n = RoomConfig.FIRST_FLOOR, top + (if building then 1 else 0) do
		local room, stage = floorRoom(n)
		if room then
			local key = `F{n}`
			want[key] = {
				sig = `{room.id}|{stage}|{lod}`,
				build = function()
					return buildFloor(pivot, key, n, room, stage, isNear)
				end,
			}
		end
	end
	want.Roof = {
		sig = `{roofN}|{st.rank}|{lod}`,
		build = function()
			return buildRoof(pivot, roofN, st.rank, isNear)
		end,
	}
	local roofRooms: { [string]: number } = {}
	for _, id in st.rooftop do
		roofRooms[id] = RoomConfig.PARTS
	end
	local chosen = RoomConfig.BY_ID[st.room]
	if chosen and chosen.kind == "roof" then
		roofRooms[chosen.id] = st.parts
	end
	for id, stage in roofRooms do
		local room = RoomConfig.BY_ID[id] :: RoomConfig.Room -- fromCsv·BY_ID 로 이미 거른 id
		want["R" .. id] = {
			sig = `{roofN}|{stage}|{lod}|{meshVersion}`,
			build = function()
				return buildRoofRoom(pivot, roofN, room, stage, isNear)
			end,
		}
	end

	-- 엘리베이터 문: 가까운 부지는 1층(현관)·2층(강당)·옥상, 캐릭터가 선 부지는 그 층 ±1 도.
	-- 갈 수 있는 층에만 단다(짓는 층·옥상 방 없는 옥상은 없다)
	local stops: { [number]: boolean } = {}
	if isNear then
		stops[1], stops[2], stops[roofN] = true, true, true
	end
	if plotId == herePlot then
		for n = math.max(RoomConfig.FIRST_FLOOR, hereFloor - 1), hereFloor + 1 do
			stops[n] = true
		end
	end
	for n in stops do
		if not RoomConfig.canRide(n, #st.floors, #st.rooftop > 0, roofN) then
			stops[n] = nil
		end
	end
	for n in stops do
		local label = if n == roofN then "옥상" else `{n}층`
		want[`E{n}`] = {
			sig = `{label}|{lod}`,
			build = function()
				return buildElevator(pivot, n, label)
			end,
		}
	end

	-- 방 안: 캐릭터가 선 부지의 그 층 ±1(옥상은 R{id})
	if plotId == herePlot then
		for n = hereFloor - 1, math.min(hereFloor + 1, roofN - 1) do
			local room, stage = floorRoom(n)
			if room and stage >= 2 then
				local key = `I{n}`
				want[key] = {
					sig = `{room.id}|{stage}|{meshVersion}`,
					build = function()
						return buildInterior(pivot, key, n, room, stage)
					end,
				}
			end
		end
	end

	local entry = rendered[plotId]
	if not entry then
		local folder = Instance.new("Folder")
		folder.Name = Keys.plotName(plotId)
		folder.Parent = root
		entry = { folder = folder, sigs = {}, nodes = {} }
		rendered[plotId] = entry
	end
	local e = entry :: Entry
	for key, node in e.nodes do
		if not want[key] then
			node:Destroy()
			e.nodes[key] = nil
			e.sigs[key] = nil
		end
	end
	local rebuilt: { [string]: boolean } = {}
	for key, w in want do
		if e.sigs[key] ~= w.sig then
			rebuilt[key] = true
			local old = e.nodes[key]
			if old then
				old:Destroy()
			end
			local node = w.build()
			node.Parent = e.folder
			e.nodes[key] = node
			e.sigs[key] = w.sig
		end
	end
	local pending = popPending[plotId]
	if pending and rebuilt[pending] then
		popPending[plotId] = nil
		pop(e.nodes[pending])
	end
end

function renderAll()
	for plotId = 1, Keys.PLOT_COUNT do
		renderPlot(plotId)
	end
end

local function characterPosition(): Vector3?
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
end

--- 캐릭터가 선 탑 부지·층. 바뀌면 그 부지들의 방 안을 다시 맞춘다
local function updateHere()
	local pos = characterPosition()
	local plot: number?, floor = nil, 0
	if pos then
		for plotId = 1, Keys.PLOT_COUNT do
			local pivot = pivots[plotId]
			if pivot and rendered[plotId] then
				local p = pivot:PointToObjectSpace(pos)
				if p.X >= FOOT.x0 - 2 and p.X <= FOOT.x1 + 2 and p.Z >= FOOT.z0 - 2 and p.Z <= FOOT.z1 + 2 then
					plot = plotId
					floor = if p.Y < PlotLayout.TOWER_BASE_Y - 2
						then 2
						else RoomConfig.FIRST_FLOOR + math.floor(
							(p.Y - PlotLayout.TOWER_BASE_Y + 1) / PlotLayout.FLOOR_STEP
						)
					break
				end
			end
		end
	end
	if plot == herePlot and floor == hereFloor then
		return
	end
	local old = herePlot
	herePlot, hereFloor = plot, floor
	if old then
		renderPlot(old)
	end
	if plot and plot ~= old then
		renderPlot(plot)
	end
end

--- 내 부지 + 가까운 다른 부지로 채워 모두 NEAR_COUNT 개(DecorController 와 같은 규칙). 바뀐 부지만 다시 그린다
local function updateNear()
	local from = characterPosition()
	local cam = Workspace.CurrentCamera
	if not from and cam then
		from = cam.CFrame.Position
	end
	local order: { { id: number, score: number } } = {}
	for plotId = 1, Keys.PLOT_COUNT do
		local pivot = plotPivot(plotId)
		if pivot and from and plotId ~= myPlotId then
			local dist = (pivot.Position - from).Magnitude
			table.insert(
				order,
				{ id = plotId, score = if near[plotId] then dist - DecorConfig.NEAR_HYSTERESIS else dist }
			)
		end
	end
	table.sort(order, function(a, b)
		return a.score < b.score
	end)
	local want: { [number]: boolean } = {}
	local slots = DecorConfig.NEAR_COUNT
	if myPlotId then
		want[myPlotId] = true
		slots -= 1
	end
	for i = 1, math.min(slots, #order) do
		want[order[i].id] = true
	end
	for plotId = 1, Keys.PLOT_COUNT do
		if (want[plotId] == true) ~= (near[plotId] == true) then
			near[plotId] = want[plotId]
			renderPlot(plotId)
		elseif not rendered[plotId] then
			renderPlot(plotId) -- 부지 모델·상태가 늦게 온 부지
		end
	end
end

--- 페이드 레이 대상 = TowerFx + 각 부지 서버 Tower 폴더(바닥판·지붕 = 천장)
local function updateFadeFilter()
	local params, fx, plots = fadeParams, fxRoot, plotsFolder
	if not params or not fx or not plots then
		return
	end
	local list: { Instance } = { fx }
	for _, model in plots:GetChildren() do
		local tower = model:FindFirstChild(Keys.TOWER_FOLDER)
		if tower then
			table.insert(list, tower)
		end
	end
	params.FilterDescendantsInstances = list
end

-- ── 가림 페이드 ──────────────────────────────────────────────────

local function setFaded(p: BasePart, on: boolean)
	p.LocalTransparencyModifier = if on then FADE else 0
	for _, child in p:GetChildren() do
		if child:IsA("SurfaceGui") then
			child.Enabled = not on
		elseif child:IsA("Decal") then -- Texture 는 Decal 을 상속한다
			child.Transparency = if on then FADE else 0
		end
	end
end

local function updateFade()
	local params = fadeParams
	local cam = Workspace.CurrentCamera
	local target = characterPosition()
	local blocking: { [BasePart]: true } = {}
	if params and cam and target and next(rendered) ~= nil then
		local away = cam.CFrame.Position - target
		if away.Magnitude > FADE_STEP then
			-- Popper 가 당기기 전 자리(최대 줌)까지 닿게 쏜다(머리말 ★)
			local finish = target + away.Unit * math.max(away.Magnitude, player.CameraMaxZoomDistance)
			local origin = target
			for _ = 1, FADE_MAX_HITS do
				local toFinish = finish - origin
				if toFinish.Magnitude <= FADE_STEP then
					break
				end
				local hit = Workspace:Raycast(origin, toFinish, params)
				if not hit then
					break
				end
				local p = hit.Instance
				blocking[p] = true
				if not faded[p] then
					setFaded(p, true)
				end
				origin = hit.Position + toFinish.Unit * FADE_STEP
			end
		end
	end
	for p in faded do
		if not blocking[p] then
			if p.Parent then
				setFaded(p, false)
			end
			faded[p] = nil
		end
	end
	for p in blocking do
		faded[p] = true
	end
end

-- ── 부지 상태 구독 ───────────────────────────────────────────────

local WATCHED_ATTRS = {
	Keys.ATTR_FLOORS,
	Keys.ATTR_ROOFTOP,
	Keys.ATTR_TOWER_ROOM,
	Keys.ATTR_TOWER_PARTS,
	Keys.ATTR_RANK,
	Keys.ATTR_FACILITIES,
}

local function watchState(state: Instance)
	local plotId = Keys.plotIdOf(state.Name)
	if not plotId or watched[state] then
		return
	end
	watched[state] = true
	local id = plotId :: number
	local connections: { RBXScriptConnection } = {}
	for _, name in WATCHED_ATTRS do
		table.insert(
			connections,
			state:GetAttributeChangedSignal(name):Connect(function()
				renderPlot(id)
			end)
		)
	end
	state.Destroying:Once(function()
		for _, c in connections do
			c:Disconnect()
		end
		watched[state] = nil
	end)
	renderPlot(id)
end

-- ── 공개 API ─────────────────────────────────────────────────────

--- 연출 이벤트(init.client.luau 가 넘긴다). FloorPart·FloorBuilt 는 내 부지면 그 조각을 짧게 튀긴다.
--- 이벤트와 어트리뷰트 중 어느 쪽이 먼저 올지 모른다. 어트리뷰트가 이미 반영됐으면 지금, 아니면 그 조각을 다시 지을 때 튀긴다
function TowerRenderController.onEvent(kind: string, payload: any)
	if type(payload) ~= "table" or type(payload.plot) ~= "number" then
		return
	end
	local plotId = payload.plot :: number
	local key: string? = nil
	local ready = false
	if (kind == "FloorPart" or kind == "FloorBuilt") and plotId == myPlotId then
		local floor = payload.floor
		local k = if type(floor) == "number" and floor > 0 then `F{floor}` else "R" .. tostring(payload.room)
		key = k
		local st = readState(plotId)
		if st then
			ready = (type(floor) == "number" and RoomConfig.roomOfFloor(st.floors, floor) == payload.room)
				or table.find(st.rooftop, payload.room) ~= nil
				or (st.room == payload.room and type(payload.partIndex) == "number" and st.parts >= payload.partIndex)
		end
		if ready then
			popPending[plotId] = nil
		else
			popPending[plotId] = k
		end
	end
	renderPlot(plotId)
	local entry = rendered[plotId]
	if ready and key and entry and entry.nodes[key] then
		pop(entry.nodes[key])
	end
end

--- TowerFx 안 BasePart 수(성능 게이트)
function TowerRenderController.partCount(): number
	local fx = fxRoot
	local count = 0
	if fx then
		for _, node in fx:GetDescendants() do
			if node:IsA("BasePart") then
				count += 1
			end
		end
	end
	return count
end

function TowerRenderController.Start()
	if started then
		return
	end
	started = true

	local fx = Instance.new("Folder")
	fx.Name = "TowerFx"
	fx.Parent = Workspace
	fxRoot = fx

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { fx }
	fadeParams = params

	lowSpec = StudentRenderController.isLowSpec()
	local function readMyPlot()
		local v = player:GetAttribute(Keys.ATTR_PLOT)
		myPlotId = if type(v) == "number" then v else nil
	end
	readMyPlot()
	MeshCache.onReady(function()
		meshVersion += 1
		renderAll()
	end)
	player:GetAttributeChangedSignal(Keys.ATTR_PLOT):Connect(function()
		readMyPlot()
		updateNear()
	end)

	-- CameraController "CameraFade"(+2) 뒤에 돈다
	RunService:BindToRenderStep("TowerFade", Enum.RenderPriority.Camera.Value + 3, updateFade)

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		slideDoors(prompt, true)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		slideDoors(prompt, false)
	end)

	-- Plots·PlotState 는 서버 부팅 뒤 온다. Start 를 막지 않게 따로 기다린다
	task.spawn(function()
		plotsFolder = Workspace:WaitForChild(Keys.PLOTS_FOLDER)
		local states = ReplicatedStorage:WaitForChild(Keys.PLOT_STATE_FOLDER)
		stateRoot = states
		for _, child in states:GetChildren() do
			watchState(child)
		end
		states.ChildAdded:Connect(watchState)

		local tick = 0
		while true do
			-- 한 번 실패해도 루프가 죽지 않게
			local ok, err = pcall(function()
				if tick % NEAR_EVERY == 0 then
					-- 저사양 다이얼은 한 번 켜지면 꺼지지 않는다. 서명이 바뀌어 창 없이 다시 짓는다
					if not lowSpec and StudentRenderController.isLowSpec() then
						lowSpec = true
						renderAll()
					end
					updateNear()
					updateFadeFilter()
				end
				updateHere()
			end)
			if not ok then
				warn(`[TowerRender] {err}`)
			end
			tick += 1
			task.wait(TICK)
		end
	end)
end

return TowerRenderController
