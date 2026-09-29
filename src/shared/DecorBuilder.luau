--!strict
--[[
	꾸미기 아이템 모델 만들기(클라 전용 로컬 파트). 개선계획 §3.5 #10·#10a.
	  build(item, cframe, options?) → Model
	    cframe = 아이템 발자국(w×d 칸) 가운데, 바닥 윗면 높이, 회전까지 들어간 월드 CFrame.
	    파트마다 cframe * CFrame.new(part.offset). offset 은 DecorConfig 계약대로 「칸 중심·바닥 y0 기준」.
	  ★ 서버는 꾸미기 파트를 모른다. 전부 Anchored, CanCollide·CanTouch false(10a: 통과 가능).
	    CanQuery 도 false 로 만든다. 탭으로 고를 내 부지 배치 모델만 DecorController 가 켠다.
	  ★ ghost 면 반투명 0.5, 그림자 없음.
	  ★ cylinder 는 세워서 만든다. size 는 (지름, 높이, 지름)으로 읽고 로블록스 원기둥(축 = X)을 Z 로 90° 눕혀
	    세운다. DecorConfig 에 회전 필드가 없어 눕힌 원기둥은 쓰지 않는다.
]]

local DecorConfig = require(script.Parent.Config.DecorConfig)

local GHOST_TRANSPARENCY = 0.5
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local DecorBuilder = {}

export type Options = {
	ghost: boolean?,
}

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
