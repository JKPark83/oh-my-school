--!strict
--[[
	졸업. 기획서 §6.1·§6.2.
	  Graduate 리모트(쿨다운 10초) → 검증(14/14, 잠금 아님, 마지막 졸업 후 10초)
	  → 프로필 원자적 변경(yield 없음): graduations += 1, facilities = {}, coins = 10 × 1.4^N,
	    졸업 확정 학생(1회 s18, 5회 s23) grant. skinsApplied·skinsOwned·tickets·board·pity·missions 유지
	  → PlotService.lock → 즉시 저장 → 리더보드 → Graduated 전체 방송 → 어트리뷰트·ProfileSync
	  → 8.0초 뒤 월드 철거(teardown) + 잠금 해제. 퇴장하면 flush() 로 즉시 철거.
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

local GraduationService = {}

-- TODO(통합): 기획서 §6.1 수치. 전용 Config 가 생기면 옮긴다.
local GRADUATE_COOLDOWN = 10 -- 초. 마지막 졸업 후
local TEARDOWN_DELAY = 8.0 -- 초. 클라 졸업식 완전 검정 시점

local lastGraduation: { [Player]: number } = {}
local pendingTeardown: { [Player]: thread } = {}

local function finish(player: Player)
	pendingTeardown[player] = nil
	PlotService.teardown(player)
	PlotService.lock(player, false)
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

	-- 원자적 프로필 변경. 여기서 저장까지 yield 없음
	profile.graduations += 1
	local graduations = profile.graduations
	profile.facilities = {}
	profile.coins = EconomyConfig.startCoins(graduations)
	local newStudent = StudentConfig.byGraduation(graduations)
	if newStudent then
		StudentService.grant(player, newStudent.id, false)
	end
	PlotService.lock(player, true)

	if not DataService.save(player) then
		warn(`[GraduationService] {player.UserId} 졸업 저장 실패, 1회 재시도`)
		if not DataService.save(player) then
			warn(`[GraduationService] {player.UserId} 졸업 저장 재시도 실패`)
		end
	end

	LeaderboardService.submit(player, graduations)
	Remotes.event(nil, "Graduated", {
		plot = PlotService.plotOf(player) or 0,
		graduations = graduations,
		newStudentId = if newStudent then newStudent.id else nil,
	})
	PlotService.syncAttributes(player)
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
