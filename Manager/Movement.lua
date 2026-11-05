local Movement = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

Movement.SpeedEnabled = false
Movement.SpeedValue = 16
Movement.OriginalSpeed = 16

Movement.TweenSpeedEnabled = false
Movement.TweenSpeedValue = 16

Movement.JumpEnabled = false
Movement.JumpValue = 50
Movement.OriginalJump = 50

Movement.InfJumpEnabled = false
Movement.InfJumpMax = 200

Movement.FlyEnabled = false
Movement.FlySpeed = 16

Movement.NoclipEnabled = false

local currentJumps = 0
local lastJumpTime = 0
local flyBodyVelocity = nil
local flyBodyGyro = nil

local connections = {}

local function UpdateOriginalStats(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        Movement.OriginalSpeed = humanoid.WalkSpeed
        Movement.OriginalJump = humanoid.JumpPower
    end
end

if LocalPlayer.Character then task.spawn(UpdateOriginalStats, LocalPlayer.Character) end

function Movement.RestoreSpeed()
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid").WalkSpeed = Movement.OriginalSpeed
    end
end

function Movement.RestoreJump()
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid").JumpPower = Movement.OriginalJump
    end
end

-- Posisi karakter sekarang (Vector3) atau nil kalau belum ada karakter.
function Movement.GetPosition()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    return root and root.Position or nil
end

-- "x, y, z" -> Vector3. Menerima koma/spasi/kurung, mis. "10 5 -3" atau "Vector3.new(10, 5, -3)".
function Movement.ParsePosition(text)
    local numbers = {}
    -- Buang kata (mis. "Vector3.new") dulu supaya angka di dalam namanya tidak terhitung.
    local cleaned = string.gsub(tostring(text or ""), "[%a_]+%d*", " ")
    for token in string.gmatch(cleaned, "[-+]?%d*%.?%d+") do
        table.insert(numbers, tonumber(token))
    end
    if #numbers ~= 3 then return nil end
    return Vector3.new(numbers[1], numbers[2], numbers[3])
end

-- Format yang sama dengan yang dibaca ParsePosition, jadi hasil salin bisa ditempel lagi untuk teleport.
function Movement.FormatPosition(position)
    return string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z)
end

-- Memindahkan karakter ke `position` dengan arah hadap tetap. Mengembalikan berhasil, pesan.
function Movement.TeleportTo(position)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false, "Your character is not ready yet." end

    local rotation = root.CFrame - root.CFrame.Position
    char:PivotTo(CFrame.new(position) * rotation)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true, "Teleported to " .. Movement.FormatPosition(position)
end

-- Nama semua pemain lain, urut abjad (untuk dropdown Teleport to Player).
function Movement.GetPlayerList()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then table.insert(list, player.Name) end
    end
    table.sort(list)
    return list
end

-- Pindah ke dekat pemain `name`: titik di atas posisinya supaya tidak menempel di badannya.
-- Mengembalikan berhasil, pesan.
function Movement.TeleportToPlayer(name)
    local player = name and Players:FindFirstChild(name)
    if not player or not player:IsA("Player") or player == LocalPlayer then
        return false, "Player not found or has left the game."
    end
    local character = player.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if not root then return false, player.DisplayName .. " has no character right now." end

    local ok, message = Movement.TeleportTo(root.Position + Vector3.new(0, 3, 0))
    if ok then message = "Teleported to " .. player.DisplayName end
    return ok, message
end

local function DestroyFlyObjects()
    if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
    if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
end

function Movement.ToggleFly(state)
    Movement.FlyEnabled = state
    -- Always remove old objects first so toggling ON repeatedly never stacks BodyVelocity.
    DestroyFlyObjects()
    if not state then return end

    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    local hrp = char.HumanoidRootPart

    do
        flyBodyVelocity = Instance.new("BodyVelocity")
        flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyBodyVelocity.Velocity = Vector3.zero
        flyBodyVelocity.Parent = hrp

        flyBodyGyro = Instance.new("BodyGyro")
        flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyBodyGyro.P = 9e4
        flyBodyGyro.CFrame = hrp.CFrame
        flyBodyGyro.Parent = hrp
    end
end

-- Respawn: fly objects die with the old character; recreate them if Fly is still ON.
table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(character)
    UpdateOriginalStats(character)
    flyBodyVelocity, flyBodyGyro = nil, nil
    if Movement.FlyEnabled then
        character:WaitForChild("HumanoidRootPart", 5)
        Movement.ToggleFly(true)
    end
end))

table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime)
    local character = LocalPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then return end

    if humanoid.FloorMaterial ~= Enum.Material.Air then
        currentJumps = 0
    end

    if Movement.SpeedEnabled then
        humanoid.WalkSpeed = Movement.SpeedValue
    end

    if Movement.TweenSpeedEnabled then
        if humanoid.MoveDirection.Magnitude > 0 then
            local extraSpeed = math.max(0, Movement.TweenSpeedValue - humanoid.WalkSpeed)
            local pushVector = humanoid.MoveDirection * extraSpeed * deltaTime
            rootPart.CFrame = rootPart.CFrame + pushVector
        end
    end

    if Movement.JumpEnabled then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = Movement.JumpValue
    end
end))

table.insert(connections, RunService.RenderStepped:Connect(function()
    if Movement.FlyEnabled and flyBodyVelocity and flyBodyGyro then
        local cam = workspace.CurrentCamera
        local moveDir = Vector3.zero

        -- Ignore key input while the user is typing in chat or a textbox.
        if not UserInputService:GetFocusedTextBox() then
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end
        end

        if moveDir.Magnitude == 0 and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            moveDir = LocalPlayer.Character.Humanoid.MoveDirection
        end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit
        end

        flyBodyVelocity.Velocity = moveDir * Movement.FlySpeed
        flyBodyGyro.CFrame = cam.CFrame
    end
end))

-- Noclip: SEMUA part karakter (Part, MeshPart, UnionOperation, aksesori) dimatikan tabrakannya, sehingga
-- tembok dari jenis object apa pun bisa ditembus. Game atau Humanoid sering menyalakan CanCollide lagi,
-- jadi dimatikan di tiga titik tiap frame (Stepped, PreSimulation, Heartbeat) dan langsung dimatikan lagi
-- kalau ada yang menyalakannya (sinyal CanCollide). Nilai asli dicatat dan dikembalikan saat noclip mati.
local noclipOriginal = setmetatable({}, { __mode = "k" }) -- part -> CanCollide asli
local noclipHooked = setmetatable({}, { __mode = "k" })    -- part -> koneksi sinyal CanCollide
local noclipWasOn = false

local function DisableCollision(part)
    if noclipOriginal[part] == nil then noclipOriginal[part] = part.CanCollide end
    if part.CanCollide then part.CanCollide = false end
    if not noclipHooked[part] then
        noclipHooked[part] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if Movement.NoclipEnabled and part.CanCollide then part.CanCollide = false end
        end)
    end
end

local function ApplyNoclip()
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then DisableCollision(part) end
    end
end

local function RestoreNoclip()
    for part, connection in pairs(noclipHooked) do
        connection:Disconnect()
        noclipHooked[part] = nil
    end
    for part, original in pairs(noclipOriginal) do
        if part.Parent then pcall(function() part.CanCollide = original end) end
        noclipOriginal[part] = nil
    end
end

local function NoclipStep()
    if Movement.NoclipEnabled then
        noclipWasOn = true
        ApplyNoclip()
    elseif noclipWasOn then
        noclipWasOn = false
        RestoreNoclip()
    end
end

table.insert(connections, RunService.Stepped:Connect(NoclipStep))
table.insert(connections, RunService.Heartbeat:Connect(NoclipStep))
pcall(function() table.insert(connections, RunService.PreSimulation:Connect(NoclipStep)) end)

table.insert(connections, UserInputService.JumpRequest:Connect(function()
    if Movement.InfJumpEnabled then
        local character = LocalPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                if tick() - lastJumpTime > 0.2 then
                    if Movement.InfJumpMax >= 200 or currentJumps < Movement.InfJumpMax then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        currentJumps = currentJumps + 1
                        lastJumpTime = tick()
                    end
                end
            end
        end
    end
end))

-- Animation speed: kecepatan dipasang ulang tiap frame ke SEMUA animasi yang sedang jalan,
-- karena track baru (ganti state jalan/lompat) selalu mulai di speed 1 dan skrip animasi game
-- bisa menimpa speed-nya. Targetnya karakter asli plus rig visual di Workspace.Rigs (Evade).
Movement.AnimSpeedEnabled = false
Movement.AnimSpeedValue = 1

local function ForEachAnimator(callback)
    local function visit(model)
        if not model then return end
        local animator = model:FindFirstChildWhichIsA("Animator", true)
        if animator then callback(animator) end
    end

    visit(LocalPlayer.Character)

    local rigs = workspace:FindFirstChild("Rigs")
    if rigs then
        for _, child in ipairs(rigs:GetChildren()) do
            if child:IsA("Model") and child.Name == LocalPlayer.Name then visit(child) end
        end
    end
end

-- Mengembalikan jumlah animasi yang sedang jalan di semua animator target.
local function ApplyAnimSpeed(speed)
    local count = 0
    ForEachAnimator(function(animator)
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            count = count + 1
            if track.Speed ~= speed then track:AdjustSpeed(speed) end
        end
    end)
    return count
end

-- PreAnimation jalan tepat sebelum animasi dihitung tiap frame, jadi nilai kita yang dipakai.
-- Kalau event itu tidak ada di executor/versi Roblox ini, pakai Heartbeat.
local animationEvent = RunService.Heartbeat
pcall(function() animationEvent = RunService.PreAnimation end)

table.insert(connections, animationEvent:Connect(function()
    if not Movement.AnimSpeedEnabled then return end
    pcall(ApplyAnimSpeed, Movement.AnimSpeedValue)
end))

function Movement.SetAnimSpeed(value)
    if type(value) ~= "number" or value < 0 then return end

    Movement.AnimSpeedValue = value
    Movement.AnimSpeedEnabled = value ~= 1

    -- Langsung diterapkan sekali (loop di atas yang menjaganya sesudah itu). Nilai 1 = kembali
    -- normal: loop berhenti dan animasi yang sedang jalan dikembalikan ke speed 1.
    local ok, count = pcall(ApplyAnimSpeed, value)
    if ok then
        print("[Mugiwara] Animation speed " .. tostring(value) .. " (" .. tostring(count) .. " animations playing)")
    else
        warn("[Mugiwara] Animation speed failed: " .. tostring(count))
    end
end

-- Full teardown on re-execute: stop every loop, release fly, restore speed/jump/animation.
getgenv().MugiwaraRegisterCleanup(function()
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    table.clear(connections)
    Movement.FlyEnabled = false
    DestroyFlyObjects()
    if Movement.SpeedEnabled then Movement.RestoreSpeed() end
    if Movement.JumpEnabled then Movement.RestoreJump() end
    if Movement.AnimSpeedEnabled then pcall(ApplyAnimSpeed, 1) end
    Movement.NoclipEnabled = false
    RestoreNoclip()
    Movement.SpeedEnabled, Movement.TweenSpeedEnabled = false, false
    Movement.JumpEnabled, Movement.InfJumpEnabled, Movement.NoclipEnabled = false, false, false
    Movement.AnimSpeedEnabled = false
end)

return Movement
