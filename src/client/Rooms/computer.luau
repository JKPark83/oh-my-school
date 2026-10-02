--!strict
--[[
	컴퓨터실 레시피. 서쪽에 책상 2줄 × 3(학생 자리 1번은 앞줄 가운데), 자리마다 모니터·키보드.
	북쪽 벽 = 선생님 큰 스크린(창 제목줄·아이콘 2), 서쪽 벽 = 큰 방향키 4, 동쪽 벽 = 서버 랙(높이 5),
	북쪽 가운데 = 프린터, 바닥 = 케이블 덮개, 남동쪽 = 코딩 놀이 매트(색 칸 4 + 꼬마 로봇).
	의자는 자리마다 초록·노랑·하늘 순서로 돈다.
	부품 3(소품)은 꺼진 모니터, 완공(마무리)에서 화면이 켜진다.
	모니터·키보드는 PropAssets.HERO.computer 메시(둥근 레트로 모니터 + 키보드 한 덩어리, 정면이 좌석 쪽).
	메시일 때만 자리마다 마우스패드·마우스를 더한다(폴백은 예산이 다 차서 없다).
	메시가 없으면 파트(두툼한 CRT 상자·키보드, 완공 때 화면 Neon).
	서버 랙은 PropAssets.HERO.serverRack 메시(불빛이 텍스처에 있다), 없으면 상자 + Neon 줄 3.
	파트: 폴백 big 28 / props 18 / finish 14 = 60, 메시일 때 big 28 / props 24 / finish 8 = 60
	(랙 메시까지 준비되면 finish 5 = 57).
	(big 28 = 좌석 18 + 랙 1 + 프린터 탁자 2 + 스크린 1 + 코딩 매트 6. 책상 밑 본체 6 은 매트로 옮겼다)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local RACK = Vector3.new(Kit.X_IN - 1.6, 0, -9) -- 서버 랙 바닥 가운데(동쪽 벽, 깊이 약 3.1)
local RACK_H = 5
local MAT = Vector3.new(6, 0, 8) -- 코딩 매트 가운데(남동쪽, 금지 구역 x 12.5 서쪽)
local PRINTER = Vector3.new(8, 0, -12.4) -- 프린터 탁자 바닥 가운데
local PRINTER_TOP = 2.6
-- 자리마다 도는 색(의자·마우스패드). 남색 책상줄에 대비를 준다
local SEAT_COLORS = { WorldPalette.pad, WorldPalette.sticker, WorldPalette.star }

-- 좌석 s 기준 오프셋(yaw 0 = 책상이 −Z). 모니터 받침·화면·본체 자리
local function at(s: Vector3, yaw: number?, offset: Vector3): Vector3
	return s + CFrame.Angles(0, math.rad(yaw or 0), 0):VectorToWorldSpace(offset)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			Kit.seat(put, i, s, SEAT_COLORS[(i - 1) % 3 + 1], WorldPalette.signBoard, room.seatYaw)
		end
		-- yaw 90: Studio 에서 이 메시는 270 일 때 뒷면이 방을 봤다. 90 이면 문 달린 앞면이 서쪽 책상 쪽
		if not Kit.hero(put, ctx.ready, "Rack", PropAssets.HERO.serverRack, RACK, RACK_H, 90, true) then
			put(
				"Rack",
				Vector3.new(3, RACK_H, 3.2),
				RACK + Vector3.new(0, RACK_H / 2, 0),
				WorldPalette.boardDark,
				{ collide = true }
			)
		end
		-- 남동쪽 바닥 = 코딩 놀이 매트(색 칸 길 4 + 출발 칸의 꼬마 로봇)
		Kit.rug(put, "CodingMat", MAT.X, MAT.Z, 7, 7, room.wall)
		for k, tile in
			{
				{ x = -2.25, z = 2.25, c = WorldPalette.pad },
				{ x = -2.25, z = 0, c = WorldPalette.sticker },
				{ x = 0, z = 0, c = WorldPalette.star },
				{ x = 0, z = -2.25, c = WorldPalette.pad },
			}
		do
			put(`MatTile{k}`, Vector3.new(2, 0.12, 2), MAT + Vector3.new(tile.x, 0.06, tile.z), tile.c)
		end
		put("MatRobot", Vector3.new(1.2, 1, 1.2), MAT + Vector3.new(-2.25, 0.62, 2.25), room.accent)
		Kit.lowTable(put, "PrinterTable", PRINTER.X, PRINTER.Z, 4, 2, PRINTER_TOP, WorldPalette.signBoard)
		Kit.board(put, "Screen", "N", -9, 8, 14, 7, WorldPalette.boardDark)
	end,

	props = function(put, ctx)
		local room = ctx.room
		local rot = CFrame.Angles(0, math.rad(room.seatYaw or 0), 0)
		for i, s in room.seats do
			local top = Kit.deskTop(s, room.seatYaw)
			if not Kit.hero(put, ctx.ready, `Computer{i}`, PropAssets.HERO.computer, top, 1.6, room.seatYaw) then
				-- 책상에 바로 앉는 두툼한 레트로 CRT 상자(메시와 비슷한 모양)
				put(
					`Monitor{i}`,
					Vector3.new(2, 1.5, 0.9),
					at(top, room.seatYaw, Vector3.new(0, 0.75, -0.3)),
					WorldPalette.ghost,
					{ rot = rot }
				)
				put(
					`Keyboard{i}`,
					Vector3.new(1.6, 0.1, 0.4),
					at(top, room.seatYaw, Vector3.new(0, 0.05, 0.4)),
					WorldPalette.trim,
					{ rot = rot }
				)
			else
				-- 메시 오른쪽(너비 ±0.98 바깥)에 마우스패드 + 마우스
				put(
					`MousePad{i}`,
					Vector3.new(0.55, 0.03, 0.7),
					at(top, room.seatYaw, Vector3.new(1.2, 0.015, 0.3)),
					SEAT_COLORS[(i - 1) % 3 + 1],
					{ rot = rot }
				)
				put(
					`Mouse{i}`,
					Vector3.new(0.3, 0.15, 0.45),
					at(top, room.seatYaw, Vector3.new(1.2, 0.105, 0.3)),
					WorldPalette.trim,
					{ rot = rot }
				)
			end
		end
		-- 서쪽 벽 큰 방향키(↑ 하나 + ← ↓ → 한 줄). 좌석보다 5 스터드 뒤 벽이라 통로와 안 겹친다
		for k, key in
			{
				{ z = -1, y = 9.2, c = WorldPalette.star },
				{ z = -2.8, y = 7.4, c = WorldPalette.pad },
				{ z = -1, y = 7.4, c = room.accent },
				{ z = 0.8, y = 7.4, c = WorldPalette.sticker },
			}
		do
			Kit.board(put, `ArrowKey{k}`, "W", key.z, key.y, 1.6, 1.6, key.c)
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
					Vector3.new(1.6, 1.1, 0.05),
					at(top, room.seatYaw, Vector3.new(0, 0.85, 0.15)),
					if i % 2 == 1 then WorldPalette.star else WorldPalette.pad,
					{ rot = rot, material = Enum.Material.Neon }
				)
			end
		end
		-- 선생님 스크린 화면(큰 면이라 Neon 아님)
		put("ScreenFace", Vector3.new(13, 6, 0.05), Vector3.new(-9, 8, Kit.Z_N + 0.2), room.wall)
		-- 스크린 위 컴퓨터 창: 제목줄 + 아이콘 2(두께 0.12, ScreenFace 를 감싸고 앞으로 0.035 나온다)
		local winZ = Kit.Z_N + 0.2
		put("ScreenTitleBar", Vector3.new(13, 0.9, 0.12), Vector3.new(-9, 10.5, winZ), room.accent)
		put("ScreenIcon1", Vector3.new(2, 2, 0.12), Vector3.new(-13, 8, winZ), WorldPalette.sticker)
		put("ScreenIcon2", Vector3.new(2, 2, 0.12), Vector3.new(-10, 8, winZ), WorldPalette.pad)
		-- 서버 랙 불빛 3(랙 서쪽 면). 메시는 텍스처에 불빛이 있다
		if not ctx.ready(PropAssets.HERO.serverRack) then
			for k, c in { WorldPalette.pad, WorldPalette.sticker, WorldPalette.star } do
				put(
					`RackLight{k}`,
					Vector3.new(0.1, 0.25, 1.6),
					RACK + Vector3.new(-1.5, 1.2 + k * 1.1, 0),
					c,
					{ material = Enum.Material.Neon }
				)
			end
		end
		put("CableCover", Vector3.new(14, 0.1, 0.8), Vector3.new(-9, 0.05, -1.5), room.accent)
	end,
}
return recipe
