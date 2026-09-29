--!strict
--[[
	졸업. 기획서 §6.1·§6.2.
	  Graduate 리모트(쿨다운 10초) → 검증(14/14, 잠금 아님, 마지막 졸업 후 10초)
	  → PlotService.lock → 프로필 원자적 변경(yield 없음): graduations += 1, facilities = {}, buildParts = 0, coins = 10 × 1.35^N,
	    졸업 확정 학생(1회 s18, 5회 s23) grant. tickets·board·pity·missions 유지
	  → 즉시 저장 요청 → (요청이 받아들여지면) 리더보드 → Graduated 전체 방송 → ProfileSync
	  → 8.0초 뒤 잠금 해제 + 월드 철거(teardown). 부지 어트리뷰트도 이때 바뀐다. 퇴장하면 flush() 로 즉시 철거.
	8초는 클라이언트 졸업식 연출(§9.5)을 위한 대기일 뿐 프로필과 무관하다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local PlotService = require(script.Parent.PlotService)
local StudentService = require(script.Parent.StudentService)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local Metrics = require(script.Parent.Parent.Metrics)

local GraduationService = {}

-- TODO(통합): 기획서 §6.1 수치. 전용 Config 가 생기면 옮긴다.
local GRADUATE_COOLDOWN = 10 -- 초. 마지막 졸업 후
local TEARDOWN_DELAY = 8.0 -- 초. 클라 졸업식 완전 검정 시점

local lastGraduation: { [Player]: number } = {}
local pendingTeardown: { [Player]: thread } = {}

local function finish(player: Player)
	pendingTeardown[player] = nil
	-- 잠금을 먼저 풀어야 teardown 의 syncAttributes 가 어트리뷰트를 쓴다
	PlotService.lock(player, false)
	PlotService.teardown(player)
end

local function graduate(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if FacilityConfig.count(profile.facilities) < FacilityConfig.COUNT then
		return
	end
	if PlotService.isLocked(player) then
		return
	end
	local now = os.clock()
	local last = lastGraduation[player]
	if last and now - last < GRADUATE_COOLDOWN then
		return
	end
	lastGraduation[player] = now
	-- 먼저 잠근다. 아래 grant 의 syncAttributes 가 빈 시설을 부지에 내보내지 않게
	PlotService.lock(player, true)

	-- 원자적 프로필 변경. 여기서 저장까지 yield 없음
	profile.graduations += 1
	local graduations = profile.graduations
	profile.facilities = {}
	profile.buildParts = 0
	profile.coins = EconomyConfig.startCoins(graduations)
	local newStudent = StudentConfig.byGraduation(graduations)
	if newStudent then
		StudentService.grant(player, newStudent.id, false)
	end
	Metrics.graduated(player)

	-- ProfileStore Save() 는 비동기라 성공 여부를 돌려주지 않는다. 요청이 거절되는 건 세션이 없을 때뿐이고,
	-- 그러면 이 졸업은 저장되지 않으니 리더보드에도 올리지 않는다. 일시 오류는 ProfileStore 자동 저장이 다시 시도한다
	if DataService.save(player) then
		LeaderboardService.submit(player, graduations)
	else
		warn(`[GraduationService] {player.UserId} 졸업 저장 요청 거절(세션 없음)`)
	end
	Remotes.event(nil, "Graduated", {
		plot = PlotService.plotOf(player) or 0,
		graduations = graduations,
		newStudentId = if newStudent then newStudent.id else nil,
	})
	-- 부지 어트리뷰트는 잠금 동안 그대로다(졸업식이 지금 학생을 쓴다). 철거 때 바뀐다
	DataService.syncNow(player)

	pendingTeardown[player] = task.delay(TEARDOWN_DELAY, finish, player)
end

--- 퇴장 시. 대기 중인 철거가 있으면 즉시 실행하고 세션 표를 비운다
function GraduationService.flush(player: Player)
	local thread = pendingTeardown[player]
	if thread then
		task.cancel(thread)
		finish(player)
	end
	lastGraduation[player] = nil
end

--- Graduate 핸들러 등록
function GraduationService.Start()
	RemoteGuard.wrap(Remotes.Graduate, { cooldown = GRADUATE_COOLDOWN, args = {} }, graduate)
end

return GraduationService
