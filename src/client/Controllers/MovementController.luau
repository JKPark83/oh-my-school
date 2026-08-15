--!nonstrict
--[[
	이동 3단계 + 감속 커브.

	★ Humanoid.WalkSpeed = 0 을 쓰지 않는다.
	  즉시 정지는 손맛이 없고, 무엇보다 "정지 거리"라는 개념 자체를 없애
	  게임을 무너뜨린다. 이 게임의 모든 판단은 "지금 멈추면 늦는가"에서 나온다.

	★ AssemblyLinearVelocity 에 직접 쓰지 않는다.
	  입력을 뗀 순간 Humanoid 의 지면 컨트롤러는 목표 속도를 0 으로 잡고
	  강한 힘으로 감속시킨다. 매 프레임 속도를 덮어써도 다음 물리 스텝에서
	  대부분 상쇄되어, 미끄러지는 대신 덜덜 떨다 선다.
	  대신 WalkSpeed 를 곡선으로 낮추면서 humanoid:Move() 로 마지막 방향을
	  계속 먹인다. 물리와 싸우지 않으므로 부드럽고, 걷기 애니메이션도 같이 느려진다.

	★ 서버는 이 파일의 결과를 신뢰하지 않는다.
	  감속 커브는 순전히 체감용이다. 적발 판정은 서버가 기록한 위치 델타가
	  담당하고, 서버는 "실제로 움직였는가"만 본다. 클라가 감속을 조작해도 얻을 게 없다.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local WAIT_TIMEOUT = 10

--[[
	굴러다니는 지우개·필통. 밟으면 정지 거리가 두 배가 된다.

	★ 이 판정만 클라이언트에 있다. 서버로 올리지 않는 이유는,
	  조작해봐야 스스로 건 페널티가 사라질 뿐 적발 판정에는 아무 영향이 없기 때문이다.
	  적발은 여전히 서버가 기록한 위치 델타로만 난다. 서버로 올리면
	  20Hz 틱에 밟는 순간을 놓쳐 "밟았는데 안 미끄러졌다"가 생긴다.
]]
local SLIP_RADIUS = 3
local SLIP_TIME = 1.2 -- 밟은 뒤 미끄러짐이 유지되는 시간(초)
local SLIP_STOP_SCALE = 2

--[[
	점프. 운동장이든 교실이든 어디서나 된다.

	★ 감속 커브와는 원래 상충한다. 공중에 뜨면 WalkSpeed 를 낮춰도 수평 속도가
	  줄지 않는다 — 발이 땅에 없으니 지면 컨트롤러가 일을 못 한다. 그래서 한때는
	  교실에서만 껐었는데, 뛸 수 없다는 것 자체가 답답하다는 판단이라 되돌렸다.
	  감속이 이상하게 느껴진다는 말이 나오면 여기가 첫 번째로 의심할 곳이다.

	★ 기본값에 맡기지 않고 명시적으로 건다. 잡혀서 리스폰될 때마다 캐릭터가 새로
	  생기는데, 그때 점프 높이를 정하는 것이 이 파일이 아니라 StarterPlayer 설정이
	  되어버리면 "왜 어떤 판에서는 안 뛰어지지"를 여기서 찾을 수 없게 된다.
]]
local JUMP_HEIGHT = 7.2 -- 로블록스 기본값

local player = Players.LocalPlayer

local MovementController = {}

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local controls = nil

local mode = MovementConfig.DEFAULT_MODE
local sprintHeld = false
local sneakHeld = false

-- 감속 중 상태. 입력을 뗀 순간에 고정되고, 멈출 때까지 유지된다.
local sliding = false
local slideSpeed = 0
local slideStopTime = 0
local slideDir = Vector3.zero

-- 방해물·업그레이드 보정. 둘 다 stopTime 에만 곱해진다.
local room: Model? = nil
local slipItems: { BasePart } = {}
local slipUntil = 0
local balanceScale = 1

local function applyMode()
	-- 살금살금이 달리기를 이긴다. 둘 다 누르면 안전한 쪽으로 간다.
	mode = if sneakHeld then "SNEAK" elseif sprintHeld then "RUN" else "WALK"

	-- 미끄러지는 중에는 WalkSpeed 를 건드리지 않는다.
	-- 여기서 덮어쓰면 "미끄러지다가 Ctrl 을 눌러 즉시 정지"가 가능해진다.
	-- 그건 브레이크 버튼이고, 이 게임에는 브레이크가 없어야 한다.
	if humanoid and not sliding then
		humanoid.WalkSpeed = MovementConfig.MODES[mode].speed
	end
end

local function applyJump()
	if humanoid then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = JUMP_HEIGHT
	end
end

local function horizontalSpeed(): number
	if not rootPart then
		return 0
	end
	local v = rootPart.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

--[[
	발밑에 굴러다니는 물건이 있는지 본다. 방해물이 꺼진 반(1~5반)에서는 아무것도 안 한다.
	물건은 2개뿐이라 거리 계산 두 번이면 끝난다 — 공간 분할이 필요한 규모가 아니다.
]]
local function checkSlip(now: number)
	if not rootPart or not room or room:GetAttribute(RoomKeys.OBSTACLES_ATTRIBUTE) ~= true then
		return
	end

	local position = rootPart.Position
	for _, item in slipItems do
		if (position - item.Position).Magnitude <= SLIP_RADIUS then
			slipUntil = now + SLIP_TIME
			return
		end
	end
end

-- 지금 입력을 떼면 얼마나 미끄러지는가. 시상수는 여기 한 곳에서만 조립한다.
local function currentStopTime(now: number): number
	local base = MovementConfig.MODES[mode].stopTime * balanceScale
	return if now < slipUntil then base * SLIP_STOP_SCALE else base
end

local function onStepped(totalTime: number, deltaTime: number)
	if not humanoid or not controls then
		return
	end

	checkSlip(totalTime)

	-- "입력이 들어오고 있는가"는 Humanoid.MoveDirection 이 아니라 컨트롤 모듈에게 묻는다.
	-- 감속 중에는 우리가 직접 Move() 를 호출하므로 MoveDirection 이 0 이 아니게 되고,
	-- 그걸 입력으로 오해하면 영원히 감속이 끝나지 않는다.
	if controls:GetMoveVector().Magnitude > 0.01 then
		sliding = false
		humanoid.WalkSpeed = MovementConfig.MODES[mode].speed

		local dir = humanoid.MoveDirection
		if dir.Magnitude > 0.01 then
			slideDir = dir
		end
		return
	end

	if not sliding then
		local speed = horizontalSpeed()
		if speed <= MovementConfig.STOP_CUTOFF or slideDir.Magnitude < 0.01 then
			return
		end

		-- 방금 입력을 뗐다. 이 순간의 실제 속도와 시상수를 고정한다.
		-- 시상수를 고정하는 이유는 위 applyMode() 의 주석과 같다.
		sliding = true
		slideSpeed = speed
		slideStopTime = currentStopTime(totalTime)
	end

	slideSpeed *= math.exp(-deltaTime / slideStopTime)

	if slideSpeed <= MovementConfig.STOP_CUTOFF then
		sliding = false
		slideDir = Vector3.zero
		humanoid.WalkSpeed = MovementConfig.MODES[mode].speed
		return
	end

	humanoid.WalkSpeed = slideSpeed
	humanoid:Move(slideDir, false)
end

local function onSprint(_name: string, state: Enum.UserInputState)
	sprintHeld = state == Enum.UserInputState.Begin
	applyMode()
	return Enum.ContextActionResult.Sink
end

local function onSneak(_name: string, state: Enum.UserInputState)
	sneakHeld = state == Enum.UserInputState.Begin
	applyMode()
	return Enum.ContextActionResult.Sink
end

local function onCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT) :: Humanoid
	rootPart = character:WaitForChild("HumanoidRootPart", WAIT_TIMEOUT) :: BasePart
	assert(humanoid and rootPart, "캐릭터에 Humanoid/HumanoidRootPart 가 없다.")

	-- 잡혀서 텔레포트된 직후 관성이 남아있으면 안 된다.
	sliding = false
	slideDir = Vector3.zero
	applyMode()

	-- 캐릭터가 새로 생기면 JumpHeight 도 새로 설정된다. 여기서 매번 다시 건다.
	applyJump()
end

-- HUD 표시용. 서버로는 보내지 않는다 — 서버는 위치 델타로 직접 판단한다.
function MovementController.getMode(): string
	return mode
end

--[[
	균형감각(balance) 업그레이드를 반영한다. 서버가 보내는 프로필 스냅샷이 유일한 근거다.
	클라이언트가 자기 마음대로 켜봐야 정지 거리만 줄어들 뿐, 적발 판정은 서버 몫이라
	얻을 게 없다. 그래서 여기서는 검증하지 않는다.
]]
function MovementController.onProfile(packet)
	balanceScale = if packet.upgrades and packet.upgrades.balance then Upgrades.BALANCE_STOP_SCALE else 1
end

--[[
	교실이 정해진 뒤에 부른다. 운동장에서는 밟을 물건이 없으므로
	room 이 nil 인 채로도 이동은 완전히 돌아간다 — checkSlip 이 먼저 빠져나간다.

	Phase 5 부터 첫 화면이 운동장이라 Start 시점에는 교실이 아직 스트리밍되지 않았다.
	그래서 이동 시작과 교실 연결을 떼어놨다.
]]
function MovementController.bindRoom(assignedRoom: Model)
	room = assignedRoom
	slipItems = {}

	local obstacles = assignedRoom:WaitForChild(RoomKeys.OBSTACLES_FOLDER, WAIT_TIMEOUT)
	if obstacles then
		for _, item in obstacles:GetChildren() do
			if item:IsA("BasePart") and item:HasTag(RoomKeys.SLIP_TAG) then
				table.insert(slipItems, item)
			end
		end
	end
end

function MovementController.Start()
	local playerScripts = player:WaitForChild("PlayerScripts", WAIT_TIMEOUT)
	assert(playerScripts, "PlayerScripts 가 없다.")

	-- PlayerModule 은 로블록스가 런타임에 넣어주는 모듈이라 Rojo 소스맵에 없다.
	-- any 로 캐스팅해 타입 분석기가 경로를 못 찾는다고 불평하지 않게 한다.
	local playerModule = require(playerScripts:WaitForChild("PlayerModule", WAIT_TIMEOUT) :: any)
	controls = playerModule:GetControls()

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- createTouchButton = true 하나로 모바일 터치 버튼이 자동 생성된다.
	-- UserInputService.InputBegan 대신 ContextActionService 를 쓰는 이유가 이것이고,
	-- 채팅창이 열려 있을 때 Shift 충돌을 알아서 처리해주는 것이 또 하나다.
	ContextActionService:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("Sneak", onSneak, true, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("Sprint", "달리기")
	ContextActionService:SetTitle("Sneak", "살금")

	-- Stepped 는 렌더 스텝(기본 컨트롤 모듈이 Move 를 호출하는 시점) 다음,
	-- 물리 스텝 직전이다. 여기서 Move 를 부르면 우리 값이 최종적으로 반영된다.
	RunService.Stepped:Connect(onStepped)
end

return MovementController
