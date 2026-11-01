require "SuQingMFSFixedBuyback/Core"
local P = SuQingMFSFixedBuyback

local function install()
    P.RefreshCatalog()
    P.EnsureHooks()
end

if not P._bootstrapRegistered then
    if Events and Events.OnGameBoot then Events.OnGameBoot.Add(install) end
    if Events and Events.OnGameStart then Events.OnGameStart.Add(install) end
    P._bootstrapRegistered = true
end

P.EnsureHooks()
