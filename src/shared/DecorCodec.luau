--!strict
--[[
	꾸미기 배치 ↔ 문자열(PlotState 어트리뷰트 "Decor"). 순수 함수. 개선계획 §3.5 #4.
	한 항목 = LIST 순번 2자리 + cx 2자리 + cz 2자리 + rot 1자리 + [층 1~2자리, 1층이면 생략] + ";"
	  예: "01292935;" = planter(01) · 칸 (29,29) · rot 3 · 5층
	decode 는 모르는 순번·범위 밖 값을 건너뛴다(잘못된 항목 하나가 나머지를 망치지 않게).
]]

local DecorConfig = require(script.Parent.Config.DecorConfig)
local Types = require(script.Parent.Types)

local DecorCodec = {}

local SEP = ";"
local MAX_FLOOR = 99

local function isInt(v: number, lo: number, hi: number): boolean
	return v == math.floor(v) and v >= lo and v <= hi
end

function DecorCodec.encode(placed: { Types.DecorPlacement }): string
	local out = table.create(#placed)
	for _, p in placed do
		local index = DecorConfig.indexOf(p.item)
		if index then
			local f = p.f or 1
			local floorPart = if f ~= 1 then tostring(f) else ""
			table.insert(out, string.format("%02d%02d%02d%d%s%s", index, p.cx, p.cz, p.rot, floorPart, SEP))
		end
	end
	return table.concat(out)
end

function DecorCodec.decode(text: string): { Types.DecorPlacement }
	local result: { Types.DecorPlacement } = {}
	local last = DecorConfig.GRID - 1
	for entry in string.gmatch(text, "([^;]+)") do
		if #entry >= 7 and #entry <= 9 and string.match(entry, "^%d+$") then
			local index = tonumber(string.sub(entry, 1, 2)) :: number
			local cx = tonumber(string.sub(entry, 3, 4)) :: number
			local cz = tonumber(string.sub(entry, 5, 6)) :: number
			local rot = tonumber(string.sub(entry, 7, 7)) :: number
			local f = if #entry > 7 then tonumber(string.sub(entry, 8)) :: number else 1
			local item = DecorConfig.LIST[index]
			if item and isInt(cx, 0, last) and isInt(cz, 0, last) and isInt(rot, 0, 3) and isInt(f, 1, MAX_FLOOR) then
				table.insert(result, {
					item = item.id,
					cx = cx,
					cz = cz,
					rot = rot,
					f = if f ~= 1 then f else nil,
				})
			end
		end
	end
	return result
end

return DecorCodec
