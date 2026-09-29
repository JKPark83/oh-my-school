--!nonstrict
--[[
	전학생 지급과 뽑기. 기획서 §4·§5.4·§11.5, 계획서 §3.2.
	  grant  프로필 students[id] += 1 → Students 어트리뷰트 → 자리가 있으면 StudentJoined 전체 방송
	  roll   원서 1장 → GachaConfig.roll → 도감·판·천장 갱신 → GachaResult 는 본인에게만
	원서가 없으면 조용히 무시한다(Deny 없음). 졸업 중(lock)도 무시.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Seats = require(ReplicatedStorage.Shared.Seats)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GachaConfig = require(ReplicatedStorage.Shared.Config.GachaConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local Metrics = require(script.Parent.Parent.Metrics)

local StudentService = {}

local ROLL_COOLDOWN = 1.0

local rng = Random.new()
local seqs: { [Player]: number } = {}

--- 판이 60칸을 넘으면 원서로 바꾼다. 넘친 만큼 이월
local function settleBoard(profile: Types.Profile)
	while profile.stickerBoard >= EconomyConfig.BOARD_CELLS do
		profile.stickerBoard -= EconomyConfig.BOARD_CELLS
		profile.tickets += 1
	end
end
StudentService.settleBoard = settleBoard

--- 학생 1명 지급. walk 는 주인 화면에서 걸어 들어오는 연출 여부
function StudentService.grant(player: Player, studentId: string, walk: boolean)
	local profile: Types.Profile? = DataService.get(player)
	local row = StudentConfig.BY_ID[studentId]
	if not profile or not row then
		return
	end
	profile.students[studentId] = (profile.students[studentId] or 0) + 1
	PlotService.syncAttributes(player)
	DataService.markDirty(player)

	local plotId = PlotService.plotOf(player)
	if plotId and Seats.seatOf(studentId, profile.facilities) then
		Remotes.event(nil, "StudentJoined", { plot = plotId, studentId = studentId, walk = walk })
	end
end

--- 원서 1장 뽑기. 조건이 안 되면 nil
function StudentService.roll(player: Player): Types.GachaResult?
	local profile: Types.Profile? = DataService.get(player)
	if not profile or PlotService.isLocked(player) or profile.tickets < 1 then
		return nil
	end
	profile.tickets -= 1
	profile.stats.totalPulls += 1

	local result = GachaConfig.roll(rng, profile.graduations, profile.students, profile.pity)
	if result.tier == "전설" then
		profile.pity = 0
	else
		profile.pity += 1
	end

	local before = profile.students[result.studentId] or 0
	local isDupe = before > 0
	if isDupe then
		profile.stickerBoard += GachaConfig.DUPE_CELLS[result.tier] or 0
		settleBoard(profile)
	end
	StudentService.grant(player, result.studentId, true)
	Metrics.gachaRolled(player, isDupe)

	seqs[player] = (seqs[player] or 0) + 1
	local packet: Types.GachaResult = {
		studentId = result.studentId,
		tier = result.tier,
		isDupe = isDupe,
		dupeCount = before + 1,
		boardCells = profile.stickerBoard,
		ticketsLeft = profile.tickets,
		pityLeft = GachaConfig.pityLeft(profile.pity),
		seq = seqs[player],
	}
	Remotes.event(player, "GachaResult", packet)
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
	return packet
end

function StudentService.Start()
	RemoteGuard.wrap(Remotes.RollGacha, { cooldown = ROLL_COOLDOWN, args = {} }, function(player)
		StudentService.roll(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		seqs[player] = nil
	end)
end

return StudentService
