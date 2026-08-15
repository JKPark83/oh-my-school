-- Studio 명령 바(Command Bar)에 붙여넣고 실행 → 출력을 그대로 복사해서 알려주세요.
local Lighting = game:GetService("Lighting")

local function c3(c)
	return string.format("rgb(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255)
end

print("========== LIGHTING ==========")
print("Technology        :", Lighting.Technology)
print("Brightness        :", Lighting.Brightness)
print("ExposureComp      :", Lighting.ExposureCompensation)
print("Ambient           :", c3(Lighting.Ambient))
print("OutdoorAmbient    :", c3(Lighting.OutdoorAmbient))
print("EnvDiffuseScale   :", Lighting.EnvironmentDiffuseScale)
print("EnvSpecularScale  :", Lighting.EnvironmentSpecularScale)
print("GlobalShadows     :", Lighting.GlobalShadows)
print("ClockTime         :", Lighting.ClockTime)

print("========== POST FX ==========")
for _, fx in ipairs(Lighting:GetChildren()) do
	if fx:IsA("BloomEffect") then
		print(("Bloom  Intensity=%.2f Size=%d Threshold=%.2f Enabled=%s")
			:format(fx.Intensity, fx.Size, fx.Threshold, tostring(fx.Enabled)))
	elseif fx:IsA("ColorCorrectionEffect") then
		print(("ColorCorrection  Brightness=%.2f Contrast=%.2f Saturation=%.2f Enabled=%s")
			:format(fx.Brightness, fx.Contrast, fx.Saturation, tostring(fx.Enabled)))
	elseif fx:IsA("Atmosphere") then
		print(("Atmosphere  Density=%.2f Haze=%.2f Glare=%.2f")
			:format(fx.Density, fx.Haze, fx.Glare))
	elseif fx:IsA("SunRaysEffect") or fx:IsA("BlurEffect") or fx:IsA("DepthOfFieldEffect") then
		print(fx.ClassName, "Enabled=" .. tostring(fx.Enabled))
	end
end

print("========== LIGHTS ==========")
local counts, samples = {}, {}
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("Light") then
		local k = inst.ClassName
		counts[k] = (counts[k] or 0) + 1
		if #(samples[k] or {}) < 3 then
			samples[k] = samples[k] or {}
			table.insert(samples[k], ("  %s  Brightness=%.2f Range=%.0f Shadows=%s  <- %s")
				:format(inst.Name, inst.Brightness, inst.Range, tostring(inst.Shadows),
					inst.Parent and inst.Parent:GetFullName() or "?"))
		end
	end
end
for cls, n in pairs(counts) do
	print(cls .. " x" .. n)
	for _, line in ipairs(samples[cls]) do print(line) end
end

print("========== REFLECTANCE / NEON ==========")
local shiny, neon = 0, 0
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("BasePart") then
		if inst.Reflectance > 0.05 then
			shiny += 1
			if shiny <= 5 then
				print(("  Reflectance=%.2f  %s (%s)"):format(inst.Reflectance, inst:GetFullName(), inst.Material.Name))
			end
		end
		if inst.Material == Enum.Material.Neon then neon += 1 end
	end
end
print(("Reflectance>0.05 parts: %d, Neon parts: %d"):format(shiny, neon))
