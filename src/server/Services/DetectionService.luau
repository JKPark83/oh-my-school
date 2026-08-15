--!nonstrict
--[[
	감지 판정. 이 게임에서 가장 중요한 파일이다.

	판정 순서는 가벼운 연산부터: 거리 → 시야각 → 레이캐스트.
	레이캐스트가 가장 비싸므로, 거리와 각도로 대부분을 먼저 걸러낸다.

	★ AssemblyLinearVelocity 를 쓰면 안 된다.
	  클래식 복제에서 플레이어 캐릭터의 물리 소유권은 클라이언트에 있다.
	  즉 서버가 읽는 속도값은 "클라이언트가 보고한 값"이다.
	  익스플로이터가 속도 0을 보고하면서 자유롭게 걸어다니면 이 게임은 게임이 아니게 된다.
	  반드시 서버가 직접 기록한 위치 델타를 쓴다. "안 움직인 척"은 위조할 수 없다.

	★ Phase 4 부터는 플레이어마다 교실도 선생님도 다르다.
	  판정은 언제나 "그 플레이어의 세션"에 대해서만 돈다.
	  전역 선생님 하나를 들고 있던 Phase 3 구조로 되돌아가면
	  옆 교실 선생님에게 적발되는 유령 버그가 생긴다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClassroomService = require(script.Parent.ClassroomService)
local TeacherAI = require(script.Parent.TeacherAI)

local TICK_RATE = 20 -- Hz. Heartbeat 매 프레임(60Hz)은 낭비다.

-- ── 억울함 방지 3종 세트 ──────────────────────────────────────
-- 이게 없으면 플레이어는 게임을 접는다. 전부 플레이테스트로 조정할 초기값이다.
local GRACE = 0.20 -- 감지 시작 직후 관성으로 미끄러진 프레임을 봐준다(초)
local MOVE_EPSILON = 0.05 -- stud/tick. 20Hz 기준 약 1 stud/s. idle 흔들림을 무시
-- 세 번째(적발 사유 전송)는 catch() 에서 Remotes.Caught 로 보낸다.

-- 교탁(z = -15) 기준 30스터드. 교실 세로가 38이므로 뒷문 앞 약 4스터드가
-- 구조적 사각지대가 된다. 버그가 아니라 설계다 — 플레이어에게 패턴을 관찰하고
-- 출발 타이밍을 고를 수 있는 숨돌리기 구간을 준다.
local MAX_SIGHT = 30

--[[
	마루가 삐걱대는 속도 기준. 살금살금(4)과 걷기(10) 사이에 둔다.
	즉 "삐걱거리는 널판 위에서는 살금살금만 허용된다"가 규칙이 된다.
	발소리(13.5)와 달리 걷기만 해도 걸리므로, 방해물이 켜진 6반부터는
	통로를 그냥 걸어 지나갈 수 없다.
]]
local CREAK_SPEED = 7

-- 널판 위에 서 있는지 판단할 때 허용할 수직 오차. 점프해서 넘어가는 건 봐준다.
local CREAK_HEIGHT = 4

-- 삐걱 소리 최소 간격(초). 판정은 20Hz 라 널판 위를 달리면 초당 스무 번 울린다.
local CREAK_COOLDOWN = 0.5

local DetectionService = {}

local lastPositions: { [Player]: Vector3 } = {}
local lastCreak: { [Player]: number } = {}
local caughtHandler: ((Player, string) -> ())? = nil

--[[
	엄폐물만 레이캐스트 대상으로 삼는다.
	학생 NPC 는 클라이언트 전용 렌더라 애초에 서버 Workspace 에 없다.

	교실이 12개라 필터에는 12벌의 엄폐물이 전부 들어간다. 나눠 담지 않는 이유는
	교실 간격이 5000 스터드이고 레이 길이가 30 스터드라, 남의 교실 엄폐물은
	애초에 레이에 닿지 않기 때문이다. 슬롯별 필터 12개를 관리하는 복잡도만 늘어난다.
]]
local coverParams = RaycastParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Include
coverParams.FilterDescendantsInstances = {}

local function refreshCoverFilter()
	coverParams.FilterDescendantsInstances = CollectionService:GetTagged(RoomKeys.COVER_TAG)
end

--[[
	여기는 "적발됐다"까지만 판단한다. 연출과 부활은 ProgressService 가 한다.
	성공 처리와 실패 처리가 한 곳에 있어야 성공 직후 적발 같은 이중 처리를 막을 수 있다.
]]
local function catch(player: Player, reason: string)
	-- 위치 기록을 지워야 텔레포트 직후의 거대한 델타로 즉시 재적발되지 않는다.
	lastPositions[player] = nil

	if caughtHandler then
		caughtHandler(player, reason)
	end
end

--[[
	달리는 발소리. 판서 중이어도 선생님이 판서를 끊고 돌아본다.

	클라이언트가 보고하는 이동 모드는 쓰지 않는다 — 익스플로이터는 "살금살금 중"이라고
	보고하면서 달릴 수 있다. 서버가 기록한 위치 델타로 직접 속도를 계산한다.

	반경은 세션마다 다르다. 실내화(quietShoes)를 산 플레이어는 절반이다.
]]
local function checkNoise(hrp: BasePart, session, speed: number)
	if speed < MovementConfig.RUN_NOISE_SPEED then
		return
	end
	if (hrp.Position - session.teacher.head.Position).Magnitude > session.noiseRadius then
		return
	end

	TeacherAI.interrupt(session.teacher)
end

--[[
	삐걱거리는 마룻바닥. 발소리와 결과는 같지만(판서 중단) 조건이 다르다.
	거리 판정이 없다 — 같은 교실 안이면 어디서 밟든 들린다.

	★ 소리도 여기서 낸다. 삐걱 소리만 클라이언트가 자기 판단으로 내면
	  "소리는 안 났는데 선생님이 돌아봤다"가 생긴다. 판정과 소리는 같은 줄에 있어야 한다.
]]
local function checkCreak(player: Player, hrp: BasePart, session, speed: number, now: number)
	if not session.obstaclesActive or speed < CREAK_SPEED then
		return
	end

	local position = hrp.Position
	for _, tile in session.creakTiles do
		local offset = tile.CFrame:PointToObjectSpace(position)
		if
			math.abs(offset.X) <= tile.Size.X / 2
			and math.abs(offset.Z) <= tile.Size.Z / 2
			and math.abs(offset.Y) <= CREAK_HEIGHT
		then
			TeacherAI.interrupt(session.teacher)

			local last = lastCreak[player]
			if not last or now - last >= CREAK_COOLDOWN then
				lastCreak[player] = now
				Remotes.Cue:FireClient(player, "creak")
			end
			return
		end
	end
end

local function check(player: Player, session, now: number, deltaTime: number)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- 위치는 감지 여부와 무관하게 "항상" 갱신한다.
	-- 이걸 조기 return 뒤에 두면, 감지가 꺼진 동안 이동한 거리가
	-- 감지가 켜지는 첫 틱에 한꺼번에 델타로 잡혀 억울한 죽음이 된다.
	local prev = lastPositions[player]
	lastPositions[player] = hrp.Position

	if prev then
		-- 수직 성분은 뺀다. 낙하는 발소리가 아니다.
		local step = hrp.Position - prev
		local speed = Vector3.new(step.X, 0, step.Z).Magnitude / deltaTime
		if speed == speed then -- NaN 가드
			checkNoise(hrp, session, speed)
			checkCreak(player, hrp, session, speed, now)
		end
	end

	local teacher = session.teacher
	if not TeacherAI.isWatching(teacher, now) then
		return
	end
	if now - teacher.watchStartedAt < GRACE then
		return
	end

	local toPlayer = hrp.Position - teacher.head.Position
	local dist = toPlayer.Magnitude

	-- (1) 거리 — 가장 싸다. 항상 먼저.
	if dist ~= dist or dist > MAX_SIGHT or dist < 1e-3 then
		return
	end

	-- (2) 시야각 — 코사인 비교. 삼각함수 호출 없이 내적 하나로 끝난다.
	local cosAngle = teacher.head.CFrame.LookVector:Dot(toPlayer.Unit)
	if cosAngle < math.cos(math.rad(teacher.config.fovDeg / 2)) then
		return
	end

	-- (3) 엄폐 — 가장 비싸다. 정말 위험한 순간에만 나간다.
	if workspace:Raycast(teacher.head.Position, toPlayer, coverParams) then
		return
	end

	-- (4) 움직임 — 서버가 기록한 위치 델타로만 판정한다.
	if prev and (hrp.Position - prev).Magnitude > MOVE_EPSILON then
		catch(player, "moved_in_sight")
	end
end

function DetectionService.setCaughtHandler(handler: (Player, string) -> ())
	caughtHandler = handler
end

--[[
	위치 기록을 지운다. 순간이동(부활/착석) 직후에 반드시 불러야 한다.
	이걸 빠뜨리면 이동한 거리가 다음 틱에 한꺼번에 델타로 잡혀
	"가만히 있었는데 죽었다"가 된다.
]]
function DetectionService.forget(player: Player)
	lastPositions[player] = nil
end

function DetectionService.Start()
	refreshCoverFilter()
	CollectionService:GetInstanceAddedSignal(RoomKeys.COVER_TAG):Connect(refreshCoverFilter)
	CollectionService:GetInstanceRemovedSignal(RoomKeys.COVER_TAG):Connect(refreshCoverFilter)

	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player] = nil
		lastCreak[player] = nil
	end)

	local accumulator = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		local sessions = ClassroomService.sessions()
		local now = os.clock()

		-- 회전 보간은 매 프레임. 20Hz 로 돌리면 눈에 띄게 끊긴다.
		-- 비어 있는 슬롯의 선생님은 돌리지 않는다 — 보는 사람이 없다.
		-- 허브에 있는 플레이어의 교실은 통째로 건너뛴다. 보는 사람도 없고,
		-- 무엇보다 운동장에서 감지가 돌면 안 된다.
		for _, session in sessions do
			if session.inClass then
				TeacherAI.update(session.teacher, now)
			end
		end

		accumulator += deltaTime
		if accumulator < 1 / TICK_RATE then
			return
		end

		-- 실제 경과 시간을 쓴다. 프레임 경계 때문에 틱 간격은 1/20 보다 항상 조금 길다.
		local elapsed = accumulator
		accumulator = 0

		for player, session in sessions do
			if session.inClass then
				check(player, session, now, elapsed)
			end
		end
	end)
end

return DetectionService
