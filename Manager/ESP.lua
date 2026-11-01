local ESP = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- ESP pemain: outline (Highlight) di sekeliling karakter pemain lain, plus label nama dan jarak di atas
-- kepala. Murni tampilan di client. UI-nya ada di Tabs/EspInjector.lua; di sini hanya logika.
--
-- Semua yang ada di Settings boleh diubah kapan saja; efeknya terasa di pembaruan berikutnya (maks 0,1 detik).

ESP.Settings = {
    OutlineColor = Color3.fromRGB(255, 85, 85),
    FillColor = Color3.fromRGB(255, 85, 85),
    FillOpacity = 0,        -- 0 = hanya outline, 1 = terisi penuh
    ThroughWalls = true,    -- terlihat menembus tembok
    ShowNames = true,
    ShowDistance = true,
    MaxDistance = 5000,     -- studs; pemain yang lebih jauh tidak digambar
}

local UPDATE_INTERVAL = 0.1

local enabled = false
local tracked = {}          -- [player] = { Character, Highlight, Billboard, Label }
local connections = {}      -- koneksi global (PlayerAdded / PlayerRemoving / Heartbeat)
local playerConnections = {} -- [player] = koneksi karakter pemain itu

-- ---------- Gaya ----------

local function ApplyStyle(entry)
    local settings = ESP.Settings
    local highlight = entry.Highlight
    highlight.OutlineColor = settings.OutlineColor
    highlight.FillColor = settings.FillColor
    highlight.FillTransparency = 1 - math.clamp(settings.FillOpacity, 0, 1)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = settings.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    if entry.Label then
        entry.Label.TextColor3 = settings.OutlineColor
        entry.Billboard.AlwaysOnTop = settings.ThroughWalls
    end
end

local function CreateBillboard(entry, anchor)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "MugiwaraESPLabel"
    billboard.Adornee = anchor
    billboard.Size = UDim2.fromOffset(200, 36)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Active = false
    billboard.ResetOnSpawn = false

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextStrokeTransparency = 0.4
    label.TextWrapped = true
    label.Parent = billboard

    billboard.Parent = anchor
    entry.Billboard = billboard
    entry.Label = label
end

-- ---------- Pemain ----------

local function Detach(player)
    local entry = tracked[player]
    if not entry then return end
    tracked[player] = nil
    if entry.Highlight then entry.Highlight:Destroy() end
    if entry.Billboard then entry.Billboard:Destroy() end
end

local function Attach(player, character)
    Detach(player)

    local highlight = Instance.new("Highlight")
    highlight.Name = "MugiwaraESP"
    highlight.Adornee = character
    highlight.Parent = character

    local entry = { Character = character, Highlight = highlight }
    tracked[player] = entry
    ApplyStyle(entry)

    -- Label menempel di kepala; tunggu karakternya selesai dimuat tanpa menahan yang lain.
    task.spawn(function()
        local anchor = character:WaitForChild("Head", 5) or character:WaitForChild("HumanoidRootPart", 5)
        if not anchor or tracked[player] ~= entry then return end
        CreateBillboard(entry, anchor)
        ApplyStyle(entry)
    end)
end

local function Track(player)
    if player == LocalPlayer or playerConnections[player] then return end
    playerConnections[player] = {
        player.CharacterAdded:Connect(function(character) Attach(player, character) end),
        player.CharacterRemoving:Connect(function() Detach(player) end),
    }
    if player.Character then Attach(player, player.Character) end
end

local function Untrack(player)
    Detach(player)
    local list = playerConnections[player]
    if list then
        for _, connection in ipairs(list) do connection:Disconnect() end
        playerConnections[player] = nil
    end
end

-- ---------- Pembaruan ----------

local function OriginPosition()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then return root.Position end
    local camera = Workspace.CurrentCamera
    return camera and camera.CFrame.Position or nil
end

local function Update()
    local origin = OriginPosition()
    if not origin then return end
    local settings = ESP.Settings

    for player, entry in pairs(tracked) do
        local character = entry.Character
        local root = character.Parent and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not root then
            -- Karakter hilang tanpa CharacterRemoving (dihapus game): bersihkan.
            if not character.Parent then Detach(player) end
        else
            local distance = (root.Position - origin).Magnitude
            local visible = distance <= settings.MaxDistance
            entry.Highlight.Enabled = visible

            if entry.Billboard then
                local text
                if settings.ShowNames then text = player.DisplayName end
                if settings.ShowDistance then
                    local part = string.format("[%d studs]", math.floor(distance + 0.5))
                    text = text and (text .. "\n" .. part) or part
                end
                entry.Billboard.Enabled = visible and text ~= nil
                if text then entry.Label.Text = text end
            end
        end
    end
end

-- Dipanggil saat pengaturan tampilan berubah, supaya perubahan langsung terlihat.
function ESP.Refresh()
    if not enabled then return end
    for _, entry in pairs(tracked) do ApplyStyle(entry) end
    Update()
end

-- ---------- On / Off ----------

function ESP.IsEnabled()
    return enabled
end

function ESP.SetEnabled(state)
    state = state == true
    if state == enabled then return end
    enabled = state

    if enabled then
        for _, player in ipairs(Players:GetPlayers()) do Track(player) end
        table.insert(connections, Players.PlayerAdded:Connect(Track))
        table.insert(connections, Players.PlayerRemoving:Connect(Untrack))

        local elapsed = 0
        table.insert(connections, RunService.Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if elapsed < UPDATE_INTERVAL then return end
            elapsed = 0
            local ok, err = pcall(Update)
            if not ok then
                warn("[Mugiwara HUB] ESP error: " .. tostring(err))
                ESP.SetEnabled(false)
            end
        end))
        Update()
    else
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        for player in pairs(playerConnections) do Untrack(player) end
        for player in pairs(tracked) do Detach(player) end
    end
end

function ESP.Destroy()
    ESP.SetEnabled(false)
end

if getgenv().MugiwaraRegisterCleanup then
    getgenv().MugiwaraRegisterCleanup(ESP.Destroy)
end

return ESP
