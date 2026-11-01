Test = { assertions = 0, cases = 0, hours = 0, syncs = 0 }
function Test.eq(actual, expected, message)
    Test.assertions = Test.assertions + 1
    if actual ~= expected then error((message or "equality") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
function Test.ok(value, message) Test.eq(not not value, true, message) end
function Test.case(name, fn)
    fn()
    Test.cases = Test.cases + 1
    print("PASS " .. name)
end
function require(name) return true end
Events = {}
for _, name in ipairs({"OnClientCommand", "OnGameBoot", "OnGameStart"}) do
    local handlers = {}
    Events[name] = { handlers = handlers, Add = function(fn) handlers[#handlers + 1] = fn end }
end
function isServer() return false end
function isClient() return false end
function instanceof(item, name) return item and item.kind == name end
function getGameTime() return { getWorldAgeHours = function() return Test.hours end } end
function ZombRand(a, b) return a end
ItemTag = { FIREARM = "firearm" }
SandboxVars = { MFSTrade = { Enabled = true } }
function Test.list(items)
    return {
        size = function() return #items end,
        get = function(self, i) return items[i + 1] end,
        contains = function(self, value) for _, item in ipairs(items) do if item == value then return true end end return false end,
    }
end
function Test.item(ft, count)
    local item = { ft = ft, count = count or 1, kind = "InventoryItem" }
    function item:getFullType() return self.ft end
    function item:getType() return string.sub(self.ft, 6) end
    function item:getCount() return self.count end
    function item:setCount(value) if self.failCount then error("injected count failure") end self.count = value end
    function item:isFavorite() return self.favorite == true end
    function item:getContainer() return self.container end
    return item
end
function Test.inventory(items)
    local inv = { items = {}, removals = 0 }
    function inv:getItems() return Test.list(self.items) end
    function inv:AddItem(item)
        if type(item) == "string" then item = Test.item(item) end
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function inv:DoRemoveItem(item)
        self.removals = self.removals + 1
        if self.failRemoval == self.removals then error("injected removal failure") end
        if self.ignoreRemoval then return end
        for i, existing in ipairs(self.items) do
            if existing == item then table.remove(self.items, i) item.container = nil return end
        end
    end
    function inv:getItemCountRecurse(ft)
        local count = 0
        for _, item in ipairs(self.items) do
            if item.ft == ft then count = count + item.count end
            if item.kind == "InventoryContainer" then count = count + item.inventory:getItemCountRecurse(ft) end
        end
        return count
    end
    for _, item in ipairs(items or {}) do inv:AddItem(item) end
    return inv
end
function Test.bag(items, favorite)
    local item = Test.item("Base.Bag_ALICEpack")
    item.kind, item.favorite, item.inventory = "InventoryContainer", favorite, Test.inventory(items)
    function item:getInventory() return self.inventory end
    return item
end
function Test.player(items)
    local p = { inventory = Test.inventory(items), data = {}, worn = {} }
    function p:getInventory() return self.inventory end
    function p:getModData() return self.data end
    function p:isEquipped(item) return self.primary == item or self.secondary == item or self.worn[item] == true end
    function p:isEquippedClothing(item) return self.worn[item] == true end
    function p:getPrimaryHandItem() return self.primary end
    function p:getSecondaryHandItem() return self.secondary end
    p.inventory:AddItem(Test.item("Base.WalkieTalkie1"))
    return p
end
function sendRemoveItemFromContainer(inv, item) Test.syncs = Test.syncs + 1 end
function sendItemStats(item) Test.syncs = Test.syncs + 1 end
function sendAddItemToContainer(inv, item) Test.syncs = Test.syncs + 1 end
function sendServerCommand(player, module, command, args)
    Test.ack = { player = player, module = module, command = command, args = args }
end
function instanceItem(ft)
    local item = Test.item(ft)
    item.kind = "WeaponPart"
    function item:getPartType() return "Scope" end
    return item
end
ScriptManager = { instance = {} }
function ScriptManager.instance:getItem(ft)
    if ft == "Base.DoesNotExist" then return nil end
    return { getDisplayName = function() return ft end }
end
function getAllItems()
    local all = {}
    for i = 1, 12 do
        local name = "TestRifle" .. i
        all[#all + 1] = {
            getModuleName = function() return "Base" end,
            getFullName = function() return "Base." .. name end,
            getName = function() return name end,
            hasTag = function() return true end,
            getDisplayCategory = function() return "Weapon" end,
        }
    end
    all[#all + 1] = {
        getModuleName = function() return "Base" end,
        getFullName = function() return "Base.RareMemento" end,
        getName = function() return "RareMemento" end,
        hasTag = function() return false end,
        getDisplayCategory = function() return "Memento" end,
    }
    return Test.list(all)
end
