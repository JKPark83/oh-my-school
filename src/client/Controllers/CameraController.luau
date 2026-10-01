--!strict
--[[
	카메라. 기획서 §9.1(흔들림)·§9.5·개선계획 §5.5(층 완공 축하 오빗)·§8.4(흔들림 끔).

	평소에는 로블록스 기본 카메라(Custom)를 그대로 쓴다. 줌 8~120, FOV 65.
	직접 CFrame 으로 굴리는 것은 연출 중(panTo/orbit/cutTo)뿐이고, restore() 로 Custom 에 돌아온다.
	꾸미기 모드의 lockPitch/unlockPitch 는 Custom 을 두고 피치만 매 프레임 덮어쓴다.

	★ 흔들림은 트라우마 모델이다. shake(t) 는 트라우마를 더하고, 실제 흔들림 크기는 트라우마² 다.
	  작은 충격은 거의 안 보이고 큰 충격은 확 보인다. 트라우마는 초당 DECAY 만큼 줄어든다.
	  흔들림·FOV 펀치는 카메라가 다 움직인 뒤(RenderPriority Camera+1)에 CFrame 위에 곱해 얹는다.
	  기본 카메라는 매 프레임 자기 CFrame 을 새로 계산하므로 얹은 오프셋이 누적되지 않는다.

	★ 가리는 벽을 지운다. 카메라와 나 사이에 낀 Keys.FADE_TAG 구조물만 반투명하게 만든다.
	  LocalTransparencyModifier 는 클라이언트 전용이라 서버 값을 건드리지 않는다.
	  Texture·Decal 은 LocalTransparencyModifier 를 따르지 않아 흐린 파트의 자식 Texture/Decal 도 Transparency 를 같이 바꾼다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local ZOOM_MIN = 8
local ZOOM_MAX = 120 -- 개선계획 §5.5. 높은 학교 전체가 보이게
local FIELD_OF_VIEW = 65

-- §9.1 트라우마 모델
local SHAKE_MAX_OFFSET = 0.6 -- studs
local SHAKE_MAX_ROLL = math.rad(1.5)
local SHAKE_DECAY = 1.2 -- 초당 트라우마 감소
local SHAKE_FREQ = 18 -- 노이즈 주파수(Hz)

-- FOV 펀치 65 → 59 → 65
local FOV_PUNCH_DEPTH = 6
local FOV_PUNCH_SECONDS = 0.3

-- panTo: 목표를 바라본 뒤 이만큼 있다가 Custom 으로 돌아온다
local PAN_HOLD = 1.2

-- orbit: seconds 동안 이 각도만큼 돈다(층 완공 축하는 학교를 한 바퀴 돈다)
local ORBIT_SWEEP = math.rad(360)

local FADE = 0.88

local player = Players.LocalPlayer

local CameraController = {}
CameraController.FIELD_OF_VIEW = FIELD_OF_VIEW

-- 연출 상태. nil 이면 기본 카메라(Custom)
type Pan = { kind: "pan", from: CFrame, to: CFrame, t0: number, seconds: number }
type Orbit = {
	kind: "orbit",
	center: Vector3,
	radius: number,
	pitch: number,
	angle0: number,
	t0: number,
	seconds: number,
}
type Hold = { kind: "hold", cframe: CFrame }
type Scripted = Pan | Orbit | Hold

local scripted: Scripted? = nil
local scriptedToken = 0

local shakeEnabled = true
local trauma = 0
local punchT0 = -math.huge

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function currentHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function goScriptable(state: Scripted)
	local cam = camera()
	if not cam then
		return
	end
	scriptedToken += 1
	scripted = state
	cam.CameraType = Enum.CameraType.Scriptable
end

--- Custom 카메라로 복귀. 진행 중인 연출은 버린다
function CameraController.restore()
	scriptedToken += 1
	scripted = nil
	local cam = camera()
	if not cam then
		return
	end
	cam.CameraType = Enum.CameraType.Custom
	local humanoid = currentHumanoid()
	if humanoid then
		cam.CameraSubject = humanoid
	end
	cam.FieldOfView = FIELD_OF_VIEW
end

--- seconds 동안 지금 자리에서 worldPos 를 바라보도록 돌린 뒤 PAN_HOLD 후 Custom 복귀
function CameraController.panTo(worldPos: Vector3, seconds: number)
	local cam = camera()
	if not cam then
		return
	end
	if scripted and scripted.kind == "orbit" then
		return -- 층 완공 축하 오빗이 우선이다
	end
	local from = cam.CFrame
	local to = CFrame.lookAt(from.Position, worldPos)
	goScriptable({ kind = "pan", from = from, to = to, t0 = os.clock(), seconds = math.max(seconds, 0.01) })
	local mine = scriptedToken
	task.delay(seconds + PAN_HOLD, function()
		if scriptedToken == mine then
			CameraController.restore()
		end
	end)
end

--- center 둘레를 radius 거리, pitchDeg 내려다보는 각도로 seconds 동안 돈다. 끝나면 마지막 프레임에 머문다
function CameraController.orbit(center: Vector3, radius: number, pitchDeg: number, seconds: number)
	local cam = camera()
	if not cam then
		return
	end
	local offset = cam.CFrame.Position - center
	local angle0 = math.atan2(offset.X, offset.Z)
	goScriptable({
		kind = "orbit",
		center = center,
		radius = radius,
		pitch = math.rad(pitchDeg),
		angle0 = angle0,
		t0 = os.clock(),
		seconds = math.max(seconds, 0.01),
	})
end

--- 즉시 이 CFrame 으로. restore() 전까지 머문다
function CameraController.cutTo(cframe: CFrame)
	goScriptable({ kind = "hold", cframe = cframe })
end

--- 트라우마를 더한다(0~1). 실제 흔들림은 트라우마² 에 비례
function CameraController.shake(amount: number)
	if not shakeEnabled then
		return
	end
	trauma = math.clamp(trauma + amount, 0, 1)
end

--- FOV 65 → 59 → 65, 0.3초
function CameraController.fovPunch()
	if not shakeEnabled then
		return
	end
	punchT0 = os.clock()
end

--- 접근성 「흔들림 끔」. false 면 shake/fovPunch 가 아무것도 안 한다
function CameraController.setShakeEnabled(enabled: boolean)
	shakeEnabled = enabled
	if not enabled then
		trauma = 0
		punchT0 = -math.huge
	end
end

local function orbitCFrame(state: Orbit, now: number): CFrame
	local alpha = math.clamp((now - state.t0) / state.seconds, 0, 1)
	local angle = state.angle0 + ORBIT_SWEEP * alpha
	local flat = math.cos(state.pitch) * state.radius
	local pos = state.center
		+ Vector3.new(math.sin(angle) * flat, math.sin(state.pitch) * state.radius, math.cos(angle) * flat)
	return CFrame.lookAt(pos, state.center)
end

--[[
	피치 고정(꾸미기 모드, 개선계획 §3.5 #10). 기본 카메라(Custom)는 그대로 두고 매 프레임 피치만 덮어쓴다.
	요(yaw)·줌·초점은 기본 카메라 것을 쓴다. 기본 카메라는 다음 프레임 우리 CFrame 에서 이어서 계산하므로
	드래그 회전은 그대로 먹고 피치만 다시 눌린다. 연출(scripted) 중에는 건드리지 않는다.
]]
type PitchLock = { from: number, to: number, t0: number, seconds: number, release: boolean }
local pitchLock: PitchLock? = nil
local savedPitch = 0 -- lockPitch 직전 각도. unlockPitch 가 여기로 돌아간다

--- 내려다보는 각도(라디안, 아래가 +)
local function currentPitch(cam: Camera): number
	return math.asin(math.clamp(-cam.CFrame.LookVector.Y, -1, 1))
end

local function applyPitch(cam: Camera, lock: PitchLock, now: number)
	local alpha = math.clamp((now - lock.t0) / lock.seconds, 0, 1)
	local pitch = lock.from + (lock.to - lock.from) * (1 - (1 - alpha) ^ 2)
	local focus = cam.Focus.Position
	local dist = (cam.CFrame.Position - focus).Magnitude
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		local up = cam.CFrame.UpVector
		flat = Vector3.new(up.X, 0, up.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
	end
	local dir = flat.Unit * math.cos(pitch) - Vector3.yAxis * math.sin(pitch)
	cam.CFrame = CFrame.lookAt(focus - dir * dist, focus)
	if lock.release and alpha >= 1 then
		pitchLock = nil
	end
end

--- 피치를 deg 로 seconds 동안 옮긴 뒤 unlockPitch 전까지 붙잡는다
function CameraController.lockPitch(deg: number, seconds: number)
	local cam = camera()
	if not cam then
		return
	end
	local now = currentPitch(cam)
	if not pitchLock or pitchLock.release then
		savedPitch = if pitchLock then pitchLock.to else now
	end
	pitchLock = { from = now, to = math.rad(deg), t0 = os.clock(), seconds = math.max(seconds, 0.01), release = false }
end

--- lockPitch 직전 각도로 seconds 동안 돌아간 뒤 기본 카메라에 맡긴다
function CameraController.unlockPitch(seconds: number)
	local cam = camera()
	if not cam or not pitchLock or pitchLock.release then
		return
	end
	pitchLock = {
		from = currentPitch(cam),
		to = savedPitch,
		t0 = os.clock(),
		seconds = math.max(seconds, 0.01),
		release = true,
	}
end

local function scriptedCFrame(state: Scripted, now: number): CFrame
	if state.kind == "pan" then
		local alpha = math.clamp((now - state.t0) / state.seconds, 0, 1)
		return state.from:Lerp(state.to, 1 - (1 - alpha) ^ 3)
	elseif state.kind == "orbit" then
		return orbitCFrame(state, now)
	end
	return state.cframe
end

-- 카메라가 다 움직인 뒤 연출 CFrame + 흔들림 + FOV 펀치를 얹는다
local function updateFx(dt: number)
	local cam = camera()
	if not cam then
		return
	end
	local now = os.clock()

	local state = scripted
	local lock = pitchLock
	if lock and not state then
		applyPitch(cam, lock, now)
	end
	local shaking = trauma > 0
	if state or shaking then
		local base = if state then scriptedCFrame(state, now) else cam.CFrame
		if shaking then
			trauma = math.max(0, trauma - SHAKE_DECAY * dt)
			local k = trauma * trauma
			local t = now * SHAKE_FREQ
			local dx = math.noise(t, 0.5) * SHAKE_MAX_OFFSET * k
			local dy = math.noise(t, 10.5) * SHAKE_MAX_OFFSET * k
			local roll = math.noise(t, 20.5) * SHAKE_MAX_ROLL * k
			base = base * CFrame.new(dx, dy, 0) * CFrame.Angles(0, 0, roll)
		end
		cam.CFrame = base
	end

	local punch = now - punchT0
	if punch < FOV_PUNCH_SECONDS then
		cam.FieldOfView = FIELD_OF_VIEW - FOV_PUNCH_DEPTH * math.sin(math.pi * punch / FOV_PUNCH_SECONDS)
	elseif cam.FieldOfView ~= FIELD_OF_VIEW then
		cam.FieldOfView = FIELD_OF_VIEW
	end
end

--- 파트 자식 Texture·Decal 투명도(LocalTransparencyModifier 를 따르지 않는다)
local function setSkin(part: BasePart, transparency: number)
	for _, child in part:GetChildren() do
		if child:IsA("Decal") then -- Texture 는 Decal 을 상속한다
			child.Transparency = transparency
		end
	end
end

--[[
	카메라와 나 사이를 막고 선 구조물을 반투명하게 만든다.
	지운 것을 기억해뒀다가, 다음 프레임 목록에 없으면 되돌린다.
]]
local faded: { [BasePart]: true } = {}

local function updateFade()
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local cam = camera()

	local blocking: { [BasePart]: true } = {}
	if head and head:IsA("BasePart") and cam and character then
		-- 캐릭터 자신은 제외한다. 안 그러면 내 뒤통수가 나를 가린 것으로 잡힌다.
		for _, p in cam:GetPartsObscuringTarget({ head.Position }, { character }) do
			if p:IsA("BasePart") and CollectionService:HasTag(p, Keys.FADE_TAG) then
				blocking[p] = true
				p.LocalTransparencyModifier = FADE
				if not faded[p] then
					setSkin(p, FADE)
				end
			end
		end
	end

	for p in faded do
		if not blocking[p] then
			-- 스트리밍으로 내려간 파트는 다시 올라올 때 기본값으로 오므로 만지지 않는다.
			if p.Parent then
				p.LocalTransparencyModifier = 0
				setSkin(p, 0)
			end
			faded[p] = nil
		end
	end
	for p in blocking do
		faded[p] = true
	end
end

local function onCharacter()
	-- 리스폰 시 카메라 인스턴스가 새로 만들어질 수 있으므로 여기서 같이 잡는다.
	local cam = camera()
	if cam then
		cam.FieldOfView = FIELD_OF_VIEW
	end
end

function CameraController.Start()
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = ZOOM_MIN
	player.CameraMaxZoomDistance = ZOOM_MAX

	if player.Character then
		onCharacter()
	end
	player.CharacterAdded:Connect(onCharacter)

	-- 카메라가 다 움직인 뒤에 얹어야 한 프레임 늦지 않는다. 흔들림을 얹은 뒤에 가림 계산.
	RunService:BindToRenderStep("CameraFx", Enum.RenderPriority.Camera.Value + 1, updateFx)
	RunService:BindToRenderStep("CameraFade", Enum.RenderPriority.Camera.Value + 2, updateFade)
end

return CameraController
