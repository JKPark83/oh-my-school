--!strict
--[[
	꾸미기 아이템 모델 만들기(클라 전용 로컬 파트). 개선계획 §3.5 #10·#10a.
	  build(item, cframe, options?) → Model
	    cframe = 아이템 발자국(w×d 칸) 가운데, 바닥 윗면 높이, 회전까지 들어간 월드 CFrame.
	    파트마다 cframe * CFrame.new(part.offset). offset 은 DecorConfig 계약대로 「칸 중심·바닥 y0 기준」.
	  ★ 서버는 꾸미기 파트를 모른다. 전부 Anchored, CanCollide·CanTouch·CanQuery false 로 만든다.
	    놓인 모델의 충돌(캐릭터와 겹치면 빠져나간 뒤)과 탭으로 고를 내 부지 모델의 CanQuery 는 DecorController 가 켠다.
	  ★ ghost 면 반투명 0.5, 그림자 없음.
	  ★ options.mesh(클라 MeshCache.decor)가 있으면 파트 대신 메시 하나를 파트 상자에 맞춰 넣는다. 서버는 이 모듈을 안 쓴다.
	  ★ cylinder 는 세워서 만든다. size 는 (지름, 높이, 지름)으로 읽고 로블록스 원기둥(축 = X)을 Z 로 90° 눕혀
	    세운다. DecorConfig 에 회전 필드가 없어 눕힌 원기둥은 쓰지 않는다.
]]

local DecorConfig = require(script.Parent.Config.DecorConfig)

local GHOST_TRANSPARENCY = 0.5
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local MESH_FILL = 0.9 -- 메시가 발자국 한 칸에서 쓰는 비율(옆 칸 물건과 붙어 보이지 않게)

local DecorBuilder = {}

-- 메시 원본(클라 MeshCache.decor). height 는 파트 상자 높이 대신 쓸 높이 상한(PropAssets.DECOR)
export type Mesh = { part: MeshPart, yaw: number, height: number? }

export type Options = {
	ghost: boolean?,
	-- 있으면 파트 대신 이 메시 하나를 파트 상자에 맞춰 넣는다
	mesh: Mesh?,
}

--- 파트 폴백 전체를 감싼 상자(발자국 가운데·바닥 y0 기준). cylinder size 도 (지름, 높이, 지름)이라 축 그대로다
local function partsBox(item: DecorConfig.Item): (Vector3, Vector3)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, spec in item.parts do
		lo = lo:Min(spec.offset - spec.size / 2)
		hi = hi:Max(spec.offset + spec.size / 2)
	end
	return lo, hi
end

--- 메시를 상자 안에 비율 그대로 가장 크게, 바닥에 붙여 가운데 둔다.
--- 가로·세로는 파트 상자와 발자국(칸 × MESH_FILL) 중 큰 쪽까지 쓴다. 높이는 mesh.height, 없으면 파트 상자 그대로다
local function buildMesh(item: DecorConfig.Item, cframe: CFrame, mesh: Mesh, ghost: boolean): MeshPart
	local lo, hi = partsBox(item)
	local parts = hi - lo
	local cell = DecorConfig.CELL * MESH_FILL
	local box = Vector3.new(math.max(parts.X, item.w * cell), mesh.height or parts.Y, math.max(parts.Z, item.d * cell))
	local turned = mesh.yaw % 180 ~= 0
	local src = mesh.part.Size
	local fit = if turned then Vector3.new(src.Z, src.Y, src.X) else src
	local k = math.min(box.X / fit.X, box.Y / fit.Y, box.Z / fit.Z)
	local part = mesh.part:Clone()
	part.Name = "Mesh"
	part.Size = src * k
	local center = Vector3.new((lo.X + hi.X) / 2, lo.Y + fit.Y * k / 2, (lo.Z + hi.Z) / 2)
	part.CFrame = cframe * CFrame.new(center) * CFrame.Angles(0, math.rad(mesh.yaw), 0)
	if ghost then
		part.TextureID = "" -- 초록·빨강 틴트가 보이게
	end
	return part
end

local function newPart(shape: string): BasePart
	if shape == "wedge" then
		return Instance.new("WedgePart")
	end
	local part = Instance.new("Part")
	if shape == "ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "cylinder" then
		part.Shape = Enum.PartType.Cylinder
	else
		part.Shape = Enum.PartType.Block
	end
	return part
end

--- item 한 개를 cframe 자리에 만든다. Parent 는 호출자가 잡는다
function DecorBuilder.build(item: DecorConfig.Item, cframe: CFrame, options: Options?): Model
	local ghost = options ~= nil and options.ghost == true
	local model = Instance.new("Model")
	model.Name = item.id
	local mesh = options and options.mesh
	if mesh then
		local part = buildMesh(item, cframe, mesh, ghost)
		part.Transparency = if ghost then GHOST_TRANSPARENCY else 0
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = not ghost
		part.Parent = model
		model.WorldPivot = cframe
		return model
	end
	for i, spec in item.parts do
		local part = newPart(spec.shape)
		part.Name = `P{i}`
		if spec.shape == "cylinder" then
			part.Size = Vector3.new(spec.size.Y, spec.size.X, spec.size.Z)
			part.CFrame = cframe * CFrame.new(spec.offset) * UPRIGHT
		else
			part.Size = spec.size
			part.CFrame = cframe * CFrame.new(spec.offset)
		end
		part.Color = spec.color
		part.Material = spec.material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local base = spec.transparency or 0
		part.Transparency = if ghost then math.max(base, GHOST_TRANSPARENCY) else base
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = not ghost
		part.Parent = model
	end
	model.WorldPivot = cframe
	return model
end

return DecorBuilder
