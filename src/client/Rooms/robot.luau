--!strict
--[[
	코딩로봇실 레시피. 가운데 서편 로봇 경기장 탁자(검은 판·흰 트랙·바퀴 로봇 3), 북동 로봇 팔,
	서쪽 벽 부품 서랍장, 남쪽 노트북 책상 줄, 북쪽 벽 화면에 블록 코딩.
	좌석: [1]·[2] 경기장 남쪽(조종기), [3]~[5] 노트북 책상. 파트 big 24 · props 23 · finish 12 = 59.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local rgb = Color3.fromRGB
local ORANGE = rgb(255, 170, 60)
local PURPLE = rgb(170, 130, 230)
local METAL = rgb(96, 100, 110)
local SCREEN = rgb(50, 60, 82)
local ARENA = Vector2.new(-7, -3) -- 경기장 가운데. 판 10×7, 윗면 = 책상 높이
local TOP = Kit.SIT_DESK
local ARM = Vector3.new(14, 0, -9) -- 로봇 팔 받침 가운데
local AXIS_Z = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축을 Z 로(관절)

--- 바퀴 로봇 3 파트: 몸통 + 바퀴 축(원기둥) + 눈(Neon). yaw 0 이면 -Z 를 본다
local function robot(put: Kit.Put, i: number, x: number, z: number, yaw: number, color: Color3)
	local r = CFrame.Angles(0, math.rad(yaw), 0)
	local base = Vector3.new(x, TOP, z)
	put(`Robot{i}`, Vector3.new(1, 0.6, 1), base + Vector3.new(0, 0.3, 0), color, { rot = r })
	put(
		`Robot{i}Wheels`,
		Vector3.new(1.3, 0.55, 0.55),
		base + r:VectorToWorldSpace(Vector3.new(0, 0.275, 0.15)),
		WorldPalette.lampIron,
		{
			shape = Enum.PartType.Cylinder,
			rot = r,
		}
	)
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
		-- 로봇 팔: 받침(충돌)·회전판·아래팔·관절·윗팔·손목 관절·집게
		put("ArmStand", Vector3.new(3, 2.5, 3), ARM + Vector3.new(0, 1.25, 0), METAL, { collide = true })
		Kit.cylinder(put, "ArmTurntable", ARM + Vector3.new(0, 2.8, 0), 2, 0.6, WorldPalette.lampIron)
		put("ArmLower", Vector3.new(0.6, 3.5, 0.6), ARM + Vector3.new(0, 4.85, 0), ORANGE)
		put("ArmJoint", Vector3.new(0.9, 1, 1), ARM + Vector3.new(0, 6.6, 0), WorldPalette.lampIron, {
			shape = Enum.PartType.Cylinder,
			rot = AXIS_Z,
		})
		put("ArmUpper", Vector3.new(3.5, 0.5, 0.5), ARM + Vector3.new(-1.75, 6.6, 0), ORANGE)
		put("ArmWrist", Vector3.new(0.7, 0.7, 0.7), ARM + Vector3.new(-3.4, 6.6, 0), WorldPalette.lampIron, {
			shape = Enum.PartType.Cylinder,
			rot = AXIS_Z,
		})
		put("ArmGripper", Vector3.new(0.4, 0.7, 0.9), ARM + Vector3.new(-3.8, 6.6, 0), room.accent)
		-- 부품 서랍장(서쪽 벽): 몸통(충돌) + 서랍 앞판 3
		put("Drawers", Vector3.new(1.6, 3.5, 6), Vector3.new(-Kit.X_IN + 0.8, 1.75, -6), METAL, { collide = true })
		for i, color in { WorldPalette.sticker, WorldPalette.star, room.accent } do
			put(`Drawer{i}`, Vector3.new(0.1, 0.9, 5.6), Vector3.new(-Kit.X_IN + 1.62, 0.65 + (i - 1) * 1.1, -6), color)
		end
	end,
	props = function(put, ctx)
		local room = ctx.room
		-- 흰 트랙(사각 고리 x -10.5~-3.5, z -5.5~-1.5)
		local white, y = WorldPalette.trim, TOP + 0.015
		put("TrackN", Vector3.new(7.3, 0.03, 0.3), Vector3.new(ARENA.X, y, -5.5), white)
		put("TrackS", Vector3.new(7.3, 0.03, 0.3), Vector3.new(ARENA.X, y, -1.5), white)
		put("TrackW", Vector3.new(0.3, 0.03, 3.7), Vector3.new(-10.5, y, -3.5), white)
		put("TrackE", Vector3.new(0.3, 0.03, 3.7), Vector3.new(-3.5, y, -3.5), white)
		robot(put, 1, -8, -5.5, 90, room.accent)
		robot(put, 2, -3.5, -3.5, 0, ORANGE)
		robot(put, 3, -6, -1.5, 270, WorldPalette.star)
		-- 경기장 앞 조종기 2(좌석 [1]·[2] 손 앞)
		for i = 1, 2 do
			put(`Remote{i}`, Vector3.new(0.8, 0.15, 0.5), Kit.deskTop(room.seats[i]) + Vector3.new(0, 0.075, 0), SCREEN)
		end
		-- 노트북 3: 바닥판 + 화면
		for i = 3, 5 do
			local d = Kit.deskTop(room.seats[i])
			put(`Laptop{i}`, Vector3.new(1.2, 0.08, 0.9), d + Vector3.new(0, 0.04, 0), rgb(200, 204, 212))
			put(`LaptopScreen{i}`, Vector3.new(1.2, 0.8, 0.08), d + Vector3.new(0, 0.48, -0.41), SCREEN)
		end
		-- 서랍장 위 예비 바퀴·전지
		Kit.cylinder(put, "SpareWheel", Vector3.new(-18.6, 3.65, -7.5), 1, 0.3, WorldPalette.lampIron)
		put("Battery", Vector3.new(0.6, 0.4, 1), Vector3.new(-18.6, 3.7, -5), WorldPalette.sticker)
	end,
	finish = function(put, ctx)
		local room = ctx.room
		-- 북쪽 벽 화면 + 블록 코딩 5줄(Z_N + 0.23: 화면 앞면에 0.03 묻힌다)
		Kit.board(put, "CodeScreen", "N", -7, 9, 14, 7, WorldPalette.boardDark)
		local blocks: { { x: number, w: number, color: Color3 } } = {
			{ x = -11, w = 4, color = WorldPalette.sticker },
			{ x = -10.5, w = 4, color = WorldPalette.star },
			{ x = -10, w = 5, color = WorldPalette.leaf[1] },
			{ x = -10.5, w = 4, color = ORANGE },
			{ x = -11, w = 3, color = PURPLE },
		}
		for i, b in blocks do
			put(`CodeBlock{i}`, Vector3.new(b.w, 0.8, 0.1), Vector3.new(b.x, 12 - i, Kit.Z_N + 0.23), b.color)
		end
		Kit.board(put, "Banner", "N", -7, 13.6, 14, 1.2, room.accent)
		Kit.board(put, "RobotPoster", "E", -8, 7, 4, 5, room.wall)
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(8, 11, Kit.Z_N + 0.15), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		Kit.rug(put, "Rug", ARENA.X, ARENA.Y, 14, 11, room.wall)
		Kit.plant(put, "Plant", -17.5, 12.5, WorldPalette.trunk, WorldPalette.hedge)
	end,
}

return recipe
