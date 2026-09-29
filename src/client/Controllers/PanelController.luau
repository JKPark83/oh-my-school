--!strict
--[[
	패널 컨트롤러. 기획서 §8.3 의 패널 6개를 코드로 그린다.
	  도감(714×330) · 뽑기(568×300) · 미션(568×300) · 꾸미기(바닥 시트 812×172) · 설정(406×150) · 졸업 확인(전체 화면)

	  ★ 한 번에 하나만 연다. 열기 0.2s Back Out(0.9→1.0), 닫기 0.12s Quad In.
	  ★ ScreenGui "Panels" DisplayOrder 5, IgnoreGuiInset. UIScale = clamp(세로/375, 0.9, 1.6).
	  ★ X 버튼 56×56, 바깥 탭, 안드로이드 뒤로가기(ButtonB) 로 닫는다.
	  ★ 프로필은 HudController.profile() / onProfile() 로만 읽는다(구현계획 §3.4).
	  ★ 서버 호출은 SetSkin / RollGacha / Graduate / SetSetting 네 개. 원서 0장이면 RollGacha 를 안 보낸다.
	  ★ 카메라 흔들림 같은 화면 연출은 FeedbackController.play 에 맡기고 여기서는 패널 안 UI 만 움직인다.
	  ★ 도감 ViewportFrame 은 열 때 만들고 닫을 때 지운다(모바일 메모리).
	  ★ 아이콘 이미지는 아직 없어 이모지·글자로 대신한다. -- TODO(통합): 아이콘 이미지
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local CharacterBuilder = require(Shared.CharacterBuilder)
local Keys = require(Shared.Config.Keys)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local FacilityConfig = require(Shared.Config.FacilityConfig)
local SkinConfig = require(Shared.Config.SkinConfig)
local StudentConfig = require(Shared.Config.StudentConfig)
local GachaConfig = require(Shared.Config.GachaConfig)
local MissionConfig = require(Shared.Config.MissionConfig)

-- 형제 컨트롤러. 계약(구현계획 §3.4)의 함수만 쓴다. 아직 옛 버전이 남아 있을 수 있어 타입은 묻지 않는다
local Controllers = script.Parent
local HudController = require(Controllers.HudController) :: any
-- 순환 require 회피(Feedback → Pad → Panel → Feedback). 쓰는 곳이 한 곳뿐이라 늦게 잇는다
local feedbackCache: any = nil
local function feedback(): any
	if not feedbackCache then
		feedbackCache = require(Controllers.FeedbackController) :: any
	end
	return feedbackCache
end
local SoundController = require(Controllers.SoundController) :: any

type Profile = Types.Profile
type GachaResult = Types.GachaResult
type Tier = Types.Tier

local PanelController = {}

export type PanelName = "codex" | "gacha" | "missions" | "skin" | "settings" | "graduate"

-- ── 상수 ──

local DESIGN_HEIGHT = 375
local SCALE_MIN = 0.9
local SCALE_MAX = 1.6
local OPEN_TIME = 0.2
local CLOSE_TIME = 0.12
local X_SIZE = 56
local GAP = 12
local RADIUS = 16
local TEXT_MIN = 14
local TEXT_MAX = 32

local SIZES: { [string]: Vector2 } = {
	codex = Vector2.new(714, 330),
	gacha = Vector2.new(568, 300),
	missions = Vector2.new(568, 300),
	skin = Vector2.new(812, 172),
	settings = Vector2.new(406, 150),
	graduate = Vector2.new(812, 375), -- 전체 화면 안 내용 영역
}

-- §8.1 색
local PANEL_BG = Color3.fromRGB(31, 41, 55) -- #1F2937
local PANEL_ALPHA = 0.15 -- α0.85
local SURFACE = Color3.fromRGB(55, 65, 81)
local DARK = Color3.fromRGB(17, 24, 39)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREY = Color3.fromRGB(156, 163, 175)
local YELLOW = Color3.fromRGB(251, 191, 36)
local GREEN = Color3.fromRGB(52, 211, 153)
local BLUE = Color3.fromRGB(96, 165, 250)
local RED = Color3.fromRGB(248, 113, 113)
local PURPLE = Color3.fromRGB(167, 139, 250)
local GOLD = Color3.fromRGB(245, 158, 11)

local FONT_BOLD = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium

-- 도감
local CODEX_CELL = Vector2.new(96, 120)
local CODEX_COLUMNS = 6

-- 뽑기(§9.2 타임라인)
local BOARD_DOTS = 10
local SHAKE_TIME = 1.2
local SHAKE_DEG = 6
local SHAKE_STEP = 0.08
local REVEAL_TIME = 0.3
local FLIP_TIME = 0.3
local RESULT_READY = 2.0
local STAMP_DELAY = 0.2
local DUPE_SHOW = 2.0
local STAMP_SOUND = "build" -- 기획서 §9.6: build 가 도장 소리다
local ROLL_TIMEOUT = 8 -- 서버 응답이 이만큼 없으면 버튼을 되살린다
local TIER_SOUND: { [string]: string } = { ["반장"] = "arrive", ["전교1등"] = "fanfare", ["전설"] = "legend" }
local TIER_COLOR: { [string]: Color3 } = { ["반장"] = BLUE, ["전교1등"] = PURPLE, ["전설"] = GOLD }

-- 꾸미기
local PREVIEW_TIME = 3

-- 졸업
local HOLD_TIME = 1.5

-- 설정
local SETTING_ROWS: { { key: Types.SettingKey, icon: string, text: string } } = {
	{ key = "shake", icon = "〰", text = "화면 흔들림" },
	{ key = "sfx", icon = "🔊", text = "효과음" },
	{ key = "haptic", icon = "📳", text = "진동" },
}

local MISSION_ICON: { [string]: string } = { stickers = "⭐", built = "🏫", chair = "🪑" }

-- ── 상태 ──

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local backdrop: TextButton? = nil
local currentName: string? = nil
local currentFrame: Frame? = nil
local currentScale: UIScale? = nil
local currentRefresh: ((Profile) -> ())? = nil
local currentCleanup: { () -> () } = {}
local generation = 0 -- 열 때마다 +1. 늦게 도착한 코루틴이 옛 패널을 만지지 않게 한다
local pendingGacha: GachaResult? = nil
local lastSeq = 0

-- ── 작은 유틸 ──

local function responsiveScale(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(SIZES.skin.X, DESIGN_HEIGHT)
	local byHeight = math.clamp(size.Y / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
	-- 세로 기준(§8.1)이되, 제일 넓은 패널(812)이 가로를 넘지 않게 막는다
	return math.min(byHeight, size.X / SIZES.skin.X)
end

local function tween(
	target: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(target, info, goal)
	t:Play()
	return t
end

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent: Instance, px: number, py: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, py or px)
	p.PaddingBottom = UDim.new(0, py or px)
	p.Parent = parent
	return p
end

local function listLayout(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

local function frame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2?,
	color: Color3?,
	alpha: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.fromScale(0, 0)
	f.BackgroundColor3 = color or SURFACE
	f.BackgroundTransparency = if color then alpha or 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2?,
	maxText: number?,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Size = size
	l.Position = position or UDim2.fromScale(0, 0)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = font or FONT_MEDIUM
	l.TextColor3 = color or WHITE
	l.TextScaled = true
	l.TextWrapped = true
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = TEXT_MIN
	c.MaxTextSize = maxText or TEXT_MAX
	c.Parent = l
	return l
end

local function button(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2?,
	color: Color3?,
	textColor: Color3?,
	maxText: number?
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Size = size
	b.Position = position or UDim2.fromScale(0, 0)
	b.BackgroundColor3 = color or YELLOW
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = FONT_BOLD
	b.TextColor3 = textColor or DARK
	b.TextScaled = true
	b.Parent = parent
	corner(b, RADIUS)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = TEXT_MIN
	c.MaxTextSize = maxText or TEXT_MAX
	c.Parent = b
	return b
end

--- 버튼 활성/비활성. 색만 바꾸지 않고 글자도 함께 바꾼다(회색 + 이유 문구)
local function setEnabled(b: TextButton, enabled: boolean, text: string, color: Color3)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.Text = text
	b.BackgroundColor3 = if enabled then color else GREY
	b.TextColor3 = if enabled then DARK else SURFACE
end

--- 사람 실루엣(머리 원 + 몸통). 원형이 없거나 미보유일 때 뷰포트 대신 쓴다
local function silhouette(parent: Instance, size: UDim2, position: UDim2?, color: Color3?): Frame
	local holder = frame(parent, "Silhouette", size, position)
	local tint = color or DARK
	local head = frame(holder, "Head", UDim2.fromScale(0.38, 0.32), UDim2.fromScale(0.31, 0.08), tint)
	corner(head, 999)
	local body = frame(holder, "Body", UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.2, 0.45), tint)
	corner(body, 14)
	return holder
end

--- 원형 진행 링. 반원 두 개를 UIGradient 로 돌려 채운다. set(0~1)
local function makeRing(parent: Instance, size: number, thickness: number, color: Color3): (Frame, (number) -> ())
	local holder = frame(parent, "Ring", UDim2.fromOffset(size, size))
	local track = frame(holder, "Track", UDim2.fromScale(1, 1))
	corner(track, 999)
	stroke(track, SURFACE, thickness)

	local function half(name: string, x: number, circleX: number): UIGradient
		local clip = frame(holder, name, UDim2.fromScale(0.5, 1), UDim2.fromScale(x, 0))
		clip.ClipsDescendants = true
		local circle = frame(clip, "Circle", UDim2.fromOffset(size, size), UDim2.fromOffset(circleX, 0))
		corner(circle, 999)
		local s = stroke(circle, color, thickness)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.499, 0),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = s
		return g
	end
	local left = half("Left", 0, 0)
	local right = half("Right", 0.5, -size / 2)

	local function set(p: number)
		local v = math.clamp(p, 0, 1)
		right.Rotation = math.min(v, 0.5) / 0.5 * 180
		left.Rotation = 180 + math.max(v - 0.5, 0) / 0.5 * 180
	end
	set(0)
	return holder, set
end

--- 학생 뷰포트. 원형이 없으면 실루엣으로 대신한다
local function studentView(parent: Instance, studentId: string, size: UDim2, position: UDim2?): GuiObject
	local model = CharacterBuilder.build(studentId, CFrame.identity, CharacterBuilder.studentConfig(studentId))
	if not model then
		return silhouette(parent, size, position, GREY)
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.Size = size
	vp.Position = position or UDim2.fromScale(0, 0)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-1, -1, -1)
	local camera = Instance.new("Camera")
	local center, extent = model:GetBoundingBox()
	local dist = math.max(extent.Y, extent.X) * 1.15 + 1.5
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0, extent.Y * 0.1, -dist), center.Position)
	camera.Parent = vp
	vp.CurrentCamera = camera
	model.Parent = vp
	vp.Parent = parent
	return vp
end

local function profileOrNil(): Profile?
	return HudController.profile()
end

local function myPlotId(): number?
	local v = player:GetAttribute(Keys.ATTR_PLOT)
	return if type(v) == "number" then v else nil
end

--- 내 부지 안 시설 모델
local function myFacilityModel(facilityId: string): Model?
	local plotId = myPlotId()
	if not plotId then
		return nil
	end
	local plots = Workspace:FindFirstChild(Keys.PLOTS_FOLDER)
	local plot = if plots then plots:FindFirstChild(Keys.plotName(plotId)) else nil
	local model = if plot then plot:FindFirstChild(facilityId) else nil
	return if model and model:IsA("Model") then model else nil
end

-- ── 껍데기: 열기·닫기 ──

local function ensureGui(): (ScreenGui, TextButton)
	if gui and backdrop then
		return gui, backdrop
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Panels"
	g.DisplayOrder = 5
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false

	-- 바깥 탭 = 닫기. 버튼이라 아래 HUD 로 입력이 새지 않는다
	local b = Instance.new("TextButton")
	b.Name = "Backdrop"
	b.Size = UDim2.fromScale(1, 1)
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.5
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = g
	b.Activated:Connect(function()
		PanelController.close()
	end)

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	backdrop = b
	return g, b
end

local function runCleanup()
	local list = currentCleanup
	currentCleanup = {}
	for _, fn in list do
		local ok, err = pcall(fn :: any)
		if not ok then
			warn(`[Panel] 정리 중 오류: {err}`)
		end
	end
end

--- 즉시 파괴(연출 없음). 다른 패널로 갈아탈 때 쓴다
local function destroyCurrent()
	runCleanup()
	currentRefresh = nil
	if currentFrame then
		currentFrame:Destroy()
	end
	currentFrame = nil
	currentScale = nil
	currentName = nil
end

--- 패널 틀을 만들어 내용 영역을 돌려준다. fullscreen 이면 화면을 덮고 안에 812×375 내용 영역을 둔다
local function openShell(name: PanelName, withClose: boolean): Frame
	local g, b = ensureGui()
	generation += 1
	local size = SIZES[name]
	local isSheet = name == "skin"
	local isFull = name == "graduate"

	local shell = Instance.new("Frame")
	shell.Name = name
	shell.BackgroundColor3 = if isFull then DARK else PANEL_BG
	shell.BackgroundTransparency = if isFull then 0.05 else PANEL_ALPHA
	shell.BorderSizePixel = 0
	shell.Active = true -- 패널 안 탭이 바깥(backdrop) 으로 새지 않게
	if isFull then
		shell.AnchorPoint = Vector2.new(0.5, 0.5)
		shell.Position = UDim2.fromScale(0.5, 0.5)
		shell.Size = UDim2.fromScale(1, 1)
	elseif isSheet then
		shell.AnchorPoint = Vector2.new(0.5, 1)
		shell.Position = UDim2.fromScale(0.5, 1)
		shell.Size = UDim2.fromOffset(size.X, size.Y)
	else
		shell.AnchorPoint = Vector2.new(0.5, 0.5)
		shell.Position = UDim2.fromScale(0.5, 0.5)
		shell.Size = UDim2.fromOffset(size.X, size.Y)
	end
	if not isFull then
		corner(shell, RADIUS)
	end

	local content: Frame = shell
	local scaleHost: Instance = shell
	if isFull then
		content = frame(shell, "Content", UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5))
		content.AnchorPoint = Vector2.new(0.5, 0.5)
		scaleHost = content
	end

	-- 반응형 배율 + 열기 팝을 하나의 UIScale 로. 전체 화면은 내용 영역만 배율을 먹는다
	local base = responsiveScale()
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = base * 0.9
	uiScale.Parent = scaleHost
	if isFull then
		-- 껍데기(전체 화면)는 투명도로만 등장한다
		shell.BackgroundTransparency = 1
		tween(shell, OPEN_TIME, { BackgroundTransparency = 0.05 })
	end
	tween(uiScale, OPEN_TIME, { Scale = base }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	if withClose then
		local x = button(
			content,
			"Close",
			"✕",
			UDim2.fromOffset(X_SIZE, X_SIZE),
			UDim2.new(1, -6, 0, 6),
			SURFACE,
			WHITE,
			28
		)
		x.AnchorPoint = Vector2.new(1, 0)
		x.ZIndex = 5
		x.Activated:Connect(function()
			PanelController.close()
		end)
	end

	shell.Parent = g
	b.BackgroundTransparency = 1
	tween(b, OPEN_TIME, { BackgroundTransparency = if isFull then 0.2 else 0.5 })
	g.Enabled = true

	currentFrame = shell
	currentScale = uiScale
	currentName = name
	return content
end

-- ── 도감 ──

local function buildCodex(content: Frame)
	local myGen = generation
	local profile = profileOrNil()
	local students: { [string]: number } = if profile then profile.students else {}
	local owned = StudentConfig.ownedCount(students)

	padding(content, 16, 10)
	local title = label(
		content,
		"Title",
		`도감 {owned}/{StudentConfig.COUNT}`,
		UDim2.new(1, -X_SIZE, 0, 36),
		nil,
		26,
		YELLOW,
		FONT_BOLD
	)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.new(1, 0, 1, -46)
	scroll.Position = UDim2.fromOffset(0, 46)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GREY
	scroll.Parent = content

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CODEX_CELL.X, CODEX_CELL.Y)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.FillDirectionMaxCells = CODEX_COLUMNS
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local views: { { id: string, card: Frame } } = {}

	local function cell(order: number, name: string): Frame
		local card = frame(scroll, name, UDim2.fromOffset(CODEX_CELL.X, CODEX_CELL.Y), nil, SURFACE)
		card.LayoutOrder = order
		corner(card, 12)
		return card
	end

	for i, id in StudentConfig.ORDER do
		local row = StudentConfig.BY_ID[id]
		local count = students[id] or 0
		local card = cell(i, id)
		if count > 0 then
			local style = StudentConfig.TIER_STYLE[row.tier]
			stroke(card, style.color, style.stroke)
			label(card, "Name", row.name, UDim2.new(1, -8, 0, 24), UDim2.new(0, 4, 1, -28), 18, WHITE, FONT_BOLD)
			if count > 1 then
				local badge = label(
					card,
					"Dupe",
					`×{count}`,
					UDim2.fromOffset(40, 20),
					UDim2.new(1, -44, 0, 4),
					16,
					YELLOW,
					FONT_BOLD
				)
				badge.TextXAlignment = Enum.TextXAlignment.Right
			end
			table.insert(views, { id = id, card = card })
		else
			stroke(card, GREY, 2)
			silhouette(card, UDim2.new(1, -24, 0, 80), UDim2.fromOffset(12, 8), DARK)
			label(card, "Unknown", "?", UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -32), 26, GREY, FONT_BOLD)
		end
	end

	-- 25번째 예약석
	local reserved = cell(#StudentConfig.ORDER + 1, "Reserved")
	stroke(reserved, GREY, 2)
	silhouette(reserved, UDim2.new(1, -24, 0, 80), UDim2.fromOffset(12, 8), DARK)
	label(reserved, "Soon", "곧 와요", UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -32), 18, GREY)

	-- 뷰포트는 프레임 뒤에 나눠 만든다. 닫히면(세대 바뀜) 남은 건 안 만든다
	task.spawn(function()
		for _, v in views do
			if myGen ~= generation then
				return
			end
			if v.card.Parent then
				studentView(v.card, v.id, UDim2.new(1, -8, 0, 84), UDim2.fromOffset(4, 4))
			end
			RunService.Heartbeat:Wait()
		end
	end)

	currentRefresh = function(p: Profile)
		title.Text = `도감 {StudentConfig.ownedCount(p.students)}/{StudentConfig.COUNT}`
	end
end

-- ── 미션 ──

local function buildMissions(content: Frame)
	padding(content, 16, 6)
	local title = label(content, "Title", "오늘 미션", UDim2.new(1, -X_SIZE, 0, 24), nil, 22, YELLOW, FONT_BOLD)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local rows = frame(content, "Rows", UDim2.new(1, 0, 1, -24), UDim2.fromOffset(0, 24))
	listLayout(rows, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local bars: { { fill: Frame, count: TextLabel, check: TextLabel, text: TextLabel } } = {}
	for i, mission in MissionConfig.LIST do
		local row = frame(rows, `Mission{i}`, UDim2.new(1, 0, 0, 88))
		row.LayoutOrder = i
		local inner = frame(row, "Inner", UDim2.new(1, 0, 1, -8), UDim2.fromOffset(0, 4), SURFACE)
		corner(inner, 12)
		label(inner, "Icon", MISSION_ICON[mission.id] or "•", UDim2.fromOffset(48, 48), UDim2.fromOffset(10, 16), 30)
		local text = label(
			inner,
			"Text",
			mission.text,
			UDim2.new(1, -200, 0, 30),
			UDim2.fromOffset(66, 10),
			22,
			WHITE,
			FONT_BOLD
		)
		text.TextXAlignment = Enum.TextXAlignment.Left
		local track = frame(inner, "Track", UDim2.new(1, -200, 0, 12), UDim2.fromOffset(66, 50), DARK)
		corner(track, 6)
		local fill = frame(track, "Fill", UDim2.fromScale(0, 1), nil, GREEN)
		corner(fill, 6)
		local count = label(inner, "Count", "", UDim2.fromOffset(70, 24), UDim2.new(1, -140, 0, 44), 18, GREY)
		count.TextXAlignment = Enum.TextXAlignment.Right
		label(
			inner,
			"Reward",
			`🎫+{MissionConfig.REWARD_TICKETS}`,
			UDim2.fromOffset(70, 24),
			UDim2.new(1, -140, 0, 12),
			18,
			YELLOW,
			FONT_BOLD
		)
		local check =
			label(inner, "Check", "✓", UDim2.fromOffset(48, 48), UDim2.new(1, -60, 0, 16), 32, GREEN, FONT_BOLD)
		check.Visible = false
		bars[i] = { fill = fill, count = count, check = check, text = text }
	end

	local function refresh(p: Profile)
		local doneCount = 0
		for i, mission in MissionConfig.LIST do
			local done = p.missions.done[i] == true
			local progress = if done then mission.target else MissionConfig.progressOf(p.missions, i)
			local ui = bars[i]
			ui.fill.Size = UDim2.fromScale(progress / mission.target, 1)
			ui.count.Text = `{progress}/{mission.target}`
			ui.check.Visible = done
			ui.text.TextColor3 = if done then GREEN else WHITE
			if done then
				doneCount += 1
			end
		end
		title.Text = if doneCount == #MissionConfig.LIST then MissionConfig.ALL_DONE_TEXT else "오늘 미션"
		title.TextColor3 = if doneCount == #MissionConfig.LIST then GREEN else YELLOW
	end
	local profile = profileOrNil()
	if profile then
		refresh(profile)
	end
	currentRefresh = refresh
end

-- ── 설정 ──

local function buildSettings(content: Frame)
	padding(content, 16, 8)
	local title = label(content, "Title", "설정", UDim2.new(1, -X_SIZE, 0, 28), nil, 22, YELLOW, FONT_BOLD)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local row = frame(content, "Row", UDim2.new(1, 0, 0, 72), UDim2.new(0, 0, 1, -72))
	listLayout(row, Enum.FillDirection.Horizontal, GAP)

	local pills: { [string]: { button: TextButton, pill: Frame, knob: Frame, state: TextLabel } } = {}
	for i, def in SETTING_ROWS do
		local b = button(row, def.key, "", UDim2.fromOffset(116, 72), nil, SURFACE, WHITE)
		b.LayoutOrder = i
		label(b, "Icon", def.icon, UDim2.fromOffset(28, 28), UDim2.fromOffset(8, 6), 22)
		local t = label(b, "Text", def.text, UDim2.new(1, -44, 0, 28), UDim2.fromOffset(40, 6), 16, WHITE, FONT_BOLD)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local pill = frame(b, "Pill", UDim2.fromOffset(44, 24), UDim2.new(0, 8, 1, -32), GREY)
		corner(pill, 12)
		local knob = frame(pill, "Knob", UDim2.fromOffset(20, 20), UDim2.fromOffset(2, 2), WHITE)
		corner(knob, 10)
		local state = label(b, "State", "", UDim2.new(1, -60, 0, 24), UDim2.new(0, 56, 1, -32), 16, GREY)
		state.TextXAlignment = Enum.TextXAlignment.Left
		pills[def.key] = { button = b, pill = pill, knob = knob, state = state }

		b.Activated:Connect(function()
			local p = profileOrNil()
			if not p then
				return
			end
			local value = not p.settings[def.key]
			Remotes.SetSetting:FireServer(def.key, value)
			-- 서버 확인 전에도 손맛은 바로 준다(ProfileSync 가 다시 맞춘다)
			local ui = pills[def.key]
			tween(ui.pill, 0.12, { BackgroundColor3 = if value then GREEN else GREY })
			tween(ui.knob, 0.12, { Position = if value then UDim2.fromOffset(22, 2) else UDim2.fromOffset(2, 2) })
			ui.state.Text = if value then "켜짐" else "꺼짐"
			SoundController.play("tick")
		end)
	end

	local function refresh(p: Profile)
		for _, def in SETTING_ROWS do
			local on = p.settings[def.key] == true
			local ui = pills[def.key]
			ui.pill.BackgroundColor3 = if on then GREEN else GREY
			ui.knob.Position = if on then UDim2.fromOffset(22, 2) else UDim2.fromOffset(2, 2)
			ui.state.Text = if on then "켜짐" else "꺼짐"
		end
	end
	local profile = profileOrNil()
	if profile then
		refresh(profile)
	end
	currentRefresh = refresh
end

-- ── 뽑기 ──

local function buildGacha(content: Frame)
	local myGen = generation
	padding(content, 14, 10)
	local title =
		label(content, "Title", "입학 원서 뽑기", UDim2.new(1, -X_SIZE, 0, 30), nil, 24, YELLOW, FONT_BOLD)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- 왼쪽: 확률판 10×10 + 확률 글자
	local left = frame(content, "Board", UDim2.fromOffset(130, 240), UDim2.fromOffset(0, 40))
	local dots = frame(left, "Dots", UDim2.fromOffset(120, 120), UDim2.fromOffset(5, 0))
	local dotGrid = Instance.new("UIGridLayout")
	dotGrid.CellSize = UDim2.fromOffset(10, 10)
	dotGrid.CellPadding = UDim2.fromOffset(2, 2)
	dotGrid.FillDirectionMaxCells = BOARD_DOTS
	dotGrid.SortOrder = Enum.SortOrder.LayoutOrder
	dotGrid.Parent = dots
	local order = 0
	for _, rate in GachaConfig.RATES do
		local n = math.floor(rate.p * BOARD_DOTS * BOARD_DOTS + 0.5)
		for _ = 1, n do
			order += 1
			local d = frame(dots, "Dot", UDim2.fromOffset(10, 10), nil, TIER_COLOR[rate.tier] or GREY)
			d.LayoutOrder = order
			corner(d, 999)
		end
	end
	local rates = frame(left, "Rates", UDim2.fromOffset(130, 66), UDim2.fromOffset(0, 130))
	listLayout(rates, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i, rate in GachaConfig.RATES do
		local l = label(
			rates,
			rate.tier,
			`{rate.tier} {math.floor(rate.p * 100 + 0.5)}%`,
			UDim2.new(1, 0, 0, 20),
			nil,
			16,
			TIER_COLOR[rate.tier] or GREY,
			FONT_BOLD
		)
		l.LayoutOrder = i
		l.TextXAlignment = Enum.TextXAlignment.Left
	end

	-- 가운데: 캡슐 + 「뽑기」
	local center = frame(content, "Center", UDim2.fromOffset(260, 240), UDim2.fromOffset(140, 40))
	local capsule = frame(center, "Capsule", UDim2.fromOffset(96, 120), UDim2.fromScale(0.5, 0))
	capsule.AnchorPoint = Vector2.new(0.5, 0)
	local capTop = frame(capsule, "Top", UDim2.fromScale(1, 0.5), nil, Color3.fromRGB(240, 244, 248))
	corner(capTop, 48)
	local capBottom = frame(capsule, "Bottom", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5), GREY)
	corner(capBottom, 48)
	frame(capsule, "Band", UDim2.new(1, 8, 0, 8), UDim2.new(0, -4, 0.5, -4), DARK)
	local ticketsText =
		label(center, "Tickets", "", UDim2.fromOffset(268, 24), UDim2.fromOffset(0, 128), 20, WHITE, FONT_BOLD)
	local rollButton =
		button(center, "Roll", "뽑기", UDim2.fromOffset(260, 72), UDim2.fromScale(0.5, 1), YELLOW, DARK, 30)
	rollButton.AnchorPoint = Vector2.new(0.5, 1)

	-- 오른쪽: 코스모 실루엣 + 천장 링
	local right = frame(content, "Pity", UDim2.fromOffset(130, 180), UDim2.fromOffset(410, 56))
	silhouette(right, UDim2.fromOffset(60, 70), UDim2.fromOffset(35, 0), DARK)
	local ring, setRing = makeRing(right, 72, 6, GOLD)
	ring.Position = UDim2.fromOffset(29, 76)
	local pityText = label(ring, "Left", "", UDim2.fromScale(1, 1), nil, 16, GOLD, FONT_BOLD)
	label(right, "Hint", "전설 확정", UDim2.fromOffset(130, 20), UDim2.fromOffset(0, 152), 14, GREY)

	local busy = false
	local overlay: Frame? = nil

	local function refreshStatic(p: Profile)
		ticketsText.Text = `원서 {p.tickets}장`
		local remain = GachaConfig.pityLeft(p.pity)
		pityText.Text = `{remain}장 더`
		setRing(1 - remain / GachaConfig.PITY)
		if not busy then
			if p.tickets >= 1 then
				setEnabled(rollButton, true, "뽑기", YELLOW)
			else
				setEnabled(rollButton, false, "원서가 없어요", YELLOW)
			end
		end
	end

	local function clearOverlay()
		if overlay then
			overlay:Destroy()
			overlay = nil
		end
		capsule.Rotation = 0
		capBottom.BackgroundColor3 = GREY
	end

	local roll: () -> ()

	--- 결과 카드. 0 → 가로 펼침 0.3s Back Out. 2.0s 부터 「확인」/「다시!」
	local function showResult(result: GachaResult, t0: number)
		local ov = frame(content, "Result", UDim2.new(1, 28, 1, 20), UDim2.fromOffset(-14, -10), PANEL_BG, 0.2)
		ov.ZIndex = 3
		overlay = ov
		local row = StudentConfig.BY_ID[result.studentId]
		local style = StudentConfig.TIER_STYLE[result.tier] or StudentConfig.TIER_STYLE[StudentConfig.TIER_ORDER[1]]
		local card = frame(ov, "Card", UDim2.fromOffset(0, 190), UDim2.new(0.5, 0, 0.5, -30), SURFACE)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.ZIndex = 4
		card.ClipsDescendants = true
		corner(card, 14)
		stroke(card, style.color, style.stroke)
		local inner = frame(card, "Inner", UDim2.fromOffset(160, 190))
		inner.AnchorPoint = Vector2.new(0.5, 0)
		inner.Position = UDim2.fromScale(0.5, 0)
		inner.ZIndex = 4
		label(inner, "Tier", result.tier, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 6), 18, style.color, FONT_BOLD)
		local view = studentView(inner, result.studentId, UDim2.fromOffset(110, 110), UDim2.fromOffset(25, 32))
		view.ZIndex = 4
		label(
			inner,
			"Name",
			if row then row.name else result.studentId,
			UDim2.new(1, 0, 0, 28),
			UDim2.fromOffset(0, 146),
			22,
			WHITE,
			FONT_BOLD
		)
		tween(card, FLIP_TIME, { Size = UDim2.fromOffset(160, 190) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		if result.isDupe then
			-- 「×n」 도장 0.2s 뒤 + 스티커판 「+n칸」 2s
			task.delay(STAMP_DELAY, function()
				if myGen ~= generation or not ov.Parent then
					return
				end
				local stamp = label(
					inner,
					"Stamp",
					`×{result.dupeCount}`,
					UDim2.fromOffset(56, 32),
					UDim2.fromOffset(98, 28),
					26,
					RED,
					FONT_BOLD
				)
				stamp.Rotation = -15
				stamp.ZIndex = 5
				stroke(stamp, RED, 2)
				local pop = Instance.new("UIScale")
				pop.Scale = 1.6
				pop.Parent = stamp
				tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				SoundController.play(STAMP_SOUND)
				local cells = GachaConfig.DUPE_CELLS[result.tier] or 0
				local plus = label(
					ov,
					"Plus",
					`스티커판 +{cells}칸`,
					UDim2.fromOffset(200, 26),
					UDim2.new(0.5, 0, 0.5, 74),
					18,
					GREEN,
					FONT_BOLD
				)
				plus.AnchorPoint = Vector2.new(0.5, 0)
				plus.ZIndex = 4
				task.delay(DUPE_SHOW, function()
					if plus.Parent then
						plus:Destroy()
					end
				end)
			end)
		end

		local remaining = RESULT_READY - (os.clock() - t0)
		task.wait(math.max(remaining, FLIP_TIME))
		if myGen ~= generation or not ov.Parent then
			return
		end
		busy = false
		local buttons = frame(ov, "Buttons", UDim2.fromOffset(260, 48), UDim2.new(0.5, 0, 0.5, 104))
		buttons.AnchorPoint = Vector2.new(0.5, 0)
		buttons.ZIndex = 4
		listLayout(buttons, Enum.FillDirection.Horizontal, GAP)
		local ok = button(buttons, "Ok", "확인", UDim2.fromOffset(120, 48), nil, SURFACE, WHITE, 22)
		ok.ZIndex = 4
		ok.LayoutOrder = 1
		local again = button(buttons, "Again", "다시!", UDim2.fromOffset(120, 48), nil, YELLOW, DARK, 22)
		again.ZIndex = 4
		again.LayoutOrder = 2
		if result.ticketsLeft < 1 then
			setEnabled(again, false, "원서 없음", YELLOW)
		end
		ok.Activated:Connect(function()
			clearOverlay()
			local p = profileOrNil()
			if p then
				refreshStatic(p)
			end
		end)
		again.Activated:Connect(function()
			clearOverlay()
			roll()
		end)
	end

	--- 색 공개 0.3s → 카드 뒤집기(등급 소리·화면 연출은 Feedback 에 위임)
	local function reveal(result: GachaResult, t0: number)
		tween(capsule, 0.1, { Rotation = 0 })
		tween(capBottom, REVEAL_TIME, { BackgroundColor3 = TIER_COLOR[result.tier] or GREY })
		task.wait(REVEAL_TIME)
		if myGen ~= generation then
			return
		end
		ticketsText.Text = `원서 {result.ticketsLeft}장`
		pityText.Text = `{result.pityLeft}장 더`
		setRing(1 - result.pityLeft / GachaConfig.PITY)
		SoundController.play(TIER_SOUND[result.tier] or "arrive")
		feedback().play("gacha", result)
		showResult(result, t0)
	end

	roll = function()
		if busy then
			return
		end
		local p = profileOrNil()
		if not p or p.tickets < 1 then
			-- 원서 없음. 서버에 보내지 않는다(§5.4)
			local ok = pcall(HudController.toast, "원서가 없어요")
			if not ok then
				warn("[Panel] HudController.toast 없음")
			end
			return
		end
		busy = true
		pendingGacha = nil
		setEnabled(rollButton, false, "두근두근…", YELLOW)
		Remotes.RollGacha:FireServer()
		SoundController.play("gachaSpin")
		task.spawn(function()
			local t0 = os.clock()
			local sign = 1
			while myGen == generation do
				local elapsed = os.clock() - t0
				if elapsed >= SHAKE_TIME and pendingGacha then
					break
				end
				if elapsed > ROLL_TIMEOUT then
					-- 서버가 답이 없다. 버튼을 되살리고 끝낸다
					tween(capsule, 0.1, { Rotation = 0 })
					busy = false
					local now = profileOrNil()
					if now then
						refreshStatic(now)
					end
					return
				end
				sign = -sign
				tween(capsule, SHAKE_STEP, { Rotation = SHAKE_DEG * sign })
				task.wait(SHAKE_STEP)
			end
			if myGen ~= generation then
				return
			end
			local result = pendingGacha
			pendingGacha = nil
			if result then
				reveal(result, t0)
			end
		end)
	end

	rollButton.Activated:Connect(roll)

	local profile = profileOrNil()
	if profile then
		refreshStatic(profile)
	else
		setEnabled(rollButton, false, "원서가 없어요", YELLOW)
	end
	currentRefresh = refreshStatic
	table.insert(currentCleanup, function()
		busy = false
	end)
end

-- ── 꾸미기(바닥 시트) ──

--- SkinRole 파트를 잠시 칠한다. 되돌릴 때는 우리가 칠한 색 그대로인 파트만 되돌린다(서버 적용과 안 싸운다)
local function previewSkin(model: Model, facilityId: string, index: number): () -> ()
	local skin = SkinConfig.get(facilityId, index)
	local saved: { { part: BasePart, color: Color3, material: Enum.Material, applied: Color3 } } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			local role = inst:GetAttribute(Keys.ATTR_SKIN_ROLE)
			if role == "primary" or role == "secondary" then
				local applied = if role == "primary" then skin.primary else skin.secondary
				table.insert(saved, { part = inst, color = inst.Color, material = inst.Material, applied = applied })
				inst.Color = applied
				inst.Material = skin.material
			end
		end
	end
	return function()
		for _, s in saved do
			if s.part.Parent and s.part.Color == s.applied then
				s.part.Color = s.color
				s.part.Material = s.material
			end
		end
	end
end

-- TODO(통합): 바닥 시트가 조이스틱 구역(§8.1 좌하 22%×30%)과 겹친다. 열려 있는 동안 이동을 막을지 결정
local function buildSkin(content: Frame, payload: any)
	local facilityId: string? = if type(payload) == "table" and type(payload.facilityId) == "string"
		then payload.facilityId
		else nil
	local facility = if facilityId then FacilityConfig.BY_ID[facilityId] else nil
	if not facilityId or not facility then
		warn("[Panel] skin 패널에 facilityId 가 없음")
		label(
			content,
			"Title",
			"시설을 골라요",
			UDim2.new(1, -X_SIZE, 0, 32),
			UDim2.fromOffset(16, 12),
			22,
			GREY,
			FONT_BOLD
		)
		return
	end
	local id: string = facilityId

	padding(content, 16, 10)
	local title =
		label(content, "Title", `{facility.name} 꾸미기`, UDim2.new(1, -X_SIZE, 0, 28), nil, 22, YELLOW, FONT_BOLD)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local row = frame(content, "Swatches", UDim2.fromOffset(4 * 72 + 3 * GAP, 100), UDim2.fromOffset(0, 40))
	listLayout(row, Enum.FillDirection.Horizontal, GAP, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local apply = button(content, "Apply", "적용", UDim2.fromOffset(200, 56), UDim2.fromScale(1, 1), YELLOW, DARK, 26)
	apply.AnchorPoint = Vector2.new(1, 1)
	local status = label(content, "Status", "", UDim2.fromOffset(220, 22), UDim2.new(1, 0, 1, -62), 16, GREY)
	status.AnchorPoint = Vector2.new(1, 1)
	status.TextXAlignment = Enum.TextXAlignment.Right

	local selected = 0
	local revert: (() -> ())? = nil
	local previewToken = 0
	local swatches: { { card: TextButton, ring: UIStroke, price: TextLabel } } = {}

	local function stopPreview()
		previewToken += 1
		if revert then
			revert()
			revert = nil
		end
	end

	local function refresh(p: Profile)
		local graduations = p.graduations
		local applied = p.skinsApplied[id] or 1
		for i, sw in swatches do
			local owned = i == 1 or p.skinsOwned[SkinConfig.key(id, i)] == true
			local locked = i == SkinConfig.GRADUATION_INDEX and graduations < 1
			if applied == i then
				sw.price.Text = "적용 중"
				sw.price.TextColor3 = GREEN
			elseif owned then
				sw.price.Text = "있어요"
				sw.price.TextColor3 = WHITE
			elseif locked then
				sw.price.Text = "🔒 졸업 후"
				sw.price.TextColor3 = GREY
			else
				sw.price.Text = Format.coins(SkinConfig.priceOf(id, i, graduations))
				sw.price.TextColor3 = YELLOW
			end
			sw.ring.Color = if selected == i then YELLOW else if applied == i then GREEN else SURFACE
			sw.ring.Thickness = if selected == i then 4 else 2
		end
		if selected == 0 then
			setEnabled(apply, false, "골라요", YELLOW)
			status.Text = ""
			return
		end
		local owned = selected == 1 or p.skinsOwned[SkinConfig.key(id, selected)] == true
		local locked = selected == SkinConfig.GRADUATION_INDEX and graduations < 1
		if applied == selected then
			setEnabled(apply, false, "적용 중", YELLOW)
			status.Text = ""
		elseif locked then
			setEnabled(apply, false, "졸업 1회 필요", YELLOW)
			status.Text = ""
		elseif owned then
			setEnabled(apply, true, "적용", GREEN)
			status.Text = ""
		else
			local price = SkinConfig.priceOf(id, selected, graduations)
			setEnabled(
				apply,
				p.coins >= price,
				if p.coins >= price then `사기 {Format.coins(price)}` else "용돈 부족",
				YELLOW
			)
			status.Text = `용돈 {Format.coins(p.coins)}`
		end
	end

	for i = 1, SkinConfig.COUNT do
		local skin = SkinConfig.get(id, i)
		local card = button(row, `Skin{i}`, "", UDim2.fromOffset(72, 100), nil, SURFACE, WHITE)
		card.LayoutOrder = i
		local chip = frame(card, "Chip", UDim2.fromOffset(60, 44), UDim2.fromOffset(6, 6), skin.primary)
		corner(chip, 10)
		local sub = frame(chip, "Sub", UDim2.fromOffset(20, 20), UDim2.new(1, -24, 1, -24), skin.secondary)
		corner(sub, 6)
		label(card, "Name", skin.name, UDim2.new(1, -4, 0, 20), UDim2.fromOffset(2, 52), 14, WHITE, FONT_BOLD)
		local price = label(card, "Price", "", UDim2.new(1, -4, 0, 20), UDim2.fromOffset(2, 74), 14, YELLOW)
		local ring = stroke(card, SURFACE, 2)
		swatches[i] = { card = card, ring = ring, price = price }

		card.Activated:Connect(function()
			selected = i
			stopPreview()
			local model = myFacilityModel(id)
			if model then
				revert = previewSkin(model, id, i)
				local token = previewToken
				task.delay(PREVIEW_TIME, function()
					if token == previewToken and revert then
						revert()
						revert = nil
					end
				end)
			end
			SoundController.play("tick")
			local p = profileOrNil()
			if p then
				refresh(p)
			end
		end)
	end

	apply.Activated:Connect(function()
		if selected == 0 then
			return
		end
		stopPreview()
		Remotes.SetSkin:FireServer(id, selected)
		SoundController.play("skin")
	end)

	local profile = profileOrNil()
	if profile then
		selected = profile.skinsApplied[id] or 1
		refresh(profile)
	else
		setEnabled(apply, false, "골라요", YELLOW)
	end
	currentRefresh = refresh
	table.insert(currentCleanup, stopPreview)
end

-- ── 졸업 확인(전체 화면) ──

local function buildGraduate(content: Frame)
	local profile = profileOrNil()
	local graduations = if profile then profile.graduations else 0
	local nextRound = graduations + 1

	label(content, "Cap", "🎓", UDim2.fromOffset(128, 110), UDim2.fromScale(0.5, 0), 96).AnchorPoint =
		Vector2.new(0.5, 0)
	label(
		content,
		"Title",
		`제 {nextRound}회 졸업식`,
		UDim2.new(1, 0, 0, 40),
		UDim2.fromOffset(0, 138),
		32,
		YELLOW,
		FONT_BOLD
	)

	local function column(name: string, heading: string, x: number, color: Color3, lines: { string })
		local col = frame(content, name, UDim2.fromOffset(300, 112), UDim2.fromOffset(x, 154), SURFACE)
		corner(col, 14)
		padding(col, 12, 8)
		listLayout(col, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
		local h = label(col, "Heading", heading, UDim2.new(1, 0, 0, 26), nil, 20, color, FONT_BOLD)
		h.LayoutOrder = 0
		h.TextXAlignment = Enum.TextXAlignment.Left
		for i, text in lines do
			local l = label(col, `Line{i}`, text, UDim2.new(1, 0, 0, 22), nil, 16, WHITE)
			l.LayoutOrder = i
			l.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
	local nextMult = Format.multiplier(1 + EconomyConfig.GRAD_STEP * nextRound)
	column("Keep", "남아요", 96, GREEN, { "도감 · 스킨 · 원서", "스티커판", `졸업 배율 {nextMult}` })
	column("Reset", "새로 지어요", 416, RED, { "시설 (전부 새로)", "용돈 0" })

	local no =
		button(content, "No", "아니요", UDim2.fromOffset(160, 56), UDim2.new(0.5, -90, 1, -8), SURFACE, WHITE, 24)
	no.AnchorPoint = Vector2.new(1, 1)
	no.Activated:Connect(function()
		PanelController.close()
	end)

	local go = button(
		content,
		"Go",
		"꾹 눌러 시작",
		UDim2.fromOffset(260, 72),
		UDim2.new(0.5, -70, 1, -8),
		YELLOW,
		DARK,
		26
	)
	go.AnchorPoint = Vector2.new(0, 1)
	local goPad = Instance.new("UIPadding")
	goPad.PaddingRight = UDim.new(0, 64)
	goPad.Parent = go
	local ring, setRing = makeRing(go, 56, 5, DARK)
	ring.AnchorPoint = Vector2.new(1, 0.5)
	ring.Position = UDim2.new(1, -8, 0.5, 0)
	ring.ZIndex = 2

	local holding = false
	local heartbeat: RBXScriptConnection? = nil
	local fired = false

	local function stopHold()
		holding = false
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		if not fired then
			setRing(0)
			go.Text = "꾹 눌러 시작"
		end
	end

	local function startHold()
		if holding or fired then
			return
		end
		holding = true
		go.Text = "졸업식 시작"
		local t0 = os.clock()
		heartbeat = RunService.Heartbeat:Connect(function()
			local p = (os.clock() - t0) / HOLD_TIME
			setRing(p)
			if p >= 1 then
				fired = true
				stopHold()
				Remotes.Graduate:FireServer()
				SoundController.play("bell")
				PanelController.close()
			end
		end)
	end

	go.MouseButton1Down:Connect(startHold)
	go.MouseButton1Up:Connect(stopHold)
	go.MouseLeave:Connect(stopHold)
	table.insert(currentCleanup, stopHold)
end

-- ── 공개 API ──

local BUILDERS: { [string]: (Frame, any) -> () } = {
	codex = function(c, _)
		buildCodex(c)
	end,
	gacha = function(c, _)
		buildGacha(c)
	end,
	missions = function(c, _)
		buildMissions(c)
	end,
	skin = buildSkin,
	settings = function(c, _)
		buildSettings(c)
	end,
	graduate = function(c, _)
		buildGraduate(c)
	end,
}

--- 패널을 연다. 이미 다른 패널이 열려 있으면 바로 바꾼다
function PanelController.open(name: PanelName, payload: any?)
	if not BUILDERS[name] then
		warn(`[Panel] 모르는 패널: {name}`)
		return
	end
	if currentName then
		destroyCurrent()
	end
	local content = openShell(name, true)
	local ok, err = pcall(BUILDERS[name] :: any, content, payload)
	if not ok then
		warn(`[Panel] {name} 그리기 실패: {err}`)
		destroyCurrent()
		if gui then
			gui.Enabled = false
		end
		return
	end
	SoundController.play("tick")
end

--- 열린 패널을 닫는다. 0.12s Quad In 으로 줄이고 지운다
function PanelController.close()
	local shell = currentFrame
	local scale = currentScale
	if not shell or not scale then
		return
	end
	runCleanup()
	currentRefresh = nil
	currentFrame = nil
	currentScale = nil
	currentName = nil
	generation += 1

	local b = backdrop
	if b then
		tween(b, CLOSE_TIME, { BackgroundTransparency = 1 })
	end
	local shrink =
		tween(scale, CLOSE_TIME, { Scale = scale.Scale * 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	shrink.Completed:Once(function()
		shell:Destroy()
		if gui and currentFrame == nil then
			gui.Enabled = false
		end
	end)
end

function PanelController.isOpen(): boolean
	return currentName ~= nil
end

function PanelController.current(): string?
	return currentName
end

--- 서버 GachaResult. 뽑기 패널이 열려 있으면 흔들기 코루틴이 집어 간다. 아니면 버린다(HUD 가 프로필로 갱신)
function PanelController.onGachaResult(payload: GachaResult)
	if type(payload) ~= "table" or type(payload.seq) ~= "number" then
		return
	end
	if payload.seq <= lastSeq then
		return
	end
	lastSeq = payload.seq
	if currentName == "gacha" then
		pendingGacha = payload
	end
end

function PanelController.Start()
	Remotes.wait()
	ensureGui()

	-- 프로필 변화 → 열린 패널만 다시 그린다
	HudController.onProfile(function(p: Profile)
		local fn = currentRefresh
		if fn then
			local ok, err = pcall(fn :: any, p)
			if not ok then
				warn(`[Panel] 갱신 실패: {err}`)
			end
		end
	end)

	-- 안드로이드 뒤로가기(ButtonB) 로 닫기 -- TODO(통합): 실기기에서 뒤로가기 KeyCode 확인
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if input.KeyCode == Enum.KeyCode.ButtonB and currentName then
			PanelController.close()
		end
	end)

	-- 화면 크기 바뀌면 배율 갱신
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if currentScale then
				currentScale.Scale = responsiveScale()
			end
		end)
	end
end

return PanelController
