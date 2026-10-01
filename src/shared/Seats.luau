--!strict
--[[
	학생 → 자리. 순수 함수. 기획서 §4.3.
	자리는 StudentConfig 에 고정돼 있고, 그 시설이 지어졌을 때만 앉는다.
]]

local Types = require(script.Parent.Types)
local StudentConfig = require(script.Parent.Config.StudentConfig)
local RoomConfig = require(script.Parent.Config.RoomConfig)

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

--[[
	방 학생의 자리. 방 학생이 아니거나 그 방이 아직 없으면 nil.
	floor = 그 방이 처음 지어진 층(옥상 방은 topFloor + 1), localPos = 방 로컬(RoomConfig.origin(floor) 기준).
	floors·rooftop 은 RoomConfig.fromCsv 결과(어트리뷰트 Floors·Rooftop)
]]
function Seats.roomSeat(
	studentId: Types.StudentId,
	floors: { string },
	rooftop: { string }
): (string?, number?, Vector3?)
	local row = StudentConfig.BY_ID[studentId]
	if not row or row.unlock.kind ~= "room" then
		return nil
	end
	local roomId = row.unlock.value
	local room = RoomConfig.BY_ID[roomId]
	if not room then
		return nil
	end
	local floor: number
	if room.kind == "roof" then
		if not table.find(rooftop, roomId) then
			return nil
		end
		floor = RoomConfig.topFloor(#floors) + 1
	else
		local i = table.find(floors, roomId)
		if not i then
			return nil
		end
		floor = i + 2
	end
	return roomId, floor, room.seats[row.seat.index]
end

--- Seats 폴더 안 Attachment 이름. 1 → "S01"
function Seats.attachmentName(index: number): string
	return string.format("S%02d", index)
end

return Seats
