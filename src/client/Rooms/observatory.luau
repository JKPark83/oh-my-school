--!strict
--[[
	천문대 레시피(옥상 방, 구역 x 0 ~ 11, z -13.9 ~ -3). 바닥 = 밤색 데크 + Neon 별 점.
	서북 = 둥근 돔(원통 받침 + 구, 남쪽 슬릿, 동쪽 문 + 계단 발판 2), 가운데 = 삼각대 큰 망원경(북쪽 하늘을 본다).
	학생 자리 1번은 망원경 접안렌즈 뒤 스툴. 서남 = 별자리 판 앞 벤치(좌석 2·3), 동쪽 = 스툴(좌석 4)·로켓 모형, 동북 = 안테나 접시.
	돔은 라벤더 받침 + 은빛 지붕 두 톤, 동북 스툴과 안테나 사이 = 토성 받침, 별자리 판 = 별을 잇는 선 + 달.
	메시(PropAssets.HERO): 삼각대·통·접안렌즈·파인더 6 파트 → telescope 1(대물렌즈 북쪽), 로켓 5 파트 → rocket 1.
	파트: 폴백 big 15 / props 15 / finish 15 = 45, 메시 big 12 / props 9 / finish 15 = 36.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local DOME = Vector2.new(2.6, -11.4) -- 돔 가운데
local DOME_D = 5
local DOME_BASE_H = 3
local SCOPE = Vector3.new(7.5, 3.5, -9.5) -- 삼각대 꼭대기(다리 3개가 모인다)
local LEG_R = 1.1 -- 다리 밑동이 꼭대기에서 벌어진 거리
local TUBE_Y = 3.8 -- 망원경 통 가운데 높이
local TUBE_LEN = 4.5
-- 통: 축(X)을 35° 들고 북쪽(-Z)으로 돌린다 → 축 = (0, sin35, -cos35)
local TUBE_ROT = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(35))
local TUBE_AXIS = TUBE_ROT:VectorToWorldSpace(Vector3.new(1, 0, 0))
local TUBE_UP = TUBE_ROT:VectorToWorldSpace(Vector3.new(0, 1, 0))
local ROCKET = Vector2.new(10, -5.2)
local ANTENNA = Vector2.new(9.8, -12.6)
local DISH_Y = 2.8
-- 접시: 축을 위·남쪽 45° 로 → 축 = (0, sin45, cos45)
local DISH_ROT = CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(0, 0, math.rad(45))
local BOARD_Z = -7.6 -- 별자리 판(벤치 북쪽, 남쪽 면에 별)
local SATURN = Vector2.new(10.2, -10.7) -- 토성 받침(좌석 4 스툴과 안테나 접시 사이)

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		local z = Kit.zone(room)
		put(
			"Deck",
			Vector3.new(z.x1 - z.x0, 0.1, z.z1 - z.z0),
			Vector3.new((z.x0 + z.x1) / 2, 0.05, (z.z0 + z.z1) / 2),
			WorldPalette.boardDark
		)
		-- 돔: 원통 받침 + 구(윗반구가 보인다) + 남쪽 슬릿 + 동쪽 문
		Kit.cylinder(put, "DomeBase", Vector3.new(DOME.X, DOME_BASE_H / 2, DOME.Y), DOME_D, DOME_BASE_H, room.wall)
		-- 지붕은 은빛 금속: 라벤더 받침과 두 톤으로 갈려 물탱크가 아니라 돔으로 읽힌다
		Kit.ball(
			put,
			"DomeTop",
			Vector3.new(DOME.X, DOME_BASE_H, DOME.Y),
			DOME_D,
			WorldPalette.pole,
			{ material = Enum.Material.Metal }
		)
		-- 슬릿: 구 표면 45° 지점에 접한 판(꼭대기 → 남쪽)
		put(
			"DomeSlit",
			Vector3.new(0.8, 0.25, 3),
			Vector3.new(DOME.X, 4.84, DOME.Y + 1.84),
			WorldPalette.lampIron,
			{ rot = CFrame.Angles(math.rad(45), 0, 0) }
		)
		put("DomeDoor", Vector3.new(0.2, 2.2, 1.2), Vector3.new(DOME.X + DOME_D / 2, 0.6 + 1.1, DOME.Y), room.accent)
		-- 망원경: 메시(대물렌즈 북쪽 = yaw 180, 돔 계단 발판을 비켜 조금 동쪽) 또는 삼각대 + 통
		if
			not Kit.hero(put, ctx.ready, "Telescope", PropAssets.HERO.telescope, Vector3.new(7.6, 0, SCOPE.Z), 5, 180)
		then
			-- 삼각대 다리 3: 꼭대기 SCOPE 에서 밑동(방향 φ, 거리 LEG_R)까지
			local legLen = math.sqrt(LEG_R ^ 2 + SCOPE.Y ^ 2)
			local tilt = math.atan(LEG_R / SCOPE.Y)
			for i, phi in { 90, 210, 330 } do
				local a = math.rad(phi)
				local mid = SCOPE + Vector3.new(math.cos(a), 0, -math.sin(a)) * (LEG_R / 2)
				put(
					`TripodLeg{i}`,
					Vector3.new(0.25, legLen, 0.25),
					Vector3.new(mid.X, 1.79, mid.Z),
					WorldPalette.lampIron,
					{ rot = CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, tilt) }
				)
			end
			put(
				"ScopeTube",
				Vector3.new(TUBE_LEN, 0.9, 0.9),
				Vector3.new(SCOPE.X, TUBE_Y, SCOPE.Z),
				room.accent,
				{ shape = Enum.PartType.Cylinder, rot = TUBE_ROT }
			)
		end
		-- 의자: 학생 스툴(접안렌즈 뒤)·벤치(좌석 2·3, Chair*)·스툴(좌석 4)
		Kit.chair(put, 1, room.seats[1], WorldPalette.wood, room.seatYaw)
		local h = Kit.SIT_HIP - 0.15
		put("ChairBench", Vector3.new(5, h, 2), Vector3.new(3.1, h / 2, -5.3), WorldPalette.wood)
		Kit.chair(put, 4, room.seats[4], WorldPalette.wood, room.seatYaw)
		-- 안테나: 기둥 + 기울인 접시
		Kit.cylinder(put, "AntennaPole", Vector3.new(ANTENNA.X, 1.1, ANTENNA.Y), 0.3, 2.2, WorldPalette.pole)
		put(
			"AntennaDish",
			Vector3.new(0.25, 2.2, 2.2),
			Vector3.new(ANTENNA.X, DISH_Y, ANTENNA.Y),
			WorldPalette.trim,
			{ shape = Enum.PartType.Cylinder, rot = DISH_ROT }
		)
		-- 로켓: 메시(창이 남쪽) 또는 몸통(코·날개는 props)
		if not Kit.hero(put, ctx.ready, "Rocket", PropAssets.HERO.rocket, Vector3.new(ROCKET.X, 0, ROCKET.Y), 3.5) then
			Kit.cylinder(put, "RocketBody", Vector3.new(ROCKET.X, 1.3, ROCKET.Y), 1, 2.6, WorldPalette.trim)
		end
	end,

	props = function(put, ctx)
		local room = ctx.room
		if not ctx.ready(PropAssets.HERO.telescope) then
			local tube = Vector3.new(SCOPE.X, TUBE_Y, SCOPE.Z)
			-- 접안렌즈(통 아래 끝) + 파인더(통 위에 나란히)
			put(
				"Eyepiece",
				Vector3.new(0.5, 0.35, 0.35),
				tube - TUBE_AXIS * (TUBE_LEN / 2 + 0.2),
				WorldPalette.lampIron,
				{ shape = Enum.PartType.Cylinder, rot = TUBE_ROT }
			)
			put(
				"Finder",
				Vector3.new(1.5, 0.3, 0.3),
				tube + TUBE_UP * 0.6,
				WorldPalette.trim,
				{ shape = Enum.PartType.Cylinder, rot = TUBE_ROT }
			)
		end
		if not ctx.ready(PropAssets.HERO.rocket) then
			-- 로켓: 코 + 날개 2(십자) + 남쪽 둥근 창(원판 축을 Z 로)
			Kit.ball(put, "RocketNose", Vector3.new(ROCKET.X, 2.7, ROCKET.Y), 1, WorldPalette.sticker)
			put("RocketFinA", Vector3.new(2, 1, 0.15), Vector3.new(ROCKET.X, 0.5, ROCKET.Y), room.accent)
			put("RocketFinB", Vector3.new(0.15, 1, 2), Vector3.new(ROCKET.X, 0.5, ROCKET.Y), room.accent)
			put(
				"RocketWindow",
				Vector3.new(0.08, 0.5, 0.5),
				Vector3.new(ROCKET.X, 1.7, ROCKET.Y + 0.5),
				WorldPalette.star,
				{ shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.rad(90), 0) }
			)
		end
		-- 토성: 기둥 + 주황 행성 + 기울인 노란 고리(원판 축을 Z 축으로 70° 세운다)
		Kit.cylinder(put, "SaturnPost", Vector3.new(SATURN.X, 0.95, SATURN.Y), 0.2, 1.9, WorldPalette.lampIron)
		Kit.ball(put, "SaturnBall", Vector3.new(SATURN.X, 2.4, SATURN.Y), 1.1, WorldPalette.cork)
		put(
			"SaturnRing",
			Vector3.new(0.08, 1.6, 1.6),
			Vector3.new(SATURN.X, 2.4, SATURN.Y),
			WorldPalette.sticker,
			{ shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(70)) }
		)
		-- 안테나 수신기(접시 앞면에 붙인다: 접시 반두께 0.125 + 공 반지름 0.15 - 살짝 묻힘 0.025)
		local dishAxis = DISH_ROT:VectorToWorldSpace(Vector3.new(1, 0, 0))
		Kit.ball(
			put,
			"AntennaFeed",
			Vector3.new(ANTENNA.X, DISH_Y, ANTENNA.Y) + dishAxis * 0.25,
			0.3,
			WorldPalette.lampIron
		)
		-- 별자리 판: 기둥 2 + 판(남쪽 벤치를 본다)
		for i, x in { 1.2, 3.8 } do
			Kit.cylinder(put, `StarBoardPost{i}`, Vector3.new(x, 1.5, BOARD_Z), 0.2, 3, WorldPalette.wood)
		end
		put("StarBoard", Vector3.new(3.2, 2, 0.15), Vector3.new(2.5, 1.9, BOARD_Z), WorldPalette.boardDark)
		-- 돔 문 앞 계단 발판 2
		put("StepHigh", Vector3.new(0.6, 0.6, 1.4), Vector3.new(5.4, 0.3, DOME.Y), WorldPalette.stone)
		put("StepLow", Vector3.new(0.6, 0.3, 1.4), Vector3.new(6, 0.15, DOME.Y), WorldPalette.stone)
	end,

	finish = function(put, ctx)
		local room = ctx.room
		local neon = { material = Enum.Material.Neon }
		-- 별자리 판의 별 5(북두칠성 느낌): 별 1·2·3 은 한 줄, 3·4·5 는 -45° 한 줄이라 선 2 개로 잇는다
		for i, p in
			{
				Vector2.new(1.4, 2.5),
				Vector2.new(2, 2.3),
				Vector2.new(2.6, 2.1),
				Vector2.new(3.1, 1.6),
				Vector2.new(3.6, 1.1),
			}
		do
			Kit.ball(put, `BoardStar{i}`, Vector3.new(p.X, p.Y, BOARD_Z + 0.1), 0.25, WorldPalette.sticker, neon)
		end
		for i, l in
			{
				{ from = Vector2.new(1.4, 2.5), to = Vector2.new(2.6, 2.1) },
				{ from = Vector2.new(2.6, 2.1), to = Vector2.new(3.6, 1.1) },
			}
		do
			local dx, dy = l.to.X - l.from.X, l.to.Y - l.from.Y
			put(
				`BoardLine{i}`,
				Vector3.new(math.sqrt(dx * dx + dy * dy), 0.06, 0.06),
				Vector3.new(l.from.X + dx / 2, l.from.Y + dy / 2, BOARD_Z + 0.09),
				WorldPalette.lightText,
				{ rot = CFrame.Angles(0, 0, math.atan2(dy, dx)) }
			)
		end
		-- 달: 판 왼쪽 아래 빈칸의 크림색 보름달
		Kit.ball(put, "BoardMoon", Vector3.new(1.3, 1.3, BOARD_Z + 0.1), 0.55, WorldPalette.signBoard)
		-- 바닥 별 점 4(45° 돌린 마름모)
		local diamond = { material = Enum.Material.Neon, rot = CFrame.Angles(0, math.rad(45), 0) }
		for i, p in { Vector2.new(6.2, -4.3), Vector2.new(9, -3.6), Vector2.new(0.6, -8.2), Vector2.new(9.5, -10.5) } do
			put(
				`FloorStar{i}`,
				Vector3.new(0.5, 0.05, 0.5),
				Vector3.new(p.X, 0.125, p.Y),
				WorldPalette.sticker,
				diamond
			)
		end
		-- 작은 등(기둥 + 불빛), 서남 모서리
		Kit.cylinder(put, "LampPost", Vector3.new(0.6, 1.25, -3.6), 0.3, 2.5, WorldPalette.lampIron)
		Kit.ball(put, "LampGlow", Vector3.new(0.6, 2.7, -3.6), 0.6, WorldPalette.lampGlow, neon)
		-- 이름 팻말(TowerRender 가 남쪽 면에 방 이름을 붙인다)
		put("Sign", Vector3.new(4, 2.2, 0.3), Vector3.new(6, 1.1, -3.3), room.accent)
	end,
}

return recipe
