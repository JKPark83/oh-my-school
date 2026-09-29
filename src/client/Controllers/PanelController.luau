--!strict
--[[
	패널 컨트롤러. 기획서 §8.3 의 패널 4개를 코드로 그린다.
	  도감(714×330) · 미션(568×300) · 설정(406×150) · 졸업 확인(전체 화면)

	  ★ 한 번에 하나만 연다. 열기 0.2s Back Out(0.9→1.0), 닫기 0.12s Quad In.
	  ★ ScreenGui "Panels" DisplayOrder 5, IgnoreGuiInset. UIScale = clamp(세로/375, 0.9, 1.6).
	  ★ X 버튼 56×56, 바깥 탭, 안드로이드 뒤로가기(ButtonB) 로 닫는다.
	  ★ 프로필은 HudController.profile() / onProfile() 로만 읽는다(구현계획 §3.4).
	  ★ 서버 호출은 Graduate / SetSetting 두 개.
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
local EconomyConfig = require(Shared.Config.EconomyConfig)
local StudentConfig = require(Shared.Config.StudentConfig)
local MissionConfig = require(Shared.Config.MissionConfig)

-- 형제 컨트롤러. 계약(구현계획 §3.4)의 함수만 쓴다. 아직 옛 버전이 남아 있을 수 있어 타입은 묻지 않는다
local Controllers = script.Parent
local HudController = require(Controllers.HudController) :: any
local SoundController = require(Controllers.SoundController) :: any

type Profile = Types.Profile

local PanelController = {}

export type PanelName = "codex" | "missions" | "settings" | "graduate"

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
	missions = Vector2.new(568, 300),
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

local FONT_BOLD = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium

-- 도감
local CODEX_CELL = Vector2.new(96, 120)
local CODEX_COLUMNS = 6

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

-- ── 작은 유틸 ──

local function responsiveScale(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(SIZES.graduate.X, DESIGN_HEIGHT)
	local byHeight = math.clamp(size.Y / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
	-- 세로 기준(§8.1)이되, 제일 넓은 패널(812)이 가로를 넘지 않게 막는다
	return math.min(byHeight, size.X / SIZES.graduate.X)
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
	local profile = profileOrNil()
	local students: { [string]: number } = if profile then profile.students else {}
	local owned = StudentConfig.ownedCount(students)

	padding(content, 16, 10)
	local title = label(
		content,
		"Title",
		`도감 {owned}/{StudentConfig.COUNT}`,
		UDim2.fromOffset(180, 36),
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

	local tabGen = 0 -- 탭을 바꿀 때마다 +1. 옛 탭의 뷰포트 코루틴이 멈춘다

	local function cell(order: number, name: string): Frame
		local card = frame(scroll, name, UDim2.fromOffset(CODEX_CELL.X, CODEX_CELL.Y), nil, SURFACE)
		card.LayoutOrder = order
		corner(card, 12)
		return card
	end

	--- 미보유 칸: 회색 테두리 + 실루엣 + 아래 글자
	local function lockedCell(order: number, name: string, text: string, maxText: number)
		local card = cell(order, name)
		stroke(card, GREY, 2)
		silhouette(card, UDim2.new(1, -24, 0, 80), UDim2.fromOffset(12, 8), DARK)
		label(card, "Unknown", text, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -32), maxText, GREY, FONT_BOLD)
	end

	--- tab = "school"(학교 친구: 시설·졸업 해금) | "friend"(함께 오는 친구: 꾸미기로 만난다)
	local function fill(tab: string)
		tabGen += 1
		local myTab = tabGen
		local myGen = generation
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local views: { { id: string, card: Frame } } = {}
		local order = 0
		for _, id in StudentConfig.ORDER do
			local row = StudentConfig.BY_ID[id]
			local isFriend = row.unlock.kind == "friend"
			if isFriend == (tab == "friend") then
				order += 1
				local count = students[id] or 0
				if count > 0 then
					local card = cell(order, id)
					local style = StudentConfig.TIER_STYLE[row.tier]
					stroke(card, style.color, style.stroke)
					label(
						card,
						"Name",
						row.name,
						UDim2.new(1, -8, 0, 24),
						UDim2.new(0, 4, 1, -28),
						18,
						WHITE,
						FONT_BOLD
					)
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
				elseif isFriend then
					lockedCell(order, id, "꾸미기로 만나요", 14)
				else
					lockedCell(order, id, "?", 26)
				end
			end
		end

		if tab == "school" then
			-- 예약석
			local reserved = cell(order + 1, "Reserved")
			stroke(reserved, GREY, 2)
			silhouette(reserved, UDim2.new(1, -24, 0, 80), UDim2.fromOffset(12, 8), DARK)
			label(reserved, "Soon", "곧 와요", UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -32), 18, GREY)
		end

		-- 뷰포트는 프레임 뒤에 나눠 만든다. 닫히거나 탭이 바뀌면(세대 바뀜) 남은 건 안 만든다
		task.spawn(function()
			for _, v in views do
				if myGen ~= generation or myTab ~= tabGen then
					return
				end
				if v.card.Parent then
					studentView(v.card, v.id, UDim2.new(1, -8, 0, 84), UDim2.fromOffset(4, 4))
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	-- 탭 2개. 고른 탭은 노랑, 나머지는 어두운 면
	local tabs: { { key: string, button: TextButton } } = {}
	local function selectTab(key: string)
		for _, t in tabs do
			local on = t.key == key
			t.button.BackgroundColor3 = if on then YELLOW else SURFACE
			t.button.TextColor3 = if on then DARK else WHITE
		end
		fill(key)
	end
	for i, def in { { key = "school", text = "학교 친구" }, { key = "friend", text = "함께 오는 친구" } } do
		local b = button(
			content,
			`Tab_{def.key}`,
			def.text,
			UDim2.fromOffset(170, 36),
			UDim2.fromOffset(190 + (i - 1) * 180, 0)
		)
		b.Activated:Connect(function()
			selectTab(def.key)
			SoundController.play("tick")
		end)
		table.insert(tabs, { key = def.key, button = b })
	end
	selectTab("school")

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
			`🎁+{MissionConfig.REWARD_CELLS}칸`,
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
	column("Keep", "남아요", 96, GREEN, { "도감 · 꾸미기", "스티커판", `졸업 배율 {nextMult}` })
	column("Reset", "새로 지어요", 416, YELLOW, { "시설 (전부 새로)", "용돈 0" })

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
	missions = function(c, _)
		buildMissions(c)
	end,
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
