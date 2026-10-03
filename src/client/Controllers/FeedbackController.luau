--!strict
--[[
	FeedbackController — 손맛(기획서 §9)

	이벤트 하나에 작은 반응 5~8개를 100ms 안에 겹쳐 쏜다: 소리·파티클·흔들림·플래시·「+N」·햅틱.
	play(kind, payload) 하나로 받고 kind 별 타임라인(§9.2)을 그대로 따른다. 층 완공 축하는 개선계획 §5.5 의 4초 오빗.

	★ 부정 피드백은 없다(§9.1). 「부족」은 링 밝힘 + 실루엣 깜빡임 + 낮은 틱뿐이고 글자·빨강·흔들림이 없다.
	★ 카메라는 CameraController 가 굴린다(트라우마 모델). 여기서는 shake(t)·fovPunch()·orbit·cutTo·restore 만 부른다.
	★ 히트스톱은 카메라·UI 만 잠깐 멈춘다(cutTo 로 현재 프레임에 고정 → restore). 월드는 멈추지 않는다.
	★ 플래시 한도(§8.4): α ≤ 0.7, ≤ 0.08초, 초당 1회. 설정 「흔들림 끔」이면 흔들림·FOV·플래시·히트스톱을 모두 끈다.
	★ 파티클은 Rate 0 + Emit(n). 동시 살아 있는 입자 ≤ 120. 예산을 넘는 요청은 깎는다.
	★ 모듈 최상위 부작용 없음. Start() 에서 ScreenGui·폴더를 만든다.
	★ 완공 지붕 아이콘(W8, 개선계획 §3.1 #8): FacilityBuilt 가 내 부지일 때만 그 시설 모델 윗면 위에 ★ 빌보드 하나가
	  ROOF_ICON_SECONDS 동안 떠올랐다 사라진다. 파트·파티클 없음, 흔들림·빨강 없음. 방문객 화면에는 없다(§7.5).
]]

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local Format = require(ReplicatedStorage.Shared.Format)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local MissionConfig = require(ReplicatedStorage.Shared.Config.MissionConfig)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
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
	towerBurst: () -> (),
}
local HudController = (require(script.Parent.HudController) :: any) :: HudApi
local CameraController = (require(script.Parent.CameraController) :: any) :: CameraApi
local SoundController = (require(script.Parent.SoundController) :: any) :: SoundApi
local PadController = (require(script.Parent.PadController) :: any) :: PadApi
-- StudentRenderController.isLowSpec() 은 계약 밖이라 any 로 받는다
local StudentRenderController = require(script.Parent.StudentRenderController) :: any

local FeedbackController = {}

-- 효과음 키(기획서 §9.6, SoundConfig.DEFS)
local SOUND_TICK = "tick"
local SOUND_GOLD = "goldPop"
local SOUND_PAD = "pad"
local SOUND_BUILD = "build" -- 도장 소리도 이걸 쓴다
local SOUND_FANFARE = "fanfare"
local SOUND_LEGEND = "legend"
local SOUND_CELEBRATE = "celebrate"
local SOUND_COMBO = "combo"
local SOUND_REWARD = "reward"
local SOUND_PLACE = "place"

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

-- 수치(기획서 §9). 클라 전용 연출 수치라 공용 Config 에 없다
local TRAUMA_GOLD = 0.15
local TRAUMA_PURCHASE = 0.30
local HITSTOP_SECONDS = 0.15
-- 전학 「짠」(StudentRender POP_SECONDS 0.45)이 끝나 자리 잡는 때와 도감 카드가 뜨는 때
local ARRIVE_SETTLE_SECONDS = 0.45
local ARRIVE_CARD_SECONDS = 0.9
local FLASH_ALPHA = 0.7
local FLASH_SECONDS = 0.08
local FLASH_INTERVAL = 1
local PARTICLE_BUDGET = 120
local PARTICLE_BUDGET_LOW = 80 -- 저사양 다이얼(§12.1)
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
-- 층 완공 축하(개선계획 §5.5). 학교 높이에 맞춰 물러나 한 바퀴 돈다. 좌표는 부지 로컬(PlotLayout)
local CELEBRATE_SECONDS = 4
local CELEBRATE_PITCH = 20
local CELEBRATE_RADIUS = 60 -- 높이 0 일 때 거리. 높이 1 스터드마다 CELEBRATE_RADIUS_PER_Y 만큼 더 물러난다
local CELEBRATE_RADIUS_PER_Y = 1.2
local CELEBRATE_ROOF_LIFT = PlotLayout.FLOOR_STEP * 0.5 -- 옥상 방 축하: 옥상 바닥 위 이만큼을 가까이(CELEBRATE_RADIUS) 돈다
local TOWER_BASE_Y = PlotLayout.TOWER_BASE_Y
local FLOOR_STEP = PlotLayout.FLOOR_STEP
local TOWER_CENTER_Z = (PlotLayout.TOWER_FOOTPRINT.z0 + PlotLayout.TOWER_FOOTPRINT.z1) / 2
-- 부품 하나(PartBuilt): 부품 번호 1..4 → build 음정. 한 시설 안에서 올라가다 마지막에 완공 연출로 끝난다
local PART_PITCH = { 1.0, 1.12, 1.26, 1.41 }
local PART_DUST = 6
-- 완공 지붕 아이콘(W8)
local ROOF_ICON_GLYPH = "★"
local ROOF_ICON_SECONDS = 2 -- 떠올랐다 사라지는 전체 시간
local ROOF_ICON_LIFT = 3 -- 모델 윗면에서 처음 높이(스터드)
local ROOF_ICON_RISE = 3 -- 2초 동안 더 떠오르는 높이(스터드)
local ROOF_ICON_PX = 96
local ROOF_ICON_STROKE = 4
local ROOF_ICON_DELAY = 0.1 -- 마지막 부품 파트가 복제될 틈
local ROOF_ICON_WAIT = 1 -- 시설 모델이 스트리밍돼 들어오길 기다리는 상한(초). 넘으면 아이콘 없이 넘어간다

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

local player = Players.LocalPlayer
local started = false
local shakeEnabled = true
local hapticEnabled = true
local celebrating = false
local screenGui: ScreenGui? = nil
local flashFrame: Frame? = nil
local popupFolder: Folder? = nil -- PlayerGui 아래, 「+N」 빌보드
local fxFolder: Folder? = nil -- Workspace 아래, 파티클 임시 파트
local lastFlash = -math.huge
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

--- 히트스톱: 카메라를 현재 프레임에 고정했다가 푼다. 월드는 그대로. 축하 오빗 중엔 카메라를 건드리지 않는다
local function hitstop(seconds: number)
	if not shakeEnabled or celebrating then
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
	local cap = if StudentRenderController.isLowSpec() then PARTICLE_BUDGET_LOW else PARTICLE_BUDGET
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

--- 완공 지붕 아이콘: 시설 모델 바운딩 박스 윗면 위에 흰 ★(금 테두리)이 떠올랐다 사라진다. 파트를 만들지 않는다
local function roofIcon(plotId: number, facilityId: string)
	local plot = PadController.plotModel(plotId)
	-- 스트리밍으로 시설 모델이 늦게 들어올 수 있어 잠깐 기다린다(task.delay 안이라 yield 해도 된다)
	local model = if plot then plot:WaitForChild(facilityId, ROOF_ICON_WAIT) else nil
	if not model or not model:IsA("Model") or not popupFolder then
		return
	end
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end
	local box, size = model:GetBoundingBox()
	local top = box.Position + Vector3.new(0, size.Y / 2 + ROOF_ICON_LIFT, 0)
	local offset = top - anchor.Position

	local gui = Instance.new("BillboardGui")
	gui.Name = "RoofIcon"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(ROOF_ICON_PX, ROOF_ICON_PX)
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = COLOR_WHITE
	label.Text = ROOF_ICON_GLYPH
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_GOLD
	stroke.Thickness = ROOF_ICON_STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	gui.Parent = popupFolder

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	local rise = TweenInfo.new(ROOF_ICON_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffsetWorldSpace = offset + Vector3.new(0, ROOF_ICON_RISE, 0) }):Play()
	-- 뒤 절반 동안 사라진다
	local fade = TweenInfo.new(
		ROOF_ICON_SECONDS * 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		ROOF_ICON_SECONDS * 0.5
	)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(ROOF_ICON_SECONDS + 0.1, function()
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

--- 스티커 뒤 공통: 콤보 5마다 토스트. 판이 찬 순간은 GiftOpened(handlers.gift)가 따로 온다
local function afterSticker(payload: any)
	local combo = if type(payload.combo) == "number" then payload.combo else 0
	if combo > 0 and combo % COMBO_TOAST_EVERY == 0 then
		handlers.combo(payload)
	end
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

--- 바닥에서 납작한 네온 링이 퍼지며 사라진다(스티커·금 스티커)
local function spreadRing(position: Vector3, color: Color3, diameter: number)
	local ring = Instance.new("Part")
	ring.Name = "PickupRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = fxFolder
	local spread = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, spread, { Size = Vector3.new(0.2, diameter, diameter), Transparency = 1 }):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

-- 금 스티커: 1 → 1.8 → 0(PadController 가 예측 때 팝), 파티클 12 + 퍼지는 링, goldPop, 트라우마 0.15, 「×5!」
handlers.gold = function(payload: any)
	local position = PadController.stickerPosition(payload.stickerId) or rootPosition()
	if position then
		burst(position, PRESET_GOLD, 12)
		spreadRing(position, COLOR_GOLD, 10)
	end
	sound(SOUND_GOLD)
	shake(TRAUMA_GOLD)
	local value = if type(payload.value) == "number" then payload.value else 0
	popup(`×5! +{Format.coins(value)}`, COLOR_GOLD)
	haptic("medium")
	afterSticker(payload)
end

-- 스티커: 팝·소리(PadController 예측 시점), 별 파티클 12 + 노란 링, 「+N」, 햅틱 소.
-- 선물판 칩 펀치는 HudController 가 stickerBoard 가 오를 때 한다
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
		burst(position, PRESET_STAR, 12)
		spreadRing(position, COLOR_YELLOW, 6)
	end
	local value = if type(payload.value) == "number" then payload.value else 0
	popup(`+{Format.coins(value)}`, COLOR_YELLOW)
	haptic("small")
	afterSticker(payload)
end

-- 콤보 5마다: 토스트(⭐ + 숫자, 글보다 그림) + combo 소리
handlers.combo = function(payload: any)
	local combo = if type(payload.combo) == "number" then payload.combo else 0
	HudController.toast(`⭐ {combo}`)
	sound(SOUND_COMBO)
end

-- 스티커판 40칸 = 선물(GiftOpened, 본인에게만 온다). 🎁 가 열리고 날아가는 건 HUD(글자 없음)
handlers.gift = function(_payload: any)
	sound(SOUND_REWARD)
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
	-- 완공 지붕 아이콘. 여기는 주인 화면뿐이다(위 mine 판정)
	task.delay(ROOF_ICON_DELAY, function()
		roofIcon(plotId :: number, facilityId)
	end)
end

-- 부품: 주인 화면에서만 build 소리(부품 번호별 음정)·먼지 6·햅틱 약. 플래시·FOV·흔들림 없음(§7.5).
-- 마지막 부품은 FacilityBuilt(purchase) 가 바로 뒤따르므로 소리를 내지 않는다(이중 소리 방지)
handlers.part = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else nil
	if plotId == nil or plotId ~= PadController.myPlot() then
		return -- 방문객 화면은 아무것도 없음
	end
	-- FloorPart(층 부품)는 facilityId·partCount 가 없다. 탑 패드 자리·RoomConfig.PARTS 로 받는다
	local isFloor = type(payload.room) == "string"
	local facilityId = if isFloor
		then Keys.TOWER_PAD_ID
		elseif type(payload.facilityId) == "string" then payload.facilityId
		else ""
	local index = if type(payload.partIndex) == "number" then payload.partIndex else 1
	local count = if isFloor
		then RoomConfig.PARTS
		elseif type(payload.partCount) == "number" then payload.partCount
		else index
	if isFloor then
		PadController.towerBurst()
	end
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

-- 전학생: 제자리 「짠」(StudentRender 0.45초, arrive·sit 소리도 거기서) → 착석 먼지 4 → 0.9초 도감 카드 + 등급 추가 연출
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
	task.delay(ARRIVE_SETTLE_SECONDS, function()
		local at = seatPosition(plotId, studentId)
		if at then
			burst(at, PRESET_DUST, 4)
		end
	end)
	task.delay(ARRIVE_CARD_SECONDS, function()
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

-- 부족: 링 밝힘 + 실루엣 깜빡임(PadController) + 낮은 틱. 글자·빨강·흔들림 없음. 나머지 이유는 로그용
handlers.deny = function(payload: any)
	if payload.reason == "coins" then
		PadController.hintShortfall()
		sound(SOUND_TICK, DENY_PITCH)
	end
end

-- 미션 완료: 배너 4초 + reward 소리 + 햅틱 소
handlers.mission = function()
	HudController.banner(`미션 완료! 선물판 +{MissionConfig.REWARD_CELLS}칸`)
	sound(SOUND_REWARD)
	haptic("small")
end

--- 층 완공 축하(개선계획 §5.5). 약 4초. 카메라가 학교 중심을 한 바퀴 돌고 끝나면 원래 카메라로 돌아온다.
--- floors = 완공 층 수. 맨 위 지붕 y = TOWER_BASE_Y + floors × FLOOR_STEP(층 0 이면 강당 지붕)
local function celebrate(plotId: number, floor: number, floors: number, roomName: string)
	local plot = PadController.plotModel(plotId)
	if not plot then
		return
	end
	celebrating = true
	HudController.hold(true)
	-- 풀기를 먼저 예약한다. 아래 연출이 오류로 끊겨도(캐릭터 리스폰·카메라 없음 등) HUD 와 카메라는 4초 뒤 돌아온다
	task.delay(CELEBRATE_SECONDS, function()
		pcall(CameraController.restore)
		HudController.hold(false)
		celebrating = false
	end)
	-- top = 옥상 바닥(맨 위 지붕) y. 층 방은 학교 전체 높이에 맞춰 물러나고, 옥상 방(floor 0)은 옥상을 가까이 돈다
	local top = TOWER_BASE_Y + floors * FLOOR_STEP
	local roofRoom = floor == 0
	local pivot = plot:GetPivot()
	local centerY = if roofRoom then top + CELEBRATE_ROOF_LIFT else top * 0.5
	local radius = if roofRoom then CELEBRATE_RADIUS else CELEBRATE_RADIUS + top * CELEBRATE_RADIUS_PER_Y
	local center = pivot:PointToWorldSpace(Vector3.new(0, centerY, TOWER_CENTER_Z))
	local roof = pivot:PointToWorldSpace(Vector3.new(0, top + 4, TOWER_CENTER_Z))
	CameraController.orbit(center, radius, CELEBRATE_PITCH, CELEBRATE_SECONDS)
	sound(SOUND_CELEBRATE)
	burst(roof, PRESET_CONFETTI, 60)
	haptic("large")
	stamp(if roofRoom then `{roomName} 완공!` else `{floor}층 {roomName} 완공!`, COLOR_GOLD, CELEBRATE_SECONDS - 1)
end

-- 층 완공: 연출은 주인 화면에서만(§7.5). 남의 부지는 아무것도 없다
handlers.floorBuilt = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else nil
	if plotId == nil or plotId ~= PadController.myPlot() or celebrating then
		return
	end
	local floor = if type(payload.floor) == "number" then payload.floor else 0
	local floors = if type(payload.floors) == "number" then payload.floors else 0
	local room = if type(payload.room) == "string" then RoomConfig.BY_ID[payload.room] else nil
	celebrate(plotId, floor, floors, if room then room.name else "")
end

-- 「멋져요」를 받았다(주인에게만 온다): 짧은 토스트 + 긍정음. 방문객 화면에는 아무것도 없다(§7.5)
handlers.liked = function(payload: any)
	local plotId = if type(payload.plot) == "number" then payload.plot else nil
	if plotId == nil or plotId ~= PadController.myPlot() then
		return
	end
	local name = if type(payload.name) == "string" then payload.name else ""
	HudController.toast(`{name} 님이 멋져요를 보냈어요!`)
	sound(SOUND_REWARD)
	haptic("small")
end

-- 꾸미기 물건이 놓였다(DecorController 가 뿅 커지는 순간 부른다. 내 부지만). 「톡」 + 바닥 먼지 + 반짝
handlers.decorPlaced = function(payload: any)
	local position = if typeof(payload.position) == "Vector3" then payload.position else nil
	if not position then
		return
	end
	sound(SOUND_PLACE)
	burst(position, PRESET_DUST, 10)
	burst(position + Vector3.new(0, 2, 0), PRESET_SPARKLE, 8)
	haptic("small")
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
