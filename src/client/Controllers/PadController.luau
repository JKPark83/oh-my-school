--!strict
--[[
	PadController — 월드 상호작용(클라이언트)

	서버가 만든 부지 인스턴스(Workspace.Plots.PlotNN)를 읽고 로컬 연출만 얹는다. 상태의 출처는 언제나 어트리뷰트다.
	- 구매 패드: PadState 로 보이기·색을 정하고, 내 부지의 활성 패드 위에 빌보드(이름·가격·진행 링)를 띄운다
	- 칭찬스티커: Collected 로 보이기를 정하고, 금 스티커엔 빛기둥. 3 스터드 안이면 먼저 숨기는 클라 예측(0.5초 안에
	  확정이 없으면 되돌림)
	- 칭찬스티커판: 내 부지 현관 벽 판의 SurfaceGui 에 60칸을 그리고 프로필 stickerBoard 만큼 채운다
	- 시설 등장: Built=true 모델이 들어오면 파트를 땅에서 솟게 한다(§9.2 구매 50ms 뒤 등장)
	- 스킨 팻말(🎨)·졸업 종(졸업하기)·접수대 ProximityPrompt → PanelController.open
	- 다른 부지의 접수대 프롬프트는 로컬에서 끄고, 「우리 학교로」 팻말 프롬프트는 반대로 내 부지에서만 끈다

	패드·스티커 파트는 서버가 Transparency 1 로 만들어 두므로(PlotShell) 여기서는 Transparency 를 직접 쓴다.
	클라가 바꾼 속성은 복제되지 않고, 서버는 이 속성을 다시 건드리지 않는다.
	스트리밍: 파트는 들어왔다 나가므로 ChildAdded/ChildRemoved 로만 붙잡는다. 모듈 최상위 부작용은 없다.
	이 모듈은 FeedbackController·TutorialController 를 require 하지 않는다(순환 방지). 위치 조회 API 만 내준다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)
local Types = require(ReplicatedStorage.Shared.Types)

-- 계획 §3.4 계약. 형제 컨트롤러는 다른 작업자가 쓰고 있어 형태만 선언하고 any 로 받는다
type HudApi = {
	profile: () -> Types.Profile?,
	onProfile: (fn: (Types.Profile) -> ()) -> (),
}
type PanelApi = {
	open: (name: string, payload: any?) -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local PanelController = (require(script.Parent.PanelController) :: any) :: PanelApi

local PadController = {}

local SKIN_ROLE_PRIMARY = "primary"

-- PadState 값(Keys.ATTR_PAD_STATE 주석과 서버 PlotService.refreshPads)
local PAD_ACTIVE = "active"
local PAD_NEXT = "next"
local PAD_BUILT = "built"

-- 패널 이름(계획 §3.4 PanelController.open)
local PANEL_SKIN = "skin"
local PANEL_GRADUATE = "graduate"
local PANEL_GACHA = "gacha"

-- 색(기획서 §8.1)
local COLOR_PANEL = Color3.fromRGB(31, 41, 55)
local COLOR_YELLOW = Color3.fromRGB(251, 191, 36)
local COLOR_GREEN = Color3.fromRGB(52, 211, 153)
local COLOR_GOLD = Color3.fromRGB(245, 158, 11)
local COLOR_GRAY = Color3.fromRGB(156, 163, 175)
local COLOR_WHITE = Color3.new(1, 1, 1)
local COLOR_BOARD_TEXT = Color3.fromRGB(74, 44, 20) -- 코르크 판 위 글자
local COLOR_BOARD_EMPTY = Color3.fromRGB(150, 110, 70) -- 빈 칸

-- 클라 전용 연출 수치(기획서 §8·§9). 공용 Config 에 없는 것만 둔다
local WAIT_TIMEOUT = 5
local BILLBOARD_DISTANCE = 120
local RING_DOTS = 20
local RING_RADIUS = 34 -- px
local RING_REFRESH = 1 -- 초
local PRICE_TEXT = 28 -- pt (§8.2)
local NAME_TEXT = 20
local TAP_SIZE = 56 -- px (§8.1 터치 최소)
local NEXT_PAD_ALPHA = 0.6
local PAD_SINK = 0.5 -- 스터드
local PAD_SINK_SECONDS = 0.2
local PICKUP_RADIUS = 3 -- 스터드
local PICKUP_REVERT = 0.5 -- 초
local POP_SCALE = 1.4
local POP_SECONDS = 0.12
local GOLD_POP_SCALE = 1.8
local GOLD_POP_SECONDS = 0.18
local PILLAR_HEIGHT = 12
local APPEAR_DROP = 6 -- 스터드
local APPEAR_SECONDS = 0.5
local APPEAR_STAGGER = 0.05
local APPEAR_DELAY = 0.05
local SKIN_SECONDS = 0.3
local SPARKLE_COUNT = 8
local HINT_COOLDOWN = 1
local HINT_SECONDS = 0.4
local SILHOUETTE_ALPHA = 0.7 -- 서버 PlotService.SILHOUETTE_TRANSPARENCY 와 같다
local SILHOUETTE_BLINK_ALPHA = 0.35
-- 스티커판 캔버스는 8×5 스터드 × 40px = 320×200px(PlotShell STICKER_BOARD_SIZE)
local BOARD_COLUMNS = 10 -- 10×6 = 60칸
local BOARD_CELL = 22 -- px
local BOARD_GAP = 4
local BOARD_POP_SECONDS = 0.15
local BOARD_FLASH_ALPHA = 0.3
local BOARD_FLASH_SECONDS = 0.3 -- §9.2 판 60 → 금색 플래시 0.3초

type Ring = {
	gui: BillboardGui,
	dots: { Frame },
	price: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	pulse: Tween?,
}

type PadEntry = {
	part: BasePart,
	plotId: number,
	facilityId: string,
	base: CFrame,
	baseColor: Color3,
	state: string,
	ring: Ring?,
	conns: { RBXScriptConnection },
}

type StickerEntry = {
	part: BasePart,
	plotId: number,
	id: string,
	baseColor: Color3,
	baseMaterial: Enum.Material,
	pillar: BasePart?,
	pendingAt: number?,
	hold: boolean, -- confirmSticker 뒤 Collected 가 올 때까지 숨긴 채 둔다
	conns: { RBXScriptConnection },
}

type FacilityEntry = {
	model: Model,
	plotId: number,
	facilityId: string,
	sign: BillboardGui?,
	bell: BillboardGui?,
	conns: { RBXScriptConnection },
}

type BoardEntry = {
	part: BasePart,
	root: Frame,
	dots: { Frame },
	title: TextLabel,
	flash: Frame,
	shown: number,
}

local player = Players.LocalPlayer
local started = false
local guiFolder: Folder? = nil -- PlayerGui 아래. 빌보드가 탭을 받으려면 여기 있어야 한다
local fxFolder: Folder? = nil -- Workspace 아래 로컬 파트(빛기둥·고스트)
local myPlotId: number? = nil
local plotModels: { [number]: Model } = {}
local plotConns: { [Model]: { RBXScriptConnection } } = {}
local pads: { [BasePart]: PadEntry } = {}
local stickers: { [BasePart]: StickerEntry } = {}
local facilities: { [Model]: FacilityEntry } = {}
local ringClock = 0
local lastHint = 0
local board: BoardEntry? = nil -- 내 부지 스티커판 하나만 그린다. 남의 판 칸 수는 클라가 모른다

-- ── 공통 헬퍼 ────────────────────────────────────────────────────

local function disconnectAll(conns: { RBXScriptConnection })
	for _, conn in conns do
		conn:Disconnect()
	end
	table.clear(conns)
end

local function readMyPlot(): number?
	local value = player:GetAttribute(Keys.ATTR_PLOT)
	return if type(value) == "number" then value else nil
end

local function plotIdOfModel(model: Instance): number?
	local value = model:GetAttribute(Keys.ATTR_PLOT_ID)
	if type(value) == "number" then
		return value
	end
	return Keys.plotIdOf(model.Name)
end

--- 인스턴스가 속한 부지 번호. Workspace.Plots 바로 아래 모델까지 올라간다
local function plotIdOfInstance(inst: Instance): number?
	local node: Instance? = inst
	while node do
		local parent = node.Parent
		if parent and parent.Name == Keys.PLOTS_FOLDER and parent.Parent == Workspace then
			return plotIdOfModel(node)
		end
		node = parent
	end
	return nil
end

local function isComplete(profile: Types.Profile?): boolean
	return profile ~= nil and FacilityConfig.count(profile.facilities) >= FacilityConfig.COUNT
end

local function newBillboard(name: string, adornee: Instance, width: number, height: number, lift: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(width, height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BILLBOARD_DISTANCE
	gui.ResetOnSpawn = false
	gui.Active = true
	gui.Parent = guiFolder
	return gui
end

local function newLabel(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextStrokeTransparency = 0.6
	label.Parent = parent
	return label
end

--- 56px 원형 탭 버튼 빌보드. 스킨 팻말·졸업 종에 쓴다
local function newTapButton(
	name: string,
	adornee: Instance,
	text: string,
	width: number,
	color: Color3
): (BillboardGui, TextButton)
	local gui = newBillboard(name, adornee, width, TAP_SIZE, 0)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 22
	button.TextColor3 = COLOR_WHITE
	button.Text = text
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, TAP_SIZE / 2)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_WHITE
	stroke.Thickness = 2
	stroke.Parent = button
	return gui, button
end

local function newLocalPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = fxFolder
	return part
end

--- 임시 파트에 파티클 하나 달아 n 개만 뿜고 치운다(Rate 0 + Emit)
local function sparkle(position: Vector3, count: number, color: Color3)
	local holder = newLocalPart("Sparkle", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color)
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

-- ── 구매 패드 ────────────────────────────────────────────────────

local function destroyRing(entry: PadEntry)
	local ring = entry.ring
	if not ring then
		return
	end
	if ring.pulse then
		ring.pulse:Cancel()
	end
	ring.gui:Destroy()
	entry.ring = nil
end

local function buildRing(entry: PadEntry): Ring
	local gui = newBillboard("Pad_" .. entry.facilityId, entry.part, 240, 96, 4)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = COLOR_PANEL
	root.BackgroundTransparency = 0.15
	root.BorderSizePixel = 0
	root.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_WHITE
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- 왼쪽: 점 20개로 그린 진행 링(회전 프레임은 ClipsDescendants 가 안 먹어 점으로 그린다)
	local ringFrame = Instance.new("Frame")
	ringFrame.Size = UDim2.fromOffset(84, 84)
	ringFrame.Position = UDim2.new(0, 6, 0.5, 0)
	ringFrame.AnchorPoint = Vector2.new(0, 0.5)
	ringFrame.BackgroundTransparency = 1
	ringFrame.Parent = root
	local dots: { Frame } = {}
	for i = 1, RING_DOTS do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(8, 8)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		local angle = -math.pi / 2 + (i - 1) / RING_DOTS * math.pi * 2
		dot.Position = UDim2.new(0.5, math.cos(angle) * RING_RADIUS, 0.5, math.sin(angle) * RING_RADIUS)
		dot.BackgroundColor3 = COLOR_GRAY
		dot.BackgroundTransparency = 0.6
		dot.BorderSizePixel = 0
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot
		dot.Parent = ringFrame
		dots[i] = dot
	end
	local coin = newLabel(ringFrame, "🪙", 24, COLOR_WHITE)
	coin.Size = UDim2.fromScale(1, 1)

	-- 오른쪽: 이름 위, 가격 아래
	local row = FacilityConfig.BY_ID[entry.facilityId]
	local name = newLabel(root, if row then row.name else entry.facilityId, NAME_TEXT, COLOR_WHITE)
	name.Position = UDim2.fromOffset(98, 10)
	name.Size = UDim2.new(1, -106, 0, 28)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local price = newLabel(root, "", PRICE_TEXT, COLOR_YELLOW)
	price.Position = UDim2.fromOffset(98, 44)
	price.Size = UDim2.new(1, -106, 0, 40)
	price.TextXAlignment = Enum.TextXAlignment.Left

	return { gui = gui, dots = dots, price = price, stroke = stroke, scale = scale, pulse = nil }
end

--- 진행 링 = 용돈 ÷ 가격. 살 수 있으면 초록으로 숨쉬기
local function updateRing(entry: PadEntry)
	local ring = entry.ring
	if not ring then
		return
	end
	local profile = HudController.profile()
	local graduations = if profile then profile.graduations else 0
	local coins = if profile then profile.coins else 0
	local price = FacilityConfig.priceOf(entry.facilityId, graduations)
	local ratio = if price > 0 then math.clamp(coins / price, 0, 1) else 1
	ring.price.Text = Format.coins(price)
	local lit = math.floor(ratio * RING_DOTS + 1e-6)
	for i, dot in ring.dots do
		local on = i <= lit
		dot.BackgroundColor3 = if on then COLOR_GREEN else COLOR_GRAY
		dot.BackgroundTransparency = if on then 0 else 0.6
	end
	local affordable = ratio >= 1
	if affordable and not ring.pulse then
		local info = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local pulse = TweenService:Create(ring.scale, info, { Scale = 1.08 })
		pulse:Play()
		ring.pulse = pulse
		ring.price.TextColor3 = COLOR_GREEN
	elseif not affordable and ring.pulse then
		ring.pulse:Cancel()
		ring.pulse = nil
		ring.scale.Scale = 1
		ring.price.TextColor3 = COLOR_YELLOW
	end
end

--- 활성 → 건설: 0.2초 가라앉은 뒤 숨기고 원래 자리로
local function sinkPad(entry: PadEntry)
	local part = entry.part
	local info = TweenInfo.new(PAD_SINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(part, info, { CFrame = entry.base - Vector3.new(0, PAD_SINK, 0) })
	tween.Completed:Once(function()
		part.Transparency = 1
		part.CFrame = entry.base
	end)
	tween:Play()
end

local function applyPad(entry: PadEntry)
	local part = entry.part
	local raw = part:GetAttribute(Keys.ATTR_PAD_STATE)
	local state = if type(raw) == "string" then raw else ""
	local previous = entry.state
	entry.state = state
	local mine = entry.plotId == myPlotId

	if state == PAD_ACTIVE then
		part.Transparency = 0
		part.Color = COLOR_GREEN
		if mine then
			if not entry.ring then
				entry.ring = buildRing(entry)
			end
			updateRing(entry)
		else
			destroyRing(entry)
		end
		return
	end

	destroyRing(entry)
	if state == PAD_NEXT then
		part.Transparency = NEXT_PAD_ALPHA
		part.Color = COLOR_GRAY
	elseif previous == PAD_ACTIVE and state == PAD_BUILT then
		part.Color = entry.baseColor
		sinkPad(entry)
	else
		part.Transparency = 1
		part.Color = entry.baseColor
	end
end

local function unwatchPad(part: Instance)
	local entry = pads[part :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns)
	destroyRing(entry)
	pads[part :: any] = nil
end

local function watchPad(part: Instance, plotId: number)
	if not part:IsA("BasePart") or pads[part] then
		return
	end
	local facilityId = part:GetAttribute(Keys.ATTR_FACILITY_ID)
	local entry: PadEntry = {
		part = part,
		plotId = plotId,
		facilityId = if type(facilityId) == "string" then facilityId else part.Name,
		base = part.CFrame,
		baseColor = part.Color,
		state = "",
		ring = nil,
		conns = {},
	}
	pads[part] = entry
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_PAD_STATE):Connect(function()
			applyPad(entry)
		end)
	)
	applyPad(entry)
end

-- ── 칭찬스티커 ───────────────────────────────────────────────────

local function destroyPillar(entry: StickerEntry)
	if entry.pillar then
		entry.pillar:Destroy()
		entry.pillar = nil
	end
end

local function applySticker(entry: StickerEntry)
	local part = entry.part
	local collected = part:GetAttribute(Keys.ATTR_COLLECTED) == true
	local gold = part:GetAttribute(Keys.ATTR_GOLD) == true
	local hidden = collected or entry.pendingAt ~= nil or entry.hold
	if hidden then
		part.Transparency = 1
		destroyPillar(entry)
		return
	end
	part.Transparency = 0
	part.Color = if gold then COLOR_GOLD else entry.baseColor
	part.Material = if gold then Enum.Material.Neon else entry.baseMaterial
	if gold then
		if not entry.pillar then
			local cframe = CFrame.new(part.Position + Vector3.new(0, PILLAR_HEIGHT / 2, 0))
			local pillar = newLocalPart("GoldPillar", Vector3.new(0.6, PILLAR_HEIGHT, 0.6), cframe, COLOR_GOLD)
			pillar.Transparency = 0.6
			entry.pillar = pillar
		end
	else
		destroyPillar(entry)
	end
end

--- 줍는 순간의 스케일 팝. 원본은 손대지 않고 로컬 복제본을 키웠다 지운다
local function popGhost(part: BasePart, gold: boolean)
	local ghost = part:Clone()
	for _, tag in CollectionService:GetTags(ghost) do
		CollectionService:RemoveTag(ghost, tag)
	end
	for name in ghost:GetAttributes() do
		ghost:SetAttribute(name, nil)
	end
	ghost.Name = "StickerGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Transparency = 0
	ghost.Parent = fxFolder
	local scale = if gold then GOLD_POP_SCALE else POP_SCALE
	local seconds = if gold then GOLD_POP_SECONDS else POP_SECONDS
	local grow = TweenService:Create(
		ghost,
		TweenInfo.new(seconds * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = part.Size * scale }
	)
	grow.Completed:Once(function()
		local shrink = TweenService:Create(
			ghost,
			TweenInfo.new(seconds * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }
		)
		shrink.Completed:Once(function()
			ghost:Destroy()
		end)
		shrink:Play()
	end)
	grow:Play()
end

local function predictPickup(entry: StickerEntry)
	entry.pendingAt = os.clock()
	popGhost(entry.part, entry.part:GetAttribute(Keys.ATTR_GOLD) == true)
	applySticker(entry)
end

local function unwatchSticker(part: Instance)
	local entry = stickers[part :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns)
	destroyPillar(entry)
	stickers[part :: any] = nil
end

local function watchSticker(part: Instance, plotId: number)
	if not part:IsA("BasePart") or stickers[part] then
		return
	end
	local entry: StickerEntry = {
		part = part,
		plotId = plotId,
		id = tostring(part:GetAttribute(Keys.ATTR_STICKER_ID)),
		baseColor = part.Color,
		baseMaterial = part.Material,
		pillar = nil,
		pendingAt = nil,
		hold = false,
		conns = {},
	}
	stickers[part] = entry
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_COLLECTED):Connect(function()
			-- 서버 확정이 왔으니 예측·보류는 끝
			entry.pendingAt = nil
			entry.hold = false
			applySticker(entry)
		end)
	)
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_GOLD):Connect(function()
			applySticker(entry)
		end)
	)
	applySticker(entry)
end

-- ── 칭찬스티커판 ─────────────────────────────────────────────────

local function unwatchBoard()
	if board then
		board.root:Destroy()
		board = nil
	end
end

--- 칸을 채운다. 60칸을 채워 원서가 되면(칸이 줄면) 판이 금색으로 번쩍이고 남은 칸이 다시 찬다
local function applyBoard(entry: BoardEntry, cells: number, animate: boolean)
	if cells == entry.shown then
		return
	end
	local wrapped = animate and cells < entry.shown
	local pop = TweenInfo.new(BOARD_POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i, dot in entry.dots do
		local on = i <= cells
		if on and animate and (wrapped or i > entry.shown) then
			dot.Size = UDim2.fromScale(0, 0)
			TweenService:Create(dot, pop, { Size = UDim2.fromScale(1, 1) }):Play()
		else
			dot.Size = if on then UDim2.fromScale(1, 1) else UDim2.fromScale(0, 0)
		end
	end
	entry.title.Text = `칭찬스티커판 {cells}/{EconomyConfig.BOARD_CELLS}`
	if wrapped then
		entry.flash.BackgroundTransparency = BOARD_FLASH_ALPHA
		TweenService:Create(entry.flash, TweenInfo.new(BOARD_FLASH_SECONDS), { BackgroundTransparency = 1 }):Play()
	end
	entry.shown = cells
end

local function watchBoard(part: BasePart)
	local surface = part:FindFirstChildOfClass("SurfaceGui")
	if not surface then
		return -- 스트리밍으로 SurfaceGui 가 뒤따라오면 onPlotDescendantAdded 가 다시 부른다
	end
	unwatchBoard()

	local root = Instance.new("Frame")
	root.Name = "BoardCells"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = surface

	local title = newLabel(root, "", 24, COLOR_BOARD_TEXT)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.TextStrokeTransparency = 1

	local rows = math.ceil(EconomyConfig.BOARD_CELLS / BOARD_COLUMNS)
	local pitch = BOARD_CELL + BOARD_GAP
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.AnchorPoint = Vector2.new(0.5, 1)
	grid.Position = UDim2.new(0.5, 0, 1, -BOARD_GAP * 2)
	grid.Size = UDim2.fromOffset(BOARD_COLUMNS * pitch - BOARD_GAP, rows * pitch - BOARD_GAP)
	grid.BackgroundTransparency = 1
	grid.Parent = root
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(BOARD_CELL, BOARD_CELL)
	layout.CellPadding = UDim2.fromOffset(BOARD_GAP, BOARD_GAP)
	layout.FillDirectionMaxCells = BOARD_COLUMNS
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local dots: { Frame } = {}
	for i = 1, EconomyConfig.BOARD_CELLS do
		local cell = Instance.new("Frame")
		cell.LayoutOrder = i
		cell.BackgroundColor3 = COLOR_BOARD_EMPTY
		cell.BorderSizePixel = 0
		cell.Parent = grid
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0.5, 0)
		cellCorner.Parent = cell
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromScale(0, 0)
		dot.BackgroundColor3 = COLOR_YELLOW
		dot.BorderSizePixel = 0
		dot.Parent = cell
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(0.5, 0)
		dotCorner.Parent = dot
		dots[i] = dot
	end

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = COLOR_GOLD
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 2
	flash.Parent = root

	local entry: BoardEntry = { part = part, root = root, dots = dots, title = title, flash = flash, shown = -1 }
	board = entry
	local profile = HudController.profile()
	applyBoard(entry, if profile then profile.stickerBoard else 0, false)
end

--- 부지가 바뀌었거나 판이 스트리밍으로 나갔다 들어왔으면 다시 그리고, 칸 수를 맞춘다
local function refreshBoard()
	local model = if myPlotId then plotModels[myPlotId] else nil
	if board and (model == nil or not board.part:IsDescendantOf(model)) then
		unwatchBoard()
	end
	if not board and model then
		local part = model:FindFirstChild(Keys.STICKER_BOARD, true)
		if part and part:IsA("BasePart") then
			watchBoard(part)
		end
	end
	local profile = HudController.profile()
	if board and profile then
		applyBoard(board, profile.stickerBoard, true)
	end
end

-- ── 시설 모델 ────────────────────────────────────────────────────

--- 파트를 땅 아래 6 스터드에서 Back Out 0.5초로 솟게 한다. 아래쪽 파트부터 0.05초 간격
local function appear(model: Model)
	local parts: { BasePart } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 1
			table.insert(parts, inst)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	for i, part in parts do
		local target = part.CFrame
		part.CFrame = target - Vector3.new(0, APPEAR_DROP, 0)
		local delay = (i - 1) * APPEAR_STAGGER
		local rise = TweenInfo.new(APPEAR_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, rise, { CFrame = target }):Play()
		-- 투명도는 Back 의 되튐이 0 아래로 내려가면 안 되므로 따로 Quad 로
		local fade =
			TweenInfo.new(APPEAR_SECONDS * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, fade, { LocalTransparencyModifier = 0 }):Play()
	end
end

local function refreshFacility(entry: FacilityEntry)
	local mine = entry.plotId == myPlotId
	local model = entry.model

	-- 스킨 팻말(🎨): 내 부지의 지은 시설마다 SkinSign Attachment 위
	local signAt = model:FindFirstChild(Keys.SKIN_SIGN, true)
	if mine and signAt and signAt:IsA("Attachment") then
		if not entry.sign then
			local gui, button = newTapButton("SkinSign_" .. entry.facilityId, signAt, "🎨", TAP_SIZE, COLOR_PANEL)
			entry.sign = gui
			button.Activated:Connect(function()
				PanelController.open(PANEL_SKIN, { facilityId = entry.facilityId })
			end)
		elseif entry.sign.Adornee ~= signAt then
			entry.sign.Adornee = signAt
		end
	elseif entry.sign then
		entry.sign:Destroy()
		entry.sign = nil
	end

	-- 졸업 종: GraduationBell 파트가 있는 모델(강당)에, 14/14 일 때만
	local bellPart = model:FindFirstChild(Keys.GRADUATION_BELL, true)
	if mine and bellPart and bellPart:IsA("BasePart") and isComplete(HudController.profile()) then
		if not entry.bell then
			local gui, button =
				newTapButton("Bell_" .. entry.facilityId, bellPart, "🔔 졸업하기", 160, COLOR_GOLD)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			entry.bell = gui
			button.Activated:Connect(function()
				PanelController.open(PANEL_GRADUATE)
			end)
		elseif entry.bell.Adornee ~= bellPart then
			entry.bell.Adornee = bellPart
		end
	elseif entry.bell then
		entry.bell:Destroy()
		entry.bell = nil
	end
end

local function unwatchFacility(model: Instance)
	local entry = facilities[model :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns)
	if entry.sign then
		entry.sign:Destroy()
	end
	if entry.bell then
		entry.bell:Destroy()
	end
	facilities[model :: any] = nil
end

local function watchFacility(model: Instance, plotId: number, animate: boolean)
	if not model:IsA("Model") or facilities[model] or not FacilityConfig.BY_ID[model.Name] then
		return
	end
	local entry: FacilityEntry = {
		model = model,
		plotId = plotId,
		facilityId = model.Name,
		sign = nil,
		bell = nil,
		conns = {},
	}
	facilities[model] = entry
	if animate and model:GetAttribute(Keys.ATTR_BUILT) == true then
		-- 파트가 모델 뒤에 몇 프레임 늦게 붙을 수 있어 잠깐 기다린다(§9.2 구매 50ms)
		task.delay(APPEAR_DELAY, function()
			if facilities[model] then
				appear(model)
			end
		end)
	end
	refreshFacility(entry)
end

-- ── 프롬프트 ─────────────────────────────────────────────────────

--- 접수대는 내 부지에서만, 「우리 학교로」 팻말은 남의 부지에서만 켠다. 광장 팻말은 건드리지 않는다
local function applyPrompt(prompt: ProximityPrompt, plotId: number)
	if prompt.Name == Keys.ADMISSION_PROMPT then
		prompt.Enabled = plotId == myPlotId
	elseif prompt.Name == Keys.HOME_PROMPT then
		prompt.Enabled = plotId ~= myPlotId
	end
end

local function onPromptTriggered(prompt: ProximityPrompt)
	if prompt.Name ~= Keys.ADMISSION_PROMPT then
		return
	end
	local plotId = plotIdOfInstance(prompt)
	if plotId ~= nil and plotId == myPlotId then
		PanelController.open(PANEL_GACHA)
	end
end

-- ── 부지 ─────────────────────────────────────────────────────────

local function onPlotDescendantAdded(inst: Instance, plotId: number)
	if inst:IsA("ProximityPrompt") then
		applyPrompt(inst, plotId)
		return
	end
	-- 판 파트와 함께 SurfaceGui 도 온다. 판이 스트리밍으로 다시 들어오면 새 인스턴스라 다시 그린다
	if inst:IsA("SurfaceGui") and inst.Parent and inst.Parent.Name == Keys.STICKER_BOARD then
		if plotId == myPlotId then
			refreshBoard()
		end
		return
	end
	local late = (inst:IsA("Attachment") and inst.Name == Keys.SKIN_SIGN)
		or (inst:IsA("BasePart") and inst.Name == Keys.GRADUATION_BELL)
	if not late then
		return
	end
	-- 스트리밍으로 늦게 온 팻말 위치·종 → 소속 시설 모델을 찾아 다시 붙인다
	local node = inst.Parent
	while node do
		local entry = facilities[node :: any]
		if entry then
			refreshFacility(entry)
			return
		end
		node = node.Parent
	end
end

local function watchFolder(folder: Instance, plotId: number, add: (Instance, number) -> (), remove: (Instance) -> ())
	local conns = plotConns[folder.Parent :: any]
	for _, child in folder:GetChildren() do
		add(child, plotId)
	end
	if conns then
		table.insert(
			conns,
			folder.ChildAdded:Connect(function(child)
				add(child, plotId)
			end)
		)
		table.insert(conns, folder.ChildRemoved:Connect(remove))
	end
end

local function onPlotChildAdded(child: Instance, plotId: number, animate: boolean)
	if child.Name == Keys.PADS_FOLDER then
		watchFolder(child, plotId, watchPad, unwatchPad)
	elseif child.Name == Keys.STICKERS_FOLDER then
		watchFolder(child, plotId, watchSticker, unwatchSticker)
	elseif child:IsA("Model") then
		watchFacility(child, plotId, animate)
	end
end

local function unwatchPlot(model: Instance)
	local conns = plotConns[model :: any]
	if conns then
		disconnectAll(conns)
		plotConns[model :: any] = nil
	end
	for part, entry in pads do
		if entry.part:IsDescendantOf(model) then
			unwatchPad(part)
		end
	end
	for part, entry in stickers do
		if entry.part:IsDescendantOf(model) then
			unwatchSticker(part)
		end
	end
	for facility in facilities do
		if facility:IsDescendantOf(model) then
			unwatchFacility(facility)
		end
	end
	for plotId, plot in plotModels do
		if plot == model then
			plotModels[plotId] = nil
		end
	end
end

local function watchPlot(model: Instance, animate: boolean)
	if not model:IsA("Model") or plotConns[model] then
		return
	end
	local plotId = plotIdOfModel(model)
	if not plotId then
		return
	end
	plotModels[plotId] = model
	local conns: { RBXScriptConnection } = {}
	plotConns[model] = conns
	table.insert(
		conns,
		model.ChildAdded:Connect(function(child)
			onPlotChildAdded(child, plotId, true)
		end)
	)
	table.insert(
		conns,
		model.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				unwatchFacility(child)
			end
		end)
	)
	table.insert(
		conns,
		model.DescendantAdded:Connect(function(inst)
			onPlotDescendantAdded(inst, plotId)
		end)
	)
	for _, child in model:GetChildren() do
		onPlotChildAdded(child, plotId, animate)
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("ProximityPrompt") then
			applyPrompt(inst, plotId)
		end
	end
	if plotId == myPlotId then
		refreshBoard()
	end
end

local function refreshAll()
	for _, entry in pads do
		applyPad(entry)
	end
	for _, entry in stickers do
		applySticker(entry)
	end
	for _, entry in facilities do
		refreshFacility(entry)
	end
	for plotId, model in plotModels do
		for _, inst in model:GetDescendants() do
			if inst:IsA("ProximityPrompt") then
				applyPrompt(inst, plotId)
			end
		end
	end
	refreshBoard()
end

-- ── 프레임 ───────────────────────────────────────────────────────

local function onHeartbeat(dt: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local rootPos: Vector3? = nil
	if root and root:IsA("BasePart") then
		rootPos = root.Position
	end
	local now = os.clock()
	for _, entry in stickers do
		if entry.plotId ~= myPlotId then
			continue
		end
		if entry.pendingAt then
			-- 0.5초 안에 Collected 도 확정도 없으면 예측을 되돌린다
			if now - entry.pendingAt > PICKUP_REVERT then
				entry.pendingAt = nil
				applySticker(entry)
			end
		elseif rootPos and not entry.hold and entry.part:GetAttribute(Keys.ATTR_COLLECTED) ~= true then
			if (entry.part.Position - rootPos).Magnitude <= PICKUP_RADIUS then
				predictPickup(entry)
			end
		end
	end

	ringClock += dt
	if ringClock >= RING_REFRESH then
		ringClock = 0
		for _, entry in pads do
			if entry.ring then
				updateRing(entry)
			end
		end
	end
end

-- ── 공개 API ─────────────────────────────────────────────────────

function PadController.Start()
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("Folder")
	gui.Name = "PadWorldGui"
	gui.Parent = playerGui
	guiFolder = gui

	local fx = Instance.new("Folder")
	fx.Name = "PadFx"
	fx.Parent = Workspace
	fxFolder = fx

	myPlotId = readMyPlot()
	player:GetAttributeChangedSignal(Keys.ATTR_PLOT):Connect(function()
		myPlotId = readMyPlot()
		refreshAll()
	end)

	HudController.onProfile(function()
		PadController.refresh()
	end)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RunService.Heartbeat:Connect(onHeartbeat)

	-- Plots 폴더는 서버 부팅 뒤 온다. Start 를 막지 않게 따로 기다린다
	task.spawn(function()
		local plots = Workspace:WaitForChild(Keys.PLOTS_FOLDER, WAIT_TIMEOUT)
		if not plots then
			plots = Workspace:WaitForChild(Keys.PLOTS_FOLDER)
		end
		for _, child in plots:GetChildren() do
			watchPlot(child, false)
		end
		plots.ChildAdded:Connect(function(child)
			watchPlot(child, true)
		end)
		plots.ChildRemoved:Connect(unwatchPlot)
	end)
end

--- 프로필·부지 변화 뒤 패드·팻말·종·프롬프트를 어트리뷰트에서 다시 계산한다
function PadController.refresh()
	refreshAll()
end

--- SkinApplied: SkinRole 파트를 0.3초 색 전환 + 재질 교체 + 반짝 8개
function PadController.applySkin(payload: { plot: number, facilityId: string, skinIndex: number })
	local model = plotModels[payload.plot]
	local facility = if model then model:FindFirstChild(payload.facilityId) else nil
	if not facility or not SkinConfig.isValidIndex(payload.skinIndex) then
		return
	end
	local skin = SkinConfig.get(payload.facilityId, payload.skinIndex)
	local info = TweenInfo.new(SKIN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in facility:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local role = part:GetAttribute(Keys.ATTR_SKIN_ROLE)
		if role == nil then
			continue
		end
		local color = if role == SKIN_ROLE_PRIMARY then skin.primary else skin.secondary
		part.Material = skin.material
		TweenService:Create(part, info, { Color = color }):Play()
	end
	if facility:IsA("Model") then
		sparkle(facility:GetPivot().Position + Vector3.new(0, 3, 0), SPARKLE_COUNT, skin.primary)
	end
end

--- StickerCollected: 예측한 스티커를 확정한다(Collected 가 올 때까지 숨긴 채 둔다)
function PadController.confirmSticker(payload: { stickerId: any })
	local id = tostring(payload.stickerId)
	for _, entry in stickers do
		if entry.plotId == myPlotId and (entry.id == id or entry.part.Name == id) then
			entry.pendingAt = nil
			entry.hold = entry.part:GetAttribute(Keys.ATTR_COLLECTED) ~= true
			applySticker(entry)
			return
		end
	end
end

--- 내 부지 패드 위치(월드). 스트리밍 밖이면 nil
function PadController.padPosition(facilityId: string): Vector3?
	for _, entry in pads do
		if entry.plotId == myPlotId and entry.facilityId == facilityId then
			return entry.part.Position
		end
	end
	return nil
end

--- 내 부지 입학 접수대 위치(월드)
function PadController.admissionDeskPosition(): Vector3?
	local model = if myPlotId then plotModels[myPlotId] else nil
	local desk = if model then model:FindFirstChild(Keys.ADMISSION_DESK, true) else nil
	return if desk and desk:IsA("BasePart") then desk.Position else nil
end

--- 내 부지 스티커 위치(월드). id 는 StickerId(1~8) 또는 파트 이름
function PadController.stickerPosition(stickerId: any): Vector3?
	local id = tostring(stickerId)
	for _, entry in stickers do
		if entry.plotId == myPlotId and (entry.id == id or entry.part.Name == id) then
			return entry.part.Position
		end
	end
	return nil
end

--- 내 부지 시설의 스킨 팻말 위치(월드)
function PadController.skinSignPosition(facilityId: string): Vector3?
	local model = if myPlotId then plotModels[myPlotId] else nil
	local facility = if model then model:FindFirstChild(facilityId) else nil
	local sign = if facility then facility:FindFirstChild(Keys.SKIN_SIGN, true) else nil
	return if sign and sign:IsA("Attachment") then sign.WorldPosition else nil
end

--- 아무 부지 시설 모델의 피벗 위치(월드). 없으면 nil
function PadController.facilityPosition(plotId: number, facilityId: string): Vector3?
	local model = plotModels[plotId]
	local facility = if model then model:FindFirstChild(facilityId) else nil
	return if facility and facility:IsA("Model") then facility:GetPivot().Position else nil
end

--- 부지 모델(있으면)
function PadController.plotModel(plotId: number): Model?
	return plotModels[plotId]
end

--- 내 부지 번호
function PadController.myPlot(): number?
	return myPlotId
end

--- 「부족」 힌트(§9.2): 활성 패드 링을 0.4초 밝히고 실루엣을 두 번 깜빡인다. 글자·빨강·흔들림 없음
function PadController.hintShortfall()
	local now = os.clock()
	if now - lastHint < HINT_COOLDOWN then
		return
	end
	lastHint = now
	for _, entry in pads do
		local ring = entry.ring
		if ring and entry.plotId == myPlotId then
			ring.stroke.Transparency = 0
			TweenService:Create(ring.stroke, TweenInfo.new(HINT_SECONDS), { Transparency = 1 }):Play()
		end
	end
	local model = if myPlotId then plotModels[myPlotId] else nil
	local silhouette = if model then model:FindFirstChild(Keys.SILHOUETTE) else nil
	if not silhouette then
		return
	end
	local parts: { BasePart } = {}
	for _, inst in silhouette:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	task.spawn(function()
		local half = TweenInfo.new(HINT_SECONDS / 4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _ = 1, 2 do
			for _, part in parts do
				TweenService:Create(part, half, { Transparency = SILHOUETTE_BLINK_ALPHA }):Play()
			end
			task.wait(HINT_SECONDS / 4)
			for _, part in parts do
				TweenService:Create(part, half, { Transparency = SILHOUETTE_ALPHA }):Play()
			end
			task.wait(HINT_SECONDS / 4)
		end
	end)
end

return PadController
