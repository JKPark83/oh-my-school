--!strict
--[[
	코딩로봇실 레시피. 가운데 서편 로봇 경기장 탁자(검은 판·흰 트랙·바퀴 로봇 3), 북동 로봇 팔,
	동쪽 가운데 로봇 친구 마스코트(남색 얼굴판·눈 2·손 흔드는 팔), 서쪽 벽 부품 서랍장,
	남쪽 노트북 책상 줄(켜진 화면), 남동 창가 조립대(만드는 중인 로봇·예비 바퀴),
	북쪽 벽 화면에 블록 코딩, 동쪽 벽 로봇 얼굴 포스터.
	좌석: [1]·[2] 경기장 남쪽(조종기), [3]~[5] 노트북 책상.
	로봇 팔은 메시(robotarm)면 1, 아니면 5. 바퀴 로봇은 메시(rover)면 하나에 1, 아니면 2.
	파트 big 33 · props 20 · finish 7 = 60(폴백) / big 29 · props 17 → 53(메시).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local rgb = Color3.fromRGB
local ORANGE = rgb(255, 170, 60)
local PURPLE = rgb(170, 130, 230)
local METAL = rgb(96, 100, 110)
local ARENA = Vector2.new(-7, -3) -- 경기장 가운데. 판 10×7, 윗면 = 책상 높이
local TOP = Kit.SIT_DESK
local ARM = Vector3.new(14, 0, -9) -- 로봇 팔 받침 가운데
local BUDDY = Vector3.new(6, 0, -10) -- 마스코트 밑면 가운데(경기장과 로봇 팔 사이 빈 동쪽)
local BENCH = Vector2.new(7, 11.8) -- 조립대 가운데(남쪽 창가)
local BENCH_TOP = 2.6

--- 바퀴 로봇 2 파트: 몸통 + 눈(Neon). yaw 0 이면 -Z 를 본다
--- 메시(rover)면 1 파트(높이 1.6). 메시 앞은 +Z 라 yaw + 180
local function robot(put: Kit.Put, ready: Kit.Ready, i: number, x: number, z: number, yaw: number, color: Color3)
	if Kit.hero(put, ready, `Robot{i}`, PropAssets.HERO.rover, Vector3.new(x, TOP, z), 1.6, yaw + 180) then
		return
	end
	local r = CFrame.Angles(0, math.rad(yaw), 0)
	local base = Vector3.new(x, TOP, z)
	put(`Robot{i}`, Vector3.new(1, 0.6, 1), base + Vector3.new(0, 0.3, 0), color, { rot = r })
	put(
		`Robot{i}Eye`,
		Vector3.new(0.6, 0.15, 0.1),
		base + r:VectorToWorldSpace(Vector3.new(0, 0.4, -0.5)),
		WorldPalette.star,
		{
			rot = r,
			material = Enum.Material.Neon,
		}
	)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		-- 경기장 탁자: 검은 판 + 받침(충돌)
		put("Arena", Vector3.new(10, 0.3, 7), Vector3.new(ARENA.X, TOP - 0.15, ARENA.Y), WorldPalette.lampIron)
		put("ArenaBase", Vector3.new(8, TOP - 0.3, 5), Vector3.new(ARENA.X, (TOP - 0.3) / 2, ARENA.Y), METAL, {
			collide = true,
		})
		-- 좌석: 경기장 앞 의자 2, 노트북 책상 3
		for i, s in room.seats do
			if i <= 2 then
				Kit.chair(put, i, s, room.accent, room.seatYaw)
			else
				Kit.seat(put, i, s, WorldPalette.wood, room.accent, room.seatYaw)
			end
		end
		-- 로봇 팔(서쪽 경기장을 본다). 메시 앞(집게)이 −Z 라 yaw 90 = 서쪽
		if not Kit.hero(put, ctx.ready, "Arm", PropAssets.HERO.robotarm, ARM, 6, 90, true) then
			-- 폴백: 받침(충돌)·회전판·아래팔·윗팔·집게
			put("ArmStand", Vector3.new(3, 2.5, 3), ARM + Vector3.new(0, 1.25, 0), METAL, { collide = true })
			Kit.cylinder(put, "ArmTurntable", ARM + Vector3.new(0, 2.8, 0), 2, 0.6, WorldPalette.lampIron)
			put("ArmLower", Vector3.new(0.6, 3.5, 0.6), ARM + Vector3.new(0, 4.85, 0), ORANGE)
			put("ArmUpper", Vector3.new(3.5, 0.5, 0.5), ARM + Vector3.new(-1.75, 6.6, 0), ORANGE)
			put("ArmGripper", Vector3.new(0.4, 0.7, 0.9), ARM + Vector3.new(-3.6, 6.6, 0), room.accent)
		end
		-- 로봇 친구 마스코트(높이 6.6, 남쪽을 본다): 다리(충돌)·둥근 몸통·흰 머리·남색 얼굴판·
		-- 하늘색 눈 2(Neon)·내린 왼팔·흔드는 오른팔(머리 쪽으로 25° 벌린다)·안테나 공
		put("BuddyBase", Vector3.new(2.2, 1.5, 1.6), BUDDY + Vector3.new(0, 0.75, 0), METAL, { collide = true })
		Kit.cylinder(put, "BuddyBody", BUDDY + Vector3.new(0, 2.75, 0), 2.8, 2.5, room.accent)
		put("BuddyHead", Vector3.new(2.6, 2, 2), BUDDY + Vector3.new(0, 5, 0), WorldPalette.trim)
		put("BuddyVisor", Vector3.new(2.2, 1.3, 0.1), BUDDY + Vector3.new(0, 5.05, 1.03), WorldPalette.boardDark)
		for i, dx in { -0.5, 0.5 } do
			Kit.ball(put, `BuddyEye{i}`, BUDDY + Vector3.new(dx, 5.15, 1.08), 0.5, WorldPalette.star, {
				material = Enum.Material.Neon,
			})
		end
		put("BuddyArmL", Vector3.new(0.6, 2, 0.6), BUDDY + Vector3.new(-1.65, 2.9, 0), METAL)
		put("BuddyArmR", Vector3.new(0.6, 2.2, 0.6), BUDDY + Vector3.new(1.9, 4.4, 0), METAL, {
			rot = CFrame.Angles(0, 0, math.rad(-25)),
		})
		Kit.ball(put, "BuddyAntenna", BUDDY + Vector3.new(0, 6.25, 0), 0.6, WorldPalette.sticker)
		-- 남동 창가 조립대(통로·노트북 책상 줄 밖)
		Kit.lowTable(put, "Workbench", BENCH.X, BENCH.Y, 6, 2.4, BENCH_TOP, WorldPalette.wood)
		-- 부품 서랍장(서쪽 벽): 몸통(충돌) + 서랍 앞판 3
		put("Drawers", Vector3.new(1.6, 3.5, 6), Vector3.new(-Kit.X_IN + 0.8, 1.75, -6), METAL, { collide = true })
		for i, color in { WorldPalette.sticker, WorldPalette.star, room.accent } do
			put(`Drawer{i}`, Vector3.new(0.1, 0.9, 5.6), Vector3.new(-Kit.X_IN + 1.62, 0.65 + (i - 1) * 1.1, -6), color)
		end
	end,
	props = function(put, ctx)
		local room = ctx.room
		-- 흰 트랙(사각 고리 x -10.5~-3.5, z -5.5~-1.5): 흰 판 위에 검은 판을 덮어 폭 0.3 고리만 남긴다
		put("TrackOuter", Vector3.new(7.3, 0.03, 4.3), Vector3.new(ARENA.X, TOP + 0.015, -3.5), WorldPalette.trim)
		put("TrackInner", Vector3.new(6.7, 0.03, 3.7), Vector3.new(ARENA.X, TOP + 0.025, -3.5), WorldPalette.lampIron)
		robot(put, ctx.ready, 1, -8, -5.5, 90, room.accent)
		robot(put, ctx.ready, 2, -3.5, -3.5, 0, ORANGE)
		robot(put, ctx.ready, 3, -6, -1.5, 270, WorldPalette.star)
		-- 경기장 앞 조종기 2(좌석 [1]·[2] 손 앞)
		for i = 1, 2 do
			put(
				`Remote{i}`,
				Vector3.new(0.8, 0.15, 0.5),
				Kit.deskTop(room.seats[i]) + Vector3.new(0, 0.075, 0),
				room.accent
			)
		end
		-- 노트북 3: 바닥판 + 켜진 화면(Neon)
		for i = 3, 5 do
			local d = Kit.deskTop(room.seats[i])
			put(`Laptop{i}`, Vector3.new(1.2, 0.08, 0.9), d + Vector3.new(0, 0.04, 0), rgb(200, 204, 212))
			put(`LaptopScreen{i}`, Vector3.new(1.2, 0.8, 0.08), d + Vector3.new(0, 0.48, -0.41), WorldPalette.star, {
				material = Enum.Material.Neon,
			})
		end
		-- 조립대 위: 만드는 중인 로봇(주황 몸통 + 옆에 내려놓은 흰 머리, 눈은 방 쪽 북을 본다) + 예비 바퀴
		local t = BENCH_TOP
		put("BenchBot", Vector3.new(1.2, 1.2, 1), Vector3.new(BENCH.X + 1.5, t + 0.6, BENCH.Y), ORANGE)
		put("BenchBotHead", Vector3.new(1, 0.8, 0.8), Vector3.new(BENCH.X - 0.2, t + 0.4, BENCH.Y), WorldPalette.trim)
		put(
			"BenchBotEye",
			Vector3.new(0.7, 0.2, 0.1),
			Vector3.new(BENCH.X - 0.2, t + 0.45, BENCH.Y - 0.42),
			WorldPalette.star,
			{ material = Enum.Material.Neon }
		)
		Kit.cylinder(
			put,
			"SpareWheel",
			Vector3.new(BENCH.X - 2, t + 0.15, BENCH.Y + 0.3),
			1,
			0.3,
			WorldPalette.lampIron
		)
	end,
	finish = function(put, _ctx)
		-- 북쪽 벽 화면 + 블록 코딩 4줄(Z_N + 0.23: 화면 앞면에 0.03 묻힌다)
		Kit.board(put, "CodeScreen", "N", -7, 9, 14, 7, WorldPalette.boardDark)
		local blocks: { { x: number, w: number, color: Color3 } } = {
			{ x = -11, w = 4, color = WorldPalette.sticker },
			{ x = -10.5, w = 4, color = WorldPalette.star },
			{ x = -10, w = 5, color = WorldPalette.leaf[1] },
			{ x = -10.5, w = 4, color = PURPLE },
		}
		for i, b in blocks do
			put(`CodeBlock{i}`, Vector3.new(b.w, 0.8, 0.1), Vector3.new(b.x, 12 - i, Kit.Z_N + 0.23), b.color)
		end
		-- 동쪽 벽 로봇 얼굴 포스터: 주황 판 + 하늘색 눈띠(Neon)
		Kit.board(put, "RobotPoster", "E", -8, 7, 4, 5, ORANGE)
		put("RobotPosterVisor", Vector3.new(0.1, 1, 2.6), Vector3.new(Kit.X_IN - 0.23, 7.6, -8), WorldPalette.star, {
			material = Enum.Material.Neon,
		})
	end,
}

return recipe
