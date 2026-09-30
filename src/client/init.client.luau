--!strict
--[[
	클라이언트 부트스트랩. 컨트롤러 시작 순서와 리모트 배선을 아는 유일한 곳이다(구현계획 §3.7).

	  ★ 순서: Remotes.wait() → Hud → Panel → Pad → StudentRender → Feedback → Tutorial → Camera → Decor → Sound → Transition.
	    Hud 가 프로필 캐시를 들고 있으므로 가장 먼저, Panel 은 Hud 를 읽으므로 바로 다음이다.
	  ★ 컨트롤러 Start 는 각각 pcall 이다. 하나가 죽어도 나머지는 뜬다 — 검정 화면보다 반쪽 HUD 가 낫다.
	  ★ ProfileSync 는 HudController.setProfile 하나로만 들어간다(seq 필터도 거기). GameEvent 는 kind 별 표로
	    나눠 보내고 각 호출도 pcall 이다. 컨트롤러끼리 이벤트를 직접 잇지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

type Profile = Types.Profile

local Controllers = script:WaitForChild("Controllers")

-- 서버가 RemoteEvents 폴더를 만든 뒤에야 나머지가 의미 있다
Remotes.wait()

-- Roblox 기본 HUD 중 체력·인벤토리만 끈다. 채팅은 둔다(§8.2)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- ── 컨트롤러 로드 ──
-- 모듈이 아직 없거나 require 가 실패해도 부팅은 계속한다. 빠진 컨트롤러는 빈 표로 대신한다

local function load(name: string): any
	local module = Controllers:FindFirstChild(name)
	if not module then
		warn(`[Client] {name} 모듈이 없음`)
		return {}
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[Client] {name} require 실패: {result}`)
		return {}
	end
	return result
end

local HudController = load("HudController")
local PanelController = load("PanelController")
local PadController = load("PadController")
local StudentRenderController = load("StudentRenderController")
local FeedbackController = load("FeedbackController")
local TutorialController = load("TutorialController")
local CameraController = load("CameraController")
local DecorController = load("DecorController")
local SoundController = load("SoundController")
local TransitionController = load("TransitionController")
local InteriorRenderController = load("InteriorRenderController")

--- 컨트롤러의 함수를 pcall 로 부른다. 함수가 없으면 조용히 건너뛴다(구현 전 컨트롤러 허용)
local function call(controller: any, name: string, method: string, ...: any)
	local fn = controller[method]
	if typeof(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[Client] {name}.{method} 오류: {err}`)
	end
end

local function start(controller: any, name: string)
	if typeof(controller.Start) ~= "function" then
		warn(`[Client] {name}.Start 가 없어 건너뜀`)
		return
	end
	local ok, err = pcall(controller.Start)
	if not ok then
		warn(`[Client] {name}.Start 실패: {err}`)
	end
end

-- ── 시작 순서(구현계획 §3.7) ──
start(HudController, "HudController")
start(PanelController, "PanelController")
start(PadController, "PadController")
start(StudentRenderController, "StudentRenderController")
start(FeedbackController, "FeedbackController")
start(TutorialController, "TutorialController")
start(CameraController, "CameraController")
start(DecorController, "DecorController")
start(SoundController, "SoundController")
start(TransitionController, "TransitionController")
start(InteriorRenderController, "InteriorRenderController")

-- ── 설정 반영 ──
-- 프로필 settings 가 바뀔 때만 각 컨트롤러에 알린다. 첫 프로필은 무조건 한 번 반영한다
-- CameraController.setShakeEnabled / SoundController.setEnabled / FeedbackController.setHapticEnabled 는
-- 구현계획 §3.4 계약 밖이다. 없으면 SoundController.setMuted 로만 대신한다

local lastSettings: { shake: boolean?, sfx: boolean?, haptic: boolean? } = {}

local function applySettings(profile: Profile)
	local settings = profile.settings
	if typeof(settings) ~= "table" then
		return
	end
	if settings.shake ~= lastSettings.shake then
		call(CameraController, "CameraController", "setShakeEnabled", settings.shake)
	end
	if settings.sfx ~= lastSettings.sfx then
		if typeof(SoundController.setEnabled) == "function" then
			call(SoundController, "SoundController", "setEnabled", settings.sfx)
		else
			call(SoundController, "SoundController", "setMuted", not settings.sfx)
		end
	end
	if settings.haptic ~= lastSettings.haptic then
		call(FeedbackController, "FeedbackController", "setHapticEnabled", settings.haptic)
	end
	lastSettings = { shake = settings.shake, sfx = settings.sfx, haptic = settings.haptic }
end

-- ── 리모트 배선 ──

-- ProfileSync → Hud 하나. seq 필터는 setProfile 안에 있다
Remotes.ProfileSync.OnClientEvent:Connect(function(packet: any)
	call(HudController, "HudController", "setProfile", packet)
end)

-- Hud 캐시가 바뀔 때 설정을 따라간다(setProfile 이 seq 를 거른 뒤라 뒤바뀐 패킷은 오지 않는다)
call(HudController, "HudController", "onProfile", applySettings)

-- GameEvent kind → 받는 컨트롤러 표(구현계획 §3.7). 각 줄이 독립 pcall 이라 앞 것이 죽어도 뒤는 간다
type Handler = (payload: any) -> ()
local dispatch: { [string]: { Handler } } = {
	-- 부품 하나. 마지막 부품이면 서버가 바로 뒤에 FacilityBuilt 도 보낸다
	PartBuilt = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "part", payload)
		end,
		function()
			call(PadController, "PadController", "refresh")
		end,
		function()
			call(TutorialController, "TutorialController", "refresh")
		end,
	},
	FacilityBuilt = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "purchase", payload)
		end,
		function()
			call(PadController, "PadController", "refresh")
		end,
		function()
			call(TutorialController, "TutorialController", "refresh")
		end,
	},
	StudentJoined = {
		function(payload)
			call(StudentRenderController, "StudentRenderController", "onStudentJoined", payload)
		end,
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "student", payload)
		end,
	},
	-- 스티커판 40칸 = 선물 1개(본인에게만 온다)
	GiftOpened = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "gift", payload)
		end,
		function(payload)
			call(HudController, "HudController", "onGift", payload)
		end,
	},
	MissionDone = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "mission", payload)
		end,
		function()
			call(HudController, "HudController", "refresh")
		end,
	},
	Graduated = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "graduated", payload)
		end,
	},
	StickerCollected = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "sticker", payload)
		end,
		function(payload)
			call(PadController, "PadController", "confirmSticker", payload)
		end,
	},
	-- 꾸미기(본인에게만 온다). 모드 끝내기·보관함 되돌리기는 DecorController 가 판단한다
	DecorPlaced = {
		function(payload)
			call(DecorController, "DecorController", "onEvent", payload)
		end,
		function()
			call(TutorialController, "TutorialController", "refresh")
		end,
	},
	DecorStored = {
		function(payload)
			call(DecorController, "DecorController", "onEvent", payload)
		end,
	},
	DecorBought = {
		function(payload)
			call(DecorController, "DecorController", "onEvent", payload)
		end,
		function(payload)
			call(PanelController, "PanelController", "onDecorEvent", payload)
		end,
	},
	DecorReturned = {
		function(payload)
			call(DecorController, "DecorController", "onEvent", payload)
		end,
		function(payload)
			call(PanelController, "PanelController", "onDecorEvent", payload)
		end,
	},
	Deny = {
		function(payload)
			call(FeedbackController, "FeedbackController", "play", "deny", payload)
		end,
		function(payload)
			call(DecorController, "DecorController", "onEvent", payload)
		end,
	},
}

Remotes.GameEvent.OnClientEvent:Connect(function(packet: any)
	if typeof(packet) ~= "table" or typeof(packet.kind) ~= "string" then
		warn("[Client] GameEvent 형태가 이상함")
		return
	end
	local handlers = dispatch[packet.kind]
	if not handlers then
		warn(`[Client] 모르는 GameEvent: {packet.kind}`)
		return
	end
	for _, handler in handlers do
		handler(packet)
	end
end)
