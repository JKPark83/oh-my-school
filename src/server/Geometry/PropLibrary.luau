--!strict
--[[
	소품 라이브러리. 개선계획 §3.1 #6~#10.

	메시 id(PropAssets)가 있으면 MeshPart 하나로, 없거나 불러오기가 실패하면 파트로 짓는다.
	  PropLibrary.tree(parent, cframe, seed)      나무. 메시 2파트(줄기·잎, 원래 텍스처) + 안 보이는 줄기 기둥 1(충돌), 폴백은 Tree.build(파트 3~5)에 그대로 맡긴다
	  PropLibrary.flowerbed(parent, cframe, seed) 화단. 메시 1파트, 폴백은 흙판 1 + 꽃 뭉치 3 = 파트 4
	  PropLibrary.wallLamp(parent, cframe)        벽등. 메시 4파트(받침·틀·유리·전구), 폴백은 벽판·팔·지붕·불빛 = 파트 4. PointLight 1
	  PropLibrary.storeModel(parent, entry, cframe) Creator Store 모델(광장 전용·비핵심). 실패하면 nil
	cframe 은 소품 밑면 중심(땅 윗면)의 자리다. 같은 시드면 같은 모양이다.

	MeshPart 의 MeshId 는 런타임에 바꿀 수 없어서 AssetService:CreateMeshPartAsync 로 만든다(서버, yield).
	id 마다 한 번만 만들어 두고(원본) 이후엔 Clone 한다. 실패도 기억해서 다시 부르지 않는다.
	기다림은 PropAssets.MESH_TIMEOUT 까지다. 넘으면 그 소품은 파트로 짓는다.
]]

local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local Tree = require(script.Parent.Tree)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local PropLibrary = {}

local SCALE_MIN, SCALE_MAX = 0.85, 1.15 -- 메시 나무 크기 흔들기
local TRUNK_COLLIDER_D = 1.4 -- 메시 나무 줄기 기둥 지름(scale 1). 보이는 줄기 굵기쯤

-- 화단 폴백: 흙판 4×2(높이 0.4) 위에 꽃 뭉치 3개
local BED_SIZE = Vector3.new(4, 0.4, 2)
local BLOOM_D_MIN, BLOOM_D_MAX = 1.1, 1.5
local BLOOM_SINK = 0.35 -- 꽃 뭉치를 흙에 묻는 깊이(공이 떠 보이지 않게)

-- 벽등: 생성물(높이 2.32)을 문 높이 8 옆에서 보이게 키운다. 빛은 벽과 문 앞만 비춘다(그림자 끔, §12.1)
local LAMP_SCALE = 1.5
local LAMP_LIGHT_RANGE = 12
local LAMP_LIGHT_BRIGHTNESS = 1.5

-- id → 원본 MeshPart. false = 실패(폴백). 요청 중인 id 는 requestedAt 에 시작 시각이 있다
local meshCache: { [number]: MeshPart | false } = {}
local requestedAt: { [number]: number } = {}

--- 원본 MeshPart 를 한 번 만든다(yield). 실패도 false 로 기억한다
local function requestMesh(id: number)
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	local made: MeshPart | false = false
	if ok and result then
		made = result
	else
		warn(`PropLibrary: 메시 {id} 를 못 만들었다. 파트로 짓는다 ({result})`)
	end
	meshCache[id] = made
	print(`PropLibrary: 메시 {id} 준비 {string.format("%.2f", os.clock() - requestedAt[id])}초`)
end

--[[
	원본 MeshPart 를 복제해 돌려준다. id 0 이거나 만들기에 실패하면 nil.
	첫 요청은 task.spawn 으로 따로 돌리고, 부르는 쪽은 요청 시작부터 PropAssets.MESH_TIMEOUT 초까지만 기다린다.
	그 뒤엔 요청이 끝나지 않았어도 nil(파트 폴백)이다 → 에셋 서버가 느려도 부팅(PlotService.Start)이 그만큼만 밀린다.
	같은 id 를 여러 곳에서 동시에 불러도 요청은 한 번이다.
]]
local function cloneMesh(id: number): MeshPart?
	if id == 0 then
		return nil
	end
	if meshCache[id] == nil and requestedAt[id] == nil then
		requestedAt[id] = os.clock()
		task.spawn(requestMesh, id)
	end
	while meshCache[id] == nil and os.clock() - requestedAt[id] < PropAssets.MESH_TIMEOUT do
		task.wait()
	end
	local cached: MeshPart | false | nil = meshCache[id]
	if cached then
		return cached:Clone()
	end
	return nil
end

--- 메시 파트 하나를 밑면 중심이 cframe 에 오게 놓는다. 색만 입히고 텍스처는 쓰지 않는다
local function placeMesh(
	mesh: MeshPart,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Model
	local model = Instance.new("Model")
	model.Name = name
	mesh.Name = name
	mesh.Size = size
	mesh.CFrame = cframe * CFrame.new(0, size.Y / 2, 0)
	mesh.Color = color
	mesh.TextureID = ""
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Anchored = true
	mesh.CanCollide = false -- 상자 충돌이라 잎까지 막는다. 지나갈 수 있게 둔다
	mesh.CastShadow = true
	mesh.Parent = model
	model.Parent = parent
	return model
end

--- 파트 하나라도 못 불러오면 나무 전체를 Tree.build 로 짓는다(줄기만 있거나 잎만 뜬 나무가 없게)
function PropLibrary.tree(parent: Instance, cframe: CFrame, seed: number): Model
	local meshes: { MeshPart } = {}
	for _, piece in PropAssets.TREE.pieces do
		local mesh = cloneMesh(piece.id)
		if not mesh then
			for _, made in meshes do
				made:Destroy()
			end
			return Tree.build(parent, cframe, seed)
		end
		table.insert(meshes, mesh)
	end
	local rng = Random.new(seed)
	local scale = rng:NextNumber(SCALE_MIN, SCALE_MAX)
	local base = cframe * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = Instance.new("Model")
	model.Name = "Tree"
	for i, piece in PropAssets.TREE.pieces do
		local mesh = meshes[i]
		mesh.Name = piece.name
		mesh.Size = piece.size * scale
		mesh.CFrame = base * CFrame.new(piece.offset * scale)
		mesh.TextureID = if piece.texture ~= 0 then `rbxassetid://{piece.texture}` else ""
		mesh.Anchored = true
		mesh.CanCollide = false -- 상자 충돌이라 뿌리·잎 폭까지 막는다. 막는 건 아래 줄기 기둥이 한다
		mesh.CastShadow = true
		mesh.Parent = model
	end
	-- 보이지 않는 줄기 기둥(원기둥 축 = X 라 Z 로 90° 세운다). 캐릭터가 나무를 뚫고 지나가지 않게
	local trunkH = PropAssets.TREE.pieces[1].size.Y * scale
	local d = TRUNK_COLLIDER_D * scale
	local collider = BuildKit.part(
		model,
		"TrunkCollider",
		Vector3.new(trunkH, d, d),
		(base * CFrame.new(0, trunkH / 2, 0)).Position,
		{
			color = WorldPalette.trunk,
			transparency = 1,
			cast = false,
			shape = Enum.PartType.Cylinder,
			cframe = CFrame.Angles(0, 0, math.pi / 2),
		}
	)
	collider.CanQuery = false -- 카메라·탭 레이에 안 보이는 기둥이 걸리지 않게
	collider.CanTouch = false
	model.Parent = parent
	return model
end

function PropLibrary.flowerbed(parent: Instance, cframe: CFrame, seed: number): Model
	local asset = PropAssets.MESHES.flowerbed
	local mesh = cloneMesh(asset.id)
	if mesh then
		return placeMesh(mesh, "Flowerbed", asset.size, cframe, WorldPalette.blossom, parent)
	end

	local rng = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "Flowerbed"
	local soilCF = cframe * CFrame.new(0, BED_SIZE.Y / 2, 0)
	BuildKit.part(model, "Soil", BED_SIZE, soilCF.Position, {
		color = WorldPalette.soil,
		material = Enum.Material.Ground,
		cframe = soilCF.Rotation,
	})
	-- 꽃 뭉치 3: 분홍 둘 + 초록 하나. 초록이 어디에 끼는지는 시드가 정한다
	local greenAt = rng:NextInteger(1, 3)
	local step = BED_SIZE.X / 3
	for i = 1, 3 do
		local d = rng:NextNumber(BLOOM_D_MIN, BLOOM_D_MAX)
		local x = -BED_SIZE.X / 2 + step * (i - 0.5) + rng:NextNumber(-0.2, 0.2)
		local cf = cframe * CFrame.new(x, BED_SIZE.Y + d / 2 - BLOOM_SINK, rng:NextNumber(-0.15, 0.15))
		BuildKit.part(model, `Bloom{i}`, Vector3.one * d, cf.Position, {
			color = if i == greenAt then WorldPalette.hedge else WorldPalette.blossom,
			material = Enum.Material.Grass,
			shape = Enum.PartType.Ball,
			collide = false,
		})
	end
	model.Parent = parent
	return model
end

--- 등 불빛. 부지당 광원 수(§12.1)에 들어간다
local function lampLight(bulb: BasePart)
	local light = Instance.new("PointLight")
	light.Color = WorldPalette.lampGlow
	light.Range = LAMP_LIGHT_RANGE
	light.Brightness = LAMP_LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = bulb
end

--[[
	벽등 하나. cframe = 벽 바깥 면 위 등 밑변 자리, LookVector = 벽 바깥 방향.
	파트 하나라도 못 불러오면 전체를 파트로 짓는다(받침만 붙은 등이 없게).
]]
function PropLibrary.wallLamp(parent: Instance, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "WallLamp"
	local meshes: { MeshPart } = {}
	for _, piece in PropAssets.WALL_LAMP.pieces do
		local mesh = cloneMesh(piece.id)
		if not mesh then
			for _, made in meshes do
				made:Destroy()
			end
			table.clear(meshes)
			break
		end
		table.insert(meshes, mesh)
	end

	if #meshes > 0 then
		-- 생성물은 등이 +Z 로 나와 있다. 반 바퀴 돌려 cframe 의 앞(-Z)으로 낸다
		local base = cframe * CFrame.Angles(0, math.pi, 0)
		for i, piece in PropAssets.WALL_LAMP.pieces do
			local mesh = meshes[i]
			mesh.Name = piece.name
			mesh.Size = piece.size * LAMP_SCALE
			mesh.CFrame = base * CFrame.new(piece.offset * LAMP_SCALE)
			mesh.TextureID = if piece.texture ~= 0 then `rbxassetid://{piece.texture}` else ""
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CastShadow = false
			mesh.Parent = model
		end
		local bulb = meshes[#meshes]
		bulb.Material = Enum.Material.Neon
		bulb.Color = WorldPalette.lampGlow
		bulb.TextureID = ""
		lampLight(bulb)
		model.Parent = parent
		return model
	end

	-- 폴백: 벽판 → 팔 → 지붕 아래 매단 불빛 상자. 크기는 메시와 같은 틀(높이 2.3 · 깊이 1.8) × LAMP_SCALE
	local s = LAMP_SCALE
	local function add(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		local cf = cframe * CFrame.new(offset * s)
		return BuildKit.part(model, name, size * s, cf.Position, {
			color = color,
			material = material,
			cframe = cf.Rotation,
			collide = false,
			cast = false,
		})
	end
	add("Plate", Vector3.new(0.6, 1.8, 0.15), Vector3.new(0, 1.3, -0.075), WorldPalette.lampIron)
	add("Arm", Vector3.new(0.2, 0.2, 1.1), Vector3.new(0, 1.9, -0.7), WorldPalette.lampIron)
	add("Cap", Vector3.new(1.1, 0.35, 1.1), Vector3.new(0, 1.7, -1.3), WorldPalette.lampIron)
	local glow =
		add("Glow", Vector3.new(0.75, 1.1, 0.75), Vector3.new(0, 0.95, -1.3), WorldPalette.lampGlow, Enum.Material.Neon)
	lampLight(glow)
	model.Parent = parent
	return model
end

--[[
	Creator Store 모델 하나. 서버에서 InsertService:LoadAsset 을 pcall 로 부른다(게임 소유자가 쓸 수 있는 에셋만 된다).
	들어온 모델은 파트·메시·겉면·묶음만 남기고(허용 목록) 나머지는 지우고, 파트는 Anchored·CanCollide false 로 둔다(장식이라 막지 않는다).
	밑면 중심이 cframe 에 오게 옮긴다. 파트 수가 entry.parts 와 다르면 warn, entry.parts × STORE_PARTS_MAX_RATIO 를 넘으면 버린다(nil).
]]
function PropLibrary.storeModel(parent: Instance, entry: PropAssets.StoreModel, cframe: CFrame): Model?
	if entry.id == 0 then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(entry.id)
	end)
	if not ok or not container then
		warn(`PropLibrary: 스토어 모델 {entry.name}({entry.id}) 을 못 불러왔다 ({container})`)
		return nil
	end

	local model = Instance.new("Model")
	model.Name = entry.name
	for _, child in container:GetChildren() do
		child.Parent = model
	end
	container:Destroy()

	-- 허용 목록: 모양(파트·메시·겉면)과 묶음(Model·Folder)만 남긴다. 스크립트·조명·소리·이미터·프롬프트 등은 전부 지운다
	-- (§12.1 조명 수 불변·서버 이미터 0, §12.2 검수 안 한 소리·상호작용 없음). 에셋 작성자가 나중에 바꿔도 이 틀을 못 넘는다
	for _, d in model:GetDescendants() do
		if
			d.Parent
			and not (
				d:IsA("BasePart")
				or d:IsA("DataModelMesh")
				or d:IsA("SurfaceAppearance")
				or d:IsA("Model")
				or d:IsA("Folder")
			)
		then
			d:Destroy()
		end
	end
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			parts += 1
		end
		if d:IsA("Seat") or d:IsA("VehicleSeat") then
			(d :: any).Disabled = true -- 앉지 못하게(장식)
		end
	end
	if parts ~= entry.parts then
		warn(`PropLibrary: 스토어 모델 {entry.name} 파트 {parts} ≠ 게이트 때 {entry.parts}`)
	end
	if parts == 0 or parts > entry.parts * PropAssets.STORE_PARTS_MAX_RATIO then
		model:Destroy()
		return nil
	end

	-- 바운딩 박스 밑면 중심(월드 축) → cframe. 모델 자체 방향은 cframe 의 회전만큼 돌린다
	local box, size = model:GetBoundingBox()
	local bottom = CFrame.new(box.Position - box.UpVector * size.Y / 2)
	model:PivotTo(cframe * bottom:ToObjectSpace(model:GetPivot()))
	model.Parent = parent
	return model
end

return PropLibrary
