--!strict
--[[
	PBR 재질(MaterialService 의 MaterialVariant)로 base 재질 전체를 덮는다. 그리기는 클라에서만 하므로 클라에서 한다.
	MaterialVariant 는 default.project.json 에 둔다 — 스크립트는 BaseMaterial 을 쓸 권한이 없어 런타임에 만들 수 없다.
	  SchoolFloorWood → WoodPlanks(바닥만 쓴다: 층 방 마루(클라 FloorWood)·체육관·음악실·도서관·강당 무대·옥상 정원)
	벽 Plaster 변형도 만들었다가 뺐다(2026-10-03 화면 비교: 벽이 어두워지고 파란 얼룩이 보였다). 벽은 기본 Plaster 그대로
	네 맵을 다 불러온 재질만 덮는다. 그 전·실패 시에는 로블록스 기본 재질 그대로(폴백). 부팅을 막지 않게 따로 돈다.
]]

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")

local MaterialSetup = {}

local MAPS = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }

local function apply(v: MaterialVariant)
	-- 게임 스크립트는 MaterialVariant 의 맵 속성(ColorMap·ColorMapContent 등)을 못 읽는다(Plugin 권한). 그래서
	-- default.project.json 이 같은 uri 를 같은 이름의 어트리뷰트로도 단다. 바꿀 때는 속성과 어트리뷰트를 같이 바꾼다.
	-- 변형을 그대로 PreloadAsync 하면 콜백이 0번이고 uri 문자열은 늘 Failure 라(2026-10-02 Studio 실측) 맵마다 부모 없는
	-- Decal 에 담아 불러오고 Success 를 센다. 빈 어트리뷰트는 Decal 도 콜백이 없어 모자란 쪽으로 센다
	local decals = {}
	for _, name in MAPS do
		local d = Instance.new("Decal")
		d.Texture = tostring(v:GetAttribute(name) or "")
		table.insert(decals, d)
	end
	local loaded = 0
	ContentProvider:PreloadAsync(decals, function(_, status)
		if status == Enum.AssetFetchStatus.Success then
			loaded += 1
		end
	end)
	if loaded < #decals then
		warn(`[MaterialSetup] {v.Name} 맵 {loaded}/{#decals} — 기본 재질 유지`)
		return
	end
	MaterialService:SetBaseMaterialOverride(v.BaseMaterial, v.Name)
end

function MaterialSetup.Start()
	for _, v in MaterialService:GetChildren() do
		if v:IsA("MaterialVariant") then
			task.spawn(apply, v)
		end
	end
end

return MaterialSetup
