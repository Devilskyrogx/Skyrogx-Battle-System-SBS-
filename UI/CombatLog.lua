-- SBS/UI/CombatLog.lua
-- Журнал боя и журнал мастера

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local string_format = string.format
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove
local CreateFrame = CreateFrame
local GetTime = GetTime
local date = date
local C_Timer = C_Timer

-- Локальная ссылка на Backdrops (доступна после загрузки Utils)
local function GetBackdrops()
    return SBS.Utils and SBS.Utils.Backdrops
end

SBS.CombatLog = {
    CurrentTab = "battle",
    MasterLog = {},
    Frame = nil,
}

-- ═══════════════════════════════════════════════════════════
-- ДОБАВЛЕНИЕ ЗАПИСЕЙ
-- ═══════════════════════════════════════════════════════════

function SBS.CombatLog:Add(text, sender)
    -- Проверяем настройку журнала боя
    local logEnabled = SBS.Settings and SBS.Settings:Get("combatLogEnabled")
    if logEnabled == nil then
        logEnabled = true -- По умолчанию включен
    end

    if logEnabled then
        -- Режим журнала: записываем в журнал
        local entry = {
            time = date("%H:%M:%S"),
            sender = sender or UnitName("player"),
            text = text,
        }

        table.insert(SBS.db.global.combatLog, entry)

        -- Ограничиваем размер лога
        while #SBS.db.global.combatLog > SBS.Config.COMBAT_LOG_MAX do
            table.remove(SBS.db.global.combatLog, 1)
        end

        -- Обновляем окно если открыто
        if self.Frame and self.Frame:IsShown() and self.CurrentTab == "battle" then
            self:UpdateFrame()
        end
    else
        -- Режим чата: выводим в чат (две строки без timestamp)
        -- Разделяем text на две строки по " Результат:"
        local line1, line2 = text:match("^(.-)( Результат:.+)$")
        if line1 and line2 then
            print("|cFFFFA500[SBS]|r " .. line1)
            print("|cFFFFA500[SBS]|r" .. line2)
        else
            -- Если не удалось разделить, выводим как есть
            print("|cFFFFA500[SBS]|r " .. text)
        end
    end
end

function SBS.CombatLog:AddMasterLog(text, category)
    if not SBS.Sync:IsMaster() then return end
    
    local entry = {
        time = date("%H:%M:%S"),
        text = text,
        category = category or "system",
    }
    
    table.insert(self.MasterLog, entry)
    
    while #self.MasterLog > SBS.Config.MASTER_LOG_MAX do
        table.remove(self.MasterLog, 1)
    end
    
    if self.Frame and self.Frame:IsShown() and self.CurrentTab == "master" then
        self:UpdateFrame()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ХЕЛПЕРЫ ДЛЯ ТЕМНОГО СТИЛЯ
-- ═══════════════════════════════════════════════════════════

local function CreateDarkButton(parent, width, height, text, textColor)
    local Backdrops = GetBackdrops() or SBS.Utils.Backdrops
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop(Backdrops.Standard)
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    if textColor then
        btn.text:SetTextColor(textColor.r, textColor.g, textColor.b)
    end
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isActive then
            self:SetBackdropColor(0.15, 0.15, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end)
    
    return btn
end

local function SetButtonActive(btn, active)
    btn.isActive = active
    if active then
        btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
        btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    else
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
end

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ ОКНА
-- ═══════════════════════════════════════════════════════════

function SBS.CombatLog:CreateFrame()
    if self.Frame then return end
    
    local Backdrops = GetBackdrops() or SBS.Utils.Backdrops
    
    -- Главный фрейм
    local f = CreateFrame("Frame", "SBS_CombatLogFrame", UIParent, "BackdropTemplate")
    f:SetSize(400, 300)
    f:SetPoint("CENTER", 300, 0)
    f:SetBackdrop(Backdrops.Standard)
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(320, 200, 600, 500)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    
    -- Топ-бар
    local topBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    topBar:SetHeight(28)
    topBar:SetPoint("TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", 0, 0)
    topBar:SetBackdrop(Backdrops.NoEdge)
    topBar:SetBackdropColor(0.12, 0.12, 0.12, 1)
    
    -- Заголовок
    f.title = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER")
    f.title:SetText("|cFFFFD700Журнал боя|r")
    
    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -4, 0)
    close:SetBackdrop(Backdrops.Standard)
    close:SetBackdropColor(0.15, 0.15, 0.15, 1)
    close:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    
    close.x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.x:SetPoint("CENTER", 0, 1)
    close.x:SetText("X")
    close.x:SetTextColor(0.6, 0.6, 0.6)
    
    close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.15, 0.15, 1)
        self.x:SetTextColor(1, 1, 1)
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        self.x:SetTextColor(0.6, 0.6, 0.6)
    end)
    close:SetScript("OnClick", function() f:Hide() end)
    
    -- Панель вкладок
    local tabBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    tabBar:SetHeight(30)
    tabBar:SetPoint("TOPLEFT", 0, -28)
    tabBar:SetPoint("TOPRIGHT", 0, -28)
    tabBar:SetBackdrop(Backdrops.NoEdge)
    tabBar:SetBackdropColor(0.06, 0.06, 0.06, 1)
    
    -- Вкладка "Бой"
    f.tabBattle = CreateDarkButton(tabBar, 70, 24, "Бой", {r=1, g=0.82, b=0})
    f.tabBattle:SetPoint("LEFT", 8, 0)
    f.tabBattle:SetScript("OnClick", function()
        self.CurrentTab = "battle"
        self:UpdateTabs()
        self:UpdateFrame()
    end)
    
    -- Вкладка "Мастер"
    f.tabMaster = CreateDarkButton(tabBar, 70, 24, "Мастер", {r=0.63, g=0.42, b=0.95})
    f.tabMaster:SetPoint("LEFT", f.tabBattle, "RIGHT", 4, 0)
    f.tabMaster:SetScript("OnClick", function()
        if not SBS.Sync:IsMaster() then
            SBS.Utils:Error("Только для ведущего!")
            return
        end
        self.CurrentTab = "master"
        self:UpdateTabs()
        self:UpdateFrame()
    end)
    
    -- Кнопка очистки
    f.clearBtn = CreateDarkButton(tabBar, 70, 24, "Очистить", {r=0.7, g=0.7, b=0.7})
    f.clearBtn:SetPoint("RIGHT", -8, 0)
    f.clearBtn:SetScript("OnClick", function()
        if self.CurrentTab == "battle" then
            SBS.db.global.combatLog = {}
        else
            self.MasterLog = {}
        end
        self:UpdateFrame()
    end)
    
    -- Контейнер для лога
    local logContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    logContainer:SetPoint("TOPLEFT", 8, -66)
    logContainer:SetPoint("BOTTOMRIGHT", -8, 8)
    logContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    logContainer:SetBackdropColor(0.05, 0.05, 0.05, 1)
    logContainer:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    
    -- Скролл-область
    local scroll = CreateFrame("ScrollFrame", "SBS_LogScroll", logContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    
    -- Стилизация скроллбара
    local scrollBar = _G["SBS_LogScrollScrollBar"]
    if scrollBar then
        scrollBar:SetWidth(12)
    end
    
    f.content = CreateFrame("Frame", "SBS_LogContent", scroll)
    f.content:SetWidth(scroll:GetWidth())
    f.content:SetHeight(400)
    scroll:SetScrollChild(f.content)
    
    f.logText = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.logText:SetPoint("TOPLEFT", 4, -4)
    f.logText:SetWidth(scroll:GetWidth() - 8)
    f.logText:SetJustifyH("LEFT")
    f.logText:SetJustifyV("TOP")
    f.logText:SetSpacing(3)
    f.logText:SetWordWrap(true)
    
    f.scrollFrame = scroll
    f.logContainer = logContainer
    
    -- Ресайз
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        self:UpdateFrame()
    end)
    
    f:SetScript("OnSizeChanged", function(_, w)
        f.content:SetWidth(w - 50)
        f.logText:SetWidth(w - 58)
    end)
    
    topBar:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            f:StartMoving()
        end
    end)
    topBar:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
    end)
    
    self.Frame = f
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ
-- ═══════════════════════════════════════════════════════════

function SBS.CombatLog:UpdateTabs()
    if not self.Frame then return end
    
    local isBattle = self.CurrentTab == "battle"
    
    SetButtonActive(self.Frame.tabBattle, isBattle)
    SetButtonActive(self.Frame.tabMaster, not isBattle)
    
    self.Frame.title:SetText(isBattle and 
        "|cFFFFD700Журнал боя|r" or 
        "|cFFA06AF1Журнал мастера|r")
    
    if SBS.Sync:IsMaster() then
        self.Frame.tabMaster:Show()
    else
        self.Frame.tabMaster:Hide()
        self.CurrentTab = "battle"
    end
end

function SBS.CombatLog:UpdateFrame()
    if not self.Frame or not self.Frame:IsShown() then return end
    
    local f = self.Frame
    f.content:SetWidth(f:GetWidth() - 50)
    f.logText:SetWidth(f:GetWidth() - 58)
    
    local lines = {}
    local log = self.CurrentTab == "battle" and SBS.db.global.combatLog or self.MasterLog
    
    for _, entry in ipairs(log) do
        if self.CurrentTab == "battle" then
            table.insert(lines,
                "|cFF666666[" .. entry.time .. "]|r " .. entry.text)
        else
            local categoryColor = entry.category == "hp_change" and "FF9966" or
                                  (entry.category == "master_action" and "A06AF1" or "888888")
            table.insert(lines,
                "|cFF666666[" .. entry.time .. "]|r " ..
                "|cFF" .. categoryColor .. entry.text .. "|r")
        end
    end
    
    f.logText:SetText(#lines > 0 and table.concat(lines, "\n") or "|cFF666666Журнал пуст|r")
    f.content:SetHeight(math.max(f.logText:GetStringHeight() + 10, 100))
    
    -- Скролл вниз
    SBS.Addon:ScheduleTimer(function()
        if f.scrollFrame then
            f.scrollFrame:SetVerticalScroll(f.scrollFrame:GetVerticalScrollRange())
        end
    end, 0.01)
end

-- ═══════════════════════════════════════════════════════════
-- ПЕРЕКЛЮЧЕНИЕ
-- ═══════════════════════════════════════════════════════════

function SBS.CombatLog:Toggle()
    -- Проверяем настройку журнала боя
    local logEnabled = SBS.Settings and SBS.Settings:Get("combatLogEnabled")
    if logEnabled == nil then
        logEnabled = true -- По умолчанию включен
    end

    if not logEnabled then
        SBS.Utils:Error("Журнал боя выключен в настройках. Включите его в Интерфейс -> Модификации -> SBS")
        return
    end

    if not self.Frame then
        self:CreateFrame()
    end

    if self.Frame:IsShown() then
        self.Frame:Hide()
    else
        self.Frame:Show()
        self:UpdateTabs()
        self:UpdateFrame()
    end
end

-- Алиасы перенесены в Core/Aliases.lua
