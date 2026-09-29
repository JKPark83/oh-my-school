--!strict
--[[
	FeedbackController — 손맛(기획서 §9)

	이벤트 하나에 작은 반응 5~8개를 100ms 안에 겹쳐 쏜다: 소리·파티클·흔들림·플래시·「+N」·햅틱.
	play(kind, payload) 하나로 받고 kind 별 타임라인(§9.2)을 그대로 따른다. 졸업식은 §9.5 의 12초 타임라인.

	★ 부정 피드백은 없다(§9.1). 「부족」은 링 밝힘 + 실루엣 깜빡임 + 낮은 틱뿐이고 글자·빨강·흔들림이 없다.
	★ 카메라는 CameraController 가 굴린다(트라우마 모델). 여기서는 shake(t)·fovPunch()·orbit·cutTo·restore 만 부른다.
	★ 히트스톱은 카메라·UI 만 잠깐 멈춘다(cutTo 로 현재 프레임에 고정 → restore). 월드는 멈추지 않는다.
	★ 플래시 한도(§8.4): α ≤ 0.7, ≤ 0.08초, 초당 1회. 설정 「흔들림 끔」이면 흔들림·FOV·플래시·히트스톱을 모두 끈다.
	★ 파티클은 Rate 0 + Emit(n). 동시 살아 있는 입자 ≤ 120(졸업식 ≤ 200). 예산을 넘는 요청은 깎는다.
	★ 모듈 최상위 부작용 없음. Start() 에서 ScreenGui·폴더를 만든다.
]]

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local Types = require(ReplicatedStorage.Shared.Types)

-- 계획 §3.4 계약(형제 컨트롤러). 형태만 선언하고 any 로 받는다
type HudApi = {
	profile: () -> Types.Profile?,
	onProfile: (fn: (Types.Profile) -> ()) -> (),
	toast: (text: string) -> (),
	banner: (text: string) -> (),
	hold: (on: boolean) -> (),
}
type CameraApi = {
	shake: (trauma: number) -> (),
	fovPunch: () -> (),
	orbit: (center: Vector3, radius: number, pitchDeg: number, seconds: number) -> (),
	cutTo: (cframe: CFrame) -> (),
	restore: () -> (),
}
type TransitionApi = {
	fadeTo: (alpha: number, seconds: number) -> (),
}
type SoundApi = {
	play: (key: string, pitch: number?) -> (), -- pitch 두 번째 인자는 계약 밖(SoundController 가 받는다)
}
type PadApi = {
	myPlot: () -> number?,
	plotModel: (plotId: number) -> Model?,
	padPosition: (facilityId: string) -> Vector3?,
	stickerPosition: (stickerId: any) -> Vector3?,
	facilityPosition: (plotId: number, facilityId: string) -> Vector3?,
	hintShortfall: () -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local CameraController = (require(script.Parent.CameraController) :: any) :: CameraApi
local TransitionController = (require(script.Parent.TransitionController) :: any) :: TransitionApi
local SoundController = (require(script.Parent.SoundController) :: any) :: SoundApi
local PadController = (require(script.Parent.PadController) :: any) :: PadApi
-- StudentRenderController.ceremony(plotId, on)·isLowSpec() 은 계약 밖이라 any 로 받는다
local StudentRenderController = require(script.Parent.StudentRenderController) :: any

local FeedbackController = {}

-- 효과음 키(기획서 §9.6, SoundConfig.DEFS)
local SOUND_TICK = "tick"
local SOUND_GOLD = "goldPop"
local SOUND_PAD = "pad"
local SOUND_ARRIVE = "arrive"
local SOUND_BELL = "bell"
local SOUND_BUILD = "build" -- 도장 소리도 이걸 쓴다
local SOUND_FANFARE = "fanfare"
local SOUND_LEGEND = "legend"
local SOUND_GRADUATION = "graduation"
local SOUND_COMBO = "combo"
local SOUND_TICKET = "ticket"
local SOUND_DOOR = "door_open"
local SOUND_SIT = "sit"

-- 등급(Types.Tier)
local TIER_NORMAL: Types.Tier = "평범"
local TIER_CAPTAIN: Types.Tier = "반장"
local TIER_TOP: Types.Tier = "전교1등"
local TIER_LEGEND: Types.Tier = "전설"

-- 별 파트 이름 접두(PlotShell "Star%02d"). 별은 StickerCollected 로 오되 value 0 이다
local STAR_PREFIX = "Star"

-- 색(기획서 §8.1)
local COLOR_PANEL = Color3.fromRGB(31, 41, 55)
local COLOR_YELLOW = Color3.fromRGB(251, 191, 36)
local COLOR_GREEN = Color3.fromRGB(52, 211, 153)
local COLOR_BLUE = Color3.fromRGB(96, 165, 250)
local COLOR_PURPLE = Color3.fromRGB(167, 139, 250)
local COLOR_GOLD = Color3.fromRGB(245, 158, 11)
local COLOR_WHITE = Color3.new(1, 1, 1)
local COLOR_DUST = Color3.fromRGB(226, 220, 205)
local COLOR_CAP = Color3.fromRGB(30, 30, 40)

-- 수치(기획서 §9). 클라 전용 연출 수치라 공용 Config 에 없다
local TRAUMA_GOLD = 0.15
local TRAUMA_PURCHASE = 0.30
local TRAUMA_LEGEND = 0.45
local TRAUMA_GRADUATION = 0.60
local HITSTOP_SECONDS = 0.15
local FLASH_ALPHA = 0.7
local FLASH_SECONDS = 0.08
local FLASH_INTERVAL = 1
local PARTICLE_BUDGET = 120
local PARTICLE_BUDGET_LOW = 80 -- 저사양 다이얼(§12.1)
local PARTICLE_BUDGET_CEREMONY = 200
local COMBO_TOAST_EVERY = 5
local DENY_PITCH = 0.9
local POPUP_RISE = 3 -- 스터드
local POPUP_SECONDS = 0.6
local CARD_IN = 0.25
local CARD_HOLD = 2.0
local CARD_OUT = 0.2
local STAMP_IN = 0.25
local STAMP_FROM = 1.3
local STAR_HIDE_SECONDS = 60
local POP_SECONDS = 0.12
local ORBIT_RADIUS = 24
local ORBIT_PITCH = 30
local ORBIT_SECONDS = 4
local CLASSROOM_CAMERA = Vector3.new(0, 17.5, 27.5) -- 교실1 을 내려다보는 카메라 오프셋(부지 로컬)
-- 부품 하나(PartBuilt): 부품 번호 1..4 → build 음정. 한 시설 안에서 올라가다 마지막에 완공 연출로 끝난다
local PART_PITCH = { 1.0, 1.12, 1.26, 1.41 }
local PART_DUST = 6

type Preset = {
	color: ColorSequence,
	size: NumberSequence,
	speed: NumberRange,
	lifetime: NumberRange,
	spread: Vector2,
	gravity: number,
	light: number,
}

local function preset(
	color: ColorSequence,
	sizeFrom: number,
	speedLo: number,
	speedHi: number,
	life: number,
	gravity: number,
	light: number
): Preset
	return {
		color = color,
		size = NumberSequence.new(sizeFrom, 0),
		speed = NumberRange.new(speedLo, speedHi),
		lifetime = NumberRange.new(life * 0.7, life),
		spread = Vector2.new(180, 180),
		gravity = gravity,
		light = light,
	}
end

local PRESET_STAR = preset(ColorSequence.new(COLOR_YELLOW), 0.6, 8, 14, 0.9, -8, 1)
local PRESET_GOLD = preset(ColorSequence.new(COLOR_GOLD, COLOR_YELLOW), 0.8, 10, 18, 1.1, -8, 1)
local PRESET_DUST = preset(ColorSequence.new(COLOR_DUST), 1.4, 3, 6, 0.8, 0, 0)
local PRESET_SPARKLE = preset(ColorSequence.new(COLOR_WHITE, COLOR_PURPLE), 0.5, 6, 12, 0.9, -2, 1)
local PRESET_PILLAR = preset(ColorSequence.new(COLOR_GOLD, COLOR_WHITE), 0.7, 14, 22, 1.4, 4, 1)
local PRESET_CONFETTI = preset(
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOR_GREEN),
		ColorSequenceKeypoint.new(0.5, COLOR_YELLOW),
		ColorSequenceKeypoint.new(1, COLOR_BLUE),
	}),
	0.7,
	14,
	24,
	2.2,
	-12,
	0
)
local PRESET_CAP = preset(ColorSequence.new(COLOR_CAP), 0.9, 18, 26, 2.4, -10, 0)

local player = Players.LocalPlayer
local started = false
local shakeEnabled = true
local hapticEnabled = true
local ceremonyActive = false
local screenGui: ScreenGui? = nil
local flashFrame: Frame? = nil
local popupFolder: Folder? = nil -- PlayerGui 아래, 「+N」 빌보드
local fxFolder: Folder? = nil -- Workspace 아래, 파티클 임시 파트
local lastFlash = -math.huge
local lastBoardCells = -1
local cardToken = 0
local currentCard: Frame? = nil
local hapticEffects: { [string]: HapticEffect } = {}
local liveParticles: { { expires: number, count: number } } = {}

-- ── 저수준 헬퍼 ──────────────────────────────────────────────────

local function rootPart(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function rootPosition(): Vector3?
	local root = rootPart()
	return if root then root.Position else nil
end

local function sound(key: string, pitch: number?)
	SoundController.play(key, pitch)
end

--- 햅틱 3단. HapticEffect 가 없는 클라이언트(구 버전)면 게임패드 모터로, 그것도 없으면 조용히 넘어간다
local HAPTIC_TYPES: { [string]: Enum.HapticEffectType } = {
	small = Enum.HapticEffectType.UIClick,
	medium = Enum.HapticEffectType.GameplayCollision,
	large = Enum.HapticEffectType.GameplayExplosion,
}
local HAPTIC_MOTOR: { [string]: number } = { small = 0.3, medium = 0.6, large = 1 }

local function haptic(strength: "small" | "medium" | "large")
	if not hapticEnabled then
		return
	end
	local ok = pcall(function()
		local effect = hapticEffects[strength]
		if not effect then
			local created = Instance.new("HapticEffect")
			created.Type = HAPTIC_TYPES[strength]
			created.Parent = fxFolder
			hapticEffects[strength] = created
			effect = created
		end
		effect:Play()
	end)
	if ok then
		return
	end
	pcall(function()
		if HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, HAPTIC_MOTOR[strength])
			task.delay(0.1, function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
			end)
		end
	end)
end

--- 흰 플래시. α 0.7 · 0.08초 · 초당 1회를 넘지 않는다. 흔들림 끔이면 없음
local function flash()
	local frame = flashFrame
	if not frame or not shakeEnabled then
		return
	end
	local now = os.clock()
	if now - lastFlash < FLASH_INTERVAL then
		return
	end
	lastFlash = now
	frame.BackgroundTransparency = 1 - FLASH_ALPHA
	TweenService:Create(frame, TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 })
		:Play()
end

--- 히트스톱: 카메라를 현재 프레임에 고정했다가 푼다. 월드는 그대로. 졸업식 오빗 중엔 카메라를 건드리지 않는다
local function hitstop(seconds: number)
	if not shakeEnabled or ceremonyActive then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	CameraController.cutTo(camera.CFrame)
	task.delay(seconds, function()
		CameraController.restore()
	end)
end

local function shake(trauma: number)
	if shakeEnabled then
		CameraController.shake(trauma)
	end
end

local function liveParticleCount(now: number): number
	local total = 0
	for i = #liveParticles, 1, -1 do
		local entry = liveParticles[i]
		if entry.expires <= now then
			table.remove(liveParticles, i)
		else
			total += entry.count
		end
	end
	return total
end

--- 임시 파트에 파티클 하나 달아 count 개만 뿜고 치운다(Rate 0 + Emit). 예산을 넘는 만큼 깎는다
local function burst(position: Vector3, style: Preset, count: number)
	local now = os.clock()
	local cap = if ceremonyActive
		then PARTICLE_BUDGET_CEREMONY
		elseif StudentRenderController.isLowSpec() then PARTICLE_BUDGET_LOW
		else PARTICLE_BUDGET
	local allowed = math.min(count, cap - liveParticleCount(now))
	if allowed <= 0 then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "Burst"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = style.color
	emitter.Size = style.size
	emitter.Speed = style.speed
	emitter.Lifetime = style.lifetime
	emitter.SpreadAngle = style.spread
	emitter.Acceleration = Vector3.new(0, style.gravity, 0)
	emitter.LightEmission = style.light
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Parent = holder
	holder.Parent = fxFolder
	emitter:Emit(allowed)
	local ttl = style.lifetime.Max
	table.insert(liveParticles, { expires = now + ttl, count = allowed })
	task.delay(ttl + 0.1, function()
		holder:Destroy()
	end)
end

--- 「+N」 팝업: 머리 위 3 스터드에서 0.6초 떠오르며 사라진다
local function popup(text: string, color: Color3)
	local root = rootPart()
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Popup"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(220, 56)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	local x = (math.random() - 0.5) * 2
	gui.StudsOffsetWorldSpace = Vector3.new(x, POPUP_RISE, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 32
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	gui.Parent = popupFolder
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	local rise = TweenInfo.new(POPUP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffsetWorldSpace = Vector3.new(x, POPUP_RISE * 2, 0) }):Play()
	local fade = TweenInfo.new(
		POPUP_SECONDS * 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		POPUP_SECONDS * 0.5
	)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(POPUP_SECONDS + 0.1, function()
		gui:Destroy()
	end)
end

--- 도장: 화면 위쪽 큰 글자가 1.3 → 1.0 으로 찍힌다
local function stamp(text: string, color: Color3, hold: number)
	local parent = screenGui
	if not parent then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "Stamp"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.fromOffset(400, 90)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 56
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	local scale = Instance.new("UIScale")
	scale.Scale = STAMP_FROM
	scale.Parent = label
	label.Parent = parent
	TweenService:Create(scale, TweenInfo.new(STAMP_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(hold, function()
		local out = TweenInfo.new(CARD_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, out, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(CARD_OUT, function()
			label:Destroy()
		end)
	end)
end

--- 도감 카드 얼굴. 원형이 없거나 실패하면 조용히 글자만 남긴다
local function attachFace(parent: Frame, studentId: string)
	task.spawn(function()
		pcall(function()
			local config = CharacterBuilder.studentConfig(studentId)
			config.sitting = false
			local model = CharacterBuilder.build("CardFace", CFrame.new(), config)
			if not model or not parent.Parent then
				return
			end
			local viewport = Instance.new("ViewportFrame")
			viewport.Size = UDim2.fromOffset(120, 120)
			viewport.Position = UDim2.new(0.5, 0, 0, 12)
			viewport.AnchorPoint = Vector2.new(0.5, 0)
			viewport.BackgroundTransparency = 1
			viewport.Ambient = COLOR_WHITE
			viewport.LightColor = COLOR_WHITE
			local world = Instance.new("WorldModel")
			world.Parent = viewport
			model.Parent = world
			local size = model:GetExtentsSize()
			local head = model:GetPivot().Position + Vector3.new(0, size.Y * 0.78, 0)
			local camera = Instance.new("Camera")
			camera.FieldOfView = 40
			camera.CFrame = CFrame.lookAt(head + Vector3.new(0, 0.2, -size.Y * 0.9), head)
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			viewport.Parent = parent
		end)
	end)
end

--- 가운데 카드: Back Out 0.25초 등장 → hold → Quad In 0.2초 퇴장. 새 카드가 오면 앞 카드는 바로 치운다
local function card(title: string, subtitle: string, color: Color3, strokePx: number, hold: number, studentId: string?)
	local parent = screenGui
	if not parent then
		return
	end
	cardToken += 1
	local mine = cardToken
	if currentCard then
		currentCard:Destroy()
		currentCard = nil
	end
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.42)
	frame.Size = UDim2.fromOffset(280, if studentId then 240 else 150)
	frame.BackgroundColor3 = COLOR_PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = strokePx
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.AnchorPoint = Vector2.new(0.5, 1)
	titleLabel.Position = UDim2.new(0.5, 0, 1, -56)
	titleLabel.Size = UDim2.new(1, -24, 0, 44)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 32
	titleLabel.TextColor3 = COLOR_WHITE
	titleLabel.Text = title
	titleLabel.Parent = frame
	local subLabel = Instance.new("TextLabel")
	subLabel.AnchorPoint = Vector2.new(0.5, 1)
	subLabel.Position = UDim2.new(0.5, 0, 1, -16)
	subLabel.Size = UDim2.new(1, -24, 0, 34)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 22
	subLabel.TextColor3 = color
	subLabel.Text = subtitle
	subLabel.Parent = frame

	frame.Parent = parent
	currentCard = frame
	if studentId then
		attachFace(frame, studentId)
	end
	TweenService:Create(scale, TweenInfo.new(CARD_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(CARD_IN + hold, function()
		if cardToken ~= mine or currentCard ~= frame then
			return
		end
		local out = TweenInfo.new(CARD_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(scale, out, { Scale = 0.8 }):Play()
		TweenService:Create(frame, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		for _, child in frame:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, out, { TextTransparency = 1 }):Play()
			elseif child:IsA("ViewportFrame") then
				TweenService:Create(child, out, { ImageTransparency = 1 }):Play()
			end
		end
		task.delay(CARD_OUT, function()
			if currentCard == frame then
				currentCard = nil
			end
			frame:Destroy()
		end)
	end)
end

--- 학생이 앉을 자리(내 부지). 좌석 Attachment 가 아직 안 왔으면 시설 피벗
local function seatPosition(plotId: number, studentId: string): Vector3?
	local profile = HudController.profile()
	local built = if profile then profile.facilities else {}
	local seat = Seats.seatOf(studentId, built)
	if not seat then
		return nil
	end
	local model = PadController.plotModel(plotId)
	local facility = if model then model:FindFirstChild(seat.facilityId) else nil
	local seats = if facility then facility:FindFirstChild(Keys.SEATS_FOLDER) else nil
	local at = if seats then seats:FindFirstChild(Seats.attachmentName(seat.index)) else nil
	if at and at:IsA("Attachment") then
		return at.WorldPosition
	end
	return PadController.facilityPosition(plotId, seat.facilityId)
end

local function tierStyle(tier: Types.Tier): { color: Color3, stroke: number }
	return StudentConfig.TIER_STYLE[tier] or StudentConfig.TIER_STYLE[TIER_NORMAL]
end

--- 그 부지 Stars 폴더에서 이름으로 별 파트를 찾는다(별 이름은 부지마다 같다)
local function findStar(plotId: number, name: string): BasePart?
	local plots = Workspace:FindFirstChild(Keys.PLOTS_FOLDER)
	local plot = if plots then plots:FindFirstChild(Keys.plotName(plotId)) else nil
	local stars = if plot then plot:FindFirstChild(Keys.STARS_FOLDER) else nil
	local star = if stars then stars:FindFirstChild(name) else nil
	if star and star:IsA("BasePart") then
		return star
	end
	return nil
end

-- ── kind 별 타임라인(§9.2) ───────────────────────────────────────

local handlers: { [string]: (payload: any) -> () } = {}

--- 스티커 뒤 공통: 콤보 5마다 토스트, 스티커판이 한 바퀴 돌면 원서
local function afterSticker(payload: any)
	local combo = if type(payload.combo) == "number" then payload.combo else 0
	if combo > 0 and combo % COMBO_TOAST_EVERY == 0 then
		handlers.combo(payload)
	end
	local cells = if type(payload.boardCells) == "number" then payload.boardCells else -1
	if lastBoardCells >= 0 and cells >= 0 and cells < lastBoardCells then
		handlers.ticket(payload)
	end
	lastBoardCells = cells
end

-- 하늘색 별(방문객): 팝 + 틱, 그 별을 60초 동안 나한테만 숨긴다
handlers.star = function(payload: any)
	local name = tostring(payload.stickerId)
	local star = if type(payload.plot) == "number" then findStar(payload.plot, name) else nil
	local position = if star then star.Position else rootPosition()
	if position then
		burst(position, PRESET_SPARKLE, 6)
	end
	sound(SOUND_TICK, 1.2)
	haptic("small")
	if not star then
		return
	end
	local ghost = star:Clone()
	ghost:ClearAllChildren()
	ghost.Name = "StarGhost"
	ghost.CanTouch = false
	ghost.CanQuery = false
	ghost.Parent = fxFolder
	star.LocalTransparencyModifier = 1
	local grow = TweenService:Create(
		ghost,
		TweenInfo.new(POP_SECONDS * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = star.Size * 1.4 }
	)
	grow.Completed:Once(function()
		local shrink = TweenService:Create(
			ghost,
			TweenInfo.new(POP_SECONDS * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }
		)
		shrink.Completed:Once(function()
			ghost:Destroy()
		end)
		shrink:Play()
	end)
	grow:Play()
	task.delay(STAR_HIDE_SECONDS, function()
		star.LocalTransparencyModifier = 0
	end)
end

-- 금 스티커: 1 → 1.8 → 0(PadController 가 예측 때 팝), 파티클 12 + 퍼지는 링, goldPop, 트라우마 0.15, 「×5!」
handlers.gold = function(payload: any)
	local position = PadController.stickerPosition(payload.stickerId) or rootPosition()
	if position then
		burst(position, PRESET_GOLD, 12)
		local ring = Instance.new("Part")
		ring.Name = "GoldRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, 1, 1)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Color = COLOR_GOLD
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Parent = fxFolder
		local spread = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(ring, spread, { Size = Vector3.new(0.2, 10, 10), Transparency = 1 }):Play()
		task.delay(0.5, function()
			ring:Destroy()
		end)
	end
	sound(SOUND_GOLD)
	shake(TRAUMA_GOLD)
	local value = if type(payload.value) == "number" then payload.value else 0
	popup(`×5! +{Format.coins(value)}`, COLOR_GOLD)
	haptic("medium")
	afterSticker(payload)
end

-- 스티커: 팝·소리(PadController 예측 시점), 별 파티클 8, 「+N」, 햅틱 소
handlers.sticker = function(payload: any)
	if payload.gold == true then
		handlers.gold(payload)
		return
	end
	local id = tostring(payload.stickerId)
	if payload.value == 0 and string.sub(id, 1, #STAR_PREFIX) == STAR_PREFIX then
		handlers.star(payload)
		return
	end
	local position = PadController.stickerPosition(payload.stickerId) or rootPosition()
	if position then
		burst(position, PRESET_STAR, 8)
	end
	local value = if type(payload.value) == "number" then payload.value else 0
	popup(`+{Format.coins(value)}`, COLOR_YELLOW)
	haptic("small")
	afterSticker(payload)
end

-- 콤보 5마다: 토스트 + combo 소리
handlers.combo = function(payload: any)
	local combo = if type(payload.combo) == "number" then payload.combo else 0
	HudController.toast(`콤보 {combo}!`)
	sound(SOUND_COMBO)
end

-- 스티커판 한 바퀴 = 원서 1장
handlers.ticket = function()
	HudController.toast("입학원서 +1!")
	sound(SOUND_TICKET)
	haptic("small")
end

-- 구매: 패드 가라앉음(PadController), build, FOV 65→59→65, 트라우마 0.30, 햅틱 중, 50ms 먼지 12, 1200ms 다음 패드 소리
handlers.purchase = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else PadController.myPlot()
	local facilityId = if type(payload.facilityId) == "string" then payload.facilityId else ""
	local mine = plotId ~= nil and plotId == PadController.myPlot()
	local position: Vector3? = nil
	if plotId then
		position = PadController.facilityPosition(plotId, facilityId)
	end
	if mine and not position then
		position = PadController.padPosition(facilityId)
	end
	if not mine then
		if position then
			burst(position, PRESET_DUST, 12)
		end
		return
	end
	sound(SOUND_BUILD)
	if shakeEnabled then
		CameraController.fovPunch()
	end
	shake(TRAUMA_PURCHASE)
	haptic("medium")
	task.delay(0.05, function()
		local dustAt = PadController.facilityPosition(plotId :: number, facilityId) or position
		if dustAt then
			burst(dustAt, PRESET_DUST, 12)
		end
	end)
	task.delay(1.2, function()
		sound(SOUND_PAD)
	end)
end

-- 부품: 주인 화면에서만 build 소리(부품 번호별 음정)·먼지 6·햅틱 약. 플래시·FOV·흔들림 없음(§7.5).
-- 마지막 부품은 FacilityBuilt(purchase) 가 바로 뒤따르므로 소리를 내지 않는다(이중 소리 방지)
handlers.part = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else nil
	if plotId == nil or plotId ~= PadController.myPlot() then
		return -- 방문객 화면은 아무것도 없음
	end
	local facilityId = if type(payload.facilityId) == "string" then payload.facilityId else ""
	local index = if type(payload.partIndex) == "number" then payload.partIndex else 1
	local count = if type(payload.partCount) == "number" then payload.partCount else index
	if index >= count then
		return -- 마지막 부품은 바로 뒤에 오는 FacilityBuilt(purchase)가 소리·햅틱·먼지를 맡는다
	end
	sound(SOUND_BUILD, PART_PITCH[index] or PART_PITCH[#PART_PITCH])
	haptic("small")
	-- 부품 파트가 복제될 틈을 준다(purchase 와 같은 50ms). 시설 모델이 아직 없으면 패드 자리에
	task.delay(0.05, function()
		local dustAt = PadController.facilityPosition(plotId, facilityId) or PadController.padPosition(facilityId)
		if dustAt then
			burst(dustAt, PRESET_DUST, PART_DUST)
		end
	end)
end

-- 전학생: door_open → 3.0초 걷기(StudentRender) → 착석 먼지 4 + sit → 3.5초 arrive + 도감 카드 + 등급 추가 연출
handlers.student = function(payload: any)
	if payload.walk ~= true then
		return -- 남의 부지·복원 착석은 연출 없음
	end
	local plotId = if type(payload.plot) == "number" then payload.plot else PadController.myPlot()
	if plotId ~= PadController.myPlot() then
		return -- 서버는 walk 를 전체에 보낸다. 카드·소리는 주인 화면에서만(§11.5)
	end
	local studentId = if type(payload.studentId) == "string" then payload.studentId else ""
	local row = StudentConfig.BY_ID[studentId]
	if not plotId or not row then
		return
	end
	sound(SOUND_DOOR)
	task.delay(3.0, function()
		local at = seatPosition(plotId, studentId)
		if at then
			burst(at, PRESET_DUST, 4)
		end
		sound(SOUND_SIT)
	end)
	task.delay(3.5, function()
		sound(SOUND_ARRIVE)
		local style = tierStyle(row.tier)
		card(row.name, `{row.tier} 전학생`, style.color, style.stroke, CARD_HOLD, studentId)
		haptic("medium")
		local at = seatPosition(plotId, studentId)
		if row.tier == TIER_CAPTAIN then
			if at then
				burst(at + Vector3.new(0, 4, 0), PRESET_CONFETTI, 20)
			end
		elseif row.tier == TIER_TOP then
			sound(SOUND_FANFARE)
		elseif row.tier == TIER_LEGEND then
			hitstop(HITSTOP_SECONDS)
			flash()
			if at then
				burst(at, PRESET_PILLAR, 30)
			end
			sound(SOUND_LEGEND)
			haptic("large")
		end
	end)
end

-- 뽑기 결과 공개 순간(패널이 타이밍을 정한다): 등급 소리, 전설은 파티클 40 + 플래시 + 트라우마 0.45
handlers.gacha = function(payload: any)
	local tier = payload.tier
	local position = rootPosition()
	if tier == TIER_LEGEND then
		hitstop(HITSTOP_SECONDS)
		flash()
		shake(TRAUMA_LEGEND)
		if position then
			burst(position + Vector3.new(0, 2, 0), PRESET_PILLAR, 40)
		end
		sound(SOUND_LEGEND)
		haptic("large")
	elseif tier == TIER_TOP then
		if position then
			burst(position + Vector3.new(0, 3, 0), PRESET_CONFETTI, 20)
		end
		sound(SOUND_FANFARE)
		haptic("medium")
	elseif tier == TIER_CAPTAIN then
		if position then
			burst(position + Vector3.new(0, 3, 0), PRESET_SPARKLE, 12)
		end
		sound(SOUND_ARRIVE)
		haptic("medium")
	else
		sound(SOUND_TICK)
		haptic("small")
	end
end

-- 중복: 「×n」 도장 0.2초 + 도장 소리. 미니 게이지는 패널 카드 안(PanelController)
handlers.dupe = function(payload: any)
	local count = if type(payload.dupeCount) == "number" then payload.dupeCount else 2
	stamp(`×{count}`, COLOR_PURPLE, 0.8)
	sound(SOUND_BUILD)
	haptic("small")
end

-- 부족: 링 밝힘 + 실루엣 깜빡임(PadController) + 낮은 틱. 글자·빨강·흔들림 없음. 나머지 이유는 로그용
handlers.deny = function(payload: any)
	if payload.reason == "coins" then
		PadController.hintShortfall()
		sound(SOUND_TICK, DENY_PITCH)
	end
end

-- 미션 완료: 배너 4초 + ticket 소리 + 햅틱 소. 원서 칩 펀치는 HUD
handlers.mission = function()
	HudController.banner("미션 완료! 원서 +1")
	sound(SOUND_TICKET)
	haptic("small")
end

--- 졸업식 §9.5. 12초. 입력 잠금은 서버 graduating 플래그가 맡는다
local function ceremony(payload: any)
	local plotId = payload.plot :: number
	local graduations = if type(payload.graduations) == "number" then payload.graduations else 0
	local newStudentId = if type(payload.newStudentId) == "string" then payload.newStudentId else nil
	local auditoriumId = FacilityConfig.ORDER[FacilityConfig.COUNT]
	local classroomId = FacilityConfig.ORDER[1]
	ceremonyActive = true
	-- 바로 뒤에 오는 ProfileSync(졸업 후 프로필)를 9.0초까지 그리지 않게, spawn 전에 잡는다
	HudController.hold(true)
	task.spawn(function()
		-- 0.0 검정 0.5초 + 종. 학생들은 강당 좌석으로(StudentRender)
		TransitionController.fadeTo(1, 0.5)
		sound(SOUND_BELL)
		pcall(function()
			StudentRenderController.ceremony(plotId, true)
		end)
		task.wait(0.5)

		-- 0.5 강당 단상 오빗 4초, graduation 음악
		local plot = PadController.plotModel(plotId)
		local center = PadController.facilityPosition(plotId, auditoriumId)
			or (if plot then plot:GetPivot().Position else rootPosition())
			or Vector3.zero
		CameraController.orbit(center, ORBIT_RADIUS, ORBIT_PITCH, ORBIT_SECONDS)
		TransitionController.fadeTo(0, 0.4)
		sound(SOUND_GRADUATION)
		task.wait(2.5)

		-- 3.0 학사모 60 + 색종이 100 + 히트스톱(오빗 중이라 플래시만) + 트라우마 0.60 + 햅틱 대
		burst(center + Vector3.new(0, 6, 0), PRESET_CAP, 60)
		burst(center + Vector3.new(0, 8, 0), PRESET_CONFETTI, 100)
		hitstop(HITSTOP_SECONDS)
		flash()
		shake(TRAUMA_GRADUATION)
		haptic("large")
		task.wait(1.5)

		-- 4.5 「졸업 N회!」 도장
		stamp(`졸업 {graduations}회!`, COLOR_GOLD, 1.3)
		sound(SOUND_BUILD)
		task.wait(1.5)

		-- 6.0 「이제 새 친구가 와요」 카드
		local newRow = if newStudentId then StudentConfig.BY_ID[newStudentId] else nil
		if newRow then
			local style = tierStyle(newRow.tier)
			card("이제 새 친구가 와요", newRow.name, style.color, style.stroke, 1.2, newStudentId)
		else
			card("이제 새 친구가 와요", "???", COLOR_PURPLE, 3, 1.2, nil)
		end
		task.wait(1.5)

		-- 7.5 검정 0.5초. 8.0 서버가 부지를 초기화한다
		TransitionController.fadeTo(1, 0.5)
		task.wait(1.5)

		-- 9.0 교실1 컷 + 「친구들은 그대로!」
		pcall(function()
			StudentRenderController.ceremony(plotId, false)
		end)
		local classroom = PadController.facilityPosition(plotId, classroomId)
		local pivot = if plot then plot:GetPivot() else CFrame.new(center)
		local lookAt = classroom or pivot.Position
		local eye = lookAt + pivot.Rotation:VectorToWorldSpace(CLASSROOM_CAMERA)
		CameraController.cutTo(CFrame.lookAt(eye, lookAt))
		TransitionController.fadeTo(0, 0.3)
		HudController.hold(false) -- 용돈 14 롤·배율 펀치·「책상 세트」 카드
		card("친구들은 그대로!", "학교는 새로 시작해요", COLOR_GREEN, 3, 1.5, nil)
		task.wait(1.5)

		-- 10.5 책상 패드 링 펄스 + 앞마당 스티커 반짝
		PadController.hintShortfall()
		for i = 1, 3 do
			local at = PadController.stickerPosition(i)
			if at then
				burst(at, PRESET_STAR, 6)
			end
		end
		task.wait(1.5)

		-- 12.0 끝. 카메라 복귀
		CameraController.restore()
		ceremonyActive = false
	end)
end

-- 졸업: 내 부지면 졸업식, 남의 부지면 그 강당 위 색종이·학사모만
handlers.graduated = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else nil
	if not plotId then
		return
	end
	if plotId == PadController.myPlot() then
		if not ceremonyActive then
			ceremony(payload)
		end
		return
	end
	local auditoriumId = FacilityConfig.ORDER[FacilityConfig.COUNT]
	local plot = PadController.plotModel(plotId)
	local center = PadController.facilityPosition(plotId, auditoriumId)
		or (if plot then plot:GetPivot().Position else nil)
	if center then
		burst(center + Vector3.new(0, 8, 0), PRESET_CONFETTI, 40)
		burst(center + Vector3.new(0, 6, 0), PRESET_CAP, 20)
	end
end

-- ── 공개 API ─────────────────────────────────────────────────────

function FeedbackController.Start()
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "Feedback"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	screenGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = COLOR_WHITE
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 10
	frame.Parent = gui
	flashFrame = frame

	local popups = Instance.new("Folder")
	popups.Name = "FeedbackPopups"
	popups.Parent = playerGui
	popupFolder = popups

	local fx = Instance.new("Folder")
	fx.Name = "FeedbackFx"
	fx.Parent = Workspace
	fxFolder = fx

	HudController.onProfile(function(profile)
		local settings = profile.settings
		if type(settings) == "table" then
			shakeEnabled = settings.shake ~= false
			hapticEnabled = settings.haptic ~= false
		end
	end)
end

--- §9.2 표의 kind. 모르는 kind 는 조용히 무시한다
function FeedbackController.play(kind: string, payload: any?)
	local handler = handlers[kind]
	if handler then
		handler(payload or {})
	end
end

function FeedbackController.setHapticEnabled(enabled: boolean)
	hapticEnabled = enabled
end

--- 「흔들림 끔」: 트라우마·FOV 펀치·플래시·히트스톱을 모두 끈다
function FeedbackController.setShakeEnabled(enabled: boolean)
	shakeEnabled = enabled
end

return FeedbackController
