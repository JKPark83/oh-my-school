--!nonstrict
--[[
	진행도 저장. 세션 락은 직접 짜지 않고 ProfileStore 에 맡긴다.

	★ 세션 락이 왜 필요한가.
	  같은 유저의 프로필을 두 서버가 동시에 열면, 나중에 저장하는 쪽이 이긴다.
	  플레이어 입장에서는 "한 시간 플레이가 통째로 사라졌다"로 보인다.
	  이건 재현이 거의 불가능해서 버그 리포트로도 안 잡힌다. 처음부터 막는 수밖에 없다.

	★ Steal 은 절대 쓰지 않는다. 세션 락을 무시하는 옵션이라 위 문제를 그대로 되살린다.
	  StartSessionAsync 가 nil 을 주면 그냥 킥한다. 드물고, 다시 들어오면 된다.

	★ 저장 시점은 세 곳뿐이다.
	    1) ProfileStore 자체 자동 저장(약 5분 주기)
	    2) 학년 수료 — 잃으면 가장 아까운 순간이다
	    3) 퇴장(EndSession) 과 서버 종료(ProfileStore 가 BindToClose 를 직접 건다)
	  반을 클리어할 때마다 저장하지 않는다. 한 판이 30초~1분이므로
	  12명 × 매 판 저장이면 DataStore 쓰기 예산을 태우기만 하고 얻는 게 없다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

local STORE_NAME = "PlayerProfile"

-- 스키마 버전. 지금은 쓸 일이 없어도 반드시 저장해 둔다.
-- 이 필드가 없는 채로 스키마가 바뀌는 날, 기존 데이터는 통째로 버릴 수밖에 없다.
local SCHEMA_VERSION = 1

local DEFAULT_PROFILE: Types.Profile = {
	version = SCHEMA_VERSION,
	grade = 1,
	class = 1,
	stars = 0,
	upgrades = {},
	cleared = {},
	perfect = {},
	gradeCleared = {},
	totalSeconds = 0,
	attempts = 0,
	caught = 0,
}

local DataService = {}

local store = nil
local profiles: { [Player]: any } = {}
local releasing: { [Player]: boolean } = {}

function DataService.Start()
	-- 스튜디오에서는 실제 DataStore 키를 건드리지 않는다.
	-- 플레이테스트 한 번이 라이브 진행도를 덮어쓰는 사고를 원천 차단한다.
	--
	-- 다만 Mock 은 실제 UpdateAsync·throttle·yield 를 태우지 않는다.
	-- 그것까지 확인하려면 ServerScriptService 에 UseLiveDataStore 속성을 켠다.
	-- 이때도 스토어 이름이 라이브와 다르므로 진행도를 덮어쓸 수는 없다.
	-- (Game Settings → Security → Enable Studio Access to API Services 가 켜져 있어야 한다)
	local isStudio = RunService:IsStudio()
	local useLive = isStudio and ServerScriptService:GetAttribute("UseLiveDataStore") == true

	local name = if isStudio then STORE_NAME .. "_Dev" else STORE_NAME
	local base = ProfileStore.New(name, DEFAULT_PROFILE)

	store = if isStudio and not useLive then base.Mock else base
end

--[[
	프로필 세션을 연다. 수 초까지 양보(yield)할 수 있다.
	@return 프로필 데이터. 실패하면 nil (이미 킥한 상태다)
]]
function DataService.load(player: Player): Types.Profile?
	assert(store, "DataService.Start 를 먼저 불러야 한다.")

	local profile = store:StartSessionAsync(tostring(player.UserId), {
		-- 로딩 도중 나가버린 사람을 위해 요청을 취소한다.
		Cancel = function()
			return player:IsDescendantOf(Players) == false
		end,
	})

	if not profile then
		-- 다른 서버가 같은 프로필을 붙잡고 있다. 훔치지 않는다.
		player:Kick("진행도를 불러오지 못했습니다. 잠시 후 다시 들어와 주세요.")
		return nil
	end

	profile:AddUserId(player.UserId) -- GDPR 삭제 요청 대응
	profile:Reconcile() -- 나중에 추가된 필드를 기존 저장본에 채워 넣는다

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- OnSessionEnd 는 우리가 부른 EndSession 으로도 울린다. 나가는 사람을 또 킥하지 않는다.
		if releasing[player] then
			releasing[player] = nil
			return
		end
		-- 여기까지 왔다면 다른 서버가 세션을 가져갔거나 서버가 내려가는 중이다.
		-- 계속 플레이하게 두면 그 뒤의 진행은 저장되지 않고 전부 사라진다.
		player:Kick("다른 곳에서 접속이 감지되었습니다. 다시 들어와 주세요.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return nil
	end

	profiles[player] = profile
	return profile.Data
end

function DataService.get(player: Player): Types.Profile?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- 잃으면 가장 아까운 순간에만 부른다. 한 번에 UpdateAsync 한 번을 쓴다.
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

function DataService.release(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		releasing[player] = true
		profile:EndSession()
	end
end

return DataService
