--!strict
--[[
	TowerRenderController — 탑(3층~) 벽·엘리베이터 칸·기본 가구·층 번호를 그리는 클라이언트 렌더. 개선계획 §3.6 #6·#12·#15.

	역할
	  서버는 층마다 바닥판(FloorNN)·엘리베이터 앵커(ElevatorNN)만 둔다(Geometry/Tower.luau). 나머지 모양은 여기서
	  Workspace.TowerFx/PlotNN 아래 로컬 파트로 그린다. 층 수는 ReplicatedStorage.PlotState.PlotNN 의 TowerFloors,
	  강당 여부는 Facilities 어트리뷰트(모든 클라에 복제)로 읽는다. 층 번호 n = 3..2+TowerFloors.
	  강당이 없거나 TowerFloors 0 이면 아무것도 그리지 않는다. 리모트 구독은 없다(어트리뷰트 감시는 여기서,
	  FloorBuilt 는 init.client.luau 가 refresh 로 보조 호출).
	  부지마다 그린 층 수를 기억해 바뀐 층만 붙이거나 뗀다. 층 하나를 사면 새 층 한 벌만 짓고, 어트리뷰트와
	  FloorBuilt 가 둘 다 와도 두 번째는 할 일이 없다.

	렌더 규칙(수치는 전부 TowerConfig.RENDER)
	  층 n 마다 파트 6개(TowerConfig.CLIENT_PARTS_PER_FLOOR, 가구 모델을 1개로 센다):
	    벽 4   발자국 4변. 바깥 면 = 발자국 변, 안쪽으로 WALL_T. 바닥판 윗면(floorY(n) + LIFT)부터 WALL_H.
	           긴 벽(z0·z1)은 발자국 폭 전체, 짧은 벽(x0·x1)은 긴 벽 사이(모서리 겹침 없음). 색 colorOf(n).
	           CanCollide true(난간), CanTouch false, CanQuery true(가림 페이드 레이캐스트용. 꾸미기 탭은 DecorFx 만 본다).
	    칸 1   엘리베이터 칸(ELEVATOR, CELL×CELL) 북쪽(−Z) 변 뒤판 한 장. 동쪽 벽 안쪽 면까지. CanCollide false.
	    가구 1 DecorBuilder 모델(furnitureOf(n)) 을 furnitureCell() 칸 가운데, floorY(n) 에 놓는다(꾸미기와 같은 높이).
	  층 번호: 교문 쪽(NUMBER_FACE, +Z)을 보는 면 두 곳 — z1 벽 바깥 면, z0 벽 안쪽 면 — 에 SurfaceGui 큰 숫자
	           (흰 글씨·검정 테두리). 층 안에서 교문 쪽 카메라로 봐도 맞은편 벽에 숫자가 보인다. 파트가 아니다.
	  창: 벽마다 SurfaceGui 1개 안 Frame WINDOW_COLS 개(연한 하늘색). 저사양 다이얼이 켜지면 창을 떼고 새로 만들지 않는다.
	  SurfaceGui 는 모두 MaxDistance = GUI_MAX_DISTANCE. 저사양이면 벽 그림자(CastShadow)도 끈다.

	LOD
	  내 부지 + 캐릭터에서 가까운 다른 부지로 채워 모두 NEAR_COUNT 개만 그린다(DecorController.updateNear 와 같은
	  규칙, 1초 주기). 지금 그리는 부지는 거리에서 NEAR_HYSTERESIS 를 빼고 순위를 매겨 경계에서 매초 바뀌지 않는다.
	  밖 부지는 폴더를 지운다(서버 바닥판만 남는다). 부지 모델이 아직 없으면 건너뛰고 다음 주기에 다시 본다.

	가림 페이드(§3.6 #12)
	  RenderStep "TowerFade"(Camera + 3, CameraController "CameraFade" 는 +2)에서 내 HumanoidRootPart → 카메라 쪽으로
	  레이캐스트(Include TowerFx)를 맞은 곳 너머로 이어 가며, 맞은 파트 전부에 LocalTransparencyModifier = RENDER.FADE.
	  이전 프레임 목록에 있었는데 이번에 안 맞은 파트는 0 으로 되돌린다(CameraController.updateFade 와 같은 방식).
	  SurfaceGui(창·층 번호)는 LocalTransparencyModifier 를 따르지 않아 흐린 동안 Enabled false 로 숨긴다.
	  ★ Popper 와 함께 도는 법: 기본 카메라 Popper(Camera 우선순위, 이 스텝보다 먼저)는 CanCollide 이고 전체 투명도
	    < 0.25 인 파트를 가림막으로 보고 카메라를 그 앞으로 당긴다. 당겨진 카메라 → 캐릭터 레이는 벽을 지나지 않으므로
	    레이는 캐릭터에서 카메라 방향으로 max(지금 거리, CameraMaxZoomDistance) 까지 쏜다(당기기 전 자리까지 닿는다).
	    흐린 벽(LTM 0.88 → 전체 투명도 0.88)은 Popper 가림막이 아니라 다음 프레임부터 카메라가 제자리로 물러난다.
	    들어가는 첫 프레임 한 번만 당겨진다. 카메라 뒤쪽 벽까지 흐릴 수 있으나 화면 밖이라 보이지 않는다.

	게이트용 API: setEnabled(on)(끄면 전부 지움. 낙하 귀가 확인용), partCount(plotId), fadeStats().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DecorBuilder = require(ReplicatedStorage.Shared.DecorBuilder)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)

-- 형제 컨트롤러는 형태만 선언하고 any 로 받는다(DecorController 와 같은 방식)
type StudentRenderApi = {
	isLowSpec: () -> boolean,
}
local StudentRenderController = (require(script.Parent.StudentRenderController) :: any) :: StudentRenderApi

local TowerRenderController = {}

-- ── 수치(클라 루프 전용. 모양 수치는 TowerConfig.RENDER) ──
local LOD_INTERVAL = 1
local FADE_MAX_HITS = 8 -- 한 프레임에 이어 쏘는 레이 수 상한(벽 두 겹 × 층 여럿을 넉넉히)
local FADE_STEP = 0.01 -- 맞은 면 바로 안쪽에서 다시 쏜다(원점을 품은 파트는 레이에 안 맞는다)
local WINDOWS_NAME = "Windows"

local RENDER = TowerConfig.RENDER
local FOOT = PlotLayout.TOWER_FOOTPRINT
local FOOT_CENTER = Vector2.new((FOOT.x0 + FOOT.x1) / 2, (FOOT.z0 + FOOT.z1) / 2)
local LONG_LEN = FOOT.x1 - FOOT.x0 -- z0·z1 벽(x 방향)
local SHORT_LEN = FOOT.z1 - FOOT.z0 - RENDER.WALL_T * 2 -- x0·x1 벽(z 방향). 긴 벽 사이에 끼운다

type WallSpec = {
	name: string,
	center: Vector2, -- 부지 로컬 x·z
	size: Vector2, -- (x 폭, z 폭)
	outer: Enum.NormalId, -- 바깥 면
	inner: Enum.NormalId,
	cols: number,
}

-- 층마다 같은 벽 4장(높이만 층마다 다르다). 회전 없는 파트에서 −Z 면 = Front, +Z 면 = Back
local WALLS: { WallSpec } = {
	{
		name = "WallN",
		center = Vector2.new(FOOT_CENTER.X, FOOT.z0 + RENDER.WALL_T / 2),
		size = Vector2.new(LONG_LEN, RENDER.WALL_T),
		outer = Enum.NormalId.Front,
		inner = Enum.NormalId.Back,
		cols = RENDER.WINDOW_COLS.LONG,
	},
	{
		name = "WallS",
		center = Vector2.new(FOOT_CENTER.X, FOOT.z1 - RENDER.WALL_T / 2),
		size = Vector2.new(LONG_LEN, RENDER.WALL_T),
		outer = Enum.NormalId.Back,
		inner = Enum.NormalId.Front,
		cols = RENDER.WINDOW_COLS.LONG,
	},
	{
		name = "WallW",
		center = Vector2.new(FOOT.x0 + RENDER.WALL_T / 2, FOOT_CENTER.Y),
		size = Vector2.new(RENDER.WALL_T, SHORT_LEN),
		outer = Enum.NormalId.Left,
		inner = Enum.NormalId.Right,
		cols = RENDER.WINDOW_COLS.SHORT,
	},
	{
		name = "WallE",
		center = Vector2.new(FOOT.x1 - RENDER.WALL_T / 2, FOOT_CENTER.Y),
		size = Vector2.new(RENDER.WALL_T, SHORT_LEN),
		outer = Enum.NormalId.Right,
		inner = Enum.NormalId.Left,
		cols = RENDER.WINDOW_COLS.SHORT,
	},
}

-- 엘리베이터 칸 뒤판: 칸 북쪽 변(−Z)에 붙여 칸 안쪽으로 WALL_T. 칸 서쪽 변부터 동쪽 벽 안쪽 면까지
local SHAFT_X0 = PlotLayout.ELEVATOR.X - PlotLayout.CELL / 2
local SHAFT_X1 = FOOT.x1 - RENDER.WALL_T
local SHAFT_CENTER =
	Vector2.new((SHAFT_X0 + SHAFT_X1) / 2, PlotLayout.ELEVATOR.Y - PlotLayout.CELL / 2 + RENDER.WALL_T / 2)
local SHAFT_SIZE = Vector2.new(SHAFT_X1 - SHAFT_X0, RENDER.WALL_T)

local FURNITURE_AT = PlotLayout.cellCenter(TowerConfig.furnitureCell())

local player = Players.LocalPlayer
local started = false
local enabled = true
local fxRoot: Folder? = nil
local plotsFolder: Instance? = nil
local stateRoot: Instance? = nil
local myPlotId: number? = nil
local lowSpecShown = false -- 지금 그려진 창이 저사양 기준인가

-- 부지마다 그린 폴더와 그 안에 지은 층 수(FIRST_FLOOR 부터 연속)
type Rendered = { folder: Folder, floors: number }
local rendered: { [number]: Rendered } = {}
local near: { [number]: boolean } = {}
local missing: { [number]: boolean } = {} -- near 인데 부지 모델이 없어 못 그린 부지(다음 주기에 다시)
local pivots: { [number]: CFrame } = {}
local watchedStates: { [Instance]: { RBXScriptConnection } } = {}
local faded: { [BasePart]: true } = {}
local blocking: { [BasePart]: true } = {} -- updateFade 가 매 프레임 비워 다시 쓴다
local fadeParams: RaycastParams? = nil

-- ── 부지 읽기 ────────────────────────────────────────────────────

local function readMyPlot(): number?
	local value = player:GetAttribute(Keys.ATTR_PLOT)
	return if type(value) == "number" then value else nil
end

--- 부지 CFrame(PlotShell 이 WorldPivot 으로 둔다. 부지는 움직이지 않아 한 번만 읽는다)
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

local function stateFolder(plotId: number): Instance?
	local folder = stateRoot
	return if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
end

local function hasAuditorium(plotId: number): boolean
	local state = stateFolder(plotId)
	local csv = if state then state:GetAttribute(Keys.ATTR_FACILITIES) else nil
	if type(csv) ~= "string" then
		return false
	end
	return (FacilityConfig.fromCsv(csv) :: any).auditorium == true
end

--- 산 층 수(0..MAX-2 정수)
local function floorsOf(plotId: number): number
	local state = stateFolder(plotId)
	local value = if state then state:GetAttribute(Keys.ATTR_TOWER_FLOORS) else nil
	if type(value) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(value), 0, TowerConfig.MAX - TowerConfig.FIRST_FLOOR + 1)
end

-- ── 만들기 ───────────────────────────────────────────────────────

local function box(
	parent: Instance,
	name: string,
	pivot: CFrame,
	center: Vector2,
	bottom: number,
	size: Vector2,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(size.X, RENDER.WALL_H, size.Y)
	part.CFrame = pivot * CFrame.new(center.X, bottom + RENDER.WALL_H / 2, center.Y)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = not lowSpecShown
	part.Parent = parent
	return part
end

local function surface(
	part: BasePart,
	name: string,
	face: Enum.NormalId,
	zOffset: number,
	pixelsPerStud: number
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.MaxDistance = RENDER.GUI_MAX_DISTANCE
	gui.AlwaysOnTop = false
	gui.ZOffset = zOffset
	gui.Parent = part
	return gui
end

local function addWindows(part: BasePart, face: Enum.NormalId, cols: number)
	local gui = surface(part, WINDOWS_NAME, face, 0, RENDER.WINDOW_PIXELS_PER_STUD)
	local rows = RENDER.WINDOW_ROWS
	local inset = RENDER.WINDOW_INSET
	for r = 1, rows do
		for c = 1, cols do
			local window = Instance.new("Frame")
			window.Name = `W{r}_{c}`
			window.BorderSizePixel = 0
			window.BackgroundColor3 = RENDER.WINDOW_COLOR
			window.Position = UDim2.fromScale((c - 1 + inset) / cols, (r - 1 + inset) / rows)
			window.Size = UDim2.fromScale((1 - inset * 2) / cols, (1 - inset * 2) / rows)
			window.Parent = gui
		end
	end
end

local function addNumber(part: BasePart, face: Enum.NormalId, n: number)
	local gui = surface(part, "Number", face, 1, RENDER.NUMBER_PIXELS_PER_STUD)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(n)
	label.TextSize = RENDER.NUMBER_SIZE
	label.TextColor3 = RENDER.NUMBER_COLOR
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = RENDER.NUMBER_STROKE_COLOR
	stroke.Thickness = RENDER.NUMBER_STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local function floorName(n: number): string
	return string.format("Floor%02d", n)
end

--- n층 한 벌: 벽 4 + 칸 뒤판 1 + 가구 모델 1
local function buildFloor(parent: Instance, pivot: CFrame, n: number, windows: boolean)
	local folder = Instance.new("Folder")
	folder.Name = floorName(n)
	local bottom = TowerConfig.floorY(n) + TowerConfig.LIFT -- 서버 바닥판 윗면
	local color = TowerConfig.colorOf(n)

	for _, spec in WALLS do
		local wall = box(folder, spec.name, pivot, spec.center, bottom, spec.size, color)
		wall.CanCollide = true -- 난간(자기 캐릭터 물리만 막는다. 서버 판정은 이 벽을 쓰지 않는다)
		if windows then
			addWindows(wall, spec.outer, spec.cols)
		end
		-- 교문 쪽을 보는 면 두 곳: z1 벽 바깥 면 + z0 벽 안쪽 면
		if spec.outer == RENDER.NUMBER_FACE or spec.inner == RENDER.NUMBER_FACE then
			addNumber(wall, RENDER.NUMBER_FACE, n)
		end
	end

	local shaft = box(folder, "Shaft", pivot, SHAFT_CENTER, bottom, SHAFT_SIZE, RENDER.SHAFT_COLOR)
	shaft.CanCollide = false

	local item = DecorConfig.BY_ID[TowerConfig.furnitureOf(n).id]
	if item then
		-- DecorBuilder 는 CanCollide·CanTouch·CanQuery 를 모두 끈 채 만든다
		local model =
			DecorBuilder.build(item, pivot * CFrame.new(FURNITURE_AT.X, TowerConfig.floorY(n), FURNITURE_AT.Y))
		model.Name = "Furniture"
		model.Parent = folder
	end

	folder.Parent = parent
end

-- ── 렌더 ─────────────────────────────────────────────────────────

--- 지울 파트를 페이드 목록에서 뺀다(파괴되면 되돌릴 필요가 없다)
local function forgetFaded(root: Instance)
	for part in faded do
		if part:IsDescendantOf(root) then
			faded[part] = nil
		end
	end
end

local function unrenderPlot(plotId: number)
	local entry = rendered[plotId]
	if not entry then
		return
	end
	forgetFaded(entry.folder)
	entry.folder:Destroy()
	rendered[plotId] = nil
end

local function newEntry(plotId: number, rootFolder: Folder): Rendered
	local folder = Instance.new("Folder")
	folder.Name = Keys.plotName(plotId)
	folder.Parent = rootFolder
	local entry: Rendered = { folder = folder, floors = 0 }
	rendered[plotId] = entry
	return entry
end

--- 그 부지를 지금 층 수에 맞춘다. 늘어난 층만 짓고 줄어든 층만 뗀다(같으면 아무것도 안 한다)
local function renderPlot(plotId: number)
	missing[plotId] = nil
	local rootFolder = fxRoot
	local floors = if hasAuditorium(plotId) then floorsOf(plotId) else 0
	if not enabled or not rootFolder or not near[plotId] or floors <= 0 then
		unrenderPlot(plotId)
		return
	end
	local pivot = plotPivot(plotId)
	if not pivot then
		unrenderPlot(plotId)
		missing[plotId] = true
		return
	end
	local entry = rendered[plotId] or newEntry(plotId, rootFolder)
	local first = TowerConfig.FIRST_FLOOR
	if floors < entry.floors then
		for n = first + floors, first + entry.floors - 1 do
			local floor = entry.folder:FindFirstChild(floorName(n))
			if floor then
				forgetFaded(floor)
				floor:Destroy()
			end
		end
	else
		local windows = not lowSpecShown
		for n = first + entry.floors, first + floors - 1 do
			buildFloor(entry.folder, pivot, n, windows)
		end
	end
	entry.floors = floors
end

local function renderAll()
	for plotId in near do
		renderPlot(plotId)
	end
end

--- 저사양으로 바뀌면 다시 짓지 않고 창 SurfaceGui 만 떼고 벽·칸 뒤판 그림자를 끈다
local function dropWindows()
	for _, entry in rendered do
		for _, node in entry.folder:GetDescendants() do
			if node:IsA("SurfaceGui") and node.Name == WINDOWS_NAME then
				node:Destroy()
			elseif node:IsA("Part") and node.Parent and node.Parent:IsA("Folder") then
				node.CastShadow = false -- 가구 모델 파트는 Model 아래라 건드리지 않는다
			end
		end
	end
end

--- 내 부지 + 가까운 다른 부지로 채워 모두 NEAR_COUNT 개(DecorController.updateNear 와 같은 규칙)
local function updateNear()
	if not enabled then
		return
	end
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local cam = Workspace.CurrentCamera
	local from: Vector3? = if hrp and hrp:IsA("BasePart") then hrp.Position elseif cam then cam.CFrame.Position else nil

	-- 지금 그리는 부지는 NEAR_HYSTERESIS 만큼 가깝게 친다(교체 이력)
	local order: { { id: number, score: number } } = {}
	for plotId = 1, Keys.PLOT_COUNT do
		local pivot = plotPivot(plotId)
		if pivot and from and plotId ~= myPlotId then
			local dist = (pivot.Position - from).Magnitude
			local score = if near[plotId] then dist - TowerConfig.NEAR_HYSTERESIS else dist
			table.insert(order, { id = plotId, score = score })
		end
	end
	table.sort(order, function(a, b)
		return a.score < b.score
	end)

	local want: { [number]: boolean } = {}
	local slots = TowerConfig.NEAR_COUNT
	if myPlotId then
		want[myPlotId] = true
		slots -= 1
	end
	for i = 1, math.min(slots, #order) do
		want[order[i].id] = true
	end

	for plotId in near do
		if not want[plotId] then
			near[plotId] = nil
			missing[plotId] = nil
			unrenderPlot(plotId)
		end
	end
	for plotId in want do
		if not near[plotId] or missing[plotId] then
			near[plotId] = true
			renderPlot(plotId)
		end
	end
end

-- ── 가림 페이드 ──────────────────────────────────────────────────

--- 흐림 켜기·끄기. SurfaceGui(창·층 번호)는 LocalTransparencyModifier 를 따르지 않아 같이 숨긴다
local function setFaded(part: BasePart, on: boolean)
	part.LocalTransparencyModifier = if on then RENDER.FADE else 0
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") then
			child.Enabled = not on
		end
	end
end

local function restoreFaded(keep: { [BasePart]: true })
	for part in faded do
		if not keep[part] then
			if part.Parent then
				setFaded(part, false)
			end
			faded[part] = nil
		end
	end
end

local function updateFade()
	-- 그린 탑도 흐린 벽도 없으면 할 일이 없다(초반·강당 없는 부지)
	if next(rendered) == nil and next(faded) == nil then
		return
	end
	table.clear(blocking)
	local params = fadeParams
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local cam = Workspace.CurrentCamera
	if enabled and params and cam and hrp and hrp:IsA("BasePart") then
		-- 캐릭터 → 카메라 쪽으로, Popper 가 당기기 전 자리(최대 줌)까지 닿게 쏜다(머리말 ★)
		local target = hrp.Position
		local away = cam.CFrame.Position - target
		if away.Magnitude > FADE_STEP then
			local reach = math.max(away.Magnitude, player.CameraMaxZoomDistance)
			local finish = target + away.Unit * reach
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
				local part = hit.Instance
				blocking[part] = true
				if not faded[part] then
					setFaded(part, true)
				end
				origin = hit.Position + toFinish.Unit * FADE_STEP
			end
		end
	end
	restoreFaded(blocking)
	for part in blocking do
		faded[part] = true
	end
end

-- ── 부지 상태 구독 ───────────────────────────────────────────────

local function watchState(state: Instance)
	if watchedStates[state] then
		return
	end
	local plotId = Keys.plotIdOf(state.Name)
	if not plotId then
		return
	end
	local function onChanged()
		if near[plotId] then
			renderPlot(plotId)
		end
	end
	local connections = {
		state:GetAttributeChangedSignal(Keys.ATTR_TOWER_FLOORS):Connect(onChanged),
		-- 강당이 생기거나 졸업으로 사라지면 탑이 나타나거나 없어진다
		state:GetAttributeChangedSignal(Keys.ATTR_FACILITIES):Connect(onChanged),
	}
	-- 폴더가 다시 만들어지면 옛 연결을 끊는다(새 폴더는 ChildAdded 로 다시 들어온다)
	table.insert(
		connections,
		state.Destroying:Connect(function()
			local list = watchedStates[state]
			if list then
				for _, connection in list do
					connection:Disconnect()
				end
			end
			watchedStates[state] = nil
		end)
	)
	watchedStates[state] = connections
	onChanged()
end

-- ── 공개 API ─────────────────────────────────────────────────────

--- 부지 하나(plotId) 또는 전부(nil)를 지금 층 수에 맞춘다(그린 층 수와 같으면 아무 일 없음). LOD 밖 부지도 아무 일 없음
function TowerRenderController.refresh(plotId: number?)
	if plotId == nil then
		renderAll()
	elseif type(plotId) == "number" and near[plotId] then
		renderPlot(plotId)
	end
end

--- 끄면 전부 지우고 페이드를 되돌린다(Studio 게이트: 벽 없이 낙하 귀가 확인). 켜면 다음 LOD 주기부터 다시 그린다
function TowerRenderController.setEnabled(on: boolean)
	if enabled == on then
		return
	end
	enabled = on
	if on then
		updateNear()
		return
	end
	restoreFaded({})
	for plotId in rendered do
		unrenderPlot(plotId)
	end
	table.clear(near)
	table.clear(missing)
end

--- 그 부지에 그려진 BasePart 수(게이트용. 가구 모델 파트까지 다 센다)
function TowerRenderController.partCount(plotId: number): number
	local entry = rendered[plotId]
	if not entry then
		return 0
	end
	local count = 0
	for _, node in entry.folder:GetDescendants() do
		if node:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

--- 지금 흐리게 만든 파트 수(게이트용)
function TowerRenderController.fadeStats(): { faded: number }
	local count = 0
	for _ in faded do
		count += 1
	end
	return { faded = count }
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

	lowSpecShown = StudentRenderController.isLowSpec()

	myPlotId = readMyPlot()
	player:GetAttributeChangedSignal(Keys.ATTR_PLOT):Connect(function()
		myPlotId = readMyPlot()
		updateNear()
	end)

	-- CameraController "CameraFade"(+2) 뒤에 돈다
	RunService:BindToRenderStep("TowerFade", Enum.RenderPriority.Camera.Value + 3, updateFade)

	-- Plots·PlotState 는 서버 부팅 뒤 온다. Start 를 막지 않게 따로 기다린다
	task.spawn(function()
		plotsFolder = Workspace:WaitForChild(Keys.PLOTS_FOLDER)
		local states = ReplicatedStorage:WaitForChild(Keys.PLOT_STATE_FOLDER)
		stateRoot = states
		for _, child in states:GetChildren() do
			watchState(child)
		end
		states.ChildAdded:Connect(watchState)

		while true do
			-- 한 번 실패해도 루프가 죽지 않게(Start 의 pcall 은 이 스레드를 감싸지 못한다)
			local ok, err = pcall(function()
				-- 저사양 다이얼은 한 번 켜지면 꺼지지 않는다. 켜지는 순간 창만 떼고 새 층부터는 창 없이 짓는다
				if not lowSpecShown and StudentRenderController.isLowSpec() then
					lowSpecShown = true
					dropWindows()
				end
				updateNear()
			end)
			if not ok then
				warn(`[TowerRender] LOD: {err}`)
			end
			task.wait(LOD_INTERVAL)
		end
	end)
end

return TowerRenderController
