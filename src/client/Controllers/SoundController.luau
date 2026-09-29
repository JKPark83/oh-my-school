--!strict
--[[
	효과음 재생. 기획서 §9.6.
	  play(key, pitch?)   풀에서 꺼내 재생. pitch 는 SoundConfig 의 speed 에 곱한다(콤보 상승음).
	  setMuted / setEnabled / isMuted   SoundGroup "Game" 의 Volume 하나로 끈다.
	복도 웅성거림은 Start() 에서 항상 작게(0.08) 깔아 둔다.

	★ 키 하나에 Sound 하나(풀). 같은 키가 겹쳐 울려야 하는 경우(콤보 연타)는 짧은 소리라
	  다시 Play() 로 처음부터 재생해도 티가 안 난다. 인스턴스를 매번 만들지 않는다.
]]

local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local HALLWAY_KEY = "hallway"

local SoundController = {}

local pool: { [string]: Sound } = {}
local muted = false

local function get(key: string): Sound
	local existing = pool[key]
	if existing then
		return existing
	end
	local sound = SoundConfig.create(key)
	sound.Parent = SoundService
	pool[key] = sound
	return sound
end

--- 효과음 재생. pitch 는 정의된 speed 에 곱한다(nil 이면 1)
function SoundController.play(key: string, pitch: number?)
	local def = SoundConfig.DEFS[key]
	if not def then
		warn(`[SoundController] 정의되지 않은 사운드: {key}`)
		return
	end
	local sound = get(key)
	sound.PlaybackSpeed = def.speed * (pitch or 1)
	if def.looped then
		if not sound.IsPlaying then
			sound:Play()
		end
		return
	end
	sound.TimePosition = 0
	sound:Play()
end

function SoundController.setMuted(value: boolean)
	muted = value
	SoundConfig.master().Volume = if value then 0 else 1
end

--- 설정 패널의 "효과음" 토글. sfx=false 가 곧 음소거다
function SoundController.setEnabled(sfx: boolean)
	SoundController.setMuted(not sfx)
end

function SoundController.isMuted(): boolean
	return muted
end

function SoundController.Start()
	SoundConfig.master()
	SoundController.play(HALLWAY_KEY)
end

return SoundController
