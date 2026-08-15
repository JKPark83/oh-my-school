--!nonstrict
--[[
	3인칭 어깨너머 고정 카메라.

	★ 1인칭 전환을 막는다.
	  이 게임은 "선생님이 나를 보는가"보다 "내 몸이 지금 얼마나 튀는가"를 봐야 하는
	  게임이다. 1인칭에서는 자기 캐릭터가 미끄러지는 게 안 보이고,
	  그러면 감속 커브라는 시스템 자체가 플레이어에게 전달되지 않는다.

	카메라를 직접 CFrame 으로 굴리지 않는다. Humanoid.CameraOffset 과
	줌 거리 제한만 걸면 기본 카메라가 알아서 처리한다. 직접 굴리면
	충돌 처리·모바일 제스처·게임패드를 전부 다시 짜야 한다.

	★ 대신 가리는 벽을 지운다. 벽에 등을 붙이면 카메라가 벽 쪽으로 밀려
	  화면이 벽면으로 꽉 찬다. 기본 카메라는 이걸 "카메라를 앞으로 당기기"로
	  해결하는데, 좁은 교실에서는 당길 자리가 없다.

	  카메라를 옮기는 대신 막고 선 것을 반투명하게 만든다. 지워도 되는 것은
	  RoomKeys.FADE_TAG 가 붙은 구조물뿐이다 — 사람과 가구는 그대로 둔다.
	  뒤돌아섰을 때 선생님이 사라지면 그건 해결이 아니라 더 큰 문제다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)

local WAIT_TIMEOUT = 10

-- 오른쪽 어깨 뒤. 캐릭터가 화면 정중앙을 가리지 않게 살짝 왼쪽으로 밀어낸다.
local SHOULDER_OFFSET = Vector3.new(1.75, 0.5, 0)

-- 줌 최소/최대를 같은 값으로 묶어 고정한다. 최소값이 0.5 보다 크면 1인칭이 봉쇄된다.
local CAMERA_DISTANCE = 11

-- 기본값(70)보다 살짝 좁힌다. 교실이 넓어 보이면 거리 감각이 무뎌진다.
local FIELD_OF_VIEW = 65

local player = Players.LocalPlayer

local CameraController = {}

-- 연출에서 잠깐 줌인했다가 되돌릴 때 기준값이 필요하다.
CameraController.FIELD_OF_VIEW = FIELD_OF_VIEW

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT) :: Humanoid
	assert(humanoid, "캐릭터에 Humanoid 가 없다.")
	humanoid.CameraOffset = SHOULDER_OFFSET

	-- 리스폰 시 카메라 인스턴스가 새로 만들어질 수 있으므로 여기서 같이 잡는다.
	Workspace.CurrentCamera.FieldOfView = FIELD_OF_VIEW
end

--[[
	카메라와 나 사이를 막고 선 구조물을 반투명하게 만든다.

	★ Transparency 가 아니라 LocalTransparencyModifier 를 쓴다. 이건 클라이언트
	  전용 속성이라 서버가 만든 원래 Transparency 를 건드리지 않는다. 원래 값을
	  어딘가에 백업해뒀다가 되돌릴 필요도 없다 — 0 으로 되돌리면 끝이다.

	★ 지운 것을 기억해뒀다가 되돌린다. 매 프레임 새로 계산한 목록에 없는 파트는
	  더 이상 안 가린다는 뜻이므로 원래대로 돌려놓는다. 기억하지 않으면
	  한 번 지나간 벽이 영영 반투명하게 남는다.
]]
local FADE = 0.88

local faded: { [BasePart]: true } = {}

local function updateFade()
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local camera = Workspace.CurrentCamera

	local blocking: { [BasePart]: true } = {}
	if head and camera then
		-- 캐릭터 자신은 제외한다. 안 그러면 내 뒤통수가 나를 가린 것으로 잡힌다.
		for _, p in camera:GetPartsObscuringTarget({ head.Position }, { character }) do
			if CollectionService:HasTag(p, RoomKeys.FADE_TAG) then
				blocking[p] = true
				p.LocalTransparencyModifier = FADE
			end
		end
	end

	for p in faded do
		if not blocking[p] then
			-- 스트리밍으로 내려간 파트는 다시 올라올 때 기본값으로 오므로 만지지 않는다.
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
			faded[p] = nil
		end
	end
	for p in blocking do
		faded[p] = true
	end
end

function CameraController.Start()
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = CAMERA_DISTANCE
	player.CameraMaxZoomDistance = CAMERA_DISTANCE

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- 카메라가 다 움직인 뒤에 계산해야 한 프레임 늦지 않는다.
	RunService:BindToRenderStep("CameraFade", Enum.RenderPriority.Camera.Value + 1, updateFade)
end

return CameraController
