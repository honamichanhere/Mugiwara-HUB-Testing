local PathInspector = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

-- Arahkan kursor ke sebuah objek di dunia game: popup di samping kursor menampilkan path-nya (siap
-- ditempel ke script) dan ClassName-nya, dan objeknya diberi outline. Tombol salin menyalin path ke
-- clipboard. UI-nya ada di Tabs/ToolsTab.lua; di sini hanya logika dan GUI popup.
--
-- Semua yang ada di Settings boleh diubah kapan saja, efeknya langsung terasa di frame berikutnya.

PathInspector.Settings = {
    MaxDistance = 1000,               -- jarak maksimal deteksi (studs)
    ShowClass = true,                 -- baris "Class: ..." di popup
    Outline = true,                   -- kotak outline pada objek yang ditunjuk
    OutlineColor = Color3.fromRGB(0, 170, 255),
    PathStyle = "GetService",         -- "GetService" -> game:GetService("Workspace").Part | "Dot" -> game.Workspace.Part
    IgnoreCharacter = true,           -- karakter sendiri tidak ikut terdeteksi
    PrintOnCopy = false,              -- cetak juga ke console (F9) saat disalin
}

PathInspector.PathStyles = { "GetService", "Dot" }

-- Dipasang oleh tab: mengembalikan true saat kursor sedang di atas UI hub, supaya popup tidak muncul di sana.
PathInspector.Blocker = nil
-- Dipanggil setelah path disalin atau gagal disalin: Callback(ok, message).
PathInspector.OnResult = nil

local TOOLTIP_OFFSET = Vector2.new(18, 18)
local TOOLTIP_MAX_WIDTH = 420
local PADDING = 8

local enabled = false
local currentTarget = nil
local gui, tooltip, pathLabel, classLabel, selectionBox
local renderConnection, inputConnection
local copyKey = Enum.KeyCode.F3

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- ---------- Path ----------

-- Nama aman (huruf/angka/underscore) pakai titik, selain itu ["..."].
local function FormatSegment(name)
    if string.match(name, "^[%a_][%w_]*$") then return "." .. name end
    local escaped = string.gsub(name, "\\", "\\\\")
    escaped = string.gsub(escaped, "\"", "\\\"")
    return "[\"" .. escaped .. "\"]"
end

function PathInspector.GetPath(instance, style)
    local segments = {}
    local current = instance
    while current and current ~= game do
        local parent = current.Parent
        if parent == game then
            if style == "Dot" then
                table.insert(segments, 1, FormatSegment(current.Name))
            else
                table.insert(segments, 1, ":GetService(\"" .. current.ClassName .. "\")")
            end
        else
            table.insert(segments, 1, FormatSegment(current.Name))
        end
        current = parent
    end
    -- Objek yang sudah tidak punya parent (terhapus / belum dipasang).
    if current ~= game then return "nil" .. table.concat(segments) end
    return "game" .. table.concat(segments)
end

-- ---------- GUI ----------

local function GuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function EnsureGui()
    if gui and gui.Parent then return end
    gui = Instance.new("ScreenGui")
    gui.Name = "MugiwaraPathInspector"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true -- posisi popup sama persis dengan GetMouseLocation
    gui.DisplayOrder = 9999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) elseif protect_gui then pcall(protect_gui, gui) end
    gui.Parent = GuiParent()

    tooltip = Instance.new("Frame")
    tooltip.Name = "Tooltip"
    tooltip.AutomaticSize = Enum.AutomaticSize.XY
    tooltip.Size = UDim2.fromOffset(0, 0)
    tooltip.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    tooltip.BackgroundTransparency = 0.1
    tooltip.Visible = false
    tooltip.Active = false
    tooltip.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = tooltip

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 70)
    stroke.Parent = tooltip

    local padding = Instance.new("UIPadding")
    padding.PaddingTop, padding.PaddingBottom = UDim.new(0, PADDING), UDim.new(0, PADDING)
    padding.PaddingLeft, padding.PaddingRight = UDim.new(0, PADDING), UDim.new(0, PADDING)
    padding.Parent = tooltip

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = tooltip

    local function Label(name, order, font, size, color)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.LayoutOrder = order
        label.AutomaticSize = Enum.AutomaticSize.XY
        label.Size = UDim2.fromOffset(0, 0)
        label.BackgroundTransparency = 1
        label.Font = font
        label.TextSize = size
        label.TextColor3 = color
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Parent = tooltip
        local limit = Instance.new("UISizeConstraint")
        limit.MaxSize = Vector2.new(TOOLTIP_MAX_WIDTH, math.huge)
        limit.Parent = label
        return label
    end
    pathLabel = Label("Path", 1, Enum.Font.Code, 14, Color3.fromRGB(255, 255, 255))
    classLabel = Label("Class", 2, Enum.Font.Gotham, 12, PathInspector.Settings.OutlineColor)

    selectionBox = Instance.new("SelectionBox")
    selectionBox.Name = "TargetOutline"
    selectionBox.LineThickness = 0.04
    selectionBox.SurfaceTransparency = 1
    selectionBox.Parent = gui
end

local function ClearTarget()
    currentTarget = nil
    if tooltip then tooltip.Visible = false end
    if selectionBox then selectionBox.Adornee = nil end
end

local function ApplyTargetStyle()
    local settings = PathInspector.Settings
    selectionBox.Color3 = settings.OutlineColor
    classLabel.TextColor3 = settings.OutlineColor
    classLabel.Visible = settings.ShowClass
    selectionBox.Adornee = settings.Outline and currentTarget or nil
end

local function ShowTarget(target)
    currentTarget = target
    pathLabel.Text = PathInspector.GetPath(target, PathInspector.Settings.PathStyle)
    classLabel.Text = "Class: " .. target.ClassName
    ApplyTargetStyle()
end

-- ---------- Deteksi ----------

local function TargetUnderCursor()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end

    local settings = PathInspector.Settings
    local mouse = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

    local character = Players.LocalPlayer.Character
    raycastParams.FilterDescendantsInstances = (settings.IgnoreCharacter and character) and { character } or {}

    local result = Workspace:Raycast(ray.Origin, ray.Direction * settings.MaxDistance, raycastParams)
    return result and result.Instance or nil
end

local function PlaceTooltip()
    local camera = Workspace.CurrentCamera
    local mouse = UserInputService:GetMouseLocation()
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local size = tooltip.AbsoluteSize

    local x = mouse.X + TOOLTIP_OFFSET.X
    local y = mouse.Y + TOOLTIP_OFFSET.Y
    -- Mentok kanan / bawah: pindahkan popup ke sisi sebaliknya dari kursor.
    if x + size.X > viewport.X then x = mouse.X - size.X - TOOLTIP_OFFSET.X end
    if y + size.Y > viewport.Y then y = mouse.Y - size.Y - TOOLTIP_OFFSET.Y end
    tooltip.Position = UDim2.fromOffset(math.max(0, x), math.max(0, y))
end

local function Step()
    local blocker = PathInspector.Blocker
    if blocker and blocker() then
        if currentTarget then ClearTarget() end
        return
    end

    local target = TargetUnderCursor()
    if not target then
        if currentTarget then ClearTarget() end
        return
    end

    if target ~= currentTarget then
        ShowTarget(target)
    end
    tooltip.Visible = true
    PlaceTooltip()
end

-- ---------- Salin ----------

local function Report(ok, message)
    if PathInspector.OnResult then pcall(PathInspector.OnResult, ok, message) end
end

-- Menyalin path objek yang sedang ditunjuk. Mengembalikan: berhasil, pesan.
function PathInspector.CopyPath()
    if not enabled then
        Report(false, "Turn Path Inspector on first.")
        return false
    end
    if not currentTarget then
        Report(false, "Point at an object first.")
        return false
    end

    local path = PathInspector.GetPath(currentTarget, PathInspector.Settings.PathStyle)
    if PathInspector.Settings.PrintOnCopy then print("[Path Inspector] " .. path) end
    if type(setclipboard) ~= "function" then
        Report(false, "Your executor cannot copy to the clipboard.")
        return false
    end
    local ok = pcall(setclipboard, path)
    Report(ok, ok and path or "Could not copy the path.")
    return ok
end

function PathInspector.SetCopyKey(keyCode)
    copyKey = keyCode
end

-- ---------- On / Off ----------

function PathInspector.IsEnabled()
    return enabled
end

-- Dipanggil saat pengaturan tampilan berubah, supaya popup yang sedang tampil ikut menyesuaikan.
function PathInspector.Refresh()
    if enabled and currentTarget and gui then ShowTarget(currentTarget) end
end

function PathInspector.SetEnabled(state)
    state = state == true
    if state == enabled then return end
    enabled = state

    if enabled then
        EnsureGui()
        renderConnection = RunService.RenderStepped:Connect(function()
            local ok, err = pcall(Step)
            if not ok then
                warn("[Mugiwara HUB] Path Inspector error: " .. tostring(err))
                PathInspector.SetEnabled(false)
            end
        end)
        inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
            -- Sedang mengetik (chat, kotak teks): jangan ikut terpicu.
            if processed then return end
            if copyKey and input.KeyCode == copyKey then PathInspector.CopyPath() end
        end)
    else
        if renderConnection then renderConnection:Disconnect() renderConnection = nil end
        if inputConnection then inputConnection:Disconnect() inputConnection = nil end
        ClearTarget()
    end
end

function PathInspector.Destroy()
    PathInspector.SetEnabled(false)
    if gui then gui:Destroy() gui = nil end
end

-- Posisi kursor dalam koordinat GUI hub (hub tidak mengabaikan GuiInset), untuk Blocker.
function PathInspector.CursorInGuiSpace()
    return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

if getgenv().MugiwaraRegisterCleanup then
    getgenv().MugiwaraRegisterCleanup(PathInspector.Destroy)
end

return PathInspector
