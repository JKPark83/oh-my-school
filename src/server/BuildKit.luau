--!nonstrict
--[[
	파트로 물건을 짓는 데 쓰는 헬퍼 두 개.

	Phase 4까지는 교실 템플릿 안에만 있었다. Phase 5에서 운동장 허브가 생기면서
	같은 코드를 쓰는 곳이 둘이 됐고, 그래서 밖으로 뺐다.
	쓰는 곳이 하나뿐일 때 미리 빼두지 않은 것도 같은 이유다.

	아트 에셋을 쓰지 않는다는 원칙은 그대로다. 전부 파트와 기본 머티리얼이다.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)

local BuildKit = {}

export type Opts = {
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	cframe: CFrame?,
	collide: boolean?,
	cast: boolean?,
	shape: Enum.PartType?,
	fade: boolean?, -- 카메라를 가리면 반투명해진다. RoomKeys.FADE_TAG 참고
}

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
		CollectionService:AddTag(p, RoomKeys.FADE_TAG)
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

return BuildKit
