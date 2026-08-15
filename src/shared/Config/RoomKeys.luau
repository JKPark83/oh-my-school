--!strict
--[[
	교실 인스턴스에 붙는 이름들. 서버가 붙이고 클라이언트가 찾는다.

	Phase 3까지는 교실이 하나뿐이라 양쪽이 문자열을 각자 적어도 됐다.
	Phase 4에서 교실이 12개가 되면서 클라이언트가 "내 교실"을 찾아야 하고,
	찾는 이름이 어긋나면 화면에 아무것도 안 나오는 침묵하는 버그가 된다.
	그래서 이름은 여기 한 곳에만 적는다.
]]

local RoomKeys = {}

-- 태그(CollectionService)
RoomKeys.SEAT_TAG = "Seat"
RoomKeys.COVER_TAG = "Cover"
RoomKeys.SLIP_TAG = "Slip"

--[[
	카메라와 나 사이를 가로막으면 반투명해지는 파트. 벽·천장 같은 구조물에만 붙는다.

	★ "가리는 것을 전부 지운다"가 아니라 "붙인 것만 지운다"인 이유는 선생님 때문이다.
	  카메라와 나 사이에 든 것을 무조건 투명하게 만들면, 뒤돌아섰을 때 선생님이나
	  옆자리 학생까지 사라진다. 보이면 안 되는 것은 벽이지 사람이 아니다.
]]
RoomKeys.FADE_TAG = "Fade"

-- 교실 모델 안의 자식 이름
RoomKeys.SEATS_FOLDER = "Seats"
RoomKeys.OBSTACLES_FOLDER = "Obstacles"
RoomKeys.TEACHER = "Teacher"

-- 어트리뷰트
RoomKeys.EMPTY_ATTRIBUTE = "IsEmpty" -- 좌석에 붙는다. 서버만 쓴다
RoomKeys.OBSTACLES_ATTRIBUTE = "ObstaclesActive" -- 교실 모델에 붙는다

-- Player 아래에 놓이는 ObjectValue. 클라이언트가 자기 교실을 찾는 유일한 경로다.
RoomKeys.ROOM_REF = "Room"

-- 운동장 허브(Phase 5). 교실과 달리 하나뿐이라 이름으로 바로 찾는다.
RoomKeys.HUB = "Playground"

return RoomKeys
