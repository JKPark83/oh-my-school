--!strict
--[[
	선물판 정산. 기획서 §5 (W4 선물판).
	  settleBoard(player, profile)  stickerBoard 가 BOARD_CELLS(40) 이상인 동안 40칸을 떼어 선물 1개를 연다.
	    giftIndex += 1. DecorConfig.giftAt(giftIndex) 가 아이템이면 보관함에 1개(kind "item", coins 0),
	    아니거나 그 아이템이 이미 MAX_OWNED 면 코인 giftCoins(졸업). GiftOpened 는 본인에게만. 넘친 칸은 이월.
	서비스가 아니다. EconomyService(스티커·별)와 MissionService(미션 완료) 둘 다 부른다.
	두 서비스가 서로 require 하면 순환이 나서 여기 따로 둔다. DataService·Remotes·Config·Metrics 만 require 한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.Services.DataService)
local Metrics = require(script.Parent.Metrics)

local GiftBoard = {}

--- 판이 찼으면 선물을 연다. 연 개수를 돌려준다(0 이면 아무 일도 없음)
function GiftBoard.settleBoard(player: Player, profile: Types.Profile): number
	local opened = 0
	while profile.stickerBoard >= EconomyConfig.BOARD_CELLS do
		profile.stickerBoard -= EconomyConfig.BOARD_CELLS
		profile.giftIndex += 1
		opened += 1
		Metrics.giftOpened(player)
		local itemId = DecorConfig.giftAt(profile.giftIndex)
		local packet: Types.GiftOpened
		if
			itemId
			and DecorConfig.heldCount(profile.decorOwned, profile.decorPlaced, itemId) < DecorConfig.MAX_OWNED
		then
			profile.decorOwned[itemId] = (profile.decorOwned[itemId] or 0) + 1
			packet = {
				giftIndex = profile.giftIndex,
				kind = "item",
				coins = 0,
				boardCells = profile.stickerBoard,
				item = itemId,
			}
		else
			local coins = EconomyConfig.giftCoins(profile.graduations)
			profile.coins += coins
			profile.stats.totalCoins += coins
			packet = {
				giftIndex = profile.giftIndex,
				kind = "coins",
				coins = coins,
				boardCells = profile.stickerBoard,
			}
		end
		Remotes.event(player, "GiftOpened", packet)
	end
	if opened > 0 then
		DataService.markDirty(player)
	end
	return opened
end

return GiftBoard
