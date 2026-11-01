local T = SFB_UITest
local P = SuQingMFSFixedBuyback
local UI = P.UI
T.names = {}
for _, row in ipairs(P.Catalog) do T.names[row.itemType] = row.displayName end
T.owned = { ["Base.Money"] = 12, ["Base.GoldCoin"] = 1, ["Base.GoldScrap"] = 2,
    ["Base.Diamond"] = 1, ["Base.Earring_Stud_Gold"] = 1,
    ["Base.WristWatch_Right_ClassicMilitary"] = 1 }

-- Backend behavior is covered separately. The UI receives deterministic,
-- authoritative-shaped rows so scan cadence and display filtering are isolated.
P.GetRows = function(player, onlyOwned)
    T.rowCalls = T.rowCalls + 1
    local rows = {}
    for _, source in ipairs(P.Catalog) do
        local count = player and (T.owned[source.itemType] or 0) or 0
        if not onlyOwned or count > 0 then
            rows[#rows + 1] = { itemType = source.itemType, category = source.category,
                price = source.price, count = 1, displayName = source.displayName, available = count }
        end
    end
    return rows
end
P.GetEligibleCount = function(_, ft) return T.owned[ft] or 0 end

local function localSale(ft, mode)
    T.localTradeCalls = T.localTradeCalls + 1
    if T.localThrow then error("local transaction failed") end
    if T.localReject then return false, "no_radio", 0, 0, 0 end
    local quantity, total, types = 0, 0, 0
    for _, row in ipairs(P.Catalog) do
        local available = T.owned[row.itemType] or 0
        if available > 0 and (not ft or row.itemType == ft) then
            local take = mode == "one" and 1 or available
            quantity, total, types = quantity + take, total + take * row.price, types + 1
            T.owned[row.itemType] = available - take
        end
    end
    if quantity == 0 then return false, "not_enough_items", 0, 0, 0 end
    T.player.data.MFSTrade_Money = T.player.data.MFSTrade_Money + total
    return true, nil, quantity, total, types
end
P.Sell = function(_, ft, mode) return localSale(ft, mode) end
P.SellAll = function(_) return localSale(nil, "all") end

function T.saleAck(args)
    local window = riskyTradeWindow
    if args.requestId == nil and window and window._sfbPending then args.requestId = window._sfbPending.requestId end
    T.emit(P.Module, P.Ack, args)
end

local function newWindow(width, height, line)
    T.fontH = line or 16
    local window = riskyTradeUI:new(20, 20, width or 420, height or 620)
    window:initialise()
    window:addToUIManager()
    riskyTradeWindow = window
    return window
end

local function resetView()
    UI.onlyOwned, UI.category = true, "all"
    T.disabled, T.noPlayer, T.radio, T.failSend = false, false, true, false
    T.network, T.localReject, T.localThrow, T.localTradeCalls = true, false, false, 0
    T.sent, T.drawCalls = {}, {}
    return newWindow(420, 620, 16)
end

local function layoutValid(width, height, line)
    local layout = UI.ComputeLayout(width, height, line)
    T.check(layout.controlH > 0 and layout.rowH > 0, "positive control sizes")
    T.check(layout.buyLabelY + line <= layout.controlsY, "buy label overlaps controls")
    T.check(layout.buyLabelY + layout.controlH <= layout.controlsY, "bulk button overlaps filters")
    T.check(layout.controlsY + layout.controlH <= layout.listY, "controls overlap list")
    T.check(layout.listY + layout.buyH <= layout.sellLabelY, "buy list overlaps equipment label")
    T.check(layout.sellLabelY + line <= layout.sellY, "equipment label overlaps list")
    T.check(layout.sellY + layout.sellH <= layout.statusY, "equipment list overlaps footer")
    T.check(layout.statusY + line <= height, "footer outside window")
    T.check(layout.buyH > 0 and layout.sellH > 0, "list viewport must exist")
    return layout
end

T.test("layout_normal_420x620_font16", function() layoutValid(420, 620, 16) end)
T.test("layout_small_396x440_font24", function() layoutValid(396, 440, 24) end)
T.test("layout_highfont_420x680_font36", function() layoutValid(420, 680, 36) end)
T.test("layout_small_highfont_396x440_font36", function() layoutValid(396, 440, 36) end)

T.test("highfont_narrow_row_action_bounds", function()
    local window = newWindow(396, 440, 36)
    window.sfbOwned:setSelected(1, false)
    window:sfbFilterChanged()
    local list = window.sfbSaleList
    local right, buttonWidth = list:actionGeometry()
    T.check(buttonWidth > 0, "nonpositive button width")
    T.check(right <= list.width, "button right outside list")
    T.check(right - buttonWidth * 2 - 4 >= 0, "sell-one action outside left list edge")
    T.drawCalls = {}
    list:doDrawItem(0, list.items[1])
    for _, draw in ipairs(T.drawCalls) do
        if draw.owner == list and draw.method == "drawRect" then
            local x, width = draw.args[1], draw.args[3]
            T.check(x >= 0 and x + width <= list.width, "action rectangle outside viewport")
        end
    end
end)

T.test("shorttext_does_not_overflow_tiny_available_width", function()
    T.fontH = 24
    for _, width in ipairs({ 0, 5, 15, 50, 100 }) do
        local short = UI.ShortText("A long item display name", width)
        T.check(getTextManager():MeasureStringX(UIFont.Small, short) <= width,
            "truncated label exceeds available width " .. tostring(width))
    end
end)

T.test("highfont_narrow_owned_checkbox_label_bounds", function()
    local previousText = T.text
    for _, labels in ipairs({
        { full = "Only show owned items", compact = "Owned" },
        { full = "仅显示当前持有物品", compact = "仅持有" },
    }) do
        T.text = { UI_SFB_OnlyOwned = labels.full, UI_SFB_OnlyOwnedCompact = labels.compact }
        local window = newWindow(396, 440, 36)
        local box = window.sfbOwned
        local label = box.options[1]
        local budget = box.width - window._sfbLayout.controlH - 10
        local measured = getTextManager():MeasureStringX(UIFont.Small, label)
        T.check(measured <= budget, "owned checkbox label exceeds its text budget")
        T.check(box.x + window._sfbLayout.controlH + 10 + measured <= window.sfbCategory.x,
            "owned checkbox label overlaps category dropdown")
        T.check(label ~= labels.full, "long owned-only label did not use compact fallback")
        T.check(type(box.tooltip) == "string" and #box.tooltip > 0, "checkbox protection tooltip missing")
    end
    T.text = previousText
end)

T.test("owned_only_default_and_original_goods", function()
    local window = resetView()
    T.check(UI.onlyOwned and window.sfbOwned:isSelected(1), "owned-only default must be selected")
    T.equal(#window.sfbSaleList.items, 6, "owned types")
    T.equal(#window.sfbPurchaseList.items, 7, "original goods count")
    T.check(window.lists.sell == T.goods, "equipment selection was replaced")
    T.equal(#window.buyButtons + #window.sellButtons, 0, "legacy rows should be removed")
    T.equal(window.sfbSaleList.Type, "SFB_TradeList", "scrolling-list subclass")
end)

T.test("all_122_rows_scroll_and_category_filter", function()
    local window = resetView()
    window.sfbOwned:setSelected(1, false)
    window:sfbFilterChanged()
    local list = window.sfbSaleList
    T.equal(#list.items, 122, "full catalog count")
    T.equal(#window.children, 6, "full catalog should not create one child button per row")
    T.equal(list:getScrollHeight(), 122 * list.itemheight, "scroll content extent")
    T.check(list:isVScrollBarVisible(), "full list needs scrollbar")
    local categoryIndices = { currency = 2, jewelry = 3, gems = 4, watches = 5, metals = 6 }
    local counts = { currency = 4, jewelry = 88, gems = 5, watches = 17, metals = 8 }
    for category, index in pairs(categoryIndices) do
        window.sfbCategory.selected = index
        window:sfbFilterChanged()
        T.equal(#list.items, counts[category], "filter " .. category)
        for _, item in ipairs(list.items) do T.equal(item.item.category, category, "wrong category row") end
    end
end)

T.test("scroll_retained_clamped_and_selection_follows_item", function()
    local window = resetView()
    window.sfbOwned:setSelected(1, false)
    window:sfbFilterChanged()
    local list = window.sfbSaleList
    list.selected = 120
    local selectedType = list.items[120].item.itemType
    list:setYScroll(-4000)
    window:sfbRefreshRows(true)
    T.equal(list.selected, 120, "same fingerprint selection stable")
    T.equal(list:getYScroll(), -4000, "same fingerprint scroll stable")
    T.owned[selectedType] = 2
    window:sfbRefreshRows(true)
    T.equal(list.items[list.selected].item.itemType, selectedType, "selection follows type after refill")
    window.sfbCategory.selected = 2
    window:sfbFilterChanged()
    T.check(list:getYScroll() >= math.min(0, list.height - list:getScrollHeight()), "scroll not clamped after shorter filter")
    T.check(list:getYScroll() <= 0, "scroll positive")
    T.owned[selectedType] = nil
end)

T.test("offscreen_rows_skip_draw_and_visible_last_row", function()
    local window = resetView()
    window.sfbOwned:setSelected(1, false)
    window:sfbFilterChanged()
    local list = window.sfbSaleList
    list:setYScroll(0)
    T.drawCalls = {}
    list:doDrawItem(100 * list.itemheight, list.items[101])
    T.equal(#T.drawCalls, 0, "offscreen row drew widgets")
    list:setYScroll(-(list:getScrollHeight() - list.height))
    list:doDrawItem(121 * list.itemheight, list.items[122])
    T.check(#T.drawCalls > 0, "last row not drawable after scroll")
end)

T.test("draw_does_not_scan_inventory", function()
    local window = resetView()
    local before = T.rowCalls
    for _ = 1, 60 do
        window:prerender()
        window.sfbSaleList:render()
        window.sfbSaleList:doDrawItem(0, window.sfbSaleList.items[1])
        window.sfbPurchaseList:doDrawItem(0, window.sfbPurchaseList.items[1])
    end
    T.equal(T.rowCalls, before, "render path rescans backend")
end)

T.test("refresh_cadence_500ms_and_hidden_window", function()
    local window = resetView()
    local before = T.rowCalls
    for _ = 1, 60 do window:update() end
    T.equal(T.rowCalls, before, "same-frame updates rescan")
    T.now = T.now + 499
    window:update()
    T.equal(T.rowCalls, before, "refresh earlier than 500ms")
    T.now = T.now + 1
    window:update()
    T.equal(T.rowCalls, before + 1, "refresh not scheduled at 500ms")
    window:setVisible(false)
    T.now = T.now + 1000
    window:update()
    T.equal(T.rowCalls, before + 1, "hidden window rescans inventory")
end)

T.test("zero_available_no_radio_disabled_or_no_player_do_not_send", function()
    local window = resetView()
    local row = { itemType = "Base.Money", available = 0, price = 10 }
    window:sfbTrade(row, "one")
    T.equal(#T.sent, 0, "zero available sale sent")
    row.available = 1
    T.radio = false; window:sfbTrade(row, "all")
    T.radio = true; T.disabled = true; window:sfbTrade(row, "one")
    T.disabled = false; T.noPlayer = true; window:sfbTrade(row, "one")
    T.equal(#T.sent, 0, "invalid precondition request sent")
    T.noPlayer = false
end)

T.test("sell_one_all_pending_and_ack", function()
    local window = resetView()
    local row = { itemType = "Base.Money", available = 12, price = 10 }
    window:sfbTrade(row, "one")
    T.equal(#T.sent, 1, "one sale sent once")
    T.equal(T.sent[1].module, P.Module, "sale module")
    T.equal(T.sent[1].command, "Sell", "sale command")
    T.equal(T.sent[1].args.mode, "one", "sale mode")
    T.check(T.sent[1].args.price == nil and T.sent[1].args.total == nil, "client sets price")
    window:sfbTrade(row, "all")
    T.equal(#T.sent, 1, "pending repeated click sent")
    T.emit("Unrelated", P.Ack, { accepted = true, money = 999999 })
    T.check(window._sfbPending ~= nil, "unrelated ack cleared pending")
    T.saleAck({ accepted = true, money = 10010, quantity = 1, total = 10 })
    T.check(window._sfbPending == nil, "sale ack did not clear pending")
    T.equal(T.player.data.MFSTrade_Money, 10010, "authoritative balance")
    window:sfbTrade(row, "all")
    T.equal(#T.sent, 2, "all sale not sent after ack")
    T.equal(T.sent[2].args.mode, "all", "all mode")
end)

T.test("equipment_purchase_uses_original_mfs_command", function()
    local window = resetView()
    window:sfbTrade(T.goods[1], "buy")
    T.equal(#T.sent, 1, "buy sent once")
    T.equal(T.sent[1].module, MFSTrade.MODULE, "original MFS module")
    T.equal(T.sent[1].command, MFSTrade.CMD_BUY, "original buy command")
    T.equal(T.sent[1].args.itemType, T.goods[1].itemType, "original goods type")
    T.emit(MFSTrade.MODULE, MFSTrade.ACK, { accepted = true, money = 7010 })
    T.check(window._sfbPending == nil, "original buy ack left pending")
end)

T.test("transport_failure_timeout_and_rejected_ack", function()
    local window = resetView()
    local row = { itemType = "Base.Money", available = 12, price = 10 }
    T.failSend = true
    window:sfbTrade(row, "one")
    T.check(window._sfbPending == nil, "transport failure leaves pending sale")
    T.equal(#T.sent, 0, "failed transport was recorded")
    T.failSend = false
    window:sfbTrade(row, "one")
    T.now = T.now + 8001
    window:update()
    T.check(window._sfbPending == nil, "pending timeout not released")
    T.check(window._sfbStatus ~= nil, "timeout has no status")
    window:sfbTrade(row, "all")
    T.saleAck({ accepted = false, money = T.player.data.MFSTrade_Money })
    T.check(window._sfbPending == nil, "rejection leaves pending")
end)

T.test("button_only_click_matching_down_up_no_scrollbar_send", function()
    local window = resetView()
    local list = window.sfbSaleList
    local right, width = list:actionGeometry()
    local bottom = list.itemheight - T.fontH / 2 - 5
    list:onMouseDown(50, 5); list:onMouseUp(50, 5)
    T.equal(#T.sent, 0, "name-only click traded")
    list:onMouseDown(right - width / 2, bottom)
    list:onMouseUpOutside(right - width / 2, bottom)
    list:onMouseUp(right - width / 2, bottom)
    T.equal(#T.sent, 0, "released-outside click traded")
    list._mouseOverScrollBar = true
    list:onMouseDown(right - width / 2, bottom); list:onMouseUp(right - width / 2, bottom)
    T.equal(#T.sent, 0, "scrollbar click traded")
    list._mouseOverScrollBar = false
    list:onMouseDown(right - width / 2, bottom)
    list:onMouseUp(right - width / 2, bottom + list.itemheight)
    T.equal(#T.sent, 0, "down and up across different items traded")
    list:onMouseDown(right - width / 2, bottom); list:onMouseUp(right - width / 2, bottom)
    T.equal(#T.sent, 1, "action click did not trade")
    T.equal(T.sent[1].args.mode, "all", "right button is sell-all")
end)

T.test("empty_state_renders_without_trade", function()
    local window = resetView()
    local original = T.owned
    T.owned = {}
    window:sfbRefreshRows(true)
    T.equal(#window.sfbSaleList.items, 0, "empty inventory has rows")
    T.drawCalls = {}
    window.sfbSaleList:render()
    T.check(#T.drawCalls >= 2, "empty owned view has no guidance")
    T.equal(#T.sent, 0, "empty view sent a trade")
    T.owned = original
end)

T.test("window_open_clamps_screen_and_reopens", function()
    T.disabled, T.screenW, T.screenH, T.fontH = false, 800, 600, 24
    if riskyTradeWindow then riskyTradeWindow:close() end
    local parent = ISPanel:new(750, 500, 300, 700)
    riskyTradeUI.open(parent)
    local window = riskyTradeWindow
    T.check(window and window:getIsVisible(), "window did not open")
    T.check(window.x >= 0 and window.y >= 0, "window negative origin")
    T.check(window.x + window.width <= T.screenW, "window off right edge")
    T.check(window.y + window.height <= T.screenH, "window off bottom edge")
    T.equal(#T.sent >= 2, true, "money/seed requests absent")
    riskyTradeUI.open(parent)
    T.check(riskyTradeWindow == nil, "second open does not close window")
    riskyTradeUI.open(parent)
    T.check(riskyTradeWindow ~= nil, "reopen failed")
    riskyTradeWindow:close()
    T.screenW, T.screenH, T.fontH = 1280, 720, 16
end)

T.test("disabled_falls_back_to_original_trade_ui", function()
    local window = resetView()
    T.disabled = true
    window:rebuildLists()
    T.check(not window._sfbActive, "disabled patch still active")
    T.check(window.sfbSaleList == nil and window.sfbPurchaseList == nil, "custom controls remain")
    T.equal(#window.buyButtons, 1, "original buyback fallback missing")
    T.equal(#window.sellButtons, 7, "original goods fallback missing")
    T.disabled = false
end)

T.test("bulk_preview_covers_every_category_despite_view_filter", function()
    local window = resetView()
    T.equal(window._sfbBulkSummary.quantity, 18, "complete quantity")
    T.equal(window._sfbBulkSummary.typeCount, 6, "complete type count")
    T.equal(window._sfbBulkSummary.total, 1870, "complete expected income")
    window.sfbCategory.selected = 2
    window:sfbFilterChanged()
    T.equal(#window.sfbSaleList.items, 2, "currency-only list")
    T.equal(window._sfbBulkSummary.quantity, 18, "filter limits global sale preview")
    T.equal(window._sfbBulkSummary.total, 1870, "filter limits global income preview")
    T.check(window.sfbSellEverything.enable, "bulk button should be available")
    T.check(string.find(window.sfbSellEverything.tooltip, "ALL categories", 1, true) ~= nil,
        "global scope tooltip missing")
end)

T.test("bulk_network_sends_one_command_and_matches_request_id", function()
    local window = resetView()
    window.sfbCategory.selected = 4
    window:sfbFilterChanged()
    window:sfbSellAll()
    T.equal(#T.sent, 1, "bulk did not send exactly one command")
    local first = T.sent[1]
    T.equal(first.command, "SellAll", "bulk command")
    T.equal(first.module, P.Module, "bulk module")
    T.check(type(first.args.requestId) == "string", "bulk request identity missing")
    T.check(first.args.itemType == nil and first.args.price == nil and first.args.total == nil,
        "bulk client should not supply a list or prices")
    T.check(not window.sfbSellEverything.enable, "pending bulk button enabled")
    window:sfbSellAll()
    T.equal(#T.sent, 1, "pending bulk repeated")
    local oldMoney = T.player.data.MFSTrade_Money
    T.emit(P.Module, P.Ack, { accepted = true, money = 999999, requestId = "wrong" })
    T.check(window._sfbPending ~= nil, "wrong request cleared pending")
    T.equal(T.player.data.MFSTrade_Money, oldMoney, "wrong request changed balance")
    T.saleAck({ accepted = true, money = oldMoney + 1870, quantity = 18, total = 1870, typeCount = 6 })
    T.check(window._sfbPending == nil, "bulk ack did not release pending")
    T.check(string.find(window._sfbStatus, "1870", 1, true) ~= nil, "bulk result has no income")
    window:sfbSellAll()
    local nextId = window._sfbPending.requestId
    T.check(nextId ~= first.args.requestId, "request ID reused")
    T.emit(P.Module, P.Ack, { accepted = true, money = 1, requestId = first.args.requestId })
    T.equal(window._sfbPending.requestId, nextId, "late prior ACK released current request")
    T.equal(T.player.data.MFSTrade_Money, oldMoney + 1870, "late prior ACK regressed balance")
end)

T.test("singleplayer_one_and_everything_complete_without_network_wait", function()
    local window = resetView()
    T.network = false
    local originalOwned = T.owned
    T.owned = { ["Base.Money"] = 12, ["Base.GoldCoin"] = 1, ["Base.GoldScrap"] = 2,
        ["Base.Diamond"] = 1, ["Base.Earring_Stud_Gold"] = 1,
        ["Base.WristWatch_Right_ClassicMilitary"] = 1 }
    local before = T.player.data.MFSTrade_Money
    window:sfbTrade({ itemType = "Base.Money", available = 12 }, "one")
    T.equal(T.localTradeCalls, 1, "SP one transaction count")
    T.equal(T.owned["Base.Money"], 11, "SP one did not remove one item")
    T.equal(T.player.data.MFSTrade_Money, before + 10, "SP one income")
    T.check(window._sfbPending == nil, "SP one waits for network ACK")
    window.sfbCategory.selected = 4
    window:sfbFilterChanged()
    window:sfbSellAll()
    T.equal(T.localTradeCalls, 2, "SP bulk did not call one transaction")
    T.equal(T.player.data.MFSTrade_Money, before + 1870, "SP complete inventory income")
    T.equal(window.money, before + 1870, "SP displayed money not immediate")
    T.check(window._sfbPending == nil, "SP bulk waits for network ACK")
    T.equal(window._sfbBulkSummary.quantity, 0, "SP preview not immediately updated")
    T.check(not window.sfbSellEverything.enable, "SP empty bulk button enabled")
    window:sfbSellAll()
    T.equal(T.localTradeCalls, 2, "empty repeated SP click invoked transaction")
    T.equal(#T.sent, 0, "SP sale sent a network command")
    T.owned = originalOwned
end)

T.test("singleplayer_failed_sale_clears_pending_and_preserves_preview", function()
    local window = resetView()
    T.network, T.localReject = false, true
    local before = T.player.data.MFSTrade_Money
    window:sfbSellAll()
    T.check(window._sfbPending == nil, "SP rejected sale left pending")
    T.equal(T.player.data.MFSTrade_Money, before, "SP rejected sale changed money")
    T.equal(window._sfbBulkSummary.quantity, 18, "SP rejected sale preview lost items")
    T.check(window.sfbSellEverything.enable, "SP rejection leaves bulk disabled")
    T.localReject, T.localThrow = false, true
    window:sfbSellAll()
    T.check(window._sfbPending == nil, "SP exception left pending")
    T.equal(T.player.data.MFSTrade_Money, before, "SP exception changed money")
    T.equal(#T.sent, 0, "SP failure sent network command")
end)

T.test("singleplayer_purchase_keeps_original_path_without_false_ack_wait", function()
    local window = resetView()
    T.network = false
    window:sfbTrade(T.goods[1], "buy")
    T.equal(#T.sent, 1, "SP purchase did not use original path")
    T.equal(T.sent[1].module, MFSTrade.MODULE, "SP purchase module changed")
    T.equal(T.sent[1].command, MFSTrade.CMD_BUY, "SP purchase command changed")
    T.check(window._sfbPending == nil, "SP purchase waits for impossible ACK")
    T.check(window._sfbStatus ~= "Equipment purchased.", "SP purchase falsely declared success")
end)

T.test("bulk_button_bounds_and_long_labels_cn_en", function()
    local previousText = T.text
    for _, label in ipairs({ "Sell everything", "一键出售所有可收购物品" }) do
        T.text = { UI_SFB_SellEverything = label }
        local window = newWindow(396, 440, 36)
        local button = window.sfbSellEverything
        T.check(button.y + button.height <= window.sfbOwned.y, "bulk button overlaps filters")
        T.check(button.x >= 0 and button.x + button.width <= window.width, "bulk button outside window")
        T.check(getTextManager():MeasureStringX(UIFont.Small, button.title) <= button.width - 16,
            "bulk label overflows button")
        T.check(type(button.tooltip) == "string" and #button.tooltip > 0, "bulk tooltip absent")
    end
    T.text = previousText
end)

local failed = 0
for _, result in ipairs(T.results) do if not result.passed then failed = failed + 1 end end
local summary = {}
for _, result in ipairs(T.results) do
    summary[#summary + 1] = "SFB_UI_TEST|" .. result.name .. "|" .. (result.passed and "PASS" or "FAIL") ..
        "|" .. (result.error or "")
end
summary[#summary + 1] = "SFB_UI_SUMMARY|" .. tostring(#T.results) .. "|" .. tostring(failed)
return table.concat(summary, "\n") .. "\n"
