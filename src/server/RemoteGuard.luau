--!strict
--[[
	클라 → 서버 리모트의 공통 관문. 기획서 §11.5·§12.2.
	  wrap(remote, opts, handler)  토큰 버킷 10/s → 인자 타입·길이·NaN 검사 → 쿨다운 → handler
	  violation(player, reason)    10분에 20회면 warn 로그 + Kick(다시 들어와 주세요)
	실패한 요청은 조용히 무시한다(Deny 도 보내지 않는다). 쿨다운 위반은 정상 클라도 낼 수 있어 카운트하지 않는다.
	SetSetting 핸들러는 소유 서비스가 없어 여기 Start() 에 둔다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.Services.DataService)

local RemoteGuard = {}

export type ArgType = "string" | "number" | "boolean"
export type Options = {
	cooldown: number, -- 초. 플레이어·리모트별
	args: { ArgType }, -- 받을 인자 타입 순서. 이 개수를 넘는 인자는 버린다
}

-- TODO(통합): 아래 수치는 기획서 §11.5 값이다. 전용 Config 가 생기면 옮긴다.
local BUCKET_CAPACITY = 10 -- 플레이어당 토큰
local BUCKET_REFILL_PER_SECOND = 10
local MAX_STRING_LENGTH = 32
local VIOLATION_WINDOW = 600 -- 초
local VIOLATION_LIMIT = 20
local SETTING_COOLDOWN = 0.5

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: Bucket } = {}
local violations: { [Player]: { number } } = {}
local cooldowns: { [RemoteEvent]: { [Player]: number } } = {}

local function takeToken(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = BUCKET_CAPACITY, last = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(BUCKET_CAPACITY, bucket.tokens + (now - bucket.last) * BUCKET_REFILL_PER_SECOND)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function isValidArg(value: any, expected: ArgType): boolean
	if typeof(value) ~= expected then
		return false
	end
	if expected == "string" then
		return #(value :: string) <= MAX_STRING_LENGTH
	end
	if expected == "number" then
		local n = value :: number
		return n == n and n ~= math.huge and n ~= -math.huge
	end
	return true
end

--- 위반 1회 기록. 10분 창 안에 20회면 킥
function RemoteGuard.violation(player: Player, reason: string)
	local now = os.clock()
	local previous: { number } = violations[player] or {}
	local kept: { number } = {}
	for _, t in previous do
		if now - t < VIOLATION_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	violations[player] = kept
	if #kept >= VIOLATION_LIMIT then
		warn(`[RemoteGuard] {player.UserId} 위반 {#kept}회/{VIOLATION_WINDOW}초 ({reason}) → 킥`)
		violations[player] = nil
		player:Kick(Keys.KICK_RELOAD)
	end
end

--- 리모트에 관문을 붙인다. handler 는 검사를 통과한 인자만 받는다
function RemoteGuard.wrap(remote: RemoteEvent, opts: Options, handler: (player: Player, ...any) -> ())
	local perPlayer: { [Player]: number } = {}
	cooldowns[remote] = perPlayer
	local argCount = #opts.args

	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not takeToken(player) then
			RemoteGuard.violation(player, `{remote.Name} 과속`)
			return
		end

		local received = table.pack(...)
		local args = table.create(argCount)
		for i = 1, argCount do
			local value = received[i]
			if not isValidArg(value, opts.args[i]) then
				RemoteGuard.violation(player, `{remote.Name} 인자 {i}`)
				return
			end
			args[i] = value
		end

		local now = os.clock()
		local last = perPlayer[player]
		if last and now - last < opts.cooldown then
			return
		end
		perPlayer[player] = now

		handler(player, table.unpack(args, 1, argCount))
	end)
end

--- 퇴장 정리 + SetSetting 핸들러
function RemoteGuard.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
		violations[player] = nil
		for _, perPlayer in cooldowns do
			perPlayer[player] = nil
		end
	end)

	RemoteGuard.wrap(
		Remotes.SetSetting,
		{ cooldown = SETTING_COOLDOWN, args = { "string", "boolean" } },
		function(player: Player, key: string, value: boolean)
			local profile = DataService.get(player)
			if not profile then
				return
			end
			if key == "shake" then
				profile.settings.shake = value
			elseif key == "sfx" then
				profile.settings.sfx = value
			elseif key == "haptic" then
				profile.settings.haptic = value
			else
				RemoteGuard.violation(player, "SetSetting key")
				return
			end
			DataService.markDirty(player)
		end
	)
end

return RemoteGuard
