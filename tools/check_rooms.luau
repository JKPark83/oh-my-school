--!strict
--[[
	방 레시피 검사(Studio 없이). 로블록스 타입을 흉내 내고 가짜 put 으로 12개 방 레시피를 big·props·finish 끝까지 돌린다.
	standalone luau 는 io 가 없어 소스를 인자 하나로 넘긴다(파일마다 "--@@FILE 경로" 줄로 시작).

	  cd <repo> && luau tools/check_rooms.luau -a "$(for f in $(find src/shared src/client/Rooms -name '*.luau'); \
	    do echo "--@@FILE $f"; cat "$f"; done)" [방id]

	규칙(실패하면 방·파트·값을 찍고 exit 1)
	  a 파트 수 ≤ 60(옥상 방 ≤ 45)
	  b 모든 파트 AABB 가 방 안(층 방 = 벽 안쪽 면·바닥·천장, 옥상 방 = 자기 zone·바닥~천장 높이·난간 안쪽 면 안)
	  c 가구 금지 구역(x ≥ 12.5 and z ≥ -2.5)·엘리베이터 기둥 모서리(x ≥ 18.5 and z ≤ -13.5)에 안 겹친다
	  d 좌석 상자(좌석 위 0.3~4.3, 가로·깊이 2)에 Chair*·Desk* 말고는 안 겹친다
	  e 좌석은 바닥(y 0)·방(구역) 안이고, 그 아래 Chair* 윗면이 앉는 높이(SIT_HIP-0.4 ~ SIT_HIP)다
	  f 뜬 파트 없음: 바닥 위, 다른 파트 윗면~안(가로 겹침), 벽 안쪽 면·천장에 붙음(층 방만). 허용 0.15
	  g 빨강 없음: 색상 H < 15° 또는 > 345° 이면서 채도 S > 0.5 금지
	  h 충돌 파트(opts.collide)가 좌석 상자에 겹치지 않고, 통로(폭 4, 도착 자리 → 방 가운데·옥상은 구역 가운데)를 막지 않는다
	회전은 AABB 로 감싼다(공 = 지름 min(size), 원기둥 = 축 X·지름 min(Y, Z)).
]]

local EPS = 0.01
local TOUCH = 0.15
-- Tower.luau RoofRail 안쪽 면(방 기준): 발자국 반(20, 15) - INSET 0.05 - RAIL_T 1. 탑 패드·도착 자리는 금지 구역(c)이 덮는다
local RAIL_IN = { X = 18.95, Y = 13.95 }

-- ── 소스 묶음 ──
local blob, onlyRoom = ...
assert(type(blob) == "string", "소스 묶음 인자가 없다(머리말 사용법)")
local files: { [string]: string } = {}
do
	local path: string? = nil
	local buf: { string } = {}
	for line in string.gmatch(blob .. "\n", "([^\n]*)\n") do
		local p = string.match(line, "^%-%-@@FILE (.+)$")
		if p then
			if path then
				files[path] = table.concat(buf, "\n")
			end
			path, buf = p, {}
		else
			table.insert(buf, line)
		end
	end
	if path then
		files[path] = table.concat(buf, "\n")
	end
end

-- ── 가짜 로블록스 타입 ──
local V3 = {}
local V3mt: any = {}
local function v3(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, V3mt)
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	return if type(b) == "number" then v3(a.X / b, a.Y / b, a.Z / b) else v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__index = function(a, k)
	local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
	if k == "Magnitude" then
		return m
	elseif k == "Unit" then
		return v3(a.X / m, a.Y / m, a.Z / m)
	end
	return nil
end
V3mt.__tostring = function(a)
	return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z)
end
V3.new = function(x: number?, y: number?, z: number?)
	return v3(x or 0, y or 0, z or 0)
end
V3.one = v3(1, 1, 1)
V3.zero = v3(0, 0, 0)

local V2mt: any = {}
local function v2(x: number, y: number): any
	return setmetatable({ X = x, Y = y }, V2mt)
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	return if type(b) == "number" then v2(a.X * b, a.Y * b) else v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__index = function(a, k)
	if k == "Magnitude" then
		return math.sqrt(a.X * a.X + a.Y * a.Y)
	end
	return nil
end
local V2 = {
	new = function(x: number?, y: number?)
		return v2(x or 0, y or 0)
	end,
}
V2.zero = v2(0, 0)
V2.one = v2(1, 1)

local Color3 = {
	new = function(r: number?, g: number?, b: number?)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
	fromRGB = function(r: number?, g: number?, b: number?)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
	end,
}

-- CFrame: 3×3 행 우선 회전 r + 위치 p
local CFmt: any = {}
local function cf(r: { number }, p: any): any
	return setmetatable({ r = r, p = p }, CFmt)
end
local function rotate(r: { number }, v: any): any
	return v3(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
local function matmul(a: { number }, b: { number }): { number }
	local out = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			out[i * 3 + j + 1] = s
		end
	end
	return out
end
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
CFmt.__mul = function(a, b)
	if getmetatable(b) == CFmt then
		return cf(matmul(a.r, b.r), a.p + rotate(a.r, b.p))
	end
	return a.p + rotate(a.r, b)
end
CFmt.__index = function(a, k)
	if k == "Position" then
		return a.p
	elseif k == "VectorToWorldSpace" then
		return function(self, v)
			return rotate(self.r, v)
		end
	end
	return nil
end
local CFrame = {
	new = function(x: any?, y: number?, z: number?)
		if type(x) == "table" then
			return cf(I3, x)
		end
		return cf(I3, v3(x or 0, y or 0, z or 0))
	end,
	Angles = function(rx: number, ry: number, rz: number)
		local cx, sx, cy, sy, cz, sz =
			math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
		local mx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
		local my = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
		local mz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
		return cf(matmul(matmul(mx, my), mz), v3(0, 0, 0))
	end,
	identity = cf(I3, v3(0, 0, 0)),
}

local Enum = setmetatable({}, {
	__index = function(t, kind)
		local items = setmetatable({}, {
			__index = function(e, name)
				local token = setmetatable({ Name = name, EnumType = kind }, {
					__tostring = function()
						return `Enum.{kind}.{name}`
					end,
				})
				rawset(e, name, token)
				return token
			end,
		})
		rawset(t, kind, items)
		return items
	end,
})

-- ── 모듈 경로 흉내(script·game) ──
local function hasPrefix(prefix: string): boolean
	for path in files do
		if string.sub(path, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local nodeMt: any = {}
local nodes: { [string]: any } = {}
local function node(dir: string): any
	local n = nodes[dir]
	if not n then
		n = setmetatable({ dir = dir }, nodeMt)
		nodes[dir] = n
	end
	return n
end
--- 이 노드가 모듈이면 그 소스 경로
local function sourceOf(n: any): string?
	local d = rawget(n, "dir")
	if files[d .. ".luau"] then
		return d .. ".luau"
	elseif files[d .. "/init.luau"] then
		return d .. "/init.luau"
	end
	return nil
end
local function childOf(n: any, name: string): any
	local d = rawget(n, "dir") .. "/" .. name
	if files[d .. ".luau"] or hasPrefix(d .. "/") then
		return node(d)
	end
	return nil
end
nodeMt.__index = function(n, k)
	local d = rawget(n, "dir")
	if k == "Parent" then
		return node(string.match(d, "^(.*)/[^/]+$") or "")
	elseif k == "Name" then
		return string.match(d, "([^/]+)$")
	elseif k == "FindFirstChild" then
		return function(self, name)
			return childOf(self, name)
		end
	elseif k == "IsA" then
		return function(self, class)
			return class == "ModuleScript" and sourceOf(self) ~= nil
		end
	end
	local c = childOf(n, k)
	assert(c, `없는 모듈 경로 {d}.{k}`)
	return c
end

local permissive: any = setmetatable({}, {
	__index = function()
		return function() end
	end,
})
local ReplicatedStorage = { Shared = node("src/shared") }
local game = {
	GetService = function(_, name: string)
		return if name == "ReplicatedStorage" then ReplicatedStorage else permissive
	end,
}

local base = getfenv(1)
local loaded: { [string]: any } = {}
local function req(n: any): any
	local path = sourceOf(n)
	assert(path, `모듈이 아니다: {rawget(n, "dir")}`)
	if loaded[path] ~= nil then
		return loaded[path]
	end
	local src = files[path]
	if string.match(path, "CharacterBuilder%.luau$") then
		-- Instance 를 만드는 모듈이라 수치만 뽑는다
		loaded[path] = {
			SIT_HIP = tonumber(string.match(src, "CharacterBuilder%.SIT_HIP = ([%d%.]+)")),
			SIT_DESK = tonumber(string.match(src, "CharacterBuilder%.SIT_DESK = ([%d%.]+)")),
		}
		return loaded[path]
	end
	local f, err = loadstring(src, "=" .. path)
	assert(f, err)
	setfenv(
		f,
		setmetatable({
			script = n, -- init.luau 의 script 는 폴더 노드(Rojo 와 같다)
			game = game,
			require = req,
			Vector3 = V3,
			Vector2 = V2,
			Color3 = Color3,
			CFrame = CFrame,
			Enum = Enum,
		}, { __index = base })
	)
	local result = f()
	loaded[path] = result
	return result
end

-- ── 검사 ──
local Rooms = req(node("src/client/Rooms"))
local RoomConfig = req(node("src/shared/Config/RoomConfig"))
local Kit = Rooms.Kit

type Box = { name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, collide: boolean }

local failures = 0
local function fail(roomId: string, rule: string, msg: string)
	failures += 1
	print(`FAIL [{roomId}] ({rule}) {msg}`)
end

local function boxStr(b: Box): string
	return string.format("%s x %.2f~%.2f y %.2f~%.2f z %.2f~%.2f", b.name, b.x0, b.x1, b.y0, b.y1, b.z0, b.z1)
end

--- 두 구간이 양(+)의 길이로 겹치는가
local function over(a0: number, a1: number, b0: number, b1: number): boolean
	return a0 < b1 - EPS and b0 < a1 - EPS
end

local function hsv(c: any): (number, number)
	local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == c.R then
			h = 60 * (((c.G - c.B) / d) % 6)
		elseif mx == c.G then
			h = 60 * ((c.B - c.R) / d + 2)
		else
			h = 60 * ((c.R - c.G) / d + 4)
		end
	end
	return h, if mx > 0 then d / mx else 0
end

-- 구역끼리·금지 구역·기둥과 안 겹친다
do
	local zones = {}
	for _, room in RoomConfig.LIST do
		if room.kind == "roof" then
			local z = Kit.zone(room)
			if z.x1 > Kit.CLEAR.X and z.z1 > Kit.CLEAR.Y then
				fail(room.id, "zone", "옥상 구역이 가구 금지 구역과 겹친다")
			end
			if z.x1 > Kit.PILLAR.X and z.z0 < Kit.PILLAR.Y then
				fail(room.id, "zone", "옥상 구역이 엘리베이터 기둥과 겹친다")
			end
			for _, other in zones do
				if over(z.x0, z.x1, other.z.x0, other.z.x1) and over(z.z0, z.z1, other.z.z0, other.z.z1) then
					fail(room.id, "zone", `옥상 구역이 {other.id} 구역과 겹친다`)
				end
			end
			table.insert(zones, { id = room.id, z = z })
		end
	end
end

local function checkRoom(room: any)
	local id = room.id
	local roof = room.kind == "roof"
	local boxes: { Box } = {}
	local function put(name: string, size: any, pos: any, color: any, opts: any?): any
		local o = opts or {}
		local shape = o.shape and o.shape.Name or "Block"
		local half
		if shape == "Ball" then
			local d = math.min(size.X, size.Y, size.Z) / 2
			half = v3(d, d, d)
		elseif shape == "Cylinder" then
			local d = math.min(size.Y, size.Z) / 2
			half = v3(size.X / 2, d, d)
		else
			half = size / 2
		end
		local r = if o.rot then o.rot.r else I3
		local hx = math.abs(r[1]) * half.X + math.abs(r[2]) * half.Y + math.abs(r[3]) * half.Z
		local hy = math.abs(r[4]) * half.X + math.abs(r[5]) * half.Y + math.abs(r[6]) * half.Z
		local hz = math.abs(r[7]) * half.X + math.abs(r[8]) * half.Y + math.abs(r[9]) * half.Z
		local b: Box = {
			name = name,
			x0 = pos.X - hx,
			x1 = pos.X + hx,
			y0 = pos.Y - hy,
			y1 = pos.Y + hy,
			z0 = pos.Z - hz,
			z1 = pos.Z + hz,
			collide = o.collide == true,
		}
		table.insert(boxes, b)
		local h, s = hsv(color)
		if (h < 15 or h > 345) and s > 0.5 then
			fail(id, "g", string.format("%s 빨강 계열 H %.0f S %.2f", name, h, s))
		end
		return {}
	end
	local recipe = Rooms.get(id)
	local ctx = { room = room, floor = RoomConfig.FIRST_FLOOR }
	recipe.big(put, ctx)
	recipe.props(put, ctx)
	recipe.finish(put, ctx)

	-- a
	local limit = if roof then 45 else 60
	if #boxes > limit then
		fail(id, "a", `파트 {#boxes} > {limit}`)
	end

	local zone = Kit.zone(room)
	local seatBoxes = {}
	for i, s in room.seats do
		table.insert(
			seatBoxes,
			{ i = i, s = s, x0 = s.X - 1, x1 = s.X + 1, y0 = s.Y + 0.3, y1 = s.Y + 4.3, z0 = s.Z - 1, z1 = s.Z + 1 }
		)
	end
	local walkTo = if roof then v2((zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2) else v2(0, 0)

	for _, b in boxes do
		-- b
		if
			b.x0 < zone.x0 - EPS
			or b.x1 > zone.x1 + EPS
			or b.z0 < zone.z0 - EPS
			or b.z1 > zone.z1 + EPS
			or b.y0 < -EPS
			or b.y1 > Kit.CEIL + EPS
		then
			fail(id, "b", `{boxStr(b)} 가 방 밖(x {zone.x0}~{zone.x1} z {zone.z0}~{zone.z1} y 0~{Kit.CEIL})`)
		end
		if roof and (math.max(-b.x0, b.x1) > RAIL_IN.X + EPS or math.max(-b.z0, b.z1) > RAIL_IN.Y + EPS) then
			fail(id, "b", `{boxStr(b)} 가 옥상 난간(|x| ≤ {RAIL_IN.X}, |z| ≤ {RAIL_IN.Y})에 겹친다`)
		end
		-- c
		if b.x1 > Kit.CLEAR.X + EPS and b.z1 > Kit.CLEAR.Y + EPS then
			fail(id, "c", `{boxStr(b)} 가 가구 금지 구역(x ≥ {Kit.CLEAR.X}, z ≥ {Kit.CLEAR.Y})에 겹친다`)
		end
		if b.x1 > Kit.PILLAR.X + EPS and b.z0 < Kit.PILLAR.Y - EPS then
			fail(
				id,
				"c",
				`{boxStr(b)} 가 엘리베이터 기둥(x ≥ {Kit.PILLAR.X}, z ≤ {Kit.PILLAR.Y})에 겹친다`
			)
		end
		-- d·h(좌석)
		for _, sb in seatBoxes do
			if over(b.x0, b.x1, sb.x0, sb.x1) and over(b.y0, b.y1, sb.y0, sb.y1) and over(b.z0, b.z1, sb.z0, sb.z1) then
				if b.collide then
					fail(id, "h", `충돌 파트 {boxStr(b)} 가 좌석 {sb.i} 상자에 겹친다`)
				elseif not (string.sub(b.name, 1, 5) == "Chair" or string.sub(b.name, 1, 4) == "Desk") then
					fail(id, "d", `{boxStr(b)} 가 좌석 {sb.i} 상자(위 0.3~4.3)에 겹친다`)
				end
			end
		end
		-- f
		local held = b.y0 <= TOUCH
		if not roof and not held then
			held = math.abs(b.x0 + Kit.X_IN) <= TOUCH
				or math.abs(b.x1 - Kit.X_IN) <= TOUCH
				or math.abs(b.z0 - Kit.Z_N) <= TOUCH
				or math.abs(b.z1 - Kit.Z_S) <= TOUCH
				or math.abs(b.y1 - Kit.CEIL) <= TOUCH
		end
		if not held then
			for _, q in boxes do
				if
					q ~= b
					and b.y0 >= q.y0 - TOUCH
					and b.y0 <= q.y1 + TOUCH
					and over(b.x0, b.x1, q.x0, q.x1)
					and over(b.z0, b.z1, q.z0, q.z1)
				then
					held = true
					break
				end
			end
		end
		if not held then
			fail(id, "f", `{boxStr(b)} 가 떠 있다(바닥·다른 파트 위·벽·천장 어디에도 안 닿음)`)
		end
		-- h(통로)
		if b.collide and b.y1 > 0.6 then
			local seg = walkTo - Kit.ARRIVAL
			local steps = math.ceil(seg.Magnitude / 0.25)
			for k = 0, steps do
				local p = Kit.ARRIVAL + seg * (k / steps)
				if p.X > b.x0 - 2 and p.X < b.x1 + 2 and p.Y > b.z0 - 2 and p.Y < b.z1 + 2 then
					fail(
						id,
						"h",
						string.format(
							"충돌 파트 %s 가 통로(%.1f, %.1f)를 막는다(폭 4)",
							boxStr(b),
							p.X,
							p.Y
						)
					)
					break
				end
			end
		end
	end

	-- e
	for _, sb in seatBoxes do
		local s = sb.s
		if math.abs(s.Y) > EPS then
			fail(id, "e", `좌석 {sb.i} {s} 가 바닥(y 0) 위가 아니다`)
		end
		if s.X - 1 < zone.x0 or s.X + 1 > zone.x1 or s.Z - 1 < zone.z0 or s.Z + 1 > zone.z1 then
			fail(id, "e", `좌석 {sb.i} {s} 가 방(구역) 밖이다`)
		end
		if s.X > Kit.CLEAR.X and s.Z > Kit.CLEAR.Y then
			fail(id, "e", `좌석 {sb.i} {s} 가 가구 금지 구역 안이다`)
		end
		local seated = false
		for _, b in boxes do
			if
				string.sub(b.name, 1, 5) == "Chair"
				and s.X > b.x0
				and s.X < b.x1
				and s.Z > b.z0
				and s.Z < b.z1
				and b.y1 >= Kit.SIT_HIP - 0.4
				and b.y1 <= Kit.SIT_HIP + EPS
			then
				seated = true
			end
		end
		if not seated then
			fail(id, "e", `좌석 {sb.i} {s} 아래 앉을 Chair* (윗면 {Kit.SIT_HIP - 0.4}~{Kit.SIT_HIP})가 없다`)
		end
	end
	print(string.format("%-12s %-6s 파트 %2d/%d  좌석 %d", id, room.kind, #boxes, limit, #room.seats))
end

local found = false
for _, room in RoomConfig.LIST do
	if onlyRoom == nil or onlyRoom == room.id then
		found = true
		checkRoom(room)
	end
end
assert(found, `모르는 방 id {onlyRoom}`)
if failures > 0 then
	error(`실패 {failures}건`, 0) -- standalone luau 는 os.exit 가 없다. 잡히지 않은 error = exit 1
end
print("check_rooms: 통과")
