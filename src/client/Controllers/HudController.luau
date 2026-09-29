--!strict
--[[
	HUD. 기획서 §8.2 표의 위젯과 프로필 로컬 캐시(§11.3)를 여기서 소유한다.

	  ★ 프로필의 유일한 클라이언트 사본이다. ProfileSync 는 setProfile 하나로만 들어오고(seq 가 크지 않으면 버림),
	    다른 컨트롤러는 profile() / onProfile() 로만 읽는다. 컨트롤러끼리 프로필을 따로 들고 있지 않는다.
	  ★ 좌표는 812×375 기준 px Offset 이고 UIScale = clamp(viewportHeight / 375, 0.9, 1.6) 로만 키운다(§8.1).
	    루트 프레임 Size 를 1/scale 로 두어 Scale 1 = 화면 끝이 되게 한다 — 오른쪽 열은 (1, -12) 로 붙는다.
	  ★ 첫 시설 전에는 용돈 칩과 「다음 시설」 카드만 보인다(§2.2 0:00). 나머지는 프로필이 조건을 채울 때 나타난다.
	  ★ 링 게이지는 원형 UIStroke 대신 얇은 진행바다(모바일 성능 우선). 매 초(Heartbeat 누적) 캐시로 다시 계산한다.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared.Config.Keys)
local DecorConfig = require(Shared.Config.DecorConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local FacilityConfig = require(Shared.Config.FacilityConfig)
local MissionConfig = require(Shared.Config.MissionConfig)
local StudentConfig = require(Shared.Config.StudentConfig)
local TowerConfig = require(Shared.Config.TowerConfig)
local Format = require(Shared.Format)
local PlotLayout = require(Shared.PlotLayout)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type Profile = Types.Profile
type Listener = (Profile) -> ()
export type SyncPacket = { seq: number, profile: Profile }

-- ── 기준 치수(§8.1) ──
local BASE_HEIGHT = 375
local SCALE_MIN = 0.9
local SCALE_MAX = 1.6
local TEXT_MIN = 14
local TEXT_MAX = 32
local CORNER = 8

-- ── 색(§8.1) ──
local PANEL = Color3.fromRGB(31, 41, 55)
local PANEL_ALPHA = 0.15 -- α0.85
local YELLOW = Color3.fromRGB(251, 191, 36)
local GREEN = Color3.fromRGB(52, 211, 153)
local GOLD = Color3.fromRGB(245, 158, 11)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(209, 213, 219)
local TRACK = Color3.fromRGB(55, 65, 81)

-- ── 시간(§8.2·§9.1) ──
local ROLL_SECONDS = 0.4 -- 용돈 숫자 롤 Quad Out
local DELTA_SECONDS = 0.4 -- 「-가격」 표시
local PUNCH_SCALE = 1.15
local PUNCH_SECONDS = 0.25
local PULSE_SECONDS = 0.8
local SLIDE_SECONDS = 0.25
local FLY_SECONDS = 0.5
local GIFT_POP_SECONDS = 0.25 -- 선물 상자가 커지는 시간(Back)
local GIFT_HOP_SECONDS = 0.15 -- 위로 톡 뛰었다 내려오는 한쪽 시간
local GIFT_OPEN_SECONDS = 0.2 -- 열리며 사라지는 시간. 합 0.25 + 0.15 + 0.2 ≒ 0.6초
local GIFT_HOP_PX = 10
local GIFT_POP_SCALE = 1.3
local GIFT_OPEN_SCALE = 1.8
local TOAST_HOLD = 2.6
local BANNER_HOLD = 4
local FADE_SECONDS = 0.35
local PAN_SECONDS = 0.4 -- §8.2 탭 → 카메라 팬
local GO_HOME_COOLDOWN = 5 -- §11.5 GoHome 속도 제한과 같은 값
local TICK_SECONDS = 1
local GOLD_MULTIPLIER = 2 -- 배율 칩이 금색이 되는 기준

-- 부지 반폭. 기획서 §7.2 부지 150×150. 부지 중심은 월드 인스턴스에서 읽는다
-- TODO(통합): 부지 크기 상수를 Config 로 옮기면 여기서 참조
local PLOT_HALF = 75

-- 다른 컨트롤러 이름·패널 이름·소리 키
-- 패널 이름은 PanelController.PanelName, 소리 키는 SoundConfig.DEFS 와 같아야 한다
local PANEL_SETTINGS = "settings"
local PANEL_CODEX = "codex"
local PANEL_MISSIONS = "missions"
local PANEL_DECOR = "decor"
local SOUND_AFFORD = "afford_ding"

-- 사용자에게 보이는 문구(≤12자)
local TEXT_NEXT_CAPTION = "다음 시설"
local TEXT_NEXT_FLOOR = "다음 층"
local TEXT_AFFORD = "살 수 있어요!"
local TEXT_NO_INCOME = "스티커를 줍자!"
local TEXT_GRADUATE = "졸업식을 열자!"
local TEXT_GRADUATE_SUB = "강당 종을 치자!"
local TEXT_GO_HOME = "우리 학교로"
local TEXT_GO_HOME_SUB = "탭하면 돌아가요"

-- TODO(통합): 아이콘 이미지(용돈·스티커·도감·미션·설정·집). 지금은 글리프로 대신한다
local GLYPH_COINS = "💰"
local GLYPH_HOME = "🏠"
local GLYPH_SETTINGS = "⚙️"
local GLYPH_CODEX = "📖"
local GLYPH_MISSIONS = "📋"
local GLYPH_DECOR = "🪴"
local GLYPH_GIFT = "🎁"
-- 선물 아이템이 꾸미기 버튼으로 날아갈 때의 글리프(DecorConfig.Kind 별). 없으면 GLYPH_DECOR
local GLYPH_BY_KIND: { [string]: string } = {
	general = "🪴",
	friend = "🙂",
	gift = "🎈",
}

-- 강당(마지막 시설). 강당을 지어야 탑 층을 살 수 있다(§3.6 #8)
local AUDITORIUM_ID = "auditorium"

local player = Players.LocalPlayer

local HudController = {}

-- ── 상태 ──
local built = false
local cached: Profile? = nil
local cachedSeq = 0
local listeners: { [number]: Listener } = {}
local listenerSeq = 0

local lastSeenStudents: number? = nil -- 도감 빨간 점: 마지막으로 도감을 연 때의 보유 수
local wasAffordable: boolean? = nil
local onOwnPlot = true
local goHomeAt = -math.huge
local nextTap: (() -> ())? = nil
local shownCardKey: string? = nil
local decorNew = false -- 선물로 받은 꾸미기가 있다. 꾸미기 시트를 열 때까지 점을 켠다
local giftToken = 0
local plotCenters: { [number]: Vector3 } = {}
local pulses: { [UIStroke]: Tween } = {}
local held = false -- 졸업식 동안 숨기고 새 프로필을 그리지 않는다(§9.5)
local heldFrom: Profile? = nil -- 숨기기 직전 프로필. 풀 때 이것과 비교해 롤·펀치를 낸다

local toastToken = 0
local bannerToken = 0
local bannerQueue: { string } = {}
local bannerBusy = false

-- 순환 require 를 피하려고 Start 에서 늦게 잇는다(PanelController 가 이 모듈을 require 한다)
local Camera: any = nil
local Panel: any = nil
local Sound: any = nil

-- ── UI 참조 ──
local root: Frame
local rootScale: UIScale
local coinsChip: Frame
local coinsLabel: TextLabel
local coinsDelta: TextLabel
local coinsValue: NumberValue
local coinsScale: UIScale
local incomeChip: Frame
local incomeLabel: TextLabel
local incomeScale: UIScale
local card: TextButton
local cardCaption: TextLabel
local cardName: TextLabel
local cardPrice: TextLabel
local cardSub: TextLabel
local cardBar: Frame
local cardFill: Frame
local cardStroke: UIStroke
local boardChip: Frame
local boardLabel: TextLabel
local boardFill: Frame
local multChip: Frame
local multLabel: TextLabel
local multScale: UIScale
local settingsButton: TextButton
local codexButton: TextButton
local codexDot: Frame
local missionButton: TextButton
local missionBadge: TextLabel
local decorButton: TextButton
local decorTapMarked = false -- UiMark "decorTap" 을 이미 보냈나
local decorDot: Frame
local decorStroke: UIStroke
local decorScale: UIScale
local giftBox: TextLabel
local giftBoxScale: UIScale
local toastLabel: TextLabel
local bannerLabel: TextLabel
local flyer: TextLabel

-- ── 생성 헬퍼 ──

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeScale(parent: Instance): UIScale
	local s = Instance.new("UIScale")
	s.Parent = parent
	return s
end

local function makeStroke(parent: Instance, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function makePanel(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = PANEL_ALPHA
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, CORNER)
	return frame
end

local function makeLabel(parent: Instance, name: string, font: Enum.Font, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.Text = ""
	label.Parent = parent

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = TEXT_MIN
	constraint.MaxTextSize = TEXT_MAX
	constraint.Parent = label
	return label
end

local function makeButton(parent: Instance, name: string, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = PANEL_ALPHA
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = parent
	corner(button, CORNER)
	return button
end

local function makeBar(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = name
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = TRACK
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 2)
	return track, fill
end

-- ── 연출 헬퍼 ──

local function tween(target: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(
		target,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

--- 위젯을 잠깐 키웠다 되돌린다(§8.2 「펀치 1.15」)
local function punch(scale: UIScale)
	scale.Scale = PUNCH_SCALE
	tween(scale, PUNCH_SECONDS, { Scale = 1 }, Enum.EasingStyle.Back)
end

--- 테두리 펄스 켜기/끄기. 켜진 것을 또 켜도 새로 시작하지 않는다
local function pulse(stroke: UIStroke, on: boolean)
	local running = pulses[stroke]
	if on then
		if running then
			return
		end
		stroke.Transparency = 0.1
		local t = TweenService:Create(
			stroke,
			TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.75 }
		)
		t:Play()
		pulses[stroke] = t
	elseif running then
		running:Cancel()
		pulses[stroke] = nil
		stroke.Transparency = 1
	end
end

--- 카드 내용이 바뀔 때 위에서 살짝 내려온다(§9.2 「카드 슬라이드 0.25초」)
local function slideCard()
	local target = card.Position
	card.Position = UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale, target.Y.Offset - 10)
	tween(card, SLIDE_SECONDS, { Position = target })
end

--- 루트 프레임 기준 px 좌표(UIScale 을 되돌린 값)
local function rootLocal(gui: GuiObject): Vector2
	local scale = rootScale.Scale
	local center = gui.AbsolutePosition + gui.AbsoluteSize / 2
	return (center - root.AbsolutePosition) / scale
end

--- 스티커판 40칸 = 선물. 코인 글리프가 판 칩에서 용돈 칩으로 날아가고 도착하면 용돈 칩이 펀치
local function flyGift()
	local from = rootLocal(boardChip)
	local to = rootLocal(coinsChip)
	flyer.Text = GLYPH_COINS
	flyer.Position = UDim2.fromOffset(from.X, from.Y)
	flyer.TextTransparency = 0
	flyer.Visible = true
	local t = tween(flyer, FLY_SECONDS, { Position = UDim2.fromOffset(to.X, to.Y) }, Enum.EasingStyle.Quad)
	t.Completed:Once(function()
		flyer.Visible = false
		punch(coinsScale)
	end)
end

--- 선물 아이템 글리프가 판 칩에서 「꾸미기」 버튼으로 날아가고, 도착하면 버튼 펀치 + 새 아이템 점
local function flyItem(itemId: string)
	local item = DecorConfig.byId(itemId)
	local from = rootLocal(boardChip)
	local to = rootLocal(decorButton)
	flyer.Text = if item then GLYPH_BY_KIND[item.kind] or GLYPH_DECOR else GLYPH_DECOR
	flyer.Position = UDim2.fromOffset(from.X, from.Y)
	flyer.TextTransparency = 0
	flyer.Visible = true
	local t = tween(flyer, FLY_SECONDS, { Position = UDim2.fromOffset(to.X, to.Y) }, Enum.EasingStyle.Quad)
	t.Completed:Once(function()
		flyer.Visible = false
		decorNew = true
		decorDot.Visible = true
		punch(decorScale)
	end)
end

--- 판 칩 위에서 🎁 가 커지고 톡 뛰었다가 열리며 사라진다(≒0.6초, 흔들기 없음). 끝나면 done
local function openGiftBox(done: () -> ())
	giftToken += 1
	local mine = giftToken
	local at = rootLocal(boardChip)
	local base = UDim2.fromOffset(at.X, at.Y)
	local up = UDim2.fromOffset(at.X, at.Y - GIFT_HOP_PX)
	giftBox.Position = base
	giftBox.TextTransparency = 0
	giftBoxScale.Scale = 0
	giftBox.Visible = true
	tween(giftBoxScale, GIFT_POP_SECONDS, { Scale = GIFT_POP_SCALE }, Enum.EasingStyle.Back)
	tween(giftBox, GIFT_HOP_SECONDS, { Position = up }).Completed:Once(function()
		tween(giftBox, GIFT_HOP_SECONDS, { Position = base }, Enum.EasingStyle.Bounce)
	end)
	task.delay(GIFT_POP_SECONDS + GIFT_HOP_SECONDS, function()
		if mine ~= giftToken then
			return
		end
		tween(giftBoxScale, GIFT_OPEN_SECONDS, { Scale = GIFT_OPEN_SCALE })
		tween(giftBox, GIFT_OPEN_SECONDS, { TextTransparency = 1 }).Completed:Once(function()
			if mine == giftToken then
				giftBox.Visible = false
			end
		end)
		done()
	end)
end

-- ── 월드 위치 읽기 ──

local function plotModel(plotId: number): Model?
	local plots = Workspace:FindFirstChild(Keys.PLOTS_FOLDER)
	local plot = if plots then plots:FindFirstChild(Keys.plotName(plotId)) else nil
	return if plot and plot:IsA("Model") then plot else nil
end

--- 부지 중심(월드) = 모델 피벗(PlotShell 이 부지 CFrame 으로 둔다). 바운딩박스는 스트리밍으로 파트 일부만 있으면 어긋난다
local function plotCenter(plotId: number): Vector3?
	local known = plotCenters[plotId]
	if known then
		return known
	end
	local plot = plotModel(plotId)
	if not plot then
		return nil
	end
	local center = plot:GetPivot().Position
	plotCenters[plotId] = center
	return center
end

local function padPosition(plotId: number, facilityId: string): Vector3?
	local plot = plotModel(plotId)
	local pads = if plot then plot:FindFirstChild(Keys.PADS_FOLDER) else nil
	local pad = if pads then pads:FindFirstChild(facilityId) else nil
	return if pad and pad:IsA("BasePart") then pad.Position else nil
end

local function partPosition(plotId: number, partName: string): Vector3?
	local plot = plotModel(plotId)
	local part = if plot then plot:FindFirstChild(partName, true) else nil
	return if part and part:IsA("BasePart") then part.Position else nil
end

--- 탑 TowerPad 위치. 파트가 스트리밍 밖이면 부지 피벗 + PlotLayout.TOWER_PAD 로 계산한다
local function towerPadPosition(plotId: number): Vector3?
	local plot = plotModel(plotId)
	if not plot then
		return nil
	end
	local tower = plot:FindFirstChild(Keys.TOWER_FOLDER)
	local pad = if tower then tower:FindFirstChild(Keys.TOWER_PAD) else nil
	if pad and pad:IsA("BasePart") then
		return pad.Position
	end
	return plot:GetPivot():PointToWorldSpace(PlotLayout.TOWER_PAD)
end

local function panTo(position: Vector3?)
	if position and Camera and Camera.panTo then
		pcall(Camera.panTo, position, PAN_SECONDS)
	end
end

--- 구독자 한 명을 pcall 로 부른다. Listener 는 반환값이 없어 pcall 결과가 1개라 any 로 넘긴다
local function notify(fn: Listener, profile: Profile)
	local ok, err = pcall(fn :: any, profile)
	if not ok then
		warn(`[Hud] onProfile 구독자 오류: {err}`)
	end
end

-- ── 파생값 ──

local function facilityCount(profile: Profile): number
	return FacilityConfig.count(profile.facilities)
end

--- 첫 시설을 지었거나 졸업한 적이 있으면 HUD 전체가 열린다
local function unlocked(profile: Profile): boolean
	return facilityCount(profile) > 0 or profile.graduations > 0
end

local function missionsDone(profile: Profile): number
	local n = 0
	for _, done in profile.missions.done do
		if done then
			n += 1
		end
	end
	return n
end

--- 강당까지 지었을 때 다음에 살 탑 층 번호. 강당 전이거나 꼭대기면 nil
local function nextTowerFloor(profile: Profile): number?
	if not profile.facilities[AUDITORIUM_ID] then
		return nil
	end
	return TowerConfig.nextFloor(profile.towerFloors)
end

--- prev 에 없고 now 에 있는 시설 하나. 없으면 nil
local function newlyBuilt(prev: Profile?, now: Profile): string?
	for _, id in FacilityConfig.ORDER do
		if now.facilities[id] and not (prev and prev.facilities[id]) then
			return id
		end
	end
	return nil
end

--- prev → now 사이에 산 부품 하나의 가격. 산 부품이 없으면 nil(졸업으로 줄어든 것도 nil)
local function boughtPartPrice(prev: Profile?, now: Profile): number?
	if not prev then
		return nil
	end
	local before = FacilityConfig.partsBuilt(prev.facilities, prev.buildParts)
	local after = FacilityConfig.partsBuilt(now.facilities, now.buildParts)
	if after <= before then
		return nil
	end
	-- 방금 완공이면 그 시설의 마지막 부품, 아니면 다음 시설의 buildParts 번째 부품
	local builtId = newlyBuilt(prev, now)
	if builtId then
		return FacilityConfig.partPriceOf(builtId, FacilityConfig.partCount(builtId), now.graduations)
	end
	local nextRow = FacilityConfig.nextOf(now.facilities)
	if nextRow and now.buildParts > 0 then
		return FacilityConfig.partPriceOf(nextRow.id, now.buildParts, now.graduations)
	end
	return nil
end

-- ── 위젯 갱신 ──

local function renderCoins(profile: Profile, prev: Profile?)
	if prev then
		tween(coinsValue, ROLL_SECONDS, { Value = profile.coins })
	else
		coinsValue.Value = profile.coins
		coinsLabel.Text = Format.coins(profile.coins)
	end

	local price = boughtPartPrice(prev, profile)
	if price then
		coinsDelta.Text = `-{Format.coins(price)}`
		coinsDelta.TextTransparency = 0
		coinsDelta.Position = UDim2.fromOffset(216, 12)
		task.delay(DELTA_SECONDS, function()
			tween(coinsDelta, FADE_SECONDS, { TextTransparency = 1, Position = UDim2.fromOffset(216, 0) })
		end)
	end
end

local function renderIncome(profile: Profile, prev: Profile?)
	local visible = unlocked(profile)
	incomeChip.Visible = visible
	if not visible then
		return
	end
	incomeLabel.Text = Format.income(EconomyConfig.incomePerSecond(profile))
	if prev then
		local grew = facilityCount(profile) > facilityCount(prev)
			or StudentConfig.ownedCount(profile.students) > StudentConfig.ownedCount(prev.students)
		if grew then
			punch(incomeScale)
		end
	end
end

-- 판이 찬 순간은 GiftOpened 가 알려 준다(onGift)
local function renderBoard(profile: Profile)
	boardChip.Visible = unlocked(profile)
	boardLabel.Text = `{profile.stickerBoard}/{EconomyConfig.BOARD_CELLS}`
	boardFill.Size = UDim2.fromScale(math.clamp(profile.stickerBoard / EconomyConfig.BOARD_CELLS, 0, 1), 1)
end

local function renderMultiplier(profile: Profile, prev: Profile?)
	local mult = EconomyConfig.multiplier(profile)
	local visible = mult > 1
	multChip.Visible = visible
	if not visible then
		return
	end
	multLabel.Text = Format.multiplier(mult)
	multLabel.TextColor3 = if mult >= GOLD_MULTIPLIER then GOLD else WHITE
	if prev and mult ~= EconomyConfig.multiplier(prev) then
		punch(multScale)
	end
end

local function renderButtons(profile: Profile)
	local visible = unlocked(profile)
	settingsButton.Visible = visible
	codexButton.Visible = visible
	missionButton.Visible = visible
	decorButton.Visible = visible
	decorDot.Visible = decorNew

	local owned = StudentConfig.ownedCount(profile.students)
	if lastSeenStudents == nil then
		lastSeenStudents = owned
	end
	codexDot.Visible = owned > (lastSeenStudents :: number)
	missionBadge.Text = `{missionsDone(profile)}/{#MissionConfig.LIST}`
end

--- 값이 있는 카드(다음 부품·다음 층) 공통: 가격·예상 초·링·살 수 있음 펄스와 딩
local function showPrice(profile: Profile, caption: string, name: string, price: number)
	local eta = EconomyConfig.etaSeconds(profile, price)
	local affordable = eta <= 0
	cardCaption.Text = caption
	cardName.Text = name
	cardPrice.Text = `{GLYPH_COINS}{Format.coins(price)}`
	cardSub.Text = if affordable
		then TEXT_AFFORD
		elseif eta == math.huge then TEXT_NO_INCOME
		else `약 {Format.eta(eta)}`
	cardBar.Visible = true
	cardFill.Size = UDim2.fromScale(math.clamp(profile.coins / price, 0, 1), 1)
	cardFill.BackgroundColor3 = GREEN
	pulse(cardStroke, affordable)

	-- 살 수 있게 되는 순간 한 번만 딩. 첫 프로필(접속 직후)은 울리지 않는다
	if affordable and wasAffordable == false and Sound and Sound.play then
		pcall(Sound.play, SOUND_AFFORD)
	end
	wasAffordable = affordable
end

--- 「다음 부품」 카드. 매 초 다시 계산한다(링·예상 초·자기 부지 여부)
local function renderCard(profile: Profile)
	local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
	local home = HudController.isOnOwnPlot()
	local key: string
	if not home then
		key = "home"
		cardCaption.Text = ""
		cardName.Text = `{GLYPH_HOME} {TEXT_GO_HOME}`
		cardPrice.Text = ""
		cardSub.Text = TEXT_GO_HOME_SUB
		cardBar.Visible = false
		pulse(cardStroke, false)
	elseif nextPart == nil and nextTowerFloor(profile) then
		local floor = nextTowerFloor(profile) :: number
		key = `floor{floor}`
		showPrice(profile, TEXT_NEXT_FLOOR, `{floor}층`, TowerConfig.priceOf(floor, profile.graduations))
	elseif nextPart == nil then
		key = "graduate"
		cardCaption.Text = `{facilityCount(profile)}/{FacilityConfig.COUNT}`
		cardName.Text = TEXT_GRADUATE
		cardPrice.Text = ""
		cardSub.Text = TEXT_GRADUATE_SUB
		cardBar.Visible = true
		cardFill.Size = UDim2.fromScale(1, 1)
		cardFill.BackgroundColor3 = GOLD
		pulse(cardStroke, true)
	else
		-- 키는 시설 단위라 카드는 시설이 바뀔 때만 미끄러진다(부품마다 흔들지 않는다)
		local facility = nextPart.facility
		key = facility.id
		showPrice(
			profile,
			TEXT_NEXT_CAPTION,
			`{facility.name} {nextPart.index}/{nextPart.count}`,
			FacilityConfig.partPriceOf(facility.id, nextPart.index, profile.graduations)
		)
	end

	if shownCardKey ~= key then
		shownCardKey = key
		slideCard()
	end
end

local function render(profile: Profile, prev: Profile?)
	renderCoins(profile, prev)
	renderIncome(profile, prev)
	renderBoard(profile)
	renderMultiplier(profile, prev)
	renderButtons(profile)
	renderCard(profile)
end

-- ── 탭 처리 ──

local function onCardTap()
	local profile = cached
	if not profile then
		return
	end
	local plotId = HudController.myPlotId()
	if not HudController.isOnOwnPlot() then
		local now = os.clock()
		if now - goHomeAt < GO_HOME_COOLDOWN then
			return
		end
		goHomeAt = now
		Remotes.GoHome:FireServer()
		return
	end
	if nextTap then
		nextTap()
		return
	end
	if not plotId then
		return
	end
	local nextRow = FacilityConfig.nextOf(profile.facilities)
	if nextRow then
		panTo(padPosition(plotId, nextRow.id))
	elseif nextTowerFloor(profile) then
		panTo(towerPadPosition(plotId))
	else
		panTo(partPosition(plotId, Keys.GRADUATION_BELL))
	end
end

local function openPanel(name: string)
	if Panel and Panel.open then
		pcall(Panel.open, name)
	end
end

-- ── 토스트·배너 ──

local function fadeLater(label: TextLabel, hold: number, token: number, current: () -> number, done: (() -> ())?)
	task.delay(hold, function()
		if current() ~= token then
			return
		end
		local t = tween(label, FADE_SECONDS, { TextTransparency = 1, BackgroundTransparency = 1 })
		t.Completed:Once(function()
			if current() == token then
				label.Visible = false
				if done then
					done()
				end
			end
		end)
	end)
end

local function showBanner(text: string)
	bannerBusy = true
	bannerToken += 1
	local mine = bannerToken
	bannerLabel.Text = text
	bannerLabel.TextTransparency = 0
	bannerLabel.Visible = true
	local scale = bannerLabel:FindFirstChildOfClass("UIScale")
	if scale then
		punch(scale)
	end
	fadeLater(bannerLabel, BANNER_HOLD, mine, function()
		return bannerToken
	end, function()
		bannerBusy = false
		local queued = table.remove(bannerQueue, 1)
		if queued then
			showBanner(queued)
		end
	end)
end

-- ── GUI 조립(§8.2 표) ──

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- 상단 인셋만큼 아래에서 시작하는 안전 영역(스케일 없음)
	local safe = Instance.new("Frame")
	safe.Name = "Safe"
	safe.Size = UDim2.fromScale(1, 1)
	safe.BackgroundTransparency = 1
	safe.Parent = gui

	-- 상단바 인셋은 접속 직후 0 이었다가 나중에 채워진다. 한 번만 읽으면 용돈 칩이 Roblox 버튼 밑에 깔린다
	local safePadding = Instance.new("UIPadding")
	local function applyInset()
		safePadding.PaddingTop = UDim.new(0, GuiService:GetGuiInset().Y)
	end
	applyInset()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(applyInset)
	safePadding.Parent = safe

	-- 루트: Size 1/scale × UIScale scale = 화면 전체. 안의 Offset 은 812×375 기준 px
	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Parent = safe
	rootScale = makeScale(root)

	-- 용돈 칩 (12, 12) 200×32
	coinsChip = makePanel(root, "Coins", UDim2.fromOffset(12, 12), UDim2.fromOffset(200, 32))
	coinsScale = makeScale(coinsChip)
	local coinsGlyph = makeLabel(coinsChip, "Glyph", Enum.Font.GothamBold, YELLOW)
	coinsGlyph.Position = UDim2.fromOffset(8, 4)
	coinsGlyph.Size = UDim2.fromOffset(24, 24)
	coinsGlyph.Text = GLYPH_COINS
	coinsLabel = makeLabel(coinsChip, "Value", Enum.Font.GothamBold, YELLOW)
	coinsLabel.Position = UDim2.fromOffset(38, 4)
	coinsLabel.Size = UDim2.fromOffset(154, 24)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsValue = Instance.new("NumberValue")
	coinsValue.Name = "CoinsValue"
	coinsValue.Parent = coinsChip
	coinsValue.Changed:Connect(function(value)
		coinsLabel.Text = Format.coins(value)
	end)
	coinsDelta = makeLabel(root, "CoinsDelta", Enum.Font.GothamBold, WHITE)
	coinsDelta.Position = UDim2.fromOffset(216, 12)
	coinsDelta.Size = UDim2.fromOffset(80, 32)
	coinsDelta.TextXAlignment = Enum.TextXAlignment.Left
	coinsDelta.TextTransparency = 1

	-- 수입 칩 (12, 52) 160×24
	incomeChip = makePanel(root, "Income", UDim2.fromOffset(12, 52), UDim2.fromOffset(160, 24))
	incomeScale = makeScale(incomeChip)
	incomeLabel = makeLabel(incomeChip, "Value", Enum.Font.GothamMedium, GREEN)
	incomeLabel.Position = UDim2.fromOffset(8, 3)
	incomeLabel.Size = UDim2.fromOffset(144, 18)
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeChip.Visible = false

	-- 「꾸미기」 버튼 (12, 84) 56×56. 용돈 칩(12..212, 12..44)·수입 칩(12..172, 52..76) 아래라 겹치지 않는다
	decorButton = makeButton(root, "Decor", UDim2.fromOffset(12, 84), UDim2.fromOffset(56, 56))
	decorStroke = makeStroke(decorButton, YELLOW)
	decorScale = makeScale(decorButton)
	local decorGlyph = makeLabel(decorButton, "Glyph", Enum.Font.GothamBold, WHITE)
	decorGlyph.Position = UDim2.fromOffset(12, 12)
	decorGlyph.Size = UDim2.fromOffset(32, 32)
	decorGlyph.Text = GLYPH_DECOR
	decorDot = Instance.new("Frame")
	decorDot.Name = "NewDot"
	decorDot.AnchorPoint = Vector2.new(1, 0)
	decorDot.Position = UDim2.new(1, -4, 0, 4)
	decorDot.Size = UDim2.fromOffset(12, 12)
	decorDot.BackgroundColor3 = YELLOW
	decorDot.BorderSizePixel = 0
	decorDot.Visible = false
	decorDot.Parent = decorButton
	corner(decorDot, 6)
	decorButton.Visible = false
	decorButton.Activated:Connect(function()
		-- W9 지표: 세션(이 클라)당 첫 탭만 서버에 알린다(Metrics 「버튼 첫 탭」)
		if not decorTapMarked then
			decorTapMarked = true
			Remotes.UiMark:FireServer("decorTap")
		end
		decorNew = false
		decorDot.Visible = false
		openPanel(PANEL_DECOR)
	end)

	-- 「다음 시설」 카드 (306, 12) 200×64, 가운데 정렬
	card = makeButton(root, "NextFacility", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(200, 64))
	card.AnchorPoint = Vector2.new(0.5, 0)
	cardStroke = makeStroke(card, GREEN)
	cardCaption = makeLabel(card, "Caption", Enum.Font.GothamMedium, MUTED)
	cardCaption.Position = UDim2.fromOffset(10, 4)
	cardCaption.Size = UDim2.fromOffset(80, 14)
	cardCaption.TextXAlignment = Enum.TextXAlignment.Left
	cardName = makeLabel(card, "Name", Enum.Font.GothamBold, WHITE)
	cardName.Position = UDim2.fromOffset(10, 18)
	cardName.Size = UDim2.fromOffset(110, 22)
	cardName.TextXAlignment = Enum.TextXAlignment.Left
	cardPrice = makeLabel(card, "Price", Enum.Font.GothamBold, YELLOW)
	cardPrice.Position = UDim2.fromOffset(120, 18)
	cardPrice.Size = UDim2.fromOffset(70, 22)
	cardPrice.TextXAlignment = Enum.TextXAlignment.Right
	cardSub = makeLabel(card, "Sub", Enum.Font.GothamMedium, MUTED)
	cardSub.Position = UDim2.fromOffset(10, 40)
	cardSub.Size = UDim2.fromOffset(180, 14)
	cardSub.TextXAlignment = Enum.TextXAlignment.Left
	cardBar, cardFill = makeBar(card, "Ring", UDim2.fromOffset(10, 56), UDim2.fromOffset(180, 4), GREEN)
	card.Activated:Connect(onCardTap)

	-- 스티커판 미니 게이지 (556, 12) 96×64 = 가운데 +150
	boardChip = makePanel(root, "Board", UDim2.new(0.5, 150, 0, 12), UDim2.fromOffset(96, 64))
	-- 글자 대신 🎁 + 칸 게이지(글보다 그림). 숫자는 작게 아래에
	local boardGlyph = makeLabel(boardChip, "Caption", Enum.Font.GothamBold, WHITE)
	boardGlyph.Position = UDim2.fromOffset(6, 4)
	boardGlyph.Size = UDim2.fromOffset(84, 24)
	boardGlyph.Text = GLYPH_GIFT
	local _boardBar, fill = makeBar(boardChip, "Ring", UDim2.fromOffset(8, 32), UDim2.fromOffset(80, 10), YELLOW)
	boardLabel = makeLabel(boardChip, "Value", Enum.Font.GothamBold, MUTED)
	boardLabel.Position = UDim2.fromOffset(6, 44)
	boardLabel.Size = UDim2.fromOffset(84, 16)
	boardFill = fill
	boardChip.Visible = false

	-- 배율 칩 (556, 84) 96×24
	multChip = makePanel(root, "Multiplier", UDim2.new(0.5, 150, 0, 84), UDim2.fromOffset(96, 24))
	multScale = makeScale(multChip)
	multLabel = makeLabel(multChip, "Value", Enum.Font.GothamBold, WHITE)
	multLabel.Position = UDim2.fromOffset(6, 3)
	multLabel.Size = UDim2.fromOffset(84, 18)
	multChip.Visible = false

	-- 오른쪽 버튼 열 (744, 12/80/148) 56×56 — 우하 예약 영역(y ≥ 263)을 넘지 않는다
	settingsButton = makeButton(root, "Settings", UDim2.new(1, -12, 0, 12), UDim2.fromOffset(56, 56))
	settingsButton.AnchorPoint = Vector2.new(1, 0)
	local settingsGlyph = makeLabel(settingsButton, "Glyph", Enum.Font.GothamBold, WHITE)
	settingsGlyph.Position = UDim2.fromOffset(12, 12)
	settingsGlyph.Size = UDim2.fromOffset(32, 32)
	settingsGlyph.Text = GLYPH_SETTINGS
	settingsButton.Visible = false
	settingsButton.Activated:Connect(function()
		openPanel(PANEL_SETTINGS)
	end)

	codexButton = makeButton(root, "Codex", UDim2.new(1, -12, 0, 80), UDim2.fromOffset(56, 56))
	codexButton.AnchorPoint = Vector2.new(1, 0)
	local codexGlyph = makeLabel(codexButton, "Glyph", Enum.Font.GothamBold, WHITE)
	codexGlyph.Position = UDim2.fromOffset(12, 12)
	codexGlyph.Size = UDim2.fromOffset(32, 32)
	codexGlyph.Text = GLYPH_CODEX
	codexDot = Instance.new("Frame")
	codexDot.Name = "NewDot"
	codexDot.AnchorPoint = Vector2.new(1, 0)
	codexDot.Position = UDim2.new(1, -4, 0, 4)
	codexDot.Size = UDim2.fromOffset(12, 12)
	codexDot.BackgroundColor3 = YELLOW
	codexDot.BorderSizePixel = 0
	codexDot.Visible = false
	codexDot.Parent = codexButton
	corner(codexDot, 6)
	codexButton.Visible = false
	codexButton.Activated:Connect(function()
		local profile = cached
		if profile then
			lastSeenStudents = StudentConfig.ownedCount(profile.students)
			codexDot.Visible = false
		end
		openPanel(PANEL_CODEX)
	end)

	missionButton = makeButton(root, "Missions", UDim2.new(1, -12, 0, 148), UDim2.fromOffset(56, 56))
	missionButton.AnchorPoint = Vector2.new(1, 0)
	local missionGlyph = makeLabel(missionButton, "Glyph", Enum.Font.GothamBold, WHITE)
	missionGlyph.Position = UDim2.fromOffset(12, 8)
	missionGlyph.Size = UDim2.fromOffset(32, 28)
	missionGlyph.Text = GLYPH_MISSIONS
	missionBadge = makeLabel(missionButton, "Badge", Enum.Font.GothamBold, YELLOW)
	missionBadge.Position = UDim2.fromOffset(4, 38)
	missionBadge.Size = UDim2.fromOffset(48, 14)
	missionButton.Visible = false
	missionButton.Activated:Connect(function()
		openPanel(PANEL_MISSIONS)
	end)

	-- 토스트 (406, 300) 406×28 가운데
	toastLabel = makeLabel(root, "Toast", Enum.Font.GothamMedium, WHITE)
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0, 300)
	toastLabel.Size = UDim2.fromOffset(406, 28)
	toastLabel.BackgroundColor3 = PANEL
	toastLabel.BackgroundTransparency = PANEL_ALPHA
	toastLabel.Visible = false
	corner(toastLabel, CORNER)
	local toastPadding = Instance.new("UIPadding")
	toastPadding.PaddingLeft = UDim.new(0, 12)
	toastPadding.PaddingRight = UDim.new(0, 12)
	toastPadding.Parent = toastLabel

	-- 배너(미션·졸업) 카드 아래 가운데, 4초
	bannerLabel = makeLabel(root, "Banner", Enum.Font.GothamBold, YELLOW)
	bannerLabel.AnchorPoint = Vector2.new(0.5, 0)
	bannerLabel.Position = UDim2.new(0.5, 0, 0, 120)
	bannerLabel.Size = UDim2.fromOffset(406, 40)
	bannerLabel.TextStrokeTransparency = 0.4
	bannerLabel.Visible = false
	makeScale(bannerLabel)

	-- 스티커판 → 용돈 칩으로 날아가는 코인(선물)
	flyer = makeLabel(root, "Flyer", Enum.Font.GothamBold, YELLOW)
	flyer.AnchorPoint = Vector2.new(0.5, 0.5)
	flyer.Size = UDim2.fromOffset(28, 28)
	flyer.Text = GLYPH_COINS
	flyer.Visible = false
	flyer.ZIndex = 5

	-- 판 칩 위에서 열리는 선물 상자
	giftBox = makeLabel(root, "GiftBox", Enum.Font.GothamBold, WHITE)
	giftBox.AnchorPoint = Vector2.new(0.5, 0.5)
	giftBox.Size = UDim2.fromOffset(48, 48)
	giftBox.Text = GLYPH_GIFT
	giftBox.Visible = false
	giftBox.ZIndex = 6
	giftBoxScale = makeScale(giftBox)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function applyScale()
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else BASE_HEIGHT
	local scale = math.clamp(height / BASE_HEIGHT, SCALE_MIN, SCALE_MAX)
	rootScale.Scale = scale
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

-- ── 공개 API ──

--- 서버 ProfileSync. seq 가 지금 것보다 크지 않으면 버린다(§11.3)
function HudController.setProfile(packet: SyncPacket)
	if typeof(packet) ~= "table" or typeof(packet.seq) ~= "number" or typeof(packet.profile) ~= "table" then
		warn("[Hud] ProfileSync 형태가 이상함")
		return
	end
	if packet.seq <= cachedSeq then
		return
	end
	local prev = cached
	cachedSeq = packet.seq
	cached = packet.profile

	if built and not held then
		render(packet.profile, prev)
	end
	for _, fn in listeners do
		notify(fn, packet.profile)
	end
end

--- 로컬 캐시된 프로필. 첫 ProfileSync 전에는 nil
function HudController.profile(): Profile?
	return cached
end

--- 프로필이 바뀔 때마다 부른다. 이미 캐시가 있으면 즉시 한 번 부른다. 반환값은 구독 해제 함수
function HudController.onProfile(fn: Listener): () -> ()
	listenerSeq += 1
	local id = listenerSeq
	listeners[id] = fn
	local current = cached
	if current then
		task.spawn(notify, fn, current)
	end
	return function()
		listeners[id] = nil
	end
end

--- 캐시로 위젯 전부 다시 그린다(MissionDone 등)
function HudController.refresh()
	local profile = cached
	if built and profile and not held then
		render(profile, profile)
	end
end

--- 졸업식(§9.5) 동안 HUD 를 숨긴다. 서버는 0초에 프로필을 초기화하지만, 용돈 14·배율 펀치·「책상 세트」 카드는
--- 9.0초 교실1 컷에서 보여야 한다. 풀 때 식 전 프로필과 비교해 한 번에 그린다
function HudController.hold(on: boolean)
	if on == held then
		return
	end
	held = on
	if on then
		heldFrom = cached
		if built then
			root.Visible = false
		end
		return
	end
	local from = heldFrom
	heldFrom = nil
	local profile = cached
	if built then
		root.Visible = true
		if profile then
			render(profile, from)
		end
	end
end

--- 서버 GiftOpened(본인에게만). 판 칩 위에서 🎁 가 열리고, 아이템이면 「꾸미기」 버튼으로, 용돈이면 용돈 칩으로 날아간다.
--- 글자는 하나도 띄우지 않는다. 판 칩이 안 보이거나 졸업식 중(HUD 숨김)이면 건너뛴다
function HudController.onGift(payload: any)
	if not built or held or not boardChip.Visible then
		return
	end
	local itemId = if typeof(payload) == "table" and typeof(payload.item) == "string" then payload.item else nil
	openGiftBox(function()
		if itemId then
			flyItem(itemId)
		else
			flyGift()
		end
	end)
end

--- 「꾸미기」 버튼의 화면 절대 좌표(IgnoreGuiInset 기준)와 크기. 안 보이면 nil. 튜토리얼 2D 손가락이 쓴다
function HudController.decorButtonRect(): (Vector2?, Vector2?)
	if not built or not decorButton.Visible or not root.Visible then
		return nil, nil
	end
	return decorButton.AbsolutePosition, decorButton.AbsoluteSize
end

--- 「꾸미기」 버튼 테두리 펄스(튜토리얼 꾸미기 단계)
function HudController.pulseDecorButton(on: boolean)
	if not built then
		return
	end
	pulse(decorStroke, on)
end

--- 2.6초 토스트
function HudController.toast(text: string)
	if not built then
		return
	end
	toastToken += 1
	local mine = toastToken
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = PANEL_ALPHA
	toastLabel.Visible = true
	fadeLater(toastLabel, TOAST_HOLD, mine, function()
		return toastToken
	end)
end

--- 4초 배너(미션·졸업). 떠 있는 배너가 있으면 뒤에 줄을 선다
-- TODO(통합): 도감 카드(FeedbackController)가 떠 있으면 그 뒤로 큐잉(§2.2 0:12)
function HudController.banner(text: string)
	if not built then
		return
	end
	if bannerBusy then
		table.insert(bannerQueue, text)
		return
	end
	showBanner(text)
end

--- 내 부지 번호. 배정 전이면 nil
function HudController.myPlotId(): number?
	local value = player:GetAttribute(Keys.ATTR_PLOT)
	return if typeof(value) == "number" then value else nil
end

--- 캐릭터가 내 부지 120×120 안에 있는가. 캐릭터가 없으면 마지막 값을 돌려준다
function HudController.isOnOwnPlot(): boolean
	local plotId = HudController.myPlotId()
	if not plotId then
		return true
	end
	local character = player.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not (rootPart and rootPart:IsA("BasePart")) then
		return onOwnPlot
	end
	local center = plotCenter(plotId)
	if not center then
		-- 모델이 아직 없다 = 스트리밍 밖 = 멀리 있다
		onOwnPlot = false
		return false
	end
	local offset = rootPart.Position - center
	onOwnPlot = math.abs(offset.X) <= PLOT_HALF and math.abs(offset.Z) <= PLOT_HALF
	return onOwnPlot
end

--- 「다음 시설」 카드 탭을 가로챈다(PadController 가 패드 위치를 안다). nil 이면 기본 동작(패드로 팬)
function HudController.setNextFacilityTap(fn: (() -> ())?)
	nextTap = fn
end

function HudController.Start()
	if built then
		return
	end
	buildGui()
	built = true

	-- 순환 require 를 피해 여기서 잇는다. 없어도 HUD 는 뜬다
	local controllers = script.Parent
	local function link(name: string): any
		local module = controllers:FindFirstChild(name)
		if not module then
			warn(`[Hud] {name} 이 없어 연결하지 않음`)
			return nil
		end
		local ok, result = pcall(require, module)
		if not ok then
			warn(`[Hud] {name} require 실패: {result}`)
			return nil
		end
		return result
	end
	Camera = link("CameraController")
	Panel = link("PanelController")
	Sound = link("SoundController")

	applyScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	-- 부지 배정·캐릭터 교체 때 카드 상태(우리 학교로)를 바로 맞춘다
	player:GetAttributeChangedSignal(Keys.ATTR_PLOT):Connect(function()
		plotCenters = {}
		HudController.refresh()
	end)

	-- 매 초 링·예상 초·자기 부지 여부 재계산
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK_SECONDS then
			return
		end
		acc = 0
		local profile = cached
		if profile and not held then
			renderCard(profile)
		end
	end)

	local profile = cached
	if profile then
		render(profile, nil)
	end
end

return HudController
