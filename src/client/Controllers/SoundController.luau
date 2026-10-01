--!strict
--[[
	효과음 재생. 기획서 §9.6.
	  play(key, pitch?)   풀에서 꺼내 재생. pitch 는 SoundConfig 의 speed 에 곱한다(콤보 상승음).
	  setMuted / setEnabled / isMuted   SoundGroup "Game" 의 Volume 하나로 끈다.
	  setMusicEnabled   배경음(SoundGroup "Music") 켜기·끄기. 끄면 멈춘 자리에서 다시 이어 튼다.
	복도 웅성거림은 Start() 에서 항상 작게(0.08) 깔아 둔다.
	배경음은 SoundConfig.MUSIC.tracks 를 차례로 돌린다. duck 효과음(졸업·팡파르)이 울리는 동안 줄인다.

	★ 키 하나에 Sound 하나(풀). 같은 키가 겹쳐 울려야 하는 경우(콤보 연타)는 짧은 소리라
	  다시 Play() 로 처음부터 재생해도 티가 안 난다. 인스턴스를 매번 만들지 않는다.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local HALLWAY_KEY = "hallway"

local SoundController = {}

local pool: { [string]: Sound } = {}
local muted = false

local DUCK_TWEEN = TweenInfo.new(0.4)

local music: Sound? = nil
local musicEnabled = false -- 프로필이 오기 전에는 끈 것으로 본다
local trackIndex = 0
local ducking = 0 -- 지금 울리는 duck 효과음 수. 0 이 되면 배경음을 되돌린다

local function playNextTrack()
	local sound = music
	if not sound or not musicEnabled then
		return
	end
	local tracks = SoundConfig.MUSIC.tracks
	trackIndex = trackIndex % #tracks + 1
	sound.SoundId = tracks[trackIndex]
	sound.TimePosition = 0
	sound:Play()
end

local function duck(sound: Sound)
	ducking += 1
	TweenService:Create(SoundConfig.music(), DUCK_TWEEN, { Volume = SoundConfig.MUSIC.duck }):Play()
	sound.Ended:Once(function()
		ducking -= 1
		if ducking == 0 then
			TweenService:Create(SoundConfig.music(), DUCK_TWEEN, { Volume = 1 }):Play()
		end
	end)
end

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
	-- 이미 울리는 중에 다시 틀면 Ended 가 한 번만 와서 수가 어긋난다. 처음 틀 때만 센다
	if def.duck and not sound.IsPlaying then
		duck(sound)
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

--- 설정 패널의 "배경음" 토글
function SoundController.setMusicEnabled(on: boolean)
	musicEnabled = on
	local sound = music
	if not sound then
		return
	end
	if not on then
		sound:Pause()
	elseif sound.TimePosition > 0 then
		sound:Resume()
	else
		playNextTrack()
	end
end

function SoundController.Start()
	SoundConfig.master()
	SoundController.play(HALLWAY_KEY)

	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Volume = SoundConfig.MUSIC.volume
	sound.Looped = false
	sound.SoundGroup = SoundConfig.music()
	sound.Parent = SoundService
	-- Ended 안에서 바로 Play() 하면 엔진이 끝난 상태로 되돌려 무시한다(2026-10-01 Studio 실측). 한 프레임 미룬다
	sound.Ended:Connect(function()
		task.defer(playNextTrack)
	end)
	-- 여기서 틀지 않는다. 첫 ProfileSync 의 setMusicEnabled 가 튼다(끈 아이에게 잠깐이라도 울리지 않게)
	music = sound
end

return SoundController
