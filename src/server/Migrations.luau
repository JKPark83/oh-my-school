--!strict
--[[
	프로필 스키마 마이그레이션. DataService 가 Reconcile 뒤에 부른다.
	Migrations[이전 버전] = 그 버전 데이터를 다음 버전으로 바꾸는 함수. version 증가는 DataService 루프가 한다.
	순수 함수만 둔다(Remotes·서비스·DataStore require 금지). Config 만 읽으므로 Studio 없이 표 하나로 검증할 수 있다.

	v1 → v2 (W4 뽑기 폐기 → 선물판·꾸미기)
	  - tickets·pity·stats.totalPulls 를 지운다.
	  - students 를 다시 계산한다(각 1명).
	      시설 해금 학생(s01~s13): 그 시설이 지금 완공(data.facilities)이면 넣는다.
	        졸업을 1번이라도 했으면 14개를 다 지어 본 것이라 전부 넣는다(졸업하면 시설은 비지만 학생은 남는다).
	      졸업 해금 학생(s18 졸업 ≥1, s23 졸업 ≥5): data.graduations 로 판단해 넣는다.
	      그 밖(뽑기로 온 s14~s24)은 지운다. W5 부터 꾸미기로 만난다.
	  - stickerBoard 는 그대로 둔다. 옛 판(60칸)이 40칸 이상이면 다음 스티커 때 GiftBoard 가 선물로 바꾼다.
	  - giftIndex 0 · decorOwned {} · decorPlaced {} · towerFloors 0 (Reconcile 이 이미 채웠으면 그대로).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)

local Migrations: { [number]: (data: any) -> () } = {}

Migrations[1] = function(data: any)
	data.tickets = nil
	data.pity = nil
	if type(data.stats) == "table" then
		data.stats.totalPulls = nil
	end

	local facilities = if type(data.facilities) == "table" then data.facilities else {}
	local graduations = if type(data.graduations) == "number" then data.graduations else 0
	local students = {}
	for _, row in StudentConfig.LIST do
		local unlock = row.unlock
		if unlock.kind == "facility" then
			if graduations >= 1 or facilities[unlock.value] == true then
				students[row.id] = 1
			end
		elseif unlock.kind == "graduation" then
			if graduations >= (unlock.value :: number) then
				students[row.id] = 1
			end
		end
	end
	data.students = students

	if data.giftIndex == nil then
		data.giftIndex = 0
	end
	if data.decorOwned == nil then
		data.decorOwned = {}
	end
	if data.decorPlaced == nil then
		data.decorPlaced = {}
	end
	if data.towerFloors == nil then
		data.towerFloors = 0
	end
end

return Migrations
