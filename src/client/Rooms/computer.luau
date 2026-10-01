--!strict
--[[
	컴퓨터실 레시피. 서쪽에 책상 2줄 × 3(학생 자리 1번은 앞줄 가운데), 자리마다 모니터·키보드·본체.
	북쪽 벽 = 선생님 큰 스크린, 동쪽 벽 = 서버 랙(작은 불빛), 북쪽 가운데 = 프린터, 바닥 = 케이블 덮개.
	부품 3(소품)은 꺼진 모니터, 완공(마무리)에서 화면이 켜진다.
	모니터·키보드는 PropAssets.HERO.computer 메시(둥근 레트로 모니터 + 키보드 한 덩어리, 정면이 좌석 쪽).
	메시가 없으면 파트(받침·모니터·키보드, 완공 때 화면 Neon).
	파트: 폴백 big 28 / props 20 / finish 11 = 59, 메시일 때 big 28 / props 8 / finish 5 = 41.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local RACK = Vector3.new(Kit.X_IN - 1, 0, -9) -- 서버 랙 바닥 가운데(동쪽 벽, 깊이 2)
local PRINTER = Vector3.new(8, 0, -12.4) -- 프린터 탁자 바닥 가운데
local PRINTER_TOP = 2.6

-- 좌석 s 기준 오프셋(yaw 0 = 책상이 −Z). 모니터 받침·화면·본체 자리
local function at(s: Vector3, yaw: number?, offset: Vector3): Vector3
	return s + CFrame.Angles(0, math.rad(yaw or 0), 0):VectorToWorldSpace(offset)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		local rot = CFrame.Angles(0, math.rad(room.seatYaw or 0), 0)
		for i, s in room.seats do
			Kit.seat(put, i, s, WorldPalette.desk, WorldPalette.signBoard, room.seatYaw)
			-- 본체: 책상 아래 오른쪽
			put(
				`Tower{i}`,
				Vector3.new(0.8, 1.6, 1.2),
				at(s, room.seatYaw, Vector3.new(1, 0.8, -1.75)),
				WorldPalette.boardDark,
				{ rot = rot }
			)
		end
		put("Rack", Vector3.new(2, 7, 3), RACK + Vector3.new(0, 3.5, 0), WorldPalette.boardDark, { collide = true })
		Kit.lowTable(put, "PrinterTable", PRINTER.X, PRINTER.Z, 4, 2, PRINTER_TOP, WorldPalette.signBoard)
		Kit.board(put, "Screen", "N", -9, 8, 14, 7, WorldPalette.boardDark)
	end,

	props = function(put, ctx)
		local room = ctx.room
		local rot = CFrame.Angles(0, math.rad(room.seatYaw or 0), 0)
		for i, s in room.seats do
			local top = Kit.deskTop(s, room.seatYaw)
			if not Kit.hero(put, ctx.ready, `Computer{i}`, PropAssets.HERO.computer, top, 1.6, room.seatYaw) then
				put(
					`MonitorStand{i}`,
					Vector3.new(0.3, 0.6, 0.3),
					at(top, room.seatYaw, Vector3.new(0, 0.3, -0.4)),
					WorldPalette.lampIron,
					{ rot = rot }
				)
				put(
					`Monitor{i}`,
					Vector3.new(2.2, 1.4, 0.15),
					at(top, room.seatYaw, Vector3.new(0, 1.3, -0.4)),
					WorldPalette.lampIron,
					{ rot = rot }
				)
				put(
					`Keyboard{i}`,
					Vector3.new(1.6, 0.1, 0.5),
					at(top, room.seatYaw, Vector3.new(0, 0.05, 0.4)),
					WorldPalette.ghost,
					{ rot = rot }
				)
			end
		end
		put("Printer", Vector3.new(2.4, 1, 1.6), PRINTER + Vector3.new(0, PRINTER_TOP + 0.5, 0), WorldPalette.ghost)
		put(
			"PrinterPaper",
			Vector3.new(1.4, 0.05, 1),
			PRINTER + Vector3.new(0, PRINTER_TOP + 1.025, 0.2),
			WorldPalette.trim
		)
	end,

	finish = function(put, ctx)
		local room = ctx.room
		local rot = CFrame.Angles(0, math.rad(room.seatYaw or 0), 0)
		-- 모니터 화면이 켜진다(모니터 앞면에 0.025 묻힌 Neon). 메시는 화면이 이미 그려져 있다
		if not ctx.ready(PropAssets.HERO.computer) then
			for i, s in room.seats do
				local top = Kit.deskTop(s, room.seatYaw)
				put(
					`MonitorGlow{i}`,
					Vector3.new(1.9, 1.1, 0.05),
					at(top, room.seatYaw, Vector3.new(0, 1.3, -0.4 + 0.075)),
					if i % 2 == 1 then WorldPalette.star else WorldPalette.pad,
					{ rot = rot, material = Enum.Material.Neon }
				)
			end
		end
		-- 선생님 스크린 화면(큰 면이라 Neon 아님)
		put("ScreenFace", Vector3.new(13, 6, 0.05), Vector3.new(-9, 8, Kit.Z_N + 0.2), room.wall)
		-- 서버 랙 불빛 3(랙 서쪽 면)
		for k, c in { WorldPalette.pad, WorldPalette.sticker, WorldPalette.star } do
			put(
				`RackLight{k}`,
				Vector3.new(0.1, 0.25, 1.6),
				RACK + Vector3.new(-1, 2.5 + k, 0),
				c,
				{ material = Enum.Material.Neon }
			)
		end
		put("CableCover", Vector3.new(14, 0.1, 0.8), Vector3.new(-9, 0.05, -1.5), room.accent)
	end,
}
return recipe
