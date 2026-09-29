--!strict
--[[
	학생 → 자리. 순수 함수. 기획서 §4.3.
	자리는 StudentConfig 에 고정돼 있고, 그 시설이 지어졌을 때만 앉는다.
]]

local Types = require(script.Parent.Types)
local StudentConfig = require(script.Parent.Config.StudentConfig)

local Seats = {}

--- 학생의 자리. 시설이 없으면 nil
function Seats.seatOf(studentId: Types.StudentId, builtFacilities: { [Types.FacilityId]: boolean }): Types.Seat?
	local row = StudentConfig.BY_ID[studentId]
	if not row then
		return nil
	end
	if builtFacilities[row.seat.facilityId] then
		return row.seat
	end
	return nil
end

--- 시설별 착석표. { desk = { [1] = "s01", [2] = "s02" } }
function Seats.occupants(
	students: { [Types.StudentId]: boolean },
	builtFacilities: { [Types.FacilityId]: boolean }
): { [Types.FacilityId]: { [number]: Types.StudentId } }
	local table_: { [Types.FacilityId]: { [number]: Types.StudentId } } = {}
	for studentId in students do
		local seat = Seats.seatOf(studentId, builtFacilities)
		if seat then
			local room = table_[seat.facilityId]
			if not room then
				room = {}
				table_[seat.facilityId] = room
			end
			room[seat.index] = studentId
		end
	end
	return table_
end

--- Seats 폴더 안 Attachment 이름. 1 → "S01"
function Seats.attachmentName(index: number): string
	return string.format("S%02d", index)
end

return Seats
