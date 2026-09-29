--!strict
--[[
	W7·W9 아이 테스트 로그. 기획서 §13.1 7·8주차·§13.3·§2.4, 개선계획 §5 W9. 저장하지 않는 세션 표와 서버 print("[Metrics] …") 뿐이다.
	세션은 프로필 로드·부지 할당 직후(begin)부터 퇴장(finish)까지다. 졸업해도 끊기지 않는다.
	  회수율        주운 스티커 / 기회. 기회 = Σ(켜진 스폰 수 × 초) / RESPAWN.
	                sim-final.py COLLECT_RATE 와 같은 뜻이다(스폰마다 다시 뜨자마자 주우면 100%).
	                "뜬 횟수"로 나누지 않는다. 안 주운 스티커는 다시 뜨지 않아 분모가 분자를 따라가기 때문이다.
	  5분 완료      5:00 에 부품·시설·미션·선물·꾸미기를 찍고 §2.4·개선계획 §13.1 기준으로 판정(꾸미기는 옛 뽑기 자리)
	  30분 시설     30:00 의 시설 수 + 누적 졸업. 이번 세션에 졸업했으면 14/14 를 이미 지난 것으로 본다
	  패드 3초 미만 활성 패드 Touched 로 관찰을 시작해 0.25초마다 구매 판정과 같은 기준(PlotService.standsOn)으로 본다.
	                위에 올라섰다가 3초 안에 내려왔고 그 사이 구매가 없으면 +1. 그중 내려올 때 살 돈이 있던 횟수도 센다
	미션·선물은 이번 세션에서 센 값, 부품·시설 수는 그 순간의 프로필 값이다.
	다른 서비스는 O(1) 함수만 부른다. 1Hz 경제 틱 안에서는 카운터만 바꾼다.
Metrics 는 DataService·PlotService·Config(+ UiMark 를 받으려고 Remotes·RemoteGuard)만 require 한다.
PlotService 는 Metrics 를 모른다(순환). 엘리베이터는 PlotService.ElevatorRode 시그널로 받는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteGuard = require(script.Parent.RemoteGuard)
local DataService = require(script.Parent.Services.DataService)
local PlotService = require(script.Parent.Services.PlotService)

local Metrics = {}

-- 게임 수치가 아니라 W7 게이트(§2.4·§13.1)라 Config 가 아닌 여기 둔다
local FIVE_MINUTES = 5 * 60
local THIRTY_MINUTES = 30 * 60
local FIVE_PARTS = 24 -- 첫 5분 부품 수(개선계획 §13.1)
local FIVE_MISSIONS = 2
local FIVE_GIFTS = 1 -- 첫 5분 선물판 선물 수
local FIVE_DECOR = 1 -- 첫 5분 꾸미기 배치 수(기획서 §2.4·개선계획 §5 W9, 옛 FIVE_PULLS 자리)
local SHORT_STAY = 3 -- 초. 이보다 짧게 서 있다 내려오면 센다(§13.3)
local PAD_POLL = 0.25 -- 초. 패드 근처에 있는 동안만 도는 확인 주기
local PAD_GRACE = 1 -- 초. Touched 뒤 이 안에 패드 위로 안 올라오면 스친 것으로 본다
local FLOOR_POLL = 1 -- 초. 층 체류 표본 주기(Heartbeat 가 아닌 task.wait)
local UI_MARK_COOLDOWN = 1 -- 초. UiMark 리모트
local UI_MARK_DECOR_TAP = "decorTap" -- UiMark 가 받는 유일한 key

type Session = {
	startedAt: number,
	isNew: boolean,
	collected: number,
	spawns: number, -- 지금 켜진 스티커 스폰 수
	spawnSince: number,
	spawnSeconds: number, -- Σ 스폰 수 × 초
	missions: number,
	gifts: number, -- 이번 세션에 연 선물판 선물
	graduations: number,
	passedFive: boolean?, -- nil = 5분 전
	atThirty: string?, -- nil = 30분 전
	shortStays: number,
	shortAffordable: number,
	padWatching: boolean,
	padBought: boolean,
	fiveTimer: thread?,
	thirtyTimer: thread?,
	lastPartAt: number, -- 직전 부품 구매(없으면 세션 시작)
	partGaps: { number }, -- 부품 구매 간격(초)
	firstDecorAt: number?, -- 세션 시작부터 초
	decorFive: number, -- 첫 5분 꾸미기 배치 수
	firstDecorTapAt: number?, -- 꾸미기 버튼 첫 탭. 세션 시작부터 초
	stickerSince: { [BasePart]: number }, -- 켜진(다시 뜬) os.clock
	stickerWaits: { number }, -- 리스폰→줍기(초)
	floorsBought: number,
	firstFloorAt: number?, -- 세션 시작부터 초
	elevatorRides: number,
	floorSeconds: { [number]: number }, -- 층 → 자기 부지 안 체류 초
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

local function clockOr(seconds: number?): string
	return if seconds then clock(seconds) else "-"
end

--- 중앙값·최대(정수 초). 목록을 복사해 정렬한다. 비었으면 nil
local function medianMax(list: { number }): (number?, number?)
	local n = #list
	if n == 0 then
		return nil, nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local mid = if n % 2 == 1 then sorted[(n + 1) // 2] else (sorted[n // 2] + sorted[n // 2 + 1]) / 2
	return math.floor(mid + 0.5), math.floor(sorted[n] + 0.5)
end

local function partGapText(session: Session): string
	local median, max = medianMax(session.partGaps)
	if not median then
		return "부품 간격 중앙값 -"
	end
	return `부품 간격 중앙값 {median}초(최대 {max}초, {#session.partGaps}회)`
end

local function stickerWaitText(session: Session): string
	local median = medianMax(session.stickerWaits)
	if not median then
		return "리스폰→줍기 중앙값 -"
	end
	return `리스폰→줍기 중앙값 {median}초({#session.stickerWaits}회)`
end

local function floorStayText(session: Session): string
	local upper = 0
	local longest: number? = nil
	for f, seconds in session.floorSeconds do
		if f >= 3 then
			upper += seconds
		end
		if not longest or seconds > session.floorSeconds[longest] then
			longest = f
		end
	end
	local one = clock(session.floorSeconds[1] or 0)
	local two = clock(session.floorSeconds[2] or 0)
	local top = if longest then `{longest}층` else "-"
	return `층 체류 1층 {one} · 2층 {two} · 3층+ {clock(upper)}(가장 오래 {top})`
end

--- 켜져 있고 안 주운 스티커 중 기록이 없는 것을 now 로 적는다(세션 시작 때)
local function trackActiveStickers(player: Player, session: Session, now: number)
	local plotId = PlotService.plotOf(player)
	if not plotId then
		return
	end
	for _, part in PlotService.activeStickers(plotId) do
		if not part:GetAttribute(Keys.ATTR_COLLECTED) and not session.stickerSince[part] then
			session.stickerSince[part] = now
		end
	end
end

--- 지금까지의 스폰 × 초를 쌓고 스폰 수를 바꾼다
local function setSpawns(session: Session, count: number)
	local now = os.clock()
	session.spawnSeconds += session.spawns * (now - session.spawnSince)
	session.spawns = count
	session.spawnSince = now
end

--- 다음 부품(14개 완공 뒤면 다음 층) 값이 지금 용돈으로 되나
local function canAfford(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
	if nextPart == nil then
		local n = if profile.facilities.auditorium then TowerConfig.nextFloor(profile.towerFloors) else nil
		return n ~= nil and profile.coins >= TowerConfig.priceOf(n, profile.graduations)
	end
	return profile.coins >= FacilityConfig.partPriceOf(nextPart.facility.id, nextPart.index, profile.graduations)
end

local function snapshotFive(player: Player, session: Session)
	session.fiveTimer = nil
	local profile = DataService.get(player)
	if sessions[player] ~= session or not profile then
		return
	end
	local parts = FacilityConfig.partsBuilt(profile.facilities, profile.buildParts)
	local facilities = FacilityConfig.count(profile.facilities)
	local passed = parts >= FIVE_PARTS
		and session.missions >= FIVE_MISSIONS
		and session.gifts >= FIVE_GIFTS
		and session.decorFive >= FIVE_DECOR
	session.passedFive = passed
	local counts = `부품 {parts}(≥{FIVE_PARTS}) · 시설 {facilities}`
	local actions = `미션 {session.missions}(≥{FIVE_MISSIONS}) · 선물 {session.gifts}(≥{FIVE_GIFTS})`
	local decor = `꾸미기 {session.decorFive}(≥{FIVE_DECOR}) · 첫 배치 {clockOr(session.firstDecorAt)}`
	local tap = `버튼 첫 탭 {clockOr(session.firstDecorTapAt)}`
	local result = `{verdict(passed)} · {kind(session)}`
	log(player, `5분 · {counts} · {actions} · {decor} · {tap} · {partGapText(session)} → {result}`)
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
		isNew = profile.graduations == 0 and parts == 0,
		collected = 0,
		spawns = EconomyConfig.spawnCount(profile.facilities, profile.buildParts),
		spawnSince = now,
		spawnSeconds = 0,
		missions = 0,
		gifts = 0,
		graduations = 0,
		passedFive = nil,
		atThirty = nil,
		shortStays = 0,
		shortAffordable = 0,
		padWatching = false,
		padBought = false,
		fiveTimer = nil,
		thirtyTimer = nil,
		lastPartAt = now,
		partGaps = {},
		firstDecorAt = nil,
		decorFive = 0,
		firstDecorTapAt = nil,
		stickerSince = {},
		stickerWaits = {},
		floorsBought = 0,
		firstFloorAt = nil,
		elevatorRides = 0,
		floorSeconds = {},
	}
	sessions[player] = session
	-- 세션 시작 때 이미 켜진 스폰은 지금 뜬 것으로 본다
	trackActiveStickers(player, session, now)
	session.fiveTimer = task.delay(FIVE_MINUTES, snapshotFive, player, session)
	session.thirtyTimer = task.delay(THIRTY_MINUTES, snapshotThirty, player, session)
	if session.isNew then
		log(player, "세션 시작 · 새 계정")
	else
		local state =
			`졸업 {profile.graduations} · 시설 {facilities}/{FacilityConfig.COUNT} · 누적 선물 {profile.giftIndex}`
		log(player, `세션 시작 · 기존 계정({state})`)
	end
end

--- 한 줄 요약. 세션을 바꾸지 않는다(summaryNow 도 쓴다)
local function summaryText(session: Session): string
	local now = os.clock()
	local spawnSeconds = session.spawnSeconds + session.spawns * (now - session.spawnSince)
	local chances = spawnSeconds / EconomyConfig.RESPAWN
	local percent = if chances > 0 then `{math.floor(session.collected / chances * 100 + 0.5)}%` else "-"
	local rate = `회수율 {percent}(주움 {session.collected} / 기회 {math.floor(chances + 0.5)})`
	local five = if session.passedFive == nil then "5분 전 종료" else `5분 {verdict(session.passedFive)}`
	local thirty = if session.atThirty then `30분 시설 {session.atThirty}` else "30분 전 종료"
	local pads = `패드 3초 미만 {session.shortStays}회(살 돈 있었음 {session.shortAffordable})`
	local length = `세션 {clock(now - session.startedAt)}`
	local decor =
		`꾸미기 첫 배치 {clockOr(session.firstDecorAt)} · 버튼 첫 탭 {clockOr(session.firstDecorTapAt)}`
	local floors =
		`층 구매 {session.floorsBought}회(첫 {clockOr(session.firstFloorAt)}) · 엘리베이터 {session.elevatorRides}회`
	return table.concat({
		kind(session),
		length,
		rate,
		five,
		thirty,
		pads,
		partGapText(session),
		stickerWaitText(session),
		decor,
		floors,
		floorStayText(session),
	}, " · ")
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
	log(player, `요약 · {summaryText(session)}`)
end

--- 세션을 끝내지 않고 지금까지 요약을 찍는다(DevCheat.MetricsNow. 5분·30분 타이머는 실시간이라 게이트가 못 기다린다)
function Metrics.summaryNow(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	log(player, `지금까지 요약 · {summaryText(session)}`)
	return true
end

--- 자기 부지 스티커 1장 주움(방문객 별 제외). 켜진 기록이 있으면 걸린 초를 목록에 넣는다
function Metrics.stickerCollected(player: Player, part: BasePart)
	local session = sessions[player]
	if not session then
		return
	end
	session.collected += 1
	local since = session.stickerSince[part]
	if since then
		session.stickerSince[part] = nil
		table.insert(session.stickerWaits, os.clock() - since)
	end
end

--- 스티커가 다시 켜짐(EconomyService.respawnSticker)
function Metrics.stickerSpawned(player: Player, part: BasePart)
	local session = sessions[player]
	if session then
		session.stickerSince[part] = os.clock()
	end
end

--- 부품 1개 구매(프로필 갱신 뒤). 패드 3초 미만 판정의 「그 사이 구매」, 스폰 수는 프로필에서 다시 센다
function Metrics.partBuilt(player: Player)
	local session = sessions[player]
	local profile = DataService.get(player)
	if not session or not profile then
		return
	end
	local now = os.clock()
	session.padBought = true
	table.insert(session.partGaps, now - session.lastPartAt)
	session.lastPartAt = now
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

--- 선물판 선물 1개 열림(GiftBoard)
function Metrics.giftOpened(player: Player)
	local session = sessions[player]
	if session then
		session.gifts += 1
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
	-- 철거로 꺼진 스폰의 기록을 버린다. 다시 지어 새로 켜진 스폰은 세지 않고 다시 뜰 때(stickerSpawned)부터 센다
	table.clear(session.stickerSince)
end

--- 꾸미기 1개 배치(DecorService place 성공. 옮기기는 안 센다)
function Metrics.decorPlaced(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local elapsed = os.clock() - session.startedAt
	if not session.firstDecorAt then
		session.firstDecorAt = elapsed
	end
	if elapsed < FIVE_MINUTES then
		session.decorFive += 1
	end
end

--- 탑 층 1개 구매(EconomyService.buyFloor)
function Metrics.floorBuilt(player: Player, _n: number)
	local session = sessions[player]
	if not session then
		return
	end
	session.padBought = true
	session.floorsBought += 1
	if not session.firstFloorAt then
		session.firstFloorAt = os.clock() - session.startedAt
	end
end

--- PlotService.ElevatorRode: 엘리베이터로 옮겨짐(탄 사람 기준, 방문객도)
local function onElevatorRode(player: Player)
	local session = sessions[player]
	if session then
		session.elevatorRides += 1
	end
end

--- UiMark(key). "decorTap" 만 받고 세션당 첫 값만 적는다. 나머지 key 는 조용히 무시
local function onUiMark(player: Player, key: string)
	local session = sessions[player]
	if not session or key ~= UI_MARK_DECOR_TAP or session.firstDecorTapAt then
		return
	end
	session.firstDecorTapAt = os.clock() - session.startedAt
end

--- 1초 표본 1회. 자기 부지 안에 있을 때만 루트 층에 +1초
local function sampleFloors()
	for player, session in sessions do
		local plotId = PlotService.plotOf(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not plotId or not root or not root:IsA("BasePart") then
			continue
		end
		local p = PlotService.cframe(plotId):PointToObjectSpace(root.Position)
		local half = PlotLayout.PLOT_HALF
		if math.abs(p.X) <= half and math.abs(p.Z) <= half then
			local f = PlotLayout.floorOf(p.Y)
			-- 2층은 탑 발자국 안(강당)만. 밖의 지붕·담장 위는 1층으로 센다(CameraController 와 같은 판정)
			local foot = PlotLayout.TOWER_FOOTPRINT
			if f == 2 and not (p.X >= foot.x0 and p.X <= foot.x1 and p.Z >= foot.z0 and p.Z <= foot.z1) then
				f = 1
			end
			session.floorSeconds[f] = (session.floorSeconds[f] or 0) + FLOOR_POLL
		end
	end
end

function Metrics.Start()
	PlotService.PadTouched:Connect(onPadTouched)
	PlotService.ElevatorRode:Connect(onElevatorRode)
	-- UiMark 는 소유 서비스가 없어 여기서 받는다(RemoteGuard 의 SetSetting 과 같은 이유)
	RemoteGuard.wrap(Remotes.UiMark, { cooldown = UI_MARK_COOLDOWN, args = { "string" } }, onUiMark)
	task.spawn(function()
		while true do
			task.wait(FLOOR_POLL)
			local ok, err = pcall(function()
				sampleFloors()
			end)
			if not ok then
				warn(`[Metrics] 층 체류 표본 실패: {err}`)
			end
		end
	end)
	-- Studio 정지·서버 종료 때는 PlayerRemoving 보다 먼저 닫힐 수 있어 남은 세션도 요약을 찍는다
	game:BindToClose(function()
		for player in sessions do
			Metrics.finish(player)
		end
	end)
end

return Metrics
