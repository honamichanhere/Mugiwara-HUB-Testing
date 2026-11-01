local ESP = getgenv().MugiwaraImport("Manager/ESP.lua")
local PlayerPath = getgenv().MugiwaraImport("Manager/PlayerPath.lua")

-- Section "Player Path": jalur berjalan ke pemain pilihan.
local function BuildPlayerPath(TargetTab, MugiwaraUI)
    if not PlayerPath then
        TargetTab:Paragraph({
            Title = "Player Path Unavailable",
            Icon = "lucide:triangle-alert",
            Desc = "The Player Path module failed to load. Re-execute the hub to try again."
        })
        return
    end

    local Settings = PlayerPath.Settings
    local PathSection = TargetTab:Section({ Title = "Player Path", Icon = "lucide:route", Opened = false, Box = true })

    -- Hanya memberi tahu saat jalur tidak ada / berubah, bukan tiap hitung ulang.
    PlayerPath.OnStatus = function(text)
        if text then MugiwaraUI:Notify({ Title = "Player Path", Content = text, Duration = 3 }) end
    end

    local TargetDropdown
    TargetDropdown = PathSection:Dropdown({
        Title = "Target Player",
        Icon = "lucide:user-search",
        Desc = "Pick the player to draw a walking route to.",
        Multi = false,
        Values = PlayerPath.GetPlayerList(),
        Callback = function(Value)
            -- Callback juga terpanggil saat UI dibuat (nilai kosong): diabaikan.
            if type(Value) ~= "string" or Value == "" then return end
            local ok, message = PlayerPath.SetTarget(Value)
            MugiwaraUI:Notify({ Title = ok and "Player Path" or "Player Path Failed", Content = message, Duration = 2 })
        end
    })

    PathSection:Button({
        Title = "Refresh Player List",
        Icon = "lucide:refresh-cw",
        Callback = function()
            if TargetDropdown and TargetDropdown.Refresh then
                TargetDropdown:Refresh(PlayerPath.GetPlayerList())
                MugiwaraUI:Notify({ Title = "List Updated", Content = "The player list has been refreshed.", Duration = 2 })
            end
        end
    })

    PathSection:Toggle({
        Title = "Show Path",
        Icon = "lucide:map-pin",
        Desc = "Draws a route along the floor to the target. It follows walkable ground only and never cuts through walls.",
        Value = false,
        Callback = function(Value) PlayerPath.SetEnabled(Value) end
    })

    PathSection:Colorpicker({
        Title = "Path Color",
        Icon = "lucide:palette",
        Default = Settings.Color,
        Callback = function(Color)
            Settings.Color = Color
            PlayerPath.Refresh()
        end
    })

    PathSection:Slider({
        Title = "Line Thickness",
        Icon = "lucide:minus",
        Step = 0.1,
        Value = { Min = 0.1, Max = 1.5, Default = Settings.Thickness },
        Callback = function(Value)
            Settings.Thickness = Value
            PlayerPath.Refresh()
        end
    })

    PathSection:Toggle({
        Title = "Line Through Walls",
        Icon = "lucide:brick-wall",
        Desc = "Keep the line visible behind walls so you can follow it around corners. The route itself always avoids walls.",
        Value = Settings.ThroughWalls,
        Callback = function(Value)
            Settings.ThroughWalls = Value
            PlayerPath.Refresh()
        end
    })

    PathSection:Toggle({
        Title = "Allow Jumps",
        Icon = "lucide:chevrons-up",
        Desc = "Let the route include jumps over gaps and obstacles.",
        Value = Settings.AllowJump,
        Callback = function(Value) Settings.AllowJump = Value end
    })
end

-- Section "ESP" dan "Player Path" di tab Main (dipakai Universal.lua dan modul game, seperti MovementInjector).
return function(TargetTab, isPremiumUser, MugiwaraUI)
    if not ESP then
        TargetTab:Paragraph({
            Title = "ESP Unavailable",
            Icon = "lucide:triangle-alert",
            Desc = "The ESP module failed to load. Re-execute the hub to try again."
        })
        BuildPlayerPath(TargetTab, MugiwaraUI)
        return
    end

    local Settings = ESP.Settings
    local EspSection = TargetTab:Section({ Title = "ESP", Icon = "lucide:eye", Opened = false, Box = true })

    EspSection:Toggle({
        Title = "Player ESP",
        Icon = "lucide:scan-eye",
        Desc = "Outline other players so you can see them through walls. Only changes how the game looks for you.",
        Value = false,
        Callback = function(Value) ESP.SetEnabled(Value) end
    })

    EspSection:Colorpicker({
        Title = "Outline Color",
        Icon = "lucide:palette",
        Desc = "Color of the outline and the name label.",
        Default = Settings.OutlineColor,
        Callback = function(Color)
            Settings.OutlineColor = Color
            ESP.Refresh()
        end
    })

    EspSection:Colorpicker({
        Title = "Fill Color",
        Icon = "lucide:paint-bucket",
        Desc = "Color inside the outline. Only visible when Fill Opacity is above 0.",
        Default = Settings.FillColor,
        Callback = function(Color)
            Settings.FillColor = Color
            ESP.Refresh()
        end
    })

    EspSection:Slider({
        Title = "Fill Opacity",
        Icon = "lucide:blend",
        Desc = "0% = outline only.",
        Step = 5,
        Suffix = "%",
        Value = { Min = 0, Max = 100, Default = Settings.FillOpacity * 100 },
        Callback = function(Value)
            Settings.FillOpacity = Value / 100
            ESP.Refresh()
        end
    })

    EspSection:Toggle({
        Title = "Through Walls",
        Icon = "lucide:brick-wall",
        Desc = "Off = only the parts of a player you can actually see are outlined.",
        Value = Settings.ThroughWalls,
        Callback = function(Value)
            Settings.ThroughWalls = Value
            ESP.Refresh()
        end
    })

    EspSection:Toggle({
        Title = "Show Names",
        Icon = "lucide:tag",
        Value = Settings.ShowNames,
        Callback = function(Value)
            Settings.ShowNames = Value
            ESP.Refresh()
        end
    })

    EspSection:Toggle({
        Title = "Show Distance",
        Icon = "lucide:ruler",
        Value = Settings.ShowDistance,
        Callback = function(Value)
            Settings.ShowDistance = Value
            ESP.Refresh()
        end
    })

    EspSection:Slider({
        Title = "Max Distance",
        Icon = "lucide:radar",
        Desc = "Players farther than this are not drawn.",
        Step = 100,
        Suffix = " studs",
        Value = { Min = 100, Max = 10000, Default = Settings.MaxDistance },
        Callback = function(Value)
            Settings.MaxDistance = Value
            ESP.Refresh()
        end
    })

    BuildPlayerPath(TargetTab, MugiwaraUI)
end
