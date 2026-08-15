--!nonstrict
--[[
	교실 슬롯 12개와 좌석의 유일한 주인.

	공용 서버에 12명이 들어오지만 교실은 공유하지 않는다.
	5000 스터드씩 떨어진 슬롯에 같은 교실을 12벌 지어두고, 들어온 순서대로 하나씩 빌려준다.
	StreamingEnabled 가 켜져 있으므로 클라이언트에는 자기 슬롯 주변만 내려간다 —
	교실 12개를 지어도 클라이언트가 그리는 건 여전히 하나다.

	★ 슬롯은 원점(0,0,0)을 비워두고 x = 10000 부터 시작한다.
	  원점은 Phase 5 의 운동장 허브 자리다. 나중에 허브를 지으면서
	  교실 좌표를 밀면 이미 검증된 감지 수치가 전부 무효가 된다.

	좌석 점유 상태는 서버만 쓴다. 클라이언트는 IsEmpty 어트리뷰트를 "읽기만" 하고,
	그 값으로 학생을 그릴지 말지 정한다. 어트리뷰트를 클라가 바꿔도 복제되지 않으므로
	빈자리를 위조할 수 없다.

	★ 착석 입력은 ProximityPrompt 로 받는다. RemoteEvent + seatId 방식보다 안전하다.
	  좌석 인스턴스를 클라이언트가 아니라 엔진이 넘겨주므로 인자 위조가 원천적으로 없고,
	  E키 / 모바일 버튼 / 게임패드 UI 가 공짜로 딸려온다.
	  다만 거리 검증은 여전히 서버가 직접 한다 — 프롬프트를 원격으로 발화시키는
	  익스플로잇이 실재하므로, MaxActivationDistance 를 신뢰하지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyTable = require(ReplicatedStorage.Shared.Config.DifficultyTable)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local Template = require(script.Parent.Parent.Classroom.Template)
local TeacherAI = require(script.Parent.TeacherAI)

-- 슬롯 수 = 서버 정원. 자리가 없으면 아예 못 들어오게 하는 편이
-- "교실이 없는 플레이어"라는 예외 상태를 코드 전체에서 없앤다.
local SLOT_COUNT = 12
local SLOT_ORIGIN_X = 10000
local SLOT_SPACING = 5000

-- 빈자리 개수. 1개면 목표가 명확하고, 2개면 경로 선택지가 생긴다.
local EMPTY_MIN = 1
local EMPTY_MAX = 2

local PROMPT_DISTANCE = 8

-- 나가는 문은 눌러 지나가는 물건이 아니다. 부활 지점이 바로 문 앞이라
-- 홀드가 없으면 앉으려다 눌린 E 한 번에 허브로 튕겨나간다.
local EXIT_HOLD = 0.7
local EXIT_DISTANCE = 6

local RNG = Random.new()

local ClassroomService = {}

-- 슬롯 배열은 고정이다. 세션은 슬롯을 가리킬 뿐 새로 만들지 않는다.
local slots: { any } = {}
local byPlayer: { [Player]: any } = {}
local triggerHandler: ((Player, BasePart) -> ())? = nil
local exitHandler: ((Player) -> ())? = nil

local function setEmpty(seat: BasePart, empty: boolean)
	seat:SetAttribute(RoomKeys.EMPTY_ATTRIBUTE, empty)

	local prompt = seat:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = empty
	end
end

--[[
	빈자리를 다시 뽑는다. 한 판이 끝날 때마다 호출한다.
	같은 자리가 연속으로 비면 경로를 외운 플레이어가 관찰을 건너뛴다.
]]
function ClassroomService.reroll(session)
	for _, seat in session.seats do
		setEmpty(seat, false)
	end

	local count = RNG:NextInteger(EMPTY_MIN, EMPTY_MAX)
	local pool = table.clone(session.seats)

	for _ = 1, count do
		if #pool == 0 then
			break
		end
		local picked = table.remove(pool, RNG:NextInteger(1, #pool)) :: BasePart
		setEmpty(picked, true)
	end
end

--[[
	방해물을 켜고 끈다. 켜면 보이고, 꺼지면 없는 것과 같다.

	삐걱거리는 마루를 "보이게" 켜는 것이 핵심이다. 안 보이는 함정은
	방해물이 아니라 그냥 억울함이고, 억울함은 이 게임에서 타협하지 않는 항목이다.
]]
function ClassroomService.setObstacles(session, active: boolean)
	if session.obstaclesActive == active then
		return
	end
	session.obstaclesActive = active
	session.model:SetAttribute(RoomKeys.OBSTACLES_ATTRIBUTE, active)

	for _, tile in session.creakTiles do
		tile.Transparency = if active then 0 else 1
	end
	for _, item in session.slipItems do
		item.Transparency = if active then 0 else 1
	end
end

function ClassroomService.setTriggerHandler(handler: (Player, BasePart) -> ())
	triggerHandler = handler
end

function ClassroomService.setExitHandler(handler: (Player) -> ())
	exitHandler = handler
end

function ClassroomService.isEmpty(seat: BasePart): boolean
	return seat:GetAttribute(RoomKeys.EMPTY_ATTRIBUTE) == true
end

function ClassroomService.get(player: Player)
	return byPlayer[player]
end

-- 읽기 전용으로만 쓴다. DetectionService 가 매 틱 순회하는 표다.
function ClassroomService.sessions(): { [Player]: any }
	return byPlayer
end

--[[
	빈 슬롯 하나를 플레이어에게 묶는다. 자리가 없으면 nil.

	Player 아래에 ObjectValue 를 하나 놓는 이유는, 클라이언트가 12개 중
	어느 교실이 자기 것인지 알 방법이 달리 없기 때문이다. 좌표로 추측하게 두면
	스트리밍 타이밍에 따라 엉뚱한 교실을 잡는다.
]]
function ClassroomService.acquire(player: Player)
	for _, slot in slots do
		if slot.owner then
			continue
		end

		slot.owner = player
		slot.teacher.owner = player
		byPlayer[player] = slot

		local ref = Instance.new("ObjectValue")
		ref.Name = RoomKeys.ROOM_REF
		ref.Value = slot.model
		ref.Parent = player
		slot.roomRef = ref

		return slot
	end

	return nil
end

function ClassroomService.release(player: Player)
	local slot = byPlayer[player]
	if not slot then
		return
	end

	byPlayer[player] = nil
	slot.owner = nil
	slot.teacher.owner = nil
	slot.inClass = false

	if slot.roomRef then
		slot.roomRef:Destroy()
		slot.roomRef = nil
	end

	-- 다음 사람이 1반부터 시작할 수 있도록 방해물은 꺼둔다.
	ClassroomService.setObstacles(slot, false)
	TeacherAI.reset(slot.teacher, DifficultyTable.get(1, 1))
end

local function buildSlot(index: number)
	local built = Template.build()
	local origin = CFrame.new(SLOT_ORIGIN_X + (index - 1) * SLOT_SPACING, 0, 0)

	local room = built.model
	room.Name = `Classroom{index}`
	-- Template.build 가 WorldPivot 을 원점으로 못박아 돌려주므로 순수 평행이동이다.
	room:PivotTo(origin)

	local seats: { BasePart } = {}
	for _, seat in built.seatsFolder:GetChildren() do
		if not seat:IsA("BasePart") then
			continue
		end
		table.insert(seats, seat)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "앉기"
		prompt.ObjectText = "빈자리"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = seat

		prompt.Triggered:Connect(function(player: Player)
			if triggerHandler then
				triggerHandler(player, seat)
			end
		end)
	end
	assert(#seats > 0, "교실에 좌석이 하나도 없다. Template.build 가 깨졌다.")

	--[[
		복도로 나가는 문. 부활 지점(doorCFrame) 바로 뒤에 보이지 않는 판 하나를 세우고
		프롬프트만 붙인다. 교실 템플릿을 건드리지 않는 이유는, 이 문이 교실의 일부가
		아니라 "허브로 돌아가는 통로"이기 때문이다 — 소유는 슬롯 쪽에 있다.
	]]
	local exitPart = Instance.new("Part")
	exitPart.Name = "ExitDoor"
	exitPart.Size = Vector3.new(6, 8, 1)
	exitPart.CFrame = origin * built.doorCFrame * CFrame.new(0, 1, 2.4)
	exitPart.Anchored = true
	exitPart.CanCollide = false
	exitPart.Transparency = 1
	exitPart.CastShadow = false
	exitPart.Parent = room

	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "복도로 나가기"
	exitPrompt.ObjectText = "교실 문"
	exitPrompt.KeyboardKeyCode = Enum.KeyCode.E
	exitPrompt.HoldDuration = EXIT_HOLD
	exitPrompt.MaxActivationDistance = EXIT_DISTANCE
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = exitPart

	exitPrompt.Triggered:Connect(function(player: Player)
		if exitHandler then
			exitHandler(player)
		end
	end)

	local slot = {
		index = index,
		origin = origin,
		model = room,
		seats = seats,
		spawn = built.spawn,
		creakTiles = built.creakTiles,
		slipItems = built.slipItems,
		-- doorCFrame 은 로컬 좌표로 왔다. 여기서 한 번만 월드로 바꿔 들고 다닌다.
		doorCFrame = origin * built.doorCFrame,
		teacher = TeacherAI.new(built.teacherModel, DifficultyTable.get(1, 1)),

		owner = nil,
		roomRef = nil,
		obstaclesActive = false,

		-- 허브에 있는 동안은 false. DetectionService 가 이 값을 보고 통째로 건너뛴다 —
		-- 운동장에서 선생님한테 잡히는 것만큼 황당한 버그는 없다.
		inClass = false,

		-- 아래 넷은 ProgressService 가 반을 열 때 덮어쓴다.
		-- 여기서 미리 채워두는 이유는, 입장 처리가 스트리밍을 기다리며 양보하는 동안에도
		-- DetectionService 의 틱은 계속 이 표를 읽기 때문이다.
		noiseRadius = MovementConfig.RUN_NOISE_RADIUS,
		caughtInClass = 0,
		classStartedAt = 0,
	}

	room.Parent = workspace
	ClassroomService.reroll(slot)

	return slot
end

function ClassroomService.Start()
	for index = 1, SLOT_COUNT do
		table.insert(slots, buildSlot(index))
	end
	return SLOT_COUNT
end

return ClassroomService
