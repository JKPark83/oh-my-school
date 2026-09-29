--!nonstrict
--[[
	RemoteEvent 10개(클라→서버 8 + 서버→클라 2). 기획서 §11.5.
	  서버: Remotes.init() 을 부팅 첫 줄에서 부른다. 폴더와 이벤트를 만든다.
	  클라: Remotes.wait() 가 30초까지 기다린다. 못 찾으면 warn 하고 다시 기다린다(assert 없음).
	  이후 Remotes.GoHome 처럼 이름으로 꺼내 쓴다.
	  GameEvent 는 kind 필드로 종류를 구분하는 단일 이벤트다. 서버는 Remotes.event() 로만 보낸다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteEvents"
local WAIT_TIMEOUT = 30

local NAMES = {
	-- 클라 → 서버
	"Graduate", -- ()
	"SetSetting", -- (key: "shake"|"sfx"|"haptic", value: boolean)
	"GoHome", -- ()
	"BuyDecor", -- (itemId: string)
	"PlaceDecor", -- (itemId: string, cx, cz, rot, f)
	"MoveDecor", -- (slot, cx, cz, rot, f)
	"StoreDecor", -- (slot)
	"ReturnDecor", -- (itemId: string). 보관함 1개를 산 값으로 돌려받는다(무료로 받은 것은 0)
	-- 서버 → 클라
	"ProfileSync", -- { seq, profile }
	"GameEvent", -- { kind, ... }
}

local Remotes = {}
Remotes.NAMES = NAMES

local ready = false

--- 서버 전용. 폴더와 이벤트를 만들고 필드에 건다
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init 은 서버에서만 부른다")
	if ready then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
	ready = true
end

--- 클라 전용. 서버가 만든 이벤트를 기다린다. 30초마다 warn 하고 계속 기다린다
function Remotes.wait()
	assert(RunService:IsClient(), "Remotes.wait 는 클라이언트에서만 부른다")
	if ready then
		return
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	while not folder do
		warn("[Remotes] 서버 이벤트 폴더를 30초째 기다리는 중")
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	end
	for _, name in NAMES do
		local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
		while not remote do
			warn(`[Remotes] {name} 을 30초째 기다리는 중`)
			remote = folder:WaitForChild(name, WAIT_TIMEOUT)
		end
		Remotes[name] = remote
	end
	ready = true
end

--- 서버 전용. GameEvent 발송. player 가 nil 이면 전원
function Remotes.event(player: Player?, kind: string, payload: { [string]: any }?)
	local packet = payload or {}
	packet.kind = kind
	local remote = Remotes.GameEvent
	if player then
		remote:FireClient(player, packet)
	else
		remote:FireAllClients(packet)
	end
end

--- 서버 전용. Deny 이벤트 단축
function Remotes.deny(player: Player, reason: "coins" | "cooldown" | "owner" | "cell" | "limit" | "owned" | "locked")
	Remotes.event(player, "Deny", { reason = reason })
end

return Remotes
