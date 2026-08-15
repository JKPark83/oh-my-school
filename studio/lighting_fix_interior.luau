-- Studio 명령 바(Command Bar)에 붙여넣고 실행.
--
-- ★ 조명 값의 주인은 이 파일이 아니다.
--   Lighting 프로퍼티와 Atmosphere/Bloom 은 default.project.json 이,
--   교실 광원(PointLight) 밝기는 src/server/Classroom/Template.luau 가 정한다.
--   Rojo 가 동기화하면 둘 다 알아서 맞춰진다.
--
--   이 스크립트가 하는 일은 하나뿐이다: **Rojo 가 모르는 잔재를 걷어내는 것**.
--   .rbxl 안에 손으로 넣어둔 post-processing 이 남아 있으면 project.json 을
--   아무리 고쳐도 화면이 계속 하얗다 — Rojo 는 자기가 만든 이름의 자식만 관리한다.
--
--   ※ Undo(Ctrl+Z)로 되돌아가지 않는다. 아래 BEFORE 출력을 남겨둘 것.

local Lighting = game:GetService("Lighting")

-- project.json 이 관리하는 이름. 이 둘만 남기고 나머지 효과는 잔재로 본다.
local MANAGED = { Haze = true, Bloom = true }

local function c3(c: Color3): string
	return string.format("rgb(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255)
end

print("========== BEFORE ==========")
print("Technology       :", Lighting.Technology)
print("Brightness       :", Lighting.Brightness)
print("ExposureComp     :", Lighting.ExposureCompensation)
print("Ambient          :", c3(Lighting.Ambient))
print("OutdoorAmbient   :", c3(Lighting.OutdoorAmbient))
print("EnvDiffuseScale  :", Lighting.EnvironmentDiffuseScale)
print("EnvSpecularScale :", Lighting.EnvironmentSpecularScale)

print("========== POST FX ==========")
local strays = {}
for _, fx in Lighting:GetChildren() do
	if not fx:IsA("PostEffect") and not fx:IsA("Atmosphere") and not fx:IsA("Sky") then
		continue
	end

	local detail = fx.ClassName
	if fx:IsA("BloomEffect") then
		detail = string.format("Bloom Intensity=%.2f Size=%d Threshold=%.2f", fx.Intensity, fx.Size, fx.Threshold)
	elseif fx:IsA("ColorCorrectionEffect") then
		detail = string.format(
			"ColorCorrection Brightness=%.2f Contrast=%.2f Saturation=%.2f",
			fx.Brightness,
			fx.Contrast,
			fx.Saturation
		)
	elseif fx:IsA("Atmosphere") then
		detail = string.format("Atmosphere Density=%.2f Haze=%.2f Glare=%.2f", fx.Density, fx.Haze, fx.Glare)
	end

	local managed = MANAGED[fx.Name] == true
	print(("  %-10s %s  %s"):format(fx.Name, managed and "[project.json]" or "[잔재]", detail))
	if not managed then
		table.insert(strays, fx)
	end
end

for _, fx in strays do
	fx:Destroy()
end
print(("잔재 %d개 제거됨"):format(#strays))

--[[
	반사율 정리. 실내 마감재는 Reflectance 0 이 정상이고, 유리만 예외다.
	이건 Rojo 가 아니라 손으로 찍어둔 파트에서 생기는 문제라 여기 남긴다.
]]
local reset = 0
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst.Reflectance > 0 and inst.Material ~= Enum.Material.Glass then
		inst.Reflectance = 0
		reset += 1
	end
end
print(("Reflectance 초기화: %d개"):format(reset))

print("=== 완료. 나머지 값은 Rojo 동기화로 들어온다 ===")
