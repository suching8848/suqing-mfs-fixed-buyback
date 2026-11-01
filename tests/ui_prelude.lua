-- Offline Kahlua UI doubles. Native Java UI layout/rendering is not emulated.
SFB_UITest = { now = 100000, screenW = 1280, screenH = 720, fontH = 16,
    sent = {}, drawCalls = {}, rowCalls = 0, radio = true, failSend = false,
    callbacks = {}, results = {}, legacyBuyCalls = 0, goodsCalls = 0, network = true, localTradeCalls = 0 }
local T = SFB_UITest

function require(_) return true end
function isServer() return false end
function isClient() return T.network end
function getTimeInMillis() return T.now end
function getTimestampMs() return T.now end
function getTexture(name)
    return { name = name, getWidth = function() return 32 end, getHeight = function() return 32 end }
end
function getText(key) return (T.text and T.text[key]) or key end
UIFont = { Small = "Small", Medium = "Medium", Large = "Large" }
local manager = {}
function manager:getFontHeight(_) return T.fontH end
function manager:MeasureStringX(_, value)
    -- Measure codepoints conservatively; this is an adjustable font double,
    -- not an assertion about native glyph metrics or font rasterization.
    local text = tostring(value or "")
    local count = 0
    for index = 1, #text do
        local byte = string.byte(text, index)
        if byte < 128 or byte >= 192 then count = count + 1 end
    end
    return count * math.ceil(T.fontH * 0.6)
end
function getTextManager() return manager end
function getCore()
    return { getScreenWidth = function() return T.screenW end,
        getScreenHeight = function() return T.screenH end }
end
T.player = { data = { MFSTrade_Money = 10000 } }
function T.player:getModData() return self.data end
function getPlayer() if T.noPlayer then return nil end; return T.player end
function sendClientCommand(player, module, command, args)
    if T.failSend then error("simulated transport failure") end
    T.sent[#T.sent + 1] = { player = player, module = module, command = command, args = args }
end
Events = { OnServerCommand = {} }
function Events.OnServerCommand.Add(fn) T.callbacks[#T.callbacks + 1] = fn end
function T.emit(module, command, args)
    for _, fn in ipairs(T.callbacks) do fn(module, command, args) end
end

local function class(name, parent)
    local result = { Type = name }
    result.__index = result
    setmetatable(result, { __index = parent })
    function result:derive(childName) return class(childName, self) end
    return result
end

ISPanel = class("ISPanel")
function ISPanel:new(x, y, width, height)
    local object = { x = x, y = y, width = width, height = height, visible = true,
        children = {}, borderColor = {}, backgroundColor = {}, backgroundColorMouseOver = {},
        yScroll = 0, scrollHeight = 0 }
    setmetatable(object, self)
    return object
end
function ISPanel:initialise() self.children = {} end
function ISPanel:instantiate()
    if self.javaObject then return end
    self.javaObject = { offline = true }
    self:createChildren()
end
function ISPanel:createChildren() end
function ISPanel:addToUIManager() self:instantiate(); self._added = true end
function ISPanel:removeFromUIManager() self._added = false end
function ISPanel:addChild(child) self.children[#self.children + 1] = child; child.parent = self end
function ISPanel:removeChild(child)
    for i = #self.children, 1, -1 do
        if self.children[i] == child then table.remove(self.children, i) end
    end
end
function ISPanel:setVisible(value) self.visible = value end
function ISPanel:getIsVisible() return self.visible end
function ISPanel:getX() return self.x end
function ISPanel:getY() return self.y end
function ISPanel:getWidth() return self.width end
function ISPanel:getHeight() return self.height end
function ISPanel:setX(value) self.x = value end
function ISPanel:setY(value) self.y = value end
function ISPanel:setWidth(value) self.width = value end
function ISPanel:setHeight(value) self.height = value end
function ISPanel:bringToTop() end
function ISPanel:update() end
function ISPanel:prerender() end
function ISPanel:render() end
function ISPanel:setImage(texture) self.image = texture end
function ISPanel:getYScroll() return self.yScroll end
function ISPanel:setYScroll(value) self.yScroll = value end
function ISPanel:setScrollHeight(value) self.scrollHeight = value end
function ISPanel:getScrollHeight() return self.scrollHeight end
function ISPanel:isVScrollBarVisible() return self.scrollHeight > self.height end
local function recordDraw(self, method, ...)
    T.drawCalls[#T.drawCalls + 1] = { owner = self, method = method, args = { ... } }
end
for _, name in ipairs({ "drawRect", "drawRectBorder", "drawText", "drawTextRight", "drawTextCentre", "drawTextureScaled" }) do
    local method = name
    ISPanel[method] = function(self, ...) recordDraw(self, method, ...) end
end

ISButton = class("ISButton", ISPanel)
function ISButton:new(x, y, width, height, title, target, callback)
    local object = ISPanel.new(self, x, y, width, height)
    object.title, object.target, object.callback = title, target, callback
    return object
end
function ISButton:onMouseDown(_, _) end
function ISButton:onMouseUp(_, _) end
function ISButton:setTitle(value) self.title = value end
function ISButton:setEnable(value) self.enable = value end

ISScrollingListBox = class("ISScrollingListBox", ISPanel)
function ISScrollingListBox:new(x, y, width, height)
    local object = ISPanel.new(self, x, y, width, height)
    object.items, object.count, object.selected, object.itemheight = {}, 0, 1, 40
    return object
end
function ISScrollingListBox:addItem(text, row, tooltip)
    local item = { text = text, item = row, tooltip = tooltip,
        itemindex = self.count + 1, height = self.itemheight }
    self.items[#self.items + 1] = item
    self.count = self.count + 1
    self.scrollHeight = self.scrollHeight + item.height
    return item
end
function ISScrollingListBox:clear() self.items = {}; self.count = 0; self.scrollHeight = 0 end
-- These coordinate semantics match current vanilla: rowAt receives content Y;
-- native event delivery already accounts for the scroll offset.
function ISScrollingListBox:rowAt(_, y)
    local top = 0
    for index, item in ipairs(self.items) do
        if y >= top and y < top + item.height then return index end
        top = top + item.height
    end
    return -1
end
function ISScrollingListBox:topOfItem(index)
    local y = 0
    for key, item in ipairs(self.items) do
        if key == index then return y end
        y = y + item.height
    end
    return -1
end
function ISScrollingListBox:isMouseOverScrollBar() return self._mouseOverScrollBar == true end
function ISScrollingListBox:onMouseDown(x, y)
    local row = self:rowAt(x, y)
    if row >= 1 then self.selected = row end
end
function ISScrollingListBox:onMouseUp(_, _) end
function ISScrollingListBox:onMouseUpOutside(_, _) end

ISTickBox = class("ISTickBox", ISPanel)
function ISTickBox:new(x, y, width, height, name, target, callback)
    local object = ISPanel.new(self, x, y, width, height)
    object.name, object.target, object.callback, object.options, object.selected = name, target, callback, {}, {}
    return object
end
function ISTickBox:addOption(value) self.options[#self.options + 1] = value end
function ISTickBox:setSelected(index, value) self.selected[index] = value end
function ISTickBox:isSelected(index) return self.selected[index] == true end

ISComboBox = class("ISComboBox", ISPanel)
function ISComboBox:new(x, y, width, height, target, callback)
    local object = ISPanel.new(self, x, y, width, height)
    object.target, object.callback, object.options, object.selected = target, callback, {}, 1
    return object
end
function ISComboBox:addOption(value) self.options[#self.options + 1] = value end
function ISComboBox:hidePopup() self._popupHidden = true end

ScriptManager = { instance = {} }
function ScriptManager.instance:getItem(ft)
    local names = T.names or {}
    return { getDisplayName = function() return names[ft] or ft end,
        getIcon = function() return "OfflineIcon" end }
end

MFSTrade = { MODULE = "MFSTrade", ACK = "TradeResult", CMD_BUY = "Buy", CMD_SELL = "Sell",
    CMD_MONEY = "RequestMoney", CMD_SEED = "RequestSeed", MoneyKey = "MFSTrade_Money" }
function MFSTrade.IsEnabled() return not T.disabled end
function MFSTrade.HasRadio(_) return T.radio end
function MFSTrade.GetMoney(player) return player and player.data.MFSTrade_Money or 0 end
function MFSTrade.GetEffectiveSeed() return T.seed or 1001 end
function MFSTrade.GetRefreshRemainingHours() return 11.5 end
function MFSTrade.BuildBuyList(_)
    T.legacyBuyCalls = T.legacyBuyCalls + 1
    return { { itemType = "Base.Pen", count = 1, price = 100 } }
end
function MFSTrade.BuildSellList(_)
    T.goodsCalls = T.goodsCalls + 1
    return T.goods
end
T.goods = {
    { itemType = "Base.HK416_cat", count = 1, unitPrice = 3000 },
    { itemType = "Gunpart.M203_cat", count = 1, unitPrice = 2500 },
    { itemType = "Gunpart.ipsc1_cat", count = 1, unitPrice = 1500 },
    { itemType = "Gunpart.XM157_cat", count = 1, unitPrice = 4200 },
    { itemType = "Base.HK51_cat", count = 1, unitPrice = 2000 },
    { itemType = "Gunpart.WB_SST", count = 1, unitPrice = 1700 },
    { itemType = "Gunpart.HeraCQR_Stock", count = 1, unitPrice = 1900 },
}
SandboxVars = { SuQingMFSFixedBuyback = {} }

function T.check(condition, message)
    if not condition then error(message or "assertion failed") end
end
function T.equal(actual, expected, message)
    T.check(actual == expected, (message or "mismatch") .. ": actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
function T.test(name, fn)
    local ok, result = pcall(fn)
    T.results[#T.results + 1] = { name = name, passed = ok, error = ok and nil or tostring(result) }
    print("SFB_UI_TEST|" .. name .. "|" .. (ok and "PASS" or "FAIL") .. "|" .. (ok and "" or tostring(result)))
end
