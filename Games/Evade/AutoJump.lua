-- Auto Jump (tahan Space untuk lompat terus, seperti bawaan Roblox).
-- Di Evade lompatan diatur Movement milik game (ReplicatedStorage.Objects.Game.Character.Client.Movement):
-- JumpReact() memasang Movement.CanJump = false dan baru membukanya lagi setelah Space DILEPAS
-- (InputService mengubah Movement.JumpHeldDown = false di InputEnded). Jadi menahan Space hanya memberi satu lompatan.
-- Selama Space ditahan, tiap kali karakter mendarat kunci itu dibuka lalu lompatan diminta lagi. Dua cara:
--   "Direct" : lewat objek Movement game (require CharacterService): JumpHeldDown = false lalu JumpReact().
--              Hanya di executor yang require-nya mengembalikan modul yang SEDANG dipakai game.
--   "Input"  : lewat VirtualInputManager: Space "dilepas" lalu "ditekan" lagi, persis seperti jari user. Dipakai kalau
--              Direct tidak bisa (mis. Solara: require modul game gagal / memberi salinan baru tanpa karakter).
-- Dua-duanya memakai jalur lompat game sendiri, jadi aturan game (stamina, downed, emote, dll.) tetap berlaku.
-- Hanya lompat dari tanah: double jump tidak dipakai otomatis.
local AutoJump = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ModuleGuard = getgenv().MugiwaraImport("Games/Evade/ModuleGuard.lua")

local LocalPlayer = Players.LocalPlayer
local RELOCK_TIMEOUT = 0.35 -- detik; lompatan yang tidak pernah lepas dari tanah (kepentok atap) tetap dibuka lagi
local SPACE = Enum.KeyCode.Space

AutoJump.Enabled = false
AutoJump.Mode = nil -- "Direct" | "Input" (dipilih saat diaktifkan)

local connection
local CharacterService
local VirtualInputManager
local jumpStarted, wasAirborne = nil, false
local pulseStep = 0 -- mode Input: 0 = diam, >0 = sedang mengirim lepas -> tekan Space

-- ---------- Direct ----------
local function GetCharacterService()
    if CharacterService ~= nil then return CharacterService end
    CharacterService = false
    local module = ReplicatedStorage:FindFirstChild("Services")
    module = module and module:FindFirstChild("Asset")
    module = module and module:FindFirstChild("CharacterService")
    if module and ModuleGuard then
        local ok, result = ModuleGuard.Require(module)
        if ok and type(result) == "table" and type(result.GetLocalCharacter) == "function" then CharacterService = result end
    end
    return CharacterService
end

local function GetMovement()
    local service = GetCharacterService()
    if not service then return nil end
    local ok, character = pcall(service.GetLocalCharacter, service)
    local movement = ok and character and character.Movement
    if type(movement) == "table" and type(movement.JumpReact) == "function" then return movement end
    return nil
end

local function MovementGrounded(movement)
    local ok, grounded = pcall(function() return movement.DataRegistry:Get("Grounded") end)
    return ok and grounded == true
end

local function StepDirect()
    local movement = GetMovement()
    if not movement then return end
    local grounded = MovementGrounded(movement)

    if movement.CanJump == false then
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

-- ---------- Input ----------
local function HumanoidGrounded()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function SendSpace(down)
    pcall(function() VirtualInputManager:SendKeyEvent(down, SPACE, false, game) end)
end

local function StepInput()
    -- Lepas di frame 1, tekan lagi di frame 3: di antaranya loop JumpReact game sempat membuka CanJump.
    if pulseStep > 0 then
        pulseStep = pulseStep + 1
        if pulseStep == 3 then
            SendSpace(true)
            pulseStep = 0
            jumpStarted, wasAirborne = os.clock(), false
        end
        return
    end

    local grounded = HumanoidGrounded()
    if not jumpStarted then jumpStarted, wasAirborne = os.clock(), false end
    if not grounded then wasAirborne = true return end
    if wasAirborne or os.clock() - jumpStarted > RELOCK_TIMEOUT then
        SendSpace(false)
        pulseStep = 1
    end
end

local function Step()
    -- Saat mode Input sedang mengirim lepas -> tekan, IsKeyDown(Space) sesaat false karena kiriman sendiri.
    if pulseStep == 0 and (not UserInputService:IsKeyDown(SPACE) or UserInputService:GetFocusedTextBox()) then
        jumpStarted = nil
        return
    end
    if AutoJump.Mode == "Direct" then StepDirect() else StepInput() end
end

local function PickMode()
    if GetMovement() then return "Direct" end
    local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if ok and vim then
        VirtualInputManager = vim
        return "Input"
    end
    return nil
end

function AutoJump.Available()
    return PickMode() ~= nil
end

-- Mengembalikan: berhasil, pesan (kalau gagal).
function AutoJump.SetEnabled(state)
    if state then
        AutoJump.Mode = PickMode()
        if not AutoJump.Mode then
            AutoJump.Enabled = false
            return false, "Your executor cannot read Evade's movement script or send key presses, so Auto Jump is not available."
        end
    end
    AutoJump.Enabled = state
    jumpStarted, pulseStep = nil, 0
    if state and not connection then
        connection = RunService.Heartbeat:Connect(function()
            local ok, err = pcall(Step)
            if not ok then warn("[Mugiwara HUB] Auto Jump error: " .. tostring(err)) end
        end)
    elseif not state and connection then
        connection:Disconnect()
        connection = nil
    end
    return true
end

getgenv().MugiwaraRegisterCleanup(function()
    AutoJump.SetEnabled(false)
end)

return AutoJump
