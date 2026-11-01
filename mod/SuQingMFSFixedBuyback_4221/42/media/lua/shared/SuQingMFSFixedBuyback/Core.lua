require "SuQingMFSFixedBuyback/Catalog"

SuQingMFSFixedBuyback = SuQingMFSFixedBuyback or {}
local P = SuQingMFSFixedBuyback
if P._coreLoaded then return P end
P._coreLoaded = true
P.Module = "SuQingMFSFixedBuyback"
P.Ack = "Result"

local MAX_SAFE = 9007199254740991
local MAX_UNITS = 1000000
local MAX_VISITS = 100000
local CATEGORY_ORDER = { currency = 1, jewelry = 2, gems = 3, watches = 4, metals = 5 }
local CATEGORY_OPTIONS = { jewelry = "Jewelry", gems = "Gems", watches = "Watches", metals = "Metals" }
local inFlight = setmetatable({}, { __mode = "k" })
local catalog, byType

local function integer(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high
        and value == math.floor(value)
end

local function sandbox()
    return (SandboxVars and SandboxVars.SuQingMFSFixedBuyback) or {}
end

function P.GetOptions()
    return { onlyOwned = false }
end

function P.IsEnabled()
    if sandbox().Enabled == false then return false end
    return MFSTrade ~= nil and type(MFSTrade.IsEnabled) == "function" and MFSTrade.IsEnabled()
end

local function activeCategory(category)
    if category == "currency" then return true end
    local option = CATEGORY_OPTIONS[category]
    return option ~= nil and sandbox()[option] ~= false
end

-- Freeze the explicit catalog once. No category, tag or display-name scan can
-- introduce another mod's item into the server's allowlist.
function P.RefreshCatalog()
    local nextCatalog, nextByType = {}, {}
    for _, source in ipairs(P.Catalog or {}) do
        local ft, category, price = source.itemType, source.category, source.price
        if type(ft) == "string" and ft:sub(1, 5) == "Base." and CATEGORY_ORDER[category]
            and integer(price, 1, MAX_SAFE) and not nextByType[ft] then
            local script
            if ScriptManager and ScriptManager.instance then
                local ok, result = pcall(function() return ScriptManager.instance:getItem(ft) end)
                if ok then script = result end
            end
            -- Without a ScriptManager the catalog can still be inspected by the
            -- offline harness; a live manager must recognize every retained ID.
            if script or not (ScriptManager and ScriptManager.instance) then
                local name = type(source.displayName) == "string" and source.displayName or ft
                if script and script.getDisplayName then
                    local ok, result = pcall(function() return script:getDisplayName() end)
                    if ok and type(result) == "string" and result ~= "" then name = result end
                end
                local record = { itemType = ft, category = category, price = price, displayName = name }
                nextCatalog[#nextCatalog + 1] = record
                nextByType[ft] = record
            end
        end
    end
    table.sort(nextCatalog, function(a, b)
        local ac, bc = CATEGORY_ORDER[a.category], CATEGORY_ORDER[b.category]
        if ac ~= bc then return ac < bc end
        return a.itemType < b.itemType
    end)
    catalog, byType = nextCatalog, nextByType
    return #catalog
end

local function ensureCatalog()
    if not catalog then P.RefreshCatalog() end
end

function P.GetUnitPrice(ft)
    ensureCatalog()
    local record = byType[ft]
    if not record or not activeCategory(record.category) then return nil end
    local multiplier = sandbox().PriceMultiplier
    if type(multiplier) ~= "number" or multiplier ~= multiplier or multiplier <= 0 or multiplier > 1000000 then
        multiplier = 1
    end
    local price = math.floor(record.price * multiplier + 0.5)
    if not integer(price, 1, MAX_SAFE) then return nil end
    return price
end

local function favorite(item)
    return item.isFavorite and item:isFavorite() == true
end

local function equipped(player, item)
    if player.isEquipped and player:isEquipped(item) then return true end
    if player.isEquippedClothing and player:isEquippedClothing(item) then return true end
    if player.getPrimaryHandItem and player:getPrimaryHandItem() == item then return true end
    if player.getSecondaryHandItem and player:getSecondaryHandItem() == item then return true end
    return false
end

local function countOf(item)
    local count = item.getCount and item:getCount() or 1
    if not integer(count, 1, MAX_UNITS) then return nil end
    return count
end

local function childInventory(item)
    if instanceof and instanceof(item, "InventoryContainer") and item.getInventory then
        return item:getInventory()
    end
    return nil
end

-- The row list uses one traversal for the entire allowlist. An equipped bag is
-- traversed normally; a favorite bag protects all its contents.
local function collect(player, requestedType, allCandidates)
    ensureCatalog()
    local counts, candidates, visited = {}, {}, {}
    local visits = 0
    local function visit(inv, depth)
        if not inv or visited[inv] then return end
        if depth > 32 then error("inventory_depth") end
        visited[inv] = true
        local items = inv:getItems()
        local size = items:size()
        for index = 0, size - 1 do
            visits = visits + 1
            if visits > MAX_VISITS then error("inventory_limit") end
            local item = items:get(index)
            if item and not favorite(item) then
                local nested = childInventory(item)
                local ft = item:getFullType()
                if (not requestedType or ft == requestedType) and byType[ft]
                    and P.GetUnitPrice(ft) and not equipped(player, item)
                    and (not nested or nested:getItems():size() == 0) then
                    local count = countOf(item)
                    if not count then error("invalid_item_count") end
                    local total = (counts[ft] or 0) + count
                    if total > MAX_UNITS then error("quantity_limit") end
                    counts[ft] = total
                    if requestedType or allCandidates then
                        candidates[#candidates + 1] = { item = item, itemType = ft, inventory = inv, count = count }
                    end
                end
                if nested then visit(nested, depth + 1) end
            end
        end
    end
    if player and player.getInventory then visit(player:getInventory(), 0) end
    return counts, candidates
end

function P.GetEligibleCount(player, ft)
    if not P.GetUnitPrice(ft) then return 0 end
    local ok, counts = pcall(collect, player, ft)
    if not ok then return 0, tostring(counts) end
    return counts[ft] or 0
end

function P.GetRows(player, onlyOwned)
    ensureCatalog()
    local counts = {}
    if player then
        local ok, result = pcall(collect, player)
        if ok then counts = result end
    end
    local rows = {}
    for _, record in ipairs(catalog) do
        local price = P.GetUnitPrice(record.itemType)
        local available = counts[record.itemType] or 0
        if price and (not onlyOwned or available > 0) then
            rows[#rows + 1] = { itemType = record.itemType, count = 1, price = price,
                category = record.category, available = available, displayName = record.displayName }
        end
    end
    return rows
end

local function contains(inv, item)
    return inv:getItems():contains(item)
end

local function rollback(changes)
    local restored = true
    for i = #changes, 1, -1 do
        local change = changes[i]
        local ok = pcall(function()
            if change.item.setCount then change.item:setCount(change.count) end
            if not contains(change.inventory, change.item) then change.inventory:AddItem(change.item) end
            if not contains(change.inventory, change.item) or countOf(change.item) ~= change.count then
                error("restore_failed")
            end
        end)
        if not ok then restored = false end
    end
    return restored
end

local function sync(changes)
    if not (isServer and isServer()) then return end
    for _, change in ipairs(changes) do
        if change.take == change.count then
            if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, change.inventory, change.item) end
        elseif sendItemStats then
            pcall(sendItemStats, change.item)
        end
    end
end

local function preflight(player, changes)
    for _, change in ipairs(changes) do
        if not contains(change.inventory, change.item) or favorite(change.item)
            or equipped(player, change.item) or countOf(change.item) ~= change.count then
            return false, "inventory_changed"
        end
    end
    return true
end

local function selectItems(player, ft, quantity)
    local counts, candidates = collect(player, ft)
    if (counts[ft] or 0) < quantity then return nil, "not_enough_items" end
    local changes, remaining = {}, quantity
    for _, candidate in ipairs(candidates) do
        if remaining <= 0 then break end
        candidate.take = math.min(candidate.count, remaining)
        changes[#changes + 1] = candidate
        remaining = remaining - candidate.take
    end
    -- Complete the preflight before changing the first item.
    local valid, why = preflight(player, changes)
    if not valid then return nil, why end
    return changes
end

local function removeSelected(changes)
    local touched = {}
    local ok, reason = pcall(function()
        for _, change in ipairs(changes) do
            touched[#touched + 1] = change
            if change.take == change.count then
                change.inventory:DoRemoveItem(change.item)
                if contains(change.inventory, change.item) then error("remove_failed") end
            else
                change.item:setCount(change.count - change.take)
                if countOf(change.item) ~= change.count - change.take then error("count_failed") end
            end
        end
    end)
    if not ok then
        local restored = rollback(touched)
        return false, restored and "remove_failed" or "rollback_failed"
    end
    return true
end

local function balance(player)
    local value = MFSTrade.GetMoney(player)
    if not integer(value, 0, MAX_SAFE) then return nil end
    return value
end

local function safeTotal(player, price, quantity)
    local money = balance(player)
    if money == nil or not integer(quantity, 1, MAX_UNITS)
        or price > math.floor((MAX_SAFE - money) / quantity) then return nil end
    return price * quantity, money
end

local function commit(player, changes, payout, before)
    local paymentData = player:getModData()
    local paymentKey = MFSTrade.MoneyKey
    if not paymentData or type(paymentKey) ~= "string" then return false, "invalid_balance" end
    local valid, why = preflight(player, changes)
    if not valid then return false, why end
    local removed, removeReason = removeSelected(changes)
    if not removed then return false, removeReason end
    local paid = pcall(function()
        if balance(player) ~= before then error("balance_changed") end
        MFSTrade.GiveMoney(player, payout)
        if balance(player) ~= before + payout then error("payment_failed") end
    end)
    if not paid then
        local restoredMoney = pcall(function() paymentData[paymentKey] = before end)
        local restored = rollback(changes)
        return false, (restored and restoredMoney) and "payment_failed" or "rollback_failed"
    end
    pcall(sync, changes)
    return true
end

-- Authoritative transaction used by the new one/all command. The existing
-- MFSTrade balance is credited only after every selected item was removed.
function P.Sell(player, ft, mode)
    if not player or not player.getInventory then return false, "invalid_player", 0, 0, 0 end
    if isClient and isClient() and not (isServer and isServer()) then return false, "server_only", 0, 0, 0 end
    if inFlight[player] then return false, "busy", 0, 0, 0 end
    if type(ft) ~= "string" or #ft > 160 or (mode ~= "one" and mode ~= "all") then
        return false, "invalid_request", 0, 0, 0
    end
    if not P.IsEnabled() then return false, "disabled", 0, 0, 0 end
    local price = P.GetUnitPrice(ft)
    if not price then return false, "not_allowed", 0, 0, 0 end
    if not MFSTrade.HasRadio(player) then return false, "no_radio", 0, 0, 0 end
    inFlight[player] = true
    local ran, accepted, reason, quantity, total = pcall(function()
        local count = P.GetEligibleCount(player, ft)
        local amount = mode == "one" and 1 or count
        if amount < 1 then return false, "not_enough_items", 0, 0 end
        local payout, before = safeTotal(player, price, amount)
        if not payout then return false, "balance_limit", 0, 0 end
        local changes, why = selectItems(player, ft, amount)
        if not changes then return false, why, 0, 0 end
        local committed, commitReason = commit(player, changes, payout, before)
        if not committed then return false, commitReason, 0, 0 end
        return true, nil, amount, payout
    end)
    inFlight[player] = nil
    if not ran then return false, "transaction_error", 0, 0, 0 end
    return accepted, reason, quantity, total, accepted and 1 or 0
end

-- One inventory snapshot and one atomic payment for all eligible catalog types.
-- UI category/owned filters and client-provided prices cannot change this plan.
function P.SellAll(player)
    if not player or not player.getInventory then return false, "invalid_player", 0, 0, 0 end
    if isClient and isClient() and not (isServer and isServer()) then return false, "server_only", 0, 0, 0 end
    if inFlight[player] then return false, "busy", 0, 0, 0 end
    if not P.IsEnabled() then return false, "disabled", 0, 0, 0 end
    if not MFSTrade.HasRadio(player) then return false, "no_radio", 0, 0, 0 end
    inFlight[player] = true
    local ran, accepted, reason, quantity, total, typeCount = pcall(function()
        local before = balance(player)
        if before == nil then return false, "invalid_balance", 0, 0, 0 end
        local counts, changes = collect(player, nil, true)
        local amount, payout, kinds = 0, 0, 0
        for ft, count in pairs(counts) do
            local price = P.GetUnitPrice(ft)
            if not price or amount > MAX_UNITS - count then return false, "quantity_limit", 0, 0, 0 end
            -- Subtract before multiplying so every intermediate stays exact.
            if price > math.floor((MAX_SAFE - before - payout) / count) then
                return false, "balance_limit", 0, 0, 0
            end
            amount, payout, kinds = amount + count, payout + price * count, kinds + 1
        end
        if amount < 1 then return false, "not_enough_items", 0, 0, 0 end
        for _, change in ipairs(changes) do change.take = change.count end
        local committed, why = commit(player, changes, payout, before)
        if not committed then return false, why, 0, 0, 0 end
        return true, nil, amount, payout, kinds
    end)
    inFlight[player] = nil
    if not ran then return false, "transaction_error", 0, 0, 0 end
    return accepted, reason, quantity, total, typeCount
end

function P.EnsureHooks()
    if not MFSTrade then
        local ok = pcall(require, "Trade/TradeShared")
        if not ok or not MFSTrade then return false end
    end
    if type(MFSTrade.BuildBuyList) ~= "function" or type(MFSTrade.TakeItem) ~= "function" then return false end
    if MFSTrade.BuildBuyList ~= P._buyListHook then
        local original = MFSTrade.BuildBuyList
        P._originalBuildBuyList = original
        P._buyListHook = function(seed)
            if not P.IsEnabled() then return original(seed) end
            return P.GetRows(nil, false)
        end
        MFSTrade.BuildBuyList = P._buyListHook
    end
    if MFSTrade.TakeItem ~= P._takeItemHook then
        local original = MFSTrade.TakeItem
        P._originalTakeItem = original
        P._takeItemHook = function(player, ft, quantity)
            if not P.IsEnabled() then return original(player, ft, quantity) end
            if not player or not player.getInventory then return false end
            local price = P.GetUnitPrice(ft)
            if not price or not integer(quantity, 1, MAX_UNITS) or inFlight[player] then return false end
            if not safeTotal(player, price, quantity) then return false end
            inFlight[player] = true
            local ran, result = pcall(function()
                local changes = selectItems(player, ft, quantity)
                if not changes or not removeSelected(changes) then return false end
                pcall(sync, changes)
                return true
            end)
            inFlight[player] = nil
            return ran and result == true
        end
        MFSTrade.TakeItem = P._takeItemHook
    end
    return true
end

return P
