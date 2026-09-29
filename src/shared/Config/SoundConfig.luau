--!strict
--[[
	사운드 19종. 기획서 §9.6 표.

	★ id 는 두 종류다. rbxassetid:// 는 Creator Store 의 무료 음원이고,
	  rbxasset://sounds/* 는 로블록스 엔진 내장 음원을 pitch(PlaybackSpeed)와 volume 으로
	  흉내 낸 것이다. 갈아끼우는 곳은 이 표 한 곳뿐이다 — 재생 로직은 아무것도 안 바뀐다.

	★ 잠입 게임 시절 정의(chalk·lecture·creak·step*·scold·tension·late·whisper)는 지웠고,
	  tick/goldPop/pad/arrive/bell/hallway 는 그때 쓰던 id 를 속도·볼륨만 바꿔 재활용한다.

	★ 신규 음원은 로블록스 제휴 라이브러리(ProSoundEffects·APMOfficial) 것만 쓴다.
	  사용자가 올린 음원은 게임·방송 음원을 무단으로 올린 경우가 많아 권리를 믿을 수 없다.

	★ SoundController.play(key, pitch) 가 여기 speed 에 pitch 를 곱한다.
	  콤보 상승음처럼 매번 다른 높이가 필요한 소리는 speed 를 기준값으로 두고 호출 쪽에서 곱한다.
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
SoundConfig.SILENT = SILENT

local DEFS: { [string]: SoundDef } = {
	-- 수입 틱. 코인이 오를 때마다 아주 짧게. 옛 의자 음원을 빠르게
	tick = { id = "rbxassetid://9113774550", volume = 0.35, speed = 1.3, looped = false },
	-- 코인 팝(수동 수확·보너스). 옛 success 음원을 높게
	goldPop = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.6, looped = false },
	-- 패드 밟음. 옛 bell 음원
	pad = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, speed = 1.4, looped = false },
	-- 전학생 도착
	arrive = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 1.45, looped = false },
	-- 종(졸업식·수업 시작). 옛 bell 음원을 낮게
	bell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 0.7, looped = false },
	-- 꾸미기가 겹쳐 옆 칸으로 밀림·놓을 수 없는 칸(부정 소리 대신 작고 가벼운 톡). 짧은 핑을 빠르게(≤0.3초)
	nudge = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, speed = 1.8, looped = false },
	-- 엘리베이터 도착 「띵」(개선계획 §3.6 #7, ≤0.5초·볼륨 ≤0.5). 짧은 핑을 조금 높게
	elevator = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, speed = 1.2, looped = false },
	-- 복도 웅성거림 배경음(루프). 항상 아주 작게 깔린다
	hallway = { id = "rbxassetid://9112811182", volume = 0.08, speed = 1, looped = true },

	-- 이하 신규 11종
	-- 시설 완공·도장. PSE "Date Stamp Big Office Impact Good Squeak 2" 0.74초
	build = { id = "rbxassetid://9114026047", volume = 0.7, speed = 1, looped = false },
	-- 전교1등 등급. APM "Correct Answer 1"(상승하는 신스) 5.4초
	fanfare = { id = "rbxassetid://1839997916", volume = 0.7, speed = 1, looped = false },
	-- 전설 등급. APM "Clock Tower (sting)"(반짝이는 첼레스타) 5.4초
	legend = { id = "rbxassetid://9043507891", volume = 0.8, speed = 1, looped = false },
	-- 졸업식. APM "That Summer (sting)" 5.5초
	graduation = { id = "rbxassetid://9042730932", volume = 0.8, speed = 1, looped = false },
	-- 콤보. speed 는 기준값이고 호출 쪽 pitch 로 단계마다 올린다. PSE "Synth Sparkle Tone High Pitch Bell Tone Ding 3" 1.1초
	combo = { id = "rbxassetid://9126073064", volume = 0.5, speed = 1, looped = false },
	-- 선물 받음(선물판 40칸·미션 완료). APM "Correct Answer 2"(윤기 있는 신스) 4.6초
	reward = { id = "rbxassetid://1839997929", volume = 0.6, speed = 1, looped = false },
	-- 스티커 획득. 콤보마다 호출 쪽 pitch 로 5음계를 올린다. PSE "Mouth Drips Cheek Pluck Water Liquid 10"(입 팝) 0.5초
	sticker = { id = "rbxassetid://9117014265", volume = 0.55, speed = 1, looped = false },
	-- 스티커 찾기 표식. 3초마다 판에 붙어 거리로 줄어드는 잔잔한 반짝(개선계획 §3.2 #9, 볼륨 ≤0.2).
	-- PSE "Synth Sparkle Tone High Pitch Tone Burst Ding 15" 0.8초
	sparkle = { id = "rbxassetid://9126076118", volume = 0.15, speed = 1, looped = false, rollOff = 50 },
	-- Roblox 공식 swoosh(12222200). 내장 rbxasset://sounds/swoosh.wav 는 로드가 막혀 있다
	door_open = { id = "rbxassetid://12222200", volume = 0.5, speed = 0.8, looped = false },
	-- 학생이 자리에 앉음. PSE "Wood Chair Creak 3"(앉기·무게 이동) 0.6초
	sit = { id = "rbxassetid://9120806427", volume = 0.5, speed = 1, looped = false },
	-- 살 수 있게 됐다는 알림. PSE "Gas Pump Bell Cu Metallic Dinging Muted 4" 1.4초
	afford_ding = { id = "rbxassetid://9114557074", volume = 0.45, speed = 1, looped = false },
}

SoundConfig.DEFS = DEFS

--[[
	이 게임의 모든 소리가 묶이는 그룹. 음소거는 이 그룹의 Volume 하나만 만지면 끝난다.

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
	아무 일도 안 일어난다. 호출자가 무음인지 물어볼 필요가 없게 하려고 이렇게 했다.
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
