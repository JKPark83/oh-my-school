--!nonstrict
--[[
	전학생 지급. 기획서 §4·§11.5, 계획서 §3.2.
	  grant  프로필 students[id] += 1 → Students 어트리뷰트 → 자리가 있으면 StudentJoined 전체 방송
	전학생은 시설 완공(EconomyService)과 졸업 확정(GraduationService)으로만 온다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Seats = require(ReplicatedStorage.Shared.Seats)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local StudentService = {}

--- 학생 1명 지급. walk 는 주인 화면에서 「짠」 등장 연출을 할지 여부(필드 이름은 프로토콜 §11.5 그대로)
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

return StudentService
