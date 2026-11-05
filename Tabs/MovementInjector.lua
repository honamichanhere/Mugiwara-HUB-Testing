local MovementModule = getgenv().MugiwaraImport("Manager/Movement.lua")
local Risk = getgenv().MugiwaraImport("Manager/Risk.lua") or { Desc = function(_, text) return text end, Warn = function() end }

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local defaultWalkSpeed = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") and LocalPlayer.Character.Humanoid.WalkSpeed or 16
local defaultJumpPower = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") and LocalPlayer.Character.Humanoid.JumpPower or 50

-- Character Movement dibagi per kategori (section di dalam section): Speed, Jump, Flight, Collision,
-- Teleport, dan Animation.
return function(TargetTab, isPremiumUser, MugiwaraUI)
    local MovementSection = TargetTab:Section({ Title = "Character Movement", Icon = "lucide:footprints", Opened = false, Box = true })

    local function Notify(title, content, duration)
        MugiwaraUI:Notify({ Title = title, Content = content, Duration = duration or 3 })
    end

    -- ---------- Speed ----------
    local SpeedSection = MovementSection:Section({ Title = "Speed", Icon = "lucide:zap", Opened = false })

    local ToggleTweenSpeed
    local ToggleSpeed = SpeedSection:Toggle({ Title = "Enable Speed Hack", Icon = "lucide:zap", Desc = Risk.Desc("SpeedHack"), Callback = function(Value) Risk.Warn(MugiwaraUI, "SpeedHack", Value); MovementModule.SpeedEnabled = Value; if not Value then MovementModule.RestoreSpeed() end; if Value and ToggleTweenSpeed then ToggleTweenSpeed:Set(false) end end })
    SpeedSection:Slider({ Title = "Speed Hack Value", Icon = "lucide:gauge", Step = 1, Value = { Min = 0, Max = 200, Default = defaultWalkSpeed }, Callback = function(Value) MovementModule.SpeedValue = Value end })

    ToggleTweenSpeed = SpeedSection:Toggle({ Title = "Enable Tween Speed", Icon = "lucide:route", Desc = Risk.Desc("TweenSpeed"), Callback = function(Value) Risk.Warn(MugiwaraUI, "TweenSpeed", Value); MovementModule.TweenSpeedEnabled = Value; if Value and ToggleSpeed then ToggleSpeed:Set(false) end end })
    SpeedSection:Slider({ Title = "Tween Speed Value", Icon = "lucide:gauge", Step = 1, Value = { Min = 0, Max = 200, Default = defaultWalkSpeed }, Callback = function(Value) MovementModule.TweenSpeedValue = Value end })

    -- ---------- Jump ----------
    local JumpSection = MovementSection:Section({ Title = "Jump", Icon = "lucide:arrow-up", Opened = false })

    JumpSection:Toggle({ Title = "Enable Jump Power", Icon = "lucide:arrow-up", Desc = Risk.Desc("JumpPower"), Callback = function(Value) Risk.Warn(MugiwaraUI, "JumpPower", Value); MovementModule.JumpEnabled = Value; if not Value then MovementModule.RestoreJump() end end })
    JumpSection:Slider({ Title = "Jump Power Value", Icon = "lucide:move-up", Step = 1, Value = { Min = 0, Max = 200, Default = defaultJumpPower }, Callback = function(Value) MovementModule.JumpValue = Value end })
    local ToggleInfJump = JumpSection:Toggle({ Title = "Enable Infinite Jump", Icon = "lucide:chevrons-up", Desc = Risk.Desc("InfiniteJump"), Callback = function(Value) Risk.Warn(MugiwaraUI, "InfiniteJump", Value); MovementModule.InfJumpEnabled = Value end })
    JumpSection:Slider({ Title = "Infinite Jump Cap", Icon = "lucide:ruler", Step = 1, Value = { Min = 0, Max = 200, Default = 200 }, Callback = function(Value) MovementModule.InfJumpMax = Value end })

    -- ---------- Flight ----------
    local FlightSection = MovementSection:Section({ Title = "Flight", Icon = "lucide:plane", Opened = false })

    local ToggleFly = FlightSection:Toggle({ Title = "Enable Fly", Icon = "lucide:plane", Desc = Risk.Desc("Fly"), Callback = function(Value) Risk.Warn(MugiwaraUI, "Fly", Value); MovementModule.ToggleFly(Value) end })
    FlightSection:Slider({ Title = "Fly Speed", Icon = "lucide:gauge", Step = 1, Value = { Min = 0, Max = 500, Default = 16 }, Callback = function(Value) MovementModule.FlySpeed = Value end })

    -- ---------- Collision ----------
    local CollisionSection = MovementSection:Section({ Title = "Collision", Icon = "lucide:ghost", Opened = false })

    local ToggleNoclip = CollisionSection:Toggle({ Title = "Enable Noclip", Icon = "lucide:ghost", Desc = Risk.Desc("Noclip", "Walk through walls and any other object. Works on the ground and in the air."), Callback = function(Value) Risk.Warn(MugiwaraUI, "Noclip", Value); MovementModule.NoclipEnabled = Value end })

    -- ---------- Teleport ----------
    local TeleportSection = MovementSection:Section({ Title = "Teleport", Icon = "lucide:navigation", Opened = false })

    local teleportText = ""
    TeleportSection:Input({ Title = "Coordinates", Icon = "lucide:map-pin", Desc = "X, Y, Z of where to go, for example 120.5, 40, -300. Paste a copied position here.", Placeholder = "X, Y, Z", Callback = function(Text) teleportText = Text end })
    TeleportSection:Button({
        Title = "Teleport to Coordinates",
        Icon = "lucide:navigation",
        Desc = Risk.Desc("Teleport", "Moves your character to the coordinates above. Teleporting far is easily flagged by the server."),
        Callback = function()
            local position = MovementModule.ParsePosition(teleportText)
            if not position then
                Notify("Teleport", "Enter three numbers: X, Y, Z.")
                return
            end
            Risk.Warn(MugiwaraUI, "Teleport", true)
            local ok, message = MovementModule.TeleportTo(position)
            Notify(ok and "Teleport" or "Teleport Failed", message)
        end
    })
    TeleportSection:Button({
        Title = "Copy My Position",
        Icon = "lucide:clipboard-copy",
        Desc = "Copies your current X, Y, Z to the clipboard.",
        Callback = function()
            local position = MovementModule.GetPosition()
            if not position then
                Notify("Copy Position", "Your character is not ready yet.")
                return
            end
            local text = MovementModule.FormatPosition(position)
            if type(setclipboard) ~= "function" or not pcall(setclipboard, text) then
                Notify("Copy Position", "Your executor cannot copy to the clipboard.")
                return
            end
            Notify("Position Copied", text, 2)
        end
    })

    TeleportSection:Divider({ Title = "Teleport to Player" })

    local selectedPlayer = nil
    local PlayerDropdown
    PlayerDropdown = TeleportSection:Dropdown({
        Title = "Player",
        Icon = "lucide:user-search",
        Desc = "Pick the player to teleport to. Type in the box to search.",
        Multi = false,
        Searchable = true,
        Values = MovementModule.GetPlayerList(),
        Callback = function(Value)
            -- Callback juga terpanggil saat UI dibuat (nilai kosong): jadi tidak mengubah pilihan.
            if type(Value) == "string" and Value ~= "" then selectedPlayer = Value end
        end
    })
    TeleportSection:Button({
        Title = "Refresh Player List",
        Icon = "lucide:refresh-cw",
        Desc = "Update the list with the players who are in the server now.",
        Callback = function()
            if PlayerDropdown and PlayerDropdown.Refresh then
                PlayerDropdown:Refresh(MovementModule.GetPlayerList())
                selectedPlayer = nil
                Notify("List Updated", "The player list has been refreshed.", 2)
            end
        end
    })
    TeleportSection:Button({
        Title = "Teleport to Player",
        Icon = "lucide:user-round-check",
        Desc = Risk.Desc("Teleport", "Moves your character next to the selected player."),
        Callback = function()
            if not selectedPlayer then
                Notify("Teleport", "Pick a player first.")
                return
            end
            Risk.Warn(MugiwaraUI, "Teleport", true)
            local ok, message = MovementModule.TeleportToPlayer(selectedPlayer)
            Notify(ok and "Teleport" or "Teleport Failed", message)
        end
    })

    -- ---------- Animation ----------
    local AnimationSection = MovementSection:Section({ Title = "Animation Controls", Icon = "lucide:timer", Opened = false })

    AnimationSection:Input({ Title = "Animation Speed", Icon = "lucide:timer", Desc = "Speed multiplier for all your playing animations, kept on every frame. Enter 1 to reset, 0 to freeze.", Placeholder = "Number", Callback = function(Text) local num = tonumber(Text) if num then MovementModule.SetAnimSpeed(num) end end })

    -- Referensi toggle dipakai shortcut keyboard (tab Misc) supaya tombol UI ikut berubah.
    MovementModule.UI = { Speed = ToggleSpeed, InfJump = ToggleInfJump, Fly = ToggleFly, Noclip = ToggleNoclip }
end
