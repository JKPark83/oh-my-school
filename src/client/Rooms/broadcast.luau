--!strict
--[[
	방송실 레시피. 좌석은 모두 남쪽(seatYaw 180)을 본다.
	북쪽 = 학교 색 배경막 앞 방송 데스크(학생 자리 1번·2번 앵커, 마이크 2), 가운데 = 카메라 삼각대·조명 스탠드 2,
	서쪽 = 믹서 콘솔 자리(3번), 남쪽 = 미리보기 모니터 자리(4·5번), 서쪽 벽 = 체크 무늬 방음 패널, 북쪽 벽 = ON AIR 등(노랑·초록).
	카메라 몸통은 PropAssets.HERO.camera 메시(렌즈가 데스크 쪽 북쪽). 삼각대 다리는 늘 파트, 메시가 없으면 몸통·렌즈도 파트.
	파트: 폴백 big 22 / props 15 / finish 15 = 52, 메시일 때 big 22 / props 14 / finish 15 = 51.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local DESK = { x = -5, z = -7, w = 10 } -- 방송 데스크 윗판 가운데(앵커 좌석 1·2 남쪽)
local CAM = Vector3.new(-5, 0, 1.5) -- 카메라 삼각대 바닥 가운데(데스크를 북쪽으로 본다)
local LIGHTS = { Vector3.new(-12, 0, -4), Vector3.new(2, 0, -4) } -- 조명 스탠드 바닥 가운데
local LEG, TILT = 3.8, math.rad(15) -- 삼각대 다리 길이·기울기
local CAM_Y = LEG * math.cos(TILT) -- 다리 꼭대기 높이(카메라 몸통 아랫면)
local LEG_OFF = LEG / 2 * math.sin(TILT) -- 다리 가운데가 꼭대기에서 벗어난 거리

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			if i <= 2 then
				Kit.chair(put, i, s, room.accent, room.seatYaw) -- 앵커 의자(데스크는 한 판)
			else
				Kit.seat(put, i, s, room.accent, WorldPalette.signBoard, room.seatYaw)
			end
		end
		local deskTop = Kit.SIT_DESK
		put(
			"DeskTop",
			Vector3.new(DESK.w, 0.275, 1.8),
			Vector3.new(DESK.x, deskTop - 0.1375, DESK.z),
			WorldPalette.signBoard
		)
		put(
			"DeskFront",
			Vector3.new(DESK.w, deskTop - 0.275, 0.3),
			Vector3.new(DESK.x, (deskTop - 0.275) / 2, DESK.z + 0.75),
			room.accent,
			{ collide = true }
		)
		Kit.board(put, "Backdrop", "N", DESK.x, 7, 16, 10, WorldPalette.roof.classroom)
		-- 카메라 삼각대: 다리 3(꼭대기가 가운데로 모인다) + 몸통
		local legY = CAM_Y / 2 + 0.02 -- 기운 다리 AABB 가 바닥 아래로 안 내려가게
		put(
			"TripodLegW",
			Vector3.new(0.15, LEG, 0.15),
			CAM + Vector3.new(-LEG_OFF, legY, 0),
			WorldPalette.lampIron,
			{ rot = CFrame.Angles(0, 0, -TILT) }
		)
		put(
			"TripodLegE",
			Vector3.new(0.15, LEG, 0.15),
			CAM + Vector3.new(LEG_OFF, legY, 0),
			WorldPalette.lampIron,
			{ rot = CFrame.Angles(0, 0, TILT) }
		)
		put(
			"TripodLegS",
			Vector3.new(0.15, LEG, 0.15),
			CAM + Vector3.new(0, legY, LEG_OFF),
			WorldPalette.lampIron,
			{ rot = CFrame.Angles(-TILT, 0, 0) }
		)
		if not Kit.hero(put, ctx.ready, "Camera", PropAssets.HERO.camera, CAM + Vector3.new(0, CAM_Y, 0), 1.4, 180) then
			put("Camera", Vector3.new(1.2, 1, 1.8), CAM + Vector3.new(0, CAM_Y + 0.5, 0), WorldPalette.boardDark)
		end
		-- 조명 스탠드 받침·기둥
		for k, p in LIGHTS do
			Kit.cylinder(put, `LightBase{k}`, p + Vector3.new(0, 0.1, 0), 1.4, 0.2, WorldPalette.lampIron)
			put(`LightPole{k}`, Vector3.new(0.2, 5.6, 0.2), p + Vector3.new(0, 3, 0), WorldPalette.lampIron)
		end
	end,

	props = function(put, ctx)
		local room = ctx.room
		local top = Kit.SIT_DESK
		-- 앵커 앞 마이크(대 + 머리)와 대본
		for i = 1, 2 do
			local x = room.seats[i].X
			put(`Mic{i}`, Vector3.new(0.12, 1, 0.12), Vector3.new(x, top + 0.5, DESK.z - 0.2), WorldPalette.lampIron)
			Kit.ball(put, `MicHead{i}`, Vector3.new(x, top + 1.15, DESK.z - 0.2), 0.4, WorldPalette.boardDark)
			put(
				`Script{i}`,
				Vector3.new(1, 0.05, 0.7),
				Vector3.new(x + 1.1, top + 0.025, DESK.z + 0.2),
				WorldPalette.trim
			)
		end
		-- 믹서 콘솔(좌석 3 책상 위) + 페이더 3
		local mix = Kit.deskTop(room.seats[3], room.seatYaw)
		put("Mixer", Vector3.new(2.6, 0.3, 1.2), mix + Vector3.new(0, 0.15, 0.1), WorldPalette.boardDark)
		for k, c in { WorldPalette.sticker, WorldPalette.pad, WorldPalette.star } do
			put(`Fader{k}`, Vector3.new(0.25, 0.2, 0.6), mix + Vector3.new(-1.2 + k * 0.6, 0.4, 0.1), c)
		end
		-- 카메라 렌즈(북쪽으로). 메시는 렌즈가 붙어 있다
		if not ctx.ready(PropAssets.HERO.camera) then
			put(
				"CameraLens",
				Vector3.new(0.8, 0.6, 0.6),
				CAM + Vector3.new(0, CAM_Y + 0.5, -0.9),
				WorldPalette.lampIron,
				{ shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.pi / 2, 0) }
			)
		end
		-- 조명 머리
		for k, p in LIGHTS do
			put(`LightHead{k}`, Vector3.new(1.4, 1, 0.8), p + Vector3.new(0, 6.3, 0), WorldPalette.lampIron)
		end
		-- 미리보기 모니터(좌석 4·5 책상 위, 학생 쪽 −Z 를 본다)
		for i = 4, 5 do
			local t = Kit.deskTop(room.seats[i], room.seatYaw)
			put(`Preview{i}`, Vector3.new(1.8, 1.2, 0.15), t + Vector3.new(0, 0.6, 0.5), WorldPalette.lampIron)
		end
	end,

	finish = function(put, ctx)
		local room = ctx.room
		-- 배경막 학교 로고(원판)
		put("Logo", Vector3.new(0.1, 4, 4), Vector3.new(DESK.x, 9, Kit.Z_N + 0.2), WorldPalette.sticker, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		-- ON AIR 표시등(노랑) + 준비 등(초록)
		Kit.board(put, "OnAirBox", "N", 9, 13, 4, 1.6, WorldPalette.lampIron)
		put(
			"OnAirLamp",
			Vector3.new(2.6, 1, 0.05),
			Vector3.new(8.4, 13, Kit.Z_N + 0.2),
			WorldPalette.sticker,
			{ material = Enum.Material.Neon }
		)
		put(
			"ReadyLamp",
			Vector3.new(0.6, 0.6, 0.05),
			Vector3.new(10.4, 13, Kit.Z_N + 0.2),
			WorldPalette.pad,
			{ material = Enum.Material.Neon }
		)
		-- 조명 불빛(데스크 쪽 북쪽 면)
		for k, p in LIGHTS do
			put(
				`LightGlow{k}`,
				Vector3.new(1.2, 0.8, 0.05),
				p + Vector3.new(0, 6.3, -0.4),
				WorldPalette.lampGlow,
				{ material = Enum.Material.Neon }
			)
		end
		-- 미리보기 화면(Neon)
		for i = 4, 5 do
			local t = Kit.deskTop(room.seats[i], room.seatYaw)
			put(
				`PreviewGlow{i}`,
				Vector3.new(1.5, 0.9, 0.05),
				t + Vector3.new(0, 0.6, 0.43),
				WorldPalette.star,
				{ material = Enum.Material.Neon }
			)
		end
		-- 서쪽 벽 방음 패널 3 × 2 체크 무늬
		for row = 0, 1 do
			for col = 0, 2 do
				local c = if (row + col) % 2 == 0 then room.wall else room.accent
				Kit.board(put, `Acoustic{row}{col}`, "W", -12 + col * 3, 7.5 + row * 3, 3, 3, c)
			end
		end
		Kit.rug(put, "Rug", -5, -1.5, 12, 6, room.wall)
	end,
}
return recipe
