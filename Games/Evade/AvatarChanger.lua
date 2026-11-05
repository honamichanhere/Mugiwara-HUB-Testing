-- Avatar Changer dipakai bersama dengan Universal, jadi logikanya ada di Manager/AvatarChanger.lua.
-- Di sini hanya menentukan rig mana yang diubah: rig yang sedang dipakai main di Workspace.Rigs
-- (Evade punya dua rig bernama sama, inventory + in-game), lewat Games/Evade/Rigs.lua.
local AvatarChanger = getgenv().MugiwaraImport("Manager/AvatarChanger.lua")
local RigsModule = getgenv().MugiwaraImport("Games/Evade/Rigs.lua")

if AvatarChanger and RigsModule then
    AvatarChanger.SetRigProvider(RigsModule.GetActive)
end

return AvatarChanger
