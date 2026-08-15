--!nonstrict
--[[
	운동장 허브의 유일한 주인.

	교실과 달리 허브는 하나뿐이고 12명이 같이 쓴다. 그래서 여기에는
	플레이어별 상태가 없다 — 프롬프트 하나를 열두 명이 같이 본다.

	★ 상점 프롬프트를 플레이어별로 켜고 끌 수 없다는 뜻이기도 하다.
	  이미 산 업그레이드의 매대를 흐리게 만들 방법이 없으므로, 프롬프트는 늘 켜두고
	  서버가 거절한 뒤 Notice 로 이유를 알린다. 눌러보고 알게 되는 편이,
	  남이 산 것 때문에 내 매대가 꺼져 있는 것보다 낫다.

	구매(매대)는 ProximityPrompt 다. 교실 좌석과 같은 이유다 —
	어느 물건이 발화했는지를 엔진이 넘겨주므로 클라이언트가 인자를 고를 여지가 없다.

	★ 반면 입장은 프롬프트가 아니라 계단 위 문턱을 밟는 것이다.
	  프롬프트는 "누를 수 있는 물건"을 가리키는 장치인데, 계단은 물건이 아니라 길이다.
	  올라갔으면 들어가는 것이 계단의 약속이고, 그 위에 E 를 한 번 더 얹으면
	  약속이 깨진다. 대신 Touched 는 한 번 넘어가는 동안 여러 번 울리므로,
	  중복 방지는 ProgressService.enterClass 쪽 가드(inClass·busy)가 맡는다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Template = require(script.Parent.Parent.Playground.Template)

-- 매대는 결과가 되돌릴 수 없으므로 살짝 붙잡고 있어야 발화한다.
local SHOP_HOLD = 0.6
local PROMPT_DISTANCE = 10

local PlaygroundService = {}

local hub = nil
local enterHandler: ((Player) -> ())? = nil
local buyHandler: ((Player, string) -> ())? = nil

function PlaygroundService.setEnterHandler(handler: (Player) -> ())
	enterHandler = handler
end

function PlaygroundService.setBuyHandler(handler: (Player, string) -> ())
	buyHandler = handler
end

-- 입장 전 RespawnLocation. 플레이어는 언제나 운동장에서 시작한다.
function PlaygroundService.spawn(): SpawnLocation
	assert(hub, "PlaygroundService.Start 가 먼저 돌아야 한다.")
	return hub.spawn
end

-- 교실에서 돌아올 때의 위치. 계단 발치에서 계단을 본다.
function PlaygroundService.returnCFrame(): CFrame
	assert(hub, "PlaygroundService.Start 가 먼저 돌아야 한다.")
	return hub.returnCFrame
end

local function attachPrompt(target: BasePart, actionText: string, objectText: string, hold: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = target
	return prompt
end

function PlaygroundService.Start()
	hub = Template.build()
	hub.model.Name = RoomKeys.HUB
	hub.model.Parent = workspace

	--[[
		계단 끝 문턱. 밟으면 교실로 들어간다.

		Touched 는 파트 이름이 아니라 "무엇이 닿았나"만 주므로, 닿은 파트에서
		캐릭터 → 플레이어를 거슬러 올라간다. GetPlayerFromCharacter 가 nil 이면
		NPC 거나 던져진 물건이니 그냥 흘린다.
	]]
	hub.entrance.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player and enterHandler then
			enterHandler(player)
		end
	end)

	--[[
		매대. 키는 서버가 자기 표에서 순서대로 꺼내 미리 묶는다.
		클라이언트는 "몇 번째 매대를 눌렀나"만 정할 수 있고, 그건 서버가 지은 물건이다.
	]]
	for index, key in Upgrades.ORDER do
		local stand = hub.shopStands[index]
		if not stand then
			continue
		end

		local def = Upgrades.DEFS[key]
		stand.Name = `Shop_{key}`

		local prompt = attachPrompt(stand, `★{def.cost} 주고 사기`, def.name, SHOP_HOLD)
		prompt.Triggered:Connect(function(player: Player)
			if buyHandler then
				buyHandler(player, key)
			end
		end)
	end

	return hub.model
end

return PlaygroundService
