--!strict
--[[
	숫자 표기. 기획서 §8.1.
	  ≤ 9,999 → "3,274"  /  만 단위 → "1.2만"  /  억 단위 → "1.5억"
	  수입 → "초마다 +9,003"  /  배율 → "×5.2" (소수 1자리 내림)
]]

local Format = {}

local function withCommas(n: number): string
	local s = tostring(n)
	local head, tail = string.match(s, "^(-?%d+)(%.?%d*)$")
	if not head then
		return s
	end
	local out = string.reverse((string.gsub(string.reverse(head), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	out = string.gsub(out, "^%-,", "-")
	return out .. (tail or "")
end

local function short(value: number, unit: string): string
	local text = string.format("%.1f", value)
	text = string.gsub(text, "%.0$", "")
	return text .. unit
end

--- 용돈·가격 표기
function Format.coins(n: number): string
	local v = math.floor(n)
	if v < 10000 then
		return withCommas(v)
	elseif v < 100000000 then
		return short(v / 10000, "만")
	end
	return short(v / 100000000, "억")
end

--- 초당 수입 표기
function Format.income(n: number): string
	return "초마다 +" .. Format.coins(n)
end

--- 배율 표기. 소수 1자리 내림
function Format.multiplier(x: number): string
	local floored = math.floor(x * 10) / 10
	return string.format("×%.1f", floored)
end

--- 남은 시간 표기. 60초 미만 "42초", 그 이상 "3분"
function Format.eta(seconds: number): string
	if seconds == math.huge or seconds ~= seconds then
		return "-"
	end
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return `{s}초`
	end
	return `{math.ceil(s / 60)}분`
end

return Format
