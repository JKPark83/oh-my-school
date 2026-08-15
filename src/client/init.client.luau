--!nonstrict
--[[
	클라이언트 부트스트랩. 순서와 리모트 배선을 아는 유일한 곳이다.

	★ Phase 5 부터 첫 화면은 운동장이다. 교실은 5000 스터드 밖에 있고
	  StreamingEnabled 때문에 그동안 내려오지도 않는다.
	  그래서 컨트롤러를 두 묶음으로 나눈다:

	    허브에서도 도는 것   — 카메라, 이동, HUD, 사운드, 전환 화면
	    교실이 있어야 하는 것 — 예고 신호, 학생 렌더, 성공/실패 연출

	  뒤쪽은 신발장을 눌러 Transition 이 오는 순간 한 번만 붙인다.
	  RoomRef.await 를 부트 시점에 부르면 운동장에 서 있는 20초 동안 기다리다 터진다.

	★ TeacherStateChanged 의 version 필터는 여기 한 곳에만 있다.
	  RemoteEvent 는 어트리뷰트·프로퍼티 복제와 순서가 보장되지 않으므로
	  단조 증가 version 으로 뒤바뀐 패킷을 버린다. 컨트롤러는 통과한 것만 받는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoomRef = require(script.RoomRef)
local CameraController = require(script.Controllers.CameraController)
local FeedbackController = require(script.Controllers.FeedbackController)
local HudController = require(script.Controllers.HudController)
local MovementController = require(script.Controllers.MovementController)
local SignalController = require(script.Controllers.SignalController)
local SoundController = require(script.Controllers.SoundController)
local StudentRenderController = require(script.Controllers.StudentRenderController)
local TeacherPoseController = require(script.Controllers.TeacherPoseController)
local TransitionController = require(script.Controllers.TransitionController)

-- 전환 연출이 덮고 있는 동안 교실이 내려온다. 넉넉하게 잡되 무한은 아니다 —
-- 무한 대기는 화면에 아무것도 안 나오는 침묵하는 버그가 된다.
local ROOM_TIMEOUT = 20

CameraController.Start()
MovementController.Start()
HudController.Start()
SoundController.Start()
TransitionController.Start()

-- ── 교실이 있어야 붙는 컨트롤러 ───────────────────────────────────
local roomBound = false
local binding = false

local function bindRoom()
	if roomBound or binding then
		return
	end
	binding = true

	local ok, room = pcall(RoomRef.await, ROOM_TIMEOUT)
	binding = false
	if not ok then
		warn(`[Client] 교실을 찾지 못했다: {room}`)
		return
	end

	roomBound = true
	MovementController.bindRoom(room)
	SignalController.Start(room)
	TeacherPoseController.Start(room)
	StudentRenderController.Start(room)
	FeedbackController.Start(room)
end

-- ── 리모트 배선 ───────────────────────────────────────────────────
local lastVersion = 0

Remotes.TeacherStateChanged.OnClientEvent:Connect(function(packet)
	if packet.version <= lastVersion then
		return
	end
	lastVersion = packet.version

	-- 몸(판서·어깨)이 먼저다. 예고 신호 세 개는 같은 프레임에 떠야 하는데,
	-- 그중 가장 늦게 눈에 들어오는 것이 몸짓이라 순서를 앞에 둔다.
	TeacherPoseController.onTeacherState(packet.state, packet.duration)
	SignalController.onTeacherState(packet.state, packet.duration)
end)

Remotes.Caught.OnClientEvent:Connect(function(reason: string)
	SoundController.onCaught()
	FeedbackController.onCaught(reason)
end)

Remotes.ClassCleared.OnClientEvent:Connect(function(payload)
	SoundController.onCleared()
	FeedbackController.onCleared(payload)
end)

-- 진행도 스냅샷. HUD 표시와 클라 이동 보정(균형감각)의 유일한 근거다.
Remotes.ProfileUpdated.OnClientEvent:Connect(function(packet)
	MovementController.onProfile(packet)
	HudController.onProfile(packet)
end)

Remotes.GradeCleared.OnClientEvent:Connect(function(payload)
	SoundController.onGradeCleared()
	HudController.onGradeCleared(payload)
end)

Remotes.Notice.OnClientEvent:Connect(function(message: string)
	HudController.onNotice(message)
end)

Remotes.Cue.OnClientEvent:Connect(function(key: string)
	SoundController.onCue(key)
end)

Remotes.Transition.OnClientEvent:Connect(function(packet)
	TransitionController.onTransition(packet)
	SoundController.onTransition(packet.to)
	-- 감속 커브는 교실에서만 전부 쓴다. 밖에서는 달리기를 제한 없이 쓸 수 있어야 한다.
	MovementController.onTransition(packet.to)

	-- 교실로 들어가는 첫 전환에서 나머지 컨트롤러를 붙인다.
	-- 검은 화면이 이 대기를 가려주므로 여기가 유일하게 기다려도 되는 자리다.
	if packet.to == "class" then
		task.spawn(bindRoom)
	end
end)
