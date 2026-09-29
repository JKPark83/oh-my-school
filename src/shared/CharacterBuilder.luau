--!nonstrict
--[[
	사람 모델 생성기. 학생 NPC(클라이언트 렌더)와 장식 선생님이 같은 함수를 쓴다. 기획서 §10.

	Humanoid 를 넣지 않는다. 앵커된 MeshPart 조립체다.
	  - 학생 24명 × 12부지에 Humanoid 를 달면 서버든 클라든 버틸 수 없다.
	  - 위치는 렌더 컨트롤러가 PivotTo/BulkMoveTo 로 직접 옮긴다.

	★ 몸은 CharacterAssets 의 메시(AI 생성, 계정에 업로드됨)다.
	★ 메시는 서버가 부팅 때 한 번만 내려받는다(preload). 원형을 ReplicatedStorage 에 두고 이후는 Clone 이다.
	  변형 하나가 실패해도 죽지 않는다 — warn 하고 건너뛴다. 그 변형을 쓰는 학생은 fallbackVariant 로 그린다.
	★ 로컬 좌표 규약: -Z 가 얼굴 방향. 모델 피벗은 발 아래 바닥 중심, 회전 0. PrimaryPart 없음.
	★ 머리 메시 파트 이름은 "HeadMesh". 예전의 센서 "Head" 파트는 없앴다(시선 판정이 사라졌다).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterAssets = require(script.Parent.Config.CharacterAssets)
local Keys = require(script.Parent.Config.Keys)
local StudentConfig = require(script.Parent.Config.StudentConfig)

local CharacterBuilder = {}

export type PersonConfig = {
	variant: string, -- CharacterAssets.VARIANTS 의 키
	fallback: string?, -- variant 원형이 없을 때 대신 쓸 키
	scale: number, -- 체구 배율. 전설 1.05, 나머지 1.0
	sitting: boolean, -- 앉은 자세면 엉덩이를 SIT_HIP 에 맞춘다. 아니면 발을 바닥에 둔다
	collide: boolean, -- 클라이언트 전용 모델은 반드시 false
	shadow: boolean,
	tint: Color3?, -- 몸 전체 색조. fallback 원형으로 그릴 때만 입힌다. nil 이면 원본 텍스처
}

-- 앉은 자세의 엉덩이 높이(= 의자 앉는 면). 시설 가구가 이 값에 맞춰 만들어진다.
CharacterBuilder.SIT_HIP = 1.55
-- 앉은 자세에서 팔뚝 아랫면 높이(= 책상 상판).
CharacterBuilder.SIT_DESK = 2.875
CharacterBuilder.HEAD_MESH = "HeadMesh"
CharacterBuilder.ARM_RIGHT = "ArmRight"
CharacterBuilder.LEGEND_SCALE = 1.05

local PROTOTYPE_FOLDER = Keys.PROTOTYPES
local HEAD_MESH = CharacterBuilder.HEAD_MESH
local ARM_RIGHT = CharacterBuilder.ARM_RIGHT
-- 오른팔의 "내린" 자세. 모델 피벗 기준 상대 CFrame 을 파트 어트리뷰트에 둔다.
local REST_ATTRIBUTE = "RestOffset"
-- 손을 들 때 팔이 어깨를 축으로 앞·위로 도는 각도(라디안)와 바깥쪽 기울기.
-- ★ 머리가 큰 체형이라 곧게(π) 올리면 정면에서 머리에 가려진다. 앞·위 2.6 + 바깥 0.5 가 얼굴 옆으로 나온다.
local RAISE_ANGLE = 2.6
local RAISE_TILT = 0.5

local DOWNLOAD_RETRIES = 3
local FOLDER_WAIT = 30
local VARIANT_WAIT = 15

local function createMeshPart(def: CharacterAssets.PartDef): MeshPart
	local lastError
	for attempt = 1, DOWNLOAD_RETRIES do
		local ok, result = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromAssetId(def.mesh), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if ok then
			return result
		end
		lastError = result
		task.wait(attempt)
	end
	error(`메시 {def.mesh} 를 못 내려받았다: {lastError}`)
end

--[[
	원형 하나. 피벗은 원점(바닥 중심, 회전 0), 치수는 생성 단위 그대로다.
	build 가 Clone 한 뒤 ScaleTo 로 줄이고 PivotTo 로 옮긴다.
]]
local function buildPrototype(key: string, variant: CharacterAssets.Variant): Model
	local model = Instance.new("Model")
	model.Name = key
	model.WorldPivot = CFrame.identity

	local pending = #variant.parts
	local failure: string? = nil
	for _, def in variant.parts do
		task.spawn(function()
			local ok, err = pcall(function()
				local part = createMeshPart(def)
				part.Name = if def.name == "Head" then HEAD_MESH else def.name
				part.TextureID = `rbxassetid://{def.texture}`
				part.Size = def.size
				part.CFrame = CFrame.new(def.offset) * CFrame.Angles(0, def.yaw, 0)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = model
			end)
			if not ok then
				failure = failure or tostring(err)
			end
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
	if failure then
		model:Destroy()
		error(`원형 {key} 조립 실패: {failure}`)
	end
	return model
end

--[[
	서버 부팅 때 한 번. 폴더를 먼저 복제해 두고 원형이 완성되는 대로 하나씩 넣는다 —
	클라이언트는 변형 단위로 WaitForChild 하므로 먼저 된 것부터 그릴 수 있다.
	실패한 변형은 warn 만 하고 건너뛴다. 그 변형의 학생은 fallbackVariant 로 그려진다.
	@return 실패한 변형 키 목록
]]
function CharacterBuilder.preload(): { string }
	assert(
		RunService:IsServer(),
		"preload 는 서버에서만 부른다. 클라이언트는 복제된 원형을 기다린다."
	)
	local folder = ReplicatedStorage:FindFirstChild(PROTOTYPE_FOLDER)
	if folder then
		return {}
	end
	folder = Instance.new("Folder")
	folder.Name = PROTOTYPE_FOLDER
	folder.Parent = ReplicatedStorage

	local pending = 0
	local failed: { string } = {}
	for key, variant in CharacterAssets.VARIANTS do
		pending += 1
		task.spawn(function()
			local ok, err = pcall(function()
				buildPrototype(key, variant).Parent = folder
			end)
			if not ok then
				warn(`[CharacterBuilder] {err}`)
				table.insert(failed, key)
			end
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
	folder:SetAttribute("Ready", true)
	return failed
end

local function prototypeFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(PROTOTYPE_FOLDER)
	if not folder and RunService:IsClient() then
		folder = ReplicatedStorage:WaitForChild(PROTOTYPE_FOLDER, FOLDER_WAIT)
	end
	return folder
end

--- 원형을 찾는다. 클라이언트는 아직 복제 중일 수 있으니 잠깐 기다린다
local function findPrototype(folder: Folder, key: string): Model?
	local proto = folder:FindFirstChild(key)
	if proto then
		return proto :: Model
	end
	if RunService:IsClient() and not folder:GetAttribute("Ready") then
		return folder:WaitForChild(key, VARIANT_WAIT) :: Model?
	end
	return nil
end

--- 실제로 쓸 변형 키. 원형이 없으면 fallback, 그것도 없으면 nil
function CharacterBuilder.resolveVariant(variant: string, fallback: string?): string?
	local folder = prototypeFolder()
	if not folder then
		return nil
	end
	if CharacterAssets.VARIANTS[variant] and findPrototype(folder, variant) then
		return variant
	end
	if fallback and CharacterAssets.VARIANTS[fallback] and findPrototype(folder, fallback) then
		return fallback
	end
	return nil
end

--[[
	@param name 모델 이름
	@param base 발 아래 바닥 중심의 CFrame. -Z 가 얼굴 방향
	@return 모델. 원형이 하나도 없으면 nil (호출자가 warn 하고 건너뛴다)
]]
function CharacterBuilder.build(name: string, base: CFrame, config: PersonConfig): Model?
	local key = CharacterBuilder.resolveVariant(config.variant, config.fallback)
	if not key then
		warn(`[CharacterBuilder] 원형 없음: {config.variant} (대체 {config.fallback or "-"})`)
		return nil
	end
	local variant = CharacterAssets.VARIANTS[key]
	local folder = prototypeFolder() :: Folder
	local model = (folder:FindFirstChild(key) :: Model):Clone()
	model.Name = name

	-- 생성 단위 → 스터드. 키를 기준으로 통째로 줄인다. 피벗(원점)은 안 움직인다.
	local target = if config.sitting then CharacterAssets.SIT_HEIGHT else CharacterAssets.STAND_HEIGHT
	local k = target * config.scale / variant.height
	model:ScaleTo(k)

	-- 앉으면 엉덩이가 의자 면(SIT_HIP)에 오도록 모델 바닥을 그만큼 내린다.
	local bottom = if config.sitting then CharacterBuilder.SIT_HIP * config.scale - variant.hip * k else 0
	model:PivotTo(base * CFrame.new(0, bottom, 0))

	-- 전용 메시는 제 텍스처를 쓴다. 색조는 대체 원형으로 그릴 때만 입혀 누군지 구별한다
	local tint = if key == config.fallback then config.tint else nil
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CanCollide = config.collide
			part.CastShadow = config.shadow
			if tint then
				part.Color = tint
			end
		end
	end

	local arm = model:FindFirstChild(ARM_RIGHT)
	if arm then
		arm:SetAttribute(REST_ATTRIBUTE, model:GetPivot():ToObjectSpace(arm.CFrame))
	end
	model:SetAttribute("Variant", key)

	return model
end

--[[
	오른팔을 어깨(팔 파트 윗면 중심)를 축으로 앞·위로 돌려 든다. 내리면 정확히 제자리다.
	모델 피벗 기준으로 계산하므로 모델이 통째로 옮겨진(idle 흔들림) 뒤에 불러도 맞는다.
]]
function CharacterBuilder.setHandRaised(model: Model, raised: boolean)
	local arm = model:FindFirstChild(ARM_RIGHT)
	local rest = arm and arm:GetAttribute(REST_ATTRIBUTE)
	if not rest then
		return
	end

	local pivot = model:GetPivot()
	local restWorld = pivot * rest
	if not raised then
		arm.CFrame = restWorld
		return
	end

	local shoulder = restWorld.Position + Vector3.new(0, arm.Size.Y / 2, 0)
	local hinge = CFrame.new(shoulder)
		* pivot.Rotation
		* CFrame.Angles(RAISE_ANGLE, 0, RAISE_TILT)
		* pivot.Rotation:Inverse()
	arm.CFrame = hinge * (CFrame.new(-shoulder) * restWorld)
end

--- 오른팔을 내린 자세로 되돌린다(setHandRaised(model, false) 와 같다)
function CharacterBuilder.resetArm(model: Model)
	CharacterBuilder.setHandRaised(model, false)
end

--- 학생 id 로 정해지는 외양. 같은 아이는 어느 부지에서 봐도 같다
function CharacterBuilder.studentConfig(studentId: string): PersonConfig
	local row = StudentConfig.BY_ID[studentId]
	assert(row, `모르는 학생: {studentId}`)
	return {
		variant = row.mesh,
		fallback = row.fallbackVariant,
		scale = if row.tier == "전설" then CharacterBuilder.LEGEND_SCALE else 1,
		sitting = true,
		collide = false,
		shadow = false, -- 24명 × 4부지 그림자는 모바일에서 그대로 프레임이 된다
		tint = row.tint,
	}
end

--- 장식 선생님. seed 홀수 = 남, 짝수 = 여
function CharacterBuilder.teacherConfig(seed: number?): PersonConfig
	local list = CharacterAssets.TEACHERS
	return {
		variant = list[((seed or 1) - 1) % #list + 1],
		fallback = nil,
		scale = 1,
		sitting = false,
		collide = false,
		shadow = false, -- §12.1 NPC CastShadow false
		tint = nil,
	}
end

return CharacterBuilder
