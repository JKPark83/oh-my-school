--!strict
--[[
	사운드 9종. 이 게임에서 소리는 장식이 아니다.

	★ 1번(분필 판서)이 멈추는 것이 예고 신호의 본체다.
	  나머지 여덟 개를 다 빼도 게임은 돌아가지만, 1번을 빼면 규칙이 무너진다.
	  그래서 1번만 3D 사운드로 선생님 머리에 붙는다 — 소리의 "방향"으로
	  선생님이 어디 있는지 알 수 있어야 한다.

	★ 지금 들어있는 id 는 전부 로블록스 엔진에 기본 내장된 rbxasset 경로다.
	  업로드 없이 당장 소리가 나게 하려고 넣은 임시값이고, 진짜 소리가 아니다.
	  pitch(PlaybackSpeed)와 volume 으로 흉내만 낸 것이라, 실제 배포 전에는
	  녹음하거나 사서 rbxassetid:// 로 갈아끼워야 한다.
	  갈아끼우는 곳은 이 표 한 곳뿐이다 — 재생 로직은 아무것도 안 바뀐다.

	★ 무음 정의(id = SILENT)가 있다. 흉내조차 안 되는 소리는 넣지 않는다.
	  수업 목소리와 복도 웅성거림을 uuhhh.mp3 로 흉내 냈더니, 피치를 낮춰
	  무한 루프한 사람 목소리는 수업이 아니라 신음소리로 들렸다. 배경음은
	  한 번 틀리면 플레이 내내 틀린 채로 깔린다 — 잘못된 배경음은 무음보다 나쁘다.
	  진짜 음원이 생기면 id 만 채우면 되고, 재생 코드는 이미 다 붙어 있다.
]]

local SoundService = game:GetService("SoundService")

export type SoundDef = {
	id: string,
	volume: number,
	speed: number, -- PlaybackSpeed. 1 이 원본
	looped: boolean,
	rollOff: number?, -- 3D 사운드일 때만. nil 이면 2D 로 재생한다
}

local SoundConfig = {}

-- 아직 쓸 만한 음원이 없다는 뜻. Sound 인스턴스는 그대로 만들어지고 재생만 안 된다.
local SILENT = ""

local DEFS: { [string]: SoundDef } = {
	-- 1. 분필 판서 (루프, 3D). 이게 멈추는 것이 예고 신호다
	--
	-- 플라스틱 발소리를 빠르게 돌려 "탁탁탁" 두드리는 소리로 쓴다. 분필은
	-- 낮고 둔한 소리가 아니라 가볍고 높은 소리다 — 피치를 낮추면 발소리로 되돌아간다.
	-- 여덟 개 중 유일하게 빼면 안 되는 소리라, 어설퍼도 무음으로 두지 않는다.
	chalk = {
		id = "rbxasset://sounds/action_footsteps_plastic.mp3",
		volume = 0.45,
		speed = 1.7,
		looped = true,
		rollOff = 55,
	},

	-- 2. 선생님 수업 목소리 (루프, 3D). 안전 구간의 배경. 분필보다 작아야 한다
	--
	-- ⚠️ 무음. uuhhh.mp3 를 피치 0.65 로 루프하니 수업이 아니라 신음소리가 됐다.
	--    사람 목소리는 흉내가 안 된다 — 웅얼거리는 수업을 직접 녹음해야 한다.
	lecture = { id = SILENT, volume = 0.18, speed = 0.65, looped = true, rollOff = 45 },

	-- 3. 마룻바닥 삐걱. 서버가 판정하고 소유자에게만 보낸다
	creak = { id = "rbxasset://sounds/snap.mp3", volume = 0.75, speed = 0.55, looped = false },

	-- 4. 실내화 발소리. 모드별로 볼륨과 간격이 다르다(간격은 SoundController 가 정한다)
	stepSneak = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.12, speed = 0.75, looped = false },
	stepWalk = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.3, speed = 1, looped = false },
	stepRun = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.55, speed = 1.35, looped = false },

	-- 5. 의자 끄는 소리. 착석 성공
	chair = { id = "rbxasset://sounds/swoosh.wav", volume = 0.6, speed = 0.5, looped = false },

	-- 6. "야!" 호통. 적발
	--
	-- 여기서만 uuhhh.mp3 를 남겨둔다. 한 번 짧게 터지는 사람 소리는
	-- 호통으로 읽힌다 — 루프가 아니라서 신음소리가 되지 않는다.
	scold = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.9, speed = 1.15, looped = false },

	-- 7. 복도 웅성거림 (루프, 2D). 학교라는 공간감
	--
	-- ⚠️ 무음. 2번과 같은 이유다. 게다가 이건 2D 라 어디에 있든 계속 들려서
	--    틀렸을 때 가장 거슬린다. 여러 사람의 웅성거림은 한 사람 목소리로 못 만든다.
	hallway = { id = SILENT, volume = 0.08, speed = 0.4, looped = true },

	-- 8. 수업 종. 학년 수료
	bell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 0.7, looped = false },

	--[[
		9. 교실 긴장감 배경음 (루프, 2D). 교실에 있는 동안만 돈다.

		★ 여기만 위 규칙("흉내가 안 되면 무음")의 예외다. 2·7번은 사람 목소리라
		  흉내가 아예 안 됐지만, 긴장감은 낮게 깔리는 한 음이면 절반은 된다.
		  베이스 음 하나를 피치 0.35 로 늘려 루프한다.

		★ 반드시 분필보다 작아야 한다. 분필(0.45)이 예고 신호의 본체이고 이건
		  배경이다. 배경이 신호를 덮으면 게임이 아니라 운이 된다. 다행히 주파수도
		  갈라져 있다 — 분필은 피치 1.7 로 높고 이건 0.35 로 낮다.

		⚠️ 이건 진짜 음악이 아니라 자리를 잡아둔 것이다. 한 음짜리 루프라
		   이어지는 지점에서 맥이 끊길 수 있다. 스튜디오에서 한 번 들어보고,
		   거슬리면 여기 id 를 진짜 음원(rbxassetid://)으로 갈아끼우면 된다.
		   재생·정지 배선은 이미 다 되어 있어서 이 한 줄 말고는 고칠 데가 없다.
	]]
	tension = { id = "rbxasset://sounds/bass.mp3", volume = 0.16, speed = 0.35, looped = true },
}

SoundConfig.DEFS = DEFS

-- 이동 모드 → 발소리 키. MovementConfig 의 모드 이름과 1:1이다.
SoundConfig.STEP_BY_MODE = {
	SNEAK = "stepSneak",
	WALK = "stepWalk",
	RUN = "stepRun",
}

-- 발소리 간격(초). 빠를수록 촘촘하다. 살금살금이 조용한 것은 볼륨만이 아니라 리듬이다.
SoundConfig.STEP_INTERVAL = {
	SNEAK = 0.62,
	WALK = 0.42,
	RUN = 0.28,
}

-- 이 속도 아래면 발소리를 내지 않는다. 감속 커브의 꼬리에서 계속 울리는 것을 막는다.
SoundConfig.STEP_MIN_SPEED = 2

--[[
	이 게임의 모든 소리가 묶이는 그룹. 음소거는 이 그룹의 Volume 하나만 만지면 끝난다.

	★ Sound 인스턴스를 찾아다니며 끄지 않는다. 소리는 여기저기서 만들어진다 —
	  발소리는 SoundService 아래, 분필은 선생님 머리에, 수업 목소리는 교탁 위에.
	  게다가 선생님은 교실에 들어간 뒤에야 생긴다. 만들어진 것을 순회하면
	  나중에 생기는 소리를 반드시 빠뜨린다. 그룹은 앞으로 만들어질 것까지 포함한다.

	★ create() 가 이 프로젝트에서 Sound 를 만드는 유일한 곳이라 여기서 묶으면 샐 곳이 없다.
	  처음 부를 때 만든다 — 모듈을 require 하는 것만으로 인스턴스가 생기면
	  서버가 이 파일을 require 하는 날 SoundGroup 이 서버에 생겨 복제된다.
]]
local master: SoundGroup? = nil

function SoundConfig.master(): SoundGroup
	local existing = master
	if existing then
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = "Game"
	group.Volume = 1
	group.Parent = SoundService
	master = group
	return group
end

--[[
	정의대로 Sound 인스턴스를 만든다. rollOff 가 있으면 3D(파트에 붙는 소리),
	없으면 2D(SoundService 아래)로 쓰라는 뜻이다 — 부모는 호출자가 정한다.

	id 가 SILENT 면 SoundId 가 빈 문자열인 Sound 가 나온다. Play() 를 불러도
	아무 일도 안 일어난다. 호출자가 무음인지 물어볼 필요가 없게 하려고 이렇게 했다 —
	나중에 진짜 음원을 넣을 때 재생 코드를 다시 찾아다니지 않아도 된다.
]]
function SoundConfig.create(key: string): Sound
	local def = DEFS[key]
	assert(def, `정의되지 않은 사운드: {key}`)

	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.PlaybackSpeed = def.speed
	sound.Looped = def.looped
	sound.SoundGroup = SoundConfig.master()

	if def.rollOff then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = def.rollOff
	end

	return sound
end

return SoundConfig
