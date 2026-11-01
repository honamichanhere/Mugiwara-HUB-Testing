-- require() pada modul game dari executor yang menjalankan script di konteks RobloxScript (Xeno memakai modul
-- CoreGui sebagai "tuan rumah") menandai modul itu sebagai milik konteks tersebut. Sesudah itu game sendiri
-- gagal memuatnya ("Cannot require a RobloxScript module from a non RobloxScript context"): Registry item game
-- me-require semua item, jadi satu require(Registry) dari sini merusak semuanya, karakter tidak jadi dimuat dan
-- avatar hilang. Modul ini satu-satunya jalan hub membaca modul item game: di executor seperti itu require
-- tidak pernah dijalankan.
local ModuleGuard = {}

local RESTRICTED_EXECUTORS = { "xeno" }

ModuleGuard.Restricted = false
pcall(function()
    local name = identifyexecutor and identifyexecutor()
    if type(name) ~= "string" then return end
    name = string.lower(name)
    for _, restricted in ipairs(RESTRICTED_EXECUTORS) do
        if string.find(name, restricted, 1, true) then ModuleGuard.Restricted = true end
    end
end)

-- Sama seperti pcall(require, module); di executor terbatas selalu gagal tanpa menjalankan apa pun.
function ModuleGuard.Require(module)
    if ModuleGuard.Restricted then return false, "reading game modules is disabled on this executor" end
    return pcall(require, module)
end

return ModuleGuard
