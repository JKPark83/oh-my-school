--!nonstrict
--[[
	리모트 정의 한 곳.
	서버가 만들고, 클라는 기다렸다 잡는다. 이름 오타로 인한 nil 참조를 없애기 위해
	양쪽 모두 이 모듈만 통해서 접근한다.

	Phase 1에서 실제로 쓰는 것만 만든다. 필요해질 때 추가한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WAIT_TIMEOUT = 10

--[[
	★ 클라 → 서버 리모트가 하나도 없다. 의도한 것이다.

	업그레이드 구매는 Phase 4 에서 RequestUpgrade 리모트였지만, Phase 5 에서
	허브 상점의 ProximityPrompt 로 옮기면서 없앴다. 프롬프트는 어느 매대가
	발화했는지를 엔진이 넘겨주므로, 클라이언트가 업그레이드 키를 고를 여지 자체가 사라진다.
	착석(좌석 프롬프트)과 같은 이유이고, 같은 방식이다.
]]
local NAMES = {
	-- 서버 → 클라
	"TeacherStateChanged", -- 선생님 상태 변경(유일한 상태 채널)
	"Caught", -- 적발 통보 + 판정 근거
	"ClassCleared", -- 착석 성공. 검증을 통과한 뒤에만 나간다
	"ProfileUpdated", -- 진행도/별/업그레이드 스냅샷. HUD와 클라 이동 보정의 근거
	"GradeCleared", -- 12반까지 수료
	"Transition", -- 허브 ↔ 교실 이동. 화면을 덮어 스트리밍 대기를 가린다
	"Notice", -- HUD 한 줄 알림. 상점 결과처럼 연출이 필요 없는 통보
	"Cue", -- 짧은 소리 하나만 재생시킨다. 상태를 바꾸지 않는다
}

-- 인스턴스 폴더 이름은 이 모듈(ReplicatedStorage.Shared.Remotes)과 헷갈리지 않게 따로 둔다.
local FOLDER_NAME = "RemoteEvents"

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
else
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(
		found,
		`{FOLDER_NAME} 폴더가 복제되지 않았다. 서버 부트스트랩이 실패했을 가능성이 높다.`
	)
	folder = found :: Folder
end

local Remotes = {}

for _, name in NAMES do
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	else
		local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
		assert(remote, `리모트 '{name}' 가 복제되지 않았다.`)
		Remotes[name] = remote
	end
end

return Remotes
