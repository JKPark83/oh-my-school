--!nonstrict
--[[
	학생 NPC 렌더. 클라이언트 전용이다.

	★ 학생을 서버에 두지 않는다.
	  Phase 4 에서 교실 슬롯 12개가 동시에 살아있게 되면 18 x 12 = 216 모델이 된다.
	  서버는 좌석 파트 18개(IsEmpty 어트리뷰트)만 소유하고, 각 클라이언트는
	  자기 교실 하나만 그린다. 그리는 쪽에서 보면 언제나 18명이다.

	학생은 게임 규칙상 전원 칠판(-Z)을 본다.
	CharacterBuilder 의 기본 방향이 -Z 이므로 회전 없는 CFrame 이면 그대로 맞는다.

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
local students: { [BasePart]: Student } = {}
local rng = Random.new(20260815)

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

	-- 발이 바닥(y = 0)에 닿는 위치. 회전이 없으므로 칠판을 본다.
	local base = CFrame.new(seat.Position.X, 0, seat.Position.Z)
	local model = CharacterBuilder.build(`Student{index}`, base, CharacterBuilder.studentConfig(index))
	model.Parent = container

	students[seat] = {
		model = model,
		pivot = model:GetPivot(),
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.1, 1.8),
	}
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

	container = Instance.new("Folder")
	container.Name = "StudentsLocal"
	container.Parent = Workspace

	-- 이미 복제된 좌석과, 아직 오는 중인 좌석을 모두 처리한다.
	for _, child in seats:GetChildren() do
		track(child)
	end
	seats.ChildAdded:Connect(track)

	startIdle()
end

return StudentRenderController
