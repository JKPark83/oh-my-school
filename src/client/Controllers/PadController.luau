--!strict
--[[
	PadController — 월드 상호작용(클라이언트)

	서버가 만든 부지 인스턴스(Workspace.Plots.PlotNN)를 읽고 로컬 연출만 얹는다. 상태의 출처는 언제나 어트리뷰트다.
	- 구매 패드: PadState 로 보이기·색을 정하고, 내 부지의 활성 패드 위에 빌보드(이름·가격·진행 링)를 띄운다.
	  내 부지 층 패드는 장식을 더 얹는다(금 테두리·모서리 등·올라가는 빛 고리·반짝이·「다음 층」 글씨). 층 부품을 사면 towerBurst
	- 칭찬스티커: 서버 파트는 보이지 않는 히트박스(3.4×3×3.4)다. 내 부지면 그 바닥에 3×0.1×3 표시판(별·하트·꽃·스마일)과
	  세로 빛·반짝 소리를 로컬로 붙인다(개선계획 §3.2 #2·#3·#9). 금 스티커엔 빛기둥. 수평 2.2·높이 4 안이면 먼저 숨기는
	  클라 예측(0.5초 안에 확정이 없으면 되돌림)
	- 칭찬스티커판: 내 부지 현관 벽 판의 SurfaceGui 에 BOARD_CELLS(40)칸을 그리고 프로필 stickerBoard 만큼 채운다
	- 시설 등장: 부품을 살 때마다 시설 모델에 새로 붙는 파트(PartIndex)만 땅에서 솟게 한다(§9.2 구매 50ms 뒤 등장).
	  DescendantAdded 로 모아 한 프레임에 한 번 올린다. 스트리밍으로 다시 들어온 옛 부품은 올리지 않는다
	- 「우리 학교로」 팻말 프롬프트는 내 부지에서만 끈다. 접수대 건물은 남지만 프롬프트는 W4 에서 없앴다
	- 방문객 별(하늘색)도 히트박스 + 로컬 표시판이다. 남의 부지에서만 판을 그린다(내 별은 안 보임, §7.5)

	패드 파트는 서버가 Transparency 1 로 만들어 두므로(PlotShell) 여기서는 Transparency 를 직접 쓴다.
	스티커·별 히트박스는 늘 투명하고 여기서도 건드리지 않는다. 보이는 것은 fxFolder 아래 로컬 판뿐이다.
	클라가 바꾼 속성은 복제되지 않고, 서버는 이 속성을 다시 건드리지 않는다.
	스트리밍: 파트는 들어왔다 나가므로 ChildAdded/ChildRemoved 로만 붙잡는다. 모듈 최상위 부작용은 없다.
	이 모듈은 FeedbackController·TutorialController 를 require 하지 않는다(순환 방지). 위치 조회 API 만 내준다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

-- 계획 §3.4 계약. 형제 컨트롤러는 다른 작업자가 쓰고 있어 형태만 선언하고 any 로 받는다
type HudApi = {
	profile: () -> Types.Profile?,
	onProfile: (fn: (Types.Profile) -> ()) -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local SoundController = require(script.Parent.SoundController)
-- isLowSpec() 만 쓴다. FeedbackController 와 같이 any 로 받는다(순환 없음: 그쪽은 SoundController 만 require)
local StudentRenderController = require(script.Parent.StudentRenderController) :: any

local PadController = {}

-- PadState 값(Keys.ATTR_PAD_STATE 주석과 서버 PlotService.refreshPads)
local PAD_ACTIVE = "active"
local PAD_NEXT = "next"
local PAD_BUILT = "built"

-- 층 쌓기(개선계획 §5.2)
local TOWER_FOLDER = Keys.TOWER_FOLDER
local TOWER_PAD = Keys.TOWER_PAD
local TOWER_FACILITY = Keys.TOWER_PAD_ID
local TEXT_CHOOSE_ROOM = "방 고르기"
local TEXT_TOWER_TOP = "최고 높이!"
local TEXT_NEXT_FLOOR = "다음 층"

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
local NEXT_PAD_ALPHA = 0.6
local PAD_SINK = 0.5 -- 스터드
local PAD_SINK_SECONDS = 0.2
-- 밟으면 눌렸다가 내려서면 튀어 오른다(활성 패드, 내 부지만). 판정은 서버가 따로 한다 — 이건 보이기만
local PAD_PRESS = 0.1 -- 스터드. 0.2 면 눌린 윗면이 방 바닥(두께 0.2) 윗면과 같아져 z-fighting 이 난다
local PAD_PRESS_SECONDS = 0.08
local PAD_RELEASE_SECONDS = 0.3
local PAD_PRESS_MARGIN = 0.5 -- 스터드. 발이 가장자리에 걸쳐도 눌린 것으로
local PAD_PRESS_DY = 6 -- 스터드. 패드 윗면과 캐릭터 루트의 높이 차 상한
local PAD_PRESS_TINT = 0.35 -- 눌린 동안 초록을 흰색 쪽으로 섞는 비율
local PICKUP_RADIUS = 2.2 -- 스터드, 수평(§3.2 #6)
local PICKUP_DY = 4 -- 스터드, 히트박스 중심과 캐릭터 루트의 높이 차
local PICKUP_REVERT = 0.5 -- 초
local PILLAR_HEIGHT = 12
-- 층 패드 장식(내 부지만)
local DECOR_FRAME = 0.5 -- 테두리 굵기·높이
local DECOR_LAMP = 0.7
local DECOR_RINGS = 3
local DECOR_RING_RISE = 7 -- 스터드
local DECOR_RING_SECONDS = 1.8
local DECOR_RING_ALPHA = 0.25
local DECOR_SPARKLE_RATE = 6
local DECOR_TEXT_PIXELS = 50 -- SurfaceGui 스터드당 픽셀
local BURST_SPARKLES = 30
local BURST_SECONDS = 0.7
local BURST_BEAM_H = 16 -- 위층까지 솟는 빛기둥
local BURST_WAVE = 10 -- 퍼지는 고리 지름
-- 스티커·별 표시판(§3.2 #2). 판 중심 = 바닥 윗면 + 0.01 → 판 윗면 = 바닥 + 0.06
local PLATE_SIZE = Vector3.new(3, 0.1, 3)
local PLATE_LIFT = 0.01
local PLATE_TOP_GAP = 0.06
local PLATE_PIXELS = 50 -- SurfaceGui 스터드당 픽셀 → 150×150 캔버스
local SHAPE_STAR = 1
local SHAPE_HEART = 2
local SHAPE_FLOWER = 3
local SHAPE_SMILE = 4
local SHAPE_COUNT = SHAPE_SMILE -- 모양 번호는 1..SHAPE_COUNT
local SPIN_SECONDS = 3 -- 1바퀴(§3.2 #3)
local GOLD_SPIN_SECONDS = 1.5
local EMIT_INTERVAL = 2.4
local EMIT_COUNT = 2
local APPEAR_POP_SCALE = 1.15 -- 0 → 1.15 → 1
local APPEAR_POP_UP = 0.15
local APPEAR_POP_DOWN = 0.1
local FLY_SECONDS = 0.18 -- 줍기: 캐릭터 쪽으로 날아가며 사라짐
local BEAM_HEIGHT = 8 -- 찾기 표식(§3.2 #9)
local CHIME_INTERVAL = 3
local COLOR_STICKER = WorldPalette.sticker
local COLOR_STAR = WorldPalette.star
local COLOR_FLOWER_CORE = Color3.fromRGB(251, 146, 60)
local APPEAR_DROP = 6 -- 스터드
local APPEAR_SECONDS = 0.5
local APPEAR_STAGGER = 0.05
local APPEAR_DELAY = 0.05
local APPEAR_GRACE = 1 -- 초. 같은 부품 번호가 이 안에 더 오면 같은 등장, 그 뒤는 스트리밍 재진입이라 올리지 않는다
local HINT_COOLDOWN = 1
local HINT_SECONDS = 0.4
local SILHOUETTE_ALPHA = 0.7 -- 서버 PlotService.SILHOUETTE_TRANSPARENCY 와 같다
local SILHOUETTE_BLINK_ALPHA = 0.35
-- 스티커판 캔버스는 8×5 스터드 × 40px = 320×200px(PlotShell STICKER_BOARD_SIZE)
local BOARD_COLUMNS = 10 -- 행은 BOARD_CELLS 로 계산한다(40칸 = 10×4)
local BOARD_CELL = 22 -- px
local BOARD_GAP = 4
local BOARD_POP_SECONDS = 0.15
local BOARD_FLASH_ALPHA = 0.3
local BOARD_FLASH_SECONDS = 0.3 -- §9.2 판이 차면 금색 플래시 0.3초

type Ring = {
	gui: BillboardGui,
	dots: { Frame },
	name: TextLabel,
	price: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	pulse: Tween?,
}

type TowerDecor = { folder: Folder, gui: SurfaceGui, caption: TextLabel, label: TextLabel, emitter: ParticleEmitter }

type PadEntry = {
	part: BasePart,
	plotId: number,
	facilityId: string,
	base: CFrame,
	baseColor: Color3,
	state: string,
	ring: Ring?,
	decor: TowerDecor?,
	pressed: boolean,
	pressTween: Tween?,
	conns: { RBXScriptConnection },
}

type StickerEntry = {
	part: BasePart,
	plotId: number,
	id: string,
	pillar: BasePart?,
	plate: Part?, -- 로컬 표시판. 주인 화면에서 보일 때만 있다
	plateGold: boolean, -- 판을 만들 때의 금 여부(바뀌면 다시 만든다)
	shape: number, -- SHAPE_*. 리스폰마다 새로 뽑는다
	spin: number, -- 라디안
	emitClock: number,
	chimeClock: number,
	pendingAt: number?,
	hold: boolean, -- confirmSticker 뒤 Collected 가 올 때까지 숨긴 채 둔다
	conns: { RBXScriptConnection },
}

type StarEntry = {
	part: BasePart,
	plotId: number,
	plate: Part?, -- 남의 부지에서만 있다
	gui: SurfaceGui?,
	spin: number,
	conns: { RBXScriptConnection },
}

type FacilityEntry = {
	model: Model,
	plotId: number,
	facilityId: string,
	conns: { RBXScriptConnection },
	appearedAt: { [number]: number }, -- 부품 번호 → 등장을 시작한 os.clock()(-inf 면 처음부터 있던 부품)
	pending: { BasePart }, -- 이번 프레임에 새로 붙어 올릴 파트
	flushQueued: boolean,
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
local stars: { [BasePart]: StarEntry } = {}
local facilities: { [Model]: FacilityEntry } = {}
local ringClock = 0
local lastHint = 0
local board: BoardEntry? = nil -- 내 부지 스티커판 하나만 그린다. 남의 판 칸 수는 클라가 모른다
-- PanelController 는 HudController 를 require 하므로 Start 에서 늦게 잇는다(순환 방지)
local PanelController: any = nil

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

	return { gui = gui, dots = dots, name = name, price = price, stroke = stroke, scale = scale, pulse = nil }
end

--- 진행 링 = 용돈 ÷ 가격. 살 수 있으면 초록으로 숨쉬기
local function updateRing(entry: PadEntry)
	local ring = entry.ring
	if not ring then
		return
	end
	local profile = HudController.profile()
	local coins = if profile then profile.coins else 0
	local price: number
	if entry.facilityId == TOWER_FACILITY then
		-- 층 패드: 짓는 방 부품 / 방 고르기 / 최고 높이. 가격이 없으면 링을 비우고 숨쉬지 않는다
		local text, towerPrice = TEXT_TOWER_TOP, 0
		if profile and profile.towerRoom ~= "" then
			local room = RoomConfig.BY_ID[profile.towerRoom]
			local k = profile.towerParts + 1
			text = `{if room then room.name else ""} {RoomConfig.PART_NAMES[k]} {k}/{RoomConfig.PARTS}`
			towerPrice = RoomConfig.partPrice(RoomConfig.stepOf(profile), k)
		elseif profile and RoomConfig.nextStep(profile) then
			text = TEXT_CHOOSE_ROOM
		end
		ring.name.Text = text
		price = towerPrice
		if entry.decor and profile then
			local room = RoomConfig.BY_ID[profile.towerRoom]
			local top = RoomConfig.topFloor(#profile.floors)
			local roof = if room then room.kind == "roof" else top >= RoomConfig.MAX_FLOOR
			entry.decor.label.Text = if roof then "옥상" else `{top + 1}층`
			-- 뼈대를 산 뒤에는 패드가 그 층 안에 있다: 「다음 층」 대신 「공사 중」
			entry.decor.caption.Text = if profile.towerParts >= 1 then RoomConfig.TEXT_BUILDING else TEXT_NEXT_FLOOR
		end
	else
		local nextIndex = if profile then profile.buildParts + 1 else 1
		price = FacilityConfig.partPriceOf(entry.facilityId, nextIndex)
	end
	-- 층 패드는 가격이 없으면(고르기·최고 높이) 빈 링
	local ratio = if price > 0
		then math.clamp(coins / price, 0, 1)
		elseif entry.facilityId == TOWER_FACILITY then 0
		else 1
	ring.price.Text = if price > 0 then Format.coins(price) else ""
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

local function stopPress(entry: PadEntry)
	entry.pressed = false
	if entry.pressTween then
		entry.pressTween:Cancel()
		entry.pressTween = nil
	end
end

--- 밟음/내려섬. 눌리면 살짝 가라앉고 밝아지며 `pad` 소리, 내려서면 Back Out 으로 튀어 오른다
local function setPressed(entry: PadEntry, on: boolean)
	if entry.pressed == on then
		return
	end
	stopPress(entry)
	entry.pressed = on
	local info = if on
		then TweenInfo.new(PAD_PRESS_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else TweenInfo.new(PAD_RELEASE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local goal = {
		CFrame = if on then entry.base - Vector3.new(0, PAD_PRESS, 0) else entry.base,
		Color = if on then COLOR_GREEN:Lerp(COLOR_WHITE, PAD_PRESS_TINT) else COLOR_GREEN,
	}
	local tween = TweenService:Create(entry.part, info, goal)
	entry.pressTween = tween
	tween:Play()
	if on then
		SoundController.play("pad")
	end
end

--- 활성 → 건설: 0.2초 가라앉은 뒤 숨기고 원래 자리로
local function sinkPad(entry: PadEntry)
	stopPress(entry)
	local part = entry.part
	local info = TweenInfo.new(PAD_SINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(part, info, { CFrame = entry.base - Vector3.new(0, PAD_SINK, 0) })
	tween.Completed:Once(function()
		part.Transparency = 1
		part.CFrame = entry.base
	end)
	tween:Play()
end

local function destroyDecor(entry: PadEntry)
	local decor = entry.decor
	if decor then
		decor.folder:Destroy()
		decor.gui:Destroy()
		entry.decor = nil
	end
end

--- 층 패드 장식. 패드 바닥(= 층 바닥) 기준으로 둘레에 세운다. 패드가 옮겨 가면 다시 만든다
local function buildDecor(entry: PadEntry): TowerDecor
	local pad = entry.part
	local folder = Instance.new("Folder")
	folder.Name = "TowerPadDecor"
	folder.Parent = fxFolder
	local floor = entry.base * CFrame.new(0, -pad.Size.Y / 2, 0)
	local half = pad.Size.X / 2 + DECOR_FRAME / 2
	local function put(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = newLocalPart(name, size, floor * offset, color)
		p.Material = material
		p.Parent = folder
		return p
	end
	-- 금 테두리 4 + 모서리 등 4(숨쉬기)
	local long = pad.Size.X + DECOR_FRAME * 2
	for i, side in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) } do
		local size = if side.X == 0
			then Vector3.new(long, DECOR_FRAME, DECOR_FRAME)
			else Vector3.new(DECOR_FRAME, DECOR_FRAME, long)
		put(
			`Frame{i}`,
			size,
			CFrame.new(side * half + Vector3.new(0, DECOR_FRAME / 2, 0)),
			COLOR_GOLD,
			Enum.Material.Metal
		)
	end
	local glow = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for i, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local lamp = put(
			`Lamp{i}`,
			Vector3.one * DECOR_LAMP,
			CFrame.new(c.X * half, DECOR_FRAME + DECOR_LAMP / 2, c.Y * half),
			COLOR_YELLOW,
			Enum.Material.Neon
		)
		lamp.Shape = Enum.PartType.Ball
		TweenService:Create(lamp, glow, { Transparency = 0.6 }):Play()
	end
	-- 위로 올라가며 사라지는 빛 고리(엘리베이터처럼 「위로」)
	local flat = CFrame.Angles(0, 0, math.pi / 2) -- 원기둥 축(X)을 세로로
	local ringSize = Vector3.new(0.12, long, long)
	for i = 1, DECOR_RINGS do
		local start = CFrame.new(0, pad.Size.Y + 0.1, 0) * flat
		local ring = put(`Ring{i}`, ringSize, start, COLOR_GREEN, Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 1
		local rise = TweenInfo.new(DECOR_RING_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1)
		task.delay((i - 1) * DECOR_RING_SECONDS / DECOR_RINGS, function()
			if ring.Parent then
				ring.Transparency = DECOR_RING_ALPHA
				TweenService:Create(ring, rise, {
					CFrame = floor * CFrame.new(0, DECOR_RING_RISE, 0) * flat,
					Transparency = 1,
				}):Play()
			end
		end)
	end
	-- 반짝이: 패드 윗면 전체에서 위로
	local core = put(
		"Sparkles",
		Vector3.new(pad.Size.X, 0.1, pad.Size.Z),
		CFrame.new(0, pad.Size.Y, 0),
		COLOR_GREEN,
		Enum.Material.Neon
	)
	core.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = DECOR_SPARKLE_RATE
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(3, 5)
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(COLOR_YELLOW, COLOR_GREEN)
	emitter.Parent = core
	-- 패드 윗면 글씨: 「다음 층」 / 「5층」(updateRing 이 바꾼다). 패드가 눌려도 같이 내려가게 패드에 붙인다
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TowerPadText"
	gui.Adornee = pad
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(pad.Size.X, pad.Size.Z) * DECOR_TEXT_PIXELS
	gui.LightInfluence = 0
	gui.Parent = guiFolder
	local caption = newLabel(gui, TEXT_NEXT_FLOOR, 30, COLOR_WHITE)
	caption.Size = UDim2.fromScale(1, 0.3)
	caption.Position = UDim2.fromScale(0, 0.12)
	local label = newLabel(gui, "", 80, COLOR_WHITE)
	label.Size = UDim2.fromScale(1, 0.5)
	label.Position = UDim2.fromScale(0, 0.4)
	label.TextStrokeColor3 = COLOR_GOLD
	label.TextStrokeTransparency = 0
	return { folder = folder, gui = gui, caption = caption, label = label, emitter = emitter }
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
			if entry.facilityId == TOWER_FACILITY and not entry.decor then
				entry.decor = buildDecor(entry)
			end
			if not entry.ring then
				entry.ring = buildRing(entry)
			end
			updateRing(entry)
		else
			destroyRing(entry)
			destroyDecor(entry)
		end
		return
	end

	destroyRing(entry)
	destroyDecor(entry)
	if previous == PAD_ACTIVE and state ~= PAD_BUILT then
		-- 눌린 채 비활성이 되면 원래 자리로 돌려 둔다
		stopPress(entry)
		part.CFrame = entry.base
	end
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
	destroyDecor(entry)
	pads[part :: any] = nil
end

--- 서버가 준 패드 자리. 시설 패드는 부품마다 옮겨 가서(PadBase) 눌림·가라앉음 연출의 기준을 여기서 읽는다
local function padBase(part: BasePart): CFrame
	local raw = part:GetAttribute(Keys.ATTR_PAD_BASE)
	return if typeof(raw) == "CFrame" then raw else part.CFrame
end

--- 다음 부품 자리로 옮겨 감: 눌림을 풀고 새 자리에서 살짝 솟아오른다. 활성이 아니면 기준만 바꾼다
local function movePad(entry: PadEntry)
	local base = padBase(entry.part)
	if base == entry.base then
		return
	end
	entry.base = base
	if entry.decor then
		destroyDecor(entry)
		entry.decor = buildDecor(entry)
	end
	if entry.state ~= PAD_ACTIVE then
		return
	end
	stopPress(entry)
	local part = entry.part
	part.CFrame = base - Vector3.new(0, PAD_SINK, 0)
	local info = TweenInfo.new(PAD_RELEASE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local tween = TweenService:Create(part, info, { CFrame = base })
	entry.pressTween = tween
	tween:Play()
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
		base = padBase(part),
		baseColor = part.Color,
		state = "",
		ring = nil,
		decor = nil,
		pressed = false,
		pressTween = nil,
		conns = {},
	}
	pads[part] = entry
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_PAD_STATE):Connect(function()
			applyPad(entry)
		end)
	)
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_PAD_BASE):Connect(function()
			movePad(entry)
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

--- 히트박스 아랫면(= 구역 바닥 윗면) 위 판 중심. 서버 계약: 히트박스 Position.Y = 바닥 + Size.Y/2
local function platePosition(hitbox: BasePart): Vector3
	local position = hitbox.Position
	return Vector3.new(position.X, position.Y - hitbox.Size.Y / 2 + PLATE_LIFT, position.Z)
end

local function shapeFrame(
	parent: Instance,
	width: number,
	height: number,
	x: number,
	y: number,
	color: Color3,
	round: boolean,
	rotation: number,
	z: number
): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, x, 0.5, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Rotation = rotation
	frame.ZIndex = z
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

--- 판 윗면에 동그란 바탕 + 흰 모양. 이미지 에셋 없이 Frame 으로 그린다(권리·검열 걱정 없음)
local function drawShape(root: Frame, shape: number, back: Color3)
	shapeFrame(root, 140, 140, 0, 0, back, true, 0, 1)
	if shape == SHAPE_STAR then
		-- 정사각형 두 장을 45° 엇갈려 8각 별
		shapeFrame(root, 72, 72, 0, 0, COLOR_WHITE, false, 0, 2)
		shapeFrame(root, 72, 72, 0, 0, COLOR_WHITE, false, 45, 2)
	elseif shape == SHAPE_HEART then
		-- 45° 돌린 정사각형 + 위쪽 두 변 가운데에 지름 = 변 길이인 원 두 개
		shapeFrame(root, 46, 46, 0, 6, COLOR_WHITE, false, 45, 2)
		shapeFrame(root, 46, 46, -16, -10, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 46, 46, 16, -10, COLOR_WHITE, true, 0, 2)
	elseif shape == SHAPE_FLOWER then
		shapeFrame(root, 40, 40, 0, -24, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 40, 40, 0, 24, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 40, 40, -24, 0, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 40, 40, 24, 0, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 30, 30, 0, 0, COLOR_FLOWER_CORE, true, 0, 3)
	else
		-- 얼굴 + 눈 두 개 + 반원 입(원 위쪽 절반을 얼굴색으로 덮는다)
		shapeFrame(root, 96, 96, 0, 0, COLOR_WHITE, true, 0, 2)
		shapeFrame(root, 14, 14, -17, -14, COLOR_BOARD_TEXT, true, 0, 3)
		shapeFrame(root, 14, 14, 17, -14, COLOR_BOARD_TEXT, true, 0, 3)
		shapeFrame(root, 44, 44, 0, 10, COLOR_BOARD_TEXT, true, 0, 3)
		shapeFrame(root, 50, 23, 0, -1, COLOR_WHITE, false, 0, 4)
	end
end

--- 로컬 표시판. 판 자체는 투명하고 윗면 SurfaceGui 가 모양을 그린다. 충돌·터치·조회·그림자 없음, FADE 태그 없음
local function newPlate(name: string, hitbox: BasePart, shape: number, back: Color3): (Part, SurfaceGui, UIScale)
	local plate = newLocalPart(name, PLATE_SIZE, CFrame.new(platePosition(hitbox)), back)
	plate.Transparency = 1
	plate.Material = Enum.Material.SmoothPlastic
	-- 개발용 확인(한 곳): 판 윗면 − 바닥 윗면 = 0.06(§3.2 #2)
	local floorY = hitbox.Position.Y - hitbox.Size.Y / 2
	assert(
		math.abs(plate.Position.Y + plate.Size.Y / 2 - floorY - PLATE_TOP_GAP) < 1e-3,
		"스티커 판 높이가 바닥 +0.06 이 아니다"
	)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Shape"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PLATE_PIXELS
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = plate
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = root
	drawShape(root, shape, back)
	return plate, gui, scale
end

--- 등장 팝 0 → 1.15 → 1
local function popIn(scale: UIScale)
	local up = TweenService:Create(
		scale,
		TweenInfo.new(APPEAR_POP_UP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = APPEAR_POP_SCALE }
	)
	up.Completed:Once(function()
		TweenService
			:Create(
				scale,
				TweenInfo.new(APPEAR_POP_DOWN, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Scale = 1 }
			)
			:Play()
	end)
	up:Play()
end

local function destroyPlate(entry: StickerEntry)
	if entry.plate then
		entry.plate:Destroy() -- 파티클·Beam·반짝 소리는 판의 자식이라 같이 지워진다
		entry.plate = nil
	end
end

--- 주인 화면 전용 판 + 파티클 + 세로 빛 + 반짝 소리
local function buildPlate(entry: StickerEntry, gold: boolean)
	local back = if gold then COLOR_GOLD else COLOR_STICKER
	local plate, _, scale = newPlate("StickerPlate", entry.part, entry.shape, back)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Color = ColorSequence.new(back)
	emitter.LightEmission = 1
	emitter.Parent = plate

	-- 멀리서 찾는 가는 세로 빛(저사양에서도 켠다). 회전축 위에 있어 판이 돌아도 그대로 서 있다
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, PLATE_SIZE.Y / 2, 0)
	bottom.Parent = plate
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, BEAM_HEIGHT, 0)
	top.Parent = plate
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.35
	beam.Width1 = 0.1
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(back)
	beam.Transparency = NumberSequence.new(0.35, 1)
	beam.Parent = plate

	-- 3D 소리. 판에 붙어 거리로 줄어든다(SoundConfig sparkle 의 rollOff)
	SoundConfig.create("sparkle").Parent = plate

	entry.plate = plate
	entry.plateGold = gold
	entry.emitClock = 0
	entry.chimeClock = math.random() * CHIME_INTERVAL -- 여러 개가 한꺼번에 울리지 않게
	popIn(scale)
end

local function applySticker(entry: StickerEntry)
	local part = entry.part
	local collected = part:GetAttribute(Keys.ATTR_COLLECTED) == true
	local gold = part:GetAttribute(Keys.ATTR_GOLD) == true
	-- 주인 화면에서만 그린다. myPlotId 는 서버가 정한 player.Plot(= 그 부지 OwnerId 가 나)
	local hidden = entry.plotId ~= myPlotId or collected or entry.pendingAt ~= nil or entry.hold
	if hidden then
		destroyPlate(entry)
		destroyPillar(entry)
		return
	end
	if entry.plate and entry.plateGold ~= gold then
		destroyPlate(entry)
	end
	if not entry.plate then
		buildPlate(entry, gold)
	end
	if gold then
		if not entry.pillar then
			local cframe = CFrame.new(platePosition(part) + Vector3.new(0, PILLAR_HEIGHT / 2, 0))
			local pillar = newLocalPart("GoldPillar", Vector3.new(0.6, PILLAR_HEIGHT, 0.6), cframe, COLOR_GOLD)
			pillar.Transparency = 0.6
			entry.pillar = pillar
		end
	else
		destroyPillar(entry)
	end
end

--- 줍기 0.18초: 판을 떼어 캐릭터 쪽으로 날리며 줄여 지운다
local function flyAway(entry: StickerEntry, target: Vector3)
	local plate = entry.plate
	if not plate then
		return
	end
	entry.plate = nil
	for _, child in plate:GetChildren() do
		if not child:IsA("SurfaceGui") then
			child:Destroy() -- 빛·파티클·소리는 바로 끈다
		end
	end
	local gui = plate:FindFirstChildOfClass("SurfaceGui")
	local root = if gui then gui:FindFirstChild("Root") else nil
	local scale = if root then root:FindFirstChildOfClass("UIScale") else nil
	local info = TweenInfo.new(FLY_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local fly = TweenService:Create(plate, info, { CFrame = plate.CFrame.Rotation + target })
	if scale then
		TweenService:Create(scale, info, { Scale = 0 }):Play()
	end
	fly.Completed:Once(function()
		plate:Destroy()
	end)
	fly:Play()
end

-- 예측 시점에 소리(개선계획 §3.2 #6·#7). 서버 왕복을 기다리지 않는다.
-- onHeartbeat 가 내 부지(myPlotId = player.Plot, 서버가 정한 주인)일 때만 부른다
local function predictPickup(entry: StickerEntry, rootPos: Vector3)
	entry.pendingAt = os.clock()
	flyAway(entry, rootPos)
	applySticker(entry)
	-- 음높이는 늘 같다. 콤보마다 올리던 5음계는 「줍는 소리가 매번 바뀐다」로 들려서 뺐다
	SoundController.play("sticker")
end

local function unwatchSticker(part: Instance)
	local entry = stickers[part :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns) -- Collected·Gold·Position 구독을 모두 끊는다
	destroyPlate(entry)
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
		pillar = nil,
		plate = nil,
		plateGold = false,
		shape = math.random(1, SHAPE_COUNT),
		spin = 0,
		emitClock = 0,
		chimeClock = 0,
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
			if part:GetAttribute(Keys.ATTR_COLLECTED) ~= true then
				entry.shape = math.random(1, SHAPE_COUNT) -- 리스폰마다 모양을 새로
			end
			applySticker(entry)
		end)
	)
	table.insert(
		entry.conns,
		part:GetAttributeChangedSignal(Keys.ATTR_GOLD):Connect(function()
			applySticker(entry)
		end)
	)
	-- 서버 moveSticker 는 히트박스 Position 만 바꾼다. 판·빛기둥을 새 자리로 옮긴다
	table.insert(
		entry.conns,
		part:GetPropertyChangedSignal("Position"):Connect(function()
			local plate = entry.plate
			if plate then
				plate.CFrame = CFrame.new(platePosition(part)) * CFrame.Angles(0, entry.spin, 0)
			end
			destroyPillar(entry)
			applySticker(entry)
		end)
	)
	applySticker(entry)
end

-- ── 방문객 별 ────────────────────────────────────────────────────

local function destroyStarPlate(entry: StarEntry)
	if entry.plate then
		entry.plate:Destroy()
		entry.plate = nil
		entry.gui = nil
	end
end

--- 방문객 별은 주인 화면에서 안 보인다(§7.5). 남의 부지에서만 판을 그린다.
--- 밟은 방문객에게 60초 숨기기는 FeedbackController 가 히트박스 LocalTransparencyModifier 로 하고, onHeartbeat 가 판에 옮긴다
local function applyStar(entry: StarEntry)
	if entry.plotId == myPlotId then
		destroyStarPlate(entry)
		return
	end
	if not entry.plate then
		local plate, gui, scale = newPlate("StarPlate", entry.part, SHAPE_STAR, COLOR_STAR)
		entry.plate = plate
		entry.gui = gui
		scale.Scale = 1
	end
end

local function unwatchStar(part: Instance)
	local entry = stars[part :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns)
	destroyStarPlate(entry)
	stars[part :: any] = nil
end

local function watchStar(part: Instance, plotId: number)
	if not part:IsA("BasePart") or stars[part] then
		return
	end
	local entry: StarEntry = { part = part, plotId = plotId, plate = nil, gui = nil, spin = 0, conns = {} }
	stars[part] = entry
	table.insert(
		entry.conns,
		part:GetPropertyChangedSignal("Position"):Connect(function()
			local plate = entry.plate
			if plate then
				plate.CFrame = CFrame.new(platePosition(part)) * CFrame.Angles(0, entry.spin, 0)
			end
		end)
	)
	applyStar(entry)
end

-- ── 칭찬스티커판 ─────────────────────────────────────────────────

local function unwatchBoard()
	if board then
		board.root:Destroy()
		board = nil
	end
end

--- 칸을 채운다. 40칸을 채워 선물이 되면(칸이 줄면) 판이 금색으로 번쩍이고 남은 칸이 다시 찬다
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

--- 파트를 땅 아래 6 스터드에서 Back Out 0.5초로 솟게 한다. 50ms 뒤 아래쪽 파트부터 0.05초 간격
local function appear(parts: { BasePart })
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	for i, part in parts do
		part.LocalTransparencyModifier = 1
		local target = part.CFrame
		part.CFrame = target - Vector3.new(0, APPEAR_DROP, 0)
		local delay = APPEAR_DELAY + (i - 1) * APPEAR_STAGGER
		local rise = TweenInfo.new(APPEAR_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, rise, { CFrame = target }):Play()
		-- 투명도는 Back 의 되튐이 0 아래로 내려가면 안 되므로 따로 Quad 로
		local fade =
			TweenInfo.new(APPEAR_SECONDS * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, fade, { LocalTransparencyModifier = 0 }):Play()
	end
end

--- BasePart 의 부품 번호(Geometry 가 붙인 PartIndex). 없으면 nil
local function partIndexOf(inst: Instance): number?
	if not inst:IsA("BasePart") then
		return nil
	end
	local index = inst:GetAttribute(Keys.ATTR_PART_INDEX)
	return if type(index) == "number" then index else nil
end

--- 이번 프레임에 모인 파트를 한 번에 올린다
local function flushAppear(entry: FacilityEntry)
	entry.flushQueued = false
	local parts: { BasePart } = {}
	if facilities[entry.model] == entry then
		for _, part in entry.pending do
			if part:IsDescendantOf(entry.model) then
				table.insert(parts, part)
			end
		end
	end
	table.clear(entry.pending)
	if #parts > 0 then
		appear(parts)
	end
end

--- 새로 붙은 파트를 등장 대기열에 넣는다. 처음 보는 부품 번호이거나 그 번호가 막 등장 중일 때만
local function queueAppear(entry: FacilityEntry, inst: Instance)
	local index = partIndexOf(inst)
	if index == nil then
		return
	end
	local now = os.clock()
	local at = entry.appearedAt[index]
	if at == nil then
		entry.appearedAt[index] = now
	elseif now - at >= APPEAR_GRACE then
		return
	end
	table.insert(entry.pending, inst :: BasePart)
	if not entry.flushQueued then
		entry.flushQueued = true
		task.defer(flushAppear, entry)
	end
end

local function unwatchFacility(model: Instance)
	local entry = facilities[model :: any]
	if not entry then
		return
	end
	disconnectAll(entry.conns)
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
		conns = {},
		appearedAt = {},
		pending = {},
		flushQueued = false,
	}
	facilities[model] = entry
	-- 이미 넣은 부품(ATTR_PARTS)은 animate 면 「방금 등장」, 아니면 「처음부터 있던 것」으로 적는다.
	-- 재접속 복원처럼 한꺼번에 오는 것도, 스트리밍으로 늦게 오는 파트도 이 표를 따른다
	local since = if animate then os.clock() else -math.huge
	local placed = model:GetAttribute(Keys.ATTR_PARTS)
	if type(placed) == "number" then
		for i = 1, placed do
			entry.appearedAt[i] = since
		end
	end
	for _, inst in model:GetDescendants() do
		local index = partIndexOf(inst)
		if index == nil then
			continue
		end
		if entry.appearedAt[index] == nil then
			entry.appearedAt[index] = since
		end
		if animate then
			queueAppear(entry, inst)
		end
	end
	table.insert(
		entry.conns,
		model.DescendantAdded:Connect(function(inst)
			queueAppear(entry, inst)
		end)
	)
end

-- ── 프롬프트 ─────────────────────────────────────────────────────

--- 「우리 학교로」 팻말은 남의 부지에서만 켠다. 광장 팻말은 건드리지 않는다
local function applyPrompt(prompt: ProximityPrompt, plotId: number)
	if prompt.Name == Keys.HOME_PROMPT then
		prompt.Enabled = plotId ~= myPlotId
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

local function watchTowerChild(child: Instance, plotId: number)
	if child.Name == TOWER_PAD then
		watchPad(child, plotId)
	end
end

--- Tower 폴더가 통째로 빠지면 ChildRemoved 가 안 오므로 월드에서 떨어진 패드를 쓸어 낸다
local function sweepDetachedPads()
	for part in pads do
		if not part:IsDescendantOf(Workspace) then
			unwatchPad(part)
		end
	end
end

local function onPlotChildAdded(child: Instance, plotId: number, animate: boolean)
	if child.Name == Keys.PADS_FOLDER then
		watchFolder(child, plotId, watchPad, unwatchPad)
	elseif child.Name == TOWER_FOLDER then
		watchFolder(child, plotId, watchTowerChild, unwatchPad)
	elseif child.Name == Keys.STICKERS_FOLDER then
		watchFolder(child, plotId, watchSticker, unwatchSticker)
	elseif child.Name == Keys.STARS_FOLDER then
		watchFolder(child, plotId, watchStar, unwatchStar)
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
	for part, entry in stars do
		if entry.part:IsDescendantOf(model) then
			unwatchStar(part)
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
			if child.Name == TOWER_FOLDER then
				sweepDetachedPads()
			elseif child:IsA("Model") then
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
	for _, entry in stars do
		applyStar(entry)
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

--- 층 패드에 서 있는 동안 고를 방이 생기면(올라섬·옥상 방 완공) 방 고르기 패널을 한 번 연다. 내려오면 닫는다
local towerPrompted = false
local function onTowerStand(standing: boolean, changed: boolean)
	if not PanelController then
		return
	end
	if standing then
		local profile = HudController.profile()
		if not profile or profile.towerRoom ~= "" then
			towerPrompted = false -- 짓는 중. 완공되면 다시 연다
		elseif not towerPrompted and RoomConfig.nextStep(profile) then
			towerPrompted = true
			PanelController.open("room")
		end
	elseif changed then
		towerPrompted = false
		if PanelController.current() == "room" then
			PanelController.close()
		end
	end
end

local function onHeartbeat(dt: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local rootPos: Vector3? = nil
	if root and root:IsA("BasePart") then
		rootPos = root.Position
	end
	local now = os.clock()
	-- 저사양이면 회전·파티클만 뺀다. 등장 팝·줍기 날아가기·세로 빛·반짝 소리는 그대로(§3.2 #3·#9)
	local lowSpec = StudentRenderController.isLowSpec() == true
	for _, entry in stickers do
		if entry.plotId ~= myPlotId then
			continue
		end
		local plate = entry.plate
		if plate then
			if not lowSpec then
				local period = if entry.plateGold then GOLD_SPIN_SECONDS else SPIN_SECONDS
				entry.spin = (entry.spin + dt * 2 * math.pi / period) % (2 * math.pi)
				entry.emitClock += dt
				if entry.emitClock >= EMIT_INTERVAL then
					entry.emitClock = 0
					local emitter = plate:FindFirstChildOfClass("ParticleEmitter")
					if emitter then
						emitter:Emit(EMIT_COUNT)
					end
				end
				-- 저사양이면 회전이 멈추므로 매 프레임 CFrame 을 다시 쓸 이유가 없다. 자리 이동은 Position 신호가 맞춘다
				plate.CFrame = CFrame.new(platePosition(entry.part)) * CFrame.Angles(0, entry.spin, 0)
			end
			entry.chimeClock += dt
			if entry.chimeClock >= CHIME_INTERVAL then
				entry.chimeClock = 0
				local chime = plate:FindFirstChildOfClass("Sound")
				if chime then
					chime.TimePosition = 0
					chime:Play()
				end
			end
		end
		if entry.pendingAt then
			-- 0.5초 안에 Collected 도 확정도 없으면 예측을 되돌린다
			if now - entry.pendingAt > PICKUP_REVERT then
				entry.pendingAt = nil
				applySticker(entry)
			end
		elseif rootPos and not entry.hold and entry.part:GetAttribute(Keys.ATTR_COLLECTED) ~= true then
			-- 수평 2.2·높이 4 안(§3.2 #6). 히트박스 중심 기준
			local offset = entry.part.Position - rootPos
			if Vector2.new(offset.X, offset.Z).Magnitude <= PICKUP_RADIUS and math.abs(offset.Y) <= PICKUP_DY then
				predictPickup(entry, rootPos)
			end
		end
	end
	for _, entry in stars do
		local plate = entry.plate
		local gui = entry.gui
		if not plate or not gui then
			continue
		end
		if not lowSpec then
			entry.spin = (entry.spin + dt * 2 * math.pi / SPIN_SECONDS) % (2 * math.pi)
			plate.CFrame = CFrame.new(platePosition(entry.part)) * CFrame.Angles(0, entry.spin, 0)
		end
		-- FeedbackController 가 밟은 방문객에게 히트박스 LTM 1 로 60초 숨긴다
		gui.Enabled = entry.part.LocalTransparencyModifier < 1
	end

	-- 발판 눌림. 패드는 부지에 3개 이하라 매 프레임 돌려도 싸다
	for _, entry in pads do
		local standing = false
		if rootPos and entry.plotId == myPlotId and entry.state == PAD_ACTIVE then
			local size = entry.part.Size
			local offset = entry.base:PointToObjectSpace(rootPos)
			local top = size.Y / 2
			standing = math.abs(offset.X) <= size.X / 2 + PAD_PRESS_MARGIN
				and math.abs(offset.Z) <= size.Z / 2 + PAD_PRESS_MARGIN
				and offset.Y > top
				and offset.Y - top <= PAD_PRESS_DY
		end
		local changed = standing ~= entry.pressed
		if changed then
			setPressed(entry, standing)
		end
		if entry.facilityId == TOWER_FACILITY and entry.plotId == myPlotId then
			onTowerStand(standing, changed)
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
	local ok, panel = pcall(require, script.Parent.PanelController)
	if ok then
		PanelController = panel
	end
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

--- 층 부품을 샀을 때(FeedbackController). 내 층 패드에서 반짝이가 터지고 고리가 퍼지며 빛기둥이 위층으로 솟는다
function PadController.towerBurst()
	for _, entry in pads do
		local decor = entry.decor
		if decor and entry.plotId == myPlotId and entry.facilityId == TOWER_FACILITY then
			decor.emitter:Emit(BURST_SPARKLES)
			local floor = entry.base * CFrame.new(0, -entry.part.Size.Y / 2, 0)
			local info = TweenInfo.new(BURST_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local wave = newLocalPart(
				"BurstWave",
				Vector3.new(0.15, entry.part.Size.X, entry.part.Size.Z),
				floor * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				COLOR_YELLOW
			)
			wave.Shape = Enum.PartType.Cylinder
			wave.Transparency = 0.2
			local beam = newLocalPart(
				"BurstBeam",
				Vector3.new(entry.part.Size.X * 0.8, 1, entry.part.Size.Z * 0.8),
				floor * CFrame.new(0, 0.5, 0),
				COLOR_GREEN
			)
			beam.Transparency = 0.3
			TweenService:Create(wave, info, { Size = Vector3.new(0.15, BURST_WAVE, BURST_WAVE), Transparency = 1 })
				:Play()
			TweenService:Create(beam, info, {
				Size = Vector3.new(beam.Size.X, BURST_BEAM_H, beam.Size.Z),
				CFrame = floor * CFrame.new(0, BURST_BEAM_H / 2, 0),
				Transparency = 1,
			}):Play()
			task.delay(BURST_SECONDS, function()
				wave:Destroy()
				beam:Destroy()
			end)
			return
		end
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
