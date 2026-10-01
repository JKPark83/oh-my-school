--!strict
--[[
	교무실 레시피. 서쪽 선생님 책상 2줄(파티션·모니터·서류), 남쪽 회의 탁자, 북쪽 시간표·서류 캐비닛, 북동 복사기, 동쪽 커피 코너.
	좌석: 1·6 회의 탁자, 2~5 선생님 책상(RoomConfig staff).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local H = Kit.SIT_DESK
local ZN, XI = Kit.Z_N, Kit.X_IN
local MEET_Z = 9 -- 회의 탁자 가운데 z
local COPIER = Vector3.new(15, 0, -10.5)
local COFFEE_X = XI - 0.8

local recipe: Kit.Recipe = {
	big = function(put, ctx) -- 28 파트
		local seats = ctx.room.seats
		-- 선생님 책상 4(앞쪽 파티션)
		for i = 2, 5 do
			local s = seats[i]
			Kit.seat(put, i, s, WorldPalette.boardDark, ctx.room.accent)
			put(`Partition{i}`, Vector3.new(3, 1.4, 0.15), Vector3.new(s.X, H + 0.7, s.Z - 2.625), WorldPalette.ghost)
		end
		-- 회의 탁자 + 남쪽 좌석 의자 2 + 북쪽 의자 2
		Kit.lowTable(put, "MeetTable", 0, MEET_Z, 7, 3, H, WorldPalette.benchWood)
		Kit.chair(put, 1, seats[1], WorldPalette.boardDark)
		Kit.chair(put, 6, seats[6], WorldPalette.boardDark)
		for k, x in { -1.5, 1.5 } do
			put(
				`MeetChair{k}`,
				Vector3.new(2, Kit.SIT_HIP - 0.15, 2),
				Vector3.new(x, 0.7, MEET_Z - 3),
				WorldPalette.boardDark
			)
		end
		-- 복사기, 서류 캐비닛 2, 커피 코너 받침, 책장
		put(
			"Copier",
			Vector3.new(3, 3.5, 2.4),
			COPIER + Vector3.new(0, 1.75, 0),
			WorldPalette.ghost,
			{ collide = true }
		)
		for k, x in { 7, 9.2 } do
			put(
				`Cabinet{k}`,
				Vector3.new(2, 4.5, 1.6),
				Vector3.new(x, 2.25, ZN + 0.8),
				WorldPalette.ghost,
				{ collide = true }
			)
		end
		put("CoffeeCounter", Vector3.new(1.6, 3, 4.4), Vector3.new(COFFEE_X, 1.5, -6.5), WorldPalette.benchWood, {
			collide = true,
		})
		Kit.shelf(put, "Bookcase", "W", 8, 5, 6, WorldPalette.benchWood, ctx.room.wall)
	end,

	props = function(put, ctx) -- 19 파트
		local seats = ctx.room.seats
		-- 책상 위: 모니터·서류 더미, 두 책상엔 머그컵
		for i = 2, 5 do
			local s = seats[i]
			put(
				`Monitor{i}`,
				Vector3.new(1.6, 1, 0.15),
				Vector3.new(s.X + 0.3, H + 0.5, s.Z - 2.35),
				WorldPalette.boardDark
			)
			put(`Papers{i}`, Vector3.new(0.9, 0.35, 1), Vector3.new(s.X - 1, H + 0.175, s.Z - 1.75), WorldPalette.trim)
		end
		for k, i in { 2, 5 } do
			local s = seats[i]
			Kit.cylinder(
				put,
				`Mug{i}`,
				Vector3.new(s.X + 1.2, H + 0.225, s.Z - 1.4),
				0.35,
				0.45,
				if k == 1 then WorldPalette.star else WorldPalette.sticker
			)
		end
		-- 복사기 덮개 + 종이 받침
		put("CopierLid", Vector3.new(3, 0.25, 2.4), COPIER + Vector3.new(0, 3.625, 0), WorldPalette.boardDark)
		put("CopierTray", Vector3.new(1.2, 0.2, 1.6), COPIER + Vector3.new(-1.8, 2.4, 0), WorldPalette.trim)
		-- 커피 머신 + 컵 2
		put("CoffeeMachine", Vector3.new(1, 1.4, 1), Vector3.new(COFFEE_X, 3.7, -7.6), WorldPalette.boardDark)
		for k, z in { -5.8, -5.1 } do
			Kit.cylinder(put, `CoffeeCup{k}`, Vector3.new(COFFEE_X, 3.25, z), 0.4, 0.5, WorldPalette.trim)
		end
		-- 회의 탁자 위 서류 + 연필꽂이
		put("MeetPapers", Vector3.new(1.2, 0.1, 0.9), Vector3.new(-1.5, H + 0.05, MEET_Z + 1), WorldPalette.trim)
		Kit.cylinder(put, "PenCup", Vector3.new(1, H + 0.3, MEET_Z), 0.5, 0.6, ctx.room.accent)
		-- 화분
		Kit.plant(put, "Plant", -17, 12.5, WorldPalette.trunk, WorldPalette.hedge)
	end,

	finish = function(put, ctx) -- 11 파트
		-- 시간표 게시판(요일 줄 4) + 시계
		Kit.board(put, "Timetable", "N", -6, 8.5, 10, 5, WorldPalette.cork)
		for k, c in { WorldPalette.star, WorldPalette.sticker, WorldPalette.lawn, WorldPalette.blossom } do
			put(`TimetableRow{k}`, Vector3.new(9, 0.8, 0.3), Vector3.new(-6, 11 - k, ZN + 0.15), c)
		end
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(2.5, 10, ZN + 0.1), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		-- 알림판(서쪽 벽) + 쪽지
		Kit.board(put, "Notice", "W", -1, 8, 6, 4, WorldPalette.signBoard)
		put("NoticeNote", Vector3.new(0.3, 1.4, 1.8), Vector3.new(-XI + 0.15, 8.4, -2), ctx.room.accent)
		-- 복사기 버튼 불빛, 천장 등 2
		put("CopierLight", Vector3.new(0.8, 0.1, 0.5), COPIER + Vector3.new(0.8, 3.8, 0.6), WorldPalette.pad, {
			material = Enum.Material.Neon,
		})
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
