--!nonstrict
--[[
	선생님 상태머신. 선생님 상태의 유일한 주인이다.

	다른 곳에서 teacher.state 에 직접 대입하면 stateVersion 이 밀리지 않아
	클라이언트와 어긋난다. 반드시 setState 를 통한다.

	           ┌──────────────────────────────────────────────┐
	           ▼                                              │
	      [TEACHING] ──teachTime──▶ [WARNING] ──warnTime──▶ [TURNING]
	                                    │                       │ turnTime
	                                    │ fakeChance            ▼
	                                    ▼                  [WATCHING]
	                               [FAKE_TURN]                  │ watchTime
	                                    │                       ▼
	                                    └──────────────▶  [RETURNING] ──turnTime──┐
	                                      (다시 TEACHING)                          │
	                                                                              └─▶ TEACHING
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

-- 감지가 켜지는 시점: TURNING 의 후반 50%.
-- 전반부까지 켜면 예고를 보고 멈춘 플레이어가 억울하게 죽는다.
local TURN_DETECT_RATIO = 0.5

-- FAKE_TURN 은 예고만 하고 안 돌아보는 낚시. 예고보다 살짝 길게 끌어야 낚인다.
local FAKE_EXTRA_TIME = 0.3

local RNG = Random.new()

local TeacherAI = {}

local function jitter(base: number, ratio: number): number
	return base * (1 + RNG:NextNumber(-ratio, ratio))
end

local function setYaw(teacher: Types.Teacher, yaw: number)
	teacher.model:PivotTo(teacher.basePivot * CFrame.Angles(0, yaw, 0))
end

--[[
	@param model 선생님 모델. "Head" 자식이 있어야 한다(시야 판정 기준점).
	@param config DifficultyTable.get() 결과
]]
function TeacherAI.new(model: Model, config: Types.TeacherConfig): Types.Teacher
	local head = model:FindFirstChild("Head")
	assert(
		head and head:IsA("BasePart"),
		"선생님 모델에 Head 파트가 없다. 시야 판정 기준점이 필요하다."
	)

	local basePivot = model:GetPivot()
	local now = os.clock()

	local teacher: Types.Teacher = {
		model = model,
		head = head,
		config = config,
		owner = nil,

		state = "TEACHING",
		stateVersion = 0,
		stateStartedAt = now,
		stateEndsAt = now + jitter(config.teachTime, 0.20),
		watchStartedAt = math.huge,
		lastWasFake = false,

		teachYaw = 0,
		basePivot = basePivot,
	}

	return teacher
end

--[[
	상태 변경 + stateVersion 증가 + 소유자에게 전송을 한 번에 처리하는 유일한 지점.

	선생님 상태를 어트리뷰트로도 노출하는 이중 채널은 만들지 않는다.
	RemoteEvent 는 어트리뷰트·프로퍼티 복제와 순서가 보장되지 않으므로,
	채널이 둘이면 클라이언트가 어느 쪽을 믿어야 할지 모르는 순간이 반드시 생긴다.
]]
function TeacherAI.setState(teacher: Types.Teacher, newState: Types.TeacherState, duration: number)
	local now = os.clock()

	teacher.state = newState
	teacher.stateVersion += 1
	teacher.stateStartedAt = now
	teacher.stateEndsAt = now + duration

	if newState == "TURNING" then
		-- 감지가 실제로 켜지는 시각을 여기서 확정해 WATCHING 까지 들고 간다.
		teacher.watchStartedAt = now + duration * TURN_DETECT_RATIO
	elseif newState ~= "WATCHING" then
		teacher.watchStartedAt = math.huge
	end

	-- 회전이 끝나는 상태에서는 자세를 정확한 각도로 한 번만 고정한다.
	-- 보간의 마지막 프레임에 맡기면 몇 도가 남아 시야각 판정이 미세하게 틀어진다.
	if newState == "WATCHING" then
		setYaw(teacher, math.pi)
	elseif newState == "TEACHING" then
		setYaw(teacher, 0)
	end

	-- 교실이 12개가 된 뒤로는 전체 방송을 하면 안 된다.
	-- 남의 교실 선생님이 돌아볼 때마다 내 화면에 비네트가 번쩍인다.
	local owner = teacher.owner
	if not owner then
		return
	end

	local packet: Types.TeacherStatePacket = {
		version = teacher.stateVersion,
		state = newState,
		duration = duration,
	}
	Remotes.TeacherStateChanged:FireClient(owner, packet)
end

--[[
	사이클은 그대로 두고 수치만 갈아끼운다. 업그레이드를 산 즉시 반영할 때 쓴다.
	여기서 사이클까지 되돌리면 예고를 기다리던 플레이어가 영문 모르고 죽는다.
]]
function TeacherAI.setConfig(teacher: Types.Teacher, config: Types.TeacherConfig)
	teacher.config = config
end

--[[
	새 반을 시작한다. 난이도를 갈아끼우고 사이클을 판서 처음부터 다시 돌린다.

	stateVersion 은 일부러 리셋하지 않는다. 클라이언트의 순서 필터가
	단조 증가를 전제로 하므로, 여기서 0 으로 되돌리면 새 반의 첫 패킷들이
	전부 "오래된 패킷"으로 버려진다.
]]
function TeacherAI.reset(teacher: Types.Teacher, config: Types.TeacherConfig)
	teacher.config = config
	teacher.lastWasFake = false
	TeacherAI.setState(teacher, "TEACHING", jitter(config.teachTime, 0.20))
end

--[[
	소음 같은 외부 자극으로 판서를 끊는다. 판서 중이 아니면 아무 일도 없다.

	★ WARNING 을 건너뛰고 바로 WATCHING 으로 보내지 않는다.
	  예고 없는 적발은 억울함이고, 억울함은 이 게임에서 유일하게 타협하지 않는 항목이다.
	  "달리면 바로 돌아본다"는 판서 시간이 끝나기를 기다리지 않는다는 뜻이지,
	  플레이어의 반응 예산을 빼앗는다는 뜻이 아니다.

	@return 실제로 끊었으면 true
]]
function TeacherAI.interrupt(teacher: Types.Teacher): boolean
	if teacher.state ~= "TEACHING" then
		return false
	end

	teacher.lastWasFake = false
	TeacherAI.setState(teacher, "WARNING", teacher.config.warnTime)
	return true
end

local function advance(teacher: Types.Teacher)
	local config = teacher.config
	local state = teacher.state

	if state == "TEACHING" then
		TeacherAI.setState(teacher, "WARNING", config.warnTime)
	elseif state == "WARNING" then
		-- 페이크 직후에는 연속 페이크를 금지한다. 2연속 낚시는 억울하게 느껴진다.
		local canFake = config.fakeChance > 0 and not teacher.lastWasFake
		if canFake and RNG:NextNumber() < config.fakeChance then
			teacher.lastWasFake = true
			TeacherAI.setState(teacher, "FAKE_TURN", config.warnTime + FAKE_EXTRA_TIME)
		else
			teacher.lastWasFake = false
			TeacherAI.setState(teacher, "TURNING", config.turnTime)
		end
	elseif state == "TURNING" then
		TeacherAI.setState(teacher, "WATCHING", jitter(config.watchTime, 0.25))
	elseif state == "WATCHING" then
		TeacherAI.setState(teacher, "RETURNING", config.turnTime)
	elseif state == "FAKE_TURN" or state == "RETURNING" then
		-- 낚시를 마쳤든 정직하게 돌아왔든, 다음은 다시 판서다.
		TeacherAI.setState(teacher, "TEACHING", jitter(config.teachTime, 0.20))
	end
end

--[[
	매 프레임 호출한다. 회전 보간이 들어있으므로 20Hz 로 돌리면 눈에 띄게 끊긴다.

	회전은 CFrame:Lerp 대신 yaw 각도를 직접 보간한다.
	정확히 180도 회전은 쿼터니언 slerp 에서 축이 모호해져 엉뚱한 방향으로 돌 수 있다.
]]
function TeacherAI.update(teacher: Types.Teacher, now: number)
	local state = teacher.state

	if state == "TURNING" or state == "RETURNING" then
		local alpha = math.clamp((now - teacher.stateStartedAt) / teacher.config.turnTime, 0, 1)
		setYaw(teacher, if state == "TURNING" then alpha * math.pi else (1 - alpha) * math.pi)
	end

	if now >= teacher.stateEndsAt then
		advance(teacher)
	end
end

-- 감지 판정을 돌려야 하는 구간인가. TURNING 후반 50% + WATCHING 전체.
function TeacherAI.isWatching(teacher: Types.Teacher, now: number): boolean
	return now >= teacher.watchStartedAt
end

return TeacherAI
