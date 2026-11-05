local PlayerPath = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer

-- Menggambar jalur berjalan dari karakter kita ke pemain pilihan. Murni tampilan di client.
-- UI-nya ada di Tabs/EspInjector.lua; di sini hanya logika.
--
-- Jalur dicari dua tahap, dan hasilnya tidak pernah garis lurus menembus dinding:
--   1. PathfindingService (navmesh game). Hasilnya DIPERIKSA dulu: ujungnya harus dekat target dan tiap ruas
--      tidak boleh membentur dinding. Navmesh sering mengembalikan jalur yang menempel ke tembok saat target
--      ada di tempat lebih tinggi atau lewat tangga, jadi jalur seperti itu dibuang.
--   2. Kalau tahap 1 gagal / tidak lolos: pencarian sendiri (A*) di atas permukaan yang bisa diinjak. Dari
--      posisi kita, tiap langkah hanya ke permukaan yang naik sedikit demi sedikit (anak tangga, ledge) atau
--      turun, dengan ruang kepala cukup, tanpa dinding di antaranya, dan titik yang menempel ke dinding diberi
--      biaya lebih sehingga jalur memilih permukaan yang lapang.

PlayerPath.Settings = {
    Color = Color3.fromRGB(0, 170, 255),
    Thickness = 0.5,        -- lebar garis (studs)
    ThroughWalls = true,    -- garis terlihat menembus tembok (tampilan saja; jalurnya tetap lewat jalan yang benar)
    AgentRadius = 2,
    AgentHeight = 5,
    AllowJump = true,       -- jalur boleh melewati lompatan
}

-- Dipasang oleh UI: dipanggil dengan teks saat status berubah (mis. tidak ada jalur). nil saat jalur normal.
PlayerPath.OnStatus = nil

local CHECK_INTERVAL = 0.5      -- seberapa sering syarat hitung ulang dicek
local RECOMPUTE_MOVE = 4        -- hitung ulang kalau kita / target bergeser sejauh ini (studs)
local RECOMPUTE_MAX_AGE = 3     -- ...atau kalau jalur sudah setua ini (detik)
local RETRY_AFTER_FAIL = 1.5    -- jeda sebelum mencoba lagi sesudah tidak ada jalur
local LIFT = 0.6                -- garis diangkat sedikit dari lantai supaya tidak tenggelam

-- Pencarian sendiri (tahap 2)
local CELL = 3                  -- jarak antar titik (studs)
local STEP_UP = 2.6             -- naik setinggi ini dianggap melangkah (tangga)
local JUMP_UP = 4               -- naik setinggi ini harus melompat (kalau Allow Jumps); lebih tinggi dari ini harus lewat tangga
local MAX_DROP = 10             -- turun sejauh ini masih dianggap jalan
local CLEAR_BOTTOM = 1.2        -- ruang kepala dicek mulai setinggi ini di atas lantai (tangga di samping tidak dihitung)
local CLEAR_RADIUS = 1.2
local MAX_NODES = 3500
local EXPAND_PER_YIELD = 120    -- tiap sekian titik, beri jeda satu frame supaya game tidak patah

local enabled = false
local target = nil          -- Player yang dituju
local computing = false
local generation = 0        -- naik tiap target / on-off berubah, supaya hitungan lama berhenti sendiri
local lastStatus = nil
local pathLength = nil
local connection
local folder
local beams, attachments = {}, {} -- Beam dan Attachment yang dipakai ulang (rantai: beam i = titik i ke titik i+1)
local lastStart, lastEnd, lastTime, lastFailed = nil, nil, 0, false

-- ---------- Gambar ----------

local function EnsureFolder()
    if folder and folder.Parent then return true end
    local camera = Workspace.CurrentCamera
    if not camera then return false end

    folder = Instance.new("Folder")
    folder.Name = "MugiwaraPlayerPath"

    -- Beam-nya ada di folder ini; Attachment-nya ditaruh di Terrain (induk standar untuk Attachment tanpa Part).
    folder.Parent = camera
    table.clear(beams)
    return true
end

local function StyleBeam(beam)
    local settings = PlayerPath.Settings
    beam.Color = ColorSequence.new(settings.Color)
    beam.Width0, beam.Width1 = settings.Thickness, settings.Thickness
    -- Beam selalu diuji kedalamannya (tidak ada "selalu di atas"), jadi garisnya tersembunyi di balik tembok.
    -- ZOffset kecil hanya mencegah garis berkedip di lantai yang sama tinggi.
    beam.ZOffset = 0.5
end

local function Clear()
    for _, beam in ipairs(beams) do beam.Enabled = false end
    pathLength = nil
end

local function Draw(points)
    if not EnsureFolder() then return end

    for index, point in ipairs(points) do
        local attachment = attachments[index]
        if not attachment or not attachment.Parent then
            attachment = Instance.new("Attachment")
            attachment.Name = "MugiwaraPathPoint"
            attachment.Parent = Workspace.Terrain
            attachments[index] = attachment
        end
        attachment.WorldPosition = point
    end

    local count = #points - 1
    for index = 1, count do
        local beam = beams[index]
        if not beam then
            beam = Instance.new("Beam")
            beam.FaceCamera = true      -- pita datar yang selalu menghadap kamera
            beam.LightEmission = 1
            beam.LightInfluence = 0
            beam.Segments = 1
            beam.Transparency = NumberSequence.new(0.1)
            beam.Parent = folder
            beams[index] = beam
        end
        beam.Attachment0 = attachments[index]
        beam.Attachment1 = attachments[index + 1]
        StyleBeam(beam)
        beam.Enabled = true
    end
    for index = count + 1, #beams do beams[index].Enabled = false end
end

-- ---------- Status ----------

local function SetStatus(text)
    if text == lastStatus then return end
    lastStatus = text
    if PlayerPath.OnStatus then pcall(PlayerPath.OnStatus, text) end
end

-- ---------- Dunia ----------

local function RootOf(player)
    local character = player and player.Character
    return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart), character
end

-- Yang diabaikan saat menembak ray: semua karakter pemain, rig visual Evade (Workspace.Rigs), dan kamera
-- (di situ garis jalur kita digambar).
local function BuildIgnore()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(list, player.Character) end
    end
    local rigs = Workspace:FindFirstChild("Rigs")
    if rigs then table.insert(list, rigs) end
    if Workspace.CurrentCamera then table.insert(list, Workspace.CurrentCamera) end
    return list
end

local function MakeRayParams(ignore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.RespectCanCollide = true -- part tembus (dekorasi, pemicu) tidak dianggap lantai atau dinding
    return params
end

-- Titik lantai tepat di bawah `position` (navmesh butuh titik di permukaan, bukan di udara).
local function GroundPosition(position, params)
    local result = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -300, 0), params)
    return result and result.Position or position
end

-- true kalau ada dinding di antara a dan b. Ray ditembakkan sedikit di atas lantai yang lebih tinggi dari
-- keduanya, jadi anak tangga rendah dan ledge kecil tidak dihitung dinding.
local function WallBetween(a, b, params)
    local top = math.max(a.Y, b.Y) + 1.6
    local from = Vector3.new(a.X, top, a.Z)
    local to = Vector3.new(b.X, top, b.Z)
    return Workspace:Raycast(from, to - from, params) ~= nil
end

-- true kalau garis a -> b menempel ke lantai: di tiap ~1,5 studs ada lantai yang tingginya hampir sama dengan
-- garis. Garis yang memotong ke atas lewat tangga, melayang di atas lubang tangga, atau menembus anak
-- tangga TIDAK lolos, jadi jalur seperti itu dibuang dan dicari ulang yang mengikuti anak tangga.
local function HugsGround(a, b, params)
    local distance = (b - a).Magnitude
    local samples = math.max(1, math.ceil(distance / 1.5))
    for index = 1, samples - 1 do
        local point = a:Lerp(b, index / samples)
        local hit = Workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -9, 0), params)
        if not hit or math.abs(hit.Position.Y - point.Y) > 1.8 then return false end
    end
    return true
end

-- Jalur digambar mengikuti lantai: tiap ~2,5 studs titiknya ditempelkan ke tinggi lantai sebenarnya, jadi di
-- tangga garisnya naik anak tangga demi anak tangga (berbelok mengikuti tangga), bukan lurus menanjak.
local function Conform(points, params)
    local result = {}
    for index = 1, #points - 1 do
        local a, b = points[index], points[index + 1]
        local pieces = math.max(1, math.ceil((b - a).Magnitude / 2.5))
        for piece = 0, pieces - 1 do
            local point = a:Lerp(b, piece / pieces)
            local hit = Workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -9, 0), params)
            if hit and math.abs(hit.Position.Y - point.Y) <= 2.5 then
                point = Vector3.new(point.X, hit.Position.Y, point.Z)
            end
            table.insert(result, point)
        end
    end
    table.insert(result, points[#points])
    return result
end

-- ---------- Tahap 1: PathfindingService ----------

local function NavmeshPath(startPoint, endPoint, params)
    local settings = PlayerPath.Settings
    local path = PathfindingService:CreatePath({
        AgentRadius = settings.AgentRadius,
        AgentHeight = settings.AgentHeight,
        AgentCanJump = settings.AllowJump,
        WaypointSpacing = 4,
    })
    local ok = pcall(path.ComputeAsync, path, startPoint, endPoint)
    if not ok or path.Status ~= Enum.PathStatus.Success then return nil end

    local points = {}
    for _, waypoint in ipairs(path:GetWaypoints()) do table.insert(points, waypoint.Position) end
    if #points < 2 then return nil end

    -- Ujung jalur harus benar-benar sampai di target, bukan berhenti di dinding terdekat.
    local last = points[#points]
    local flat = Vector3.new(last.X - endPoint.X, 0, last.Z - endPoint.Z).Magnitude
    if flat > 10 or math.abs(last.Y - endPoint.Y) > 10 then return nil end

    for index = 1, #points - 1 do
        if WallBetween(points[index], points[index + 1], params) or not HugsGround(points[index], points[index + 1], params) then return nil end
    end
    return points
end

-- ---------- Tahap 2: pencarian sendiri ----------

-- Antrian prioritas (min-heap) berdasarkan F.
local Heap = {}
Heap.__index = Heap
function Heap.new() return setmetatable({ items = {}, size = 0 }, Heap) end
function Heap:Push(node)
    self.size = self.size + 1
    local items, index = self.items, self.size
    items[index] = node
    while index > 1 do
        local parent = math.floor(index / 2)
        if items[parent].F <= items[index].F then break end
        items[parent], items[index] = items[index], items[parent]
        index = parent
    end
end
function Heap:Pop()
    local items = self.items
    local top = items[1]
    items[1] = items[self.size]
    items[self.size] = nil
    self.size = self.size - 1
    local index = 1
    while true do
        local left, right, smallest = index * 2, index * 2 + 1, index
        if left <= self.size and items[left].F < items[smallest].F then smallest = left end
        if right <= self.size and items[right].F < items[smallest].F then smallest = right end
        if smallest == index then break end
        items[smallest], items[index] = items[index], items[smallest]
        index = smallest
    end
    return top
end

local DIRECTIONS = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}
local CARDINALS = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }

-- Mengembalikan daftar titik, atau nil (tidak ada jalur / dibatalkan lewat `token`).
local function GridPath(startPoint, goalPoint, ignore, params, token)
    local settings = PlayerPath.Settings
    local maxUp = settings.AllowJump and JUMP_UP or STEP_UP
    local boxHeight = math.max(settings.AgentHeight - CLEAR_BOTTOM, 1)
    local boxSize = Vector3.new(CLEAR_RADIUS * 2, boxHeight, CLEAR_RADIUS * 2)
    local maxRange = (goalPoint - startPoint).Magnitude * 1.6 + 60

    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = ignore
    overlap.RespectCanCollide = true
    overlap.MaxParts = 1

    local nodes = {}
    local function KeyOf(pos)
        return string.format("%d,%d,%d",
            math.floor((pos.X - startPoint.X) / CELL + 0.5),
            math.floor((pos.Z - startPoint.Z) / CELL + 0.5),
            math.floor(pos.Y / 2 + 0.5))
    end

    -- Permukaan yang bisa diinjak di kolom (x, z): paling tinggi yang naiknya tidak lebih dari `maxUp` dari
    -- `fromY` dan turunnya tidak lebih dari MAX_DROP, dengan ruang kepala kosong. Ray dilanjutkan ke bawah
    -- melewati permukaan yang tidak cocok (mis. atas lantai di tingkat berikutnya), supaya lantai di
    -- bawahnya tetap ketemu.
    local function Probe(fromY, x, z)
        local y = fromY + maxUp
        local bottom = fromY - MAX_DROP
        for _ = 1, 4 do
            local hit = Workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, bottom - y, 0), params)
            if not hit then return nil end
            local pos = hit.Position
            if hit.Normal.Y >= 0.6 then
                local box = CFrame.new(pos + Vector3.new(0, CLEAR_BOTTOM + boxHeight / 2, 0))
                if #Workspace:GetPartBoundsInBox(box, boxSize, overlap) == 0 then return pos end
            end
            y = pos.Y - 0.1
            if y <= bottom then return nil end
        end
        return nil
    end

    -- Biaya tambahan untuk titik yang menempel ke dinding: jalur lebih suka permukaan yang lapang.
    local function WallPenalty(pos)
        local penalty = 0
        local origin = pos + Vector3.new(0, 2, 0)
        for _, direction in ipairs(CARDINALS) do
            if Workspace:Raycast(origin, direction * (CLEAR_RADIUS + 1.2), params) then penalty = penalty + 1.5 end
        end
        return penalty
    end

    local function Heuristic(pos)
        local dx, dz = pos.X - goalPoint.X, pos.Z - goalPoint.Z
        return (math.sqrt(dx * dx + dz * dz) + math.abs(pos.Y - goalPoint.Y) * 0.5) * 1.3
    end

    local startNode = { Pos = startPoint, G = 0, F = Heuristic(startPoint) }
    nodes[KeyOf(startPoint)] = startNode
    local open = Heap.new()
    open:Push(startNode)

    local expanded = 0
    while open.size > 0 and expanded < MAX_NODES do
        local current = open:Pop()
        if not current.Closed then
            current.Closed = true
            expanded = expanded + 1
            local pos = current.Pos

            local flat = Vector3.new(pos.X - goalPoint.X, 0, pos.Z - goalPoint.Z).Magnitude
            if flat <= CELL * 1.2 and math.abs(pos.Y - goalPoint.Y) <= 4 then
                local points = {}
                local node = current
                while node do
                    table.insert(points, 1, node.Pos)
                    node = node.Parent
                end
                return points
            end

            if expanded % EXPAND_PER_YIELD == 0 then
                task.wait()
                if token ~= generation or not enabled then return nil end
            end

            for _, direction in ipairs(DIRECTIONS) do
                local x, z = pos.X + direction[1] * CELL, pos.Z + direction[2] * CELL
                if math.sqrt((x - startPoint.X) ^ 2 + (z - startPoint.Z) ^ 2) <= maxRange then
                    local neighbour = Probe(pos.Y, x, z)
                    if neighbour then
                        local rise = neighbour.Y - pos.Y
                        -- Naik: tidak boleh ada langit-langit (lantai tingkat atas) di antara kita dan permukaan baru.
                        local blockedAbove = rise > 0.5 and Workspace:Raycast(pos + Vector3.new(0, 0.5, 0), Vector3.new(0, rise + 1.5, 0), params) ~= nil
                        if rise <= maxUp and rise >= -MAX_DROP and not blockedAbove and not WallBetween(pos, neighbour, params) then
                            local key = KeyOf(neighbour)
                            local known = nodes[key]
                            if not (known and known.Closed) then
                                local step = (direction[1] ~= 0 and direction[2] ~= 0) and CELL * 1.414 or CELL
                                local cost = step + math.abs(rise) * 0.5
                                if rise > STEP_UP then cost = cost + 12 end -- melompat jauh lebih mahal daripada memutar lewat tangga
                                if not known then cost = cost + WallPenalty(neighbour) end
                                local g = current.G + cost
                                if not known or g < known.G then
                                    local node = known or { Pos = neighbour }
                                    node.G, node.F, node.Parent = g, g + Heuristic(neighbour), current
                                    nodes[key] = node
                                    open:Push(node)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Titik yang searah (lurus, ketinggian sama) digabung supaya garis tidak terdiri dari ratusan ruas kecil.
local function Simplify(points)
    if #points < 3 then return points end
    local result = { points[1] }
    for index = 2, #points - 1 do
        local a, b, c = result[#result], points[index], points[index + 1]
        local d1, d2 = b - a, c - b
        local straight = d1.Magnitude > 0 and d2.Magnitude > 0
            and d1.Unit:Dot(d2.Unit) > 0.999 and math.abs(d1.Y) < 0.05 and math.abs(d2.Y) < 0.05
        if not straight then table.insert(result, b) end
    end
    table.insert(result, points[#points])
    return result
end

-- ---------- Hitung jalur ----------

local function Compute(token)
    if not enabled then return end
    if not target then
        Clear()
        return
    end
    if target.Parent ~= Players then
        target = nil
        Clear()
        SetStatus("The selected player left the game.")
        return
    end

    local myRoot = RootOf(LocalPlayer)
    local targetRoot = RootOf(target)
    if not myRoot or not targetRoot then
        Clear()
        SetStatus("Waiting for both characters to spawn.")
        return
    end

    local ignore = BuildIgnore()
    local params = MakeRayParams(ignore)
    local startPoint = GroundPosition(myRoot.Position, params)
    local endPoint = GroundPosition(targetRoot.Position, params)

    local points = NavmeshPath(startPoint, endPoint, params)
    if token ~= generation or not enabled then return end
    if not points then
        points = GridPath(startPoint, endPoint, ignore, params, token)
        if token ~= generation or not enabled then return end
        if points then table.insert(points, endPoint) end
    end

    lastStart, lastEnd, lastTime = myRoot.Position, targetRoot.Position, os.clock()
    lastFailed = points == nil

    if not points then
        Clear()
        SetStatus("No walkable path to " .. target.DisplayName .. " right now.")
        return
    end

    points = Conform(Simplify(points), params)
    local lifted, length = {}, 0
    for index, point in ipairs(points) do
        lifted[index] = point + Vector3.new(0, LIFT, 0)
        if index > 1 then length = length + (point - points[index - 1]).Magnitude end
    end
    if #lifted < 2 then
        Clear()
        SetStatus(nil)
        return
    end

    pathLength = length
    Draw(lifted)
    SetStatus(nil)
end

-- Hitung ulang hanya kalau kita / target sudah bergeser, jalurnya sudah tua, atau percobaan sebelumnya gagal.
local function NeedsRecompute()
    local myRoot = RootOf(LocalPlayer)
    local targetRoot = RootOf(target)
    if not myRoot or not targetRoot then return true end
    if not lastStart then return true end
    local age = os.clock() - lastTime
    if lastFailed then return age >= RETRY_AFTER_FAIL end
    return (myRoot.Position - lastStart).Magnitude > RECOMPUTE_MOVE
        or (targetRoot.Position - lastEnd).Magnitude > RECOMPUTE_MOVE
        or age >= RECOMPUTE_MAX_AGE
end

local function Invalidate()
    generation = generation + 1
    lastStart, lastEnd = nil, nil
    lastFailed = false
end

-- ---------- Pengaturan ----------

function PlayerPath.GetLength()
    return pathLength
end

-- Pemain yang dituju (nama pemain, atau nil untuk melepas). Mengembalikan berhasil, pesan.
function PlayerPath.SetTarget(name)
    Invalidate()
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
    for _, beam in ipairs(beams) do StyleBeam(beam) end
end

-- Dipanggil saat pengaturan jalur berubah (mis. Allow Jumps): jalur dihitung ulang di pemeriksaan berikutnya.
function PlayerPath.Recompute()
    Invalidate()
end

-- ---------- On / Off ----------

function PlayerPath.IsEnabled()
    return enabled
end

function PlayerPath.SetEnabled(state)
    state = state == true
    if state == enabled then return end
    enabled = state
    Invalidate()

    if enabled then
        lastStatus = nil
        local elapsed = CHECK_INTERVAL
        connection = RunService.Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if elapsed < CHECK_INTERVAL or computing then return end
            elapsed = 0
            if not target or not NeedsRecompute() then return end
            local token = generation
            computing = true
            task.spawn(function()
                local ok, err = pcall(Compute, token)
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
    if folder then folder:Destroy() folder = nil end
    for _, attachment in ipairs(attachments) do attachment:Destroy() end
    table.clear(beams)
    table.clear(attachments)
end

if getgenv().MugiwaraRegisterCleanup then
    getgenv().MugiwaraRegisterCleanup(PlayerPath.Destroy)
end

return PlayerPath
