--!strict
--[[
	댄스실 레시피. 북쪽 벽 3칸 거울(위 LED 띠) + 발레 바, 나무 마루, 미러볼 아래 체크무늬 디스코 바닥 3×3(12×12),
	남쪽 벽 스피커 2 사이 띠·음표 포스터, 미러볼·천장 무대 조명 2, 음표 포스터 2(동쪽 벽),
	매트 더미 위 붐박스·물병 선반(서쪽).
	가운데는 비워 춤출 자리. 학생은 서쪽 벽 긴 벤치에 앉아 동쪽(무대)을 본다(seatYaw 270, stand 없음).
	스피커는 메시(PropAssets.HERO.speaker)가 준비되면 하나에 메시 1, 아니면 파트 3(몸통·우퍼·트위터).
	붐박스는 메시(PropAssets.HERO.boombox) 1, 아니면 파트 3(몸통·스피커 2).
	파트 big 23 · props 17 · finish 20 = 60(폴백) / 스피커 메시 −4 · 붐박스 메시 −2 → 54(메시).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local rgb = Color3.fromRGB
local PINK = rgb(255, 176, 206)
local SPEAKER = rgb(56, 54, 64)
local CONE = rgb(30, 30, 36)
local BENCH_X0, BENCH_X1 = -Kit.X_IN, -15.7 -- 벤치 앞 가장자리는 좌석 x(-16.5)에서 0.8 앞
local FACE_Z = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 Z 로(북쪽을 보는 원판)
local BALL = Vector3.new(-2, 15, -4) -- 미러볼 가운데

local function speaker(put: Kit.Put, ready: Kit.Ready, i: number, x: number)
	-- 메시: 높이 5 → 발자국 1.93×1.87, 남쪽 벽에 붙어 북쪽(춤 자리)을 본다
	if Kit.hero(put, ready, `Speaker{i}`, PropAssets.HERO.speaker, Vector3.new(x, 0, Kit.Z_S - 1), 5, 180, true) then
		return
	end
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
		-- 하늘빛 은색 유리라 흰 벽과 갈린다. 위·아래 틀 + 칸막이 2 로 거울 3장처럼 보인다
		put("Mirror", Vector3.new(36, 9, 0.2), Vector3.new(-1.2, 5.5, Kit.Z_N + 0.1), rgb(196, 220, 236), {
			material = Enum.Material.Glass,
		})
		put("MirrorFrame", Vector3.new(36.4, 0.4, 0.3), Vector3.new(-1.2, 10.2, Kit.Z_N + 0.15), room.accent)
		put("MirrorSill", Vector3.new(36.4, 0.4, 0.3), Vector3.new(-1.2, 0.8, Kit.Z_N + 0.15), room.accent)
		for i, x in { -7.2, 4.8 } do
			put(`MirrorDivider{i}`, Vector3.new(0.3, 9, 0.3), Vector3.new(x, 5.5, Kit.Z_N + 0.15), room.accent)
		end
		-- 거울 위 LED 띠(틀 윗면 10.4 바로 위)
		put("LedStrip", Vector3.new(36, 0.2, 0.2), Vector3.new(-1.2, 10.55, Kit.Z_N + 0.1), PINK, {
			material = Enum.Material.Neon,
		})
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
			Vector3.new(15, 1.4, BENCH_X1 - BENCH_X0),
			Vector3.new((BENCH_X0 + BENCH_X1) / 2, 0.7, 0),
			WorldPalette.benchWood,
			{ rot = CFrame.Angles(0, math.rad(270), 0), seat = true } -- 동쪽(마루)을 보고 앉는다
		)
		put("BenchBack", Vector3.new(0.5, 2.2, 15), Vector3.new(-Kit.X_IN + 0.25, 2.5, 0), WorldPalette.benchWood)
		speaker(put, ctx.ready, 1, -8)
		speaker(put, ctx.ready, 2, 9)
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
		-- 나무 무대. 디스코 바닥(y 0.13)이 그 위에 올라가므로 같은 단계에서 먼저 깐다.
		-- 방 마루(WoodPlanks)와 무늬가 겹치지 않게 Wood
		put("DanceFloor", Vector3.new(27.8, 0.1, 25.6), Vector3.new(-1.5, 0.05, 0), rgb(214, 172, 120), {
			material = Enum.Material.Wood,
			collide = false,
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
		-- 매트 더미(윗면 y 1.2) 위 붐박스. 북쪽 춤 자리를 본다(이 메시는 yaw 0 에서 스피커 면이 북쪽, 화면 확인)
		if not Kit.hero(put, ctx.ready, "Boombox", PropAssets.HERO.boombox, Vector3.new(-15.5, 1.2, 11.5), 1.6, 0) then
			put("Boombox", Vector3.new(2, 1, 0.8), Vector3.new(-15.5, 1.7, 11.5), room.accent)
			for i, x in { -16, -15 } do
				put(`BoomboxCone{i}`, Vector3.new(0.1, 0.7, 0.7), Vector3.new(x, 1.7, 11.1), CONE, {
					shape = Enum.PartType.Cylinder,
					rot = FACE_Z,
				})
			end
		end
		-- 미러볼 바로 아래 디스코 바닥 3×3(칸 4, 12×12). 진한 남색 판 위에 네 모서리·가운데 색 칸 5를 얹어
		-- 체크무늬가 된다. Neon 은 화면에서 흰색으로 날아가 진한 SmoothPlastic 을 쓴다
		put("DiscoFloor", Vector3.new(12, 0.06, 12), Vector3.new(BALL.X, 0.13, BALL.Z), WorldPalette.boardDark)
		local tileColors = { WorldPalette.sticker, WorldPalette.pad, PINK, WorldPalette.star, room.accent }
		for i, cell in
			{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(0, 0), Vector2.new(-1, 1), Vector2.new(1, 1) }
		do
			put(
				`Tile{i}`,
				Vector3.new(4, 0.06, 4),
				Vector3.new(BALL.X + cell.X * 4, 0.15, BALL.Z + cell.Y * 4),
				tileColors[i]
			)
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
		-- 천장 무대 조명 2(천장 18 에 붙는다)
		for i, x in { -11, 7 } do
			local color = if i == 1 then PINK else WorldPalette.star
			Kit.cylinder(
				put,
				`StageLight{i}`,
				Vector3.new(x, 17.4, -4),
				1.2,
				1.2,
				color,
				{ material = Enum.Material.Neon }
			)
		end
		-- 남쪽 벽(스피커 둘 사이): 위 띠 + 노란 음표 포스터(머리는 북쪽을 보는 원판, 기둥은 보는 쪽 오른편 = 서쪽)
		local south = Kit.Z_S - 0.1
		put("Banner", Vector3.new(12, 1.6, 0.2), Vector3.new(0.5, 11, south), room.accent)
		put("PosterS", Vector3.new(5, 6, 0.2), Vector3.new(0.5, 6.5, south), WorldPalette.sticker)
		put("NoteHeadS", Vector3.new(0.1, 1.6, 1.6), Vector3.new(1, 5, Kit.Z_S - 0.23), room.accent, {
			shape = Enum.PartType.Cylinder,
			rot = FACE_Z,
		})
		put("NoteStemS", Vector3.new(0.3, 3, 0.1), Vector3.new(0.35, 6.5, Kit.Z_S - 0.23), room.accent)
		-- 동쪽 벽 음표 포스터 2(가구 금지 구역 z ≥ -2.5 를 피한다). 음표 = 머리(서쪽을 보는 원판) + 기둥, 포스터에 0.02 묻힌다.
		-- 포스터(y 4.5~9.5) 가운데에 작게 둔다: 머리 y 6, 기둥 y 6~7.8
		for i, z in { -11, -6.5 } do
			Kit.board(put, `Poster{i}`, "E", z, 7, 3.5, 5, if i == 1 then WorldPalette.star else PINK)
			local note = if i == 1 then WorldPalette.trim else room.accent
			put(`NoteHead{i}`, Vector3.new(0.1, 1.3, 1.3), Vector3.new(Kit.X_IN - 0.23, 6, z - 0.3), note, {
				shape = Enum.PartType.Cylinder,
			})
			put(`NoteStem{i}`, Vector3.new(0.1, 1.8, 0.3), Vector3.new(Kit.X_IN - 0.23, 6.9, z + 0.2), note)
		end
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(-Kit.X_IN + 0.1, 9.5, 0), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
		})
		Kit.plant(put, "Plant", 15.5, -11.5, WorldPalette.trunk, WorldPalette.hedge)
	end,
}

return recipe
