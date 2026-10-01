--!strict
--[[
	패널 컨트롤러. 기획서 §8.3 의 패널 4개와 꾸미기 시트를 코드로 그린다.
	  도감(714×330) · 미션(568×300) · 설정(532×150) · 꾸미기(780×340)

	  ★ 한 번에 하나만 연다. 열기 0.2s Back Out(0.9→1.0), 닫기 0.12s Quad In.
	  ★ ScreenGui "Panels" DisplayOrder 5, IgnoreGuiInset. UIScale = clamp(세로/375, 0.9, 1.6).
	  ★ X 버튼 56×56, 바깥 탭, 안드로이드 뒤로가기(ButtonB) 로 닫는다.
	  ★ 프로필은 HudController.profile() / onProfile() 로만 읽는다(구현계획 §3.4).
	  ★ 서버 호출은 SetSetting / BuyDecor / ReturnDecor. 사고 돌려주는 판정은 서버가 한다.
	  ★ 꾸미기 시트: 위 줄 보관함(탭 = 놓기), 아래 줄 가게(탭 = 큰 확인 카드). 돈이 모자라면 ✓ 가 흐린 회색이다(글자 없음).
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
local FacilityConfig = require(Shared.Config.FacilityConfig)
local StudentConfig = require(Shared.Config.StudentConfig)
local MissionConfig = require(Shared.Config.MissionConfig)
local DecorConfig = require(Shared.Config.DecorConfig)
local DecorBuilder = require(Shared.DecorBuilder)
local DecorCodec = require(Shared.DecorCodec)
local Keys = require(Shared.Config.Keys)

-- 형제 컨트롤러. 계약(구현계획 §3.4)의 함수만 쓴다. 아직 옛 버전이 남아 있을 수 있어 타입은 묻지 않는다
local Controllers = script.Parent
local HudController = require(Controllers.HudController) :: any
local SoundController = require(Controllers.SoundController) :: any
local DecorController = require(Controllers.DecorController) :: any

type Profile = Types.Profile

local PanelController = {}

export type PanelName = "codex" | "missions" | "settings" | "decor"

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
local DESIGN_WIDTH = 812 -- 가로 기준 화면 폭. 패널이 이보다 넓은 화면을 가정하지 않는다

local SIZES: { [string]: Vector2 } = {
	codex = Vector2.new(714, 330),
	missions = Vector2.new(568, 300),
	settings = Vector2.new(532, 150), -- 토글 4개: 16 + 116×4 + 12×3 + 16
	decor = Vector2.new(780, 340), -- 812×375 안에 들어간다
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

-- 꾸미기 시트(글보다 그림)
local DECOR_GLYPH_TITLE = "🌷"
local DECOR_GLYPH_INVENTORY = "🎒"
local DECOR_GLYPH_SHOP = "🛒"
local DECOR_GLYPH_RETURN = "↩"
local DECOR_INV_CARD = Vector2.new(96, 120)
local DECOR_SHOP_CARD = Vector2.new(104, 126)
local DECOR_INV_PICTURE = 72
local DECOR_SHOP_PICTURE = 76
local DECOR_SHOP_RING = 36
local DECOR_CONFIRM_PICTURE = 200
local DECOR_CONFIRM_RING = 72
local DECOR_CONFIRM_OK = 88
local DECOR_VIEW_DIST = 0.9 -- 모델 대각선 × 이 값 = 카메라 거리
local DECOR_FRIEND_SMALL = 0.45 -- 친구 카드의 작은 물건 크기(그림 한 변 비율)
local DECOR_PUNCH = 1.15

-- 설정
local SETTING_ROWS: { { key: Types.SettingKey, icon: string, text: string } } = {
	{ key = "shake", icon = "〰", text = "화면 흔들림" },
	{ key = "sfx", icon = "🔊", text = "효과음" },
	{ key = "music", icon = "🎵", text = "배경음" },
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
	local size = if camera then camera.ViewportSize else Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
	local byHeight = math.clamp(size.Y / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
	-- 세로 기준(§8.1)이되, 기준 폭(812)이 가로를 넘지 않게 막는다
	return math.min(byHeight, size.X / DESIGN_WIDTH)
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

--- 내 부지에 놓인 꾸미기. ProfileSync 는 decorPlaced 를 빼고 보내므로 PlotState Decor 어트리뷰트를 읽는다
local function placedNow(): { Types.DecorPlacement }
	local plotId = HudController.myPlotId()
	local states = ReplicatedStorage:FindFirstChild(Keys.PLOT_STATE_FOLDER)
	local state = if plotId and states then states:FindFirstChild(Keys.plotName(plotId)) else nil
	local raw = if state then state:GetAttribute(Keys.ATTR_DECOR) else nil
	return if type(raw) == "string" and raw ~= "" then DecorCodec.decode(raw) else {}
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

--- 패널 틀을 만들어 내용 영역을 돌려준다
local function openShell(name: PanelName, withClose: boolean): Frame
	local g, b = ensureGui()
	generation += 1
	local size = SIZES[name]

	local shell = Instance.new("Frame")
	shell.Name = name
	shell.BackgroundColor3 = PANEL_BG
	shell.BackgroundTransparency = PANEL_ALPHA
	shell.BorderSizePixel = 0
	shell.Active = true -- 패널 안 탭이 바깥(backdrop) 으로 새지 않게
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromOffset(size.X, size.Y)
	corner(shell, RADIUS)

	-- 반응형 배율 + 열기 팝을 하나의 UIScale 로
	local base = responsiveScale()
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = base * 0.9
	uiScale.Parent = shell
	tween(uiScale, OPEN_TIME, { Scale = base }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	if withClose then
		local x =
			button(shell, "Close", "X", UDim2.fromOffset(X_SIZE, X_SIZE), UDim2.new(1, -6, 0, 6), SURFACE, WHITE, 28)
		x.AnchorPoint = Vector2.new(1, 0)
		x.ZIndex = 5
		x.Activated:Connect(function()
			PanelController.close()
		end)
	end

	shell.Parent = g
	b.BackgroundTransparency = 1
	tween(b, OPEN_TIME, { BackgroundTransparency = 0.5 })
	g.Enabled = true

	currentFrame = shell
	currentScale = uiScale
	currentName = name
	return shell
end

-- ── 도감 ──

--- 받침이 있으면 「을」, 없으면 「를」. 한글이 아니면 「을」
local function objectParticle(word: string): string
	local last = utf8.codepoint(word, utf8.offset(word, -1) :: number)
	if last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 == 0 then
		return "를"
	end
	return "을"
end

--- 미보유 학생 칸 아래 힌트. 방 이름은 P3 에서 RoomConfig 로 바꾼다
local function unlockHint(unlock: StudentConfig.Unlock): string
	if unlock.kind == "facility" then
		local facility = FacilityConfig.BY_ID[unlock.value :: string]
		if facility then
			return `{facility.name}{objectParticle(facility.name)} 지으면`
		end
	elseif unlock.kind == "room" then
		return "방을 지으면"
	elseif unlock.kind == "friend" then
		return "친구 아이템을 사면"
	end
	return "?"
end

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

	--- tab = "school"(학교 친구: 시설·방 해금) | "friend"(함께 오는 친구: 꾸미기로 만난다)
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
				else
					lockedCell(order, id, unlockHint(row.unlock), 14)
				end
			end
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
			local tabText = t.button:FindFirstChild("Text")
			if tabText and tabText:IsA("TextLabel") then
				tabText.TextColor3 = if on then DARK else WHITE
			end
		end
		fill(key)
	end
	-- 탭은 그림(🙂 / 🌷) + 작은 글자
	for i, def in
		{
			{ key = "school", glyph = "🙂", text = "학교 친구" },
			{ key = "friend", glyph = "🌷", text = "함께 오는 친구" },
		}
	do
		local b =
			button(content, `Tab_{def.key}`, "", UDim2.fromOffset(170, 36), UDim2.fromOffset(190 + (i - 1) * 180, 0))
		label(b, "Glyph", def.glyph, UDim2.fromOffset(28, 28), UDim2.fromOffset(8, 4), 24)
		local tabText =
			label(b, "Text", def.text, UDim2.new(1, -44, 0, 20), UDim2.fromOffset(40, 8), 14, DARK, FONT_BOLD)
		tabText.TextXAlignment = Enum.TextXAlignment.Left
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

-- ── 꾸미기 시트 ──

--- 꾸미기 아이템 뷰포트. 모델을 비스듬히 위에서 본다
local function decorView(parent: Instance, item: DecorConfig.Item, size: UDim2, position: UDim2?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.Size = size
	vp.Position = position or UDim2.fromScale(0, 0)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-1, -1, -1)
	local model = DecorBuilder.build(item, CFrame.identity)
	local camera = Instance.new("Camera")
	local center, extent = model:GetBoundingBox()
	local dist = extent.Magnitude * DECOR_VIEW_DIST + 1
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(dist * 0.6, dist * 0.55, -dist * 0.6), center.Position)
	camera.Parent = vp
	vp.CurrentCamera = camera
	model.Parent = vp
	vp.Parent = parent
	return vp
end

--- 카드 그림. 함께 오는 친구 아이템은 학생 얼굴 + 오른쪽 아래 작은 물건
local function decorPicture(parent: Instance, item: DecorConfig.Item, px: number, position: UDim2?)
	local student = item.student
	if item.kind == "friend" and student then
		local holder = frame(parent, "Picture", UDim2.fromOffset(px, px), position)
		studentView(holder, student, UDim2.fromScale(1, 1))
		local small = math.floor(px * DECOR_FRIEND_SMALL)
		decorView(holder, item, UDim2.fromOffset(small, small), UDim2.new(1, -small, 1, -small))
		return
	end
	decorView(parent, item, UDim2.fromOffset(px, px), position)
end

--- 펀치 스케일(카드 하나). 없으면 만든다
local function punchCard(card: GuiObject)
	local s = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = card
	s.Scale = DECOR_PUNCH
	tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

--- 가로 스크롤 줄 하나
local function decorRow(parent: Instance, name: string, y: number, height: number): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.Size = UDim2.new(1, 0, 0, height)
	scroll.Position = UDim2.fromOffset(0, y)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = GREY
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.Parent = parent
	listLayout(scroll, Enum.FillDirection.Horizontal, GAP, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	return scroll
end

local function clearRow(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local decorPendingPunch: string? = nil

local function buildDecor(content: Frame)
	local myGen = generation
	padding(content, 16, 10)

	-- 제목 줄: 글자 대신 그림(🌷 = 보관함, 🛒 = 가게)
	label(content, "Title", DECOR_GLYPH_TITLE, UDim2.fromOffset(40, 36), nil, 30, WHITE, FONT_BOLD)

	label(content, "InvIcon", DECOR_GLYPH_INVENTORY, UDim2.fromOffset(28, 28), UDim2.fromOffset(0, 40), 22)
	local inventory = decorRow(content, "Inventory", 40, DECOR_INV_CARD.Y + 6)
	inventory.Size = UDim2.new(1, -36, 0, DECOR_INV_CARD.Y + 6)
	inventory.Position = UDim2.fromOffset(36, 40)

	local shopY = 40 + DECOR_INV_CARD.Y + 12
	label(content, "ShopIcon", DECOR_GLYPH_SHOP, UDim2.fromOffset(28, 28), UDim2.fromOffset(0, shopY), 22)
	local shop = decorRow(content, "Shop", shopY, DECOR_SHOP_CARD.Y + 6)
	shop.Size = UDim2.new(1, -36, 0, DECOR_SHOP_CARD.Y + 6)
	shop.Position = UDim2.fromOffset(36, shopY)

	-- 그림은 프레임 뒤에 나눠 그린다(도감과 같은 방식). 줄을 새로 만들면 rowGen 이 바뀌어 옛 작업이 멈춘다
	local rowGen = 0
	local function drawLater(jobs: { () -> () })
		local mine = rowGen
		task.spawn(function()
			for _, job in jobs do
				if myGen ~= generation or mine ~= rowGen then
					return
				end
				job()
				RunService.Heartbeat:Wait()
			end
		end)
	end

	-- 줄마다 카드 참조. 코인만 바뀌면 링·어둡게만 다시 칠한다
	local invKey: string? = nil -- nil 이면 아직 안 그렸다
	local invCards: { [string]: { card: TextButton, count: TextLabel } } = {}
	local shopCards: { [string]: { card: TextButton, set: (number) -> (), dim: Frame } } = {}

	-- 큰 확인 카드(가게 카드 탭 = 사기, 보관함 ↩ = 돌려주기). 바깥 탭 = 닫기
	local confirm: TextButton? = nil
	local confirmItem: string? = nil
	local confirmSet: ((number) -> ())? = nil
	local confirmOk: TextButton? = nil

	local function closeConfirm()
		if confirm then
			confirm:Destroy()
		end
		confirm = nil
		confirmItem = nil
		confirmSet = nil
		confirmOk = nil
	end

	local function paintConfirm(p: Profile)
		local id = confirmItem
		local set = confirmSet
		local ok = confirmOk
		if not (id and set and ok) then
			return
		end
		local price = DecorConfig.priceOf(id)
		local full = DecorConfig.heldCount(p.decorOwned, placedNow(), id) >= DecorConfig.MAX_OWNED
		local can = p.coins >= price and not full
		set(if price > 0 then p.coins / price else 1)
		-- 아직이면 흐린 회색 ✓(글자 없이 「아직」). 빨강·흔들기 없음
		ok.BackgroundColor3 = if can then GREEN else GREY
		ok.BackgroundTransparency = if can then 0 else 0.6
		ok.TextTransparency = if can then 0 else 0.5
		ok.AutoButtonColor = can
	end

	-- returning = 돌려주기 확인(그림 + ↩ + ✓). 돌려받는 값은 서버만 알아 숫자는 없다
	local function openConfirm(id: string, returning: boolean)
		local p = profileOrNil()
		local item = DecorConfig.byId(id)
		if not (p and item) then
			return
		end
		closeConfirm()
		local cover = Instance.new("TextButton")
		cover.Name = "Confirm"
		cover.Size = UDim2.fromScale(1, 1)
		cover.BackgroundColor3 = PANEL_BG
		cover.BackgroundTransparency = 0.05
		cover.BorderSizePixel = 0
		cover.AutoButtonColor = false
		cover.Text = ""
		cover.ZIndex = 10
		cover.Parent = content
		corner(cover, 12)
		cover.Activated:Connect(closeConfirm)

		local box = frame(cover, "Box", UDim2.fromOffset(460, 260), UDim2.fromScale(0.5, 0.5), SURFACE)
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Active = true -- 상자 안 탭은 닫기로 새지 않는다
		box.ZIndex = 11
		corner(box, 16)

		decorPicture(box, item, DECOR_CONFIRM_PICTURE, UDim2.fromOffset(20, 20))
		local set: ((number) -> ())? = nil
		if returning then
			label(
				box,
				"Return",
				DECOR_GLYPH_RETURN,
				UDim2.fromOffset(DECOR_CONFIRM_RING, DECOR_CONFIRM_RING),
				UDim2.fromOffset(250, 24),
				56,
				WHITE,
				FONT_BOLD
			)
		else
			local ring, setRing = makeRing(box, DECOR_CONFIRM_RING, 6, GREEN)
			ring.Position = UDim2.fromOffset(250, 24)
			set = setRing
			local price = label(
				box,
				"Price",
				`💰{Format.coins(DecorConfig.priceOf(id))}`,
				UDim2.fromOffset(190, 28),
				UDim2.fromOffset(250, 24 + DECOR_CONFIRM_RING + 6),
				22,
				YELLOW,
				FONT_BOLD
			)
			price.TextXAlignment = Enum.TextXAlignment.Left
		end
		local ok = button(
			box,
			"Ok",
			"✓",
			UDim2.fromOffset(DECOR_CONFIRM_OK, DECOR_CONFIRM_OK),
			-- 오른쪽 아래 점프 버튼 자리(812×375 기준)를 피해 조금 왼쪽에 둔다
			UDim2.new(1, -40, 1, -20),
			GREEN,
			WHITE,
			56
		)
		ok.AnchorPoint = Vector2.new(1, 1)
		corner(ok, DECOR_CONFIRM_OK / 2)
		for _, d in box:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 12
			end
		end
		ok.Activated:Connect(function()
			local now = profileOrNil()
			if not now then
				return
			end
			if returning then
				if (now.decorOwned[id] or 0) > 0 then
					Remotes.ReturnDecor:FireServer(id)
					SoundController.play("tick")
				end
				closeConfirm()
				return
			end
			local cost = DecorConfig.priceOf(id)
			local full = DecorConfig.heldCount(now.decorOwned, placedNow(), id) >= DecorConfig.MAX_OWNED
			if now.coins < cost or full then
				return -- 흐린 ✓ 는 눌러도 아무 일 없다
			end
			Remotes.BuyDecor:FireServer(id)
			SoundController.play("tick")
			closeConfirm()
		end)

		confirm = cover
		confirmItem = id
		confirmSet = set
		confirmOk = ok
		paintConfirm(p)
	end

	--- 보관함 줄(개수 > 0). 카드 탭 = 시트 닫고 놓기, ↩ = 돌려주기
	local function buildInventory(p: Profile)
		clearRow(inventory)
		invCards = {}
		local jobs: { () -> () } = {}
		for order, item in DecorConfig.LIST do
			local count = p.decorOwned[item.id] or 0
			if count > 0 then
				local card = button(
					inventory,
					item.id,
					"",
					UDim2.fromOffset(DECOR_INV_CARD.X, DECOR_INV_CARD.Y),
					nil,
					SURFACE,
					WHITE
				)
				card.LayoutOrder = order
				local badge = label(
					card,
					"Count",
					`×{count}`,
					UDim2.fromOffset(40, 20),
					UDim2.new(1, -44, 0, 4),
					16,
					YELLOW,
					FONT_BOLD
				)
				badge.TextXAlignment = Enum.TextXAlignment.Right
				badge.ZIndex = 2
				local back = button(card, "Return", "", UDim2.new(1, -12, 0, 30), UDim2.new(0, 6, 1, -34), DARK, WHITE)
				back.ZIndex = 2
				label(
					back,
					"Glyph",
					DECOR_GLYPH_RETURN,
					UDim2.fromOffset(24, 24),
					UDim2.fromOffset(4, 3),
					20,
					WHITE,
					FONT_BOLD
				).ZIndex =
					3
				local backText =
					label(back, "Text", "돌려주기", UDim2.new(1, -32, 1, -6), UDim2.fromOffset(28, 3), 14, GREY)
				backText.ZIndex = 3
				local id = item.id
				card.Activated:Connect(function()
					PanelController.close()
					DecorController.beginPlace(id)
				end)
				back.Activated:Connect(function()
					openConfirm(id, true)
				end)
				invCards[id] = { card = card, count = badge }
				table.insert(jobs, function()
					if card.Parent then
						decorPicture(card, item, DECOR_INV_PICTURE, UDim2.fromOffset(12, 4))
					end
				end)
			end
		end
		drawLater(jobs)
	end

	--- 가게 줄(진열 대상, 선물 제외, 가격순). 탭 = 큰 확인 카드
	local function buildShop()
		clearRow(shop)
		shopCards = {}
		local rows: { DecorConfig.Item } = {}
		for _, item in DecorConfig.LIST do
			if DecorConfig.isShown(item) then
				table.insert(rows, item)
			end
		end
		table.sort(rows, function(a, b)
			return a.price < b.price
		end)
		local jobs: { () -> () } = {}
		for order, item in rows do
			local card =
				button(shop, item.id, "", UDim2.fromOffset(DECOR_SHOP_CARD.X, DECOR_SHOP_CARD.Y), nil, SURFACE, WHITE)
			card.LayoutOrder = order
			local ring, set = makeRing(card, DECOR_SHOP_RING, 4, GREEN)
			ring.Position = UDim2.new(0, 6, 1, -DECOR_SHOP_RING - 6)
			local price = label(
				card,
				"Price",
				Format.coins(DecorConfig.priceOf(item.id)),
				UDim2.new(1, -DECOR_SHOP_RING - 14, 0, 20),
				UDim2.new(0, DECOR_SHOP_RING + 10, 1, -DECOR_SHOP_RING / 2 - 16),
				16,
				YELLOW,
				FONT_BOLD
			)
			price.TextXAlignment = Enum.TextXAlignment.Left
			-- 보관함 + 배치가 상한이면 카드 전체를 흐리게 덮는다
			local dim = frame(card, "Dim", UDim2.fromScale(1, 1), nil, DARK, 0.45)
			corner(dim, RADIUS)
			dim.ZIndex = 3
			dim.Visible = false
			local id = item.id
			card.Activated:Connect(function()
				local now = profileOrNil()
				if now and DecorConfig.heldCount(now.decorOwned, placedNow(), id) >= DecorConfig.MAX_OWNED then
					return
				end
				openConfirm(id, false)
				SoundController.play("tick")
			end)
			shopCards[id] = { card = card, set = set, dim = dim }
			table.insert(jobs, function()
				if card.Parent then
					decorPicture(card, item, DECOR_SHOP_PICTURE, UDim2.fromOffset(14, 4))
				end
			end)
		end
		drawLater(jobs)
	end

	local function refresh(p: Profile)
		-- 보관함 아이디 목록이 바뀔 때만 줄을 다시 만든다(진열 목록은 고정이다)
		local inv: { string } = {}
		for _, item in DecorConfig.LIST do
			if (p.decorOwned[item.id] or 0) > 0 then
				table.insert(inv, item.id)
			end
		end
		local nextInv = table.concat(inv, ",")
		if nextInv ~= invKey then
			-- 두 줄의 그림 작업이 같은 rowGen 을 쓰므로 둘 다 새로 만든다
			invKey = nextInv
			rowGen += 1
			buildInventory(p)
			buildShop()
		end
		for id, ui in invCards do
			ui.count.Text = `×{p.decorOwned[id] or 0}`
		end
		local placed = placedNow() -- 카드마다 Decor 어트리뷰트를 다시 풀지 않게 한 번만
		for id, ui in shopCards do
			local cost = DecorConfig.priceOf(id)
			ui.set(if cost > 0 then p.coins / cost else 1)
			ui.dim.Visible = DecorConfig.heldCount(p.decorOwned, placed, id) >= DecorConfig.MAX_OWNED
		end
		paintConfirm(p)

		local pending = decorPendingPunch
		if pending then
			local target = invCards[pending] or shopCards[pending]
			if target then
				decorPendingPunch = nil
				punchCard(target.card)
			end
		end
	end

	local profile = profileOrNil()
	if profile then
		refresh(profile)
	end
	currentRefresh = refresh
	table.insert(currentCleanup, closeConfirm)
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
	decor = function(c, _)
		buildDecor(c)
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

--- 서버 DecorBought / DecorReturned(본인에게만). 꾸미기 시트가 열려 있으면 카드를 다시 칠하고 그 카드를 짧게 펀치
function PanelController.onDecorEvent(payload: any)
	if currentName ~= "decor" or typeof(payload) ~= "table" or typeof(payload.item) ~= "string" then
		return
	end
	decorPendingPunch = payload.item
	local fn = currentRefresh
	local p = profileOrNil()
	if fn and p then
		local ok, err = pcall(fn :: any, p)
		if not ok then
			warn(`[Panel] 꾸미기 갱신 실패: {err}`)
		end
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
