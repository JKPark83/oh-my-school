--!strict
--[[
	W7 아이 테스트 로그. 기획서 §13.1 7주차·§13.3·§2.4. 저장하지 않는 세션 표와 서버 print("[Metrics] …") 뿐이다.
	세션은 프로필 로드·부지 할당 직후(begin)부터 퇴장(finish)까지다. 졸업해도 끊기지 않는다.
	  회수율        주운 스티커 / 기회. 기회 = Σ(켜진 스폰 수 × 초) / RESPAWN.
	                sim-final.py COLLECT_RATE 와 같은 뜻이다(스폰마다 다시 뜨자마자 주우면 100%).
	                "뜬 횟수"로 나누지 않는다. 안 주운 스티커는 다시 뜨지 않아 분모가 분자를 따라가기 때문이다.
	  5분 완료      5:00 에 부품·시설·전학생(중복 제외)·뽑기로 온 새 학생·뽑기·미션을 찍고 §2.4·개선계획 §13.1 기준으로 판정
	  30분 시설     30:00 의 시설 수 + 누적 졸업. 이번 세션에 졸업했으면 14/14 를 이미 지난 것으로 본다
	  첫 뽑기       세션 시작부터 첫 뽑기까지. 일어난 순간 찍는다
	  패드 3초 미만 활성 패드 Touched 로 관찰을 시작해 0.25초마다 구매 판정과 같은 기준(PlotService.standsOn)으로 본다.
	                위에 올라섰다가 3초 안에 내려왔고 그 사이 구매가 없으면 +1. 그중 내려올 때 살 돈이 있던 횟수도 센다
	뽑기·새 학생·미션은 이번 세션에서 센 값, 시설·전학생 수는 그 순간의 프로필 값이다.
	다른 서비스는 O(1) 함수만 부른다. 1Hz 경제 틱 안에서는 카운터만 바꾼다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local DataService = require(script.Parent.Services.DataService)
local PlotService = require(script.Parent.Services.PlotService)

local Metrics = {}

-- 게임 수치가 아니라 W7 게이트(§2.4·§13.1)라 Config 가 아닌 여기 둔다
local FIVE_MINUTES = 5 * 60
local THIRTY_MINUTES = 30 * 60
local FIRST_PULL_GOAL = 2 * 60
local FIVE_PARTS = 24 -- 첫 5분 부품 수(개선계획 §13.1)
local FIVE_STUDENTS = 8
local FIVE_PULLS = 4
local FIVE_MISSIONS = 2
local SHORT_STAY = 3 -- 초. 이보다 짧게 서 있다 내려오면 센다(§13.3)
local PAD_POLL = 0.25 -- 초. 패드 근처에 있는 동안만 도는 확인 주기
local PAD_GRACE = 1 -- 초. Touched 뒤 이 안에 패드 위로 안 올라오면 스친 것으로 본다

type Session = {
	startedAt: number,
	isNew: boolean,
	collected: number,
	spawns: number, -- 지금 켜진 스티커 스폰 수
	spawnSince: number,
	spawnSeconds: number, -- Σ 스폰 수 × 초
	pulls: number,
	gachaNew: number, -- 뽑기로 온 새 학생(중복 제외)
	firstPullAt: number?,
	missions: number,
	graduations: number,
	passedFive: boolean?, -- nil = 5분 전
	atThirty: string?, -- nil = 30분 전
	shortStays: number,
	shortAffordable: number,
	padWatching: boolean,
	padBought: boolean,
	fiveTimer: thread?,
	thirtyTimer: thread?,
}

local sessions: { [Player]: Session } = {}

local function clock(seconds: number): string
	local s = math.floor(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

local function log(player: Player, text: string)
	print(`[Metrics] {player.DisplayName}({player.UserId}) {text}`)
end

local function kind(session: Session): string
	return if session.isNew then "새 계정" else "기존 계정"
end

local function verdict(passed: boolean): string
	return if passed then "통과" else "미달"
end

--- 지금까지의 스폰 × 초를 쌓고 스폰 수를 바꾼다
local function setSpawns(session: Session, count: number)
	local now = os.clock()
	session.spawnSeconds += session.spawns * (now - session.spawnSince)
	session.spawns = count
	session.spawnSince = now
end

--- 다음 부품 값이 지금 용돈으로 되나
local function canAfford(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
	return nextPart ~= nil
		and profile.coins >= FacilityConfig.partPriceOf(nextPart.facility.id, nextPart.index, profile.graduations)
end

local function snapshotFive(player: Player, session: Session)
	session.fiveTimer = nil
	local profile = DataService.get(player)
	if sessions[player] ~= session or not profile then
		return
	end
	local parts = FacilityConfig.partsBuilt(profile.facilities, profile.buildParts)
	local facilities = FacilityConfig.count(profile.facilities)
	local students = StudentConfig.ownedCount(profile.students)
	local passed = parts >= FIVE_PARTS
		and students >= FIVE_STUDENTS
		and session.gachaNew >= 1
		and session.pulls >= FIVE_PULLS
		and session.missions >= FIVE_MISSIONS
	session.passedFive = passed
	local counts =
		`부품 {parts}(≥{FIVE_PARTS}) · 시설 {facilities} · 전학생 {students}(≥{FIVE_STUDENTS}, 뽑기로 {session.gachaNew})`
	local actions = `뽑기 {session.pulls}(≥{FIVE_PULLS}) · 미션 {session.missions}(≥{FIVE_MISSIONS})`
	log(player, `5분 · {counts} · {actions} → {verdict(passed)} · {kind(session)}`)
end

local function snapshotThirty(player: Player, session: Session)
	session.thirtyTimer = nil
	local profile = DataService.get(player)
	if sessions[player] ~= session or not profile then
		return
	end
	local facilities = FacilityConfig.count(profile.facilities)
	local passed = facilities >= FacilityConfig.COUNT or session.graduations > 0
	local suffix = if session.graduations > 0 then `(졸업 {session.graduations}회)` else ""
	session.atThirty = `{facilities}/{FacilityConfig.COUNT}{suffix}`
	local grads = `누적 졸업 {profile.graduations}회(이번 세션 {session.graduations})`
	log(
		player,
		`30분 · 시설 {facilities}/{FacilityConfig.COUNT} · {grads} → {verdict(passed)} · {kind(session)}`
	)
end

--- 패드 위에 있는 동안만 돈다. 세션이 바뀌거나 내려오면 끝
local function watchPad(player: Player, session: Session, pad: BasePart)
	local started = os.clock()
	local since: number? = nil
	while sessions[player] == session do
		local now = os.clock()
		if PlotService.standsOn(player, pad) then
			if not since then
				since = now
				session.padBought = false
			end
		elseif since then
			if now - since < SHORT_STAY and not session.padBought then
				session.shortStays += 1
				if canAfford(player) then
					session.shortAffordable += 1
				end
			end
			break
		elseif now - started >= PAD_GRACE then
			break
		end
		task.wait(PAD_POLL)
	end
	session.padWatching = false
end

--- PlotService.PadTouched: 주인이 자기 활성 패드에 닿음
local function onPadTouched(player: Player, pad: BasePart)
	local session = sessions[player]
	if not session or session.padWatching then
		return
	end
	session.padWatching = true
	task.spawn(watchPad, player, session, pad)
end

--- 세션 시작. 프로필 로드·부지 할당 직후에 부른다
function Metrics.begin(player: Player)
	local profile = DataService.get(player)
	if not profile or sessions[player] then
		return
	end
	local now = os.clock()
	local facilities = FacilityConfig.count(profile.facilities)
	local parts = FacilityConfig.partsBuilt(profile.facilities, profile.buildParts)
	local session: Session = {
		startedAt = now,
		isNew = profile.graduations == 0 and parts == 0 and profile.stats.totalPulls == 0,
		collected = 0,
		spawns = EconomyConfig.spawnCount(profile.facilities, profile.buildParts),
		spawnSince = now,
		spawnSeconds = 0,
		pulls = 0,
		gachaNew = 0,
		firstPullAt = nil,
		missions = 0,
		graduations = 0,
		passedFive = nil,
		atThirty = nil,
		shortStays = 0,
		shortAffordable = 0,
		padWatching = false,
		padBought = false,
		fiveTimer = nil,
		thirtyTimer = nil,
	}
	sessions[player] = session
	session.fiveTimer = task.delay(FIVE_MINUTES, snapshotFive, player, session)
	session.thirtyTimer = task.delay(THIRTY_MINUTES, snapshotThirty, player, session)
	if session.isNew then
		log(player, "세션 시작 · 새 계정")
	else
		local state =
			`졸업 {profile.graduations} · 시설 {facilities}/{FacilityConfig.COUNT} · 누적 뽑기 {profile.stats.totalPulls}`
		log(player, `세션 시작 · 기존 계정({state})`)
	end
end

--- 퇴장. 남은 타이머를 끄고 한 줄 요약을 찍는다
function Metrics.finish(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if session.fiveTimer then
		task.cancel(session.fiveTimer)
	end
	if session.thirtyTimer then
		task.cancel(session.thirtyTimer)
	end
	setSpawns(session, 0)
	local chances = session.spawnSeconds / EconomyConfig.RESPAWN
	local percent = if chances > 0 then `{math.floor(session.collected / chances * 100 + 0.5)}%` else "-"
	local rate = `회수율 {percent}(주움 {session.collected} / 기회 {math.floor(chances + 0.5)})`
	local firstPull = `첫 뽑기 {if session.firstPullAt then clock(session.firstPullAt) else "없음"}`
	local five = if session.passedFive == nil then "5분 전 종료" else `5분 {verdict(session.passedFive)}`
	local thirty = if session.atThirty then `30분 시설 {session.atThirty}` else "30분 전 종료"
	local pads = `패드 3초 미만 {session.shortStays}회(살 돈 있었음 {session.shortAffordable})`
	local length = `세션 {clock(os.clock() - session.startedAt)}`
	log(player, `요약 · {kind(session)} · {length} · {rate} · {firstPull} · {five} · {thirty} · {pads}`)
end

--- 자기 부지 스티커 1장 주움(방문객 별 제외)
function Metrics.stickerCollected(player: Player)
	local session = sessions[player]
	if session then
		session.collected += 1
	end
end

--- 부품 1개 구매(프로필 갱신 뒤). 패드 3초 미만 판정의 「그 사이 구매」, 스폰 수는 프로필에서 다시 센다
function Metrics.partBuilt(player: Player)
	local session = sessions[player]
	local profile = DataService.get(player)
	if not session or not profile then
		return
	end
	session.padBought = true
	local spawns = EconomyConfig.spawnCount(profile.facilities, profile.buildParts)
	if spawns ~= session.spawns then
		setSpawns(session, spawns)
	end
end

--- 시설 1개 완공(마지막 부품). 스폰 수는 partBuilt 가 이미 맞췄다
function Metrics.facilityBuilt(player: Player)
	local session = sessions[player]
	if session then
		session.padBought = true
	end
end

--- 뽑기 1회 성공
function Metrics.gachaRolled(player: Player, isDupe: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	session.pulls += 1
	if not isDupe then
		session.gachaNew += 1
	end
	if session.firstPullAt == nil then
		local elapsed = os.clock() - session.startedAt
		session.firstPullAt = elapsed
		log(
			player,
			`첫 뽑기 {clock(elapsed)}(≤{clock(FIRST_PULL_GOAL)} {verdict(elapsed <= FIRST_PULL_GOAL)}) · {kind(
				session
			)}`
		)
	end
end

--- 일일 미션 1개 완료
function Metrics.missionDone(player: Player)
	local session = sessions[player]
	if session then
		session.missions += 1
	end
end

--- 졸업. 시설이 비어 스폰도 0 이 된다(철거까지 8초는 잠금이라 어차피 못 줍는다)
function Metrics.graduated(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.graduations += 1
	setSpawns(session, 0)
end

function Metrics.Start()
	PlotService.PadTouched:Connect(onPadTouched)
	-- Studio 정지·서버 종료 때는 PlayerRemoving 보다 먼저 닫힐 수 있어 남은 세션도 요약을 찍는다
	game:BindToClose(function()
		for player in sessions do
			Metrics.finish(player)
		end
	end)
end

return Metrics
