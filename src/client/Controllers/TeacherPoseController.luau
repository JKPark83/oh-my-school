--!nonstrict
--[[
	선생님 몸의 클라이언트 연출을 통째로 소유한다. 판서와 어깨 들썩임 둘 다 여기 있다.

	★ 왜 클라이언트인가.
	  서버는 상태만 보내고 연출은 클라 몫이라는 이 프로젝트의 규칙 그대로다.
	  게다가 판서를 하려면 선생님이 칠판 쪽으로 한 걸음 나가야 하는데(아래 참고),
	  서버 모델을 움직이면 DetectionService 의 MAX_SIGHT(교탁 z = -15 기준 30스터드)와
	  소음 반경이 통째로 밀린다. 튜닝된 난이도를 건드리지 않으면서 그림만 고치는
	  방법은 클라이언트에서만 움직이는 것뿐이다. 서버 판정은 서버 사본을 읽으므로
	  여기서 무엇을 하든 감지에는 영향이 없다.

	★ 왜 어깨 들썩임까지 가져왔는가.
	  원래 SignalController 에 있었다. 그런데 판서 루프가 매 프레임 팔·몸통 CFrame 을
	  쓰기 시작하면 트윈과 주인이 둘이 되어 팔만 부들부들 떤다. CFrame 을 쓰는 주인은
	  하나여야 한다. 그래서 들썩임을 이 루프 안의 오프셋 하나로 흡수했다 —
	  덕분에 예고 순간에 "팔이 칠판에서 떨어지는 것"과 "어깨가 들썩이는 것"이
	  동시에 일어난다. 신호가 하나 더 늘었지 늦어지지 않았다.

	★ 판서가 멈추는 것 자체가 예고다.
	  분필 소리(SignalController)와 같은 프레임에 팔이 내려온다. 소리를 끈 플레이어에게는
	  이쪽이 본 신호가 된다.

	팔에 관절이 없다(CharacterBuilder 는 앵커된 파트 조립체다). 그래서 팔은
	"어깨에서 목표점 방향으로 뻗은 길이 가변 블록"으로 다룬다. 뭉툭한 인형이라
	길이가 조금 늘었다 줄었다 하는 것은 플레이 거리에서 팔꿈치로 읽힌다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)

local WAIT_TIMEOUT = 10

-- ── 자세 ──────────────────────────────────────────────────────────
-- 선생님은 칠판에서 3.1스터드 떨어져 서 있고 팔은 2스터드다. 그대로면 허공에 쓴다.
-- 판서 중에만 한 걸음 나갔다가, 판서가 끝나면 정확히 제자리로 돌아온다.
local STEP_FORWARD = 1.6
-- 칠판을 따라 좌우로 옮겨 다니는 한계. 판서 폭(글자 폭)보다 넉넉하면 된다.
local SHUFFLE_LIMIT = 4.5
-- 오른손잡이라 손이 몸통보다 오른쪽에 있다. 몸은 글자보다 이만큼 왼쪽에 선다.
local HAND_LEAD = 1.2
-- 팔 길이 허용 범위. 아래를 벗어나면 분필 끝이 칠판에 안 닿거나 팔이 고무가 된다.
local ARM_MIN, ARM_MAX = 1.15, 2.75

local CHALK_LEN = 0.6
local ERASER_LEN = 0.5
local BOARD_GAP = 0.06 -- 칠판 면에서 살짝 띄운다. 0 이면 z-fighting 이 난다

--[[
	SurfaceGui 의 "오른쪽"이 칠판 파트의 어느 축인가.
	Blackboard 의 글자는 Back(+Z) 면에 있고, 그 면을 보는 사람의 오른쪽은 파트 +X 다.
	분필이 글자와 반대로 쓸리면 이 값만 -1 로 뒤집으면 된다.
]]
local FACE_RIGHT = 1

-- 글자 하나가 차지하는 가로폭 / 줄 높이. 한글·숫자가 섞여 있어 정확할 수 없다.
-- 분필 끝이 글자 근처면 되는 것이지 글자 위에 정확히 얹힐 필요는 없다.
local CHAR_ADVANCE = 0.72

-- ── 타이밍 ────────────────────────────────────────────────────────
-- 판서 자세로 들어가는 시간. 나올 때는 예고 신호라서 훨씬 빠르다.
local BLEND_IN = 0.30
local BLEND_OUT = 0.12

--[[
	TEACHING 패킷을 받고 실제로 팔을 잡기까지의 유예.

	RemoteEvent 와 PivotTo 의 복제는 순서가 보장되지 않는다. 패킷이 먼저 오면
	선생님은 아직 RETURNING 마지막 몇 도를 돌고 있는데, 그 프레임에 우리가
	"칠판을 보는 자세"로 파트를 덮어쓰면 몸이 한 프레임 순간이동한다.
]]
local ENGAGE_DELAY = 0.12

local GRAPHEME_TIME = 0.16 -- 글자 하나 쓰는 데 걸리는 시간
local HOLD_TIME = 2.0 -- 다 쓰고 나서 그대로 두는 시간
local ERASE_TIME = 1.1 -- 지우개로 쓸어내는 시간

local TWITCH_HEIGHT = 0.4 -- 어깨가 들썩이는 높이(스터드)
local TWITCH_TIME = 0.2 -- 올라갔다 내려오는 왕복 전체

local TeacherPoseController = {}

-- ── 런타임 상태 ───────────────────────────────────────────────────
local ready = false
local basePivot: CFrame -- 회전 0(칠판을 보는) 자세의 선생님 피벗
local bodyParts: { { part: BasePart, offset: CFrame } } = {}
local arm: BasePart
local armOffset: CFrame
local armRestSize: Vector3
local board: BasePart
local label: TextLabel
local chalk: BasePart
local eraser: BasePart
local dust: ParticleEmitter

local lineLengths: { number } = {}
local lineCount = 0
local lineHeight = 0
local widestHalf = 0
local totalGraphemes = 0

local state = "TEACHING"
local engageAt = 0
local blend = 0
local posed = false -- 파트를 한 번이라도 우리가 건드렸는가(제자리 복귀 판단)
local twitchStart: number? = nil

local phase = "WRITE" -- WRITE → HOLD → ERASE → WRITE
local cursor = 0 -- 지금까지 쓴 글자 수(실수)
local phaseT = 0

--[[
	칠판에 적힌 글의 레이아웃을 라벨에서 직접 읽는다.

	★ 글의 주인은 여전히 Template 이다. 여기서 문자열을 다시 적지 않는 이유는
	  두 곳에 적힌 순간 둘이 어긋나기 때문이다. 우리는 "무엇이 적혀 있는지"를
	  읽어서 "어디에 쓰는 시늉을 할지"만 계산한다.
]]
local function measureText()
	lineLengths = {}
	totalGraphemes = 0
	widestHalf = 0

	for line in (label.Text .. "\n"):gmatch("(.-)\n") do
		local len = utf8.len(line) or #line
		table.insert(lineLengths, len)
	end

	lineCount = #lineLengths
	lineHeight = label.TextSize / 40 -- BuildKit 의 SurfaceGui.PixelsPerStud

	for i, len in lineLengths do
		widestHalf = math.max(widestHalf, len * lineHeight * CHAR_ADVANCE / 2)
		-- 줄바꿈도 grapheme 하나다. 마지막 줄 뒤에는 없다.
		totalGraphemes += len + (if i < lineCount then 1 else 0)
	end
end

-- 지금까지 쓴 글자 수 → (몇 번째 줄, 그 줄에서 얼마나 갔는가 0~1)
local function cursorToLine(g: number): (number, number)
	local acc = 0
	for i, len in lineLengths do
		if len > 0 and g <= acc + len then
			return i, (g - acc) / len
		end
		acc += len + 1
	end
	return lineCount, 1
end

-- 칠판 면 위의 한 점. u 는 글자 진행 방향, v 는 위쪽. 둘 다 칠판 중심 기준 스터드.
local function boardPoint(u: number, v: number): Vector3
	return (board.CFrame * CFrame.new(u * FACE_RIGHT, v, board.Size.Z / 2 + BOARD_GAP)).Position
end

-- 지금 분필(또는 지우개)이 있어야 할 칠판 위의 점
local function penTarget(): Vector3
	if phase == "ERASE" then
		-- 위 한 줄, 아래 한 줄. 왕복 두 번으로 판을 훑는다.
		local pass = phaseT / ERASE_TIME * 2
		local seg = math.min(math.floor(pass), 1)
		local t = pass - seg
		local sign = if seg == 0 then 1 else -1
		return boardPoint(widestHalf * sign * (1 - 2 * t), lineHeight * sign)
	end

	local line, frac = cursorToLine(cursor)
	local v = ((lineCount - 1) / 2 - (line - 1)) * lineHeight
	local halfWidth = lineLengths[line] * lineHeight * CHAR_ADVANCE / 2
	return boardPoint((-1 + 2 * frac) * halfWidth, v)
end

local function advancePhase(dt: number)
	if phase == "WRITE" then
		cursor += dt / GRAPHEME_TIME
		if cursor >= totalGraphemes then
			cursor = totalGraphemes
			phase, phaseT = "HOLD", 0
		end
	elseif phase == "HOLD" then
		phaseT += dt
		if phaseT >= HOLD_TIME then
			phase, phaseT = "ERASE", 0
		end
	else
		phaseT += dt
		if phaseT >= ERASE_TIME then
			phase, phaseT, cursor = "WRITE", 0, 0
		end
	end

	if phase == "WRITE" then
		label.MaxVisibleGraphemes = math.floor(cursor)
		label.TextTransparency = 0
	elseif phase == "HOLD" then
		label.MaxVisibleGraphemes = -1
		label.TextTransparency = 0
	else
		label.MaxVisibleGraphemes = -1
		label.TextTransparency = phaseT / ERASE_TIME
	end
end

-- 우리가 건드린 것을 전부 원래 자리로 돌려놓고 손을 뗀다.
local function release()
	for _, entry in bodyParts do
		entry.part.CFrame = basePivot * entry.offset
	end
	arm.Size = armRestSize
	arm.CFrame = basePivot * armOffset

	chalk.Transparency = 1
	eraser.Transparency = 1
	dust.Enabled = false
	posed = false
end

local function step(dt: number)
	if not ready then
		return
	end

	local writing = state == "TEACHING" and os.clock() >= engageAt
	local target = if writing then 1 else 0
	if blend < target then
		blend = math.min(1, blend + dt / BLEND_IN)
	elseif blend > target then
		blend = math.max(0, blend - dt / BLEND_OUT)
	end

	local twitchY = 0
	local start = twitchStart
	if start then
		local t = os.clock() - start
		if t >= TWITCH_TIME then
			twitchStart = nil
		else
			twitchY = math.sin(t / TWITCH_TIME * math.pi) * TWITCH_HEIGHT
		end
	end

	if blend <= 0 and twitchStart == nil then
		if posed then
			release()
		end
		return
	end
	posed = true

	-- 자세가 거의 다 잡히기 전에는 글자를 진행시키지 않는다.
	-- 팔이 아직 칠판에 안 닿았는데 글자만 늘어나면 허공에 쓴 것이 된다.
	if writing and blend > 0.5 then
		advancePhase(dt)
	end

	local pen = penTarget()

	-- 몸. 글자 위치를 따라 칠판을 좌우로 옮겨 다니고, 판서 중에만 한 걸음 앞으로.
	local localPen = basePivot:PointToObjectSpace(pen)
	local shuffle = math.clamp(localPen.X - HAND_LEAD, -SHUFFLE_LIMIT, SHUFFLE_LIMIT)
	local body = basePivot:VectorToWorldSpace(Vector3.new(shuffle, 0, -STEP_FORWARD)) * blend
		+ Vector3.new(0, twitchY, 0)

	for _, entry in bodyParts do
		entry.part.CFrame = basePivot * entry.offset + body
	end

	-- 팔. 어깨는 고정하고 목표점 방향으로 길이를 늘여 뻗는다.
	local shoulder = (basePivot * armOffset * CFrame.new(0, armRestSize.Y / 2, 0)).Position + body
	local delta = pen - shoulder
	local dist = delta.Magnitude
	local dir = if dist > 0.01 then delta / dist else Vector3.new(0, 0, -1)

	local restRot = (basePivot * armOffset).Rotation
	local rot = restRot
	-- lookAt 은 방향이 수직에 가까우면 축이 모호해진다. 그럴 일은 없지만 막아둔다.
	if math.abs(dir.Y) < 0.99 then
		local writeRot = CFrame.lookAt(Vector3.zero, dir).Rotation * CFrame.Angles(math.pi / 2, 0, 0)
		rot = restRot:Lerp(writeRot, blend)
	end

	local armLen = math.clamp(dist - CHALK_LEN, ARM_MIN, ARM_MAX)
	local length = armRestSize.Y + (armLen - armRestSize.Y) * blend

	arm.Size = Vector3.new(armRestSize.X, length, armRestSize.Z)
	arm.CFrame = CFrame.new(shoulder) * rot * CFrame.new(0, -length / 2, 0)

	-- 손에 쥔 것. 팔의 끝(로컬 -Y 방향)에 붙는다.
	local axis = -rot.UpVector
	local erasing = phase == "ERASE"
	local propLen = if erasing then ERASER_LEN else CHALK_LEN
	local propCF = CFrame.new(shoulder + axis * (length + propLen / 2)) * rot

	chalk.CFrame = propCF
	eraser.CFrame = propCF
	chalk.Transparency = if erasing then 1 else 1 - blend
	eraser.Transparency = if erasing then 1 - blend else 1

	-- 분필가루는 실제로 긋고 있을 때만. 다 쓰고 멈춘 손에서 가루가 날리면 안 된다.
	dust.Enabled = blend > 0.5 and writing and phase ~= "HOLD"
end

--[[
	init.client 의 상태 핸들러가 version 필터를 통과시킨 패킷만 넘겨준다.
	SignalController 보다 "먼저" 불려야 한다 — 배선 순서는 init.client 주석 참고.
]]
function TeacherPoseController.onTeacherState(newState: string, _duration: number)
	state = newState

	if newState == "TEACHING" then
		engageAt = os.clock() + ENGAGE_DELAY
		return
	end

	-- WARNING 과 FAKE_TURN 은 플레이어에게 똑같이 보여야 한다.
	-- 낚시인지 아닌지 구분되면 낚시가 아니다.
	if newState == "WARNING" or newState == "FAKE_TURN" then
		twitchStart = os.clock()
	end
end

local function makeProp(parent: Instance, name: string, size: Vector3, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic -- Neon 금지. 실내가 하얗게 뜨는 원인이 된다
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

function TeacherPoseController.Start(room: Model)
	local teacher = room:WaitForChild(RoomKeys.TEACHER, WAIT_TIMEOUT)
	local furniture = room:WaitForChild("Furniture", WAIT_TIMEOUT)
	local blackboard = furniture and furniture:WaitForChild("Blackboard", WAIT_TIMEOUT)
	local gui = blackboard and blackboard:FindFirstChildOfClass("SurfaceGui")
	local text = gui and gui:FindFirstChildOfClass("TextLabel")
	local armPart = teacher and teacher:WaitForChild("ArmRight", WAIT_TIMEOUT)

	--[[
		하나라도 없으면 조용히 포기한다. 판서는 연출이다 —
		연출이 없다고 게임이 멈추면 그게 더 큰 버그다.
	]]
	if not (teacher and blackboard and text and armPart) then
		warn("[TeacherPose] 판서에 필요한 인스턴스를 못 찾았다. 판서 연출을 끈다.")
		return
	end

	board = blackboard
	label = text
	arm = armPart

	--[[
		★ 기준 자세를 "지금 파트가 있는 자리"에서 스냅샷 뜨지 않는다.
		  이 컨트롤러는 교실 입장 전환 중에 붙는데, 그 순간 선생님이 몸을 돌리는
		  중일 수 있다. 그 자세를 기준으로 잡으면 판서 내내 몸이 비뚤어져 있다.

		  대신 (1) 각 파트의 피벗 기준 상대 위치를 뜨고 — 모델이 통짜로 도니까
		  이 값은 회전과 무관하게 항상 같다 — (2) 회전 0 인 피벗을 따로 만든다.
		  PivotTo 는 피벗을 축으로 도므로 피벗의 "위치"는 회전 중에도 안 변한다.
		  거기에 교실의 회전을 곱하면 그것이 칠판을 보는 자세다.
	]]
	local pivot = teacher:GetPivot()
	basePivot = CFrame.new(pivot.Position) * room:GetPivot().Rotation

	bodyParts = {}
	for _, child in teacher:GetChildren() do
		if child:IsA("BasePart") and child ~= arm then
			table.insert(bodyParts, { part = child, offset = pivot:ToObjectSpace(child.CFrame) })
		end
	end

	armOffset = pivot:ToObjectSpace(arm.CFrame)
	armRestSize = arm.Size

	chalk = makeProp(teacher, "Chalk", Vector3.new(0.2, CHALK_LEN, 0.2), Color3.fromRGB(244, 244, 238))
	eraser = makeProp(teacher, "Eraser", Vector3.new(1.1, ERASER_LEN, 0.45), Color3.fromRGB(72, 62, 58))

	dust = Instance.new("ParticleEmitter")
	dust.Name = "ChalkDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(238, 238, 232))
	dust.LightEmission = 0 -- 발광하면 안 된다. 실내 과다노출을 막으려고 조명을 낮춘 참이다
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Rate = 14
	dust.Speed = NumberRange.new(0.2, 0.5)
	dust.SpreadAngle = Vector2.new(25, 25)
	dust.Acceleration = Vector3.new(0, -4, 0)
	dust.Enabled = false
	dust.Parent = chalk

	measureText()
	label.MaxVisibleGraphemes = 0

	--[[
		★ 첫 상태는 패킷이 아니라 지금 어디를 보고 있는지로 정한다.
		  이 컨트롤러는 교실 전환 중에 붙는데, 그때 서버는 이미 TEACHING 을
		  한 번 보내고 지나간 뒤일 수 있다(SignalController 가 첫 분필 소리를
		  직접 켜주는 것과 같은 문제다). 그래서 TEACHING 을 기본값으로 두어야 하는데,
		  하필 뒤돌아본 순간에 붙으면 뒤돌아 선 선생님이 등 뒤 칠판으로
		  팔을 뻗는 그림이 나온다. 방향은 패킷과 달리 놓칠 수가 없다.
	]]
	state = if pivot.LookVector:Dot(basePivot.LookVector) > 0.7 then "TEACHING" else "WATCHING"
	engageAt = os.clock() + ENGAGE_DELAY

	ready = true
	RunService.RenderStepped:Connect(step)
end

return TeacherPoseController
