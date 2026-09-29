--!strict
--[[
	TutorialController — 말 없는 튜토리얼(기획서 §2)

	글로 가르치지 않는다. 지금 할 일 하나를 말풍선(≤12자)·발자국·손가락·빛기둥으로 가리킬 뿐이다.
	단계는 §2.1 표를 프로필로 계산한다(첫 번째로 참인 행). 서버는 튜토리얼을 모른다 — 전부 클라 로컬 연출.

	★ 대상 위치는 PadController 가 안다(패드·접수대·스티커·스킨 표지판). 아직 스트리밍 전이면 nil 이 오므로
	  매 틱 다시 물어본다. 나를 PadController 가 require 하지 않는다(순환 금지).
	★ §2.3 에스컬레이션: 대상에서 12 스터드 넘게 떨어진 채 30초 → 큰 화살표 3번 + 손가락 4초, 60초 → 카메라 팬.
	  가까이 가면 타이머가 0 으로 돌아간다. 단계 ⑦(끝)도 다음 패드를 대상으로 에스컬레이션만 한다.
	★ 모듈 최상위 부작용 없음. Start() 에서 폴더·앵커를 만든다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Types = require(ReplicatedStorage.Shared.Types)

-- 계획 §3.4 계약(형제 컨트롤러). 형태만 선언하고 any 로 받는다
type HudApi = {
	profile: () -> Types.Profile?,
	onProfile: (fn: (Types.Profile) -> ()) -> (),
}
type PadApi = {
	padPosition: (facilityId: string) -> Vector3?,
	admissionDeskPosition: () -> Vector3?,
	-- 아래 넷은 §3.4 계약 밖. PadController 가 덤으로 낸다
	myPlot: () -> number?,
	plotModel: (plotId: number) -> Model?,
	stickerPosition: (stickerId: any) -> Vector3?,
	skinSignPosition: (facilityId: string) -> Vector3?,
}
type CameraApi = {
	panTo: (worldPos: Vector3, seconds: number) -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local PadController = (require(script.Parent.PadController) :: any) :: PadApi
local CameraController = (require(script.Parent.CameraController) :: any) :: CameraApi

local TutorialController = {}

-- 단계(§2.1)
local STAGE_DESK = 1 -- 책상을 사자
local STAGE_STICKERS = 2 -- 스티커를 줍자
local STAGE_GROW3 = 3 -- 시설 3개까지(말풍선 없음)
local STAGE_GACHA = 4 -- 원서로 뽑아 보자
local STAGE_GROW4 = 5 -- 이제 학교를 키우자
local STAGE_SKIN = 6 -- 색을 바꿔 보자(세션 1회)
local STAGE_DONE = 7 -- 끝. 에스컬레이션만

-- 말풍선(≤12자)
local BUBBLE_DESK = "책상을 사자!"
local BUBBLE_STICKERS = "스티커를 줍자!"
local BUBBLE_GACHA = "원서로 뽑아 보자!"
local BUBBLE_GROW = "이제 학교를 키우자!"
local BUBBLE_SKIN = "색을 바꿔 보자!"
local FINGER_TEXT = "👇"
local ARROW_TEXT = "⬇"

-- 단계 문턱(§2.1)
local STICKER_HINT_COUNT = EconomyConfig.STICKER_HOME_UNTIL -- 앞마당 스티커 1~3번(서버 홈 리스폰 기준과 같은 값)
local GROW3_FACILITIES = 3
local GROW4_FACILITIES = 4
local SKIN_HINT_FACILITIES = 5
local REENTRY_TICKETS = 3 -- ⑦에서 원서 3장인데 한 번도 안 뽑았으면 ④로

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
local SKIN_PILLAR_SECONDS = 8
local FINGER_SIZE = 64
local FINGER_HEIGHT = 4
local FINGER_BOUNCE = 1.2
local FINGER_BOUNCE_SECONDS = 0.45
local ARROW_SIZE = 216
local ARROW_HEIGHT = 10
local ARROW_BLINKS = 3
local ARROW_BLINK_SECONDS = 0.3
local ESCALATE_FINGER_SECONDS = 4
local STUCK_DISTANCE = 12
local STUCK_FIRST = 30
local STUCK_SECOND = 60
local PAN_SECONDS = 0.6
local TICK = 0.25
local BILLBOARD_DISTANCE = 150

-- 색(§8.1)
local COLOR_PANEL = Color3.fromRGB(31, 41, 55)
local COLOR_YELLOW = Color3.fromRGB(251, 191, 36)
local COLOR_WHITE = Color3.new(1, 1, 1)

type StageSpec = { bubble: string?, footprints: boolean, finger: boolean, pillar: boolean }
local SPECS: { [number]: StageSpec } = {
	[STAGE_DESK] = { bubble = BUBBLE_DESK, footprints = true, finger = true, pillar = true },
	[STAGE_STICKERS] = { bubble = BUBBLE_STICKERS, footprints = true, finger = false, pillar = true },
	[STAGE_GROW3] = { footprints = true, finger = false, pillar = false },
	[STAGE_GACHA] = { bubble = BUBBLE_GACHA, footprints = true, finger = false, pillar = true },
	[STAGE_GROW4] = { bubble = BUBBLE_GROW, footprints = true, finger = false, pillar = false },
	[STAGE_SKIN] = { bubble = BUBBLE_SKIN, footprints = false, finger = false, pillar = true },
	[STAGE_DONE] = { footprints = false, finger = false, pillar = false },
}

local player = Players.LocalPlayer
local started = false
local currentStage = STAGE_DONE
local currentTarget: Vector3? = nil
local visualsReady = false
local bubbleStage = 0 -- 말풍선을 이미 띄운 단계(단계 진입마다 한 번)
local skinHintShown = false -- ⑥ 세션 1회
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
local escalated = false
local tickAccum = 0

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
end

-- ── 단계 계산(§2.1) ─────────────────────────────────────────────

local function skinsOwnedCount(profile: Types.Profile): number
	local count = 0
	for _, owned in profile.skinsOwned do
		if owned then
			count += 1
		end
	end
	return count
end

--- 첫 번째로 참인 행이 단계다
local function computeStage(profile: Types.Profile): number
	local built = FacilityConfig.count(profile.facilities)
	local stats = profile.stats
	local noPulls = stats.totalPulls == 0
	if built == 0 then
		return STAGE_DESK
	end
	if stats.totalStickers < STICKER_HINT_COUNT then
		return STAGE_STICKERS
	end
	if built < GROW3_FACILITIES then
		return STAGE_GROW3
	end
	if profile.tickets >= 1 and noPulls then
		return STAGE_GACHA
	end
	if built < GROW4_FACILITIES then
		return STAGE_GROW4
	end
	if built >= SKIN_HINT_FACILITIES and skinsOwnedCount(profile) == 0 and not skinHintShown then
		return STAGE_SKIN
	end
	if noPulls and profile.tickets >= REENTRY_TICKETS then
		return STAGE_GACHA -- ⑦ 재진입
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
	elseif stage == STAGE_GACHA then
		return PadController.admissionDeskPosition()
	elseif stage == STAGE_SKIN then
		return PadController.skinSignPosition(FacilityConfig.ORDER[1])
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
	local stage = computeStage(profile)
	local target = resolveTarget(stage, profile)
	local stageChanged = stage ~= currentStage
	local targetChanged = target ~= currentTarget
	currentStage = stage
	currentTarget = target
	if stageChanged then
		stuck = 0
		escalated = false
		hideBubble()
		if stage == STAGE_SKIN then
			-- 빛기둥 8초 뒤 세션 플래그를 세우고 ⑦로 넘어간다
			task.delay(SKIN_PILLAR_SECONDS, function()
				if currentStage == STAGE_SKIN then
					skinHintShown = true
					TutorialController.refresh()
				end
			end)
		end
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
	local profile = HudController.profile()
	if not profile then
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
		escalated = false
		return
	end
	stuck += step
	if not escalated and stuck >= STUCK_FIRST then
		escalated = true
		escalate()
	end
	if stuck >= STUCK_SECOND then
		CameraController.panTo(target, PAN_SECONDS)
		stuck = 0
		escalated = false
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

	player.CharacterAdded:Connect(onCharacter)
	HudController.onProfile(apply)
	RunService.Heartbeat:Connect(tick)
end

--- 프로필이 바뀌었을 때(init.client 가 FacilityBuilt 뒤에 부른다). onProfile 로도 따라가므로 겹쳐도 무해
function TutorialController.refresh()
	local profile = HudController.profile()
	if profile then
		apply(profile)
	end
end

--- 현재 단계 1~7(§2.1)
function TutorialController.stage(): number
	return currentStage
end

return TutorialController
