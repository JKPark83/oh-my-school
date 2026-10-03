--!strict
--[[
	클라 소품 메시 원본 캐시(PropAssets.HERO·DECOR). TowerRenderController·InteriorRenderController·DecorController·PanelController 가 같이 쓴다.
	  MeshCache.get(asset)  준비된 원본(복제해서 쓴다). 아직이면 불러오기를 걸고 nil, id 0·실패도 nil(= 파트 폴백).
	  MeshCache.onReady(fn) 새 메시가 준비되면 부른다. 여러 개가 잇따라 와도 READY_DELAY 에 한 번만.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DecorBuilder = require(ReplicatedStorage.Shared.DecorBuilder)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)

local MeshCache = {}

local READY_DELAY = 0.5 -- 방 하나가 메시 여럿을 한꺼번에 부른다. 다시 짓기를 한 번으로 묶는다

local cache: { [number]: MeshPart | false } = {}
local loading: { [number]: boolean } = {}
local listeners: { () -> () } = {}
local queued = false

local function notify()
	if queued then
		return
	end
	queued = true
	task.delay(READY_DELAY, function()
		queued = false
		for _, fn in listeners do
			fn()
		end
	end)
end

function MeshCache.get(asset: PropAssets.MeshAsset): MeshPart?
	local id = asset.id
	local cached = cache[id]
	if cached ~= nil then
		return if cached then cached :: MeshPart else nil
	end
	if id > 0 and not loading[id] then
		loading[id] = true
		task.spawn(function()
			local ok, result = pcall(function()
				return AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Automatic,
				})
			end)
			if ok and result then
				if asset.texture then
					result.TextureID = "rbxassetid://" .. asset.texture
				end
				cache[id] = result
				notify()
			else
				cache[id] = false
				warn(`[MeshCache] 메시 {id} 를 못 만들었다. 파트로 짓는다 ({result})`)
			end
		end)
	end
	return nil
end

--- 꾸미기 아이템 메시(PropAssets.DECOR). DecorBuilder.build 의 options.mesh 로 넘긴다. 없거나 아직이면 nil(= 파트)
function MeshCache.decor(itemId: string): DecorBuilder.Mesh?
	local entry = PropAssets.DECOR[itemId]
	local part = if entry then MeshCache.get(entry.asset) else nil
	return if entry and part then { part = part, yaw = entry.yaw, height = entry.height } else nil
end

function MeshCache.onReady(fn: () -> ())
	table.insert(listeners, fn)
end

return MeshCache
