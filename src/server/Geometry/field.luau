--!strict
--[[
	운동장(시설 13) 지오메트리 — 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 12개(≤25), 전부 BuildKit.part.
	  치수·위치는 FacilityConfig 행(center/size, 부지 로컬)에서 읽고 plotCFrame 으로 월드 변환한다.
	  60×45 땅(primary) + 안쪽 테두리 트랙 띠 넷(secondary) + 축구 골대 둘(동·서). 벽·지붕·문 없음(동쪽이 본관 쪽으로 열림).
	  땅과 트랙은 높이 ≤1 이라 Shell 바닥에서 걸려 넘어지지 않는다. 좌석 없음(Seats 폴더는 비어 있다).
	  door 가 nil 이라 Door Attachment 는 없다.
	  스티커 3개(§7.2, (-60,25)(-45,37.5)(-30,50)) 는 PlotShell 이 놓으므로 여기서는 손대지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local field = {}

local COLOR_PRIMARY = Color3.fromRGB(170, 130, 90)
local COLOR_SECONDARY = Color3.fromRGB(130, 100, 60)
local MATERIAL = Enum.Material.Sand

local GROUND_T = 0.2
local TRACK_W = 3
local TRACK_T = 0.06
local GOAL_W = 8
local GOAL_H = 4
local GOAL_INSET = 22.5 -- 중심에서 골대까지(트랙 안쪽)

local COLOR_WHITE = Color3.fromRGB(245, 245, 245)

local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

--- 골대 3파트: 기둥 둘 + 크로스바. 골문은 Z 방향으로 열린다
local function buildGoal(model: Model, plotCFrame: CFrame, suffix: string, x: number, groundTop: number, z: number)
	local opts = function(): BuildKit.Opts
		return { color = COLOR_WHITE, material = Enum.Material.Metal }
	end
	part(
		model,
		"GoalPostN" .. suffix,
		Vector3.new(0.4, GOAL_H, 0.4),
		at(plotCFrame, x, groundTop + GOAL_H / 2, z - GOAL_W / 2),
		opts()
	)
	part(
		model,
		"GoalPostS" .. suffix,
		Vector3.new(0.4, GOAL_H, 0.4),
		at(plotCFrame, x, groundTop + GOAL_H / 2, z + GOAL_W / 2),
		opts()
	)
	part(
		model,
		"GoalBar" .. suffix,
		Vector3.new(0.4, 0.4, GOAL_W + 0.4),
		at(plotCFrame, x, groundTop + GOAL_H - 0.2, z),
		opts()
	)
end

function field.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[script.Name]
	assert(row, `FacilityConfig 에 {script.Name} 행이 없다`)
	local cx, cz = row.center.X, row.center.Z
	local w, d = row.size.X, row.size.Z
	local groundTop = row.center.Y + GROUND_T
	local trackY = groundTop + TRACK_T / 2

	local model = Instance.new("Model")
	model.Name = row.id
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	-- 땅(primary)
	local ground =
		part(model, "Ground", Vector3.new(w, GROUND_T, d), at(plotCFrame, cx, row.center.Y + GROUND_T / 2, cz), {
			color = COLOR_PRIMARY,
			material = MATERIAL,
		})
	model.PrimaryPart = ground

	-- 트랙 띠 넷(secondary): 땅 가장자리 안쪽을 한 바퀴 두른다
	local trackOpts = function(): BuildKit.Opts
		return { color = COLOR_SECONDARY, material = MATERIAL, collide = false, cast = false }
	end
	local half = TRACK_W / 2
	local strips: { { name: string, size: Vector3, x: number, z: number } } = {
		{ name = "TrackN", size = Vector3.new(w, TRACK_T, TRACK_W), x = cx, z = cz - d / 2 + half },
		{ name = "TrackS", size = Vector3.new(w, TRACK_T, TRACK_W), x = cx, z = cz + d / 2 - half },
		{ name = "TrackW", size = Vector3.new(TRACK_W, TRACK_T, d - 2 * TRACK_W), x = cx - w / 2 + half, z = cz },
		{ name = "TrackE", size = Vector3.new(TRACK_W, TRACK_T, d - 2 * TRACK_W), x = cx + w / 2 - half, z = cz },
	}
	for _, s in strips do
		part(model, s.name, s.size, at(plotCFrame, s.x, trackY, s.z), trackOpts())
	end

	-- 하프 라인 + 골대 둘(서·동)
	part(model, "HalfLine", Vector3.new(0.5, TRACK_T, d - 2 * TRACK_W), at(plotCFrame, cx, trackY, cz), {
		color = COLOR_WHITE,
		collide = false,
		cast = false,
	})
	buildGoal(model, plotCFrame, "W", cx - GOAL_INSET, groundTop, cz)
	buildGoal(model, plotCFrame, "E", cx + GOAL_INSET, groundTop, cz)

	return model
end

return field
