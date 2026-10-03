--!strict
--[[
	TutorialController — 말 없는 튜토리얼(기획서 §2)

	글로 가르치지 않는다. 지금 할 일 하나를 말풍선(≤12자)·발자국·손가락·빛기둥으로 가리킬 뿐이다.
	단계는 §2.1 표를 프로필로 계산한다(첫 번째로 참인 행). 서버는 튜토리얼을 모른다 — 전부 클라 로컬 연출.

	★ 대상 위치는 PadController 가 안다(패드·스티커). 아직 스트리밍 전이면 nil 이 오므로
	  매 틱 다시 물어본다. 나를 PadController 가 require 하지 않는다(순환 금지).
	★ §2.3 에스컬레이션: 대상에서 12 스터드 넘게 떨어진 채 30초 → 큰 화살표 3번 + 손가락 4초, 60초 → 카메라 팬.
	  가까이 가면 타이머가 0 으로 돌아간다. 단계 ⑥(끝)도 다음 패드를 대상으로 에스컬레이션만 한다.
	★ 단계 ⑤(꾸미기)는 월드 대상이 없다. HUD 「꾸미기」 버튼 옆 2D 손가락 + 버튼 펄스. 시트를 열거나 처음 놓으면 끝.
	  에스컬레이션은 30초 뒤 말풍선을 한 번 더 띄우는 것뿐이다(팬할 월드 위치가 없다).
	★ 층 안내: 층 방을 완공하면(profile.floors 가 늘면) 층 패드가 새 층으로 옮겨 간다. 화면 위 글 + 큰 「⬇」 화살표·빛기둥으로
	  지금 층의 엘리베이터 → 새 층의 층 패드를 차례로 가리키고, 그 패드에 올라서면 끝. 튜토리얼 단계와 따로 돈다.
	★ 모듈 최상위 부작용 없음. Start() 에서 폴더·앵커를 만든다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local Types = require(ReplicatedStorage.Shared.Types)

-- 계획 §3.4 계약(형제 컨트롤러). 형태만 선언하고 any 로 받는다
type HudApi = {
	profile: () -> Types.Profile?,
	onProfile: (fn: (Types.Profile) -> ()) -> (),
	myPlotId: () -> number?,
	isOnOwnPlot: () -> boolean,
	pulseDecorButton: (on: boolean) -> (),
	decorButtonRect: () -> (Vector2?, Vector2?),
	guideSlot: () -> Frame?,
}
type PanelApi = {
	current: () -> string?,
}
type DecorApi = {
	isActive: () -> boolean,
}
type PadApi = {
	padPosition: (facilityId: string) -> Vector3?,
	-- 아래 셋은 §3.4 계약 밖. PadController 가 덤으로 낸다
	myPlot: () -> number?,
	plotModel: (plotId: number) -> Model?,
	stickerPosition: (stickerId: any) -> Vector3?,
}
type CameraApi = {
	panTo: (worldPos: Vector3, seconds: number) -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local PadController = (require(script.Parent.PadController) :: any) :: PadApi
local CameraController = (require(script.Parent.CameraController) :: any) :: CameraApi
local PanelController = (require(script.Parent.PanelController) :: any) :: PanelApi
local DecorController = (require(script.Parent.DecorController) :: any) :: DecorApi

local TutorialController = {}

-- 단계(§2.1)
local STAGE_DESK = 1 -- 책상을 사자
local STAGE_STICKERS = 2 -- 스티커를 줍자
local STAGE_GROW3 = 3 -- 시설 3개까지(말풍선 없음)
local STAGE_GROW4 = 4 -- 이제 학교를 키우자
local STAGE_DECOR = 5 -- 꾸며 보자(HUD 「꾸미기」 버튼)
local STAGE_DONE = 6 -- 끝. 에스컬레이션만

-- 말풍선(≤12자)
local BUBBLE_DESK = "책상을 사자!"
local BUBBLE_STICKERS = "스티커를 줍자!"
local BUBBLE_GROW = "이제 학교를 키우자!"
local BUBBLE_DECOR = "꾸며 보자!"
local HUD_FINGER_TEXT = "👆"
local PANEL_DECOR = "decor" -- PanelController.PanelName
local FINGER_TEXT = "👇"
local ARROW_TEXT = "⬇"

-- 단계 문턱(§2.1)
local STICKER_HINT_COUNT = EconomyConfig.STICKER_HOME_UNTIL -- 앞마당 스티커 1~3번(서버 홈 리스폰 기준과 같은 값)
-- 안 A 시뮬 활동형에서 시설 3 은 0:52, 시설 4 는 1:16 이라 임계값을 바꾸지 않는다(개선계획 §3.4 #11)
local GROW3_FACILITIES = 3
local GROW4_FACILITIES = 4

-- 연출 수치(§2.2·§2.3). 클라 전용이라 공용 Config 에 없다
local BUBBLE_SECONDS = 8
local BUBBLE_TEXT = 26
local BUBBLE_OFFSET = 2.2 -- 머리 위 스터드
local FOOTPRINT_SIZE = Vector3.new(1.2, 0.1, 2)
local FOOTPRINT_LIFT = 0.15
local FOOTPRINT_DIM = 0.65
local FOOTPRINT_STEP = 0.35
-- 앞마당 → 현관 → 복도 → 교실1 문. 부지 로컬 좌표(FacilityConfig 의 책상 패드 (-60, -37.5) 쪽으로)
-- TODO(통합): PlotShell 의 실제 복도 좌표에 맞춰 손봐야 할 수 있다
local FOOTPRINT_PATH = {
	Vector3.new(0, 0, 37.5),
	Vector3.new(0, 0, 12.5),
	Vector3.new(-7.5, 0, -22.5),
	Vector3.new(-32.5, 0, -25),
	Vector3.new(-55, 0, -37.5),
}
local PILLAR_SIZE = Vector3.new(1, 14, 1)
local PILLAR_ALPHA = 0.5
local PILLAR_PULSE_ALPHA = 0.8
local PILLAR_PULSE_SECONDS = 0.8
local FINGER_SIZE = 64
local FINGER_HEIGHT = 4
local FINGER_BOUNCE = 1.2
local FINGER_BOUNCE_SECONDS = 0.45
local ARROW_SIZE = 216
local ARROW_HEIGHT = 10
local ARROW_BLINKS = 3
local ARROW_BLINK_SECONDS = 0.3
local ESCALATE_FINGER_SECONDS = 4
local HUD_FINGER_SIZE = 48 -- px. 「꾸미기」 버튼 바로 아래에서 위를 가리킨다
local HUD_FINGER_GAP = 4
local HUD_FINGER_BOUNCE = 8
local STUCK_DISTANCE = 12
local STUCK_FIRST = 30
local STUCK_SECOND = 60 -- 목표 밖에서 가만히 서 있은 시간(걷는 중·패널·꾸미기 중에는 0 으로)
local MOVING = 0.1 -- Humanoid.MoveDirection 크기가 이보다 크면 걷는 중
local PAN_SECONDS = 0.6
local TICK = 0.25
local BILLBOARD_DISTANCE = 150
-- 층 안내
local GUIDE_DELAY = 2.5 -- 층 완공 축하(카드·학생 등장)가 지나간 뒤에 띄운다
local GUIDE_DONE_DISTANCE = 3 -- 층 패드에서 수평 이만큼 안이면 끝
local GUIDE_FLOOR_SLACK = 1 -- 캐릭터 층 판정: 그 층 바닥보다 이만큼 아래까지 그 층
local GUIDE_ELEVATOR_UP = 5 -- 타는 곳 바닥에서 화살표 앵커까지(+ GUIDE_ARROW_HEIGHT = 표지판 바로 위)
local GUIDE_PAD_UP = 1
local GUIDE_ARROW_SIZE = 120
local GUIDE_ARROW_HEIGHT = 3.5

-- 색(§8.1)
local COLOR_PANEL = Color3.fromRGB(31, 41, 55)
local COLOR_YELLOW = Color3.fromRGB(251, 191, 36)
local COLOR_WHITE = Color3.new(1, 1, 1)

-- hud = HUD 「꾸미기」 버튼을 가리키는 2D 손가락 + 버튼 펄스
type StageSpec = { bubble: string?, footprints: boolean, finger: boolean, pillar: boolean, hud: boolean? }
local SPECS: { [number]: StageSpec } = {
	[STAGE_DESK] = { bubble = BUBBLE_DESK, footprints = true, finger = true, pillar = true },
	[STAGE_STICKERS] = { bubble = BUBBLE_STICKERS, footprints = true, finger = false, pillar = true },
	[STAGE_GROW3] = { footprints = true, finger = false, pillar = false },
	[STAGE_GROW4] = { bubble = BUBBLE_GROW, footprints = true, finger = false, pillar = false },
	[STAGE_DECOR] = { bubble = BUBBLE_DECOR, footprints = false, finger = false, pillar = false, hud = true },
	[STAGE_DONE] = { footprints = false, finger = false, pillar = false },
}

local player = Players.LocalPlayer
local started = false
local currentStage = STAGE_DONE
local currentTarget: Vector3? = nil
local visualsReady = false
local bubbleStage = 0 -- 말풍선을 이미 띄운 단계(단계 진입마다 한 번)
local guiFolder: Folder? = nil
local fxFolder: Folder? = nil
local anchor: BasePart? = nil -- 대상 위치의 보이지 않는 파트. 손가락·화살표가 붙는다
local bubble: BillboardGui? = nil
local bubbleToken = 0
local finger: BillboardGui? = nil
local arrow: BillboardGui? = nil
local pillars: { BasePart } = {}
local footprints: { BasePart } = {}
local footprintToken = 0
local stuck = 0
local idle = 0 -- 카메라 팬용. 움직이는 동안 팬하면 조작을 빼앗으므로 따로 센다
local escalated = false
local tickAccum = 0
local hudGui: ScreenGui? = nil -- 2D 손가락(PlayerGui 바로 아래)
local hudFinger: Frame? = nil
local decorSeen = false -- 이번 접속에서 꾸미기 시트를 열었다
local guideFloor: number? = nil -- 층 안내 중이면 새로 지은 층
local guideFloorCount = -1 -- 마지막으로 본 강당 + 층 방 수(-1 = 아직 모름)
local guideLabel: TextLabel? = nil
local guideAnchor: BasePart? = nil
local guideArrow: BillboardGui? = nil
local guidePillar: BasePart? = nil

-- ── 저수준 헬퍼 ──────────────────────────────────────────────────

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function headPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	return if head and head:IsA("BasePart") then head else nil
end

local function newPart(name: string, size: Vector3, cframe: CFrame, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = COLOR_YELLOW
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = fxFolder
	return part
end

local function newBillboard(name: string, size: number, height: number, text: string, textSize: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	local at = anchor
	if at then
		gui.Adornee = at
	end
	gui.Size = UDim2.fromOffset(size, size)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BILLBOARD_DISTANCE
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = COLOR_YELLOW
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = guiFolder
	return gui
end

-- ── 연출 요소 ────────────────────────────────────────────────────

local function hideBubble()
	bubbleToken += 1
	if bubble then
		bubble:Destroy()
		bubble = nil
	end
end

--- 머리 위 말풍선. 탭하면 닫히고 8초면 저절로 닫힌다
local function showBubble(text: string)
	hideBubble()
	local head = headPart()
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Bubble"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(320, 64)
	gui.StudsOffset = Vector3.new(0, BUBBLE_OFFSET, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Active = true
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = COLOR_PANEL
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = BUBBLE_TEXT
	button.TextColor3 = COLOR_WHITE
	button.Text = text
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_YELLOW
	stroke.Thickness = 3
	stroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = button
	button.Activated:Connect(hideBubble)
	gui.Parent = guiFolder
	bubble = gui
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	local mine = bubbleToken
	task.delay(BUBBLE_SECONDS, function()
		if bubbleToken == mine then
			hideBubble()
		end
	end)
end

local function placeAnchor(target: Vector3)
	if anchor then
		anchor.Position = target
	end
end

local function hideFinger()
	if finger then
		finger:Destroy()
		finger = nil
	end
end

--- 「👇」 손가락. 대상 위에서 위아래로 튄다
local function showFinger()
	if finger then
		return
	end
	local gui = newBillboard("Finger", FINGER_SIZE, FINGER_HEIGHT, FINGER_TEXT, FINGER_SIZE - 8)
	finger = gui
	local bounce = TweenInfo.new(FINGER_BOUNCE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(gui, bounce, { StudsOffset = Vector3.new(0, FINGER_HEIGHT + FINGER_BOUNCE, 0) }):Play()
end

local function hideHudFinger()
	if hudFinger then
		hudFinger:Destroy()
		hudFinger = nil
	end
end

--- HUD 「꾸미기」 버튼 아래에 붙인다. 버튼이 안 보이면 숨긴다(매 틱 다시 맞춘다)
local function placeHudFinger()
	local holder = hudFinger
	if not holder then
		return
	end
	local position, size = HudController.decorButtonRect()
	if not (position and size) then
		holder.Visible = false
		return
	end
	holder.Visible = true
	holder.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y + HUD_FINGER_GAP)
end

--- 「👆」 2D 손가락. 버튼 쪽으로 위아래로 튄다
local function showHudFinger()
	local gui = hudGui
	if hudFinger or not gui then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "DecorFinger"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Size = UDim2.fromOffset(HUD_FINGER_SIZE, HUD_FINGER_SIZE + HUD_FINGER_BOUNCE)
	holder.BackgroundTransparency = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(HUD_FINGER_SIZE, HUD_FINGER_SIZE)
	label.Position = UDim2.fromOffset(0, HUD_FINGER_BOUNCE)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = HUD_FINGER_SIZE - 8
	label.TextColor3 = COLOR_YELLOW
	label.TextStrokeTransparency = 0.3
	label.Text = HUD_FINGER_TEXT
	label.Parent = holder
	holder.Parent = gui
	hudFinger = holder
	placeHudFinger()
	local bounce = TweenInfo.new(FINGER_BOUNCE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(label, bounce, { Position = UDim2.fromOffset(0, 0) }):Play()
end

--- 큰 「⬇」 화살표. 에스컬레이션 때만 켜서 3번 깜빡인다
local function blinkArrow()
	local gui = arrow or newBillboard("Arrow", ARROW_SIZE, ARROW_HEIGHT, ARROW_TEXT, ARROW_SIZE - 16)
	arrow = gui
	task.spawn(function()
		for _ = 1, ARROW_BLINKS do
			if arrow ~= gui then
				return
			end
			gui.Enabled = true
			task.wait(ARROW_BLINK_SECONDS)
			if arrow ~= gui then
				return
			end
			gui.Enabled = false
			task.wait(ARROW_BLINK_SECONDS)
		end
	end)
end

local function addPillar(at: Vector3)
	local part = newPart("Pillar", PILLAR_SIZE, CFrame.new(at + Vector3.new(0, PILLAR_SIZE.Y / 2, 0)), PILLAR_ALPHA)
	table.insert(pillars, part)
	local pulse = TweenInfo.new(PILLAR_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(part, pulse, { Transparency = PILLAR_PULSE_ALPHA }):Play()
end

--- 발자국 5개. 앞마당에서 교실1 문까지 고정 경로를 차례로 밝힌다
local function buildFootprints(pivot: CFrame)
	for i, point in FOOTPRINT_PATH do
		local cframe = pivot * CFrame.new(point + Vector3.new(0, FOOTPRINT_LIFT, 0))
		table.insert(footprints, newPart(`Footprint{i}`, FOOTPRINT_SIZE, cframe, FOOTPRINT_DIM))
	end
	footprintToken += 1
	local mine = footprintToken
	task.spawn(function()
		local lit = 1
		while footprintToken == mine do
			for j, part in footprints do
				part.Transparency = if j == lit then 0 else FOOTPRINT_DIM
			end
			lit = lit % #footprints + 1
			task.wait(FOOTPRINT_STEP)
		end
	end)
end

--- 말풍선만 빼고 다 치운다(말풍선은 단계가 바뀔 때만)
local function clearVisuals()
	footprintToken += 1
	for _, part in footprints do
		part:Destroy()
	end
	table.clear(footprints)
	for _, part in pillars do
		part:Destroy()
	end
	table.clear(pillars)
	hideFinger()
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
	hideHudFinger()
	HudController.pulseDecorButton(false)
end

-- ── 층 안내 ──────────────────────────────────────────────────────

local function stopGuide()
	guideFloor = nil
	for _, inst in { guideLabel, guideAnchor, guideArrow, guidePillar } :: { Instance? } do
		if inst then
			inst:Destroy()
		end
	end
	guideLabel, guideAnchor, guideArrow, guidePillar = nil, nil, nil, nil
end

--- 부지 로컬 높이 y 에 선 캐릭터의 층(1층·2층 강당·3층 이상)
local function floorAt(y: number): number
	local n = 1
	while n < RoomConfig.MAX_FLOOR + 1 and y >= RoomConfig.floorY(n + 1) - GUIDE_FLOOR_SLACK do
		n += 1
	end
	return n
end

local function startGuide(n: number)
	stopGuide()
	guideFloor = n
	-- 글은 HUD 카드 아래 칸을 채운다(HUD 스케일·상단 바 배치를 그대로 따른다. 화면 가운데를 가리지 않게)
	local label = Instance.new("TextLabel")
	label.Name = "FloorGuide"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLOR_PANEL
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = COLOR_WHITE
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_YELLOW
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	label.Parent = HudController.guideSlot()
	guideLabel = label

	local at = newPart("GuideAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), 1)
	guideAnchor = at
	local arrowGui = newBillboard("GuideArrow", GUIDE_ARROW_SIZE, GUIDE_ARROW_HEIGHT, ARROW_TEXT, GUIDE_ARROW_SIZE - 16)
	arrowGui.Adornee = at
	local bounce = TweenInfo.new(FINGER_BOUNCE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(arrowGui, bounce, { StudsOffset = Vector3.new(0, GUIDE_ARROW_HEIGHT + FINGER_BOUNCE, 0) })
		:Play()
	guideArrow = arrowGui
	local pillar = newPart("GuidePillar", PILLAR_SIZE, CFrame.new(), PILLAR_ALPHA)
	local pulse = TweenInfo.new(PILLAR_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(pillar, pulse, { Transparency = PILLAR_PULSE_ALPHA }):Play()
	guidePillar = pillar
end

--- 매 틱: 지금 층이 새 층이 아니면 그 층 엘리베이터, 새 층이면 층 패드를 가리킨다. 패드에 올라서면 끝
local function updateGuide()
	local n = guideFloor
	local label, at, arrowGui, pillar = guideLabel, guideAnchor, guideArrow, guidePillar
	if not n or not label or not at or not arrowGui or not pillar then
		return
	end
	local plotId = HudController.myPlotId()
	local plot = if plotId then PadController.plotModel(plotId) else nil
	local origin = rootPosition()
	local onOwnPlot = HudController.isOnOwnPlot()
	-- 남의 부지에선 칸을 「멋져요」가 쓰니 안내 글을 숨긴다
	label.Visible = onOwnPlot
	local here = if plot and origin and onOwnPlot then floorAt(plot:GetPivot():PointToObjectSpace(origin).Y) else nil
	local target: Vector3? = nil -- 화살표 앵커
	local floorSpot: Vector3? = nil -- 빛기둥 밑동(엘리베이터 타는 곳 바닥). 패드는 패드 장식이 대신한다
	if here == n then
		local pad = PadController.padPosition(Keys.TOWER_PAD_ID)
		if pad and origin and Vector3.new(pad.X - origin.X, 0, pad.Z - origin.Z).Magnitude <= GUIDE_DONE_DISTANCE then
			stopGuide()
			return
		end
		label.Text = `{n}층 발판에서 계속 지어요!`
		target = if pad then pad + Vector3.new(0, GUIDE_PAD_UP, 0) else nil
	else
		label.Text = `엘리베이터를 타고 {n}층으로 가요!`
		if here and plot then
			local spot = PlotLayout.elevatorSpot(here)
			local base = plot:GetPivot() * Vector3.new(spot.X, RoomConfig.floorY(here), spot.Z)
			floorSpot = base
			target = base + Vector3.new(0, GUIDE_ELEVATOR_UP, 0)
		end
	end
	arrowGui.Enabled = target ~= nil
	if target then
		at.Position = target
	end
	pillar.Parent = if floorSpot then fxFolder else nil
	if floorSpot then
		pillar.CFrame = CFrame.new(floorSpot + Vector3.new(0, PILLAR_SIZE.Y / 2, 0))
	end
end

--- 강당·층 방이 새로 서면(완공) 축하가 지나간 뒤 안내를 켠다. 첫 프로필은 기준만 잡는다
local function watchFloors(profile: Types.Profile)
	local count = #profile.floors + (if profile.facilities.auditorium then 1 else 0)
	if guideFloorCount >= 0 and count > guideFloorCount then
		local n = RoomConfig.topFloor(#profile.floors)
		task.delay(GUIDE_DELAY, function()
			if guideFloorCount == count then
				startGuide(n)
			end
		end)
	end
	guideFloorCount = count
end

-- ── 단계 계산(§2.1) ─────────────────────────────────────────────

--- 내 부지 PlotState 의 Decor 어트리뷰트가 비었나(아직 하나도 안 놓음). 폴더가 아직 없으면 false
local function plotDecorEmpty(): boolean
	local plotId = HudController.myPlotId()
	local states = ReplicatedStorage:FindFirstChild(Keys.PLOT_STATE_FOLDER)
	local state = if plotId and states then states:FindFirstChild(Keys.plotName(plotId)) else nil
	if not state then
		return false
	end
	local raw = state:GetAttribute(Keys.ATTR_DECOR)
	return raw == nil or raw == ""
end

--- 꾸미기 단계 조건: 시설 4 이상, 보관함에 화분, 아직 하나도 안 놓았고 이번 접속에 시트를 안 열었다
local function decorPending(profile: Types.Profile): boolean
	return not decorSeen and (profile.decorOwned[DecorConfig.TUTORIAL_ITEM] or 0) >= 1 and plotDecorEmpty() -- ProfileSync 에는 decorPlaced 가 없다. 놓은 것은 Decor 어트리뷰트로 본다
end

--- 첫 번째로 참인 행이 단계다
local function computeStage(profile: Types.Profile): number
	local built = FacilityConfig.count(profile.facilities)
	local stats = profile.stats
	-- 책상 첫 부품은 시작 용돈으로 산다. 수입은 완공 때만 붙으므로 부품 2·3 은 스티커로 사야 해서
	-- 부품 1 뒤에는 시설이 0 이어도 스티커로 보내고, 스티커를 다 주우면 책상 패드로 돌려보낸다
	if FacilityConfig.partsBuilt(profile.facilities, profile.buildParts) == 0 then
		return STAGE_DESK
	end
	if stats.totalStickers < STICKER_HINT_COUNT then
		return STAGE_STICKERS
	end
	if built == 0 then
		-- 스티커를 다 주웠어도 다음 부품 살 돈이 없으면 스티커로 보낸다
		local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
		if nextPart and profile.coins < FacilityConfig.partPriceOf(nextPart.facility.id, nextPart.index) then
			return STAGE_STICKERS
		end
		return STAGE_DESK -- 책상 마저 짓기
	end
	if built < GROW3_FACILITIES then
		return STAGE_GROW3
	end
	if built < GROW4_FACILITIES then
		return STAGE_GROW4
	end
	if decorPending(profile) then
		return STAGE_DECOR
	end
	return STAGE_DONE
end

--- 앞마당 스티커 1~3 중 가장 가까운 것
local function nearestSticker(): Vector3?
	local origin = rootPosition()
	local best: Vector3? = nil
	local bestDistance = math.huge
	for i = 1, STICKER_HINT_COUNT do
		local at = PadController.stickerPosition(i)
		if at then
			local distance = if origin then (at - origin).Magnitude else 0
			if distance < bestDistance then
				best = at
				bestDistance = distance
			end
		end
	end
	return best
end

--- 단계의 대상 위치. 아직 스트리밍 전이면 nil
local function resolveTarget(stage: number, profile: Types.Profile): Vector3?
	if stage == STAGE_DESK then
		return PadController.padPosition(FacilityConfig.ORDER[1])
	elseif stage == STAGE_STICKERS then
		return nearestSticker()
	elseif stage == STAGE_DECOR then
		return nil -- 월드 대상 없음(HUD 버튼)
	end
	local nextRow = FacilityConfig.nextOf(profile.facilities)
	return if nextRow then PadController.padPosition(nextRow.id) else nil
end

--- 단계 연출을 세운다. 필요한 위치가 아직 없으면 false(다음 틱에 다시)
local function buildVisuals(stage: number): boolean
	local spec = SPECS[stage]
	local target = currentTarget
	if (spec.finger or spec.pillar) and not target then
		return false
	end
	local plotId = PadController.myPlot()
	local plot = if plotId then PadController.plotModel(plotId) else nil
	if spec.footprints and not plot then
		return false
	end
	clearVisuals()
	if target then
		placeAnchor(target)
	end
	if spec.pillar and target then
		if stage == STAGE_STICKERS then
			for i = 1, STICKER_HINT_COUNT do
				local at = PadController.stickerPosition(i)
				if at then
					addPillar(at)
				end
			end
		else
			addPillar(target)
		end
	end
	if spec.finger then
		showFinger()
	end
	if spec.hud then
		showHudFinger()
		HudController.pulseDecorButton(true)
	end
	if spec.footprints and plot then
		buildFootprints(plot:GetPivot())
	end
	if spec.bubble and bubbleStage ~= stage then
		bubbleStage = stage
		showBubble(spec.bubble)
	end
	return true
end

local function apply(profile: Types.Profile)
	watchFloors(profile)
	local stage = computeStage(profile)
	local target = resolveTarget(stage, profile)
	local stageChanged = stage ~= currentStage
	local targetChanged = target ~= currentTarget
	currentStage = stage
	currentTarget = target
	if stageChanged then
		stuck = 0
		idle = 0
		escalated = false
		hideBubble()
	end
	if stageChanged or targetChanged or not visualsReady then
		visualsReady = buildVisuals(stage)
	end
end

-- ── 에스컬레이션(§2.3) ──────────────────────────────────────────

local function escalate()
	blinkArrow()
	if finger then
		return -- 이미 상시 손가락인 단계
	end
	showFinger()
	task.delay(ESCALATE_FINGER_SECONDS, function()
		if not SPECS[currentStage].finger then
			hideFinger()
		end
	end)
end

local function tick(dt: number)
	tickAccum += dt
	if tickAccum < TICK then
		return
	end
	local step = tickAccum
	tickAccum = 0
	updateGuide()
	local profile = HudController.profile()
	if not profile then
		return
	end
	if currentStage == STAGE_DECOR then
		-- 시트를 열면 끝(놓기는 프로필·Decor 어트리뷰트로 끝난다)
		if PanelController.current() == PANEL_DECOR then
			decorSeen = true
			apply(profile)
			return
		end
		placeHudFinger()
		stuck += step
		if not escalated and stuck >= STUCK_FIRST then
			-- 팬할 월드 위치가 없어 말풍선만 한 번 더
			escalated = true
			showBubble(BUBBLE_DECOR)
		end
		return
	end
	if not visualsReady then
		apply(profile)
		if not visualsReady then
			return
		end
	end
	local target = currentTarget
	local origin = rootPosition()
	if not target or not origin then
		return
	end
	if (origin - target).Magnitude <= STUCK_DISTANCE then
		stuck = 0
		idle = 0
		escalated = false
		return
	end
	stuck += step
	if not escalated and stuck >= STUCK_FIRST then
		escalated = true
		escalate()
	end
	if stuck >= STUCK_SECOND then
		-- 팬은 가만히 서 있을 때만이라(아래) 30초 힌트는 따로 60초마다 다시 켠다
		stuck = 0
		escalated = false
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local busy = (humanoid ~= nil and humanoid.MoveDirection.Magnitude > MOVING)
		or PanelController.current() ~= nil
		or DecorController.isActive()
	idle = if busy then 0 else idle + step
	if idle >= STUCK_SECOND then
		CameraController.panTo(target, PAN_SECONDS)
		idle = 0
	end
end

-- 리스폰하면 말풍선을 새 머리에 다시 붙인다
local function onCharacter(character: Model)
	task.spawn(function()
		local head = character:WaitForChild("Head", 5)
		if bubble and head and head:IsA("BasePart") then
			bubble.Adornee = head
		end
	end)
end

-- ── 공개 API ─────────────────────────────────────────────────────

function TutorialController.Start()
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("Folder")
	gui.Name = "TutorialGui"
	gui.Parent = playerGui
	guiFolder = gui

	local fx = Instance.new("Folder")
	fx.Name = "TutorialFx"
	fx.Parent = Workspace
	fxFolder = fx

	anchor = newPart("Anchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), 1)

	-- 2D 손가락. HUD(2) 위, 패널(5) 아래. HUD 와 같은 IgnoreGuiInset 좌표라 버튼 AbsolutePosition 을 그대로 쓴다
	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 3
	screen.Parent = playerGui
	hudGui = screen

	player.CharacterAdded:Connect(onCharacter)
	HudController.onProfile(apply)
	RunService.Heartbeat:Connect(tick)
end

--- 프로필이 바뀌었을 때(init.client 가 PartBuilt·FacilityBuilt 뒤에 부른다). onProfile 로도 따라가므로 겹쳐도 무해
function TutorialController.refresh()
	local profile = HudController.profile()
	if profile then
		apply(profile)
	end
end

--- 현재 단계 1~6(§2.1)
function TutorialController.stage(): number
	return currentStage
end

return TutorialController
