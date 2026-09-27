--!nonstrict
--[[
	학생 NPC 렌더. 클라이언트 전용이다.

	★ 학생을 서버에 두지 않는다.
	  Phase 4 에서 교실 슬롯 12개가 동시에 살아있게 되면 18 x 12 = 216 모델이 된다.
	  서버는 좌석 파트 18개(IsEmpty 어트리뷰트)만 소유하고, 각 클라이언트는
	  자기 교실 하나만 그린다. 그리는 쪽에서 보면 언제나 18명이다.

	학생은 기본적으로 칠판(-Z)을 본다. CharacterBuilder 의 기본 방향이 -Z 이므로
	회전 없는 CFrame 이면 그대로 맞는다. 예외가 고자질하는 학생이다 —
	Facing 어트리뷰트가 0 이 아니면 그만큼 돌려 앉힌다.

	★ 방향과 손드는 자세를 여기서 "정하지" 않는다. 서버가 어트리뷰트로 말한 것을
	  그리기만 한다. 누가 고자질하는 학생인지는 서버의 판정 근거이기도 해서,
	  화면이 자기 마음대로 그리면 보이는 것과 규칙이 어긋난다.

	빈자리에는 아무도 그리지 않는다. 서버가 IsEmpty 를 바꾸면 여기서 즉시 반영된다 —
	즉 "빈자리가 어디인가"는 클라이언트가 정하는 것이 아니라 보여주기만 한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)

local WAIT_TIMEOUT = 10

-- 미세 idle. 30Hz 로 충분하다. 60Hz 로 돌리면 저사양 기기에서 이 루프만으로 프레임이 깎인다.
local IDLE_RATE = 30
local BOB_HEIGHT = 0.04 -- 숨쉬는 상하 폭(스터드)
local SWAY_ANGLE = 0.05 -- 몸통이 좌우로 흔들리는 각도(라디안)

local StudentRenderController = {}

type Student = {
	model: Model,
	pivot: CFrame,
	phase: number,
	speed: number,
}

local container: Folder
local seatsFolder: Instance
local students: { [BasePart]: Student } = {}
local rng = Random.new(20260815)

--[[
	이 교실의 학년. 아이들 체구가 여기서 나온다.

	★ 프로필(ProfileUpdated)이 아니라 교실 모델의 어트리뷰트를 본다.
	  학생 렌더는 교실에 매여 있고 프로필은 플레이어에 매여 있어서, 둘의 도착 순서가
	  어긋나면 한 반을 통째로 전 학년 체구로 그린다. 그리는 근거는
	  그리는 대상에 붙어 있어야 한다.
]]
local grade = 1

local function despawn(seat: BasePart)
	local student = students[seat]
	if not student then
		return
	end
	students[seat] = nil
	student.model:Destroy()
end

local function spawnStudent(seat: BasePart)
	despawn(seat)

	local index = seat:GetAttribute("Index") or 1
	local config = CharacterBuilder.studentConfig(index, grade)

	-- 발이 바닥(y = 0)에 닿는 위치. 회전이 0 이면 칠판을 본다.
	local yaw = seat:GetAttribute(RoomKeys.FACING_ATTRIBUTE) or 0
	local base = CFrame.new(seat.Position.X, 0, seat.Position.Z) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = CharacterBuilder.build(`Student{index}`, base, config)
	model.Parent = container

	local student = {
		model = model,
		pivot = model:GetPivot(),
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.1, 1.8),
	}
	students[seat] = student

	-- 반 도중에 다시 그려지는 경우(빈자리 재배치 등)를 위해 손 상태도 같이 복원한다.
	if seat:GetAttribute(RoomKeys.RAISED_ATTRIBUTE) == true then
		CharacterBuilder.setHandRaised(model, true)
	end
end

local function refresh(seat: BasePart)
	if seat:GetAttribute(RoomKeys.EMPTY_ATTRIBUTE) == true then
		despawn(seat)
	else
		spawnStudent(seat)
	end
end

local function track(child: Instance)
	if not child:IsA("BasePart") then
		return
	end
	child:GetAttributeChangedSignal(RoomKeys.EMPTY_ATTRIBUTE):Connect(function()
		refresh(child)
	end)
	-- 방향이 바뀌면 다시 세운다. 손든 팔의 기준 자세도 같이 새로 잡힌다.
	child:GetAttributeChangedSignal(RoomKeys.FACING_ATTRIBUTE):Connect(function()
		refresh(child)
	end)
	child:GetAttributeChangedSignal(RoomKeys.RAISED_ATTRIBUTE):Connect(function()
		local student = students[child]
		if student then
			CharacterBuilder.setHandRaised(student.model, child:GetAttribute(RoomKeys.RAISED_ATTRIBUTE) == true)
		end
	end)
	refresh(child)
end

local function startIdle()
	local elapsed = 0
	local accumulator = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		accumulator += deltaTime
		if accumulator < 1 / IDLE_RATE then
			return
		end
		accumulator = 0

		for _, student in students do
			local t = elapsed * student.speed + student.phase
			-- 모델 전체를 한 번에 옮긴다. 파트를 하나씩 움직이면 얼굴이 머리에서 떨어져 나간다.
			student.model:PivotTo(
				student.pivot
					* CFrame.new(0, math.sin(t) * BOB_HEIGHT, 0)
					* CFrame.Angles(0, math.sin(t * 0.6) * SWAY_ANGLE, 0)
			)
		end
	end)
end

function StudentRenderController.Start(room: Model)
	local seats = room:WaitForChild(RoomKeys.SEATS_FOLDER, WAIT_TIMEOUT)
	assert(seats, "좌석 폴더가 복제되지 않았다.")
	seatsFolder = seats

	container = Instance.new("Folder")
	container.Name = "StudentsLocal"
	container.Parent = Workspace

	grade = room:GetAttribute(RoomKeys.GRADE_ATTRIBUTE) or grade

	--[[
		학년이 바뀌면 열여덟 명을 통째로 다시 그린다.

		★ 반이 바뀔 때마다가 아니라 학년이 바뀔 때만 일어나는 일이다.
		  같은 학년 안에서 1반부터 12반까지는 이 신호가 안 온다.

		★ 살아 있는 students 표를 순회하지 않고 좌석 폴더를 다시 훑는다.
		  refresh 가 표에서 지웠다가 다시 넣기 때문에, 순회 중에 그러면
		  Lua 가 다음 키를 못 찾는다.
	]]
	room:GetAttributeChangedSignal(RoomKeys.GRADE_ATTRIBUTE):Connect(function()
		grade = room:GetAttribute(RoomKeys.GRADE_ATTRIBUTE) or grade
		for _, child in seatsFolder:GetChildren() do
			if child:IsA("BasePart") then
				refresh(child)
			end
		end
	end)

	-- 이미 복제된 좌석과, 아직 오는 중인 좌석을 모두 처리한다.
	for _, child in seats:GetChildren() do
		track(child)
	end
	seats.ChildAdded:Connect(track)

	startIdle()
end

return StudentRenderController
