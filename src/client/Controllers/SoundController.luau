--!nonstrict
--[[
	사운드 12종 중 열 개를 담당한다.
	나머지 둘(분필·수업 목소리)은 SignalController 가 선생님 몸에 붙여 관리한다 —
	그 둘은 "선생님이 내는 소리"라 선생님을 아는 쪽이 들고 있어야 한다.

	여기서 내는 소리:
	  발소리   — 이동 모드와 실제 속도로 클라이언트가 직접 친다
	  삐걱     — 서버가 판정해 Cue 로 보내준다
	  의자     — 착석
	  성공음   — 그 자리가 빈자리였다는 판정. 의자와 겹쳐 난다
	  호통     — 적발
	  종       — 학년 수료
	  지각 종  — 이번 반의 제한 시간이 끝났다. 실패가 아니라 퍼펙트만 날아간다
	  숨소리   — 고자질하는 학생이 나를 봤다. 삐걱처럼 서버가 판정해 Cue 로 보낸다
	  복도     — 2D 앰비언트. 계속 돈다
	  긴장감   — 2D 앰비언트. 교실에 있는 동안만 돈다

	★ 발소리를 서버로 올리지 않는다. 서버 판정은 20Hz 라 발이 닿는 순간을 못 맞추고,
	  무엇보다 발소리는 "내가 듣는 소리"다 — 조작해봐야 자기 귀만 속인다.
	  실제 적발은 서버가 기록한 위치 델타가 낸다.

	★ 반대로 삐걱은 서버가 낸다. 삐걱은 적발 판정의 일부라서, 소리와 판정이
	  갈라지면 "소리는 안 났는데 잡혔다"가 된다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local MovementController = require(script.Parent.MovementController)

local player = Players.LocalPlayer

local SoundController = {}

-- 한 번씩 재생하는 소리는 미리 만들어두고 재사용한다.
-- 매번 Instance.new 하면 짧은 소리가 겹칠 때 GC 가 튄다.
local pool: { [string]: Sound } = {}
local stepSounds: { [string]: Sound } = {}
local tension: Sound? = nil

local lastStep = 0

local function play(key: string)
	local sound = pool[key]
	if sound then
		sound:Play()
	end
end

--[[
	발소리. 모드가 정하는 것은 볼륨·피치만이 아니라 간격이다.
	살금살금이 조용한 것은 소리가 작아서이기도 하지만, 발이 뜸해서이기도 하다.
]]
local function updateSteps(now: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Sit or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if speed < SoundConfig.STEP_MIN_SPEED then
		return
	end

	local mode = MovementController.getMode()
	if now - lastStep < SoundConfig.STEP_INTERVAL[mode] then
		return
	end
	lastStep = now

	local step = stepSounds[mode]
	if step then
		step:Play()
	end
end

--[[
	음소거. 마스터 그룹 볼륨 하나로 전부 꺼진다 — 발소리도, 분필도, 종도.
	SignalController 가 선생님에게 붙이는 소리까지 같은 그룹이라 여기서 같이 꺼진다.

	★ Pause 하지 않고 볼륨만 0 으로 둔다. 멈췄다가 다시 틀면 분필 루프가 끊기는데,
	  분필이 멈추는 것이 예고 신호의 본체라 "소리를 껐다 켰더니 예고 신호가
	  타이밍을 잃었다"가 된다. 볼륨만 0 이면 루프는 계속 제자리를 돈다.

	★ 저장하지 않는다. 세션 안에서만 유지된다 — 소리 설정 하나 때문에
	  프로필 스키마를 올리고 마이그레이션을 붙일 일이 아니다.
]]
local muted = false

function SoundController.setMuted(value: boolean)
	muted = value
	SoundConfig.master().Volume = if muted then 0 else 1
end

function SoundController.isMuted(): boolean
	return muted
end

function SoundController.toggleMute(): boolean
	SoundController.setMuted(not muted)
	return muted
end

--[[
	교실 긴장감 배경음. 교실에 들어가면 켜고 운동장으로 나오면 끈다.

	★ 선생님 상태에 반응시키지 않는다. 예고 신호가 뜰 때 음악이 같이 고조되면
	  분필이 멈추는 것을 안 듣고도 위험을 알게 된다 — 이 게임의 실력이 통째로
	  공짜가 된다. 배경음은 교실에 있다는 사실만 알려주면 된다.

	★ 운동장에서는 끈다. 계속 깔아두면 긴장감이 아니라 그냥 이 게임의 소리가 된다.
	  교실 문을 넘는 순간 소리가 바뀌어야 넘었다는 게 느껴진다.
]]
function SoundController.onTransition(to: string)
	local sound = tension
	if not sound then
		return
	end

	if to == "class" then
		sound:Play()
	else
		sound:Stop()
	end
end

-- 서버가 보내는 짧은 소리 하나. 상태를 바꾸지 않으므로 여기서 끝난다.
function SoundController.onCue(key: string)
	play(key)
end

--[[
	착석 성공. 의자 끄는 소리와 성공음을 같은 프레임에 겹쳐 낸다.

	★ 의자를 먼저 친다. 둘이 붙어 나긴 하지만 귀는 먼저 들어온 쪽을 원인으로 듣는다 —
	  "앉았고, 그래서 통과했다"의 순서다. 뒤집으면 통과한 다음에 앉은 것처럼 들린다.
]]
function SoundController.onCleared()
	play("chair")
	play("success")
end

function SoundController.onCaught()
	play("scold")
end

function SoundController.onGradeCleared()
	play("bell")
end

function SoundController.Start()
	--[[
		2D 로 쓰는 소리는 SoundService 아래에 둔다. 캐릭터에 붙이면
		부활할 때마다 같이 사라져서 다시 만들어야 한다.
	]]
	for _, key in { "creak", "chair", "success", "scold", "bell", "late", "whisper" } do
		local sound = SoundConfig.create(key)
		sound.Parent = SoundService
		pool[key] = sound
	end

	for mode, key in SoundConfig.STEP_BY_MODE do
		local sound = SoundConfig.create(key)
		sound.Parent = SoundService
		stepSounds[mode] = sound
	end

	-- 복도 웅성거림. 아주 작게 계속 돈다. 이게 있어야 학교가 비어 있지 않다.
	local hallway = SoundConfig.create("hallway")
	hallway.Parent = SoundService
	hallway:Play()

	-- 긴장감 배경음은 만들어만 둔다. 재생은 교실로 들어가는 전환이 시킨다.
	local bed = SoundConfig.create("tension")
	bed.Parent = SoundService
	tension = bed

	RunService.Heartbeat:Connect(function()
		updateSteps(os.clock())
	end)
end

return SoundController
