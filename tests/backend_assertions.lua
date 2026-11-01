local T, P = Test, SuQingMFSFixedBuyback
local originalStock = T.originalStock
local function money(p) return MFSTrade.GetMoney(p) end
local function reset() SandboxVars.SuQingMFSFixedBuyback = nil; SandboxVars.MFSTrade.Enabled = true end
T.case("catalog and exact IDs", function()
    T.eq(P.RefreshCatalog(), 122)
    local rows = MFSTrade.BuildBuyList(1)
    T.eq(#rows, 122)
    local seen = {}
    for _, row in ipairs(rows) do T.ok(not seen[row.itemType]); seen[row.itemType] = true; T.ok(row.price > 0) end
    T.eq(P.GetUnitPrice("Base.Money"), 10)
    T.eq(P.GetUnitPrice("Base.MoneyBundle"), 1000)
    T.eq(P.GetUnitPrice("Base.SilverCoin"), 50)
    T.eq(P.GetUnitPrice("Base.GoldCoin"), 250)
    T.eq(P.GetUnitPrice("Base.KeyRing"), nil)
    T.eq(P.GetUnitPrice("Base.OnionRings"), nil)
    T.eq(P.GetUnitPrice("Base.Necklace_Teeth"), nil)
end)
T.case("single and batch currency sale", function()
    local p = T.player({T.item("Base.Money",10), T.item("Base.SilverCoin",2), T.item("Base.GoldCoin")})
    local ok, why, qty, total = P.Sell(p, "Base.Money", "one")
    T.eq(ok,true); T.eq(qty,1); T.eq(total,10)
    T.eq(P.GetEligibleCount(p,"Base.Money"),9)
    T.eq(P.Sell(p,"Base.Money","all"),true)
    T.eq(P.Sell(p,"Base.SilverCoin","all"),true)
    T.eq(P.Sell(p,"Base.GoldCoin","all"),true)
    T.eq(money(p),450)
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),0)
    T.eq(P.Sell(p,"Base.Money","all"),false)
    T.eq(money(p),450)
end)
T.case("bundle equivalence and original stock unchanged", function()
    local a,b = T.player({T.item("Base.MoneyBundle")}),T.player({T.item("Base.Money",100)})
    P.Sell(a,"Base.MoneyBundle","all"); P.Sell(b,"Base.Money","all")
    T.eq(money(a),1000);T.eq(money(b),money(a))
    T.eq(MFSTrade.BuildSellList,originalStock)
    T.eq(#MFSTrade.BuildSellList(1),7)
    local rows = MFSTrade.BuildBuyList(1); T.hours=25
    local later = MFSTrade.BuildBuyList(99)
    T.eq(#rows,#later)
    for i,row in ipairs(rows) do T.eq(row.itemType,later[i].itemType);T.eq(row.price,later[i].price) end
    T.hours=0
end)
T.case("favorites, hands and worn jewelry", function()
    local fav,held,worn,sale = T.item("Base.Money"),T.item("Base.Money"),T.item("Base.Ring_Left_RingFinger_Gold"),T.item("Base.Money",3)
    fav.favorite=true
    local p=T.player({fav,held,worn,sale}); p.primary=held;p.worn[worn]=true
    T.eq(P.GetEligibleCount(p,"Base.Money"),3)
    T.eq(P.GetEligibleCount(p,worn.ft),0)
    T.eq(P.Sell(p,"Base.Money","all"),true)
    T.eq(money(p),30);T.eq(p.inventory:getItemCountRecurse("Base.Money"),2)
    T.eq(P.Sell(p,worn.ft,"all"),false);T.ok(p.inventory:getItems():contains(worn))
end)
T.case("nested equipped bags and favorite ancestors", function()
    local open=T.bag({T.item("Base.Money",4),T.bag({T.item("Base.Money",6)})})
    local protected=T.bag({T.item("Base.Money",9)},true)
    local p=T.player({open,protected});p.worn[open]=true
    T.eq(P.GetEligibleCount(p,"Base.Money"),10)
    T.eq(P.Sell(p,"Base.Money","all"),true)
    T.eq(money(p),100);T.eq(protected.inventory:getItemCountRecurse("Base.Money"),9)
    T.ok(p.inventory:getItems():contains(open))
end)
T.case("category switches and multiplier", function()
    SandboxVars.SuQingMFSFixedBuyback={Watches=false,Metals=false,Jewelry=false,Gems=false}
    T.eq(#P.GetRows(nil,false),4)
    T.eq(P.GetUnitPrice("Base.WristWatch_Left_DigitalBlack"),nil)
    local p=T.player({T.item("Base.Diamond")})
    T.eq(P.Sell(p,"Base.Diamond","all"),false);T.eq(money(p),0)
    SandboxVars.SuQingMFSFixedBuyback={PriceMultiplier=0.1}
    T.eq(P.GetUnitPrice("Base.Money"),1);T.eq(P.GetUnitPrice("Base.MoneyBundle"),100)
    reset();T.eq(#P.GetRows(nil,false),122)
end)
T.case("radio and trade settings required", function()
    local p=T.player({T.item("Base.Money")})
    p.inventory:DoRemoveItem(p.inventory.items[2])
    T.eq(P.Sell(p,"Base.Money","all"),false);T.eq(money(p),0)
    local p2=T.player({T.item("Base.Money")})
    SandboxVars.MFSTrade.Enabled=false
    T.eq(P.Sell(p2,"Base.Money","all"),false);T.eq(money(p2),0);reset()
end)
T.case("invalid requests rejected before debit", function()
    local p=T.player({T.item("Base.Money",8)})
    for _, args in ipairs({{"Base.Money","ten"},{"Base.KeyRing","all"},{"Base.DoesNotExist","one"},{123,"all"}}) do
        T.eq(P.Sell(p,args[1],args[2]),false)
    end
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),8);T.eq(money(p),0)
end)
T.case("rollback after second object removal fails", function()
    local p=T.player({T.item("Base.Money"),T.item("Base.Money"),T.item("Base.Money")})
    p.inventory.failRemoval=2
    local ok,reason=P.Sell(p,"Base.Money","all")
    T.eq(ok,false);T.eq(reason,"remove_failed")
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),3);T.eq(money(p),0)
    p.inventory.failRemoval=nil;T.eq(P.Sell(p,"Base.Money","all"),true);T.eq(money(p),30)
end)
T.case("failed partial count is not paid", function()
    local item=T.item("Base.Money",5);item.failCount=true
    local p=T.player({item})
    T.eq(P.Sell(p,"Base.Money","one"),false)
    T.eq(item.count,5);T.eq(money(p),0)
end)
T.case("payment failure restores count and balance", function()
    local item=T.item("Base.Money",5);local p=T.player({item})
    local give=MFSTrade.GiveMoney
    MFSTrade.GiveMoney=function(player,amount) give(player,amount);error("injected credit failure") end
    local ok,why=P.Sell(p,"Base.Money","all")
    T.eq(ok,false);T.eq(why,"payment_failed");T.eq(money(p),0);T.eq(item.count,5)
    T.ok(p.inventory:getItems():contains(item))
    MFSTrade.GiveMoney=give
    T.eq(P.Sell(p,"Base.Money","one"),true);T.eq(money(p),10);T.eq(item.count,4)
end)
T.case("legacy endpoint enforces allowlist and protected items", function()
    local p=T.player({T.item("Base.Money",3),T.item("Base.KeyRing")})
    T.eq(MFSTrade.TakeItem(p,"Base.KeyRing",1),false)
    T.eq(MFSTrade.TakeItem(p,"Base.Money",4),false)
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),3)
    T.eq(MFSTrade.TakeItem(p,"Base.Money",2),true)
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),1)
end)
T.case("owned rows filter and counts", function()
    local p=T.player({T.item("Base.GoldCoin",2),T.item("Base.Money",7),T.item("Base.Necklace_Teeth")})
    local rows=P.GetRows(p,true);T.eq(#rows,2)
    local found={};for _,r in ipairs(rows)do found[r.itemType]=r.available end
    T.eq(found["Base.GoldCoin"],2);T.eq(found["Base.Money"],7)
end)
T.case("hooks remain safe under repeated and foreign wrappers", function()
    local hook=MFSTrade.BuildBuyList;P.EnsureHooks();T.eq(MFSTrade.BuildBuyList,hook)
    MFSTrade.BuildBuyList=function(seed)return hook(seed)end
    local take=MFSTrade.TakeItem;MFSTrade.TakeItem=function(...)return take(...)end
    T.eq(P.EnsureHooks(),true);T.eq(#MFSTrade.BuildBuyList(),122)
    SandboxVars.SuQingMFSFixedBuyback={Enabled=false}
    local rows=MFSTrade.BuildBuyList();T.eq(#rows,1);T.eq(rows[1].itemType,"Base.RareMemento")
    local p=T.player({T.item("Base.Money")});T.eq(MFSTrade.TakeItem(p,"Base.Money",1),true)
    reset()
end)
T.case("numeric overflow cannot credit or consume", function()
    local p=T.player({T.item("Base.Money")});p.data[MFSTrade.MoneyKey]=9007199254740990
    T.eq(P.Sell(p,"Base.Money","one"),false)
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),1)
    p.data[MFSTrade.MoneyKey]=0.5
    T.eq(P.Sell(p,"Base.Money","one"),false);T.eq(p.inventory:getItemCountRecurse("Base.Money"),1)
end)
T.case("server protocol ignores client price and repeats safely", function()
    local p=T.player({T.item("Base.GoldCoin",2)})
    local handler=Events.OnClientCommand.handlers[#Events.OnClientCommand.handlers]
    handler(P.Module,"Sell",p,{itemType="Base.GoldCoin",mode="all",price=99999999,count=10000})
    T.eq(Test.ack.module,P.Module);T.eq(Test.ack.args.accepted,true)
    T.eq(Test.ack.args.total,500);T.eq(money(p),500)
    handler(P.Module,"Sell",p,{itemType="Base.GoldCoin",mode="all"})
    T.eq(Test.ack.args.accepted,false);T.eq(money(p),500)
    handler(P.Module,"Sell",p,nil);T.eq(Test.ack.args.reason,"invalid_request")
end)
T.case("all 122 catalog types use one snapshot and one payment", function()
    reset()
    local items, expected, quantity = {}, 0, 0
    for i, record in ipairs(P.Catalog) do
        local count = i % 3 + 1
        local item = T.item(record.itemType, count)
        item.reads = 0
        function item:getFullType() self.reads = self.reads + 1; return self.ft end
        items[#items + 1] = item
        expected = expected + P.GetUnitPrice(record.itemType) * count
        quantity = quantity + count
    end
    local p, originalGive, payments = T.player(items), MFSTrade.GiveMoney, 0
    MFSTrade.GiveMoney = function(player, amount) payments = payments + 1; originalGive(player, amount) end
    local ok, reason, qty, total, kinds = P.SellAll(p)
    MFSTrade.GiveMoney = originalGive
    T.eq(ok, true); T.eq(reason, nil); T.eq(qty, quantity); T.eq(total, expected)
    T.eq(kinds, 122); T.eq(payments, 1); T.eq(money(p), expected)
    T.eq(p.inventory:getItems():size(), 1)
    for _, item in ipairs(items) do T.eq(item.reads, 1) end
    T.eq(P.SellAll(p), false); T.eq(money(p), expected)
end)
T.case("bulk protects favorites hands worn items and favorite ancestors", function()
    local fav, held, worn = T.item("Base.Money", 9), T.item("Base.GoldCoin"), T.item("Base.Ring_Left_RingFinger_Gold")
    fav.favorite = true
    local protected = T.bag({T.bag({T.item("Base.Diamond", 3)})}, true)
    local open = T.bag({T.item("Base.SilverCoin", 2), T.item("Base.WristWatch_Left_DigitalBlack"), T.item("Base.GoldScrap", 4)})
    local unknown, notes = T.item("Base.KeyRing"), T.item("Base.Money", 3)
    local p = T.player({fav, held, worn, protected, open, unknown, notes})
    p.primary, p.worn[worn], p.worn[open] = held, true, true
    local ok, reason, qty, total, kinds = P.SellAll(p)
    T.eq(ok,true); T.eq(qty,10); T.eq(total,330); T.eq(kinds,4)
    for _, item in ipairs({fav,held,worn,protected,open,unknown}) do T.ok(p.inventory:getItems():contains(item)) end
    T.eq(fav.count,9); T.eq(protected.inventory:getItemCountRecurse("Base.Diamond"),3)
    T.eq(open.inventory:getItems():size(),0); T.eq(money(p),330)
end)
T.case("bulk obeys disabled categories and price multiplier", function()
    SandboxVars.SuQingMFSFixedBuyback={Watches=false,Metals=false,Jewelry=false,Gems=false,PriceMultiplier=0.1}
    local diamond, watch, metal = T.item("Base.Diamond"),T.item("Base.WristWatch_Left_DigitalBlack"),T.item("Base.GoldBar")
    local p=T.player({T.item("Base.Money",3),T.item("Base.MoneyBundle"),diamond,watch,metal})
    local ok, why, qty, total, kinds=P.SellAll(p)
    T.eq(ok,true);T.eq(qty,4);T.eq(total,103);T.eq(kinds,2);T.eq(money(p),103)
    for _,item in ipairs({diamond,watch,metal}) do T.ok(p.inventory:getItems():contains(item)) end
    reset()
end)
T.case("bulk requires radio enabled trade and authoritative context", function()
    local p=T.player({T.item("Base.Money")})
    p.inventory:DoRemoveItem(p.inventory.items[2])
    local ok, why=P.SellAll(p);T.eq(ok,false);T.eq(why,"no_radio")
    local p2=T.player({T.item("Base.Money")})
    SandboxVars.SuQingMFSFixedBuyback={Enabled=false}
    ok,why=P.SellAll(p2);T.eq(ok,false);T.eq(why,"disabled");reset()
    local originalClient=isClient
    isClient=function()return true end
    ok,why=P.SellAll(p2);T.eq(ok,false);T.eq(why,"server_only")
    isClient=originalClient
    T.eq(money(p),0);T.eq(money(p2),0)
end)
T.case("bulk aggregate quantity and balance limits reject before removing", function()
    local p=T.player({T.item("Base.Money",700000),T.item("Base.SilverCoin",400000)})
    local ok,why=P.SellAll(p);T.eq(ok,false);T.eq(why,"quantity_limit")
    T.eq(p.inventory.removals,0);T.eq(money(p),0)
    local p2=T.player({T.item("Base.Money",10),T.item("Base.SilverCoin",3)})
    p2.data[MFSTrade.MoneyKey]=9007199254740791
    ok,why=P.SellAll(p2);T.eq(ok,false);T.eq(why,"balance_limit")
    T.eq(p2.inventory.removals,0);T.eq(money(p2),9007199254740791)
end)
T.case("bulk invalid snapshot never partially sells", function()
    local invalid=T.item("Base.SilverCoin",1000001)
    local p=T.player({T.item("Base.Money",2),invalid})
    local ok,why=P.SellAll(p);T.eq(ok,false);T.eq(why,"transaction_error")
    T.eq(p.inventory.removals,0);T.eq(money(p),0)
end)
T.case("bulk rollback spans types and nested containers", function()
    local first, second=T.item("Base.Money",5),T.item("Base.SilverCoin",3)
    local bag=T.bag({second,T.item("Base.Diamond")})
    local p=T.player({first,bag});bag.inventory.failRemoval=2
    local ok,why=P.SellAll(p);T.eq(ok,false);T.eq(why,"remove_failed")
    T.ok(p.inventory:getItems():contains(first));T.eq(first.count,5)
    T.ok(bag.inventory:getItems():contains(second));T.eq(second.count,3)
    T.eq(bag.inventory:getItemCountRecurse("Base.Diamond"),1);T.eq(money(p),0)
    bag.inventory.failRemoval=nil
    local accepted,reason,qty,total,kinds=P.SellAll(p)
    T.eq(accepted,true);T.eq(qty,9);T.eq(total,1200);T.eq(kinds,3)
end)
T.case("bulk payment failure restores every type and previous balance", function()
    local items={T.item("Base.Money",3),T.item("Base.GoldCoin",2),T.item("Base.Diamond")}
    local p=T.player(items);p.data[MFSTrade.MoneyKey]=77
    local give=MFSTrade.GiveMoney
    MFSTrade.GiveMoney=function(player,amount)give(player,amount);error("injected bulk credit failure")end
    local ok,why=P.SellAll(p)
    MFSTrade.GiveMoney=give
    T.eq(ok,false);T.eq(why,"payment_failed");T.eq(money(p),77)
    for _,item in ipairs(items)do T.ok(p.inventory:getItems():contains(item))end
    T.eq(items[1].count,3);T.eq(items[2].count,2);T.eq(items[3].count,1)
end)
T.case("bulk rejects reentrant selling while its payment runs", function()
    local p=T.player({T.item("Base.Money",2),T.item("Base.GoldCoin")})
    local give, nestedOk, nestedReason=MFSTrade.GiveMoney
    MFSTrade.GiveMoney=function(player,amount)
        nestedOk,nestedReason=P.SellAll(player)
        give(player,amount)
    end
    local ok=P.SellAll(p);MFSTrade.GiveMoney=give
    T.eq(ok,true);T.eq(nestedOk,false);T.eq(nestedReason,"busy");T.eq(money(p),270)
end)
T.case("bulk protocol ignores spoofed payload and deduplicates request IDs", function()
    local p=T.player({T.item("Base.Money",3),T.item("Base.SilverCoin",2),T.item("Base.KeyRing")})
    local handler=Events.OnClientCommand.handlers[#Events.OnClientCommand.handlers]
    handler(P.Module,"SellAll",p,{requestId="bulk-1",price=99999999,count=9999,itemType="Base.KeyRing",items={"Base.KeyRing"}})
    T.eq(Test.ack.args.accepted,true);T.eq(Test.ack.args.quantity,5)
    T.eq(Test.ack.args.typeCount,2);T.eq(Test.ack.args.total,130);T.eq(Test.ack.args.requestId,"bulk-1")
    T.eq(money(p),130);T.eq(p.inventory:getItemCountRecurse("Base.KeyRing"),1)
    p.inventory:AddItem(T.item("Base.Money",2))
    handler(P.Module,"SellAll",p,{requestId="bulk-1"})
    T.eq(Test.ack.args.accepted,true);T.eq(Test.ack.args.total,130)
    T.eq(money(p),130);T.eq(p.inventory:getItemCountRecurse("Base.Money"),2)
    handler(P.Module,"Sell",p,{requestId="bulk-1",itemType="Base.Money",mode="all"})
    T.eq(Test.ack.args.accepted,false);T.eq(Test.ack.args.reason,"invalid_request")
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),2)
    handler(P.Module,"SellAll",p,{requestId="bulk-2"})
    T.eq(Test.ack.args.accepted,true);T.eq(Test.ack.args.total,20);T.eq(money(p),150)
    handler(P.Module,"SellAll",p,{requestId="bulk-1"})
    T.eq(Test.ack.args.money,150);T.eq(money(p),150)
end)
T.case("single-type request IDs cannot replay onto newly acquired items", function()
    local p=T.player({T.item("Base.GoldCoin",2)})
    local handler=Events.OnClientCommand.handlers[#Events.OnClientCommand.handlers]
    handler(P.Module,"Sell",p,{requestId="one-1",itemType="Base.GoldCoin",mode="one"})
    T.eq(Test.ack.args.typeCount,1);T.eq(money(p),250)
    handler(P.Module,"Sell",p,{requestId="one-1",itemType="Base.GoldCoin",mode="one"})
    T.eq(money(p),250);T.eq(p.inventory:getItemCountRecurse("Base.GoldCoin"),1)
    handler(P.Module,"Sell",p,{requestId="one-1",itemType="Base.GoldCoin",mode="all"})
    T.eq(Test.ack.args.reason,"invalid_request");T.eq(money(p),250)
end)
T.case("malformed and failed bulk requests never debit and remain idempotent", function()
    local p=T.player({T.item("Base.Money",2)})
    local handler=Events.OnClientCommand.handlers[#Events.OnClientCommand.handlers]
    for _,args in ipairs({{requestId=3},{requestId=""},{requestId=string.rep("x",129)}})do
        handler(P.Module,"SellAll",p,args)
        T.eq(Test.ack.args.accepted,false);T.eq(Test.ack.args.reason,"invalid_request")
    end
    T.eq(money(p),0);T.eq(p.inventory:getItemCountRecurse("Base.Money"),2)
    p.inventory.failRemoval=1
    handler(P.Module,"SellAll",p,{requestId="failed-bulk"})
    T.eq(Test.ack.args.accepted,false);T.eq(Test.ack.args.reason,"remove_failed")
    p.inventory.failRemoval=nil
    handler(P.Module,"SellAll",p,{requestId="failed-bulk"})
    T.eq(Test.ack.args.accepted,false);T.eq(money(p),0)
    T.eq(p.inventory:getItemCountRecurse("Base.Money"),2)
end)
print("backend integration passed; cases="..T.cases.."; assertions="..T.assertions)
return "BACKEND_PASS", T.cases, T.assertions
