local PlayerPath = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer

-- Menggambar jalur berjalan dari karakter kita ke pemain pilihan. Jalur dihitung oleh PathfindingService
-- (navmesh milik game), jadi selalu lewat tempat yang bisa dilalui dan tidak menembus tembok. Kalau tidak ada
-- jalur, tidak ada garis yang digambar (tidak pernah garis lurus menembus dinding). Murni tampilan di client.
-- UI-nya ada di Tabs/EspInjector.lua; di sini hanya logika.

PlayerPath.Settings = {
    Color = Color3.fromRGB(0, 170, 255),
    Thickness = 0.3,        -- tebal garis (studs)
    ThroughWalls = true,    -- garis terlihat menembus tembok (tampilan saja; jalurnya tetap lewat jalan yang benar)
    AgentRadius = 2,
    AgentHeight = 5,
    AllowJump = true,       -- jalur boleh melewati lompatan
}

-- Dipasang oleh UI: dipanggil dengan teks saat status berubah (mis. tidak ada jalur). nil saat jalur normal.
PlayerPath.OnStatus = nil

local RECOMPUTE_INTERVAL = 0.5
local LIFT = 0.6            -- garis diangkat sedikit dari lantai supaya tidak tenggelam

local enabled = false
local target = nil          -- Player yang dituju
local computing = false
local lastStatus = nil
local pathLength = nil
local connection
local folder, anchor
local segments = {}         -- BoxHandleAdornment yang dipakai ulang

-- ---------- Gambar ----------

local function EnsureFolder()
    if folder and folder.Parent then return true end
    local camera = Workspace.CurrentCamera
    if not camera then return false end

    folder = Instance.new("Folder")
    folder.Name = "MugiwaraPlayerPath"

    -- Adornment butuh Adornee; satu Part tak terlihat di titik 0 jadi acuan semuanya.
    anchor = Instance.new("Part")
    anchor.Name = "Anchor"
    anchor.Anchored = true
    anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = CFrame.new()
    anchor.Parent = folder

    folder.Parent = camera
    table.clear(segments)
    return true
end

local function Clear()
    for _, segment in ipairs(segments) do segment.Visible = false end
    pathLength = nil
end

local function Draw(points)
    if not EnsureFolder() then return end
    local settings = PlayerPath.Settings

    local count = #points - 1
    for index = 1, count do
        local segment = segments[index]
        if not segment then
            segment = Instance.new("BoxHandleAdornment")
            segment.Adornee = anchor
            segment.Transparency = 0.15
            segment.Parent = folder
            segments[index] = segment
        end
        local from, to = points[index], points[index + 1]
        local length = (to - from).Magnitude
        segment.Size = Vector3.new(settings.Thickness, settings.Thickness, math.max(length, 0.01))
        segment.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
        segment.Color3 = settings.Color
        segment.AlwaysOnTop = settings.ThroughWalls
        segment.Visible = true
    end
    for index = count + 1, #segments do segments[index].Visible = false end
end

-- ---------- Status ----------

local function SetStatus(text)
    if text == lastStatus then return end
    lastStatus = text
    if PlayerPath.OnStatus then pcall(PlayerPath.OnStatus, text) end
end

-- ---------- Hitung jalur ----------

local function RootOf(player)
    local character = player and player.Character
    return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart), character
end

-- Titik lantai tepat di bawah `position` (navmesh butuh titik di permukaan, bukan di udara).
local function GroundPosition(position, ignore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local result = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -200, 0), params)
    return result and result.Position or position
end

local function Compute()
    if not enabled then return end
    if not target or target.Parent ~= Players then
        target = nil
        Clear()
        SetStatus("The selected player left the game.")
        return
    end

    local myRoot, myCharacter = RootOf(LocalPlayer)
    local targetRoot, targetCharacter = RootOf(target)
    if not myRoot or not targetRoot then
        Clear()
        SetStatus("Waiting for both characters to spawn.")
        return
    end

    local ignore = { myCharacter, targetCharacter }
    if folder then table.insert(ignore, folder) end
    local startPoint = GroundPosition(myRoot.Position, ignore)
    local endPoint = GroundPosition(targetRoot.Position, ignore)

    local settings = PlayerPath.Settings
    local path = PathfindingService:CreatePath({
        AgentRadius = settings.AgentRadius,
        AgentHeight = settings.AgentHeight,
        AgentCanJump = settings.AllowJump,
        WaypointSpacing = 4,
    })
    local ok = pcall(path.ComputeAsync, path, startPoint, endPoint)

    -- ComputeAsync menunggu; pastikan pilihan belum berubah selagi menunggu.
    if not enabled or not target then return end

    if not ok or path.Status ~= Enum.PathStatus.Success then
        Clear()
        SetStatus("No walkable path to " .. target.DisplayName .. " right now.")
        return
    end

    local points = {}
    local length = 0
    for _, waypoint in ipairs(path:GetWaypoints()) do
        local point = waypoint.Position + Vector3.new(0, LIFT, 0)
        if #points > 0 then length = length + (point - points[#points]).Magnitude end
        table.insert(points, point)
    end
    if #points < 2 then
        Clear()
        SetStatus(nil)
        return
    end

    pathLength = length
    Draw(points)
    SetStatus(nil)
end

-- ---------- Pengaturan ----------

function PlayerPath.GetLength()
    return pathLength
end

-- Pemain yang dituju (nama pemain, atau nil untuk melepas). Mengembalikan berhasil, pesan.
function PlayerPath.SetTarget(name)
    if not name or name == "" then
        target = nil
        Clear()
        return true, "Target cleared."
    end
    local player = Players:FindFirstChild(name)
    if not player or player == LocalPlayer or not player:IsA("Player") then
        return false, "Player not found or has left the game."
    end
    target = player
    lastStatus = nil
    Clear()
    return true, "Path target: " .. player.DisplayName
end

function PlayerPath.GetPlayerList()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then table.insert(list, player.Name) end
    end
    table.sort(list)
    return list
end

-- Dipanggil saat tampilan berubah (warna, tebal, tembus tembok); jalurnya sendiri tidak dihitung ulang.
function PlayerPath.Refresh()
    local settings = PlayerPath.Settings
    for _, segment in ipairs(segments) do
        segment.Color3 = settings.Color
        segment.AlwaysOnTop = settings.ThroughWalls
        segment.Size = Vector3.new(settings.Thickness, settings.Thickness, segment.Size.Z)
    end
end

-- ---------- On / Off ----------

function PlayerPath.IsEnabled()
    return enabled
end

function PlayerPath.SetEnabled(state)
    state = state == true
    if state == enabled then return end
    enabled = state

    if enabled then
        lastStatus = nil
        local elapsed = RECOMPUTE_INTERVAL
        connection = RunService.Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if elapsed < RECOMPUTE_INTERVAL or computing then return end
            elapsed = 0
            computing = true
            task.spawn(function()
                local ok, err = pcall(Compute)
                computing = false
                if not ok then
                    warn("[Mugiwara HUB] Player Path error: " .. tostring(err))
                    PlayerPath.SetEnabled(false)
                end
            end)
        end)
    else
        if connection then connection:Disconnect() connection = nil end
        Clear()
        SetStatus(nil)
    end
end

function PlayerPath.Destroy()
    PlayerPath.SetEnabled(false)
    if folder then folder:Destroy() folder, anchor = nil, nil end
    table.clear(segments)
end

if getgenv().MugiwaraRegisterCleanup then
    getgenv().MugiwaraRegisterCleanup(PlayerPath.Destroy)
end

return PlayerPath
