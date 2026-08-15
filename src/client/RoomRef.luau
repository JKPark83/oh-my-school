--!nonstrict
--[[
	내 교실을 찾는 유일한 경로.

	Workspace 에 교실이 12개 있고, 이름만 보고는 어느 것이 내 것인지 알 수 없다.
	서버가 Player 아래에 ObjectValue 를 하나 놓아주고, 클라이언트는 그것만 본다.

	★ ObjectValue 가 이미 붙어 있어도 .Value 는 잠시 nil 일 수 있다.
	  StreamingEnabled 상태에서 참조 대상이 아직 이 클라이언트로 내려오지 않았으면
	  참조가 풀린 것처럼 보인다. 그래서 WaitForChild 한 번으로는 부족하고,
	  값이 채워질 때까지 기다려야 한다. 물론 무한히 기다리지는 않는다 —
	  무한 대기는 화면에 아무것도 안 나오는 침묵하는 버그가 된다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomKeys = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RoomKeys"))

local POLL = 0.1

local RoomRef = {}

function RoomRef.await(timeout: number): Model
	local player = Players.LocalPlayer
	local ref = player:WaitForChild(RoomKeys.ROOM_REF, timeout)
	assert(ref, `Player 아래 {RoomKeys.ROOM_REF} 가 없다. 서버가 교실을 배정하지 못했다.`)

	local deadline = os.clock() + timeout
	while not ref.Value and os.clock() < deadline do
		task.wait(POLL)
	end

	local room = ref.Value
	assert(room, "배정된 교실이 아직 스트리밍되지 않았다.")
	return room :: Model
end

return RoomRef
