--!nonstrict
--[[
	HUD. 계획서 §7.3 의 규칙은 "덜어내는 것"이다.

	  좌상단  — 지금 몇 학년 몇 반인가, 별은 몇 개인가, 소리 켬/끔
	  하단중앙 — 지금 장착한 업그레이드, 그 아래 이동 모드 (둘 다 작게)
	  가운데  — 알림 한 줄. 상점 결과처럼 연출이 필요 없는 통보
	  수료 배너 — 학년을 끝냈을 때만

	없는 것: 체력바, 미니맵, 퀘스트 로그, 선생님 상태 표시.

	★ 특히 "선생님 상태"를 글자로 띄우지 않는다. Phase 1~4 의 디버그 HUD 에는 있었지만,
	  그게 있으면 소리와 비네트를 아무도 안 본다. 상태를 읽는 능력이 이 게임의 실력이다.

	적발 사유는 FeedbackController 가 실패 연출의 부제로 띄운다. 여기서 또 띄우지 않는다.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local MovementController = require(script.Parent.MovementController)
local SoundController = require(script.Parent.SoundController)

local WAIT_TIMEOUT = 10

local NOTICE_HOLD = 2.6
local NOTICE_FADE = 0.35
local BANNER_HOLD = 4

local MODE_COLORS = {
	SNEAK = Color3.fromRGB(150, 220, 255),
	WALK = Color3.fromRGB(225, 225, 225),
	RUN = Color3.fromRGB(255, 140, 140),
}

--[[
	장착 칸의 글리프. 이미지 에셋을 쓰지 않는 프로젝트라 이모지로 대신한다.
	이름만 나열하면 세 개가 다 비슷한 글자 덩어리로 보이는데,
	앞에 그림이 하나 붙으면 곁눈질로도 어느 것이 켜져 있는지 구분된다.
]]
local UPGRADE_GLYPHS = {
	quietShoes = "👟",
	balance = "⚖️",
	instinct = "👁️",
}

local CHIP_POP = 0.22

local player = Players.LocalPlayer

local HudController = {}

local classLabel: TextLabel
local starLabel: TextLabel
local modeLabel: TextLabel
local noticeLabel: TextLabel
local bannerLabel: TextLabel
local muteButton: TextButton
local chips: { [string]: TextLabel } = {}

local noticeToken = 0
local bannerToken = 0
local shownUpgrades: { [string]: boolean } = {}

local function makeLabel(parent: Instance, name: string, size: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- 좌상단은 상단 인셋 아래에 둔다. 모바일에서 노치와 겹치지 않게
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)

	-- ── 좌상단 ──
	classLabel = makeLabel(gui, "Class", 26, Enum.Font.GothamBold)
	classLabel.Size = UDim2.fromOffset(320, 32)
	classLabel.Position = UDim2.fromOffset(18, 14)
	classLabel.TextXAlignment = Enum.TextXAlignment.Left

	starLabel = makeLabel(gui, "Stars", 20, Enum.Font.GothamMedium)
	starLabel.Size = UDim2.fromOffset(320, 24)
	starLabel.Position = UDim2.fromOffset(18, 46)
	starLabel.TextXAlignment = Enum.TextXAlignment.Left
	starLabel.TextColor3 = Color3.fromRGB(255, 226, 140)

	--[[
		소리 켬/끔. 버튼이 곧 표시등이다 — 껐다는 사실이 화면에 남아 있지 않으면
		음소거해놓고 잊은 사람에게는 "소리가 안 나는 게임"이 된다.

		우상단이 아니라 좌상단 아래에 둔다. 우상단은 로블록스 플레이어 목록 자리고,
		모바일에서는 겹친다. 우하단은 ContextActionService 가 만드는
		달리기/살금 터치 버튼 자리다.
	]]
	muteButton = Instance.new("TextButton")
	muteButton.Name = "Mute"
	muteButton.Size = UDim2.fromOffset(96, 30)
	muteButton.Position = UDim2.fromOffset(18, 78)
	muteButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	muteButton.BackgroundTransparency = 0.55
	muteButton.BorderSizePixel = 0
	muteButton.AutoButtonColor = true
	muteButton.Font = Enum.Font.GothamMedium
	muteButton.TextSize = 16
	muteButton.TextColor3 = Color3.new(1, 1, 1)
	muteButton.Text = ""
	muteButton.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = muteButton

	--[[
		── 하단 중앙: 장착한 업그레이드 ──

		산 물건이 화면 어디에도 안 보이면, 별을 쓴 것이 실제로 무엇을 바꿨는지
		알 방법이 없다. 그렇다고 크게 띄우면 이 HUD 의 규칙("덜어내는 것")이 깨지므로,
		이동 모드 바로 위에 작은 칸으로 눕힌다. 아무것도 없으면 줄 자체가 안 보인다.

		AutomaticSize 를 쓰는 이유는 칸 개수가 0~3 으로 변하기 때문이다.
		너비를 못박으면 하나만 켜졌을 때 가운데가 아니라 왼쪽에 치우쳐 보인다.
	]]
	local chipRow = Instance.new("Frame")
	chipRow.Name = "Equipped"
	chipRow.BackgroundTransparency = 1
	chipRow.AnchorPoint = Vector2.new(0.5, 1)
	chipRow.Position = UDim2.new(0.5, 0, 1, -44)
	chipRow.Size = UDim2.fromOffset(0, 26)
	chipRow.AutomaticSize = Enum.AutomaticSize.X
	chipRow.Parent = gui

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = chipRow

	for order, key in Upgrades.ORDER do
		local def = Upgrades.DEFS[key]
		local chip = makeLabel(chipRow, key, 15, Enum.Font.GothamMedium)
		chip.LayoutOrder = order
		chip.Size = UDim2.fromOffset(0, 26)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		chip.BackgroundTransparency = 0.5
		chip.TextStrokeTransparency = 1
		chip.Text = `{UPGRADE_GLYPHS[key] or "•"} {def.name}`
		chip.Visible = false

		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 8)
		chipCorner.Parent = chip

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = chip

		chips[key] = chip
	end

	-- ── 하단 중앙: 이동 모드 ──
	-- 모바일 터치 버튼(ContextActionService 가 자동 생성)은 오른쪽 아래에 뜨므로 겹치지 않는다.
	modeLabel = makeLabel(gui, "Mode", 18, Enum.Font.GothamMedium)
	modeLabel.Size = UDim2.new(1, 0, 0, 24)
	modeLabel.Position = UDim2.new(0.5, 0, 1, -46)
	modeLabel.AnchorPoint = Vector2.new(0.5, 0)
	modeLabel.TextTransparency = 0.25

	-- ── 알림 한 줄 ──
	noticeLabel = makeLabel(gui, "Notice", 22, Enum.Font.GothamMedium)
	noticeLabel.Size = UDim2.new(1, 0, 0, 30)
	noticeLabel.Position = UDim2.fromScale(0.5, 0.72)
	noticeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	noticeLabel.TextTransparency = 1
	noticeLabel.TextColor3 = Color3.fromRGB(255, 240, 200)

	-- ── 수료 배너 ──
	bannerLabel = makeLabel(gui, "Banner", 34, Enum.Font.GothamBold)
	bannerLabel.Size = UDim2.new(1, 0, 0, 48)
	bannerLabel.Position = UDim2.fromScale(0.5, 0.3)
	bannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerLabel.TextTransparency = 1
	bannerLabel.TextColor3 = Color3.fromRGB(255, 226, 140)
end

local function fadeOut(label: TextLabel, delay: number, token: number, current: () -> number)
	task.delay(delay, function()
		if current() ~= token then
			return
		end
		TweenService:Create(label, TweenInfo.new(NOTICE_FADE), { TextTransparency = 1 }):Play()
	end)
end

local function refreshMute()
	local off = SoundController.isMuted()
	muteButton.Text = if off then "🔇 소리 끔" else "🔊 소리 켬"
	muteButton.TextTransparency = if off then 0.35 else 0
end

local function toggleMute()
	SoundController.toggleMute()
	refreshMute()
end

--[[
	장착 칸 갱신. ProfileUpdated 는 산 직후에도, 접속할 때도 똑같이 온다.
	그래서 "이번에 새로 생긴 것"만 튀어오르게 하고 나머지는 조용히 켠다 —
	재접속할 때마다 세 칸이 다 같이 뛰면 그건 피드백이 아니라 소음이다.
]]
local function refreshChips(owned: { [string]: boolean }?)
	for key, chip in chips do
		local has = owned ~= nil and owned[key] == true
		chip.Visible = has

		if has and not shownUpgrades[key] then
			-- 새로 산 것. 살짝 크게 떴다가 제자리로 — TRANS_BACK 대신 Back/Out 이다
			chip.TextSize = 21
			TweenService
				:Create(
					chip,
					TweenInfo.new(CHIP_POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ TextSize = 15 }
				)
				:Play()
		end
		shownUpgrades[key] = has
	end
end

function HudController.onProfile(packet)
	if not classLabel then
		return
	end
	classLabel.Text = `{packet.grade}학년 {packet.class}반`
	starLabel.Text = `★ {packet.stars}`
	refreshChips(packet.upgrades)
end

function HudController.onNotice(message: string)
	if not noticeLabel then
		return
	end
	noticeToken += 1
	local mine = noticeToken

	noticeLabel.Text = message
	noticeLabel.TextTransparency = 0

	fadeOut(noticeLabel, NOTICE_HOLD, mine, function()
		return noticeToken
	end)
end

function HudController.onGradeCleared(payload)
	if not bannerLabel then
		return
	end
	bannerToken += 1
	local mine = bannerToken

	local minutes = math.floor(payload.totalSeconds / 60)
	local seconds = math.floor(payload.totalSeconds % 60)
	bannerLabel.Text = `🎓 {payload.grade}학년 수료!  {minutes}분 {seconds}초 · ★{payload.stars}`
	bannerLabel.TextTransparency = 0

	fadeOut(bannerLabel, BANNER_HOLD, mine, function()
		return bannerToken
	end)
end

function HudController.Start()
	buildGui()

	-- 터치는 버튼이 받고, 키보드/게임패드는 여기서 받는다. 버튼이 이미 화면에 있으므로
	-- createTouchButton 은 false 다 — 켜면 우하단에 같은 기능이 하나 더 생긴다.
	refreshMute()
	muteButton.Activated:Connect(toggleMute)
	ContextActionService:BindAction("Mute", function(_name, state)
		if state == Enum.UserInputState.Begin then
			toggleMute()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonY)

	--[[
		기본 체력바를 끈다. 이 게임에는 체력이 없다 —
		화면에 체력바가 있으면 "맞으면 깎이는 게임"으로 읽힌다.
		백팩도 끈다. 들고 다니는 물건이 하나도 없다.
	]]
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	-- 이동 모드는 이벤트가 아니라 폴링으로 표시한다.
	-- 표시 하나 때문에 컨트롤러에 시그널을 만들 이유가 없다.
	RunService.RenderStepped:Connect(function()
		local mode = MovementController.getMode()
		modeLabel.Text = MovementConfig.MODES[mode].label
		modeLabel.TextColor3 = MODE_COLORS[mode]
	end)
end

return HudController
