require "SuQingMFSFixedBuyback/Core"
local P = SuQingMFSFixedBuyback

local recent = setmetatable({}, { __mode = "k" })
local MAX_RECENT = 64

local function acknowledge(player, ok, reason, quantity, total, typeCount, requestId)
    local money = 0
    if MFSTrade and MFSTrade.GetMoney then
        local got, value = pcall(MFSTrade.GetMoney, player)
        if got and type(value) == "number" then money = value end
    end
    if sendServerCommand then
        pcall(sendServerCommand, player, P.Module, P.Ack, {
            accepted = ok == true, reason = reason, quantity = quantity or 0,
            total = total or 0, money = money, typeCount = typeCount or 0,
            requestId = requestId,
        })
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= P.Module or (command ~= "Sell" and command ~= "SellAll") or not player then return end
    if type(args) ~= "table" then
        acknowledge(player, false, "invalid_request", 0, 0)
        return
    end
    local requestId = args.requestId
    if requestId ~= nil and (type(requestId) ~= "string" or #requestId < 1 or #requestId > 128) then
        acknowledge(player, false, "invalid_request", 0, 0)
        return
    end
    local bucket
    if requestId then
        bucket = recent[player]
        if not bucket then
            bucket = { order = {}, entries = {} }
            recent[player] = bucket
        end
        local previous = bucket.entries[requestId]
        if previous then
            -- An identifier belongs to one request, even after inventory changes.
            if previous.command ~= command or (command == "Sell" and
                (previous.itemType ~= args.itemType or previous.mode ~= args.mode)) then
                acknowledge(player, false, "invalid_request", 0, 0, 0, requestId)
            else
                acknowledge(player, previous.ok, previous.reason, previous.quantity,
                    previous.total, previous.typeCount, requestId)
            end
            return
        end
    end
    local ran, ok, reason, quantity, total, typeCount
    if command == "SellAll" then
        ran, ok, reason, quantity, total, typeCount = pcall(P.SellAll, player)
    else
        ran, ok, reason, quantity, total, typeCount = pcall(P.Sell, player, args.itemType, args.mode)
    end
    if not ran then
        ok, reason, quantity, total, typeCount = false, "transaction_error", 0, 0, 0
    end
    if bucket then
        if #bucket.order >= MAX_RECENT then
            local oldest = table.remove(bucket.order, 1)
            bucket.entries[oldest] = nil
        end
        bucket.order[#bucket.order + 1] = requestId
        bucket.entries[requestId] = { command = command, itemType = args.itemType, mode = args.mode,
            ok = ok, reason = reason, quantity = quantity, total = total, typeCount = typeCount }
    end
    acknowledge(player, ok, reason, quantity, total, typeCount, requestId)
end

if not P._serverRegistered and Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(onClientCommand)
    P._serverRegistered = true
end
