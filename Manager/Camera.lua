local CameraModule = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

CameraModule.FreecamEnabled = false
CameraModule.FreecamSpeed = 16

-- Putar kamera bebas. Dasarnya sama dengan kamera bawaan Roblox: mouse 0.5 derajat per pixel (vertikal sedikit lebih
-- pelan, 0.77x) dikali Camera Sensitivity dari setting Roblox, panah 40 derajat per detik (sengaja jauh lebih pelan dari Roblox, 120). Kecepatan arah kiri/kanan
-- dan atas/bawah adalah pengali tambahan yang berlaku untuk mouse (klik kanan) maupun panah.
CameraModule.UseRobloxSensitivity = true -- true: ikut setting Roblox, false: pakai MouseSensitivity di bawah
CameraModule.MouseSensitivity = 1        -- 1 = sensitivitas Roblox bawaan
CameraModule.HorizontalSpeed = 1         -- pengali putar kiri/kanan
CameraModule.VerticalSpeed = 1           -- pengali putar atas/bawah

local MOUSE_DEGREES_PER_PIXEL = 0.5
local MOUSE_VERTICAL_RATIO = 0.77
local ARROW_DEGREES_PER_SECOND = 40

-- Smooth Mouse: menyaring putaran kamera (Free Camera maupun kamera biasa) supaya gerakan tangan yang tidak rata /
-- tremor tidak sampai ke kamera.
--   "Smooth"   : putaran mouse dikumpulkan lalu dilepas sedikit demi sedikit tiap frame (getaran kecil saling hilang).
--   "Constant" : yang diambil hanya ARAH gerakan; kamera berputar dengan kecepatan tetap seperti tombol panah.
--                Gerakan di bawah Deadzone diabaikan (tremor tidak memutar kamera sama sekali).
CameraModule.SmoothMouseEnabled = false
CameraModule.SmoothMouseMode = "Smooth"   -- "Smooth" | "Constant"
CameraModule.SmoothMouseSmoothness = 0.5  -- 0 = hampir langsung, 1 = sangat halus (mode Smooth)
CameraModule.SmoothMouseSpeed = 60        -- derajat per detik (mode Constant)
CameraModule.SmoothMouseDeadzone = 20     -- derajat per detik; gerakan lebih pelan dari ini diabaikan (mode Constant)
CameraModule.SmoothMouseModes = { "Smooth", "Constant" }

local CONSTANT_RESPONSE = 0.08 -- detik; perataan kecepatan mouse supaya celah antar polling mouse tidak membuat putaran tersendat

local lookFilter = { PendingYaw = 0, PendingPitch = 0, VelYaw = 0, VelPitch = 0 }

function CameraModule.ResetSmoothMouse()
    lookFilter.PendingYaw, lookFilter.PendingPitch, lookFilter.VelYaw, lookFilter.VelPitch = 0, 0, 0, 0
end

local function ConstantAxis(velocity, deltaTime)
    if math.abs(velocity) <= CameraModule.SmoothMouseDeadzone then return 0 end
    return (velocity > 0 and 1 or -1) * CameraModule.SmoothMouseSpeed * deltaTime
end

-- Masukan: putaran yang diminta frame ini (derajat). Keluaran: putaran yang benar-benar dipakai frame ini (derajat).
local function FilterLook(yaw, pitch, deltaTime)
    if not CameraModule.SmoothMouseEnabled or deltaTime <= 0 then return yaw, pitch end

    if CameraModule.SmoothMouseMode == "Constant" then
        local alpha = 1 - math.exp(-deltaTime / CONSTANT_RESPONSE)
        lookFilter.VelYaw = lookFilter.VelYaw + (yaw / deltaTime - lookFilter.VelYaw) * alpha
        lookFilter.VelPitch = lookFilter.VelPitch + (pitch / deltaTime - lookFilter.VelPitch) * alpha
        return ConstantAxis(lookFilter.VelYaw, deltaTime), ConstantAxis(lookFilter.VelPitch, deltaTime)
    end

    local rate = 40 - CameraModule.SmoothMouseSmoothness * 38 -- 40/detik (cepat) .. 2/detik (sangat halus)
    local alpha = 1 - math.exp(-rate * deltaTime)
    lookFilter.PendingYaw = lookFilter.PendingYaw + yaw
    lookFilter.PendingPitch = lookFilter.PendingPitch + pitch
    local outYaw, outPitch = lookFilter.PendingYaw * alpha, lookFilter.PendingPitch * alpha
    lookFilter.PendingYaw = lookFilter.PendingYaw - outYaw
    lookFilter.PendingPitch = lookFilter.PendingPitch - outPitch
    return outYaw, outPitch
end

local GameSettings
pcall(function() GameSettings = UserSettings():GetService("UserGameSettings") end)

-- Camera Sensitivity dari setting Roblox (dibaca tiap frame, jadi perubahan di menu Roblox langsung ikut).
function CameraModule.GetRobloxSensitivity()
    local ok, value = pcall(function() return GameSettings.MouseSensitivity end)
    if ok and type(value) == "number" and value > 0 then return value end
    return 1
end
CameraModule.FOVLocked = false
CameraModule.FOVValue = Camera and Camera.FieldOfView or 70
CameraModule.GameIntendedFOV = Camera and Camera.FieldOfView or 70
CameraModule.SpectateTarget = nil

CameraModule.PositionStabilizer = 0
CameraModule.RotationStabilizer = 0

CameraModule.ZoomLocked = false
CameraModule.ZoomValue = 12.5

local isModifyingFOV = false

local fovConnection
local subjectConnection
local cameraChangeConnection
local streamingTask = nil

local originalCameraType = Camera and Camera.CameraType or Enum.CameraType.Custom
local originalCameraSubject = Camera and Camera.CameraSubject
local originalMouseBehavior = Enum.MouseBehavior.Default
local freecamCFrame = Camera and Camera.CFrame or CFrame.new()
local rotationX = 0
local rotationY = 0

local smoothFocus = nil
local smoothRot = nil
local smoothDist = 0

CameraModule.OnFOVChanged = nil

local function UpdateCharacterAnchor()
    local shouldAnchor = (CameraModule.FreecamEnabled or CameraModule.SpectateTarget ~= nil)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character.HumanoidRootPart.Anchored = shouldAnchor
    end
end

local function LockFOV()
    if not Camera or isModifyingFOV then return end
    local currentCamFOV = Camera.FieldOfView
    
    if CameraModule.FOVLocked then
        if currentCamFOV ~= CameraModule.FOVValue then
            CameraModule.GameIntendedFOV = currentCamFOV
            isModifyingFOV = true
            Camera.FieldOfView = CameraModule.FOVValue
            isModifyingFOV = false
        end
    else
        if currentCamFOV ~= CameraModule.FOVValue then
            CameraModule.FOVValue = currentCamFOV
            CameraModule.GameIntendedFOV = currentCamFOV
            if CameraModule.OnFOVChanged then
                CameraModule.OnFOVChanged(currentCamFOV)
            end
        end
    end
end

function CameraModule.SetFOV(value)
    CameraModule.FOVValue = value
    if Camera then
        if not CameraModule.FOVLocked then CameraModule.GameIntendedFOV = value end
        isModifyingFOV = true
        Camera.FieldOfView = value
        isModifyingFOV = false
    end
end

function CameraModule.RestoreFOV()
    if Camera then
        isModifyingFOV = true
        Camera.FieldOfView = CameraModule.GameIntendedFOV
        isModifyingFOV = false
    end
end

local function LockSubject()
    if not Camera then return end
    if CameraModule.SpectateTarget and not CameraModule.FreecamEnabled then
        local targetChar = CameraModule.SpectateTarget.Character
        if targetChar and targetChar:FindFirstChild("Humanoid") then
            if Camera.CameraSubject ~= targetChar.Humanoid then
                Camera.CameraType = Enum.CameraType.Custom
                Camera.CameraSubject = targetChar.Humanoid
            end
        else
            CameraModule.SetSpectate(nil)
        end
    end
end

local function ConnectCameraEvents()
    if fovConnection then fovConnection:Disconnect() end
    if subjectConnection then subjectConnection:Disconnect() end
    if Camera then
        fovConnection = Camera:GetPropertyChangedSignal("FieldOfView"):Connect(LockFOV)
        subjectConnection = Camera:GetPropertyChangedSignal("CameraSubject"):Connect(LockSubject)
        LockFOV()
        LockSubject()
    end
end

cameraChangeConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
    ConnectCameraEvents()
end)

ConnectCameraEvents()

function CameraModule.SetZoom(value)
    CameraModule.ZoomValue = value
    if not CameraModule.FreecamEnabled then
        LocalPlayer.CameraMinZoomDistance = value
        LocalPlayer.CameraMaxZoomDistance = value
        
        if not CameraModule.ZoomLocked then
            task.delay(0.1, function()
                if not CameraModule.ZoomLocked then
                    LocalPlayer.CameraMinZoomDistance = 0.5
                    LocalPlayer.CameraMaxZoomDistance = 400
                end
            end)
        end
    end
end

function CameraModule.ToggleFreecam(state)
    CameraModule.FreecamEnabled = state
    UpdateCharacterAnchor()

    if state then
        originalCameraType = Camera.CameraType
        originalCameraSubject = Camera.CameraSubject
        originalMouseBehavior = UserInputService.MouseBehavior
        
        Camera.CameraType = Enum.CameraType.Scriptable
        freecamCFrame = Camera.CFrame
        local rx, ry, rz = freecamCFrame:ToOrientation()
        rotationX = math.deg(rx)
        rotationY = math.deg(ry)

        if Workspace.StreamingEnabled then
            streamingTask = task.spawn(function()
                while CameraModule.FreecamEnabled do
                    pcall(function() LocalPlayer:RequestStreamAroundAsync(freecamCFrame.Position) end)
                    task.wait(0.5)
                end
            end)
        end
    else
        Camera.CameraType = originalCameraType or Enum.CameraType.Custom
        Camera.CameraSubject = originalCameraSubject or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid"))
        UserInputService.MouseBehavior = originalMouseBehavior
        if streamingTask then
            task.cancel(streamingTask)
            streamingTask = nil
        end
    end
end

function CameraModule.SetSpectate(playerName)
    if not playerName or playerName == "" or playerName == LocalPlayer.Name then
        CameraModule.SpectateTarget = nil
        UpdateCharacterAnchor()
        if not CameraModule.FreecamEnabled and Camera then
            Camera.CameraType = Enum.CameraType.Custom
            Camera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        end
        return true, "Stopped spectating. Returned to local character."
    end

    local targetPlayer = Players:FindFirstChild(playerName)
    if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") then
        CameraModule.SpectateTarget = targetPlayer
        UpdateCharacterAnchor()
        LockSubject()
        return true, "Now spectating: " .. playerName
    else
        CameraModule.SpectateTarget = nil
        UpdateCharacterAnchor()
        return false, "Player not found or has left the game."
    end
end

function CameraModule.GetPlayerList()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name ~= LocalPlayer.Name then table.insert(list, player.Name) end
    end
    return list
end

RunService:BindToRenderStep("MugiwaraCameraMaster", Enum.RenderPriority.Last.Value + 2, function(deltaTime)
    if not Camera then return end

    if CameraModule.FreecamEnabled then
        Camera.CameraType = Enum.CameraType.Scriptable
        
        local moveVector = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, -1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, 1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveVector = moveVector + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveVector = moveVector + Vector3.new(0, -1, 0) end

        -- Putaran yang diminta frame ini (derajat), lalu disaring Smooth Mouse sebelum dipakai.
        local turnPitch, turnYaw = 0, 0
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            local mouseDelta = UserInputService:GetMouseDelta()
            local sensitivity, vertical = CameraModule.MouseSensitivity, 1
            if CameraModule.UseRobloxSensitivity then
                sensitivity, vertical = CameraModule.GetRobloxSensitivity(), MOUSE_VERTICAL_RATIO
            end
            turnPitch = -(mouseDelta.Y * MOUSE_DEGREES_PER_PIXEL * sensitivity * vertical * CameraModule.VerticalSpeed)
            turnYaw = -(mouseDelta.X * MOUSE_DEGREES_PER_PIXEL * sensitivity * CameraModule.HorizontalSpeed)
        else
            UserInputService.MouseBehavior = originalMouseBehavior
            local turn = ARROW_DEGREES_PER_SECOND * deltaTime
            local rotSpeedX, rotSpeedY = turn * CameraModule.VerticalSpeed, turn * CameraModule.HorizontalSpeed
            if UserInputService:IsKeyDown(Enum.KeyCode.Up) then turnPitch = turnPitch + rotSpeedX end
            if UserInputService:IsKeyDown(Enum.KeyCode.Down) then turnPitch = turnPitch - rotSpeedX end
            if UserInputService:IsKeyDown(Enum.KeyCode.Left) then turnYaw = turnYaw + rotSpeedY end
            if UserInputService:IsKeyDown(Enum.KeyCode.Right) then turnYaw = turnYaw - rotSpeedY end
        end
        turnYaw, turnPitch = FilterLook(turnYaw, turnPitch, deltaTime)
        rotationY = rotationY + turnYaw
        rotationX = math.clamp(rotationX + turnPitch, -89, 89)
        if math.abs(rotationX) >= 89 then lookFilter.PendingPitch = 0 end
        local camRotation = CFrame.Angles(0, math.rad(rotationY), 0) * CFrame.Angles(math.rad(rotationX), 0, 0)
        
        if moveVector.Magnitude > 0 then
            moveVector = moveVector.Unit * CameraModule.FreecamSpeed * deltaTime
            local relativeMove = camRotation * moveVector
            freecamCFrame = freecamCFrame + relativeMove
        end

        Camera.CFrame = CFrame.new(freecamCFrame.Position) * camRotation
        Camera.Focus = CFrame.new(freecamCFrame.Position + (camRotation.LookVector * 10))
    end

    if not CameraModule.FreecamEnabled and CameraModule.ZoomLocked then
        LocalPlayer.CameraMinZoomDistance = CameraModule.ZoomValue
        LocalPlayer.CameraMaxZoomDistance = CameraModule.ZoomValue
    end

    if CameraModule.PositionStabilizer == 0 and CameraModule.RotationStabilizer == 0 then
        smoothFocus = nil
        return
    end

    local targetCF = Camera.CFrame
    local targetFocus = Camera.Focus.Position

    if not smoothFocus or (smoothFocus - targetFocus).Magnitude > 100 then
        smoothFocus = targetFocus
        smoothRot = targetCF.Rotation
        smoothDist = (targetCF.Position - targetFocus).Magnitude
    end

    local targetDist = (targetCF.Position - targetFocus).Magnitude
    local targetRot = targetCF.Rotation
    
    local blendSpeed = 60
    local baseAlpha = 1 - math.exp(-blendSpeed * deltaTime)
    
    local posSpeedFactor = 1 - (CameraModule.PositionStabilizer * 0.9)
    local rotSpeedFactor = 1 - (CameraModule.RotationStabilizer * 0.9)
    
    local posAlpha = math.clamp(baseAlpha * posSpeedFactor, 0, 1)
    local rotAlpha = math.clamp(baseAlpha * rotSpeedFactor, 0, 1)

    smoothFocus = smoothFocus:Lerp(targetFocus, posAlpha)
    smoothRot = smoothRot:Lerp(targetRot, rotAlpha)
    smoothDist = smoothDist + (targetDist - smoothDist) * rotAlpha

    local newPos = smoothFocus + (smoothRot.LookVector * -smoothDist)
    Camera.CFrame = CFrame.new(newPos) * smoothRot

end)

-- Smooth Mouse di kamera biasa.
-- Kamera "sumber" (kamera bawaan Roblox, atau kamera milik game seperti Evade yang menyimpan sudutnya sendiri) dibiarkan
-- berjalan apa adanya. Tepat sebelum frame berikutnya dimulai (prioritas First) Camera.CFrame dikembalikan ke hasil
-- kamera sumber, jadi sumber TIDAK PERNAH melihat hasil saringan dan tidak ada umpan balik (umpan balik itulah yang
-- membuat kamera memantul / bounce: sumber yang menyimpan sudut sendiri terus menghitung ulang selisih yang sama).
-- Setelah sumber jalan (prioritas Last + 1), selisih sudut sumber terhadap frame sebelumnya = putaran dari input user
-- (mouse, panah, touch, gamepad); selisih itu disaring dan kamera diputar mengelilingi Camera.Focus dengan jarak yang sama.
local SNAP_YAW, SNAP_PITCH = math.rad(90), math.rad(60) -- lompatan sebesar ini (respawn, teleport kamera) tidak disaring
local MAX_PITCH = math.rad(80)
local sourceCFrame, sourceYaw, sourcePitch -- hasil kamera sumber frame sebelumnya
local smoothYaw, smoothPitch               -- sudut yang ditampilkan

local function LookAngles(cf)
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function WrapAngle(angle)
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function SmoothMouseActive()
    return Camera and CameraModule.SmoothMouseEnabled and not CameraModule.FreecamEnabled
        and Camera.CameraType == Enum.CameraType.Custom
end

local function ResetSource()
    sourceCFrame, sourceYaw, sourcePitch, smoothYaw, smoothPitch = nil, nil, nil, nil, nil
    CameraModule.ResetSmoothMouse()
end

RunService:BindToRenderStep("MugiwaraSmoothMouseRestore", Enum.RenderPriority.First.Value, function()
    if sourceCFrame and SmoothMouseActive() then Camera.CFrame = sourceCFrame end
end)

RunService:BindToRenderStep("MugiwaraSmoothMouse", Enum.RenderPriority.Last.Value + 1, function(deltaTime)
    if not SmoothMouseActive() then
        if sourceCFrame then ResetSource() end
        return
    end

    local cf, focus = Camera.CFrame, Camera.Focus.Position
    local yaw, pitch = LookAngles(cf)
    local turnYaw = sourceYaw and WrapAngle(yaw - sourceYaw) or 0
    local turnPitch = sourcePitch and (pitch - sourcePitch) or 0
    sourceCFrame, sourceYaw, sourcePitch = cf, yaw, pitch

    if not smoothYaw or math.abs(turnYaw) > SNAP_YAW or math.abs(turnPitch) > SNAP_PITCH then
        smoothYaw, smoothPitch = yaw, pitch
        CameraModule.ResetSmoothMouse()
        return
    end

    local outYaw, outPitch = FilterLook(math.deg(turnYaw), math.deg(turnPitch), deltaTime)
    smoothYaw = WrapAngle(smoothYaw + math.rad(outYaw))
    smoothPitch = math.clamp(smoothPitch + math.rad(outPitch), -MAX_PITCH, MAX_PITCH)
    if math.abs(smoothPitch) >= MAX_PITCH then lookFilter.PendingPitch = 0 end

    local distance = (cf.Position - focus).Magnitude
    local rotation = CFrame.Angles(0, smoothYaw, 0) * CFrame.Angles(smoothPitch, 0, 0)
    Camera.CFrame = CFrame.new(focus) * rotation * CFrame.new(0, 0, distance)
end)

function CameraModule.SetSmoothMouse(enabled)
    CameraModule.SmoothMouseEnabled = enabled
    ResetSource()
end

function CameraModule.SetSmoothMouseMode(mode)
    if mode ~= "Smooth" and mode ~= "Constant" then return end
    CameraModule.SmoothMouseMode = mode
    CameraModule.ResetSmoothMouse()
end

-- Full teardown on re-execute: undo freecam/spectate, release the character, drop all hooks.
getgenv().MugiwaraRegisterCleanup(function()
    pcall(function() RunService:UnbindFromRenderStep("MugiwaraCameraMaster") end)
    pcall(function() RunService:UnbindFromRenderStep("MugiwaraSmoothMouse") end)
    pcall(function() RunService:UnbindFromRenderStep("MugiwaraSmoothMouseRestore") end)
    CameraModule.SmoothMouseEnabled = false
    if fovConnection then fovConnection:Disconnect() fovConnection = nil end
    if subjectConnection then subjectConnection:Disconnect() subjectConnection = nil end
    if cameraChangeConnection then cameraChangeConnection:Disconnect() cameraChangeConnection = nil end

    if CameraModule.FreecamEnabled then pcall(CameraModule.ToggleFreecam, false) end
    CameraModule.FOVLocked = false
    CameraModule.ZoomLocked = false
    CameraModule.PositionStabilizer, CameraModule.RotationStabilizer = 0, 0
    CameraModule.OnFOVChanged = nil
    pcall(CameraModule.SetSpectate, nil)
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        LocalPlayer.CameraMinZoomDistance = 0.5
        LocalPlayer.CameraMaxZoomDistance = 400
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then root.Anchored = false end
    end)
    CameraModule.RestoreFOV()
end)

return CameraModule
