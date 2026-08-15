--!nonstrict
--[[
	사람 모델 생성기. 선생님(서버)과 학생(클라이언트)이 같은 함수를 쓴다.

	Humanoid 를 넣지 않는다. 앵커된 파트 조립체다.
	  - 학생 18명 x 12슬롯에 Humanoid 를 달면 서버든 클라든 버틸 수 없다.
	  - 선생님은 상태머신이 PivotTo 로 직접 돌린다. Humanoid 의 이동/애니메이션이 필요 없다.

	★ 로컬 좌표 규약: -Z 가 얼굴 방향이다.
	  로블록스 CFrame 의 LookVector 가 -Z 이므로, base = CFrame.lookAt(위치, 바라볼곳) 을
	  넘기면 얼굴이 자동으로 그쪽을 향한다. 항등 CFrame 이면 칠판(-Z)을 본다.

	치수는 scale = 1 기준 키 약 5.6 스터드(로블록스 기본 캐릭터와 비슷)다.
	scale 만 바꾸면 초등학생 체구가 된다.
]]

local CharacterBuilder = {}

export type Pose = "STAND" | "SIT"

export type PersonConfig = {
	scale: number,
	pose: Pose,
	skin: Color3,
	hair: Color3,
	shirt: Color3,
	pants: Color3,
	glasses: boolean,
	face: string, -- FACES 의 키. 표정
	collide: boolean, -- 클라이언트 전용 모델은 반드시 false. 서버가 모르는 충돌이 생기면 위치가 어긋난다
	shadow: boolean,
}

-- 앉은 자세의 엉덩이 높이(= 의자 앉는 면). 교실 가구가 이 값에 맞춰 만들어진다.
CharacterBuilder.SIT_HIP = 1.55
-- 앉은 자세에서 팔뚝 아랫면 높이(= 책상 상판). 팔이 책상에 정확히 얹힌다.
CharacterBuilder.SIT_DESK = 2.875

local function darken(color: Color3, amount: number): Color3
	return Color3.new(color.R * amount, color.G * amount, color.B * amount)
end

type PartSpec = {
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
}

local function emit(model: Model, base: CFrame, config: PersonConfig, spec: PartSpec): BasePart
	local s = config.scale
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Size = spec.size * s
	p.CFrame = base * CFrame.new(spec.offset * s)
	p.Color = spec.color
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency or 0
	p.Anchored = true
	p.CanCollide = config.collide
	p.CanQuery = false -- 시야 레이캐스트 대상이 아니다. 엄폐물은 Cover 태그가 정한다
	p.CanTouch = false
	p.CastShadow = config.shadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

--[[
	표정. 머리 앞면(-Z)에 SurfaceGui 로 그린다.

	★ 파트로 만들지 않는다. 원래 눈은 0.2 x 0.26 스터드짜리 파트였는데,
	  1.5 스터드 머리에 붙은 그 크기는 플레이 거리에서 그냥 사라진다.
	  파트를 키우면 이번엔 얼굴에서 튀어나온 검은 블록이 된다.
	  평면에 그리면 크기를 마음대로 키워도 머리 모양이 안 망가진다.

	★ 이미지를 안 쓴다. 텍스처를 올리려면 에셋 승인을 기다려야 하고,
	  이 프로젝트는 업로드 없이 돌아가는 것이 규칙이다. Frame + UICorner 로
	  둥근 알약을 만들고 Rotation 으로 눈썹과 입꼬리 각도를 준다 —
	  표정을 만드는 건 눈이 아니라 눈썹 각도와 입꼬리 방향이다.

	★ 코는 파트로 남겨둔다. 코만은 튀어나와 있어야 옆에서 봐도 얼굴로 읽히고,
	  SurfaceGui 는 표면 평면에 그려지므로 앞으로 나온 코가 자연스럽게 가린다.
]]
local FACE_INK = Color3.fromRGB(28, 24, 26)
local FACE_BLUSH = Color3.fromRGB(240, 150, 150)

type FaceDef = {
	brow: number, -- 눈썹 회전(도). +면 안쪽 끝이 내려간다 = 화난 얼굴
	browY: number,
	eyeH: number, -- 눈 높이. 작을수록 게슴츠레하다
	mouth: string,
	blush: boolean,
}

local FACES: { [string]: FaceDef } = {
	-- 수업 중인 아이들. 대부분 무표정이거나 지루하다
	NEUTRAL = { brow = 0, browY = 0.34, eyeH = 0.22, mouth = "FLAT", blush = false },
	BORED = { brow = 5, browY = 0.355, eyeH = 0.085, mouth = "FLAT", blush = false },
	SMILE = { brow = -6, browY = 0.325, eyeH = 0.22, mouth = "SMILE", blush = true },
	GRIN = { brow = -9, browY = 0.315, eyeH = 0.2, mouth = "OPEN", blush = true },
	WORRY = { brow = -15, browY = 0.33, eyeH = 0.25, mouth = "FROWN", blush = false },

	-- 선생님. 돌아본 순간에 읽혀야 하는 얼굴이라 눈썹을 가장 세게 꺾는다
	STERN = { brow = 17, browY = 0.305, eyeH = 0.15, mouth = "FROWN", blush = false },
}

-- 입 조각. x, y 는 얼굴 안의 절대 위치(0~1), rot 는 회전(도)
type MouthSeg = { x: number, y: number, w: number, h: number, rot: number }

local MOUTHS: { [string]: { MouthSeg } } = {
	FLAT = { { x = 0.5, y = 0.755, w = 0.24, h = 0.05, rot = 0 } },
	-- 두 조각이 아래 가운데에서 만나 ∪ 를 만든다
	SMILE = {
		{ x = 0.43, y = 0.747, w = 0.15, h = 0.05, rot = 22 },
		{ x = 0.57, y = 0.747, w = 0.15, h = 0.05, rot = -22 },
	},
	FROWN = {
		{ x = 0.43, y = 0.763, w = 0.15, h = 0.05, rot = -22 },
		{ x = 0.57, y = 0.763, w = 0.15, h = 0.05, rot = 22 },
	},
	-- 벌린 입. 조각 하나를 크게 키우고 UICorner 로 타원을 만든다
	OPEN = { { x = 0.5, y = 0.76, w = 0.2, h = 0.17, rot = 0 } },
}

local function pill(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	return frame
end

local function emitFace(head: BasePart, faceKey: string)
	local def = FACES[faceKey] or FACES.NEUTRAL

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front -- = -Z. 이 프로젝트의 얼굴 방향 규약과 같다
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 64
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- 0 이면 어두운 교실에서도 얼굴만 형광등처럼 뜬다. 1 이면 복도쪽 자리에서 표정이 안 보인다.
	gui.LightInfluence = 0.4
	-- 교실 대각선이 약 45 스터드다. 그보다 멀면 그릴 필요가 없다.
	gui.MaxDistance = 80
	gui.Parent = head

	local root = Instance.new("Frame")
	root.Name = "Ink"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	for _, side in { -1, 1 } do
		local ex = 0.5 + 0.235 * side
		local suffix = if side < 0 then "L" else "R"

		if def.blush then
			pill(root, `Blush{suffix}`, 0.5 + 0.33 * side, 0.63, 0.16, 0.1, FACE_BLUSH).BackgroundTransparency = 0.45
		end

		pill(root, `Brow{suffix}`, ex, def.browY, 0.2, 0.045, FACE_INK).Rotation = def.brow * side
		pill(root, `Eye{suffix}`, ex, 0.47, 0.17, def.eyeH, FACE_INK)

		-- 눈동자에 찍는 흰 점 하나가 "인형"과 "살아있는 얼굴"을 가른다.
		-- 눈이 가늘 때는 점이 눈 밖으로 삐져나오므로 생략한다.
		if def.eyeH > 0.12 then
			pill(root, `Glint{suffix}`, ex - 0.035 * side, 0.44, 0.05, 0.055, Color3.fromRGB(255, 255, 255))
		end
	end

	for i, seg in MOUTHS[def.mouth] do
		pill(root, `Mouth{i}`, seg.x, seg.y, seg.w, seg.h, FACE_INK).Rotation = seg.rot
	end
end

--[[
	얼굴. 머리 중심 높이(yh)만 받으면 서 있든 앉아 있든 같은 코드로 붙는다.
	머리 반지름이 0.75 이므로 앞면은 z = -0.75. 얼굴 파트는 그보다 살짝 앞으로 낸다.
]]
local function emitHead(model: Model, base: CFrame, config: PersonConfig, yh: number)
	local specs: { PartSpec } = {
		{ name = "Head", size = Vector3.new(1.5, 1.5, 1.5), offset = Vector3.new(0, yh, 0), color = config.skin },

		-- 머리카락. 정수리 + 앞머리. 이 둘만 있어도 "사람"으로 읽힌다
		{
			name = "Hair",
			size = Vector3.new(1.62, 0.55, 1.62),
			offset = Vector3.new(0, yh + 0.85, 0),
			color = config.hair,
		},
		{
			name = "Fringe",
			size = Vector3.new(1.62, 0.38, 0.22),
			offset = Vector3.new(0, yh + 0.58, -0.72),
			color = config.hair,
		},

		-- 코만 파트다. 이유는 위 emitFace 주석에 있다
		{
			name = "Nose",
			size = Vector3.new(0.16, 0.22, 0.18),
			offset = Vector3.new(0, yh - 0.12, -0.79),
			color = darken(config.skin, 0.88),
		},
	}

	local head: BasePart? = nil
	for _, spec in specs do
		local p = emit(model, base, config, spec)
		if spec.name == "Head" then
			head = p
		end
	end
	assert(head, "Head 파트를 못 만들었다.")
	emitFace(head, config.face)

	if not config.glasses then
		return
	end

	-- 안경알은 반투명이라 눈이 비친다. 불투명하게 하면 눈을 가려 표정이 사라진다.
	local lensSize = Vector3.new(0.52, 0.5, 0.06)
	emit(model, base, config, {
		name = "GlassLeft",
		size = lensSize,
		offset = Vector3.new(-0.35, yh + 0.05, -0.8),
		color = Color3.fromRGB(210, 230, 240),
		transparency = 0.5,
	})
	emit(model, base, config, {
		name = "GlassRight",
		size = lensSize,
		offset = Vector3.new(0.35, yh + 0.05, -0.8),
		color = Color3.fromRGB(210, 230, 240),
		transparency = 0.5,
	})
	emit(model, base, config, {
		name = "GlassBridge",
		size = Vector3.new(0.3, 0.07, 0.06),
		offset = Vector3.new(0, yh + 0.05, -0.81),
		color = Color3.fromRGB(50, 50, 55),
	})
end

local function emitStanding(model: Model, base: CFrame, config: PersonConfig)
	local leg = Vector3.new(0.95, 2.0, 0.95)
	local arm = Vector3.new(0.85, 2.0, 0.85)

	local specs: { PartSpec } = {
		{ name = "LegLeft", size = leg, offset = Vector3.new(-0.5, 1.0, 0), color = config.pants },
		{ name = "LegRight", size = leg, offset = Vector3.new(0.5, 1.0, 0), color = config.pants },
		{
			name = "Torso",
			size = Vector3.new(2.0, 2.0, 1.0),
			offset = Vector3.new(0, 3.0, 0),
			color = config.shirt,
			material = Enum.Material.Fabric,
		},
		{ name = "ArmLeft", size = arm, offset = Vector3.new(-1.42, 3.0, 0), color = config.skin },
		{ name = "ArmRight", size = arm, offset = Vector3.new(1.42, 3.0, 0), color = config.skin },
	}

	for _, spec in specs do
		emit(model, base, config, spec)
	end
	emitHead(model, base, config, 4.8)
end

--[[
	앉은 자세. 무릎을 앞(-Z)으로 접고 팔뚝을 책상 위에 얹는다.
	관절이 없으므로 허벅지/정강이를 별도 파트로 꺾어 만든다.
]]
local function emitSitting(model: Model, base: CFrame, config: PersonConfig)
	local shin = Vector3.new(0.85, 1.55, 0.85)
	local thigh = Vector3.new(0.85, 0.85, 2.2)
	local arm = Vector3.new(0.85, 0.85, 1.9)

	local specs: { PartSpec } = {
		{ name = "ShinLeft", size = shin, offset = Vector3.new(-0.48, 0.775, -1.5), color = config.pants },
		{ name = "ShinRight", size = shin, offset = Vector3.new(0.48, 0.775, -1.5), color = config.pants },
		{ name = "ThighLeft", size = thigh, offset = Vector3.new(-0.48, 1.98, -0.55), color = config.pants },
		{ name = "ThighRight", size = thigh, offset = Vector3.new(0.48, 1.98, -0.55), color = config.pants },
		{
			name = "Torso",
			size = Vector3.new(2.0, 2.0, 1.0),
			offset = Vector3.new(0, 3.4, 0),
			color = config.shirt,
			material = Enum.Material.Fabric,
		},
		{ name = "ArmLeft", size = arm, offset = Vector3.new(-1.42, 3.3, -0.95), color = config.skin },
		{ name = "ArmRight", size = arm, offset = Vector3.new(1.42, 3.3, -0.95), color = config.skin },
	}

	for _, spec in specs do
		emit(model, base, config, spec)
	end
	emitHead(model, base, config, 5.15)
end

--[[
	@param name 모델 이름
	@param base 발이 닿는 바닥 높이의 CFrame. LookVector 가 얼굴 방향이 된다
	@param config 체구/색/자세

	PrimaryPart 는 Torso 다. 선생님 회전(PivotTo)이 몸통 중심을 축으로 돌게 하기 위해서다.
	TeacherAI 는 model:FindFirstChild("Head") 로 시야 기준점을 찾으므로,
	모든 파트를 모델의 직계 자식으로 둔다(폴더로 감싸지 않는다).
]]
function CharacterBuilder.build(name: string, base: CFrame, config: PersonConfig): Model
	local model = Instance.new("Model")
	model.Name = name

	if config.pose == "SIT" then
		emitSitting(model, base, config)
	else
		emitStanding(model, base, config)
	end

	model.PrimaryPart = model:FindFirstChild("Torso") :: BasePart
	return model
end

-- ── 프리셋 ────────────────────────────────────────────────────────

local SKINS = {
	Color3.fromRGB(245, 214, 185),
	Color3.fromRGB(232, 195, 162),
	Color3.fromRGB(214, 172, 138),
	Color3.fromRGB(190, 145, 112),
}
local HAIRS = {
	Color3.fromRGB(30, 26, 26),
	Color3.fromRGB(48, 34, 28),
	Color3.fromRGB(72, 48, 34),
	Color3.fromRGB(20, 18, 20),
}
local SHIRTS = {
	Color3.fromRGB(235, 235, 240), -- 흰 체육복
	Color3.fromRGB(120, 175, 225),
	Color3.fromRGB(230, 150, 160),
	Color3.fromRGB(150, 200, 160),
	Color3.fromRGB(250, 210, 120),
	Color3.fromRGB(180, 165, 220),
}
local PANTS = {
	Color3.fromRGB(60, 70, 95),
	Color3.fromRGB(40, 45, 55),
	Color3.fromRGB(90, 80, 70),
	Color3.fromRGB(70, 90, 80),
}

--[[
	표정 뽑기 통. 수업 중이라 무표정과 지루함이 많고, 웃는 아이가 몇 명 섞인다.
	같은 확률로 여섯 표정을 돌리면 교실이 아니라 놀이터가 된다.
]]
local FACE_POOL = { "NEUTRAL", "NEUTRAL", "NEUTRAL", "BORED", "BORED", "BORED", "SMILE", "SMILE", "GRIN", "WORRY" }

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

--[[
	학생 프리셋. seatIndex 로 시드를 고정하므로 같은 자리는 항상 같은 아이가 앉는다.
	재접속할 때마다 반 아이들 얼굴이 바뀌면 "내 교실"이라는 느낌이 사라진다.
]]
function CharacterBuilder.studentConfig(seatIndex: number): PersonConfig
	local rng = Random.new(seatIndex * 7919)
	return {
		scale = rng:NextNumber(0.82, 0.9),
		pose = "SIT",
		skin = pick(SKINS, rng),
		hair = pick(HAIRS, rng),
		shirt = pick(SHIRTS, rng),
		pants = pick(PANTS, rng),
		glasses = rng:NextNumber() < 0.25,
		face = pick(FACE_POOL, rng),
		collide = false, -- 클라이언트 전용. 서버가 모르는 벽을 만들면 안 된다
		shadow = false, -- 216개 그림자는 모바일에서 그대로 프레임이 된다
	}
end

function CharacterBuilder.teacherConfig(): PersonConfig
	return {
		scale = 1,
		pose = "STAND",
		skin = Color3.fromRGB(238, 205, 178),
		hair = Color3.fromRGB(35, 30, 30),
		shirt = Color3.fromRGB(95, 105, 140), -- 남색 정장 상의
		pants = Color3.fromRGB(55, 60, 75),
		glasses = true,
		face = "STERN",
		collide = true,
		shadow = true,
	}
end

return CharacterBuilder
