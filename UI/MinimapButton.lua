-- SBS/UI/MinimapButton.lua
-- Кнопка на миникарте (WoW 11.0.2+)

local ADDON_NAME, SBS = ...

SBS.UI = SBS.UI or {}

function SBS.UI:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")
    
    -- Создаём Data Broker объект
    local dataBroker = LDB:NewDataObject("SBS", {
        type = "launcher",
        text = "SBS",
        icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
        OnClick = function(_, button)
            if button == "LeftButton" then
                SBS.UI:ToggleMainFrame()
            elseif button == "RightButton" then
                SBS.CombatLog:Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("SBS Battle System", 1, 0.85, 0)
            tooltip:AddLine("ЛКМ - открыть окно", 1, 1, 1)
            tooltip:AddLine("ПКМ - журнал боя", 1, 1, 1)
            if SBS.Sync:IsMaster() then
                tooltip:AddLine(SBS.Utils:Color("A06AF1", "Вы мастер"))
            elseif SBS.Sync:GetMasterName() then
                tooltip:AddLine("Мастер: " .. SBS.Sync:GetMasterName(), 0.7, 0.7, 0.7)
            end
        end,
    })
    
    -- Инициализируем настройки для иконки
    if not SBS.db.profile.minimap then
        SBS.db.profile.minimap = { hide = false }
    end
    
    -- Регистрируем иконку
    LDBIcon:Register("SBS", dataBroker, SBS.db.profile.minimap)
end
