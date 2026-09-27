--!nonstrict
--[[
	사람 모델 생성기. 선생님(서버)과 학생(클라이언트)이 같은 함수를 쓴다.

	Humanoid 를 넣지 않는다. 앵커된 MeshPart 조립체다.
	  - 학생 18명 x 12슬롯에 Humanoid 를 달면 서버든 클라든 버틸 수 없다.
	  - 선생님은 상태머신이 PivotTo 로 직접 돌린다. Humanoid 의 이동/애니메이션이 필요 없다.

	★ 몸은 CharacterAssets 의 메시(AI 생성, 계정에 업로드됨)다.
	  예전의 상자 몸 + SurfaceGui 얼굴은 플레이 거리에서 사람으로 안 읽혔다.
	  "업로드 없이 돌아간다"는 규칙은 그래서 버렸다. (CharacterAssets 헤더 참고)

	★ 메시는 서버가 부팅 때 한 번만 내려받는다(preload).
	  AssetService:CreateMeshPartAsync 는 네트워크 호출이다. 변형 11개 x 파트 5개를
	  원형(prototype)으로 만들어 ReplicatedStorage 에 두고, 이후의 build 는 전부 Clone 이다.
	  클라이언트는 원형이 복제되기를 기다렸다가 복제한다 — 클라마다 55번 내려받지 않는다.

	★ 로컬 좌표 규약: -Z 가 얼굴 방향이다.
	  로블록스 CFrame 의 LookVector 가 -Z 이므로, base = CFrame.lookAt(위치, 바라볼곳) 을
	  넘기면 얼굴이 자동으로 그쪽을 향한다. 항등 CFrame 이면 칠판(-Z)을 본다.
	  모델 피벗은 발 아래 바닥 중심이고 회전은 0 이다. PrimaryPart 를 두지 않는다 —
	  메시 파트에는 생성기가 구운 회전이 섞여 있어 그것을 피벗으로 삼으면 "앞"이 틀어진다.

	★ "Head" 는 눈에 안 보이는 센서 파트다. 머리 메시는 "HeadMesh".
	  DetectionService 가 Head.CFrame.LookVector 를 시선으로 쓰는데, 머리 메시 파트의
	  CFrame 은 위에서 말한 구운 회전 때문에 시선이 아니다. 회전 0 인 파트를 머리 중심에
	  하나 두면 그 규약이 그대로 지켜진다.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterAssets = require(script.Parent.Config.CharacterAssets)
local GradeTheme = require(script.Parent.Config.GradeTheme)

local CharacterBuilder = {}

export type PersonConfig = {
	variant: string, -- CharacterAssets.VARIANTS 의 키
	scale: number, -- 체구 배율. 학년(GradeTheme.bodyScale)에서 온다
	sitting: boolean, -- 앉은 자세면 엉덩이를 SIT_HIP 에 맞춘다. 아니면 발을 바닥에 둔다
	collide: boolean, -- 클라이언트 전용 모델은 반드시 false. 서버가 모르는 충돌이 생기면 위치가 어긋난다
	shadow: boolean,
}

-- 앉은 자세의 엉덩이 높이(= 의자 앉는 면). 교실 가구가 이 값에 맞춰 만들어진다.
CharacterBuilder.SIT_HIP = 1.55
-- 앉은 자세에서 팔뚝 아랫면 높이(= 책상 상판). 팔이 책상에 정확히 얹힌다.
CharacterBuilder.SIT_DESK = 2.875

local PROTOTYPE_FOLDER = "CharacterPrototypes"
local HEAD_MESH = "HeadMesh"
local ARM_RIGHT = "ArmRight"
-- 오른팔의 "내린" 자세. 모델 피벗 기준 상대 CFrame 을 파트 어트리뷰트에 둔다.
-- setHandRaised 가 여기서 출발해 어깨를 축으로 돌린다.
local REST_ATTRIBUTE = "RestOffset"
-- 손을 들 때 팔이 어깨를 축으로 앞·위로 도는 각도(라디안)와 바깥쪽으로 기울이는 각도. 메시는 관절이 없어 팔 전체가 돈다.
-- ★ 머리가 몸보다 큰 체형이라 팔을 곧게(π) 올리면 정면에서 머리에 완전히 가려 손든 것이 안 보인다.
--   앞·위(2.6)로 올리고 바깥(0.5)으로 기울여야 얼굴 옆으로 손이 나온다. (2026-09-27 Studio 에서 각도 6종 비교)
local RAISE_ANGLE = 2.6
local RAISE_TILT = 0.5

local DOWNLOAD_RETRIES = 3
local CLIENT_WAIT = 30

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
				part.CanQuery = false -- 시야 레이캐스트 대상이 아니다. 엄폐물은 Cover 태그가 정한다
				part.CanTouch = false
				part.Parent = model

				if def.name == "Head" then
					local sensor = Instance.new("Part")
					sensor.Name = "Head"
					sensor.Size = Vector3.new(0.5, 0.5, 0.5)
					sensor.CFrame = CFrame.new(def.offset)
					sensor.Transparency = 1
					sensor.Anchored = true
					sensor.CanCollide = false
					sensor.CanQuery = false
					sensor.CanTouch = false
					sensor.CastShadow = false
					sensor.Parent = model
				end
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
		error(`[CharacterBuilder] 원형 {key} 조립 실패: {failure}`)
	end
	return model
end

--[[
	서버 부팅 때 한 번. 교실 슬롯을 짓기 전에 불러야 한다(선생님이 여기서 나온다).
	실패하면 조용히 상자로 대체하지 않고 죽는다 — 메시가 없는 채로 게임이 뜨면
	그게 더 찾기 어려운 버그다.
]]
function CharacterBuilder.preload()
	assert(
		RunService:IsServer(),
		"preload 는 서버에서만 부른다. 클라이언트는 복제된 원형을 기다린다."
	)
	if ReplicatedStorage:FindFirstChild(PROTOTYPE_FOLDER) then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = PROTOTYPE_FOLDER

	local pending = 0
	local failure: string? = nil
	for key, variant in CharacterAssets.VARIANTS do
		pending += 1
		task.spawn(function()
			local ok, err = pcall(function()
				buildPrototype(key, variant).Parent = folder
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
		error(failure)
	end
	folder.Parent = ReplicatedStorage
end

local function prototypes(): Folder
	local folder = ReplicatedStorage:FindFirstChild(PROTOTYPE_FOLDER)
	if not folder and RunService:IsClient() then
		folder = ReplicatedStorage:WaitForChild(PROTOTYPE_FOLDER, CLIENT_WAIT)
	end
	assert(folder, "사람 원형이 없다. 서버가 CharacterBuilder.preload() 를 먼저 불러야 한다.")
	return folder
end

--[[
	@param name 모델 이름
	@param base 발 아래 바닥 중심의 CFrame. -Z 가 얼굴 방향
]]
function CharacterBuilder.build(name: string, base: CFrame, config: PersonConfig): Model
	local variant = CharacterAssets.VARIANTS[config.variant]
	assert(variant, `모르는 사람 변형: {config.variant}`)

	local prototype = prototypes():FindFirstChild(config.variant)
	assert(prototype, `원형 {config.variant} 가 복제되지 않았다`)
	local model = prototype:Clone()
	model.Name = name

	-- 생성 단위 → 스터드. 키를 기준으로 통째로 줄인다. 피벗(원점)은 안 움직인다.
	local target = if config.sitting then CharacterAssets.SIT_HEIGHT else CharacterAssets.STAND_HEIGHT
	local k = target * config.scale / variant.height
	model:ScaleTo(k)

	-- 앉으면 엉덩이가 의자 면(SIT_HIP)에 오도록 모델 바닥을 그만큼 내린다. 발은 의자 아래로 늘어진다.
	local bottom = if config.sitting then CharacterBuilder.SIT_HIP * config.scale - variant.hip * k else 0
	model:PivotTo(base * CFrame.new(0, bottom, 0))

	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CanCollide = config.collide and part.Name ~= "Head"
			part.CastShadow = config.shadow and part.Name ~= "Head"
		end
	end

	local arm = model:FindFirstChild(ARM_RIGHT)
	arm:SetAttribute(REST_ATTRIBUTE, model:GetPivot():ToObjectSpace(arm.CFrame))

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

	-- 파트 회전은 Y 축 회전뿐이라 파트의 위쪽 = 세계의 위쪽이다. 어깨 = 윗면 중심.
	local shoulder = restWorld.Position + Vector3.new(0, arm.Size.Y / 2, 0)
	-- 모델의 X 축(어깨선)을 축으로 돈다. 파트 자체의 축은 구운 회전 때문에 어깨선이 아니다.
	local hinge = CFrame.new(shoulder)
		* pivot.Rotation
		* CFrame.Angles(RAISE_ANGLE, 0, RAISE_TILT)
		* pivot.Rotation:Inverse()
	arm.CFrame = hinge * (CFrame.new(-shoulder) * restWorld)
end

--[[
	좌석 번호로 정해지는 학생 외양. 같은 자리는 언제 봐도 같은 아이다.
	체구는 학년이 정한다(GradeTheme.bodyScale). 자리마다 ±2.5% 만 흔들어 줄이 자로 잰 듯 보이지 않게 한다.
]]
function CharacterBuilder.studentConfig(seatIndex: number, grade: number): PersonConfig
	local rng = Random.new(seatIndex * 7919)
	local list = CharacterAssets.STUDENTS
	return {
		variant = list[(seatIndex - 1) % #list + 1],
		scale = GradeTheme.get(grade).bodyScale + rng:NextNumber(-0.025, 0.025),
		sitting = true,
		collide = false,
		shadow = false, -- 216개 그림자는 모바일에서 그대로 프레임이 된다
	}
end

-- 슬롯 번호로 남·여 선생님을 번갈아 세운다.
function CharacterBuilder.teacherConfig(seed: number?): PersonConfig
	local list = CharacterAssets.TEACHERS
	return {
		variant = list[((seed or 1) - 1) % #list + 1],
		scale = 1,
		sitting = false,
		collide = true,
		shadow = true,
	}
end

return CharacterBuilder
