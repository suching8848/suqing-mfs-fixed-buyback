-- Independent MFS buyback UI. No Workshop source is replaced.
if isServer and isServer() then return end

require "SuQingMFSFixedBuyback/Core"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
require "UI/risky_trade"

local P = SuQingMFSFixedBuyback
if P._uiInstalled or not riskyTradeUI then return end
P._uiInstalled = true
P.UI = P.UI or {}
local UI = P.UI
UI.onlyOwned = UI.onlyOwned ~= false
UI.category = UI.category or "all"
local categories = { "all", "currency", "jewelry", "gems", "watches", "metals" }
local originalRebuild = riskyTradeUI.rebuildLists
local originalPrerender = riskyTradeUI.prerender
local originalUpdate = riskyTradeUI.update
local originalRefresh = riskyTradeUI.refresh
local originalTrade = riskyTradeUI.onTradeEntry
local originalOpen = riskyTradeUI.open
local textures = {}

local function tr(key, fallback)
    local value = getText(key)
    if not value or value == key then return fallback end
    return value
end

local function nowMs()
    if getTimeInMillis then return getTimeInMillis() end
    return (os.time() or 0) * 1000
end

local function fontHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function finite(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

-- Remove whole UTF-8 characters only, then measure using the active UI font.
function UI.ShortText(value, width)
    local text = tostring(value or "")
    local manager = getTextManager()
    if width <= 0 then return "" end
    if manager:MeasureStringX(UIFont.Small, text) <= width then return text end
    local suffix = "..."
    if manager:MeasureStringX(UIFont.Small, suffix) > width then return "" end
    while #text > 0 and manager:MeasureStringX(UIFont.Small, text .. suffix) > width do
        local position = #text
        while position > 1 do
            local byte = string.byte(text, position)
            if byte < 128 or byte >= 192 then break end
            position = position - 1
        end
        text = string.sub(text, 1, position - 1)
    end
    return text .. suffix
end

local function displayData(row)
    local script = ScriptManager.instance and ScriptManager.instance:getItem(row.itemType)
    local name = row.displayName or row.itemType
    if script then
        local scriptName = script:getDisplayName()
        if scriptName and scriptName ~= "" then name = scriptName end
        if textures[row.itemType] == nil then
            local icon = script:getIcon()
            textures[row.itemType] = (icon and getTexture("media/textures/Item_" .. icon .. ".png")) or false
        end
    end
    row._sfbName = name
    row._sfbTexture = textures[row.itemType] or nil
    return row
end

function UI.ComputeLayout(width, height, lineHeight)
    local row = math.max(44, lineHeight * 2 + 14)
    local controlH = math.max(22, lineHeight + 6)
    local buyLabelY = lineHeight * 2 + 18
    local controlsY = buyLabelY + controlH + 5
    local listY = controlsY + controlH + 6
    local statusY = height - lineHeight - 9
    local labelGap, labelBelow, footerGap = 7, 5, 5
    local usable = statusY - listY - lineHeight - labelGap - labelBelow - footerGap
    -- At large font sizes on 800x480, reclaim padding before reducing either
    -- viewport. Never invent more space than the window actually contains.
    if usable < row * 2 then
        controlsY = buyLabelY + controlH + 2
        listY = controlsY + controlH + 2
        statusY = height - lineHeight - 6
        labelGap, labelBelow, footerGap = 4, 3, 3
        usable = statusY - listY - lineHeight - labelGap - labelBelow - footerGap
    end
    usable = math.max(2, usable)
    local buyH = math.max(1, math.floor(usable * 0.49))
    if usable >= row * 2 then buyH = math.max(row, math.min(usable - row, buyH)) end
    local sellLabelY = listY + buyH + labelGap
    local sellY = sellLabelY + lineHeight + labelBelow
    return { width = width, rowH = row, controlH = controlH, buyLabelY = buyLabelY,
        controlsY = controlsY, listY = listY, buyH = buyH, sellLabelY = sellLabelY,
        sellY = sellY, sellH = math.max(1, usable - buyH), statusY = statusY }
end

local function rowFingerprint(rows)
    local values = {}
    for _, row in ipairs(rows) do
        values[#values + 1] = row.itemType .. ":" .. tostring(row.available or 0) .. ":" ..
            tostring(row.price or row.unitPrice or 0)
    end
    return table.concat(values, "|")
end
UI.RowFingerprint = rowFingerprint

local TradeList = ISScrollingListBox:derive("SFB_TradeList")

function TradeList:new(x, y, width, height, owner, kind, rowHeight)
    local object = ISScrollingListBox:new(x, y, width, height)
    setmetatable(object, self)
    self.__index = self
    object.owner = owner
    object.kind = kind
    object.itemheight = rowHeight
    object.font = UIFont.Small
    object.drawBorder = true
    object.backgroundColor = { r = 0.035, g = 0.035, b = 0.035, a = 0.9 }
    object.borderColor = { r = 0.35, g = 0.35, b = 0.35, a = 0.8 }
    return object
end

function TradeList:actionGeometry()
    local right = self.width - 8
    if self:isVScrollBarVisible() then right = right - 12 end
    local label = tr("UI_SFB_SellAll", "Sell all")
    local width = math.max(46, getTextManager():MeasureStringX(UIFont.Small, label) + 14)
    width = math.min(width, math.max(28, math.floor((right - 50) * 0.30)))
    return right, width
end

function TradeList:actionAt(x, y, item)
    if not item then return nil end
    local top = self:topOfItem(item.itemindex)
    local localY = y - top
    if localY < self.itemheight - fontHeight() - 8 then return nil end
    local right, buttonWidth = self:actionGeometry()
    if x >= right - buttonWidth and x <= right then
        return self.kind == "sell" and "all" or "buy"
    end
    if self.kind == "sell" and x >= right - buttonWidth * 2 - 4 and x < right - buttonWidth - 4 then
        return "one"
    end
    return nil
end

function TradeList:onMouseDown(x, y)
    if self:isMouseOverScrollBar() then
        self._sfbArmed = nil
        return ISScrollingListBox.onMouseDown(self, x, y)
    end
    ISScrollingListBox.onMouseDown(self, x, y)
    local item = self.items[self:rowAt(x, y)]
    local action = self:actionAt(x, y, item)
    self._sfbArmed = item and action and { itemType = item.item.itemType, action = action } or nil
end

-- UIElement redirects a second press here when the list inherits the native
-- double-click handler. Treat it as another press, still requiring mouse-up.
function TradeList:onMouseDoubleClick(x, y)
    return self:onMouseDown(x, y)
end

function TradeList:onMouseUp(x, y)
    ISScrollingListBox.onMouseUp(self, x, y)
    local armed = self._sfbArmed
    self._sfbArmed = nil
    if not armed or self:isMouseOverScrollBar() then return end
    local item = self.items[self:rowAt(x, y)]
    if not item or item.item.itemType ~= armed.itemType or self:actionAt(x, y, item) ~= armed.action then return end
    self.owner:sfbTrade(item.item, armed.action)
end

function TradeList:onMouseUpOutside(x, y)
    self._sfbArmed = nil
    ISScrollingListBox.onMouseUpOutside(self, x, y)
end

function TradeList:doDrawItem(y, item)
    local row = item.item
    local line = fontHeight()
    local rowH = self.itemheight
    local visibleY = y + self:getYScroll()
    if visibleY + rowH < 0 or visibleY > self.height then return y + rowH end
    local right, buttonWidth = self:actionGeometry()
    local pending = self.owner._sfbPending ~= nil
    local enabled = not pending and (self.kind ~= "sell" or (row.available or 0) > 0)
    if self.selected == item.index then self:drawRect(1, y, self.width - 2, rowH - 1, 0.24, 0.5, 0.4, 0.16) end
    self:drawRectBorder(1, y, self.width - 2, rowH, 0.4, 0.3, 0.3, 0.3)
    local iconSize = math.min(32, rowH - 8)
    if row._sfbTexture then self:drawTextureScaled(row._sfbTexture, 5, y + 5, iconSize, iconSize, enabled and 1 or 0.45, 1, 1, 1) end
    if row._sfbNameWidth ~= right - 45 then
        row._sfbNameWidth = right - 45
        row._sfbShortName = UI.ShortText(row._sfbName, row._sfbNameWidth)
    end
    local name = row._sfbShortName
    local color = enabled and 0.95 or 0.5
    self:drawText(name, 42, y + 4, color, color, color, 1, UIFont.Small)
    local bottom = y + rowH - line - 5
    local buttonY = bottom - 2
    local function button(x, label, compact)
        if getTextManager():MeasureStringX(UIFont.Small, label) > buttonWidth - 8 then label = compact end
        label = UI.ShortText(label, buttonWidth - 8)
        self:drawRect(x, buttonY, buttonWidth, line + 4, enabled and 0.8 or 0.35, 0.12, 0.17, 0.12)
        self:drawRectBorder(x, buttonY, buttonWidth, line + 4, enabled and 0.8 or 0.35, 0.45, 0.65, 0.4)
        self:drawTextCentre(label, x + buttonWidth / 2, bottom, color, color, color, 1, UIFont.Small)
    end
    if self.kind == "sell" then
        local information = "$" .. tostring(row.price or 0) .. "  " .. tr("UI_SFB_Available", "Available") .. ":" .. tostring(row.available or 0)
        self:drawText(UI.ShortText(information, right - buttonWidth * 2 - 52), 42, bottom, 0.45, 0.95, 0.5, 1, UIFont.Small)
        button(right - buttonWidth * 2 - 4, tr("UI_SFB_SellOne", "Sell 1"), tr("UI_SFB_SellOneCompact", "1"))
        button(right - buttonWidth, tr("UI_SFB_SellAll", "Sell all"), tr("UI_SFB_SellAllCompact", "All"))
    else
        self:drawText(UI.ShortText("x" .. tostring(row.count or 1) .. "  $" .. tostring(row.unitPrice or 0), right - buttonWidth - 50),
            42, bottom, 1, 0.88, 0.35, 1, UIFont.Small)
        button(right - buttonWidth, tr("UI_SFB_Buy", "Buy"), tr("UI_SFB_BuyCompact", "Buy"))
    end
    return y + rowH
end

function TradeList:render()
    ISScrollingListBox.render(self)
    if self.kind == "sell" and #self.items == 0 then
        self:drawText(UI.ShortText(tr("UI_SFB_NoItems", "No eligible items in this view."), self.width - 16),
            8, 12, 0.65, 0.65, 0.65, 1, UIFont.Small)
        self:drawText(UI.ShortText(tr("UI_SFB_ShowAllHint", "Uncheck owned-only to view the full catalog."), self.width - 16),
            8, 16 + fontHeight(), 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
end

local function removeControls(window)
    for _, name in ipairs({ "sfbSaleList", "sfbPurchaseList", "sfbOwned", "sfbCategory", "sfbSellEverything" }) do
        local control = window[name]
        if control then
            if control.hidePopup then control:hidePopup() end
            window:removeChild(control)
            window[name] = nil
        end
    end
end

local function refill(list, rows, signature)
    if list._sfbSignature == signature then return end
    local selected = list.items[list.selected]
    local selectedType = selected and selected.item.itemType
    local scroll = list:getYScroll()
    list:clear()
    local selectedIndex = 1
    for index, row in ipairs(rows) do
        displayData(row)
        local tooltip = row._sfbName
        if list.kind == "sell" then
            tooltip = tooltip .. "\n" .. tr("UI_SFB_AllIncome", "Sell-all income") .. ": $" .. tostring((row.price or 0) * (row.available or 0))
        end
        list:addItem(row._sfbName, row, tooltip)
        if row.itemType == selectedType then selectedIndex = index end
    end
    list.selected = selectedIndex
    list:setScrollHeight(#rows * list.itemheight)
    local clampedScroll = math.max(math.min(0, scroll), math.min(0, list.height - #rows * list.itemheight))
    list:setYScroll(clampedScroll)
    list.smoothScrollY = clampedScroll
    list.smoothScrollTargetY = clampedScroll
    list._sfbSignature = signature
end

function riskyTradeUI:sfbUpdateBulkButton()
    local button = self.sfbSellEverything
    if not button then return end
    local summary = self._sfbBulkSummary or { quantity = 0, total = 0, typeCount = 0 }
    local label = tr("UI_SFB_SellEverything", "Sell everything")
    local detail = tostring(summary.typeCount) .. tr("UI_SFB_Types", " types") .. "/" ..
        tostring(summary.quantity) .. tr("UI_SFB_Units", " items") .. "  +$" .. tostring(summary.total)
    local title = label .. "  " .. detail
    if getTextManager():MeasureStringX(UIFont.Small, title) > button.width - 16 then
        title = label .. "  +$" .. tostring(summary.total)
    end
    button:setTitle(UI.ShortText(title, button.width - 16))
    button.tooltip = tr("UI_SFB_BulkScope", "Sells eligible items from ALL categories, including bags. List filters do not limit this action.") ..
        "\n" .. detail .. "\n" .. tr("UI_SFB_Protected", "Favorites and equipped items are protected.")
    button:setEnable(self._sfbPending == nil and summary.quantity > 0)
end

function riskyTradeUI:sfbRefreshRows(force)
    if not self._sfbActive or not self.sfbSaleList then return end
    local player = getPlayer()
    local now = nowMs()
    if not force and now < (self._sfbNextRefresh or 0) then return end
    self._sfbNextRefresh = now + 500
    -- One inventory scan supplies both the complete-sale preview and the view.
    -- Category/owned filters affect the list only, never the global sale.
    local rows = P.GetRows(player, false)
    local filtered = {}
    local summary = { quantity = 0, total = 0, typeCount = 0 }
    for _, row in ipairs(rows) do
        local available = row.available or 0
        if available > 0 then
            summary.quantity = summary.quantity + available
            summary.total = summary.total + available * (row.price or 0)
            summary.typeCount = summary.typeCount + 1
        end
        if (not UI.onlyOwned or available > 0) and (UI.category == "all" or row.category == UI.category) then
            filtered[#filtered + 1] = row
        end
    end
    self._sfbBulkSummary = summary
    self:sfbUpdateBulkButton()
    self._sfbSaleRows = filtered
    refill(self.sfbSaleList, filtered, rowFingerprint(filtered))
    self.money = player and MFSTrade.GetMoney(player) or 0
end

function riskyTradeUI:sfbFilterChanged()
    UI.onlyOwned = self.sfbOwned:isSelected(1)
    UI.category = categories[self.sfbCategory.selected] or "all"
    self:sfbRefreshRows(true)
end

function riskyTradeUI:rebuildLists()
    if not P.IsEnabled() then
        removeControls(self)
        self._sfbActive = false
        return originalRebuild(self)
    end
    self:clearTradeButtons()
    removeControls(self)
    self._sfbActive = true
    local layout = UI.ComputeLayout(self.width, self.height, fontHeight())
    self._sfbLayout = layout
    self.sfbSellEverything = ISButton:new(8, layout.buyLabelY, self.width - 16, layout.controlH,
        tr("UI_SFB_SellEverything", "Sell everything"), self, self.sfbSellAll)
    self.sfbSellEverything:initialise()
    self.sfbSellEverything:instantiate()
    self.sfbSellEverything.backgroundColor = { r = 0.12, g = 0.24, b = 0.13, a = 0.9 }
    self.sfbSellEverything.backgroundColorMouseOver = { r = 0.2, g = 0.36, b = 0.2, a = 1 }
    self:addChild(self.sfbSellEverything)
    self.sfbOwned = ISTickBox:new(8, layout.controlsY, self.width - 158, layout.controlH,
        "SFBOnlyOwned", self, self.sfbFilterChanged)
    self.sfbOwned:initialise()
    local ownedLabel = tr("UI_SFB_OnlyOwned", "Only show owned items")
    local ownedWidth = self.width - 158 - layout.controlH - 10
    if getTextManager():MeasureStringX(UIFont.Small, ownedLabel) > ownedWidth then
        ownedLabel = tr("UI_SFB_OnlyOwnedCompact", "Owned")
    end
    self.sfbOwned:addOption(UI.ShortText(ownedLabel, ownedWidth))
    self.sfbOwned.tooltip = tr("UI_SFB_Protected", "Favorites and equipped items are protected.")
    self.sfbOwned:setSelected(1, UI.onlyOwned)
    self:addChild(self.sfbOwned)
    self.sfbCategory = ISComboBox:new(self.width - 144, layout.controlsY, 136, layout.controlH,
        self, self.sfbFilterChanged)
    self.sfbCategory:initialise()
    local selected = 1
    for index, category in ipairs(categories) do
        self.sfbCategory:addOption(tr("UI_SFB_Category_" .. category, category))
        if category == UI.category then selected = index end
    end
    self.sfbCategory.selected = selected
    self:addChild(self.sfbCategory)
    self.sfbSaleList = TradeList:new(8, layout.listY, self.width - 16, layout.buyH, self, "sell", layout.rowH)
    self.sfbSaleList:initialise()
    self.sfbSaleList:instantiate()
    self:addChild(self.sfbSaleList)
    self.sfbPurchaseList = TradeList:new(8, layout.sellY, self.width - 16, layout.sellH, self, "buy", layout.rowH)
    self.sfbPurchaseList:initialise()
    self.sfbPurchaseList:instantiate()
    self:addChild(self.sfbPurchaseList)
    local seed = MFSTrade.GetEffectiveSeed()
    local goods = MFSTrade.BuildSellList(seed)
    self.lists = { seed = seed, buy = {}, sell = goods }
    refill(self.sfbPurchaseList, goods, rowFingerprint(goods))
    self:sfbRefreshRows(true)
    if self.closebutton then
        self.closebutton:setX(self.width - self.closebutton.width - 6)
        self.closebutton:bringToTop()
    end
end

function riskyTradeUI:sfbCompleteSale(args)
    self._sfbPending = nil
    if args.accepted then
        self._sfbStatus = tr("UI_SFB_Sold", "Sold") .. " " .. tostring(args.quantity or 0) ..
            tr("UI_SFB_Units", " items") .. "  +$" .. tostring(args.total or 0)
    else
        self._sfbStatus = tr("UI_SFB_Rejected", "Transaction declined. Check eligible items and your radio.")
    end
    self._sfbNextRefresh = 0
    self:sfbRefreshRows(true)
end

function riskyTradeUI:sfbSellAll()
    -- Refresh the complete preview at the actual click, regardless of filters.
    if self._sfbPending then return end
    self:sfbRefreshRows(true)
    if not self._sfbBulkSummary or self._sfbBulkSummary.quantity < 1 then return end
    return self:sfbTrade(nil, "everything")
end

function riskyTradeUI:sfbTrade(entry, mode)
    if self._sfbPending then return end
    local player = getPlayer()
    if not player or not P.IsEnabled() then return end
    if not MFSTrade.HasRadio(player) then
        self._sfbStatus = tr("UI_SFB_NeedRadio", "Carry a walkie-talkie to trade.")
        return
    end
    if mode ~= "everything" and (not entry or not entry.itemType) then return end
    if mode ~= "buy" and mode ~= "everything" and (entry.available or 0) < 1 then return end
    if mode == "buy" and not (isClient and isClient()) and not (isServer and isServer()) then
        -- Keep the original SP purchase path without inventing a network ACK.
        -- Sending the request alone does not establish purchase success.
        originalTrade(self, entry, "buy")
        self._sfbStatus = tr("UI_SFB_PurchaseRequested", "Purchase requested. Check your items and balance.")
        self:sfbRefreshRows(true)
        return
    end
    UI.transactionSequence = (UI.transactionSequence or 0) + 1
    local requestId = tostring(nowMs()) .. ":" .. tostring(UI.transactionSequence)
    self._sfbPending = { kind = mode, time = nowMs(), itemType = entry and entry.itemType, requestId = requestId }
    self._sfbStatus = tr("UI_SFB_Waiting", "Waiting for transaction...")
    self:sfbUpdateBulkButton()
    if mode == "buy" then
        originalTrade(self, entry, "buy")
        return
    end
    -- Native sendServerCommand is a no-op in single-player, so waiting for its
    -- network ACK always timed out. Execute the same authoritative transaction
    -- locally and consume its actual result immediately in that environment.
    if not (isClient and isClient()) and not (isServer and isServer()) then
        local ran, accepted, reason, quantity, total, typeCount
        if mode == "everything" then
            ran, accepted, reason, quantity, total, typeCount = pcall(P.SellAll, player)
        else
            ran, accepted, reason, quantity, total, typeCount = pcall(P.Sell, player, entry.itemType, mode)
        end
        self:sfbCompleteSale({ accepted = ran and accepted == true,
            reason = not ran and "transaction_error" or reason, quantity = quantity, total = total, typeCount = typeCount })
        return
    end
    local command = mode == "everything" and "SellAll" or "Sell"
    local args = { requestId = requestId }
    if mode ~= "everything" then args.itemType, args.mode = entry.itemType, mode end
    local ok = pcall(sendClientCommand, player, P.Module, command, args)
    if not ok then
        self._sfbPending = nil
        self._sfbStatus = tr("UI_SFB_Failed", "Could not send the trade. Check your balance and items.")
        self:sfbUpdateBulkButton()
    end
end

function riskyTradeUI:onTradeEntry(entry, kind)
    if not self._sfbActive then return originalTrade(self, entry, kind) end
    return self:sfbTrade(entry, kind == "buy" and "buy" or "one")
end

function riskyTradeUI:refresh()
    originalRefresh(self)
    if self._sfbActive then self._sfbNextRefresh = 0 end
end

function riskyTradeUI:update()
    if not self._sfbActive then
        if P.IsEnabled() then self:rebuildLists() else return originalUpdate(self) end
    end
    ISPanel.update(self)
    if not self:getIsVisible() then return end
    if not P.IsEnabled() or not self.lists or self.lists.seed ~= MFSTrade.GetEffectiveSeed() then
        self:rebuildLists()
    end
    if not self._sfbActive then return end
    if self._sfbPending and nowMs() - self._sfbPending.time > 8000 then
        self._sfbPending = nil
        self._sfbStatus = tr("UI_SFB_Timeout", "No reply yet. Check your balance before retrying.")
        self._sfbNextRefresh = 0
    end
    self:sfbRefreshRows(false)
end

function riskyTradeUI:prerender()
    if not self._sfbActive then return originalPrerender(self) end
    ISPanel.prerender(self)
    local layout = self._sfbLayout
    if not layout then return end
    local line = fontHeight()
    self:drawText(tr("UI_SFB_Title", "SuQing fixed buyback"), 8, 6, 1, 1, 1, 1, UIFont.Small)
    local remaining = MFSTrade.GetRefreshRemainingHours()
    local minutes = math.max(0, math.floor(remaining * 60 + 0.5))
    local refresh = tr("UI_SFB_GoodsRefresh", "Equipment refresh") .. " " .. string.format("%d:%02d", math.floor(minutes / 60), minutes % 60)
    self:drawText(refresh, 8, line + 10, 1, 0.85, 0.4, 1, UIFont.Small)
    self:drawTextRight("$" .. tostring(self.money or 0), self.width - 8, line + 10, 0.4, 1, 0.5, 1, UIFont.Small)
    self:drawText(tr("UI_SFB_Equipment", "Buy equipment"), 8, layout.sellLabelY, 1, 0.88, 0.35, 1, UIFont.Small)
    local status = self._sfbStatus or tr("UI_SFB_Protected", "Favorites and equipped items are protected.")
    self:drawText(UI.ShortText(status, self.width - 16), 8, layout.statusY, 0.7, 0.8, 0.7, 1, UIFont.Small)
end

function riskyTradeUI.open(parentWindow)
    if not P.IsEnabled() then return originalOpen(parentWindow) end
    if riskyTradeWindow and riskyTradeWindow:getIsVisible() then
        riskyTradeWindow:close()
        return
    end
    local core = getCore()
    local screenW, screenH = core:getScreenWidth(), core:getScreenHeight()
    local width = math.min(420, screenW - 24)
    local height = math.min(math.max(560, parentWindow:getHeight()), screenH - 40)
    local x = math.max(8, math.min(parentWindow:getX() + parentWindow:getWidth(), screenW - width - 8))
    local y = math.max(8, math.min(parentWindow:getY(), screenH - height - 8))
    riskyTradeWindow = riskyTradeUI:new(x, y, width, height)
    riskyTradeWindow:initialise()
    riskyTradeWindow:addToUIManager()
    riskyTradeWindow:requestMoney()
    riskyTradeWindow:requestSeed()
end

local function onServerCommand(module, command, args)
    if type(args) ~= "table" then return end
    local own = module == P.Module and command == P.Ack
    local original = module == MFSTrade.MODULE and command == MFSTrade.ACK
    if not own and not original then return end
    local player = getPlayer()
    local window = riskyTradeWindow
    if not window or not window._sfbActive then return end
    if own then
        local pending = window._sfbPending
        -- Ignore stale or unrelated ACKs, including their old balance snapshot.
        if not pending or pending.kind == "buy" or args.requestId ~= pending.requestId then return end
        if player and finite(args.money) then player:getModData()[MFSTrade.MoneyKey] = args.money end
        window:sfbCompleteSale(args)
        return
    end
    if original and args.accepted ~= nil and window._sfbPending and window._sfbPending.kind == "buy" then
        window._sfbPending = nil
        if args.accepted then
            window._sfbStatus = tr("UI_SFB_Purchased", "Equipment purchased.")
        else
            window._sfbStatus = tr("UI_SFB_Rejected", "Transaction declined. Inventory was checked again.")
        end
    end
    window._sfbNextRefresh = 0
end

Events.OnServerCommand.Add(onServerCommand)
print("[SuQingMFSFixedBuyback] scrolling trade UI installed")
