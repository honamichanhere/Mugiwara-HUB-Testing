local PathInspector = getgenv().MugiwaraImport("Manager/PathInspector.lua")
local KeybindsModule = getgenv().MugiwaraImport("Manager/Keybinds.lua")

-- Tab Tools: alat bantu kecil untuk membuat dan menguji script. Tiap alat satu Section; alat baru cukup
-- ditambahkan sebagai Section di bawah.
return function(Window, isPremiumUser, MugiwaraUI)

    local TabTools = Window:Tab({ Title = "Tools", Icon = "lucide:hammer" })

    local function Notify(title, content, duration)
        MugiwaraUI:Notify({ Title = title, Content = content, Duration = duration or 3 })
    end

    if not PathInspector then
        TabTools:Paragraph({
            Title = "Tools Unavailable",
            Icon = "lucide:triangle-alert",
            Desc = "The Path Inspector module failed to load. Re-execute the hub to try again."
        })
        return
    end

    local Settings = PathInspector.Settings

    -- Popup tidak ditampilkan selagi kursor ada di atas jendela hub.
    PathInspector.Blocker = function()
        if not Window.Opened or not Window.Main then return false end
        local cursor = PathInspector.CursorInGuiSpace()
        local position, size = Window.Main.AbsolutePosition, Window.Main.AbsoluteSize
        return cursor.X >= position.X and cursor.X <= position.X + size.X
            and cursor.Y >= position.Y and cursor.Y <= position.Y + size.Y
    end

    PathInspector.OnResult = function(ok, message)
        if ok then
            Notify("Path Copied", message, 2)
        else
            Notify("Path Inspector", message, 3)
        end
    end

    -- ---------- Path Inspector ----------
    local InspectorSection = TabTools:Section({ Title = "Path Inspector", Icon = "lucide:scan-search", Opened = true, Box = true })

    local copyName = KeybindsModule and KeybindsModule.Get("PathInspectorCopy", "F3") or "F3"
    local function ApplyCopyKey(name)
        PathInspector.SetCopyKey(KeybindsModule and KeybindsModule.GetKeyCode(name) or nil)
    end
    ApplyCopyKey(copyName)

    InspectorSection:Toggle({
        Title = "Path Inspector",
        Icon = "lucide:scan-search",
        Desc = "Point at any object in the game to see its path and class next to the cursor, with an outline around it.",
        Value = false,
        Callback = function(Value)
            PathInspector.SetEnabled(Value)
        end
    })

    InspectorSection:Keybind({
        Title = "Copy Path Key",
        Icon = "lucide:clipboard-copy",
        Desc = "Copies the path of the object under the cursor. Only works while Path Inspector is on.",
        Value = copyName,
        OnChange = function(value)
            if not (KeybindsModule and KeybindsModule.IsValidKey(value)) then
                Notify("Copy Path Key", "This needs a keyboard key.", 3)
                return
            end
            KeybindsModule.Set("PathInspectorCopy", value)
            ApplyCopyKey(value)
            Notify("Shortcut Saved", "Copy Path = " .. value, 2)
        end
    })

    InspectorSection:Dropdown({
        Title = "Path Style",
        Icon = "lucide:route",
        Desc = "GetService: game:GetService(\"Workspace\").Part   |   Dot: game.Workspace.Part",
        Values = PathInspector.PathStyles,
        Value = Settings.PathStyle,
        Callback = function(Option)
            if type(Option) ~= "string" or Option == "" then return end
            Settings.PathStyle = Option
            PathInspector.Refresh()
        end
    })

    InspectorSection:Toggle({
        Title = "Show Class Name",
        Icon = "lucide:tag",
        Desc = "Show the ClassName under the path in the popup.",
        Value = Settings.ShowClass,
        Callback = function(Value)
            Settings.ShowClass = Value
            PathInspector.Refresh()
        end
    })

    InspectorSection:Toggle({
        Title = "Outline Object",
        Icon = "lucide:square-dashed",
        Desc = "Draw a box around the object under the cursor.",
        Value = Settings.Outline,
        Callback = function(Value)
            Settings.Outline = Value
            PathInspector.Refresh()
        end
    })

    InspectorSection:Colorpicker({
        Title = "Outline Color",
        Icon = "lucide:palette",
        Desc = "Color of the outline and the class name.",
        Default = Settings.OutlineColor,
        Callback = function(Color)
            Settings.OutlineColor = Color
            PathInspector.Refresh()
        end
    })

    InspectorSection:Slider({
        Title = "Max Distance",
        Icon = "lucide:ruler",
        Desc = "How far from the camera objects can be picked.",
        Step = 50,
        Suffix = " studs",
        Value = { Min = 50, Max = 5000, Default = Settings.MaxDistance },
        Callback = function(Value)
            Settings.MaxDistance = Value
        end
    })

    InspectorSection:Toggle({
        Title = "Ignore My Character",
        Icon = "lucide:user-x",
        Desc = "Look through your own character so it never blocks the object behind it.",
        Value = Settings.IgnoreCharacter,
        Callback = function(Value)
            Settings.IgnoreCharacter = Value
        end
    })

    InspectorSection:Toggle({
        Title = "Print Copied Path to Console",
        Icon = "lucide:terminal",
        Desc = "Also print the path to the console (F9) when you copy it.",
        Value = Settings.PrintOnCopy,
        Callback = function(Value)
            Settings.PrintOnCopy = Value
        end
    })
end
