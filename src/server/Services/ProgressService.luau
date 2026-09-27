--!nonstrict
--[[
	한 플레이어의 "한 판"과 "12반 진행"을 담당한다.

	성공과 실패가 같은 파일에 있는 이유는, 둘 다 "플레이어를 얼려서 연출을 보여주고
	문 앞으로 되돌린다"는 같은 절차이기 때문이다.
	이 절차가 두 곳에 흩어지면 성공 직후 적발 같은 이중 처리가 반드시 생긴다.

	진행도(별·업그레이드·반)까지 여기서 다루는 이유도 같다.
	별을 주는 순간은 클리어하는 순간 하나뿐이고, 그 순간의 판정 근거(퍼펙트였는가)는
	실패 처리가 쥐고 있다. 둘을 떼면 "퍼펙트 판정"이 두 파일에 걸친다.

	★ 착석 검증 순서: 레이트 리밋 → 진행 중복 → 내 교실 → 빈자리 → 캐릭터 → 거리(NaN 가드)
	  거리 검증이 없으면 텔레포트 치트로 72반이 3초에 뚫린다.
	  ProximityPrompt 의 MaxActivationDistance 는 클라이언트 쪽 판정이라 신뢰하지 않는다.
	  "내 교실인가"는 Phase 4 에서 새로 생긴 항목이다 — 프롬프트를 원격으로 발화시키면
	  5000 스터드 밖 남의 교실 좌석도 트리거할 수 있다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyTable = require(ReplicatedStorage.Shared.Config.DifficultyTable)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local ClassroomService = require(script.Parent.ClassroomService)
local DataService = require(script.Parent.DataService)
local DetectionService = require(script.Parent.DetectionService)
local PlaygroundService = require(script.Parent.PlaygroundService)
local TeacherAI = require(script.Parent.TeacherAI)

-- 프롬프트 사거리(8)보다 넉넉하게 잡되, 통로 건너편에서는 닿지 않도록.
-- 분단 간격이 14 이므로 12 면 "옆 분단 자리에 원격 착석"은 막힌다.
local SIT_RANGE = 12
local TRIGGER_INTERVAL = 0.4
local UPGRADE_INTERVAL = 1.0

-- 연출 시간. 계획서 §5.4 기준 각 1초 안에 완결한다.
local CLEAR_HOLD = 0.9
local FAIL_HOLD = 1.0

-- 앉았을 때 HumanoidRootPart 가 좌석면 위로 뜨는 높이
local SIT_RISE = 1.4

-- 방해물이 켜지는 반. 1~5반은 순수하게 규칙만 배우는 구간이다.
local OBSTACLE_FROM_CLASS = 6

--[[
	고자질하는 학생이 처음 등장하는 반. 방해물(6반)보다 뒤에 둔다 —
	방해물은 길을 좁힐 뿐이지만 이 학생은 규칙을 하나 더 만든다.
	새 규칙은 한 번에 하나씩 와야 무엇 때문에 잡혔는지 알 수 있다.
]]
local SNITCH_FROM_CLASS = 9

--[[
	이번 반에 고자질하는 학생을 몇 명 둘 것인가.

	★ 최대 2명이다. 3명이 되는 순간 교실이 "지나갈 수 있는 길"이 아니라
	  "지나갈 수 없는 벽"이 된다. 이 학생들은 길을 없애는 장치가 아니라
	  길을 고르게 만드는 장치라, 언제나 우회로가 남아 있어야 한다.

	★ 학년이 오를 때 1명으로 되돌리지 않는다. 방해물·지정석과 같은 규칙이다 —
	  한 번 배운 것은 계속 있고, 학년은 그 위에 얹는다.
]]
local function snitchCount(profile): number
	if profile.grade == 1 then
		return if profile.class >= SNITCH_FROM_CLASS then 1 else 0
	end
	return if profile.grade >= 4 then 2 else 1
end

-- 학년 최초 수료 보너스. 반 클리어 12 + 퍼펙트 12 + 이것 3 = 27 이 1학년 전체 예산이고,
-- 업그레이드 총액 30 보다 적다. 전부 살 수 없어야 선택이 선택이 된다.
-- 학년이 6개가 된 뒤에도 이 긴장은 1학년 안에서만 성립한다 — 2학년부터는 셋 다 살 수 있다.
-- 처음 12반이 "무엇을 포기할 것인가"의 구간이고, 그 뒤는 갖춰가는 구간이다.
local GRADE_BONUS = 3

-- 허브 ↔ 교실 전환에서 화면이 덮여 있는 시간.
-- 이 시간 동안 RequestStreamAroundAsync 가 끝나기를 기다린다 —
-- 신발을 갈아신는 연출이 로딩을 가리는 커버다.
local TRANSITION_HOLD = 0.55

local ProgressService = {}

local busy: { [Player]: boolean } = {}
local lastTrigger: { [Player]: number } = {}
local lastUpgrade: { [Player]: number } = {}

local function getParts(player: Player)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return nil, nil, nil
	end
	return character, humanoid, hrp
end

--[[
	HUD 와 클라이언트 이동 보정이 쓰는 스냅샷. 프로필 전체를 내려보내지 않는다 —
	cleared/perfect 표는 클라가 알 이유가 없고, 크기만 계속 자란다.
]]
local function pushProfile(player: Player, profile)
	--[[
		종까지 남은 시간은 "남은 초"로 보낸다. 절대 시각을 보내면 서버와 클라의
		os.clock() 기준점이 달라 계산이 안 되고, 시각을 맞추려면 핑을 재야 한다.
		남은 초는 그런 것 없이 그대로 쓸 수 있고, 이 패킷이 반 중간에 다시 나가도
		그때의 남은 시간이 실려 나가므로 클라 카운트다운이 저절로 다시 맞춰진다.

		★ 초 단위 갱신을 위해 이걸 매초 쏘지 않는다. 카운트다운은 클라가 혼자 세고,
		  판정은 서버가 자기 시계로 한다. 화면과 판정이 0.1초쯤 어긋나도
		  실패가 아니라 별 하나가 걸린 문제라 아무도 다치지 않는다.
	]]
	local session = ClassroomService.get(player)
	local bellSeconds = nil
	if session and session.bellAt then
		bellSeconds = math.max(0, session.bellAt - os.clock())
	end

	Remotes.ProfileUpdated:FireClient(player, {
		grade = profile.grade,
		class = profile.class,
		stars = profile.stars,
		upgrades = profile.upgrades,
		totalSeconds = profile.totalSeconds,
		bellSeconds = bellSeconds,
	})
end

--[[
	프로필의 업그레이드를 실제 수치에 반영한다. 세 가지 효과가 각각 다른 곳에서 쓰인다.

	  실내화(quietShoes) : 발소리 반경 — 서버 감지가 읽는다
	  눈치(instinct)     : 예고 신호를 0.1초 앞당긴다 — 선생님 설정으로 들어간다
	  균형감각(balance)  : 정지 거리 — 클라이언트 이동이 읽는다(pushProfile 로 나간다)

	★ 눈치는 판서에서 0.1초를 떼어 예고에 붙인다. 사이클 총 길이는 그대로다.
	  예고를 그냥 늘리면 난이도가 통째로 내려가서, 표에 적힌 반응 예산이 무의미해진다.
]]
local function applyUpgrades(session, profile)
	session.noiseRadius = MovementConfig.RUN_NOISE_RADIUS
		* (if profile.upgrades.quietShoes then Upgrades.QUIET_SHOES_RADIUS_SCALE else 1)

	local config = DifficultyTable.get(profile.grade, profile.class)
	if profile.upgrades.instinct then
		config.teachTime -= Upgrades.INSTINCT_LEAD
		config.warnTime += Upgrades.INSTINCT_LEAD
	end
	return config
end

--[[
	새 반을 연다. 입장 직후와 한 판이 끝난 직후, 두 곳에서만 부른다.
]]
local function beginClass(player: Player)
	local session = ClassroomService.get(player)
	local profile = DataService.get(player)
	if not session or not profile then
		return
	end

	TeacherAI.reset(session.teacher, applyUpgrades(session, profile))

	--[[
		교실에 이번 학년의 옷을 입힌다.

		★ 난이도를 바꾸는 줄(위의 TeacherAI.reset) 바로 옆에 둔다. 이 두 줄은
		  같은 것의 앞뒤다 — 선생님이 얼마나 빨리 도는지가 난이도이고,
		  칠판 문구와 벽 색과 아이들 체구는 그 난이도의 얼굴이다.
		  떨어뜨려 놓으면 한쪽만 고치는 커밋이 반드시 생기고, 그때 플레이어는
		  3학년 교실에서 5학년 선생님을 만난다.
	]]
	ClassroomService.setGrade(session, profile.grade, profile.class)

	-- 방해물은 1학년 6반에서 처음 켜고 그 뒤로는 끄지 않는다.
	-- 학년마다 1반에서 다시 꺼버리면 2학년 1반이 방금 깬 1학년 12반보다 쉬워진다.
	ClassroomService.setObstacles(session, profile.grade > 1 or profile.class >= OBSTACLE_FROM_CLASS)

	-- 내 자리가 문에서 멀어지는 속도. 방해물과 같은 규칙이라 학년이 바뀌어도 되돌리지 않는다.
	-- 1학년 안에서만 1반 문 앞 → 12반 교실 전체로 벌어진다.
	local reach = if profile.grade > 1 then 1 else (profile.class - 1) / (DifficultyTable.CLASSES_PER_GRADE - 1)
	ClassroomService.reroll(session, reach)
	-- reroll 다음이어야 한다. 앉아 있는 자리 중에서 뽑으므로 누가 비었는지가 먼저 정해져야 한다.
	ClassroomService.setSnitches(session, snitchCount(profile))

	session.caughtInClass = 0
	session.classStartedAt = os.clock()

	--[[
		종을 건다. classStartedAt 과 같은 시각에서 출발하지만 둘은 다른 것을 잰다 —
		classStartedAt 은 잡혀서 다시 시작해도 계속 흐르는 "이 반에 쓴 시간"(랭킹용)이고,
		bellAt 은 이번 반의 마감이다.

		★ 잡혀도 종은 다시 걸지 않는다. 다시 걸면 일부러 잡혀서 시계를 되돌리는 길이 열린다.
		  그리고 어차피 한 번 잡히면 퍼펙트는 이미 날아간 뒤라 종을 되돌릴 이유도 없다.
	]]
	session.bellAt = os.clock() + DifficultyTable.bellTime(profile.grade, profile.class)

	profile.attempts += 1
	pushProfile(player, profile)
end

--[[
	연출이 끝나면 문 앞으로 되돌린다. 성공이든 실패든 다음 판의 출발점은 같다.
	DetectionService.forget 을 텔레포트 "직후"에 부른다 — 이걸 빠뜨리면
	순간이동한 거리가 다음 틱에 델타로 잡혀 곧바로 재적발된다.
]]
local function release(player: Player)
	busy[player] = nil

	local session = ClassroomService.get(player)
	local character, humanoid, hrp = getParts(player)
	if not character or not session then
		return
	end

	hrp.Anchored = false
	humanoid.Sit = false
	character:PivotTo(session.doorCFrame)
	DetectionService.forget(player)
end

local function freeze(player: Player)
	busy[player] = true
	DetectionService.forget(player)
end

function ProgressService.fail(player: Player, reason: string)
	if busy[player] then
		return
	end

	local _, _, hrp = getParts(player)
	if not hrp then
		return
	end

	local session = ClassroomService.get(player)
	local profile = DataService.get(player)
	if not session or not session.inClass then
		return -- 허브에 있다. 잡힐 수 있는 곳이 아니다
	end
	if profile then
		-- 한 번이라도 잡히면 이번 반의 퍼펙트는 날아간다. 다음 반에서 다시 노리면 된다.
		session.caughtInClass += 1
		profile.caught += 1
	end

	freeze(player)
	-- 그 자리에 못박는다. "화면 정지"는 연출이 아니라 실제 정지여야 억울함이 없다 —
	-- 정지 화면 뒤에서 캐릭터가 계속 미끄러지면 부활 위치가 매번 달라진다.
	hrp.Anchored = true

	Remotes.Caught:FireClient(player, reason)
	task.delay(FAIL_HOLD, release, player)
end

--[[
	별을 주고 반을 넘긴다. 별은 "처음 클리어"에만 나간다 —
	1반을 12번 돌아 별을 무한히 버는 길을 막는다.
]]
local function award(session, profile): (number, boolean)
	local key = `{profile.grade}-{profile.class}`
	local gained = 0

	if not profile.cleared[key] then
		profile.cleared[key] = true
		gained += 1
	end

	--[[
		퍼펙트 = 한 번도 안 잡혔고, 종이 울리기 전에 앉았다.

		★ 별 하나를 새로 만들지 않고 기존 퍼펙트 조건에 얹는 이유는 예산 때문이다.
		  한 학년의 별은 반 클리어 12 + 퍼펙트 12 + 수료 3 = 27 이고, 업그레이드 총액 30
		  보다 적어야 "무엇을 포기할 것인가"가 성립한다. 시간 별을 따로 주면 39가 되어
		  1학년만 돌아도 셋 다 살 수 있게 되고, 그 순간 상점이 상점이 아니게 된다.

		★ 대신 퍼펙트가 어려워진다. 그게 노린 것이다 — 안 잡히는 것만으로 별이 나오면
		  느리게 갈수록 유리하고, 그러면 살금살금 말고는 아무도 쓰지 않는다.
	]]
	local perfect = session.caughtInClass == 0 and (session.bellAt == nil or os.clock() <= session.bellAt)
	if perfect and not profile.perfect[key] then
		profile.perfect[key] = true
		gained += 1
	end

	-- 누적 시간은 반 시작부터 잰다. 중간에 잡혀 다시 시도한 시간도 전부 포함된다 —
	-- 랭킹이 "졸업까지 걸린 시간"이므로 실패한 시간도 실력이다.
	profile.totalSeconds += os.clock() - session.classStartedAt
	profile.stars += gained

	return gained, perfect
end

local function clear(player: Player, session, seat: BasePart)
	local _, humanoid, hrp = getParts(player)
	if not hrp then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	freeze(player)

	-- 좌석에 앉힌 자세로 고정한다. 앉는 순간이 곧 클리어이므로 되돌릴 여지를 두지 않는다.
	hrp.CFrame = CFrame.new(seat.Position + Vector3.new(0, SIT_RISE, 0))
	humanoid.Sit = true
	hrp.Anchored = true

	local grade, class = profile.grade, profile.class
	local gained, perfect = award(session, profile)

	local isLastClass = class >= DifficultyTable.CLASSES_PER_GRADE
	local gradeKey = tostring(grade)
	if isLastClass and not profile.gradeCleared[gradeKey] then
		profile.gradeCleared[gradeKey] = true
		profile.stars += GRADE_BONUS
		gained += GRADE_BONUS
	end

	Remotes.ClassCleared:FireClient(player, {
		grade = grade,
		class = class,
		seat = seat:GetAttribute("Index"),
		stars = gained,
		perfect = perfect,
	})

	task.delay(CLEAR_HOLD, function()
		release(player)

		if isLastClass then
			--[[
				12반을 깼다. 다음 학년 표가 있으면 그 학년 1반으로 올라간다.

				★ 학년을 넘기는 곳은 여기 한 줄뿐이다. 예전에는 이 줄이 없어서
				  "1학년 수료" 배너만 뜨고 반은 12 에 그대로 남았다 —
				  수료했다고 말해놓고 같은 12반을 다시 열어주는 상태였다.

				★ 마지막 학년(표에 다음 항목이 없는 학년)이면 그대로 둔다.
				  별은 이미 준 반에서 다시 나오지 않으므로 반복해도 이득이 없다.
			]]
			if DifficultyTable.has(grade + 1) then
				profile.grade = grade + 1
				profile.class = 1
			end

			Remotes.GradeCleared:FireClient(player, {
				grade = grade,
				totalSeconds = profile.totalSeconds,
				stars = profile.stars,
			})
			-- 운동장으로 나가는 동안 HUD 가 이미 다음 학년을 가리켜야 한다.
			-- 다음 pushProfile 은 교실에 다시 들어갈 때라, 그때까지 기다리면
			-- 운동장에 서 있는 내내 방금 끝낸 반이 좌상단에 남는다.
			pushProfile(player, profile)
			DataService.save(player) -- 잃으면 가장 아까운 순간

			-- 수료했으면 운동장으로 내보낸다. 모아둔 별을 쓸 곳이 거기에 있고,
			-- 12반 문 앞에 그대로 세워두면 방금 끝난 것이 끝난 것으로 안 읽힌다.
			ProgressService.exitToHub(player)
			return
		end

		profile.class = class + 1
		beginClass(player)
	end)
end

--[[
	ProximityPrompt 가 발화했을 때 호출된다.
	여기가 클라이언트 입력이 서버 상태를 바꾸는 유일한 지점이므로, 검증은 전부 여기 모은다.
]]
function ProgressService.onSeatTriggered(player: Player, seat: BasePart)
	local now = os.clock()

	-- (1) 레이트 리밋. 프롬프트 연타/스팸으로 서버를 흔들지 못하게 한다
	local last = lastTrigger[player]
	if last and now - last < TRIGGER_INTERVAL then
		return
	end
	lastTrigger[player] = now

	-- (2) 이미 성공/실패 연출 중이면 무시. 이중 클리어를 막는다
	if busy[player] then
		return
	end

	-- (3) 내 교실의 좌석인가. 프롬프트는 원격으로 발화시킬 수 있으므로
	--     소유권을 서버가 직접 확인한다
	local session = ClassroomService.get(player)
	if not session or not session.inClass or not seat:IsDescendantOf(session.model) then
		return
	end

	-- (4) 빈자리인가. 서버만 아는 값이다
	if not ClassroomService.isEmpty(seat) then
		return
	end

	-- (5) 캐릭터가 살아있는가
	local _, _, hrp = getParts(player)
	if not hrp then
		return
	end

	-- (6) 실제로 그 자리 앞에 있는가.
	--     NaN 을 먼저 거른다 — NaN 은 어떤 비교에도 false 를 돌려주므로
	--     ">" 검사만으로는 통과해버린다.
	local dist = (hrp.Position - seat.Position).Magnitude
	if dist ~= dist or dist > SIT_RANGE then
		return
	end

	--[[
		(7) 내 자리인가. 여기서 처음으로 "무시"가 아니라 "실패"가 된다.

		★ 거리 검사 뒤에 두는 순서가 중요하다. 앞에 두면 프롬프트를 원격으로 발화시켜
		  교실 반대편에 서 있는 사람을 실패시킬 수 있다 — 남이 나를 잡는 길이 열린다.
		  실제로 그 자리 앞까지 걸어간 사람만 이 줄에 닿아야 한다.

		★ 무시하지 않고 실패시키는 이유는 함정이 함정이려면 대가가 있어야 하기 때문이다.
		  아무 일도 안 일어나면 플레이어는 빈자리를 순서대로 눌러보며 정답을 찾는다 —
		  관찰이 시행착오로 바뀐다. 프롬프트에 "빈자리"라고 미리 적혀 있으므로
		  이 실패는 속은 것이 아니라 안 읽은 것이다.
	]]
	if not ClassroomService.isAssigned(session, seat) then
		ProgressService.fail(player, "wrong_seat")
		return
	end

	clear(player, session, seat)
end

--[[
	문구점 매대에서 업그레이드를 산다.

	키는 서버가 매대에 미리 묶어둔 값이라 위조할 여지가 없지만, 가격·보유 여부·잔액은
	여전히 서버가 자기 표에서 다시 읽는다. 프롬프트는 원격으로 발화시킬 수 있으므로
	"어느 매대를 눌렀나"는 신뢰해도 "살 수 있나"는 신뢰하지 않는다.

	거절 사유를 Notice 로 돌려주는 이유는 상점이 12명 공용이기 때문이다.
	매대를 사람마다 꺼둘 수 없으니, 눌렀을 때 이유를 말해주는 수밖에 없다.
]]
function ProgressService.onUpgradeRequested(player: Player, key: string)
	local now = os.clock()
	local last = lastUpgrade[player]
	if last and now - last < UPGRADE_INTERVAL then
		return
	end
	lastUpgrade[player] = now

	if not Upgrades.exists(key) then
		return
	end

	local profile = DataService.get(player)
	local session = ClassroomService.get(player)
	if not profile or not session then
		return
	end

	local def = Upgrades.DEFS[key]

	if profile.upgrades[key] then
		Remotes.Notice:FireClient(player, `{def.name}은(는) 이미 가지고 있다`)
		return
	end

	local cost = Upgrades.cost(key)
	if profile.stars < cost then
		Remotes.Notice:FireClient(player, `★{cost - profile.stars}개가 모자란다`)
		return
	end

	profile.stars -= cost
	profile.upgrades[key] = true

	--[[
		산 즉시 효과가 붙어야 한다. 다음 반까지 기다리면 산 게 맞는지 알 수 없다.
		다만 선생님 사이클은 다시 돌리지 않는다 — 판서 중에 사이클이 리셋되면
		예고를 기다리던 플레이어가 영문 모르고 죽는다.
		교실 밖(허브)에서 샀다면 설정만 갈아둔다. 어차피 입장할 때 beginClass 가 다시 조립한다.
	]]
	if session.inClass then
		TeacherAI.setConfig(session.teacher, applyUpgrades(session, profile))
	else
		applyUpgrades(session, profile)
	end

	Remotes.Notice:FireClient(player, `{def.name} 구입! {def.desc}`)
	pushProfile(player, profile)
end

--[[
	신발장 → 교실. 화면을 덮고, 그 뒤에서 스트리밍을 기다린 다음 옮긴다.

	ProximityPrompt.Triggered 는 자기 스레드에서 돌기 때문에 여기서 양보해도 안전하다.
	busy 를 먼저 잡는 이유는 전환 도중 신발장을 또 누르는 것을 막기 위해서다.
]]
function ProgressService.enterClass(player: Player)
	local session = ClassroomService.get(player)
	if not session or session.inClass or busy[player] then
		return
	end
	busy[player] = true

	Remotes.Transition:FireClient(player, { to = "class" })
	task.wait(TRANSITION_HOLD)

	-- 교실 바닥이 아직 안 내려와 있으면 그대로 떨어진다. 입장 때와 같은 이유다.
	pcall(function()
		player:RequestStreamAroundAsync(session.doorCFrame.Position)
	end)

	-- 기다리는 동안 나갔거나 죽었을 수 있다
	local character = player.Character
	if not player:IsDescendantOf(Players) or not character or ClassroomService.get(player) ~= session then
		busy[player] = nil
		return
	end

	-- 교실 안에서 캐릭터를 리셋하면 교실 스폰으로 돌아와야 한다.
	-- 허브 스폰인 채로 두면 운동장에 서 있는데 판이 계속 도는 상태가 된다.
	player.RespawnLocation = session.spawn

	beginClass(player)
	character:PivotTo(session.doorCFrame)
	DetectionService.forget(player)

	-- 감지를 켜는 것은 맨 마지막이다. 텔레포트 델타가 잡히지 않도록 forget 다음에 온다.
	session.inClass = true
	busy[player] = nil
end

--[[
	교실 → 운동장. 잡히는 중이거나 클리어 연출 중이면 무시한다.
]]
function ProgressService.exitToHub(player: Player)
	local session = ClassroomService.get(player)
	if not session or not session.inClass or busy[player] then
		return
	end
	busy[player] = true

	-- 감지부터 끈다. 화면이 덮인 뒤에 잡히면 사유도 못 보고 죽는다.
	session.inClass = false
	-- 운동장에는 울릴 종이 없다. 지워두지 않으면 다음 프로필 갱신에
	-- 방금 끝낸 반의 남은 시간이 실려 나간다.
	session.bellAt = nil
	DetectionService.forget(player)
	player.RespawnLocation = PlaygroundService.spawn()

	Remotes.Transition:FireClient(player, { to = "hub" })
	task.wait(TRANSITION_HOLD)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.Anchored = false
		end
		character:PivotTo(PlaygroundService.returnCFrame())
	end

	busy[player] = nil
end

--[[
	입장. 프로필 → 교실 슬롯 → 운동장 스폰 순서를 지킨다.

	★ Phase 5 부터 첫 화면은 교실이 아니라 운동장이다.
	  교실 슬롯은 여기서 미리 잡아두되(자리가 없으면 아예 못 들어오게 한다),
	  실제로 들어가는 것은 신발장을 눌렀을 때다.

	★ CharacterAdded 를 잡아 텔레포트하는 대신 RespawnLocation 을 쓴다.
	  캐릭터가 붙는 시점과 텔레포트가 경주하면, 진 쪽에서 플레이어가
	  0.5초쯤 원점 상공에 떠 있다가 옮겨진다. 로블록스 기본 리스폰 규칙에
	  맡기면 그 경주 자체가 없어진다.
]]
local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)
	if not profile then
		return -- load 안에서 이미 킥했다
	end

	local session = ClassroomService.acquire(player)
	if not session then
		player:Kick("교실이 모두 찼습니다. 잠시 후 다시 들어와 주세요.")
		DataService.release(player)
		return
	end

	local spawnPoint = PlaygroundService.spawn()
	player.RespawnLocation = spawnPoint

	-- 캐릭터를 붙이기 전에 그 주변을 먼저 내려보낸다.
	-- 이걸 빼면 바닥이 아직 없는 곳에 스폰해 그대로 떨어진다.
	pcall(function()
		player:RequestStreamAroundAsync(spawnPoint.Position)
	end)

	if not player:IsDescendantOf(Players) then
		return -- 로딩 중에 나갔다. PlayerRemoving 이 뒷정리를 한다
	end

	-- 교실은 아직 열지 않는다. 다만 HUD 가 "1학년 3반 · ★5"를 바로 띄우려면
	-- 프로필 스냅샷은 지금 보내야 한다.
	applyUpgrades(session, profile)
	pushProfile(player, profile)
	player:LoadCharacterAsync()
end

local function onPlayerRemoving(player: Player)
	busy[player] = nil
	lastTrigger[player] = nil
	lastUpgrade[player] = nil

	ClassroomService.release(player)
	DataService.release(player)
end

function ProgressService.Start()
	-- 교실 슬롯을 배정받기 전에는 캐릭터를 붙이지 않는다.
	Players.CharacterAutoLoads = false

	ClassroomService.setTriggerHandler(ProgressService.onSeatTriggered)
	ClassroomService.setExitHandler(ProgressService.exitToHub)
	DetectionService.setCaughtHandler(ProgressService.fail)

	PlaygroundService.setEnterHandler(ProgressService.enterClass)
	PlaygroundService.setBuyHandler(ProgressService.onUpgradeRequested)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- 부트스트랩보다 먼저 들어온 플레이어가 있을 수 있다. 스튜디오에서는 거의 항상이다.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
end

return ProgressService
