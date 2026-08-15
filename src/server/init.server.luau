--!nonstrict
--[[
	서버 부트스트랩. 순서를 아는 유일한 곳이다.

	모듈 최상위에서는 아무것도 하지 않는다. require 는 값만 반환하고,
	실제 작업은 Start() 에서 한다. 그래야 순서는 여기 한 곳만 보면 파악된다.

	순서가 중요한 이유:
	  DataService  — 플레이어가 들어오기 전에 스토어가 있어야 한다
	  Classroom    — 슬롯 12개가 다 지어진 뒤에야 배정할 수 있다
	  Playground   — 첫 스폰 지점이다. Progress 가 RespawnLocation 으로 쓰므로 먼저 서야 한다
	  Progress     — 여기서 PlayerAdded 를 잡는다. 위 셋이 준비된 뒤여야 한다
	  Detection    — 매 프레임 세션 표를 읽는다. 마지막에 켠다
]]

local DataService = require(script.Services.DataService)
local ClassroomService = require(script.Services.ClassroomService)
local DetectionService = require(script.Services.DetectionService)
local PlaygroundService = require(script.Services.PlaygroundService)
local ProgressService = require(script.Services.ProgressService)

DataService.Start()

local slotCount = ClassroomService.Start()
PlaygroundService.Start()

ProgressService.Start()
DetectionService.Start()

print(`[Boot] 운동장 + 교실 슬롯 {slotCount}개 준비 완료`)
