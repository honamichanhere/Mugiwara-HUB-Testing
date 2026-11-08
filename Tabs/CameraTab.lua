local CameraModule = getgenv().MugiwaraImport("Manager/Camera.lua")

return function(Window, isPremiumUser, MugiwaraUI)
    
    local TabCamera = Window:Tab({ Title = "Camera", Icon = "lucide:video" })

    local PremiumSection = TabCamera:Section({ Title = '<font color="#ffff82">Premium Features</font>', Icon = "rbxassetid://74594159374416", IconColor = Color3.fromRGB(255, 255, 130), Opened = false, Box = true })
    
    local FreeSection = PremiumSection:Section({ Title = "Free Camera", Icon = "lucide:video", Opened = false })

    local ToggleFreecam = FreeSection:Toggle({
        Title = "Enable Free Camera",
        Icon = "lucide:video",
        Desc = "Detach camera. Move with WASD/QE. Rotate by holding Right-Click or using Arrow Keys.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Callback = function(Value)
            CameraModule.ToggleFreecam(Value)
        end
    })

    -- Referensi toggle dipakai shortcut keyboard (tab Misc) supaya tombol UI ikut berubah.
    CameraModule.UI = { Freecam = ToggleFreecam }

    FreeSection:Slider({
        Title = "Free Camera Speed",
        Icon = "lucide:gauge",
        Desc = "Adjust the movement speed of the free camera.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 1,
        Value = { Min = 0, Max = 500, Default = 16 },
        Callback = function(Value)
            CameraModule.FreecamSpeed = Value
        end
    })

    local LookSection = PremiumSection:Section({ Title = "Free Camera Look", Icon = "lucide:mouse-pointer-2", Opened = false })

    LookSection:Toggle({
        Title = "Match Roblox Sensitivity",
        Icon = "lucide:mouse-pointer-2",
        Desc = "Turn the free camera with the Camera Sensitivity from your Roblox settings. Turn off to use the slider below.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Value = true,
        Callback = function(Value)
            CameraModule.UseRobloxSensitivity = Value
        end
    })

    LookSection:Slider({
        Title = "Mouse Sensitivity",
        Icon = "lucide:mouse",
        Desc = "Right-Click turning speed when Match Roblox Sensitivity is off. 1 = Roblox default.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.05,
        Suffix = "x",
        Value = { Min = 0.1, Max = 5, Default = 1 },
        Callback = function(Value)
            CameraModule.MouseSensitivity = Value
        end
    })

    LookSection:Slider({
        Title = "Horizontal Speed (Left / Right)",
        Icon = "lucide:move-horizontal",
        Desc = "How fast the camera turns left and right. Applies to Right-Click and the Left / Right Arrow Keys.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.05,
        Suffix = "x",
        Value = { Min = 0.1, Max = 5, Default = 1 },
        Callback = function(Value)
            CameraModule.HorizontalSpeed = Value
        end
    })

    LookSection:Slider({
        Title = "Vertical Speed (Up / Down)",
        Icon = "lucide:move-vertical",
        Desc = "How fast the camera turns up and down. Applies to Right-Click and the Up / Down Arrow Keys.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.05,
        Suffix = "x",
        Value = { Min = 0.1, Max = 5, Default = 1 },
        Callback = function(Value)
            CameraModule.VerticalSpeed = Value
        end
    })

    local ObserveSection = PremiumSection:Section({ Title = "Observation Mode", Icon = "lucide:eye", Opened = false })

    local DropdownSpectate
    DropdownSpectate = ObserveSection:Dropdown({
        Title = "Spectate Player",
        Icon = "lucide:eye",
        Desc = "Select a player from the server to observe their perspective.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Multi = false,
        Values = CameraModule.GetPlayerList(),
        Callback = function(Value)
            -- Library lama (WindUI) memanggil callback dropdown saat UI dibuat (nilai kosong); guard ini dipertahankan supaya
            -- tidak muncul notifikasi "Observation Active" tiap hub dijalankan.
            if type(Value) ~= "string" or Value == "" then return end

            local success, msg = CameraModule.SetSpectate(Value)
            MugiwaraUI:Notify({ Title = success and "Observation Active" or "Observation Failed", Content = msg, Duration = 3 })
        end
    })

    ObserveSection:Button({
        Title = "Refresh Player List",
        Desc = "Update the dropdown with the current active players in the server.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Icon = "lucide:refresh-cw",
        Callback = function()
            if DropdownSpectate and DropdownSpectate.Refresh then
                DropdownSpectate:Refresh(CameraModule.GetPlayerList())
                MugiwaraUI:Notify({ Title = "List Updated", Content = "The player list has been successfully refreshed.", Duration = 2 })
            end
        end
    })

    ObserveSection:Button({
        Title = "Stop Spectating",
        Desc = "Return the camera to your own local character.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Icon = "lucide:user-x",
        Callback = function()
            local success, msg = CameraModule.SetSpectate(nil)
            MugiwaraUI:Notify({ Title = "Camera Reset", Content = msg, Duration = 3 })
        end
    })

    local StabilizerSection = PremiumSection:Section({ Title = "Global Stabilizer Engine", Icon = "lucide:move", Opened = false })

    StabilizerSection:Slider({
        Title = "Position Stabilizer",
        Icon = "lucide:move",
        Desc = "Adds spring-like lag to character tracking.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.01,
        Value = { Min = 0, Max = 1, Default = 0 },
        Callback = function(Value)
            CameraModule.PositionStabilizer = Value
        end
    })

    StabilizerSection:Slider({
        Title = "Rotation Stabilizer",
        Icon = "lucide:rotate-3d",
        Desc = "Smooths out camera aiming for a cinematic feel.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.01,
        Value = { Min = 0, Max = 1, Default = 0 },
        Callback = function(Value)
            CameraModule.RotationStabilizer = Value
        end
    })

    local SmoothMouseSection = PremiumSection:Section({ Title = "Smooth Mouse", Icon = "lucide:mouse-pointer-click", Opened = false })

    SmoothMouseSection:Toggle({
        Title = "Enable Smooth Mouse",
        Icon = "lucide:mouse",
        Desc = "Filters how the camera turns (normal camera and Free Camera), so shaky or uneven mouse movement does not reach the camera.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Value = false,
        Callback = function(Value)
            CameraModule.SetSmoothMouse(Value)
        end
    })

    SmoothMouseSection:Dropdown({
        Title = "Smooth Mouse Mode",
        Icon = "lucide:sliders-horizontal",
        Desc = "Smooth: eases every mouse movement out over a few frames. Constant: only the direction counts, the camera turns at a fixed speed like the Arrow Keys.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Values = CameraModule.SmoothMouseModes,
        Value = CameraModule.SmoothMouseMode,
        Callback = function(Option)
            if type(Option) == "string" then CameraModule.SetSmoothMouseMode(Option) end
        end
    })

    SmoothMouseSection:Slider({
        Title = "Smoothness",
        Icon = "lucide:waves",
        Desc = "Smooth mode. Higher = softer, slower to catch up with the mouse.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 0.01,
        Value = { Min = 0, Max = 1, Default = CameraModule.SmoothMouseSmoothness },
        Callback = function(Value)
            CameraModule.SmoothMouseSmoothness = Value
        end
    })

    SmoothMouseSection:Slider({
        Title = "Constant Turn Speed",
        Icon = "lucide:gauge",
        Desc = "Constant mode. How fast the camera turns while the mouse moves, in degrees per second.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 1,
        Suffix = "°/s",
        Value = { Min = 5, Max = 360, Default = CameraModule.SmoothMouseSpeed },
        Callback = function(Value)
            CameraModule.SmoothMouseSpeed = Value
        end
    })

    SmoothMouseSection:Slider({
        Title = "Constant Deadzone",
        Icon = "lucide:circle-off",
        Desc = "Constant mode. Mouse movement slower than this is ignored, so a shaky hand does not turn the camera. Raise it if the camera still drifts.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Step = 1,
        Suffix = "°/s",
        Value = { Min = 0, Max = 300, Default = CameraModule.SmoothMouseDeadzone },
        Callback = function(Value)
            CameraModule.SmoothMouseDeadzone = Value
        end
    })

    local FovSection = TabCamera:Section({ Title = "Field of View", Icon = "lucide:eye", Opened = false, Box = true })

    local ToggleFOV
    ToggleFOV = FovSection:Toggle({
        Title = "Force Lock FOV",
        Icon = "lucide:lock",
        Desc = "Prevent the game from dynamically altering your field of view.",
        Callback = function(Value)
            CameraModule.FOVLocked = Value
            if not Value then CameraModule.RestoreFOV() end
        end
    })

    local safeFov = workspace.CurrentCamera and math.clamp(workspace.CurrentCamera.FieldOfView, 20, 120) or 70

    local SliderFOV
    SliderFOV = FovSection:Slider({
        Title = "Adjust FOV",
        Icon = "lucide:scan-eye",
        Desc = "Set your preferred field of view. Syncs automatically if game alters it.",
        Step = 1,
        Value = { Min = 20, Max = 120, Default = safeFov },
        Callback = function(Value)
            CameraModule.SetFOV(Value)
        end
    })
    
    local ZoomSection = TabCamera:Section({ Title = "Zoom Configurations", Icon = "lucide:fullscreen", Opened = false, Box = true })

    ZoomSection:Toggle({
        Title = "Force Lock Zoom",
        Icon = "lucide:lock",
        Desc = "Lock camera distance. Prevents game or scrolling from altering zoom.",
        Callback = function(Value)
            CameraModule.ZoomLocked = Value
            if not Value and not CameraModule.FreecamEnabled then
                game:GetService("Players").LocalPlayer.CameraMinZoomDistance = 0.5
                game:GetService("Players").LocalPlayer.CameraMaxZoomDistance = 400
            end
        end
    })

    ZoomSection:Slider({
        Title = "Adjust Zoom Distance",
        Icon = "lucide:zoom-in",
        Desc = "Set manual distance.",
        Step = 0.5,
        Value = { Min = 0, Max = 200, Default = 12.5 },
        Callback = function(Value)
            CameraModule.SetZoom(Value)
        end
    })

    CameraModule.OnFOVChanged = function(newValue)
        if SliderFOV then
            pcall(function() 
                if SliderFOV.SetValue then SliderFOV:SetValue(newValue)
                elseif SliderFOV.Set then SliderFOV:Set(newValue) end 
            end)
        end
    end

end
