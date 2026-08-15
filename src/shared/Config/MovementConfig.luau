--!strict
--[[
	이동 3단계 수치. 이 표가 게임 디자인의 전부다.

	감속은 선형이 아니라 지수 감쇠다: v(t) = v0 * e^(-t / stopTime)
	따라서 stopTime 은 "완전히 멈추는 데 걸리는 시간"이 아니라 시상수다.
	실제로 게임에 의미가 있는 값은 아래 두 가지이고, 둘 다 stopTime 에서 유도된다.

	  미끄러지는 거리 = stopTime * (speed - STOP_CUTOFF)
	  멈출 때까지 시간 = stopTime * ln(speed / STOP_CUTOFF)

	  | 모드     | speed | stopTime | 미끄럼 | 정지까지 |
	  |----------|-------|----------|--------|----------|
	  | 살금살금 |     4 |     0.08 | 0.2 st |   0.11초 |
	  | 걷기     |    10 |     0.35 | 3.2 st |   0.81초 |
	  | 달리기   |    17 |     0.75 | 12  st |   2.13초 |

	★ 이 표를 읽는 법 — 1학년의 반응 예산은 다음과 같다.
	    warnTime(0.60~0.75) + turnTime 전반부(0.23) + GRACE(0.20) = 약 1.0~1.2초
	  여기에 사람의 반응 시간 0.25초를 빼면 실제로 쓸 수 있는 감속 시간은 0.75~0.95초다.

	    살금살금 0.11초 → 항상 여유 있게 멈춘다 (느림에 대한 보상)
	    걷기     0.81초 → 아슬아슬하다 (여기가 이 게임의 긴장)
	    달리기   2.13초 → 못 멈춘다. 예고를 보고 브레이크를 밟으면 이미 늦었다

	  달리기는 "예고를 보고 멈추는" 수단이 아니라 "미리 멈출 자신이 있을 때
	  쓰는" 수단이다. 이 한 줄에서 게임의 모든 판단이 나온다.
]]

local Types = require(script.Parent.Parent.Types)

local MovementConfig = {}

-- 이 속도 아래로 떨어지면 0 으로 스냅한다.
-- 하필 1 stud/s 인 이유: 서버 감지의 MOVE_EPSILON(0.05 stud/tick @ 20Hz)이
-- 정확히 1 stud/s 다. 즉 "멈췄다"는 말이 "감지에 안 걸린다"와 같은 뜻이 된다.
MovementConfig.STOP_CUTOFF = 1

MovementConfig.DEFAULT_MODE = "WALK" :: Types.MoveMode

MovementConfig.MODES = {
	SNEAK = { speed = 4, stopTime = 0.08, noisy = false, label = "살금살금" },
	WALK = { speed = 10, stopTime = 0.35, noisy = false, label = "걷기" },
	RUN = { speed = 17, stopTime = 0.75, noisy = true, label = "달리기" },
} :: { [Types.MoveMode]: Types.MoveModeConfig }

--[[
	서버가 "달렸다"고 판정하는 속도 기준.
	걷기(10)와 달리기(17) 사이에 둔다. 클라이언트가 보고하는 모드값이 아니라
	서버가 기록한 위치 델타로 계산한 속도와 비교한다.
]]
MovementConfig.RUN_NOISE_SPEED = 13.5

-- 발소리가 선생님에게 닿는 거리(스터드). 교실 하나를 덮는 크기.
MovementConfig.RUN_NOISE_RADIUS = 45

return MovementConfig
