--!strict
--[[
	교무실 레시피. 서쪽 선생님 책상 2줄(파스텔 파티션·켜진 모니터·출석부) 위에 깔개, 방 가운데 분홍 깔개 위 숙제 제출 탁자,
	남쪽 회의 탁자, 북쪽 시간표·서류 캐비닛, 북서 정수기, 서쪽 벽 학사일정 달력, 북동 복사기, 동쪽 커피 코너.
	깔개·파티션은 SmoothPlastic(Fabric 은 파스텔색이 어둡고 거칠게 보인다).
	좌석: 1·6 회의 탁자, 2~5 선생님 책상(RoomConfig staff).
	복사기는 메시(PropAssets.HERO.copier, 앞이 남쪽)가 준비되면 몸통·덮개 대신 1 파트.
	파트 수: 폴백 60 / 메시 59.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local H = Kit.SIT_DESK
local ZN, XI = Kit.Z_N, Kit.X_IN
local MEET_Z = 9 -- 회의 탁자 가운데 z
local COPIER = Vector3.new(15, 0, -10.5)
local COFFEE_X = XI - 0.8
local HOMEWORK = Vector3.new(2, 0, -5) -- 방 가운데 숙제 제출 탁자(도착 자리 → 방 가운데 통로 북쪽)

local recipe: Kit.Recipe = {
	big = function(put, ctx) -- 33 파트
		local seats = ctx.room.seats
		-- 선생님 책상 구역 깔개(회청 가구와 갈색 바닥 사이 색 덩어리). Kit.rug 는 Fabric 이라 직접 놓는다
		put("StaffRug", Vector3.new(11, 0.1, 13), Vector3.new(-12.5, 0.05, -1), WorldPalette.deskDome)
		-- 방 가운데 분홍 깔개 + 둥근 숙제 제출 탁자(통로 사이 빈 바닥을 채운다)
		put("CenterRug", Vector3.new(8, 0.1, 7), HOMEWORK + Vector3.new(0, 0.05, 0), WorldPalette.blossom)
		Kit.cylinder(put, "HomeworkTable", HOMEWORK + Vector3.new(0, H - 0.15, 0), 4, 0.3, WorldPalette.benchWood)
		Kit.cylinder(
			put,
			"HomeworkTableLeg",
			HOMEWORK + Vector3.new(0, (H - 0.3) / 2, 0),
			1,
			H - 0.3,
			WorldPalette.trim,
			{
				collide = true,
			}
		)
		-- 선생님 책상 4(앞쪽 파티션, 하늘·크림 번갈아)
		for i = 2, 5 do
			local s = seats[i]
			Kit.seat(put, i, s, WorldPalette.boardDark, ctx.room.accent)
			put(
				`Partition{i}`,
				Vector3.new(3, 1.4, 0.15),
				Vector3.new(s.X, H + 0.7, s.Z - 2.625),
				if i % 2 == 0 then WorldPalette.deskDome else WorldPalette.signBoard
			)
		end
		-- 회의 탁자 + 남쪽 좌석 의자 2 + 북쪽 긴 의자
		Kit.lowTable(put, "MeetTable", 0, MEET_Z, 7, 3, H, WorldPalette.benchWood)
		Kit.chair(put, 1, seats[1], WorldPalette.boardDark)
		Kit.chair(put, 6, seats[6], WorldPalette.boardDark)
		put("MeetBench", Vector3.new(5, Kit.SIT_HIP - 0.15, 2), Vector3.new(0, 0.7, MEET_Z - 3), WorldPalette.boardDark)
		-- 정수기(북서 모서리): 몸통 + 물통(몸통 윗면에 올린다)
		put(
			"WaterCooler",
			Vector3.new(1.4, 3.4, 1.4),
			Vector3.new(-18, 1.7, -12.8),
			WorldPalette.trim,
			{ collide = true }
		)
		Kit.cylinder(put, "WaterBottle", Vector3.new(-18, 4.1, -12.8), 1.1, 1.4, WorldPalette.star, {
			transparency = 0.35,
		})
		-- 복사기, 서류 캐비닛 2, 커피 코너 받침, 책장
		if not Kit.hero(put, ctx.ready, "Copier", PropAssets.HERO.copier, COPIER, 3.2, 0, true) then
			put(
				"Copier",
				Vector3.new(3, 3.5, 2.4),
				COPIER + Vector3.new(0, 1.75, 0),
				WorldPalette.ghost,
				{ collide = true }
			)
		end
		for k, x in { 7, 9.2 } do
			put(
				`Cabinet{k}`,
				Vector3.new(2, 4.5, 1.6),
				Vector3.new(x, 2.25, ZN + 0.8),
				if k == 1 then WorldPalette.ghost else WorldPalette.desk,
				{ collide = true }
			)
		end
		put("CoffeeCounter", Vector3.new(1.6, 3, 4.4), Vector3.new(COFFEE_X, 1.5, -6.5), WorldPalette.benchWood, {
			collide = true,
		})
		Kit.shelf(put, "Bookcase", "W", 8, 5, 6, WorldPalette.benchWood, ctx.room.wall)
	end,

	props = function(put, ctx) -- 16 파트(메시 15)
		local seats = ctx.room.seats
		-- 책상 위: 켜진 모니터·서류 더미(두 책상은 노란 출석부), 한 책상엔 머그컵
		for i = 2, 5 do
			local s = seats[i]
			put(`Monitor{i}`, Vector3.new(1.6, 1, 0.15), Vector3.new(s.X + 0.3, H + 0.5, s.Z - 2.35), WorldPalette.star)
			put(
				`Papers{i}`,
				Vector3.new(0.9, 0.35, 1),
				Vector3.new(s.X - 1, H + 0.175, s.Z - 1.75),
				if i == 2 or i == 4 then WorldPalette.sticker else WorldPalette.trim
			)
		end
		local s2 = seats[2]
		Kit.cylinder(put, "Mug2", Vector3.new(s2.X + 1.2, H + 0.225, s2.Z - 1.4), 0.35, 0.45, WorldPalette.star)
		-- 복사기 덮개
		if not ctx.ready(PropAssets.HERO.copier) then
			put("CopierLid", Vector3.new(3, 0.25, 2.4), COPIER + Vector3.new(0, 3.625, 0), WorldPalette.boardDark)
		end
		-- 커피 머신 + 컵
		put("CoffeeMachine", Vector3.new(1, 1.4, 1), Vector3.new(COFFEE_X, 3.7, -7.6), WorldPalette.boardDark)
		Kit.cylinder(put, "CoffeeCup", Vector3.new(COFFEE_X, 3.25, -5.5), 0.4, 0.5, WorldPalette.trim)
		-- 숙제 제출 탁자 위: 노란 숙제 바구니 + 민트 연필꽂이
		put("HomeworkTray", Vector3.new(1.6, 0.5, 1.2), HOMEWORK + Vector3.new(-0.6, H + 0.25, 0), WorldPalette.sticker)
		Kit.cylinder(put, "PenCup", HOMEWORK + Vector3.new(1, H + 0.3, 0.3), 0.5, 0.6, WorldPalette.pad)
		-- 화분
		Kit.plant(put, "Plant", -17, 12.5, WorldPalette.trunk, WorldPalette.hedge)
	end,

	finish = function(put, _ctx) -- 11 파트
		-- 시간표 게시판(요일 줄 4) + 시계
		Kit.board(put, "Timetable", "N", -6, 8.5, 10, 5, WorldPalette.cork)
		for k, c in { WorldPalette.star, WorldPalette.sticker, WorldPalette.lawn, WorldPalette.blossom } do
			put(`TimetableRow{k}`, Vector3.new(9, 0.8, 0.3), Vector3.new(-6, 11 - k, ZN + 0.15), c)
		end
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(2.5, 10, ZN + 0.1), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		-- 알림판(서쪽 벽)
		Kit.board(put, "Notice", "W", -1, 8, 6, 4, WorldPalette.signBoard)
		-- 학사일정 달력(서쪽 벽, 선생님 책상 뒤): 흰 달력 장 + 노란 머리 띠
		Kit.board(put, "Calendar", "W", -10, 8, 6, 4, WorldPalette.trim)
		Kit.board(put, "CalendarTop", "W", -10, 10.4, 6, 0.8, WorldPalette.sticker)
		-- 천장 등 2
		for k, p in { Vector3.new(-12.5, 0, -1), Vector3.new(2, 0, 4) } do
			put(
				`CeilingLight{k}`,
				Vector3.new(6, 0.3, 2),
				p + Vector3.new(0, Kit.CEIL - 0.15, 0),
				WorldPalette.lampGlow
			)
		end
	end,
}

return recipe
