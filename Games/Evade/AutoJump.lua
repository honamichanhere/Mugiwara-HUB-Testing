-- Auto Jump (tahan Space untuk lompat terus, seperti bawaan Roblox).
-- Di Evade lompatan diatur Movement milik game (ReplicatedStorage.Objects.Game.Character.Client.Movement):
-- JumpReact() memasang Movement.CanJump = false dan baru membukanya lagi setelah Space DILEPAS
-- (InputService mengubah Movement.JumpHeldDown = false di InputEnded). Jadi menahan Space hanya memberi satu lompatan.
-- Modul ini, selama Space ditahan: begitu karakter mendarat lagi kuncinya dibuka (JumpHeldDown = false, persis yang
-- dilakukan game saat Space dilepas), lalu JumpReact() dipanggil lagi. Lompatan tetap lewat fungsi game sendiri,
-- jadi aturan game (stamina, downed, emote, dll.) tetap berlaku. Hanya lompat dari tanah: tidak memakai double jump.
local AutoJump = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ModuleGuard = getgenv().MugiwaraImport("Games/Evade/ModuleGuard.lua")

local RELOCK_TIMEOUT = 0.35 -- detik; lompatan yang tidak pernah lepas dari tanah (kepentok atap) tetap dibuka lagi

AutoJump.Enabled = false

local CharacterService
local connection
local jumpStarted, wasAirborne = nil, false

-- Modul CharacterService milik game (sudah dimuat game, require hanya mengambil tabel yang sama).
-- Gagal di executor yang tidak boleh me-require modul game (lihat ModuleGuard).
local function GetCharacterService()
    if CharacterService ~= nil then return CharacterService end
    local module = ReplicatedStorage:FindFirstChild("Services")
    module = module and module:FindFirstChild("Asset")
    module = module and module:FindFirstChild("CharacterService")
    if not (module and ModuleGuard) then
        CharacterService = false
        return false
    end
    local ok, result = ModuleGuard.Require(module)
    CharacterService = (ok and type(result) == "table" and type(result.GetLocalCharacter) == "function") and result or false
    return CharacterService
end

function AutoJump.Available()
    return GetCharacterService() ~= false
end

local function IsGrounded(movement)
    local ok, grounded = pcall(function() return movement.DataRegistry:Get("Grounded") end)
    return ok and grounded == true
end

local function Step()
    if not UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:GetFocusedTextBox() then
        jumpStarted = nil
        return
    end

    local ok, character = pcall(CharacterService.GetLocalCharacter, CharacterService)
    local movement = ok and character and character.Movement
    if type(movement) ~= "table" or type(movement.JumpReact) ~= "function" then return end

    local grounded = IsGrounded(movement)

    if movement.CanJump == false then
        -- Lompatan sedang "dikunci" sampai Space dilepas. Buka setelah mendarat lagi.
        if not jumpStarted then jumpStarted, wasAirborne = os.clock(), false end
        if not grounded then wasAirborne = true end
        if grounded and (wasAirborne or os.clock() - jumpStarted > RELOCK_TIMEOUT) then
            movement.JumpHeldDown = false -- loop JumpReact game selesai di Heartbeat berikutnya -> CanJump = true
        end
        return
    end

    if grounded then
        jumpStarted, wasAirborne = os.clock(), false
        task.spawn(movement.JumpReact, movement) -- JumpReact menunggu (yield) selama tombol "ditahan"
    end
end

-- Mengembalikan: berhasil, pesan (kalau gagal).
function AutoJump.SetEnabled(state)
    if state and not AutoJump.Available() then
        AutoJump.Enabled = false
        return false, "Your executor cannot read Evade's movement script, so Auto Jump is not available."
    end
    AutoJump.Enabled = state
    if state and not connection then
        connection = RunService.Heartbeat:Connect(function()
            local ok, err = pcall(Step)
            if not ok then warn("[Mugiwara HUB] Auto Jump error: " .. tostring(err)) end
        end)
    elseif not state and connection then
        connection:Disconnect()
        connection = nil
        jumpStarted = nil
    end
    return true
end

getgenv().MugiwaraRegisterCleanup(function()
    AutoJump.SetEnabled(false)
end)

return AutoJump
