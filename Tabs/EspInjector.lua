local ESP = getgenv().MugiwaraImport("Manager/ESP.lua")

-- Section "ESP" di tab Main (dipakai Universal.lua dan modul game, seperti MovementInjector).
return function(TargetTab, isPremiumUser, MugiwaraUI)
    if not ESP then
        TargetTab:Paragraph({
            Title = "ESP Unavailable",
            Icon = "lucide:triangle-alert",
            Desc = "The ESP module failed to load. Re-execute the hub to try again."
        })
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
end
