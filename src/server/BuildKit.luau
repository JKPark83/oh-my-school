--!nonstrict
--[[
	파트로 물건을 짓는 데 쓰는 헬퍼들.

	Phase 4까지는 교실 템플릿 안에만 있었다. Phase 5에서 운동장 허브가 생기면서
	같은 코드를 쓰는 곳이 둘이 됐고, 그래서 밖으로 뺐다.
	쓰는 곳이 하나뿐일 때 미리 빼두지 않은 것도 같은 이유다.

	아트 에셋을 쓰지 않는다는 원칙은 그대로다. 전부 파트와 기본 머티리얼이다.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local BuildKit = {}

export type Opts = {
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	cframe: CFrame?,
	collide: boolean?,
	cast: boolean?,
	shape: Enum.PartType?,
	fade: boolean?, -- 카메라를 가리면 반투명해진다. Keys.FADE_TAG 참고
	light: boolean?, -- 천장등. 지붕 파트에만 켠다. 아랫면에 SurfaceLight 를 단다
}

-- 천장등. 지붕이 그림자를 드리워 방 안이 Ambient 만으로는 어둡다.
-- 그림자를 끄는 것은 저사양 폰 때문이다 — 부지당 13개(교실1·현관 3 + 시설 10)가 켜진다.
local LIGHT_COLOR = Color3.fromRGB(255, 244, 226)
local LIGHT_BRIGHTNESS = 1.2
local LIGHT_RANGE = 16 -- 지붕 아랫면에서 바닥까지 12~14

function BuildKit.part(parent: Instance, name: string, size: Vector3, position: Vector3, opts: Opts): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = opts.shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = if opts.cframe then CFrame.new(position) * opts.cframe else CFrame.new(position)
	p.Color = opts.color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Transparency = opts.transparency or 0
	p.Anchored = true
	p.CanCollide = if opts.collide == nil then true else opts.collide
	p.CastShadow = if opts.cast == nil then true else opts.cast
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent

	-- 태그는 여기 한 곳에서 붙인다. 짓는 쪽은 fade = true 한 줄만 쓰면 된다.
	if opts.fade then
		CollectionService:AddTag(p, Keys.FADE_TAG)
	end

	if opts.light then
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 90
		light.Color = LIGHT_COLOR
		light.Brightness = LIGHT_BRIGHTNESS
		light.Range = LIGHT_RANGE
		light.Shadows = false
		light.Parent = p
	end

	return p
end

--[[
	SurfaceGui 로 글자를 넣는다. 텍스처 에셋 없이 한글을 표시하는 유일한 방법이고,
	"한국 초등학교"라는 인상은 결국 벽에 붙은 글자에서 나온다.

	@return 만들어진 TextLabel. 학년이 바뀔 때 칠판·급훈·시간표의 글자를 갈아끼워야 해서
	        돌려준다. 나중에 target 을 뒤져 찾는 것보다 지을 때 받아두는 편이 확실하다 —
	        찾는 쪽은 이름이 어긋나도 조용히 nil 을 받고, 그러면 글자만 1학년에 남는다.
]]
function BuildKit.surfaceText(
	target: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	scale: number
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1 -- 조명을 받아야 벽에 인쇄된 것처럼 보인다
	gui.Parent = target

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.86)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = color
	label.TextScaled = false
	label.TextSize = math.floor(40 * scale)
	label.TextWrapped = true
	label.RichText = true
	label.Text = text
	label.Parent = gui

	return label
end

--- Model/Folder 바로 아래 Attachment 는 엔진이 가장 가까운 조상 Model 의 피벗 기준으로 WorldCFrame 을 계산한다.
--- Geometry 는 CFrame 에 월드 CFrame 을 넣으므로, 피벗을 고정한 뒤 그 기준의 로컬 CFrame 으로 바꿔 준다.
--- 시설·실루엣 모델을 만든 직후 한 번 부른다(Workspace 에 넣기 전).
function BuildKit.localizeAttachments(model: Model)
	local pivot = model:GetPivot()
	-- PrimaryPart 가 남아 있으면 피벗이 그 파트를 따라가서, 클라 등장 연출(파트를 내렸다 올림) 동안 자리도 같이 내려간다
	model.PrimaryPart = nil
	model.WorldPivot = pivot
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and not d.Parent:IsA("BasePart") then
			d.CFrame = pivot:ToObjectSpace(d.CFrame)
		end
	end
end

--[[
	부품 번호 검사(개선계획 §3.4). 모델 안 모든 BasePart 에 PartIndex 가 1..count 정수로 붙어 있고
	1..count 각 번호가 파트 하나 이상에 쓰였는지 본다. Geometry build 끝에서 부른다.
	PlotService 가 이 번호로 부품 k 의 파트만 골라 부지에 넣으므로, 빠진 번호가 있으면 그 부품을 사도 아무것도 안 생긴다.
]]
function BuildKit.assertPartIndex(model: Model, count: number)
	local used = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local index = d:GetAttribute(Keys.ATTR_PART_INDEX)
			if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > count then
				error(`{model.Name}: 파트 {d.Name} 의 {Keys.ATTR_PART_INDEX}({index}) 가 1..{count} 밖이다`, 2)
			end
			used[index] = true
		end
	end
	for k = 1, count do
		if not used[k] then
			error(`{model.Name}: 부품 {k} 번을 쓴 파트가 없다(1..{count})`, 2)
		end
	end
end

return BuildKit
