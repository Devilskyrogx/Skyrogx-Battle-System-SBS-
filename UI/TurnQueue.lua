-- SBS/UI/TurnQueue.lua
-- Окно очереди пошагового боя

local ADDON_NAME, SBS = ...

-- ═══════════════════════════════════════════════════════════
-- КЭШИРОВАНИЕ ГЛОБАЛЬНЫХ ФУНКЦИЙ
-- ═══════════════════════════════════════════════════════════
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local string_format = string.format
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove
local wipe = wipe
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GameTooltip = GameTooltip
local PlaySound = PlaySound
local C_Timer = C_Timer

-- Локальные ссылки
local TurnQueueFrame = nil
local YourTurnFrame = nil



-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ ОКНА ОЧЕРЕДИ
-- ═══════════════════════════════════════════════════════════

local function CreateTurnQueueFrame()
    if TurnQueueFrame then return TurnQueueFrame end

    local f = CreateFrame("Frame", "SBS_TurnQueueFrame", UIParent, "BackdropTemplate")
    f:SetSize(270, 300)  -- Ширина для HP, энергии и эффектов
    f:SetPoint("TOP", 0, -100)
    f:SetBackdrop(SBS.Utils.Backdrops.Standard)
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    
    -- Топ-бар
    local topBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    topBar:SetHeight(26)
    topBar:SetPoint("TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", 0, 0)
    topBar:SetBackdrop(SBS.Utils.Backdrops.NoEdge)
    topBar:SetBackdropColor(0.12, 0.12, 0.12, 1)
    topBar:EnableMouse(true)
    topBar:RegisterForDrag("LeftButton")
    topBar:SetScript("OnDragStart", function() f:StartMoving() end)
    topBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.topBar = topBar
    
    -- Заголовок
    f.title = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER")
    f.title:SetText("|cFFFFD700РАУНД 1|r")
    
    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -3, 0)
    close:SetBackdrop(SBS.Utils.Backdrops.Standard)
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
    close:SetScript("OnClick", function()
        f:Hide()
        SBS.Utils:Info("Окно очереди скрыто. Для открытия: |cFF00FF00/sbscombat queue|r")
    end)
    
    -- Таймер
    f.timerBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.timerBar:SetHeight(20)
    f.timerBar:SetPoint("TOPLEFT", 0, -26)
    f.timerBar:SetPoint("TOPRIGHT", 0, -26)
    f.timerBar:SetBackdrop(SBS.Utils.Backdrops.NoEdge)
    f.timerBar:SetBackdropColor(0.06, 0.06, 0.06, 1)
    
    f.timerText = f.timerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.timerText:SetPoint("CENTER")
    f.timerText:SetText("|cFFFFFF001:00|r")
    
    -- Контейнер списка (привязан сверху и снизу для правильного позиционирования)
    local listContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listContainer:SetPoint("TOPLEFT", 4, -50)
    listContainer:SetPoint("TOPRIGHT", -4, -50)
    listContainer:SetPoint("BOTTOM", 0, 48)  -- Отступ снизу для кнопок (28) + ресайзер (8) + отступы (12)
    listContainer:SetBackdrop(SBS.Utils.Backdrops.Standard)
    listContainer:SetBackdropColor(0.05, 0.05, 0.05, 1)
    listContainer:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    
    -- Скролл
    local scroll = CreateFrame("ScrollFrame", "SBS_TurnQueueScroll", listContainer)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -14, 4)  -- Уменьшили отступ справа для кастомного скроллбара
    
    f.content = CreateFrame("Frame", "SBS_TurnQueueContent", scroll)
    f.content:SetWidth(scroll:GetWidth())
    f.content:SetHeight(200)
    scroll:SetScrollChild(f.content)
    
    -- Кастомный скроллбар
    local scrollBar = CreateFrame("Frame", nil, listContainer, "BackdropTemplate")
    scrollBar:SetWidth(8)
    scrollBar:SetPoint("TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", -4, 4)
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        edgeSize = 0,
    })
    scrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    scrollBar:Hide()  -- Скрыт по умолчанию
    
    -- Ползунок скроллбара
    local scrollThumb = CreateFrame("Frame", nil, scrollBar, "BackdropTemplate")
    scrollThumb:SetWidth(8)
    scrollThumb:SetHeight(30)
    scrollThumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        edgeSize = 0,
    })
    scrollThumb:SetBackdropColor(0.4, 0.4, 0.4, 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    
    -- Подсветка при наведении
    scrollThumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.6, 0.6, 1)
    end)
    scrollThumb:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.4, 0.4, 1)
    end)
    
    -- Драг для ползунка
    local isDragging = false
    local startY = 0
    
    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
            startY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            self:SetBackdropColor(0.7, 0.7, 0.7, 1)
        end
    end)
    
    scrollThumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            isDragging = false
            if self:IsMouseOver() then
                self:SetBackdropColor(0.6, 0.6, 0.6, 1)
            else
                self:SetBackdropColor(0.4, 0.4, 0.4, 1)
            end
        end
    end)
    
    scrollThumb:SetScript("OnUpdate", function(self)
        if isDragging then
            local curY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta = startY - curY
            startY = curY
            
            local maxScroll = f.content:GetHeight() - scroll:GetHeight()
            if maxScroll > 0 then
                local currentScroll = scroll:GetVerticalScroll()
                local scrollBarHeight = scrollBar:GetHeight()
                local thumbHeight = self:GetHeight()
                local scrollRatio = delta / (scrollBarHeight - thumbHeight) * maxScroll
                
                local newScroll = math.max(0, math.min(maxScroll, currentScroll + scrollRatio))
                scroll:SetVerticalScroll(newScroll)
            end
        end
    end)
    
    -- Обновление позиции ползунка при скролле
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        local maxScroll = f.content:GetHeight() - self:GetHeight()
        if maxScroll > 0 then
            local scrollRatio = offset / maxScroll
            local scrollBarHeight = scrollBar:GetHeight()
            local thumbHeight = scrollThumb:GetHeight()
            local maxThumbOffset = scrollBarHeight - thumbHeight
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -scrollRatio * maxThumbOffset)
        end
    end)
    
    -- Скролл колесом мыши
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = f.content:GetHeight() - self:GetHeight()
        if maxScroll > 0 then
            local current = self:GetVerticalScroll()
            local step = 40  -- Шаг скролла
            local newScroll = math.max(0, math.min(maxScroll, current - delta * step))
            self:SetVerticalScroll(newScroll)
        end
    end)
    
    f.scrollFrame = scroll
    f.scrollBar = scrollBar
    f.scrollThumb = scrollThumb
    f.listContainer = listContainer
    f.rows = {}
    
    -- Ресайз по вертикали
    f:SetResizable(true)
    f:SetMinResize(270, 200)
    f:SetMaxResize(270, 800)
    
    -- Значок ресайза (внизу по центру)
    local resizer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    resizer:SetSize(30, 8)
    resizer:SetPoint("BOTTOM", 0, 0)
    resizer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        edgeSize = 0,
    })
    resizer:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    resizer:EnableMouse(true)
    resizer:SetFrameLevel(f:GetFrameLevel() + 10)
    
    -- Иконка ресайза (три горизонтальные линии)
    local icon1 = resizer:CreateTexture(nil, "OVERLAY")
    icon1:SetSize(20, 1)
    icon1:SetPoint("CENTER", 0, 2)
    icon1:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local icon2 = resizer:CreateTexture(nil, "OVERLAY")
    icon2:SetSize(20, 1)
    icon2:SetPoint("CENTER", 0, 0)
    icon2:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local icon3 = resizer:CreateTexture(nil, "OVERLAY")
    icon3:SetSize(20, 1)
    icon3:SetPoint("CENTER", 0, -2)
    icon3:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    resizer:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
        icon1:SetColorTexture(0.8, 0.8, 0.8, 1)
        icon2:SetColorTexture(0.8, 0.8, 0.8, 1)
        icon3:SetColorTexture(0.8, 0.8, 0.8, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Изменить высоту окна", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    resizer:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        icon1:SetColorTexture(0.5, 0.5, 0.5, 1)
        icon2:SetColorTexture(0.5, 0.5, 0.5, 1)
        icon3:SetColorTexture(0.5, 0.5, 0.5, 1)
        GameTooltip:Hide()
    end)
    
    local isResizing = false
    local startHeight = 0
    local startY = 0
    local startTop = 0
    local startLeft = 0
    
    -- Флаг что пользователь вручную изменил размер
    f.userResized = false
    
    resizer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isResizing = true
            startHeight = f:GetHeight()
            startY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            -- Запоминаем позицию верха окна
            startTop = f:GetTop()
            startLeft = f:GetLeft()
            self:SetBackdropColor(0.35, 0.35, 0.35, 1)
        end
    end)
    
    resizer:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            isResizing = false
            f.userResized = true  -- Помечаем что пользователь изменил размер
            if self:IsMouseOver() then
                self:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
            else
                self:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            end
        end
    end)
    
    resizer:SetScript("OnUpdate", function(self)
        if isResizing then
            local curY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta = startY - curY
            local newHeight = math.max(200, math.min(800, startHeight + delta))
            
            -- Сохраняем позицию верха окна неизменной (окно растёт вниз)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", startLeft, startTop)
            f:SetHeight(newHeight)
            -- listContainer автоматически подстроится благодаря привязке к BOTTOM
        end
    end)
    
    f.resizer = resizer
    
    -- Контейнер для кнопок (центрированный)
    f.buttonContainer = CreateFrame("Frame", nil, f)
    f.buttonContainer:SetSize(208, 28)  -- 4 кнопки по 48px + 3 отступа по 4px = 204px + немного запаса
    f.buttonContainer:SetPoint("BOTTOM", 0, 10)  -- Подняли чуть выше чтобы не перекрывать ресайзер


    -- Кнопка Атака (первая)
    f.attackBtn = CreateFrame("Button", nil, f.buttonContainer, "BackdropTemplate")
    f.attackBtn:SetSize(48, 28)
    f.attackBtn:SetPoint("LEFT", 0, 0)
    f.attackBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    f.attackBtn:SetBackdropColor(0.5, 0.15, 0.1, 1)
    f.attackBtn:SetBackdropBorderColor(0.7, 0.2, 0.15, 1)
    
    f.attackBtn.text = f.attackBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.attackBtn.text:SetPoint("CENTER")
    f.attackBtn.text:SetText("|cFFFF6666Атака|r")
    
    f.attackBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.2, 0.15, 1)
    end)
    f.attackBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.15, 0.1, 1)
    end)
    f.attackBtn:SetScript("OnClick", function(self)
        SBS.UI:ShowTurnQueueAttackMenu(self)
    end)
    
    -- Кнопка Исцеление (вторая)
    f.healBtn = CreateFrame("Button", nil, f.buttonContainer, "BackdropTemplate")
    f.healBtn:SetSize(48, 28)
    f.healBtn:SetPoint("LEFT", f.attackBtn, "RIGHT", 4, 0)
    f.healBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    f.healBtn:SetBackdropColor(0.1, 0.4, 0.2, 1)
    f.healBtn:SetBackdropBorderColor(0.15, 0.6, 0.3, 1)
    
    f.healBtn.text = f.healBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.healBtn.text:SetPoint("CENTER")
    f.healBtn.text:SetText("|cFF66FF66Лечение|r")
    
    f.healBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.5, 0.25, 1)
    end)
    f.healBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.4, 0.2, 1)
    end)
    f.healBtn:SetScript("OnClick", function(self)
        SBS.UI:ShowTurnQueueHealMenu(self)
    end)
    
    -- Кнопка Эффекты (третья)
    f.effectBtn = CreateFrame("Button", nil, f.buttonContainer, "BackdropTemplate")
    f.effectBtn:SetSize(48, 28)
    f.effectBtn:SetPoint("LEFT", f.healBtn, "RIGHT", 4, 0)
    f.effectBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    f.effectBtn:SetBackdropColor(0.4, 0.25, 0.1, 1)
    f.effectBtn:SetBackdropBorderColor(0.6, 0.4, 0.15, 1)
    
    f.effectBtn.text = f.effectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.effectBtn.text:SetPoint("CENTER")
    f.effectBtn.text:SetText("|cFFFF9933Эффект|r")
    
    f.effectBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.35, 0.15, 1)
    end)
    f.effectBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.25, 0.1, 1)
    end)
    f.effectBtn:SetScript("OnClick", function(self)
        SBS.UI:ShowTurnQueueEffectMenu(self)
    end)
    
    -- Кнопка Пропуск (четвёртая)
    f.skipBtn = CreateFrame("Button", nil, f.buttonContainer, "BackdropTemplate")
    f.skipBtn:SetSize(48, 28)
    f.skipBtn:SetPoint("LEFT", f.effectBtn, "RIGHT", 4, 0)
    f.skipBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    f.skipBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    f.skipBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    f.skipBtn.text = f.skipBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.skipBtn.text:SetPoint("CENTER")
    f.skipBtn.text:SetText("Пропуск")
    f.skipBtn.text:SetTextColor(0.8, 0.8, 0.8)
    
    f.skipBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)
    f.skipBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end)
    f.skipBtn:SetScript("OnClick", function(self)
        -- Отключаем кнопку на короткое время чтобы предотвратить двойной клик
        self:Disable()
        C_Timer.After(0.1, function()
            if self:IsShown() then
                self:Enable()
            end
        end)

        if SBS.Sync:IsMaster() then
            SBS.TurnSystem:SkipTurn()
        else
            SBS.TurnSystem:PlayerSkipTurn()
        end
    end)
    
    -- NPC текст (показывается во время фазы NPC - компактное окно без заголовка)
    f.npcText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.npcText:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.npcText:SetText("|cFFA06AF1ХОД ПРОТИВНИКА|r")
    f.npcText:Hide()
    
    TurnQueueFrame = f
    return f
end

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ СТРОКИ УЧАСТНИКА (РАСШИРЕННАЯ ВЕРСИЯ)
-- ═══════════════════════════════════════════════════════════

local ROW_HEIGHT = 56  -- Высота для HP, энергии и эффектов

local function CreateParticipantRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetBackdrop(SBS.Utils.Backdrops.Standard)
    row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    row:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.5)

    -- ═══ ВЕРХНЯЯ СТРОКА: Индикатор + Имя + Инициатива + Статус ═══
    local topRow = CreateFrame("Frame", nil, row)
    topRow:SetHeight(18)
    topRow:SetPoint("TOPLEFT", 2, -2)
    topRow:SetPoint("TOPRIGHT", -2, -2)

    -- Индикатор текущего хода
    row.indicator = topRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.indicator:SetPoint("LEFT", 2, 0)
    row.indicator:SetText("")
    row.indicator:SetWidth(12)

    -- Имя (ограничиваем ширину чтобы не наезжало на roll)
    row.name = topRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", 14, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(140)

    -- Статус (OK или >>)
    row.status = topRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("RIGHT", -2, 0)
    row.status:SetJustifyH("RIGHT")
    row.status:SetWidth(24)

    -- Инициатива (между именем и статусом)
    row.roll = topRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.roll:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
    row.roll:SetJustifyH("RIGHT")
    row.roll:SetTextColor(0.6, 0.6, 0.6)

    -- Кнопка пропуска (только для мастера в свободном режиме)
    row.skipBtn = CreateFrame("Button", nil, topRow, "BackdropTemplate")
    row.skipBtn:SetSize(50, 14)
    row.skipBtn:SetPoint("RIGHT", -2, 0)
    row.skipBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    row.skipBtn:SetBackdropColor(0.2, 0.15, 0.1, 1)
    row.skipBtn:SetBackdropBorderColor(0.4, 0.3, 0.2, 1)
    row.skipBtn:Hide()  -- По умолчанию скрыта

    row.skipBtn.text = row.skipBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.skipBtn.text:SetPoint("CENTER")
    row.skipBtn.text:SetText("Пропуск")
    row.skipBtn.text:SetTextColor(0.8, 0.7, 0.6)

    row.skipBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.25, 0.15, 1)
    end)
    row.skipBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.15, 0.1, 1)
    end)
    row.skipBtn:SetScript("OnClick", function(self)
        if self.playerGUID and SBS.TurnSystem then
            SBS.TurnSystem:SkipPlayerTurn(self.playerGUID)
        end
    end)

    -- ═══ СРЕДНЯЯ СТРОКА: HP бар + Энергия ═══
    local midRow = CreateFrame("Frame", nil, row)
    midRow:SetHeight(14)
    midRow:SetPoint("TOPLEFT", 4, -20)
    midRow:SetPoint("TOPRIGHT", -4, -20)

    -- HP Bar (Status Bar)
    row.hpBar = CreateFrame("StatusBar", nil, midRow, "BackdropTemplate")
    row.hpBar:SetHeight(12)
    row.hpBar:SetPoint("LEFT", 0, 0)
    row.hpBar:SetPoint("RIGHT", -55, 0)
    row.hpBar:SetMinMaxValues(0, 10)
    row.hpBar:SetValue(10)
    row.hpBar:SetStatusBarTexture("Interface\\AddOns\\SBS\\texture\\bar_texture")
    row.hpBar:SetStatusBarColor(0.1, 0.6, 0.2)
    row.hpBar:SetBackdrop(SBS.Utils.Backdrops.Standard)
    row.hpBar:SetBackdropColor(0.05, 0.05, 0.05, 1)
    row.hpBar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- HP Text внутри бара
    row.hpText = row.hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.hpText:SetPoint("CENTER")
    row.hpText:SetTextColor(1, 1, 1)
    row.hpText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")

    -- Shield Bar (поверх HP)
    row.shieldBar = CreateFrame("StatusBar", nil, row.hpBar)
    row.shieldBar:SetAllPoints()
    row.shieldBar:SetMinMaxValues(0, 10)
    row.shieldBar:SetValue(0)
    row.shieldBar:SetStatusBarTexture("Interface\\AddOns\\SBS\\texture\\bar_texture")
    row.shieldBar:SetStatusBarColor(0.4, 0.7, 1, 0.5)
    row.shieldBar:SetFrameLevel(row.hpBar:GetFrameLevel() + 1)

    -- Энергия (точки справа от HP)
    row.energyFrame = CreateFrame("Frame", nil, midRow)
    row.energyFrame:SetSize(50, 12)
    row.energyFrame:SetPoint("RIGHT", 0, 0)

    row.energyDots = {}
    for i = 1, 5 do
        local dot = row.energyFrame:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", (i-1) * 10, 0)
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        dot:SetVertexColor(0.2, 0.2, 0.2)
        row.energyDots[i] = dot
    end

    -- ═══ НИЖНЯЯ СТРОКА: Эффекты ═══
    local bottomRow = CreateFrame("Frame", nil, row)
    bottomRow:SetHeight(18)
    bottomRow:SetPoint("TOPLEFT", 4, -36)
    bottomRow:SetPoint("TOPRIGHT", -4, -36)
    row.effectsRow = bottomRow

    -- Контейнер для иконок эффектов
    row.effectIcons = {}
    for i = 1, 10 do
        local icon = CreateFrame("Frame", nil, bottomRow, "BackdropTemplate")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", (i-1) * 18, 0)
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        icon:SetBackdropColor(0.1, 0.1, 0.1, 1)
        icon:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        icon:Hide()

        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetPoint("TOPLEFT", 1, -1)
        icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)

        icon.stacks = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        icon.stacks:SetPoint("BOTTOMRIGHT", 2, -2)
        icon.stacks:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        icon.stacks:SetTextColor(1, 1, 1)

        icon:EnableMouse(true)
        icon:SetScript("OnEnter", function(self)
            if self.effectId and self.effectData then
                local def = SBS.Effects.Definitions[self.effectId]
                if def then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    local typeColor = def.type == "buff" and "00FF00" or "FF4444"
                    GameTooltip:AddLine("|cFF" .. typeColor .. def.name .. "|r")
                    if def.description then
                        GameTooltip:AddLine(def.description, 1, 1, 1, true)
                    end
                    GameTooltip:AddLine("Осталось раундов: " .. (self.effectData.remainingRounds or 0), 0.7, 0.7, 0.7)
                    local val = self.effectData.value or 0
                    if val > 0 then
                        GameTooltip:AddLine("Значение: " .. val, 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end
            end
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.effectIcons[i] = icon
    end

    return row
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ ОКНА ОЧЕРЕДИ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:UpdateTurnQueue()
    -- Обновляем кнопки GM панели
    if self.UpdateGMCombatButtons then
        self:UpdateGMCombatButtons()
    end
    
    -- Обновляем кнопки действий в главном окне
    if self.UpdateActionButtons then
        self:UpdateActionButtons()
    end
    
    local f = TurnQueueFrame
    if not f then return end
    
    local ts = SBS.TurnSystem
    
    -- Скрываем если бой не активен
    if not ts:IsActive() then
        f:Hide()
        return
    end
    
    -- Фаза NPC - компактное окно с заголовком для перемещения
    if ts.phase == "npc" then
        f.topBar:Show()
        f.title:SetText("|cFFA06AF1ХОД ПРОТИВНИКА|r")
        f.scrollFrame:Hide()
        f.listContainer:Hide()
        f.skipBtn:Hide()
        f.attackBtn:Hide()
        f.effectBtn:Hide()
        f.healBtn:Hide()
        f.timerBar:Hide()
        f.npcText:Hide()
        -- Компактное перемещаемое окно
        f:SetSize(220, 50)
        return
    else
        -- Фаза игроков - показываем всё
        f.npcText:Hide()
        f.topBar:Show()
        f.scrollFrame:Show()
        f.listContainer:Show()
        f.timerBar:Show()
    end
    
    -- Сброс пользовательского размера при новом бое (раунд 1)
    if ts.round == 1 and f.lastRound ~= 1 then
        f.userResized = false
    end
    f.lastRound = ts.round
    
    -- Заголовок
    f.title:SetText("|cFFFFD700РАУНД " .. ts.round .. "|r")

    -- Таймер (показывается по-разному в зависимости от режима и настройки)
    if ts.useTimer then
        local remaining = 0
        if ts.mode == "queue" then
            remaining = ts:GetTimeRemaining()  -- Таймер хода
        else
            remaining = ts:GetRoundTimeRemaining()  -- Таймер раунда
        end

        local mins = math.floor(remaining / 60)
        local secs = math.floor(remaining % 60)
        local timerColor = remaining <= 10 and "FF6666" or (remaining <= 30 and "FFFF00" or "FFFFFF")
        f.timerText:SetText("|cFF" .. timerColor .. mins .. ":" .. string.format("%02d", secs) .. "|r")
        f.timerBar:Show()
    else
        -- Таймер выключен - скрываем
        f.timerBar:Hide()
    end
    
    -- Создаём/обновляем строки
    local contentWidth = f.content:GetWidth()
    local yOffset = 0
    local participantCount = #ts.participants
    local myName = UnitName("player")

    for i, p in ipairs(ts.participants) do
        local row = f.rows[i]
        if not row then
            row = CreateParticipantRow(f.content, i)
            f.rows[i] = row
        end

        row:SetPoint("TOPLEFT", 2, -yOffset)
        row:SetPoint("TOPRIGHT", -2, -yOffset)
        row:Show()

        -- Подсветка текущего хода
        local myGUID = UnitGUID("player")
        local isMe = (p.guid == myGUID)
        local isCurrent = (i == ts.currentIndex)

        if ts.mode == "queue" then
            -- Очередной режим - подсветка текущего игрока
            if isCurrent then
                row:SetBackdropColor(0.15, 0.35, 0.15, 0.9)
                row:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
                row.indicator:SetText("|cFF00FF00>|r")
            else
                if isMe then
                    row:SetBackdropColor(0.12, 0.12, 0.22, 0.8)
                    row:SetBackdropBorderColor(0.2, 0.2, 0.4, 0.8)
                else
                    row:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
                    row:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.5)
                end
                row.indicator:SetText("")
            end
        else
            -- Свободный режим - нет индикатора текущего хода
            row.indicator:SetText("")
            if isMe then
                row:SetBackdropColor(0.12, 0.12, 0.22, 0.8)
                row:SetBackdropBorderColor(0.2, 0.2, 0.4, 0.8)
            else
                row:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
                row:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.5)
            end
        end

        -- Имя
        local nameColor = isMe and "66CCFF" or "FFFFFF"
        row.name:SetText("|cFF" .. nameColor .. p.name .. "|r")

        -- Инициатива (показываем только в очередном режиме)
        if ts.mode == "queue" then
            row.roll:SetText("[" .. p.roll .. "]")
            row.roll:Show()
        else
            row.roll:Hide()
        end

        -- Проверяем внеочередной ход
        local hasFreeAction = (ts.freeActionGUID and ts.freeActionGUID == p.guid)

        -- Статус
        if ts.mode == "queue" then
            -- Очередной режим - показываем ">>" для текущего
            if p.acted then
                row.status:SetText("|cFF00FF00OK|r")
            elseif hasFreeAction then
                -- Пометка о внеочередном ходе (золотая звёздочка)
                row.status:SetText("|cFFFFD700★|r")
            elseif isCurrent then
                row.status:SetText("|cFFFFFF00>>|r")
            else
                row.status:SetText("")
            end
        else
            -- Свободный режим - только OK для сходивших
            if p.acted then
                row.status:SetText("|cFF00FF00OK|r")
            elseif hasFreeAction then
                -- Пометка о внеочередном ходе (золотая звёздочка)
                row.status:SetText("|cFFFFD700★|r")
            else
                row.status:SetText("")
            end
        end
        
        -- Подсветка строки для внеочередного хода
        if hasFreeAction and not p.acted then
            row:SetBackdropColor(0.25, 0.2, 0.05, 0.9)
            row:SetBackdropBorderColor(0.9, 0.7, 0.2, 1)
        end

        -- Кнопка пропуска (только в свободном режиме для мастера)
        if ts.mode == "free" and SBS.Sync:IsMaster() and not p.acted then
            row.skipBtn:Show()
            row.skipBtn.playerGUID = p.guid
            -- Сдвигаем статус влево
            row.status:ClearAllPoints()
            row.status:SetPoint("RIGHT", row.skipBtn, "LEFT", -4, 0)
        else
            row.skipBtn:Hide()
            -- Возвращаем статус на место
            row.status:ClearAllPoints()
            row.status:SetPoint("RIGHT", -2, 0)
        end

        -- ═══ ПОЛУЧЕНИЕ ДАННЫХ ИГРОКА ═══
        local hp, maxHp, shield, energy, maxEnergy = 0, 10, 0, 0, 2
        local playerData = nil

        if isMe then
            -- Свои данные берём напрямую
            hp = SBS.Stats:GetCurrentHP()
            maxHp = SBS.Stats:GetMaxHP()
            shield = SBS.Stats:GetShield()
            energy = SBS.Stats:GetEnergy()
            maxEnergy = SBS.Stats:GetMaxEnergy()
        else
            -- Данные других игроков из синхронизации
            playerData = SBS.Sync.RaidData[p.name]
            if playerData then
                hp = playerData.hp or 0
                maxHp = playerData.maxHp or 10
                shield = playerData.shield or 0
                energy = playerData.energy or 0
                maxEnergy = playerData.maxEnergy or 2
            end
        end

        -- ═══ HP BAR ═══
        row.hpBar:SetMinMaxValues(0, maxHp)
        row.hpBar:SetValue(hp)

        -- Цвет HP бара в зависимости от процента
        local hpPercent = maxHp > 0 and (hp / maxHp) or 0
        if hpPercent > 0.5 then
            row.hpBar:SetStatusBarColor(0.1, 0.6, 0.2)
        elseif hpPercent > 0.25 then
            row.hpBar:SetStatusBarColor(0.8, 0.6, 0.1)
        else
            row.hpBar:SetStatusBarColor(0.7, 0.15, 0.1)
        end

        -- HP текст
        local hpText = hp .. "/" .. maxHp
        if shield > 0 then
            hpText = hpText .. " |cFF66CCFF+" .. shield .. "|r"
        end
        row.hpText:SetText(hpText)

        -- Shield bar
        if shield > 0 then
            row.shieldBar:SetMinMaxValues(0, maxHp)
            row.shieldBar:SetValue(math.min(shield, maxHp))
            row.shieldBar:Show()
        else
            row.shieldBar:Hide()
        end

        -- ═══ ЭНЕРГИЯ ═══
        for e = 1, 5 do
            if e <= maxEnergy then
                row.energyDots[e]:Show()
                if e <= energy then
                    row.energyDots[e]:SetVertexColor(0.5, 0.3, 0.8)  -- Заполненная
                else
                    row.energyDots[e]:SetVertexColor(0.15, 0.15, 0.15)  -- Пустая
                end
            else
                row.energyDots[e]:Hide()
            end
        end

        -- ═══ ЭФФЕКТЫ ═══
        local effects = SBS.Effects:GetAll("player", p.name)
        local effectIndex = 1

        for effectId, effectData in pairs(effects) do
            if effectIndex <= 10 then
                local icon = row.effectIcons[effectIndex]
                local def = SBS.Effects.Definitions[effectId]

                if def then
                    icon:Show()
                    icon.texture:SetTexture(def.icon)
                    icon.effectId = effectId
                    icon.effectData = effectData

                    -- Цвет рамки по типу эффекта
                    if def.type == "buff" then
                        icon:SetBackdropBorderColor(0.2, 0.7, 0.2, 1)
                    elseif def.type == "debuff" or def.type == "dot" then
                        icon:SetBackdropBorderColor(0.7, 0.2, 0.2, 1)
                    else
                        icon:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                    end

                    -- Стаки
                    if effectData.stacks and effectData.stacks > 1 then
                        icon.stacks:SetText(effectData.stacks)
                        icon.stacks:Show()
                    else
                        icon.stacks:Hide()
                    end

                    effectIndex = effectIndex + 1
                end
            end
        end

        -- Скрываем неиспользуемые иконки эффектов
        for e = effectIndex, 10 do
            row.effectIcons[e]:Hide()
        end

        yOffset = yOffset + ROW_HEIGHT + 2
    end

    -- Скрываем лишние строки
    for i = participantCount + 1, #f.rows do
        f.rows[i]:Hide()
    end

    f.content:SetHeight(math.max(yOffset, 50))

    -- Показываем/скрываем скроллбар в зависимости от количества участников
    if participantCount > 3 then
        f.scrollBar:Show()
    else
        f.scrollBar:Hide()
    end

    -- Автоматический расчёт высоты окна только если пользователь не изменял размер вручную
    if not f.userResized then
        local maxVisibleRows = 5
        local maxListHeight = maxVisibleRows * (ROW_HEIGHT + 2) + 16
        local listHeight = math.min(participantCount * (ROW_HEIGHT + 2) + 16, maxListHeight)
        local totalHeight = 26 + 20 + listHeight + 48  -- topbar + timer + list + buttons area
        if not ts.useTimer then totalHeight = totalHeight - 20 end
        -- Минимальная высота окна для красивого вида
        totalHeight = math.max(totalHeight, 200)
        f:SetSize(270, totalHeight)
        -- listContainer автоматически подстроится благодаря привязке к BOTTOM
    end
    -- При ручном ресайзе listContainer тоже автоматически подстроится
    
    -- Кнопки действий - показываем все кнопки, но активируем только когда можно действовать
    local canAct = false
    if ts.mode == "queue" then
        -- Очередной режим - можем действовать если наш ход или мастер
        canAct = ts:IsMyTurn() or SBS.Sync:IsMaster()
    else
        -- Свободный режим - можем действовать если ещё не ходили или мастер
        local myGUID = UnitGUID("player")
        local myActed = false
        for _, participant in ipairs(ts.participants) do
            if participant.guid == myGUID then
                myActed = participant.acted
                break
            end
        end
        canAct = (not myActed) or SBS.Sync:IsMaster()
    end

    if ts.phase == "players" then
        -- Показываем все кнопки
        f.attackBtn:Show()
        f.healBtn:Show()
        f.effectBtn:Show()
        f.skipBtn:Show()

        -- Активируем/деактивируем в зависимости от возможности действовать
        if canAct then
            f.attackBtn:Enable()
            f.attackBtn:SetAlpha(1)
            f.healBtn:Enable()
            f.healBtn:SetAlpha(1)
            f.effectBtn:Enable()
            f.effectBtn:SetAlpha(1)
            f.skipBtn:Enable()
            f.skipBtn:SetAlpha(1)
        else
            f.attackBtn:Disable()
            f.attackBtn:SetAlpha(0.5)
            f.healBtn:Disable()
            f.healBtn:SetAlpha(0.5)
            f.effectBtn:Disable()
            f.effectBtn:SetAlpha(0.5)
            f.skipBtn:Disable()
            f.skipBtn:SetAlpha(0.5)
        end
    else
        f.skipBtn:Hide()
        f.attackBtn:Hide()
        f.effectBtn:Hide()
        f.healBtn:Hide()
    end
end

function SBS.UI:UpdateTurnTimer(remaining)
    local f = TurnQueueFrame
    if not f or not f:IsShown() then return end

    local ts = SBS.TurnSystem
    if not ts.useTimer then
        -- Таймер выключен
        f.timerBar:Hide()
        return
    end

    local mins = math.floor(remaining / 60)
    local secs = math.floor(remaining % 60)
    local timerColor = remaining <= 10 and "FF6666" or (remaining <= 30 and "FFFF00" or "FFFFFF")
    f.timerText:SetText("|cFF" .. timerColor .. mins .. ":" .. string.format("%02d", secs) .. "|r")
    f.timerBar:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ/СКРЫТЬ ОКНО
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ShowTurnQueue()
    local f = CreateTurnQueueFrame()
    f:Show()
    self:UpdateTurnQueue()
end

function SBS.UI:HideTurnQueue()
    if TurnQueueFrame then
        TurnQueueFrame:Hide()
    end
end

function SBS.UI:ToggleTurnQueue()
    local f = CreateTurnQueueFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:UpdateTurnQueue()
    end
end

-- ═══════════════════════════════════════════════════════════
-- УВЕДОМЛЕНИЯ О ФАЗАХ
-- ═══════════════════════════════════════════════════════════

local PhaseAlertFrame = nil

local function CreatePhaseAlertFrame()
    if PhaseAlertFrame then return PhaseAlertFrame end
    
    local f = CreateFrame("Frame", "SBS_PhaseAlertFrame", UIParent, "BackdropTemplate")
    f:SetSize(300, 100)
    f:SetPoint("CENTER", 0, 150)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetFrameStrata("DIALOG")
    f:Hide()
    
    -- Заголовок фазы (сверху)
    f.phaseText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.phaseText:SetPoint("TOP", 0, -12)
    f.phaseText:SetText("")
    
    -- Основной текст (по центру)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER", 0, 5)
    f.text:SetText("")
    
    -- Подсказка (снизу)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.hint:SetPoint("BOTTOM", 0, 12)
    f.hint:SetText("")
    
    -- Анимация появления
    f.fadeIn = f:CreateAnimationGroup()
    local alpha = f.fadeIn:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.3)
    
    -- Анимация исчезновения
    f.fadeOut = f:CreateAnimationGroup()
    local alphaOut = f.fadeOut:CreateAnimation("Alpha")
    alphaOut:SetFromAlpha(1)
    alphaOut:SetToAlpha(0)
    alphaOut:SetDuration(0.5)
    alphaOut:SetStartDelay(3)
    f.fadeOut:SetScript("OnFinished", function()
        f:Hide()
    end)
    
    PhaseAlertFrame = f
    return f
end

function SBS.UI:ShowYourTurnAlert()
    local f = CreatePhaseAlertFrame()
    
    -- Зелёная тема
    f:SetBackdropColor(0.1, 0.2, 0.1, 0.95)
    f:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
    
    f.phaseText:SetText("|cFF66CCFFХОД ИГРОКОВ|r")
    f.text:SetText("|cFF00FF00ВАШ ХОД!|r")
    f.hint:SetText("|cFFAAAAAA(выполните действие или пропустите ход)|r")
    
    f:Show()
    f:SetAlpha(1)
    f.fadeIn:Play()
    f.fadeOut:Play()
    
    -- Звук
    PlaySound(8960, "SFX") -- READY_CHECK
end

function SBS.UI:ShowPlayersPhaseAlert()
    local f = CreatePhaseAlertFrame()
    
    -- Синяя тема
    f:SetBackdropColor(0.1, 0.15, 0.25, 0.95)
    f:SetBackdropBorderColor(0.3, 0.5, 0.8, 1)
    
    f.phaseText:SetText("")
    f.text:SetText("|cFF66CCFFХОД ИГРОКОВ|r")
    f.hint:SetText("")
    
    f:Show()
    f:SetAlpha(1)
    f.fadeIn:Play()
    f.fadeOut:Play()
end

function SBS.UI:ShowNPCPhaseAlert()
    local f = CreatePhaseAlertFrame()
    
    -- Фиолетовая тема
    f:SetBackdropColor(0.2, 0.1, 0.2, 0.95)
    f:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    
    f.phaseText:SetText("")
    f.text:SetText("|cFFA06AF1ХОД ПРОТИВНИКА|r")
    f.hint:SetText("")
    
    -- Звук
    PlaySound(37666, "SFX") -- UI_RAID_BOSS_WHISPER_WARNING
    
    f:Show()
    f:SetAlpha(1)
    f.fadeIn:Play()
    f.fadeOut:Play()
end

function SBS.UI:ShowCombatEndAlert()
    local f = CreatePhaseAlertFrame()
    
    -- Серая тема
    f:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    f.phaseText:SetText("")
    f.text:SetText("|cFFFFFFFFБОЙ ОКОНЧЕН|r")
    f.hint:SetText("")
    
    -- Звук
    PlaySound(8959, "SFX") -- PVP_THROUGH_QUEUE
    
    f:Show()
    f:SetAlpha(1)
    f.fadeIn:Play()
    f.fadeOut:Play()
end

function SBS.UI:ShowFreeActionAlert()
    local f = CreatePhaseAlertFrame()
    
    -- Золотая тема для внеочередного хода
    f:SetBackdropColor(0.2, 0.15, 0.05, 0.95)
    f:SetBackdropBorderColor(0.9, 0.7, 0.2, 1)
    
    f.phaseText:SetText("|cFFFFD700ВНЕОЧЕРЕДНОЙ ХОД|r")
    f.text:SetText("|cFFFFFFFFВам дан внеочередной ход!|r")
    f.hint:SetText("|cFFAAAAAA(выполните действие)|r")
    
    f:Show()
    f:SetAlpha(1)
    f.fadeIn:Play()
    f.fadeOut:Play()
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ АТАКИ В ОКНЕ ОЧЕРЕДИ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ShowTurnQueueAttackMenu(button)
    -- Используем урезанное меню атаки (без лечения и эффектов)
    SBS.Dialogs:ShowAttackOnlyMenu(button)
end

-- Меню для AoE ударов (компактное для TurnQueue)
function SBS.UI:ShowAoEHitMenu(button)
    -- Используем общее AoE меню
    SBS.Dialogs:ShowAoEActionMenu(button)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ЛЕЧЕНИЯ В ОКНЕ ОЧЕРЕДИ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ShowTurnQueueHealMenu(button)
    -- Используем общее меню лечения из Dialogs
    SBS.Dialogs:ShowHealMenu(button)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ЭФФЕКТОВ В ОКНЕ ОЧЕРЕДИ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ShowTurnQueueEffectMenu(button)
    SBS.Dialogs:ShowEffectsMenu(button)
end

-- ═══════════════════════════════════════════════════════════
-- AoE ПАНЕЛЬ
-- ═══════════════════════════════════════════════════════════

local aoePanel = nil

function SBS.UI:ShowAoEPanel()
    if aoePanel then
        aoePanel:Hide()
    end
    
    local stat = SBS.Combat:GetAoEStat()
    local hitsLeft = SBS.Combat:GetAoEHitsLeft()
    local statColor = SBS.Config.StatColors[stat] or "FFFFFF"
    local statName = SBS.Config.StatNames[stat] or stat
    
    aoePanel = CreateFrame("Frame", "SBS_AoEPanel", UIParent, "BackdropTemplate")
    aoePanel:SetSize(200, 100)
    aoePanel:SetPoint("TOP", 0, -150)
    aoePanel:SetFrameStrata("FULLSCREEN_DIALOG")
    aoePanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2
    })
    aoePanel:SetBackdropColor(0.1, 0.05, 0.05, 0.95)
    aoePanel:SetBackdropBorderColor(0.8, 0.4, 0.1, 1)
    
    -- Заголовок
    local title = aoePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFFFF9900AoE АТАКА|r")
    
    -- Стата
    local statText = aoePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statText:SetPoint("TOP", 0, -30)
    statText:SetText(SBS.Utils:Color(statColor, statName))
    
    -- Счётчик ударов
    aoePanel.counterText = aoePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    aoePanel.counterText:SetPoint("CENTER", 0, 5)
    aoePanel.counterText:SetText("Осталось ударов: |cFFFFD700" .. hitsLeft .. "|r")
    
    -- Кнопка удара
    local hitBtn = CreateFrame("Button", nil, aoePanel, "BackdropTemplate")
    hitBtn:SetSize(85, 26)
    hitBtn:SetPoint("BOTTOMLEFT", 10, 10)
    hitBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    hitBtn:SetBackdropColor(0.4, 0.15, 0.15, 1)
    hitBtn:SetBackdropBorderColor(0.6, 0.25, 0.25, 1)
    
    local hitText = hitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hitText:SetPoint("CENTER")
    hitText:SetText("|cFFFFFFFFУдарить|r")
    
    hitBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.2, 0.2, 1) end)
    hitBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.15, 0.15, 1) end)
    hitBtn:SetScript("OnClick", function() SBS.Combat:AoEHit() end)
    
    -- Кнопка отмены
    local cancelBtn = CreateFrame("Button", nil, aoePanel, "BackdropTemplate")
    cancelBtn:SetSize(85, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    cancelBtn:SetBackdrop(SBS.Utils.Backdrops.Standard)
    cancelBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("|cFFAAAAAAОтмена|r")
    
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 1) end)
    cancelBtn:SetScript("OnClick", function() SBS.Combat:CancelAoE() end)
    
    aoePanel:Show()
end

function SBS.UI:HideAoEPanel()
    if aoePanel then
        aoePanel:Hide()
        aoePanel = nil
    end
end

function SBS.UI:UpdateAoEPanel()
    if not aoePanel or not aoePanel:IsShown() then return end

    local hitsLeft = SBS.Combat:GetAoEHitsLeft()
    if aoePanel.counterText then
        aoePanel.counterText:SetText("Осталось ударов: |cFFFFD700" .. hitsLeft .. "|r")
    end
end

-- Обновляем очередь при получении данных другого игрока (HP/Energy изменились)
C_Timer.After(0.5, function()
    if SBS.Events then
        SBS.Events:Register("PLAYER_DATA_RECEIVED", function(_)
            if TurnQueueFrame and TurnQueueFrame:IsShown() then
                SBS.UI:UpdateTurnQueue()
            end
        end, SBS.UI)
    end
end)
