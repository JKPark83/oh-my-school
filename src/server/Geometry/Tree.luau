--!strict
--[[
	시드 나무. 개선계획 §3.1 #3.

	Tree.build(parent, cframe, seed) 는 나무 하나를 Model 로 짓는다. 파트는 줄기 1 + 잎 뭉치 2~4 = 최대 5.
	같은 시드면 같은 나무다(Random.new(seed) 하나로 모든 값을 순서대로 뽑는다. 뽑는 순서를 바꾸면 모양이 바뀐다).
	시드마다 줄기 높이·굵기·기울기, 잎 뭉치 수·크기·자리, 잎 색(WorldPalette.leaf 3종)이 달라진다.

	cframe 은 나무 밑동(땅 윗면)의 자리다. 줄기는 SINK 만큼 땅에 묻어 기울여도 밑이 뜨지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local Tree = {}

local SINK = 0.4
local TRUNK_H_MIN, TRUNK_H_MAX = 4.5, 7.5
local TRUNK_D_MIN, TRUNK_D_MAX = 1.0, 1.5
local TILT_MAX = math.rad(9)
local CLUMPS_MIN, CLUMPS_MAX = 2, 4 -- 줄기 포함 파트 3~5
local CANOPY_D_MIN, CANOPY_D_MAX = 6, 9
local SIDE_SCALE_MIN, SIDE_SCALE_MAX = 0.55, 0.8

function Tree.build(parent: Instance, cframe: CFrame, seed: number): Model
	local rng = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "Tree"

	local trunkH = rng:NextNumber(TRUNK_H_MIN, TRUNK_H_MAX)
	local trunkD = rng:NextNumber(TRUNK_D_MIN, TRUNK_D_MAX)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local tilt = rng:NextNumber(0, TILT_MAX)
	local leafColor = WorldPalette.leaf[rng:NextInteger(1, #WorldPalette.leaf)]
	local clumps = rng:NextInteger(CLUMPS_MIN, CLUMPS_MAX)

	-- 무작위 방향으로 tilt 만큼 기운 줄기. Cylinder 축은 X 라 Z 축으로 90° 세운다
	local base = cframe * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
	local trunkCF = base * CFrame.new(0, trunkH / 2 - SINK, 0) * CFrame.Angles(0, 0, math.pi / 2)
	BuildKit.part(model, "Trunk", Vector3.new(trunkH, trunkD, trunkD), trunkCF.Position, {
		color = WorldPalette.trunk,
		material = Enum.Material.Wood,
		cframe = trunkCF.Rotation,
	})

	-- 잎: 줄기 끝 위의 큰 뭉치 하나 + 옆으로 붙은 작은 뭉치들. 잎은 똑바로 선 월드 축 기준으로 놓는다
	local top = (base * CFrame.new(0, trunkH - SINK, 0)).Position
	local mainD = rng:NextNumber(CANOPY_D_MIN, CANOPY_D_MAX)
	local leafOpts = function(): BuildKit.Opts
		return {
			color = leafColor,
			material = Enum.Material.Grass,
			shape = Enum.PartType.Ball,
			collide = false,
		}
	end
	BuildKit.part(model, "Leaf1", Vector3.one * mainD, top + Vector3.new(0, mainD * 0.3, 0), leafOpts())
	local angle = rng:NextNumber(0, math.pi * 2)
	for i = 2, clumps do
		local d = mainD * rng:NextNumber(SIDE_SCALE_MIN, SIDE_SCALE_MAX)
		-- 옆 뭉치는 대략 고르게 돌되 간격을 흔들어 등간격이 되지 않게 한다
		angle += math.pi * 2 / (clumps - 1) + rng:NextNumber(-0.6, 0.6)
		local r = mainD * rng:NextNumber(0.3, 0.5)
		local up = rng:NextNumber(0.05, 0.45) * mainD
		local offset = Vector3.new(math.cos(angle) * r, up, math.sin(angle) * r)
		BuildKit.part(model, `Leaf{i}`, Vector3.one * d, top + offset, leafOpts())
	end

	model.Parent = parent
	return model
end

return Tree
