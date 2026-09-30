--!nonstrict
--[[
	파트로 물건을 짓는 데 쓰는 헬퍼들.

	Phase 4까지는 교실 템플릿 안에만 있었다. Phase 5에서 운동장 허브가 생기면서
	같은 코드를 쓰는 곳이 둘이 됐고, 그래서 밖으로 뺐다.
	쓰는 곳이 하나뿐일 때 미리 빼두지 않은 것도 같은 이유다.

	파트가 기본이고, 소품 메시·창 텍스처는 PropAssets 를 거쳐 쓴다(id 0 이면 파트 폴백).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)

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
-- 지붕 아랫면에서 바닥까지 17(체육관 20). 16 이던 때는 바닥이 범위 밖이라 벽 위만 밝고 바닥은 새카맸다.
-- 26 도 모자랐다: 사방이 막힌 방(교실1·2·급식실)은 바닥 가장자리만 밝았고, 밝아 보이던 방은 벽 틈으로 든 하늘빛이었다
local LIGHT_RANGE = 40

-- 박공지붕 처마가 벽 바깥으로 나오는 길이
BuildKit.EAVE = 0.5

--- Part·WedgePart 공통 속성·태그·천장등
local function finish(p: BasePart, parent: Instance, name: string, size: Vector3, position: Vector3, opts: Opts)
	p.Name = name
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
end

function BuildKit.part(parent: Instance, name: string, size: Vector3, position: Vector3, opts: Opts): Part
	local p = Instance.new("Part")
	p.Shape = opts.shape or Enum.PartType.Block
	finish(p, parent, name, size, position, opts)
	return p
end

--- 쐐기 파트. 로컬 +Z 쪽이 높은 변(뒷면 수직), -Z 쪽으로 비탈이 내려간다. opts.shape 는 무시한다
function BuildKit.wedge(parent: Instance, name: string, size: Vector3, position: Vector3, opts: Opts): WedgePart
	local p = Instance.new("WedgePart")
	finish(p, parent, name, size, position, opts)
	return p
end

--[[
	박공지붕 = 쐐기 2개(개선계획 §3.1 #7). 평지붕 1 → 2 라 시설 파트가 1 늘어난다.
	  top    벽 윗면 중심의 월드 CFrame. 용마루는 top 의 로컬 X 방향(긴 변)이다
	  length 용마루 방향 길이, span 용마루와 직각인 전체 폭(둘 다 처마 포함)
	  rise   벽 윗면에서 용마루까지 높이
	쐐기 밑면이 벽 윗면(y=top)에 얹혀서 방 안에서는 평평한 천장으로 보인다.
	천장등(opts.light)은 첫 쐐기(-Z 쪽, 이름 name)에만 단다 → 시설마다 조명 수가 그대로다. 둘째는 name .. "2".
	지붕 윗면·바운딩 박스 꼭대기 = top.Y + rise.
]]
function BuildKit.gableRoof(
	parent: Instance,
	name: string,
	top: CFrame,
	length: number,
	span: number,
	rise: number,
	opts: Opts
): (WedgePart, WedgePart)
	local size = Vector3.new(length, rise, span / 2)
	-- -Z 쪽 쐐기: 높은 변(+Z)이 가운데. +Z 쪽 쐐기는 Y 로 반 바퀴 돌려 높은 변이 가운데를 보게 한다
	local a = top * CFrame.new(0, rise / 2, -span / 4)
	local b = top * CFrame.new(0, rise / 2, span / 4) * CFrame.Angles(0, math.pi, 0)
	local optsA = table.clone(opts)
	optsA.cframe = a.Rotation
	local optsB = table.clone(opts)
	optsB.cframe = b.Rotation
	optsB.light = false
	return BuildKit.wedge(parent, name, size, a.Position, optsA),
		BuildKit.wedge(parent, name .. "2", size, b.Position, optsB)
end

--[[
	바깥벽 창(개선계획 §3.1 #8). PropAssets.WINDOW_TEXTURE.id 가 0 이면 아무것도 안 붙이고 nil.
	Texture 는 파트가 아니라 파트 예산에 들지 않는다. face 는 벽의 바깥 면(옆면 4개 중 하나).
	칸 폭·세로 위치는 PropAssets.windowTile 이 정한다: 창 아랫변이 벽 아랫면 + sill.
]]
function BuildKit.window(part: BasePart, face: Enum.NormalId): Texture?
	local spec = PropAssets.WINDOW_TEXTURE
	if spec.id == 0 then
		return nil
	end
	assert(face ~= Enum.NormalId.Top and face ~= Enum.NormalId.Bottom, "BuildKit.window: 옆면에만 붙인다")
	local height = part.Size.Y
	local width = if face == Enum.NormalId.Front or face == Enum.NormalId.Back then part.Size.X else part.Size.Z
	local tileU, offsetV = PropAssets.windowTile(width, height)

	local t = Instance.new("Texture")
	t.Name = "Window"
	t.Face = face
	t.Texture = "rbxassetid://" .. spec.id
	t.StudsPerTileU = tileU
	t.StudsPerTileV = spec.studsPerTile.Y
	t.OffsetStudsV = offsetV
	t.Transparency = 0
	t.Parent = part
	return t
end

--[[
	도서관 책 판 앞면의 책등 그림. PropAssets.BOOKSHELF_TEXTURE.id 가 0 이면 nil(색 판 폴백).
	가로는 면 폭을 칸으로 딱 나눠 양 끝에서 책이 잘리지 않게, 세로는 면 높이 한 칸.
]]
local BOOKSHELF_BACK = Color3.fromRGB(74, 48, 28) -- bookshelf.png 뒤판 색

function BuildKit.bookshelf(part: BasePart, face: Enum.NormalId): Texture?
	local spec = PropAssets.BOOKSHELF_TEXTURE
	if spec.id == 0 then
		return nil
	end
	assert(face ~= Enum.NormalId.Top and face ~= Enum.NormalId.Bottom, "BuildKit.bookshelf: 옆면에만 붙인다")
	local width = if face == Enum.NormalId.Front or face == Enum.NormalId.Back then part.Size.X else part.Size.Z

	local t = Instance.new("Texture")
	t.Name = "Books"
	t.Face = face
	t.Texture = "rbxassetid://" .. spec.id
	t.StudsPerTileU = width / math.max(1, math.round(width / spec.studsPerTileU))
	t.StudsPerTileV = part.Size.Y
	t.Parent = part
	part.Color = BOOKSHELF_BACK -- 옆면에 폴백 색 띠가 비치지 않게 그림 뒤판 색으로
	return t
end

--[[
	방 안 디테일 그림(PropAssets.INTERIOR). 그림 한 장을 면 전체에 늘려 붙인다. id 0 이면 nil(장식만 빠진다).
	투명 덧그림(사물함 문·수납장)은 파트 색이 비쳐서 같은 그림으로 색을 바꿔 쓸 수 있다.
	Decal 은 파트가 아니라 파트 예산에 들지 않는다.
]]
function BuildKit.decal(part: BasePart, face: Enum.NormalId, id: number, name: string?): Decal?
	if id == 0 then
		return nil
	end
	local d = Instance.new("Decal")
	d.Name = name or "Detail"
	d.Face = face
	d.Texture = "rbxassetid://" .. id
	d.Parent = part
	return d
end

--- 벽 안쪽 아래 걸레받이 띠(wainscot.png 아래 22%). 흰 그림을 color 로 물들인다. 벽 높이가 달라도 띠 비율은 같다
function BuildKit.wainscot(wall: BasePart, face: Enum.NormalId, color: Color3): Decal?
	local d = BuildKit.decal(wall, face, PropAssets.INTERIOR.WAINSCOT, "Wainscot")
	if d then
		d.Color3 = color
	end
	return d
end

--- 바닥 윗면 타일(한 장 = PropAssets.FLOOR_TILE_STUDS). 줄눈 색이 밝은 회색이라 파트 색은 타일 색이 된다
function BuildKit.floorTile(floor: BasePart): Texture?
	local id = PropAssets.INTERIOR.FLOOR_TILE
	if id == 0 then
		return nil
	end
	local t = Instance.new("Texture")
	t.Name = "Tile"
	t.Face = Enum.NormalId.Top
	t.Texture = "rbxassetid://" .. id
	t.StudsPerTileU = PropAssets.FLOOR_TILE_STUDS
	t.StudsPerTileV = PropAssets.FLOOR_TILE_STUDS
	t.Parent = floor
	return t
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
