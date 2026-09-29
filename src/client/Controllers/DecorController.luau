--!strict
--[[
	DecorController — 꾸미기 렌더·배치 조작(클라이언트). 개선계획 §3.5 #10·#10a·「실패했을 때 아이가 보는 것」, §3.6 #10.

	렌더
	  서버는 꾸미기 파트를 만들지 않는다. ReplicatedStorage.PlotState.PlotNN 의 Decor 어트리뷰트(DecorCodec 문자열)를
	  읽어 Workspace.DecorFx/PlotNN 아래 로컬 모델로 그린다. 부지 로컬 → 월드는 Plots.PlotNN 의 피벗(PlotShell 이
	  부지 CFrame 으로 둔다. 스트리밍과 무관하게 복제됨)으로 옮긴다. 모델 어트리뷰트 "Slot" = decorPlaced 순번.
	  1층 높이는 바닥 윗면 y0(운동장·복도가 지어졌으면 그 바닥 위), 3층부터는 TOWER_BASE_Y + (f-3) × FLOOR_STEP 이고
	  강당이 지어진 부지에서만 그린다.
	  LOD: 내 부지 + 캐릭터에서 가까운 부지 3개만 그린다(1초마다 다시 잰다). 나머지는 모델을 지운다.

	조작(주인만. W6 꾸미기 시트가 부른다)
	  beginPlace(itemId) / beginMove(slot) / cancel() / isActive().
	  고스트는 캐릭터가 바라보는 방향 앞 2칸(10 스터드)에 격자 스냅해 따라온다. 카메라는 피치 55° 로 고정.
	  ✓ → PlaceDecor·MoveDecor, ↻ → 90° 회전, ✕ → 끝, ↩(옮기기에서만) → StoreDecor.
	  ✓ 를 보내면 고스트를 숨기고 서버 확인(DecorPlaced·DecorStored 또는 Decor 어트리뷰트 변화)을 기다린다.
	  확인이 오면 모드를 끝낸다. 2초 안에 안 오면 고스트를 되살린다. Deny cell·limit·owned 면 0.2초 페이드 후 끝.
	  꾸미기 모드 안에서 내 부지의 놓인 물건을 탭하면 그 물건 옮기기로 넘어간다(모드 밖 탭은 무시).

	실패 표시(빨강·흔들림 없음)
	  서버와 같은 DecorGrid.canPlace 로 먼저 판정한다. 놓을 수 없으면 고스트 회색 + ✓ 흐림.
	  겹친 물건에는 노란 윤곽선이 1Hz 보다 느리게 깜빡이고, 40개가 차면 배치 수 막대가 가득 찬 채 천천히 깜빡인다.
	  흐린 ✓ 를 누르면 「뿅」(nudge) + 가장 가까운 놓을 수 있는 칸으로 0.2초 스르르 옮긴다(없으면 소리만).

	방문객: 남의 부지 꾸미기는 렌더만 한다. 탭·고스트는 내 부지 모델만 다룬다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DecorBuilder = require(ReplicatedStorage.Shared.DecorBuilder)
local DecorCodec = require(ReplicatedStorage.Shared.DecorCodec)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local DecorGrid = require(ReplicatedStorage.Shared.DecorGrid)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type DecorPlacement = Types.DecorPlacement

-- 형제 컨트롤러는 형태만 선언하고 any 로 받는다(PadController 와 같은 방식)
type HudApi = {
	profile: () -> Types.Profile?,
}
type CameraApi = {
	lockPitch: (deg: number, seconds: number) -> (),
	unlockPitch: (seconds: number) -> (),
}
type SoundApi = {
	play: (key: string, pitch: number?) -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local CameraController = (require(script.Parent.CameraController) :: any) :: CameraApi
local SoundController = (require(script.Parent.SoundController) :: any) :: SoundApi

local DecorController = {}

-- ── 수치(클라 연출 전용. 판정 수치는 DecorConfig·PlotLayout) ──
local GHOST_AHEAD = 10 -- 스터드. 캐릭터 앞 2칸
local PITCH_DEG = 55
local PITCH_SECONDS = 0.4
local LOD_INTERVAL = 1
local NEAR_COUNT = 3
local PENDING_TIMEOUT = 2
local NUDGE_SECONDS = 0.2
local FADE_SECONDS = 0.2
local BLINK_HALF = 0.6 -- 반 주기. 한 번 깜빡 1.2초(≤1Hz)
local HIGHLIGHT_OUTLINE = 0.4
local HIGHLIGHT_DIM = 0.9
local GHOST_BAD_TRANSPARENCY = 0.65
local GHOST_OUTLINE = 0.3
local TAP_DISTANCE = 500
local SOUND_NUDGE = "nudge"

-- ── 화면(812×375 기준 px, HudController 와 같은 UIScale 규칙) ──
local BASE_HEIGHT = 375
local SCALE_MIN = 0.9
local SCALE_MAX = 1.6
local MARGIN = 12
local GAP = 12
local SIZE_CONFIRM = 88
local SIZE_ROTATE = 72
local SIZE_CANCEL = 56
local SIZE_STORE = 40
local BAR_W = 168
local BAR_H = 8

local GLYPH_CONFIRM = "✓"
local GLYPH_ROTATE = "↻"
local GLYPH_CANCEL = "✕"
local GLYPH_STORE = "↩"

-- 색(기획서 §8.1). 빨강 없음
local PANEL = Color3.fromRGB(31, 41, 55)
local PANEL_ALPHA = 0.15
local GREEN = Color3.fromRGB(52, 211, 153)
local YELLOW = Color3.fromRGB(251, 191, 36)
local WHITE = Color3.fromRGB(255, 255, 255)
local TRACK = Color3.fromRGB(55, 65, 81)
local GREY = Color3.fromRGB(156, 163, 175)
local DIM_ALPHA = 0.6 -- 흐린 ✓ 배경 투명도

-- 서버 거부 중 고스트를 보관함으로 되돌리는 것(§3.5)
local RETURN_REASONS: { [string]: boolean } = { cell = true, limit = true, owned = true }

type PlotRender = {
	folder: Folder,
	models: { [number]: Model },
}

type GhostPart = { part: BasePart, color: Color3, transparency: number }

type Mode = {
	kind: "place" | "move",
	item: string,
	slot: number?, -- 옮기기면 원래 배치 순번
	rot: number,
	cx: number,
	cz: number,
	f: number,
	ok: boolean,
	reason: string,
	ghost: Model,
	parts: { GhostPart },
	outline: Highlight,
	evalKey: string?, -- 마지막으로 판정한 (칸·회전·층·배치 버전)
	pinned: { cx: number, cz: number, from: string }?, -- 뿅 이동한 칸. 따라갈 칸이 from 에서 바뀌면 푼다
	anim: { from: CFrame, to: CFrame, t0: number }?,
	pending: boolean,
	fading: boolean,
}

local player = Players.LocalPlayer
local started = false
local fxRoot: Folder? = nil
local plotsFolder: Instance? = nil
local stateRoot: Instance? = nil
local myPlotId: number? = nil

local rendered: { [number]: PlotRender } = {}
local near: { [number]: boolean } = {}
local placedCache: { [number]: { DecorPlacement } } = {}
local pivots: { [number]: CFrame } = {}
local watchedStates: { [Instance]: boolean } = {}
local placedVersion = 0 -- 내 부지 Decor 가 바뀔 때마다 +1

local mode: Mode? = nil
local modeToken = 0
local blockerLights: { [Model]: { light: Highlight, tween: Tween } } = {}
local hiddenJump: GuiObject? = nil

-- GUI
local gui: ScreenGui? = nil
local root: Frame
local rootScale: UIScale
local confirmButton: TextButton
local rotateButton: TextButton
local cancelButton: TextButton
local storeButton: TextButton
local bar: CanvasGroup
local barCells: { Frame } = {}
local barTween: Tween? = nil

-- ── 부지 읽기 ────────────────────────────────────────────────────

local function readMyPlot(): number?
	local value = player:GetAttribute(Keys.ATTR_PLOT)
	return if type(value) == "number" then value else nil
end

local function plotModel(plotId: number): Model?
	local folder = plotsFolder
	local model = if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
	return if model and model:IsA("Model") then model else nil
end

--- 부지 CFrame(PlotShell 이 WorldPivot 으로 둔다. 부지는 움직이지 않아 한 번만 읽는다)
local function plotPivot(plotId: number): CFrame?
	local known = pivots[plotId]
	if known then
		return known
	end
	local model = plotModel(plotId)
	if not model then
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

local function readPlaced(plotId: number): { DecorPlacement }
	local known = placedCache[plotId]
	if known then
		return known
	end
	local state = stateFolder(plotId)
	local raw = if state then state:GetAttribute(Keys.ATTR_DECOR) else nil
	local placed = if type(raw) == "string" and raw ~= "" then DecorCodec.decode(raw) else {}
	placedCache[plotId] = placed
	return placed
end

local function builtOf(plotId: number): { [string]: boolean }
	local state = stateFolder(plotId)
	local csv = if state then state:GetAttribute(Keys.ATTR_FACILITIES) else nil
	return if type(csv) == "string" then FacilityConfig.fromCsv(csv) :: any else {}
end

local function towerFloors(): number
	local profile = HudController.profile()
	local floors = if profile then profile.towerFloors else nil
	return if type(floors) == "number" then floors else 0
end

-- ── 좌표 ─────────────────────────────────────────────────────────

--- 회전을 반영한 발자국 칸 수
local function footSize(item: DecorConfig.Item, rot: number): (number, number)
	if rot % 2 == 1 then
		return item.d, item.w
	end
	return item.w, item.d
end

--- 발자국 가운데(부지 로컬 x·z)
local function footCenter(item: DecorConfig.Item, cx: number, cz: number, rot: number): Vector2
	local w, d = footSize(item, rot)
	local cell = PlotLayout.CELL
	return PlotLayout.cellCenter(cx, cz) + Vector2.new((w - 1) * cell / 2, (d - 1) * cell / 2)
end

--- 층 바닥 윗면(부지 로컬 y). 1층은 운동장·복도처럼 바닥 위에 깐 시설이 있으면 그 바닥 위
local function floorY(built: { [string]: boolean }, f: number, at: Vector2): number
	if f >= 3 then
		return PlotLayout.TOWER_BASE_Y + (f - 3) * PlotLayout.FLOOR_STEP
	end
	for _, zone in PlotLayout.STICKER_ZONES do
		local id = zone.facilityId
		local row = if id and built[id] then (FacilityConfig.BY_ID :: any)[id] else nil
		if row then
			local hx, hz = row.size.X / 2, row.size.Z / 2
			if math.abs(at.X - row.center.X) <= hx and math.abs(at.Y - row.center.Z) <= hz then
				return zone.floorY
			end
		end
	end
	return 0
end

local function worldCFrame(
	pivot: CFrame,
	built: { [string]: boolean },
	item: DecorConfig.Item,
	cx: number,
	cz: number,
	rot: number,
	f: number
): CFrame
	local center = footCenter(item, cx, cz, rot)
	local y = floorY(built, f, center)
	return pivot * CFrame.new(center.X, y, center.Y) * CFrame.Angles(0, rot * math.pi / 2, 0)
end

-- ── 렌더 ─────────────────────────────────────────────────────────

local function unrenderPlot(plotId: number)
	local entry = rendered[plotId]
	if not entry then
		return
	end
	for model in blockerLights do
		if model:IsDescendantOf(entry.folder) then
			blockerLights[model].tween:Cancel()
			blockerLights[model] = nil
		end
	end
	entry.folder:Destroy()
	rendered[plotId] = nil
end

local function applyHidden()
	local current = mode
	local mine = if myPlotId then rendered[myPlotId] else nil
	if not mine then
		return
	end
	for slot, model in mine.models do
		local hide = current ~= nil and current.kind == "move" and current.slot == slot
		model.Parent = if hide then nil else mine.folder
	end
end

local function renderPlot(plotId: number)
	unrenderPlot(plotId)
	local rootFolder = fxRoot
	if not rootFolder or not near[plotId] then
		return
	end
	local pivot = plotPivot(plotId)
	if not pivot then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Keys.plotName(plotId)
	local entry: PlotRender = { folder = folder, models = {} }
	local built = builtOf(plotId)
	local hasTower = built.auditorium == true
	local mine = plotId == myPlotId
	for slot, p in readPlaced(plotId) do
		local item = DecorConfig.byId(p.item)
		local f = p.f or 1
		if item and (f < 3 or hasTower) then
			local model = DecorBuilder.build(item, worldCFrame(pivot, built, item, p.cx, p.cz, p.rot, f))
			model:SetAttribute("Slot", slot)
			if mine then
				-- 탭으로 고르려면 레이캐스트에 잡혀야 한다. 충돌·터치는 계속 끔(§3.5 #10a)
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanQuery = true
					end
				end
			end
			model.Parent = folder
			entry.models[slot] = model
		end
	end
	folder.Parent = rootFolder
	rendered[plotId] = entry
	if mine then
		applyHidden()
	end
end

--- 내 부지 + 캐릭터에서 가까운 부지 NEAR_COUNT 개
local function updateNear()
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local cam = Workspace.CurrentCamera
	local from: Vector3? = if hrp and hrp:IsA("BasePart") then hrp.Position elseif cam then cam.CFrame.Position else nil

	local order: { { id: number, dist: number } } = {}
	for plotId = 1, Keys.PLOT_COUNT do
		local pivot = plotPivot(plotId)
		if pivot and from then
			table.insert(order, { id = plotId, dist = (pivot.Position - from).Magnitude })
		end
	end
	table.sort(order, function(a, b)
		return a.dist < b.dist
	end)

	local want: { [number]: boolean } = {}
	for i = 1, math.min(NEAR_COUNT, #order) do
		want[order[i].id] = true
	end
	if myPlotId then
		want[myPlotId] = true
	end

	for plotId in near do
		if not want[plotId] then
			near[plotId] = nil
			unrenderPlot(plotId)
		end
	end
	for plotId in want do
		if not near[plotId] then
			near[plotId] = true
			renderPlot(plotId)
		end
	end
end

-- ── GUI ──────────────────────────────────────────────────────────

local function tween(target: Instance, seconds: number, goal: { [string]: any }): Tween
	local t = TweenService:Create(target, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function blink(target: Instance, goal: { [string]: any }): Tween
	local t = TweenService:Create(
		target,
		TweenInfo.new(BLINK_HALF, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		goal
	)
	t:Play()
	return t
end

local function makeRoundButton(name: string, size: number, glyph: string, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = PANEL_ALPHA
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = math.floor(size * 0.5)
	button.TextColor3 = WHITE
	button.Text = glyph
	button.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

local function applyScale()
	local cam = Workspace.CurrentCamera
	local height = if cam then cam.ViewportSize.Y else BASE_HEIGHT
	local scale = math.clamp(height / BASE_HEIGHT, SCALE_MIN, SCALE_MAX)
	rootScale.Scale = scale
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

local function setBarBlink(on: boolean)
	local running = barTween
	if on then
		if not running then
			bar.GroupTransparency = 0
			barTween = blink(bar, { GroupTransparency = HIGHLIGHT_DIM - 0.3 })
		end
	elseif running then
		running:Cancel()
		barTween = nil
		bar.GroupTransparency = 0
	end
end

local function renderBar()
	if not gui then
		return
	end
	local count = if myPlotId then #readPlaced(myPlotId) else 0
	for i, cell in barCells do
		cell.BackgroundColor3 = if i <= count then GREEN else TRACK
	end
end

local function setConfirmEnabled(ok: boolean)
	confirmButton.BackgroundTransparency = if ok then PANEL_ALPHA else DIM_ALPHA
	confirmButton.BackgroundColor3 = if ok then GREEN else GREY
	confirmButton.TextTransparency = if ok then 0 else DIM_ALPHA
	confirmButton.AutoButtonColor = ok
end

--- 모바일 점프 버튼이 ✓ 자리(오른쪽 아래)와 겹친다. 꾸미기 동안만 숨긴다
local function jumpButton(): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	local touch = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
	local frame = if touch then touch:FindFirstChild("TouchControlFrame") else nil
	local jump = if frame then frame:FindFirstChild("JumpButton") else nil
	return if jump and jump:IsA("GuiObject") then jump else nil
end

local function showGui(kind: "place" | "move")
	local screen = gui
	if not screen then
		return
	end
	storeButton.Visible = kind == "move"
	renderBar()
	screen.Enabled = true
	if not hiddenJump then
		local jump = jumpButton()
		if jump and jump.Visible then
			jump.Visible = false
			hiddenJump = jump
		end
	end
end

local function hideGui()
	local screen = gui
	if screen then
		screen.Enabled = false
	end
	setBarBlink(false)
	local jump = hiddenJump
	if jump then
		jump.Visible = true
		hiddenJump = nil
	end
end

-- ── 막는 물건 윤곽선 ─────────────────────────────────────────────

local function setBlockers(slots: { number })
	local want: { [Model]: boolean } = {}
	local mine = if myPlotId then rendered[myPlotId] else nil
	if mine then
		for _, slot in slots do
			local model = mine.models[slot]
			if model and model.Parent then
				want[model] = true
			end
		end
	end
	for model, entry in blockerLights do
		if not want[model] then
			entry.tween:Cancel()
			entry.light:Destroy()
			blockerLights[model] = nil
		end
	end
	for model in want do
		if not blockerLights[model] then
			local light = Instance.new("Highlight")
			light.Name = "Blocker"
			light.FillTransparency = 1
			light.OutlineColor = YELLOW
			light.OutlineTransparency = HIGHLIGHT_OUTLINE
			light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			light.Parent = model
			blockerLights[model] = { light = light, tween = blink(light, { OutlineTransparency = HIGHLIGHT_DIM }) }
		end
	end
end

-- ── 고스트 ───────────────────────────────────────────────────────

local function makeGhost(item: DecorConfig.Item): (Model, { GhostPart }, Highlight)
	local ghost = DecorBuilder.build(item, CFrame.new(), { ghost = true })
	ghost.Name = "Ghost"
	local parts: { GhostPart } = {}
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, { part = part, color = part.Color, transparency = part.Transparency })
		end
	end
	-- 벽 뒤로 가려져도 윤곽은 보이게(§3.5 #10)
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = WHITE
	outline.OutlineTransparency = GHOST_OUTLINE
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = ghost
	ghost.Parent = fxRoot
	return ghost, parts, outline
end

local function paintGhost(current: Mode)
	for _, g in current.parts do
		g.part.Color = if current.ok then g.color else GREY
		g.part.Transparency = if current.ok then g.transparency else math.max(g.transparency, GHOST_BAD_TRANSPARENCY)
	end
end

--- 캐릭터 앞 GHOST_AHEAD 스터드를 발자국 가운데로 삼는 원점 칸. 부지 밖이면 inside = false
local function followCell(current: Mode, item: DecorConfig.Item): (number, number, number, boolean)
	local plotId = myPlotId
	local pivot = if plotId then plotPivot(plotId) else nil
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not pivot or not hrp or not hrp:IsA("BasePart") then
		return current.cx, current.cz, current.f, false
	end
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local ahead = if flat.Magnitude > 1e-3 then flat.Unit * GHOST_AHEAD else Vector3.zero
	local p = pivot:PointToObjectSpace(hrp.Position + ahead)
	local w, d = footSize(item, current.rot)
	local cell = PlotLayout.CELL
	local cx, cz = PlotLayout.cellOf(p.X - (w - 1) * cell / 2, p.Z - (d - 1) * cell / 2)
	cx = math.min(cx, PlotLayout.GRID - w)
	cz = math.min(cz, PlotLayout.GRID - d)
	local half = PlotLayout.PLOT_HALF
	local inside = math.abs(p.X) <= half and math.abs(p.Z) <= half
	return cx, cz, PlotLayout.floorOf(p.Y), inside
end

--- 지금 칸에서 서버와 같은 판정을 하고 고스트·✓·윤곽선·막대에 반영한다
local function evaluate(current: Mode, inside: boolean)
	local plotId = myPlotId
	if not plotId then
		return
	end
	local placed = readPlaced(plotId)
	local ok, reason = DecorGrid.canPlace(
		placed,
		towerFloors(),
		current.item,
		current.cx,
		current.cz,
		current.rot,
		current.f,
		current.slot
	)
	if not inside then
		ok, reason = false, "cell"
	end
	current.ok = ok
	current.reason = reason
	paintGhost(current)
	setConfirmEnabled(ok)
	-- 겹친 물건이 있으면 노란 윤곽(다른 이유면 빈 목록)
	if ok or not inside then
		setBlockers({})
	else
		setBlockers(
			DecorGrid.blockers(placed, current.f, current.cx, current.cz, current.rot, current.item, current.slot)
		)
	end
	setBarBlink(reason == "limit")
end

local function placeGhost(current: Mode, item: DecorConfig.Item)
	local plotId = myPlotId
	local pivot = if plotId then plotPivot(plotId) else nil
	if not plotId or not pivot then
		return
	end
	local cf = worldCFrame(pivot, builtOf(plotId), item, current.cx, current.cz, current.rot, current.f)
	local anim = current.anim
	if anim then
		anim.to = cf
	else
		current.ghost:PivotTo(cf)
	end
end

local function onHeartbeat()
	local current = mode
	if not current or current.pending or current.fading then
		return
	end
	local item = DecorConfig.byId(current.item)
	if not item then
		return
	end
	local cx, cz, f, inside = followCell(current, item)
	local followKey = `{cx},{cz},{f},{current.rot}`
	local pinned = current.pinned
	if pinned then
		if pinned.from == followKey then
			cx, cz = pinned.cx, pinned.cz
		else
			current.pinned = nil
		end
	end
	local key = `{cx},{cz},{f},{current.rot},{placedVersion},{towerFloors()},{inside}`
	if key ~= current.evalKey then
		current.evalKey = key
		current.cx, current.cz, current.f = cx, cz, f
		evaluate(current, inside)
		placeGhost(current, item)
	end
	local anim = current.anim
	if anim then
		local alpha = math.clamp((os.clock() - anim.t0) / NUDGE_SECONDS, 0, 1)
		current.ghost:PivotTo(anim.from:Lerp(anim.to, 1 - (1 - alpha) ^ 2))
		if alpha >= 1 then
			current.anim = nil
		end
	end
end

-- ── 모드 ─────────────────────────────────────────────────────────

local function fire(name: string, ...: any)
	local remote = (Remotes :: any)[name]
	if remote then
		remote:FireServer(...)
	else
		warn(`[Decor] 리모트 {name} 이 없음`)
	end
end

--- 고스트·윤곽선만 치운다. 카메라·GUI 는 그대로(다른 물건으로 바로 넘어갈 때)
local function teardown()
	local current = mode
	if not current then
		return
	end
	modeToken += 1
	mode = nil
	current.ghost:Destroy()
	setBlockers({})
	setBarBlink(false)
	applyHidden()
end

local function enter(kind: "place" | "move", itemId: string, slot: number?, rot: number)
	local item = DecorConfig.byId(itemId)
	if not item or not myPlotId or not fxRoot then
		return
	end
	local wasActive = mode ~= nil
	teardown()
	modeToken += 1
	local ghost, parts, outline = makeGhost(item)
	mode = {
		kind = kind,
		item = itemId,
		slot = slot,
		rot = rot,
		cx = 0,
		cz = 0,
		f = 1,
		ok = false,
		reason = "cell",
		ghost = ghost,
		parts = parts,
		outline = outline,
		evalKey = nil,
		pinned = nil,
		anim = nil,
		pending = false,
		fading = false,
	}
	applyHidden()
	showGui(kind)
	if not wasActive then
		CameraController.lockPitch(PITCH_DEG, PITCH_SECONDS)
	end
	onHeartbeat()
end

--- 흐린 ✓: 「뿅」 + 가장 가까운 놓을 수 있는 칸으로 0.2초
local function nudge(current: Mode)
	SoundController.play(SOUND_NUDGE)
	local plotId = myPlotId
	if not plotId or current.reason == "limit" then
		return
	end
	local nx, nz = DecorGrid.nearestFree(
		readPlaced(plotId),
		towerFloors(),
		current.item,
		current.cx,
		current.cz,
		current.rot,
		current.f,
		current.slot
	)
	if not nx or not nz then
		return
	end
	current.pinned = { cx = nx, cz = nz, from = `{current.cx},{current.cz},{current.f},{current.rot}` }
	current.anim = { from = current.ghost:GetPivot(), to = current.ghost:GetPivot(), t0 = os.clock() }
	current.evalKey = nil
	onHeartbeat()
end

--- 보낸 뒤 서버 확인을 기다린다. 2초 안에 안 오면 고스트를 되살린다
local function setPending(current: Mode)
	current.pending = true
	current.ghost.Parent = nil
	setBlockers({})
	local token = modeToken
	task.delay(PENDING_TIMEOUT, function()
		if modeToken == token and mode == current and current.pending then
			current.pending = false
			current.ghost.Parent = fxRoot
			current.evalKey = nil
		end
	end)
end

local function onConfirm()
	local current = mode
	if not current or current.pending or current.fading then
		return
	end
	if not current.ok then
		nudge(current)
		return
	end
	if current.kind == "place" then
		fire("PlaceDecor", current.item, current.cx, current.cz, current.rot, current.f)
	else
		fire("MoveDecor", current.slot, current.cx, current.cz, current.rot, current.f)
	end
	setPending(current)
end

local function onRotate()
	local current = mode
	if not current or current.pending or current.fading then
		return
	end
	current.rot = (current.rot + 1) % 4
	current.pinned = nil
	onHeartbeat()
end

local function onStore()
	local current = mode
	if not current or current.kind ~= "move" or current.pending or current.fading then
		return
	end
	fire("StoreDecor", current.slot)
	setPending(current)
end

--- 서버 거부: 고스트를 0.2초 페이드해 보관함으로 돌려보낸다
local function fadeBack(current: Mode)
	current.fading = true
	current.pending = false
	current.anim = nil
	current.ghost.Parent = fxRoot
	for _, g in current.parts do
		tween(g.part, FADE_SECONDS, { Transparency = 1 })
	end
	tween(current.outline, FADE_SECONDS, { OutlineTransparency = 1 })
	local token = modeToken
	task.delay(FADE_SECONDS, function()
		if modeToken == token then
			DecorController.cancel()
		end
	end)
end

-- ── 탭 ───────────────────────────────────────────────────────────

local function tapAt(position: Vector2)
	local current = mode
	local plotId = myPlotId
	if not current or current.pending or current.fading or not plotId then
		return
	end
	local mine = rendered[plotId]
	local cam = Workspace.CurrentCamera
	if not mine or not cam then
		return
	end
	local ray = cam:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { mine.folder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * TAP_DISTANCE, params)
	if not hit then
		return
	end
	local node: Instance? = hit.Instance
	while node and node ~= mine.folder do
		local slot = node:GetAttribute("Slot")
		if type(slot) == "number" then
			DecorController.onPlacedTapped(slot)
			return
		end
		node = node.Parent
	end
end

-- ── 부지 상태 구독 ───────────────────────────────────────────────

local function onStateChanged(plotId: number)
	placedCache[plotId] = nil
	if near[plotId] then
		renderPlot(plotId)
	end
	if plotId ~= myPlotId then
		return
	end
	placedVersion += 1
	renderBar()
	local current = mode
	if current and current.pending then
		DecorController.cancel()
	end
end

local function watchState(state: Instance)
	if watchedStates[state] then
		return
	end
	local plotId = Keys.plotIdOf(state.Name)
	if not plotId then
		return
	end
	watchedStates[state] = true
	state:GetAttributeChangedSignal(Keys.ATTR_DECOR):Connect(function()
		onStateChanged(plotId)
	end)
	-- 강당이 생기거나(3층 이상 그리기) 운동장·복도 바닥이 깔리면 높이가 바뀐다
	state:GetAttributeChangedSignal(Keys.ATTR_FACILITIES):Connect(function()
		if near[plotId] then
			renderPlot(plotId)
			-- 다시 지으면 노란 윤곽이 사라지므로 내 부지면 고스트 판정을 다시 한다
			local current = mode
			if current and plotId == myPlotId then
				current.evalKey = nil
			end
		end
	end)
	onStateChanged(plotId)
end

-- ── GUI 만들기 ───────────────────────────────────────────────────

local function buildGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "DecorGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 3
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false

	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Parent = screen
	rootScale = Instance.new("UIScale")
	rootScale.Parent = root

	-- 오른쪽 아래 1/3(812×375 기준 x ≥ 541, y ≥ 250) 안. 오른쪽부터 ✓ ↻ ✕, ✕ 위에 ↩, ✓·↻ 위에 막대
	local bottom = -MARGIN
	local xConfirm = -MARGIN
	local xRotate = xConfirm - SIZE_CONFIRM - GAP
	local xCancel = xRotate - SIZE_ROTATE - GAP
	confirmButton = makeRoundButton("Confirm", SIZE_CONFIRM, GLYPH_CONFIRM, UDim2.new(1, xConfirm, 1, bottom), GREEN)
	rotateButton = makeRoundButton("Rotate", SIZE_ROTATE, GLYPH_ROTATE, UDim2.new(1, xRotate, 1, bottom), PANEL)
	cancelButton = makeRoundButton("Cancel", SIZE_CANCEL, GLYPH_CANCEL, UDim2.new(1, xCancel, 1, bottom), PANEL)
	storeButton = makeRoundButton(
		"Store",
		SIZE_STORE,
		GLYPH_STORE,
		UDim2.new(1, xCancel - (SIZE_CANCEL - SIZE_STORE) / 2, 1, bottom - SIZE_CANCEL - 10),
		PANEL
	)

	-- 배치 수 막대(MAX_PLACED 칸)
	bar = Instance.new("CanvasGroup")
	bar.Name = "Count"
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, xConfirm, 1, bottom - SIZE_CONFIRM - 8)
	bar.Size = UDim2.fromOffset(BAR_W, BAR_H)
	bar.BackgroundTransparency = 1
	bar.Parent = root
	local max = DecorConfig.MAX_PLACED
	for i = 1, max do
		local cell = Instance.new("Frame")
		cell.Name = `C{i}`
		cell.Position = UDim2.fromScale((i - 1) / max, 0)
		cell.Size = UDim2.new(1 / max, -1, 1, 0)
		cell.BackgroundColor3 = TRACK
		cell.BorderSizePixel = 0
		cell.Parent = bar
		barCells[i] = cell
	end

	confirmButton.Activated:Connect(onConfirm)
	rotateButton.Activated:Connect(onRotate)
	cancelButton.Activated:Connect(function()
		DecorController.cancel()
	end)
	storeButton.Activated:Connect(onStore)

	applyScale()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
end

-- ── 공개 API ─────────────────────────────────────────────────────

--- 보관함의 itemId 를 놓기 시작한다(W6 시트)
function DecorController.beginPlace(itemId: string)
	enter("place", itemId, nil, 0)
end

--- 내 부지의 slot 번째 배치를 옮기기 시작한다
function DecorController.beginMove(slot: number)
	local plotId = myPlotId
	if not plotId then
		return
	end
	local p = readPlaced(plotId)[slot]
	if not p then
		return
	end
	enter("move", p.item, slot, p.rot)
end

--- 꾸미기 모드를 끝낸다. 카메라는 들어가기 전 각도로 0.4초에 돌아간다
function DecorController.cancel()
	if not mode then
		return
	end
	teardown()
	hideGui()
	CameraController.unlockPitch(PITCH_SECONDS)
end

function DecorController.isActive(): boolean
	return mode ~= nil
end

--- 꾸미기 모드에서 내 부지의 놓인 물건을 탭함 → 그 물건 옮기기. 모드 밖이면 아무 일 없음
function DecorController.onPlacedTapped(slot: number)
	local current = mode
	if not current or current.pending or current.fading then
		return
	end
	if current.kind == "move" and current.slot == slot then
		return
	end
	DecorController.beginMove(slot)
end

--- GameEvent(본인 수신): DecorPlaced·DecorStored·DecorBought·DecorReturned·Deny
function DecorController.onEvent(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local current = mode
	if not current then
		return
	end
	local kind = payload.kind
	if kind == "DecorPlaced" or kind == "DecorStored" then
		if current.pending then
			DecorController.cancel()
		end
	elseif kind == "Deny" then
		if current.pending and RETURN_REASONS[payload.reason] == true then
			fadeBack(current)
		end
	end
end

function DecorController.Start()
	if started then
		return
	end
	started = true

	local fx = Instance.new("Folder")
	fx.Name = "DecorFx"
	fx.Parent = Workspace
	fxRoot = fx

	buildGui()

	myPlotId = readMyPlot()
	player:GetAttributeChangedSignal(Keys.ATTR_PLOT):Connect(function()
		DecorController.cancel()
		local old = myPlotId
		myPlotId = readMyPlot()
		if old then
			renderPlot(old)
		end
		if myPlotId then
			placedCache[myPlotId] = nil
			renderPlot(myPlotId)
		end
		renderBar()
	end)
	player.CharacterRemoving:Connect(function()
		DecorController.cancel()
	end)

	RunService.Heartbeat:Connect(onHeartbeat)

	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
		if processed or #positions == 0 then
			return
		end
		tapAt(positions[1])
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		tapAt(Vector2.new(input.Position.X, input.Position.Y))
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

		while true do
			updateNear()
			task.wait(LOD_INTERVAL)
		end
	end)
end

return DecorController
