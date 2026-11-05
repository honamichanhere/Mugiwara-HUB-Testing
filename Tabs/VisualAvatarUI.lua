-- Antarmuka Accessory dan Korless (Headless + Korblox), dipakai bersama oleh Universal dan Evade.
-- Logikanya ada di Manager/VisualAccessories.lua; modul itu dikirim lewat parameter `VisualAcc` supaya
-- Evade memakai versi yang sudah dipasangi rig-nya sendiri.
--
-- Penjaga anti-dobel: tiap bagian hanya boleh dibuat SEKALI per sesi hub. Kalau ada jalur lain yang mencoba
-- membuatnya lagi (misalnya modul Universal ikut termuat di game yang sudah punya modul sendiri), yang kedua
-- dilewati. Penjaga dibersihkan saat hub di-unload atau di-execute ulang.
local UI = {}

local function Claim(name)
    local env = getgenv()
    if not env.MugiwaraVisualAvatarUI then
        env.MugiwaraVisualAvatarUI = {}
        env.MugiwaraRegisterCleanup(function() env.MugiwaraVisualAvatarUI = nil end)
    end
    if env.MugiwaraVisualAvatarUI[name] then
        warn("[Mugiwara HUB] " .. name .. " UI is already built, skipping the second copy.")
        return false
    end
    env.MugiwaraVisualAvatarUI[name] = true
    return true
end

function UI.BuildAccessory(Section, VisualAcc, isPremiumUser, MugiwaraUI)
    if not Claim("Accessory") then return end

    local templateNames = {}
    if VisualAcc and VisualAcc.Templates then
        for _, item in ipairs(VisualAcc.Templates) do
            table.insert(templateNames, item.Name)
        end
    end

    -- Multi-select: tiap item yang dicentang dipasang, dan dilepas lagi saat centangnya dihapus.
    -- `worn` = nama template yang saat ini terpasang lewat dropdown ini.
    local worn = {}
    local TemplateDropdown
    TemplateDropdown = Section:Dropdown({
        Title = "Accessory Templates",
        Icon = "lucide:shirt",
        Desc = "Tick the accessories you want to wear. Untick one to take it off.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Multi = true,
        Values = templateNames,
        Value = {},
        Callback = function(Selected)
            if not VisualAcc or type(Selected) ~= "table" then return end

            local wanted = {}
            for _, name in ipairs(Selected) do wanted[name] = true end

            for _, item in ipairs(VisualAcc.Templates) do
                if wanted[item.Name] and not worn[item.Name] then
                    worn[item.Name] = true
                    task.spawn(function() VisualAcc.Apply(item.ID, MugiwaraUI) end)
                elseif not wanted[item.Name] and worn[item.Name] then
                    worn[item.Name] = nil
                    VisualAcc.Remove(item.ID)
                end
            end
        end
    })

    local CustomAccInput
    CustomAccInput = Section:Input({
        Title = "Load Custom Asset ID",
        Icon = "lucide:hash",
        Desc = "Enter a valid Marketplace Accessory ID.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Placeholder = "e.g., 10159600649",
        Callback = function(Text)
            if not Text or Text == "" then return end
            local assetId = tonumber(Text)
            if assetId then
                task.spawn(function()
                    if VisualAcc then VisualAcc.Apply(assetId, MugiwaraUI) end
                end)
                pcall(function() CustomAccInput:Set("") end)
            else
                MugiwaraUI:Notify({ Title = "Invalid Input", Content = "Please enter a valid numeric ID.", Duration = 3 })
            end
        end
    })

    Section:Button({
        Title = "Clear All Custom Accessories",
        Icon = "lucide:trash-2",
        Desc = "Remove all spawned accessories from your character.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Callback = function()
            if VisualAcc then VisualAcc.Clear(MugiwaraUI) end
            -- Centang di dropdown ikut dilepas (tanpa memicu callback-nya).
            worn = {}
            pcall(function() TemplateDropdown:Set({}, true) end)
        end
    })
end

-- Avatar Changer: `AvatarChanger` adalah Manager/AvatarChanger.lua (Evade mengirim versi dengan rig-nya sendiri).
function UI.BuildAvatar(Section, AvatarChanger, isPremiumUser, MugiwaraUI)
    if not Claim("Avatar") then return end

    local AvatarInput
    AvatarInput = Section:Input({
        Title = "Morph By Username",
        Icon = "lucide:user-round",
        Desc = "Copy any player's avatar exactly 1:1.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Placeholder = "Username...",
        Callback = function(Text)
            if not Text or Text == "" then return end

            task.spawn(function()
                if AvatarChanger then AvatarChanger.Apply(Text, MugiwaraUI) end
            end)
            pcall(function() AvatarInput:Set("") end)
        end
    })

    Section:Button({
        Title = "Revert to Original",
        Icon = "lucide:undo-2",
        Desc = "Back to original avatar.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Callback = function()
            if AvatarChanger then AvatarChanger.Clear(true, MugiwaraUI) end
        end
    })
end

function UI.BuildKorless(Section, VisualAcc, isPremiumUser, MugiwaraUI)
    if not Claim("Korless") then return end

    Section:Toggle({
        Title = "Headless Head",
        Icon = "lucide:skull",
        Desc = "Visually removes your character's head.",
        Locked = not isPremiumUser,
        LockedTitle = "Premium Only",
        Callback = function(Value)
            task.spawn(function()
                if VisualAcc then VisualAcc.ToggleHeadless(Value) end
            end)
        end
    })

    local function KorbloxToggle(side)
        local lower = string.lower(side)
        Section:Toggle({
            Title = "Korblox " .. side .. " Leg",
            Icon = "lucide:footprints",
            Desc = "Applies Korblox visual mesh to the " .. lower .. " leg.",
            Locked = not isPremiumUser,
            LockedTitle = "Premium Only",
            Callback = function(Value)
                task.spawn(function()
                    if not VisualAcc then return end
                    if Value and VisualAcc.IsKorbloxReady and not VisualAcc.IsKorbloxReady() then
                        MugiwaraUI:Notify({ Title = "Korblox", Content = "Preparing your avatar data. Korblox is applied in a few seconds.", Duration = 4 })
                    end
                    local ok = VisualAcc.ToggleKorblox(Value, side)
                    if Value and not ok then
                        MugiwaraUI:Notify({ Title = "Korblox", Content = "Could not apply the " .. lower .. " Korblox leg. Check the console for details.", Duration = 4 })
                    end
                end)
            end
        })
    end

    -- Kaki kanan memakai cache Korblox seperti skrip Korless-Visual; kaki kiri punya cache sendiri dengan aset
    -- kaki kiri (lihat Manager/VisualAccessories.lua).
    KorbloxToggle("Left")
    KorbloxToggle("Right")

    -- Cache avatar disiapkan sekarang (premium saja), jadi toggle Korblox pertama tidak perlu menunggu.
    if isPremiumUser and VisualAcc and VisualAcc.PrepareKorblox then VisualAcc.PrepareKorblox() end
end

return UI
