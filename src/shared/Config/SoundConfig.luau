--!strict
--[[
	사운드 12종. 이 게임에서 소리는 장식이 아니다.

	★ 1번(분필 판서)이 멈추는 것이 예고 신호의 본체다.
	  나머지 열한 개를 다 빼도 게임은 돌아가지만, 1번을 빼면 규칙이 무너진다.
	  그래서 1번만 3D 사운드로 선생님 머리에 붙는다 — 소리의 "방향"으로
	  선생님이 어디 있는지 알 수 있어야 한다.

	★ id 는 두 종류다. rbxassetid:// 는 Creator Store 의 무료(IsPublicDomain) 음원이고
	  (2026-09-27 docs/음원-후보.md 에서 고름, 전부 ProSoundEffects 라이브러리),
	  rbxasset://sounds/* 는 로블록스 엔진 내장 음원을 pitch(PlaybackSpeed)와 volume 으로
	  흉내 낸 임시값이다. 내장 음원은 speed 가 보정값(1 이 아님)이고, 스토어 음원은 원본 그대로(1)다.
	  갈아끼우는 곳은 이 표 한 곳뿐이다 — 재생 로직은 아무것도 안 바뀐다.
	  ★ 스토어 음원은 업로드가 아니다. "업로드 없이 돌아간다"는 규칙은 그대로 지켜진다.

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
	-- ProSoundEffects "Chalkboard 11" (9.9초). 분필 쓰기 + 분필 집고 놓는 소리가 섞여 있다.
	-- ⚠️ 루프 안의 "집고 놓는" 짧은 정지가 예고 신호(멈춤)로 오해되면 이 게임은 운이 된다.
	--    플레이해서 억울한 죽음이 나오면 후보 "Chalkboard 6"(9113781420) / "7"(9113781416) 로 바꾸거나
	--    내장 action_footsteps_plastic.mp3 (speed 1.7) 로 되돌린다.
	-- 여덟 개 중 유일하게 빼면 안 되는 소리라, 어설퍼도 무음으로 두지 않는다.
	chalk = {
		id = "rbxassetid://9113781663",
		volume = 0.45,
		speed = 1,
		looped = true,
		rollOff = 55,
	},

	-- 2. 선생님 수업 목소리 (루프, 3D). 안전 구간의 배경. 분필보다 작아야 한다
	--
	-- ⚠️ 무음. uuhhh.mp3 를 피치 0.65 로 루프하니 수업이 아니라 신음소리가 됐다.
	--    사람 목소리는 흉내가 안 된다 — 웅얼거리는 수업을 직접 녹음해야 한다.
	lecture = { id = SILENT, volume = 0.18, speed = 0.65, looped = true, rollOff = 45 },

	-- 3. 마룻바닥 삐걱. 서버가 판정하고 소유자에게만 보낸다
	-- ProSoundEffects "Floor Creaks Wood Floorboard 11" (1.7초). 쿨다운 0.5초 안에 끝나야 하니 2초 아래.
	creak = { id = "rbxassetid://9125563505", volume = 0.75, speed = 1, looped = false },

	-- 4. 실내화 발소리. 모드별로 볼륨과 간격이 다르다(간격은 SoundController 가 정한다)
	stepSneak = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.12, speed = 0.75, looped = false },
	stepWalk = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.3, speed = 1, looped = false },
	stepRun = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.55, speed = 1.35, looped = false },

	-- 5. 의자 끄는 소리. 착석 성공
	-- ProSoundEffects "Chair Movement 5" (2.6초, 금속 다리 긁힘). 한국 교실 의자는 철제라 나무 의자 소리를 피했다.
	chair = { id = "rbxassetid://9113774550", volume = 0.6, speed = 1, looped = false },

	-- 6. "야!" 호통. 적발
	--
	-- 여기서만 uuhhh.mp3 를 남겨둔다. 한 번 짧게 터지는 사람 소리는
	-- 호통으로 읽힌다 — 루프가 아니라서 신음소리가 되지 않는다.
	scold = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.9, speed = 1.15, looped = false },

	-- 7. 복도 웅성거림 (루프, 2D). 학교라는 공간감
	--
	-- ProSoundEffects "Kids Walla 2" (53초, Loop). 실내 체육관의 아이들 여러 명 소리.
	-- 여러 사람이어야 한다는 조건은 맞췄고, 개별 단어는 0.08 볼륨이면 묻힌다.
	-- ⚠️ 이건 2D 라 어디에 있든 계속 들려서 틀렸을 때 가장 거슬린다. 거슬리면 SILENT 로 되돌린다.
	--    (예전에 uuhhh.mp3 한 사람 목소리를 늘려 썼다가 신음소리가 되어 비웠던 자리다.)
	hallway = { id = "rbxassetid://9112811182", volume = 0.08, speed = 1, looped = true },

	-- 8. 수업 종. 학년 수료
	bell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 0.7, looped = false },

	--[[
		9. 교실 긴장감 배경음 (루프, 2D). 교실에 있는 동안만 돈다.

		ProSoundEffects "Command Room Tone Deep Air Conditioning Hum 2" (35초). 공조기 저역 룸톤.
		멜로디도 리듬도 없다 — 이 게임의 긴장은 "조용한 교실" 자체다. 공포 게임 드론(Hollow Rumble 계열)은
		톤이 안 맞아 피했다. 20분 들어도 견딜 것이 조건이라 가장 심심한 것을 골랐다.
		(예전에는 내장 bass.mp3 한 음을 피치 0.35 로 늘려 자리를 잡아 두었다.)

		★ 반드시 분필보다 작아야 한다. 분필(0.45)이 예고 신호의 본체이고 이건
		  배경이다. 배경이 신호를 덮으면 게임이 아니라 운이 된다. 주파수도
		  갈라져 있다 — 분필은 고역, 이건 저역 웅웅거림이다.

		⚠️ 룸톤은 원본이 작아 0.16 으로는 안 들릴 수 있어 0.2 로 뒀다. 그래도 분필의 절반 아래다.
		   재생·정지 배선은 이미 다 되어 있어서 이 한 줄 말고는 고칠 데가 없다.
	]]
	tension = { id = "rbxassetid://9125446564", volume = 0.2, speed = 1, looped = true },

	--[[
		10. 착석 성공음. 5번(의자)과 같은 순간에 겹쳐 난다.

		★ 둘을 나눈 이유는 말하는 내용이 다르기 때문이다. 의자 끄는 소리는
		  "앉았다"는 사실이고, 이건 "해냈다"는 판정이다. 자리에 앉는 것과
		  그 자리가 정답이었다는 것은 같은 사건이 아니다 — 의자 소리만 나면
		  앉기는 앉았는데 통과한 건지 알 수 없다.

		★ 8번(종)과 같은 음원을 피치만 올려 쓴다. 낮은 종은 학년 수료,
		  높은 핑은 한 반 통과 — 같은 음색의 높낮이가 "큰 성공/작은 성공"으로
		  읽힌다. 음원을 하나 더 고르면 이 관계가 사라진다.
	]]
	success = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 1.45, looped = false },

	--[[
		11. 지각 종. 반마다 걸린 제한 시간이 끝났을 때 교실 안에서 한 번 울린다.

		★ 8번(종)을 그대로 쓰면 안 된다. 8번은 "학년을 끝냈다"는 축하고 이건
		  "퍼펙트를 놓쳤다"는 통보다. 한 소리가 정반대 두 가지를 뜻하는 순간,
		  소리로 상황을 읽는 이 게임의 규칙 자체가 깨진다.

		★ 그래서 같은 음원의 세 번째 자리에 놓는다. 피치 0.45 / 0.7 / 1.45 는
		  지각 · 수료 · 통과 순이고, 낮을수록 나쁜 소식이다. 음량도 가장 작다 —
		  놓쳤다는 사실은 알려야 하지만, 아직 통과할 수 있는 사람의 손을
		  멈추게 할 만큼 크면 안 된다.
	]]
	late = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.55, speed = 0.45, looped = false },

	--[[
		12. 숨 들이키는 소리. 고자질하는 학생이 나를 보고 손을 든 순간 한 번 난다.

		★ 이 소리가 없으면 유예 1.5초가 통째로 존재하지 않는 것과 같다.
		  손은 등 뒤나 옆에서 올라가고 카메라는 대개 그쪽을 안 보고 있다.
		  보이지 않는 경고는 경고가 아니라 지연된 처벌이다.

		★ 그래서 크기(0.5)가 발소리보다 크다. 놓치면 안 되는 유일한 정보라
		  다른 소리에 묻히면 안 된다. 대신 짧아서 오래 방해하지 않는다.

		★ 3번(삐걱)과 역할이 정확히 대칭이다. 삐걱은 "내가 소리를 냈다",
		  이건 "누가 나를 봤다" — 둘 다 아직 잡히지 않았고 둘 다 지금 움직이라는 뜻이다.
	]]
	whisper = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.5, speed = 1.6, looped = false },
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
