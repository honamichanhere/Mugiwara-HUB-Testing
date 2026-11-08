local LightingModule = getgenv().MugiwaraImport("Manager/Lighting.lua")
local HttpService = game:GetService("HttpService")

local SharePreset = {}
SharePreset.JOEVAN_PREFIX = "JOEVAN#"
SharePreset.MAX_CODE_LENGTH = 65536

local MWL_PREFIX = "MWL1:"

local WIRE_SKY = {
    { "SkyboxBk", "t" }, { "SkyboxDn", "t" }, { "SkyboxFt", "t" }, { "SkyboxLf", "t" }, { "SkyboxRt", "t" }, { "SkyboxUp", "t" },
    { "SunTextureId", "t" }, { "MoonTextureId", "t" }, { "StarCount", "n" }, { "CelestialBodiesShown", "b" },
    { "SunAngularSize", "n" }, { "MoonAngularSize", "n" },
}
local SKY_SHORT = { SkyboxBk = "Bk", SkyboxDn = "Dn", SkyboxFt = "Ft", SkyboxLf = "Lf", SkyboxRt = "Rt", SkyboxUp = "Up" }

local CATEGORIES = { "Lighting", "Atmosphere", "Bloom", "Blur", "ColorCorrection", "DepthOfField", "SunRays", "Clouds" }
local POST_EFFECTS = { "Bloom", "ColorCorrection", "DepthOfField", "SunRays" }

local function trim(text)
    return (string.gsub(string.gsub(tostring(text or ""), "^%s+", ""), "%s+$", ""))
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function round(value)
    return math.floor(value * 10000 + 0.5) / 10000
end

local function colorRGB(value)
    if typeof and typeof(value) == "Color3" then
        return value.R, value.G, value.B
    end
    if type(value) == "table" then
        local r, g, b = value.r or value.R, value.g or value.G, value.b or value.B
        if finite(r) and finite(g) and finite(b) then return r, g, b end
    end
    return nil
end

local function clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 end
    return x
end

local function colorToHex(value)
    local r, g, b = colorRGB(value)
    if not r then return nil end
    return string.format("#%02X%02X%02X",
        math.floor(clamp01(r) * 255 + 0.5), math.floor(clamp01(g) * 255 + 0.5), math.floor(clamp01(b) * 255 + 0.5))
end

local function textureToWire(value)
    if type(value) == "number" and finite(value) then return string.format("%.0f", value) end
    if type(value) ~= "string" then return "" end
    value = trim(value)
    local id = value:match("^rbxassetid://(%d+)$") or value:match("[%?&]id=(%d+)") or value:match("^(%d+)$")
    if id then return id end
    if value:match("^rbxasset://[%w_/%.%-]+$") and not value:find("..", 1, true) then return value end
    return ""
end

local B64_STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_REV = {}
for i = 1, 64 do B64_REV[string.byte(B64_STD, i)] = i - 1 end

local function b64Encode(text, alphabet, pad)
    local out = {}
    for i = 1, #text, 3 do
        local a, b, c = string.byte(text, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local s = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
        local keep = (c and 4) or (b and 3) or 2
        for k = 1, keep do out[#out + 1] = string.sub(alphabet, s[k] + 1, s[k] + 1) end
        if pad then for _ = keep + 1, 4 do out[#out + 1] = "=" end end
    end
    return table.concat(out)
end

local function b64DecodeStd(text)
    text = string.gsub(text, "[^%w%+/]", "")
    if #text % 4 == 1 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local n, count = 0, 0
        for k = 0, 3 do
            local byte = string.byte(text, i + k)
            if byte then
                n = n * 64 + B64_REV[byte]
                count = count + 1
            else
                n = n * 64
            end
        end
        local b1, b2, b3 = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = (count == 4 and string.char(b1, b2, b3)) or (count == 3 and string.char(b1, b2)) or string.char(b1)
    end
    return table.concat(out)
end

local function decodeJoevanPayload(payload)
    if crypt and crypt.base64decode then
        local ok, res = pcall(crypt.base64decode, payload)
        if ok and type(res) == "string" and res ~= "" then return res end
    end
    return b64DecodeStd(payload)
end

SharePreset.b64Encode = b64Encode
SharePreset.b64DecodeStd = b64DecodeStd

function SharePreset.IsJoevanCode(code)
    return string.sub(trim(code), 1, #SharePreset.JOEVAN_PREFIX) == SharePreset.JOEVAN_PREFIX
end

function SharePreset.DecodeJoevan(code)
    code = string.gsub(trim(code), "%s+", "")
    if #code > SharePreset.MAX_CODE_LENGTH then return nil, "The code is too long." end
    if string.sub(code, 1, #SharePreset.JOEVAN_PREFIX) ~= SharePreset.JOEVAN_PREFIX then
        return nil, "That is not a JoevanShader preset code."
    end
    local damaged = "The JoevanShader code is damaged. Copy it again."
    local json = decodeJoevanPayload(string.sub(code, #SharePreset.JOEVAN_PREFIX + 1))
    if not json or json == "" then return nil, damaged end
    local ok, state = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(state) ~= "table" then return nil, damaged end
    return state
end

function SharePreset.JoevanToData(state)
    local layout = LightingModule.PresetCodeLayout or {}
    local allowed = {}
    for _, spec in ipairs(layout) do
        allowed[spec[1]] = allowed[spec[1]] or {}
        allowed[spec[1]][spec[2]] = spec[3]
    end

    local values = {}
    for _, cat in ipairs(CATEGORIES) do
        local src = state[cat]
        if type(src) == "table" and allowed[cat] then
            for prop, kind in pairs(allowed[cat]) do
                local v = src[prop]
                if (kind == "c" and colorRGB(v)) or (kind == "n" and finite(v)) or (kind == "b" and type(v) == "boolean") then
                    values[cat] = values[cat] or {}
                    values[cat][prop] = v
                end
            end
        end
    end

    for _, cat in ipairs(POST_EFFECTS) do
        values[cat] = values[cat] or {}
        if values[cat].Enabled == nil then
            if cat == "Bloom" and type(state.BloomEnabled) == "boolean" then
                values[cat].Enabled = state.BloomEnabled
            elseif cat == "SunRays" and type(state.SunRaysEnabled) == "boolean" then
                values[cat].Enabled = state.SunRaysEnabled
            else
                values[cat].Enabled = next(values[cat]) ~= nil
            end
        end
    end
    if values.Lighting == nil and type(state.GlobalShadows) == "boolean" then
        values.Lighting = { GlobalShadows = state.GlobalShadows }
    end
    values.Blur = values.Blur or { Enabled = false }

    if not values.Clouds then
        local ci = tonumber(state.CloudsIntensity)
        if ci and ci > 0 then
            values.Clouds = { Enabled = true, Cover = clamp01(ci / 100 * 0.8), Density = clamp01(ci / 100 * 1.5) }
        else
            values.Clouds = { Enabled = false }
        end
    end

    local sky = nil
    local skyName = state.ActiveSkyboxName
    local skyData = state.ActiveSkyboxData
    if type(skyData) == "table" and skyName ~= "Default" then
        sky = {}
        for _, spec in ipairs(WIRE_SKY) do
            local field = spec[1]
            local v = skyData[field]
            if v == nil and SKY_SHORT[field] then v = skyData[SKY_SHORT[field]] end
            if v ~= nil then sky[field] = v end
        end
        if next(sky) == nil then sky = nil end
    end
    return values, sky
end

function SharePreset.DataToWire(name, values, sky)
    local layout = LightingModule.PresetCodeLayout or {}
    local wireValues = {}
    for index, spec in ipairs(layout) do
        local v = values[spec[1]] and values[spec[1]][spec[2]]
        local encoded = ""
        if spec[3] == "c" then
            encoded = colorToHex(v) or ""
        elseif spec[3] == "n" and finite(v) then
            encoded = round(v)
        elseif spec[3] == "b" and type(v) == "boolean" then
            encoded = v
        end
        wireValues[index] = encoded
    end

    local wireSky = 0
    if sky then
        wireSky = {}
        for index, spec in ipairs(WIRE_SKY) do
            local v = sky[spec[1]]
            local encoded = ""
            if spec[2] == "t" then
                encoded = textureToWire(v)
            elseif spec[2] == "n" and finite(v) then
                encoded = round(v)
            elseif spec[2] == "b" and type(v) == "boolean" then
                encoded = v
            end
            wireSky[index] = encoded
        end
    end

    local json = HttpService:JSONEncode({ tostring(name or ""), wireValues, wireSky })
    return MWL_PREFIX .. b64Encode(json, B64_URL, false)
end

function SharePreset.JoevanToMugiwaraCode(code, name)
    if LightingModule.PresetCodePrefix ~= MWL_PREFIX or type(LightingModule.PresetCodeLayout) ~= "table" then
        return nil, "This hub version uses a newer preset code format."
    end
    local state, message = SharePreset.DecodeJoevan(code)
    if not state then return nil, message end
    local values, sky = SharePreset.JoevanToData(state)
    local presetName = name
    if type(presetName) ~= "string" or presetName == "" then
        presetName = type(state.Name) == "string" and state.Name or "Joevan Preset"
    end
    return SharePreset.DataToWire(presetName, values, sky)
end

function SharePreset.Import(code)
    code = trim(code)
    if SharePreset.IsJoevanCode(code) then
        local wire, message = SharePreset.JoevanToMugiwaraCode(code)
        if not wire then return false, message end
        return LightingModule.ImportPreset(wire)
    end
    return LightingModule.ImportPreset(code)
end

function SharePreset.ExportJoevan(presetName)
    local data, message = LightingModule.GetPresetData(presetName)
    if not data then return nil, message or "Preset not found." end

    local state = { Name = tostring(presetName), _source = "Mugiwara", _savedAt = os.time() }
    for _, cat in ipairs(CATEGORIES) do
        local src = data.Values and data.Values[cat]
        if type(src) == "table" then
            local out = {}
            for prop, v in pairs(src) do
                local r, g, b = colorRGB(v)
                if r then
                    out[prop] = { r = r, g = g, b = b, isColor3 = true }
                elseif finite(v) or type(v) == "boolean" then
                    out[prop] = v
                end
            end
            state[cat] = out
        end
    end
    if state.Bloom and state.Bloom.Enabled ~= nil then state.BloomEnabled = state.Bloom.Enabled end
    if state.SunRays and state.SunRays.Enabled ~= nil then state.SunRaysEnabled = state.SunRays.Enabled end
    if state.Lighting and state.Lighting.GlobalShadows ~= nil then state.GlobalShadows = state.Lighting.GlobalShadows end
    if state.Clouds and state.Clouds.Enabled and finite(state.Clouds.Cover) then
        state.CloudsIntensity = math.floor(clamp01(state.Clouds.Cover / 0.8) * 100 + 0.5)
    end

    state.ActiveSkyboxName = "Default"
    if type(data.Sky) == "table" and data.SkyName ~= "Default Sky" then
        local skyData = {}
        for _, spec in ipairs(WIRE_SKY) do
            local v = data.Sky[spec[1]]
            if spec[2] == "t" then
                local wire = textureToWire(v)
                if wire:match("^%d+$") then
                    skyData[spec[1]] = "rbxassetid://" .. wire
                elseif wire ~= "" then
                    skyData[spec[1]] = wire
                end
            elseif (spec[2] == "n" and finite(v)) or (spec[2] == "b" and type(v) == "boolean") then
                skyData[spec[1]] = v
            end
        end
        if skyData.SkyboxBk then
            state.ActiveSkyboxName = data.SkyName or "Mugiwara Sky"
            state.ActiveSkyboxData = skyData
        end
    end

    local ok, json = pcall(function() return HttpService:JSONEncode(state) end)
    if not ok then return nil, "Could not make a code for this preset." end
    return SharePreset.JOEVAN_PREFIX .. b64Encode(json, B64_STD, true)
end

return SharePreset
