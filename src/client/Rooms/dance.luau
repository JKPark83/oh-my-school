--!strict
--[[
	댄스실 레시피. 북쪽 벽 거울 + 발레 바, 나무 마루, 스피커 2(남쪽 벽), 미러볼(천장), 매트 더미·물병 선반(서쪽).
	가운데는 비워 춤출 자리. 학생은 서쪽 벽 긴 벤치에 앉아 동쪽(무대)을 본다(seatYaw 270, stand 없음).
	파트 big 19 · props 15 · finish 11 = 45.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local rgb = Color3.fromRGB
local PINK = rgb(255, 176, 206)
local SPEAKER = rgb(56, 54, 64)
local CONE = rgb(30, 30, 36)
local BENCH_X0, BENCH_X1 = -Kit.X_IN, -15.7 -- 벤치 앞 가장자리는 좌석 x(-16.5)에서 0.8 앞
local FACE_Z = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 Z 로(북쪽을 보는 원판)
local BALL = Vector3.new(-2, 15, -4) -- 미러볼 가운데

local function speaker(put: Kit.Put, i: number, x: number)
	local front = Kit.Z_S - 2
	put(`Speaker{i}`, Vector3.new(2.4, 4.5, 2), Vector3.new(x, 2.25, Kit.Z_S - 1), SPEAKER, { collide = true })
	put(
		`Woofer{i}`,
		Vector3.new(0.2, 1.8, 1.8),
		Vector3.new(x, 1.6, front - 0.05),
		CONE,
		{ shape = Enum.PartType.Cylinder, rot = FACE_Z }
	)
	put(
		`Tweeter{i}`,
		Vector3.new(0.2, 0.8, 0.8),
		Vector3.new(x, 3.5, front - 0.05),
		CONE,
		{ shape = Enum.PartType.Cylinder, rot = FACE_Z }
	)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		-- 거울: 북쪽 벽 거의 전체(동쪽 끝은 엘리베이터 기둥 앞에서 멈춘다)
		put("Mirror", Vector3.new(36, 9, 0.2), Vector3.new(-1.2, 5.5, Kit.Z_N + 0.1), rgb(222, 238, 248), {
			material = Enum.Material.Glass,
		})
		put("MirrorFrame", Vector3.new(36.4, 0.4, 0.3), Vector3.new(-1.2, 10.2, Kit.Z_N + 0.15), room.accent)
		-- 발레 바: 벽에서 나온 받침 3 + 가로 봉
		for i, x in { -11, -1, 9 } do
			put(`BarBracket{i}`, Vector3.new(0.3, 0.2, 1.1), Vector3.new(x, 3.3, Kit.Z_N + 0.55), WorldPalette.lampIron)
		end
		put("BalletBar", Vector3.new(24, 0.3, 0.3), Vector3.new(-1.2, 3.5, Kit.Z_N + 1), WorldPalette.wood, {
			shape = Enum.PartType.Cylinder,
		})
		-- 서쪽 벽 긴 벤치(좌석 4개가 다 이 위). 등받이는 좌석 상자 뒤
		put(
			"ChairBench",
			Vector3.new(BENCH_X1 - BENCH_X0, 1.4, 15),
			Vector3.new((BENCH_X0 + BENCH_X1) / 2, 0.7, 0),
			WorldPalette.benchWood
		)
		put("BenchBack", Vector3.new(0.5, 2.2, 15), Vector3.new(-Kit.X_IN + 0.25, 2.5, 0), WorldPalette.benchWood)
		speaker(put, 1, -8)
		speaker(put, 2, 9)
		Kit.shelf(put, "BottleShelf", "W", -11, 4, 4, WorldPalette.wood, room.wall)
		-- 매트 더미(남서 모서리)
		for i, color in { room.accent, WorldPalette.star, PINK } do
			put(`Mat{i}`, Vector3.new(4, 0.4, 2.5), Vector3.new(-15.5, 0.2 + (i - 1) * 0.4, 11.5), color, {
				material = Enum.Material.Fabric,
			})
		end
	end,
	props = function(put, ctx)
		local room = ctx.room
		-- 나무 마루. 춤 자리 표시(y 0.13)가 그 위에 올라가므로 같은 단계에서 먼저 깐다
		put("DanceFloor", Vector3.new(27.8, 0.1, 25.6), Vector3.new(-1.5, 0.05, 0), rgb(214, 172, 120), {
			material = Enum.Material.WoodPlanks,
		})
		-- 물병 선반 위 3
		for i, color in { WorldPalette.star, PINK, WorldPalette.leaf[1] } do
			Kit.cylinder(put, `Bottle{i}`, Vector3.new(-18.8, 4.45, -12 + (i - 1)), 0.5, 0.9, color)
		end
		-- 벤치 위(좌석 사이) 수건 2·물병 2
		for i, z in { -4, 4 } do
			put(
				`Towel{i}`,
				Vector3.new(1.2, 0.15, 1.2),
				Vector3.new(-17.4, 1.475, z),
				if i == 1 then room.wall else WorldPalette.trim,
				{
					material = Enum.Material.Fabric,
				}
			)
		end
		Kit.cylinder(put, "BenchBottle1", Vector3.new(-18.3, 1.85, 0), 0.4, 0.9, WorldPalette.star)
		Kit.cylinder(put, "BenchBottle2", Vector3.new(-17.4, 2, 4), 0.4, 0.9, PINK)
		-- 매트 위 카세트 오디오
		put("Boombox", Vector3.new(2, 1, 0.8), Vector3.new(-15.5, 1.7, 11.5), room.accent)
		for i, x in { -16, -15 } do
			put(`BoomboxCone{i}`, Vector3.new(0.1, 0.7, 0.7), Vector3.new(x, 1.7, 11.1), CONE, {
				shape = Enum.PartType.Cylinder,
				rot = FACE_Z,
			})
		end
		-- 춤 자리 표시 4(마루 윗면 y 0.1)
		for i, color in { WorldPalette.sticker, WorldPalette.star, PINK, room.accent } do
			local x, z = BALL.X - 3 + ((i - 1) % 2) * 6, BALL.Z - 3 + (if i > 2 then 6 else 0)
			Kit.cylinder(put, `Spot{i}`, Vector3.new(x, 0.13, z), 1.5, 0.06, color)
		end
	end,
	finish = function(put, ctx)
		local room = ctx.room
		-- 미러볼: 줄(천장에 닿는다) + 공 + 빛 점 3
		put("BallString", Vector3.new(0.1, 4.5, 0.1), BALL + Vector3.new(0, 0.75, 0), WorldPalette.lampIron)
		Kit.ball(put, "MirrorBall", BALL, 2, rgb(225, 228, 236), { material = Enum.Material.Foil })
		for i, d in { Vector3.new(0.95, 0, 0), Vector3.new(-0.5, 0.4, 0.7), Vector3.new(0.3, -0.4, -0.8) } do
			local color = ({ PINK, WorldPalette.star, WorldPalette.sticker })[i]
			Kit.ball(put, `BallDot{i}`, BALL + d, 0.35, color, { material = Enum.Material.Neon })
		end
		Kit.board(put, "Banner", "W", 0, 12.5, 12, 1.2, room.accent)
		-- 동쪽 벽 춤 포스터 2(가구 금지 구역 z ≥ -2.5 를 피한다)
		Kit.board(put, "Poster1", "E", -11, 7, 3.5, 5, room.wall)
		Kit.board(put, "Poster2", "E", -6.5, 7, 3.5, 5, PINK)
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(-Kit.X_IN + 0.1, 9.5, 0), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
		})
		Kit.plant(put, "Plant", 15.5, -11.5, WorldPalette.trunk, WorldPalette.hedge)
	end,
}

return recipe
