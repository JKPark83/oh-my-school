--!strict
--[[
	학년/반별 선생님 수치.

	핵심 원칙: 2~6학년은 코드가 아니라 데이터다.
	여기에 학년 항목을 추가하는 것만으로 콘텐츠가 늘어나야 한다.

	반 1 → 반 12는 first / last 사이를 선형 보간한다.
	반마다 표를 손으로 쓰지 않는다.
]]

local Types = require(script.Parent.Parent.Types)

local CLASSES_PER_GRADE = 12

local BANDS: { [number]: { first: Types.TeacherConfig, last: Types.TeacherConfig } } = {
	-- 1학년: 페이크 턴 0%.
	-- 첫 학년에서 배워야 할 규칙은 "예고를 보면 멈춘다" 하나뿐이다.
	-- 여기에 낚시를 섞으면 규칙 자체를 못 배운다.
	[1] = {
		first = { teachTime = 5.0, warnTime = 0.75, turnTime = 0.45, watchTime = 1.6, fovDeg = 90, fakeChance = 0 },
		last = { teachTime = 3.5, warnTime = 0.60, turnTime = 0.45, watchTime = 2.2, fovDeg = 90, fakeChance = 0 },
	},
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local DifficultyTable = {}

DifficultyTable.CLASSES_PER_GRADE = CLASSES_PER_GRADE

function DifficultyTable.get(grade: number, class: number): Types.TeacherConfig
	local band = BANDS[grade]
	assert(band, `{grade}학년 난이도 정의가 없다. DifficultyTable.BANDS에 추가해야 한다.`)

	local t = (math.clamp(class, 1, CLASSES_PER_GRADE) - 1) / (CLASSES_PER_GRADE - 1)
	local first, last = band.first, band.last

	return {
		teachTime = lerp(first.teachTime, last.teachTime, t),
		warnTime = lerp(first.warnTime, last.warnTime, t),
		turnTime = lerp(first.turnTime, last.turnTime, t),
		watchTime = lerp(first.watchTime, last.watchTime, t),
		fovDeg = lerp(first.fovDeg, last.fovDeg, t),
		fakeChance = lerp(first.fakeChance, last.fakeChance, t),
	}
end

return DifficultyTable
