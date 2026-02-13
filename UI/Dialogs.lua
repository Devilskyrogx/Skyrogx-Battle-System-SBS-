-- SBS/UI/Dialogs.lua
-- Диалоговые окна и выпадающие меню

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local type = type
local wipe = wipe
local string_format = string.format
local string_sub = string.sub
local math_random = math.random
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local GameTooltip = GameTooltip
local PlaySound = PlaySound
local C_Timer = C_Timer

-- Общий backdrop шаблон
local BACKDROP = SBS.Utils and SBS.Utils.Backdrops and SBS.Utils.Backdrops.Standard or {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = nil,  -- Убираем рамку
    edgeSize = 0,
}

SBS.Dialogs = {}

-- ═══════════════════════════════════════════════════════════
-- КАСТОМНОЕ ВЫПАДАЮЩЕЕ МЕНЮ С ПЕРЕИСПОЛЬЗОВАНИЕМ ФРЕЙМОВ
-- ═══════════════════════════════════════════════════════════

local activeMenu = nil

-- Состояние свёрнутых категорий (сохраняется между показами)
local CollapsedCategories = {}

-- Пул виджетов для переиспользования
local WidgetPool = {
    buttons = {},   -- Обычные кнопки
    titles = {},    -- Заголовки
}

-- Получить или создать кнопку из пула
local function AcquireButton(parent)
    local btn = table_remove(WidgetPool.buttons)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("LEFT", 8, 0)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
    end
    -- Устанавливаем backdrop без рамки каждый раз
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        edgeSize = 0,
    })
    btn:SetParent(parent)
    btn:Show()
    btn:EnableMouse(true)  -- Убеждаемся что мышь включена при каждом использовании
    return btn
end

-- Получить или создать заголовок из пула
local function AcquireTitle(parent)
    local title = table_remove(WidgetPool.titles)
    if not title then
        title = CreateFrame("Button", nil, parent)
        title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title.text:SetPoint("LEFT", 14, 0)
        title.text:SetTextColor(0.5, 0.5, 0.5)
        title.arrow = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title.arrow:SetPoint("LEFT", 3, 0)
        title.arrow:SetTextColor(0.6, 0.6, 0.6)
        title.isTitle = true
        title:EnableMouse(true)
        title:RegisterForClicks("LeftButtonUp")
    end
    title:SetParent(parent)
    title:Show()
    title:EnableMouse(true)  -- Убеждаемся что мышь включена при каждом использовании
    return title
end

-- Вернуть виджет в пул
local function ReleaseWidget(widget)
    widget:Hide()
    widget:ClearAllPoints()
    widget:SetParent(nil)

    -- Сбрасываем скрипты
    widget:SetScript("OnEnter", nil)
    widget:SetScript("OnLeave", nil)
    widget:SetScript("OnClick", nil)

    if widget.isTitle then
        table_insert(WidgetPool.titles, widget)
    else
        table_insert(WidgetPool.buttons, widget)
    end
end

local function CreateCustomMenu(name, width)
    local menu = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    menu:SetSize(width or 180, 20)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    menu:EnableMouse(true)
    menu:Hide()
    menu.widgets = {}
    menu.menuWidth = width or 180

    menu:SetScript("OnShow", function(self)
        if activeMenu and activeMenu ~= self then
            activeMenu:Hide()
        end
        activeMenu = self
    end)

    menu:SetScript("OnHide", function(self)
        GameTooltip:Hide()
        if activeMenu == self then
            activeMenu = nil
        end
        -- Возвращаем виджеты в пул
        for _, w in ipairs(self.widgets) do
            ReleaseWidget(w)
        end
        wipe(self.widgets)
    end)

    return menu
end

local function SetupButton(btn, menu, text, onClick, color, tooltip, tooltipDesc)
    btn:SetSize(menu.menuWidth - 10, 22)
    btn:SetBackdropColor(0, 0, 0, 0)
    btn.text:SetText(text)

    -- Цвет текста
    if color then
        if type(color) == "string" then
            -- Hex строка
            local r = tonumber(color:sub(1,2), 16) / 255
            local g = tonumber(color:sub(3,4), 16) / 255
            local b = tonumber(color:sub(5,6), 16) / 255
            btn.text:SetTextColor(r, g, b)
        elseif type(color) == "table" then
            btn.text:SetTextColor(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1)
        end
    else
        btn.text:SetTextColor(1, 1, 1)
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(tooltip, 1, 0.82, 0)
            if tooltipDesc then
                GameTooltip:AddLine(tooltipDesc, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        -- Закрываем меню после клика (это работает для sticky меню тоже)
        menu:Hide()
        if onClick then onClick() end
    end)
end

local function SetupTitle(title, menu, text, categoryId, isCollapsed, onToggle)
    title:SetSize(menu.menuWidth - 10, 18)
    title.text:SetText(text)
    title.arrow:SetText(isCollapsed and ">" or "v")

    title:SetScript("OnEnter", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7)
        self.arrow:SetTextColor(0.8, 0.8, 0.8)
    end)
    title:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.5, 0.5, 0.5)
        self.arrow:SetTextColor(0.6, 0.6, 0.6)
    end)
    title:SetScript("OnClick", function(self)
        if onToggle then onToggle(categoryId) end
    end)
end

-- Показать меню с поддержкой сворачиваемых категорий
-- options: { position = "left" | "bottom" | "top", collapsible = true/false, sticky = true/false }
local function ShowMenu(menu, anchor, items, options)
    options = options or {}

    -- Сохраняем sticky режим для меню
    menu.isSticky = options.sticky or false
    menu.anchorButton = anchor

    -- Возвращаем старые виджеты в пул
    for _, w in ipairs(menu.widgets) do
        ReleaseWidget(w)
    end
    wipe(menu.widgets)

    -- Функция перестроения меню
    local function RebuildMenu()
        -- Очищаем
        for _, w in ipairs(menu.widgets) do
            ReleaseWidget(w)
        end
        wipe(menu.widgets)

        local y = -8
        local currentCategory = nil
        local skipUntilNextCategory = false

        for _, item in ipairs(items) do
            if item.isTitle then
                currentCategory = item.categoryId or item.text

                local widget = AcquireTitle(menu)
                if options.collapsible then
                    -- По умолчанию категории развёрнуты (свёрнуты только если явно true)
                    local isCollapsed = (CollapsedCategories[currentCategory] == true)
                    skipUntilNextCategory = isCollapsed

                    SetupTitle(widget, menu, item.text, currentCategory, isCollapsed, function(catId)
                        CollapsedCategories[catId] = not CollapsedCategories[catId]
                        RebuildMenu()
                    end)
                else
                    -- Категории не сворачиваются - показываем все кнопки
                    skipUntilNextCategory = false
                    widget:SetSize(menu.menuWidth - 10, 18)
                    widget.text:SetText(item.text)
                    widget.arrow:SetText("")
                end
                y = y - 18
                widget:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, y + 18)
                table.insert(menu.widgets, widget)
            else
                if not skipUntilNextCategory then
                    local widget = AcquireButton(menu)
                    SetupButton(widget, menu, item.text, item.func, item.color, item.tooltip, item.tooltipDesc)
                    y = y - 24
                    widget:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, y + 24)
                    table.insert(menu.widgets, widget)
                end
            end
        end

        -- Установить размер
        menu:SetHeight(math.abs(y) + 8)
    end

    RebuildMenu()

    -- Позиционировать
    menu:ClearAllPoints()
    if anchor then
        if options.position == "left" then
            -- Слева от anchor (для главного меню)
            menu:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
        elseif options.position == "top" then
            -- Сверху от anchor (раскрытие вверх)
            menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        else
            -- Снизу от anchor (по умолчанию)
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        end
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x/scale, y/scale)
    end

    menu:Show()
end

-- Закрытие меню при клике вне
local menuCloseFrame = CreateFrame("Frame", "SBS_MenuCloseFrame", UIParent)
menuCloseFrame:SetFrameStrata("FULLSCREEN")
menuCloseFrame:SetAllPoints()
menuCloseFrame:EnableMouse(false)
menuCloseFrame:SetScript("OnMouseDown", function()
    if activeMenu then
        activeMenu:Hide()
    end
    menuCloseFrame:EnableMouse(false)
end)

local origShowMenu = ShowMenu
ShowMenu = function(menu, anchor, items, options)
    origShowMenu(menu, anchor, items, options)

    -- Если sticky режим, не включаем автозакрытие при клике вне
    if not menu.isSticky then
        -- Сбрасываем предыдущий OnUpdate чтобы он не закрыл новое меню
        menuCloseFrame:SetScript("OnUpdate", nil)
        menuCloseFrame:EnableMouse(true)
        C_Timer.After(0.15, function()
            if not activeMenu then return end
            menuCloseFrame:SetScript("OnUpdate", function()
                if activeMenu and not activeMenu:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    activeMenu:Hide()
                    menuCloseFrame:EnableMouse(false)
                    menuCloseFrame:SetScript("OnUpdate", nil)
                end
            end)
        end)
    end
end

-- Создаём меню (только контейнеры, виджеты берутся из пула)
local AttackMenu = CreateCustomMenu("SBS_CustomAttackMenu", 180)
local CheckMenu = CreateCustomMenu("SBS_CustomCheckMenu", 180)
local SpecMenu = CreateCustomMenu("SBS_CustomSpecMenu", 200)
local MasterSpecMenu = CreateCustomMenu("SBS_MasterSpecMenu", 200)
local HealMenu = CreateCustomMenu("SBS_CustomHealMenu", 160)

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ АТАКИ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowAttackMenu(button)
    -- Если AoE активно, показываем специальное меню
    if SBS.Combat:IsAoEActive() then
        self:ShowAoEActionMenu(button)
        return
    end
    if SBS.Combat:IsAoEHealActive() then
        SBS.Utils:Error("Сначала завершите AoE исцеление!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    local hasTarget = guid ~= nil
    
    local isPlayer = false
    local hasNPCData = false
    local npcAlive = false
    
    if hasTarget then
        isPlayer = SBS.Utils:IsTargetPlayer()
        if not isPlayer then
            local data = SBS.Units:Get(guid)
            hasNPCData = data ~= nil
            npcAlive = hasNPCData and data.hp > 0
        end
    end
    
    local items = {}
    local energy = SBS.Stats:GetEnergy()
    local maxEnergy = SBS.Stats:GetMaxEnergy()
    
    -- Обычные атаки (только если есть живой NPC)
    if hasTarget and not isPlayer and hasNPCData and npcAlive then
        table.insert(items, { text = "— Атака —", isTitle = true, categoryId = "attack" })
        for _, stat in ipairs(SBS.Config.AttackStats) do
            local cfg = SBS.Config.StatColors[stat]
            local statName = SBS.Config.StatNames[stat] or stat
            local desc = ""
            if stat == "Strength" then desc = "Бросок d20 + Сила. Мощная атака ближнего боя."
            elseif stat == "Dexterity" then desc = "Бросок d20 + Ловкость. Точный удар или выстрел."
            elseif stat == "Intelligence" then desc = "Бросок d20 + Интеллект. Магическая атака."
            end
            table.insert(items, {
                text = statName,
                color = cfg,
                tooltip = "Атака: " .. statName,
                tooltipDesc = desc,
                func = function() SBS.Combat:Attack(stat) end
            })
        end
    end

    -- AoE атаки (требуют энергию)
    local aoeCost = SBS.Config.ENERGY_COST_AOE
    local aoeAvailable = energy >= aoeCost
    local aoeColorSuffix = aoeAvailable and "" or " |cFF666666(нет энергии)|r"

    table.insert(items, { text = "— AoE (" .. aoeCost .. " эн.) —", isTitle = true, categoryId = "aoe" })
    for _, stat in ipairs(SBS.Config.AttackStats) do
        local cfg = SBS.Config.StatColors[stat]
        local statName = SBS.Config.StatNames[stat] or stat
        table.insert(items, {
            text = "AoE " .. statName .. aoeColorSuffix,
            color = aoeAvailable and cfg or "666666",
            tooltip = "AoE " .. statName,
            tooltipDesc = "Порог " .. SBS.Config.AOE_THRESHOLD .. ". Макс. " .. SBS.Config.AOE_MAX_TARGETS .. " целей.\nСтоимость: " .. aoeCost .. " энергии",
            func = function()
                if not aoeAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Combat:StartAoEAttack(stat)
            end
        })
    end

    -- Особое действие
    local specialCost = SBS.Config.ENERGY_COST_SPECIAL
    local specialAvailable = energy >= specialCost
    local specialColor = specialAvailable and "9966FF" or "666666"

    table.insert(items, { text = "— Особое (" .. specialCost .. " эн.) —", isTitle = true, categoryId = "special" })
    table.insert(items, {
        text = "|cFF" .. specialColor .. "Особое действие|r",
        tooltip = "Особое действие",
        tooltipDesc = "Бросок d20 + лучшая атакующая стата.\nПорог: " .. SBS.Config.SPECIAL_ACTION_THRESHOLD .. "\nПри успехе — опишите действие для мастера.",
        func = function()
            if not specialAvailable then
                SBS.Utils:Error("Недостаточно энергии!")
                return
            end
            SBS.Combat:SpecialAction()
        end
    })

    -- Исцеление
    table.insert(items, { text = "— Исцеление —", isTitle = true, categoryId = "heal" })
    table.insert(items, {
        text = SBS.Config.StatNames["Spirit"] or "Дух",
        color = SBS.Config.StatColors["Spirit"],
        tooltip = "Исцеление",
        tooltipDesc = "Бросок d20 + Дух. Восстанавливает HP союзнику.",
        func = function() SBS.Combat:Heal() end
    })

    -- Щит для хилов и универсалов
    local role = SBS.Stats:GetRole()
    if role == "healer" or role == "universal" then
        table.insert(items, { text = "— Щит —", isTitle = true, categoryId = "shield" })
        table.insert(items, {
            text = "Наложить щит",
            color = {r = 0.4, g = 0.8, b = 1},
            tooltip = "Щит",
            tooltipDesc = "Создаёт временный щит, поглощающий урон.",
            func = function() SBS.Combat:Shield() end
        })
    end

    -- Снятие раны (только для целителя)
    if role == "healer" then
        if hasTarget and isPlayer then
            table.insert(items, { text = "— Раны —", isTitle = true, categoryId = "wounds" })
            table.insert(items, {
                text = "Снять рану",
                color = {r = 1, g = 0.5, b = 0.5},
                tooltip = "Снять рану (Лекарь)",
                tooltipDesc = "Бросок d20 + Дух против порога 16. При успехе снимает одно ранение с цели.",
                func = function() SBS.Combat:RemoveWound() end
            })
        end
    end

    -- ══════════ ЭФФЕКТЫ ══════════
    local effectsCost = 1
    local effectsAvailable = energy >= effectsCost
    local effectsColorSuffix = effectsAvailable and "" or " |cFF666666(нет энергии)|r"

    table.insert(items, { text = "— Эффекты (" .. effectsCost .. " эн.) —", isTitle = true, categoryId = "effects" })

    -- DoT на NPC (если цель - живой NPC)
    if hasTarget and not isPlayer and hasNPCData and npcAlive then
        table.insert(items, {
            text = "Наложить DoT" .. effectsColorSuffix,
            color = effectsAvailable and {r = 0.8, g = 0.3, b = 0.1} or {r = 0.4, g = 0.4, b = 0.4},
            tooltip = "Периодический урон",
            tooltipDesc = "Наложить эффект урона на NPC.\nУрон каждый раунд в течение нескольких раундов.",
            func = function()
                if not effectsAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Dialogs:ShowEffectMenu(button, "npc", guid)
            end
        })
    end

    -- Бафф на игрока (если цель - игрок или себя)
    local buffTargetName = nil
    if hasTarget and isPlayer then
        buffTargetName = name
    end

    table.insert(items, {
        text = "Наложить бафф" .. effectsColorSuffix,
        color = effectsAvailable and {r = 0.2, g = 0.8, b = 0.3} or {r = 0.4, g = 0.4, b = 0.4},
        tooltip = "Усиление союзника",
        tooltipDesc = buffTargetName and ("Наложить бафф на " .. buffTargetName) or "Наложить бафф на себя (без таргета) или союзника",
        func = function()
            if not effectsAvailable then
                SBS.Utils:Error("Недостаточно энергии!")
                return
            end
            local target = buffTargetName or UnitName("player")
            SBS.Dialogs:ShowEffectMenu(button, "player", target)
        end
    })

    -- Дебафф на NPC (Ослабление - доступно всем)
    if hasTarget and not isPlayer and hasNPCData and npcAlive then
        table.insert(items, {
            text = "Ослабить NPC" .. effectsColorSuffix,
            color = effectsAvailable and {r = 0.6, g = 0.4, b = 0.4} or {r = 0.4, g = 0.4, b = 0.4},
            tooltip = "Ослабление",
            tooltipDesc = "Снижает защитный стат NPC на 1-3 (случ.) на 3 раунда.\nВыберите: Стойкость, Сноровка или Воля.\nСтоимость: 1 энергия",
            func = function()
                if not effectsAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Dialogs:ShowPlayerWeakenNPCDialog(guid, name)
            end
        })
    end

    -- Если меню уже открыто от этой кнопки, закрываем его
    if AttackMenu:IsShown() and AttackMenu.anchorButton == button then
        AttackMenu:Hide()
        return
    end

    -- Используем кнопку как якорь для sticky меню
    ShowMenu(AttackMenu, button, items, { position = "top", sticky = true, collapsible = true })
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ АТАКИ (урезанное для панели очереди)
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowAttackOnlyMenu(button)
    -- Если AoE активно, показываем специальное меню
    if SBS.Combat:IsAoEActive() then
        self:ShowAoEActionMenu(button)
        return
    end
    if SBS.Combat:IsAoEHealActive() then
        SBS.Utils:Error("Сначала завершите AoE исцеление!")
        return
    end

    local guid, name = SBS.Utils:GetTargetGUID()
    local hasTarget = guid ~= nil

    local isPlayer = false
    local hasNPCData = false
    local npcAlive = false

    if hasTarget then
        isPlayer = SBS.Utils:IsTargetPlayer()
        if not isPlayer then
            local data = SBS.Units:Get(guid)
            hasNPCData = data ~= nil
            npcAlive = hasNPCData and data.hp > 0
        end
    end

    local items = {}
    local energy = SBS.Stats:GetEnergy()

    -- Проверка наличия корректной цели
    if not hasTarget then
        SBS.Utils:Error("Нет цели для атаки")
        return
    end

    if isPlayer then
        SBS.Utils:Error("Нельзя атаковать игрока")
        return
    end

    if not hasNPCData then
        SBS.Utils:Error("Цель не имеет HP")
        return
    end

    if not npcAlive then
        SBS.Utils:Error("Цель мертва")
        return
    end

    -- Обычные атаки
    table.insert(items, { text = "— Атака —", isTitle = true })
    for _, stat in ipairs(SBS.Config.AttackStats) do
        local cfg = SBS.Config.StatColors[stat]
        local statName = SBS.Config.StatNames[stat] or stat
        local desc = ""
        if stat == "Strength" then desc = "Бросок d20 + Сила. Мощная атака ближнего боя."
        elseif stat == "Dexterity" then desc = "Бросок d20 + Ловкость. Точный удар или выстрел."
        elseif stat == "Intelligence" then desc = "Бросок d20 + Интеллект. Магическая атака."
        end
        table.insert(items, {
            text = statName,
            color = cfg,
            tooltip = "Атака: " .. statName,
            tooltipDesc = desc,
            func = function() SBS.Combat:Attack(stat) end
        })
    end

    -- AoE атаки (требуют энергию)
    local aoeCost = SBS.Config.ENERGY_COST_AOE
    local aoeAvailable = energy >= aoeCost
    local aoeColorSuffix = aoeAvailable and "" or " |cFF666666(нет энергии)|r"

    table.insert(items, { text = "— AoE атака (" .. aoeCost .. " энергии) —", isTitle = true })
    for _, stat in ipairs(SBS.Config.AttackStats) do
        local cfg = SBS.Config.StatColors[stat]
        local statName = SBS.Config.StatNames[stat] or stat
        table.insert(items, {
            text = "AoE " .. statName .. aoeColorSuffix,
            color = aoeAvailable and cfg or "666666",
            tooltip = "AoE " .. statName,
            tooltipDesc = "Порог " .. SBS.Config.AOE_THRESHOLD .. ". Макс. " .. SBS.Config.AOE_MAX_TARGETS .. " целей.\nСтоимость: " .. aoeCost .. " энергии",
            func = function()
                if not aoeAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Combat:StartAoEAttack(stat)
            end
        })
    end

    -- Особое действие
    local specialCost = SBS.Config.ENERGY_COST_SPECIAL
    local specialAvailable = energy >= specialCost
    local specialColor = specialAvailable and "9966FF" or "666666"

    table.insert(items, { text = "— Особое действие (" .. specialCost .. " энергии) —", isTitle = true })
    table.insert(items, {
        text = "|cFF" .. specialColor .. "Особое действие|r",
        tooltip = "Особое действие",
        tooltipDesc = "Бросок d20 + лучшая атакующая стата.\nПорог: " .. SBS.Config.SPECIAL_ACTION_THRESHOLD .. "\nПри успехе — опишите действие для мастера.",
        func = function()
            if not specialAvailable then
                SBS.Utils:Error("Недостаточно энергии!")
                return
            end
            SBS.Combat:SpecialAction()
        end
    })

    ShowMenu(AttackMenu, button, items)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ЭФФЕКТОВ (для кнопки "Эффект" в очереди ходов)
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowEffectsMenu(button)
    local guid, name = SBS.Utils:GetTargetGUID()
    local hasTarget = guid ~= nil
    local isPlayer = hasTarget and SBS.Utils:IsTargetPlayer()
    local role = SBS.Stats:GetRole() or "universal"
    local energy = SBS.Stats:GetEnergy()

    local hasNPCData = false
    local npcAlive = false
    if hasTarget and not isPlayer then
        local data = SBS.Units:Get(guid)
        hasNPCData = data ~= nil
        npcAlive = hasNPCData and data.hp > 0
    end

    local items = {}
    local effectsCost = 1
    local effectsAvailable = energy >= effectsCost
    local effectsColorSuffix = effectsAvailable and "" or " |cFF666666(нет энергии)|r"

    table.insert(items, { text = "— Эффекты (" .. effectsCost .. " энергии) —", isTitle = true })

    -- DoT на NPC (если цель - живой NPC)
    if hasTarget and not isPlayer and hasNPCData and npcAlive then
        table.insert(items, {
            text = "Наложить DoT" .. effectsColorSuffix,
            color = effectsAvailable and {r = 0.8, g = 0.3, b = 0.1} or {r = 0.4, g = 0.4, b = 0.4},
            tooltip = "Периодический урон",
            tooltipDesc = "Наложить эффект урона на NPC.\nУрон каждый раунд в течение нескольких раундов.",
            func = function()
                if not effectsAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Dialogs:ShowEffectMenu(button, "npc", guid)
            end
        })
    end

    -- Бафф на игрока (если цель - игрок или себя)
    local buffTargetName = nil
    if hasTarget and isPlayer then
        buffTargetName = name
    end

    table.insert(items, {
        text = "Наложить бафф" .. effectsColorSuffix,
        color = effectsAvailable and {r = 0.2, g = 0.8, b = 0.3} or {r = 0.4, g = 0.4, b = 0.4},
        tooltip = "Усиление союзника",
        tooltipDesc = buffTargetName and ("Наложить бафф на " .. buffTargetName) or "Наложить бафф на себя (без таргета) или союзника",
        func = function()
            if not effectsAvailable then
                SBS.Utils:Error("Недостаточно энергии!")
                return
            end
            local target = buffTargetName or UnitName("player")
            SBS.Dialogs:ShowEffectMenu(button, "player", target)
        end
    })

    -- Дебафф на NPC (Ослабление - доступно всем)
    if hasTarget and not isPlayer and hasNPCData and npcAlive then
        table.insert(items, {
            text = "Ослабить NPC" .. effectsColorSuffix,
            color = effectsAvailable and {r = 0.6, g = 0.4, b = 0.4} or {r = 0.4, g = 0.4, b = 0.4},
            tooltip = "Ослабление",
            tooltipDesc = "Снижает защитный стат NPC на 1-3 (случ.) на 3 раунда.\nВыберите: Стойкость, Сноровка или Воля.\nСтоимость: 1 энергия",
            func = function()
                if not effectsAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Dialogs:ShowPlayerWeakenNPCDialog(guid, name)
            end
        })
    end

    -- Если меню пустое (кроме заголовка)
    if #items == 1 then
        table.insert(items, {
            text = "Нет доступных действий",
            color = {r = 0.5, g = 0.5, b = 0.5},
            func = function() end
        })
    end

    ShowMenu(AttackMenu, button, items)
end

-- Меню для активного AoE режима
function SBS.Dialogs:ShowAoEActionMenu(button)
    local stat = SBS.Combat:GetAoEStat()
    local hitsLeft = SBS.Combat:GetAoEHitsLeft()
    local statColor = SBS.Config.StatColors[stat] or {r=1,g=1,b=1}
    local statName = SBS.Config.StatNames[stat] or stat
    
    local items = {
        { text = "— AoE " .. statName .. " —", isTitle = true },
        { text = "Осталось: " .. hitsLeft, isTitle = true },
        {
            text = "Ударить цель",
            color = {r = 1, g = 0.4, b = 0.4},
            tooltip = "AoE удар",
            tooltipDesc = "Нанести урон выбранной цели.\nЦель нельзя атаковать повторно.",
            func = function() SBS.Combat:AoEHit() end
        },
        {
            text = "Завершить AoE",
            color = {r = 0.6, g = 0.6, b = 0.6},
            tooltip = "Отменить",
            tooltipDesc = "Завершить AoE атаку досрочно.",
            func = function() SBS.Combat:CancelAoE() end
        },
    }
    
    ShowMenu(AttackMenu, button, items)
end

function SBS.Dialogs:ShowAoEHealActionMenu(button)
    local healsLeft = SBS.Combat:GetAoEHealsLeft()
    
    local items = {
        { text = "— AoE Исцеление —", isTitle = true },
        { text = "Осталось: " .. healsLeft, isTitle = true },
        {
            text = "Исцелить цель",
            color = {r = 0.4, g = 1, b = 0.4},
            tooltip = "AoE исцеление",
            tooltipDesc = "Исцелить выбранного союзника.\nОдного союзника нельзя исцелить дважды.",
            func = function() SBS.Combat:AoEHealTarget() end
        },
        {
            text = "Завершить",
            color = {r = 0.6, g = 0.6, b = 0.6},
            tooltip = "Отменить",
            tooltipDesc = "Завершить AoE исцеление досрочно.",
            func = function() SBS.Combat:CancelAoEHeal() end
        },
    }
    
    ShowMenu(AttackMenu, button, items)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ЭФФЕКТОВ (для игроков)
-- ═══════════════════════════════════════════════════════════

local EffectMenu = CreateCustomMenu("SBS_CustomEffectMenu", 220)

function SBS.Dialogs:ShowEffectMenu(button, targetType, targetId)
    local role = SBS.Stats:GetRole() or "Universal"
    local casterName = UnitName("player")
    
    -- Определяем какие эффекты показывать
    local effectsToShow = {}
    
    if targetType == "npc" then
        -- Только DoT эффекты для NPC (исключаем мастерские и дебаффы типа "ослабление")
        local allEffects = SBS.Effects:GetAvailable(role, "npc")
        for _, effectInfo in ipairs(allEffects) do
            -- Показываем только DoT и не мастерские
            if effectInfo.def.type == "dot" and effectInfo.def.category ~= "master" then
                table.insert(effectsToShow, effectInfo)
            end
        end
    else
        -- Баффы для игроков (исключаем мастерские)
        local allEffects = SBS.Effects:GetAvailable(role, "player")
        for _, effectInfo in ipairs(allEffects) do
            if effectInfo.def.type == "buff" and effectInfo.def.category ~= "master" then
                table.insert(effectsToShow, effectInfo)
            end
        end
    end
    
    local items = {}
    local targetName = targetType == "npc" 
        and (SBS.Units:Get(targetId) and SBS.Units:Get(targetId).name or "NPC") 
        or targetId
    
    table.insert(items, { text = "— Эффекты на " .. targetName .. " —", isTitle = true })
    
    if #effectsToShow == 0 then
        table.insert(items, { 
            text = "|cFF666666Нет доступных эффектов|r", 
            isTitle = true 
        })
    else
        for _, effectInfo in ipairs(effectsToShow) do
            local def = effectInfo.def
            local onCooldown = effectInfo.onCooldown
            local cdRemaining = effectInfo.cooldownRemaining
            
            -- Проверяем, висит ли уже эффект на цели
            local alreadyActive = SBS.Effects:HasEffect(targetType, targetId, def.id)
            
            local colorHex = SBS.Effects:GetColorHex(def.color)
            local text = def.name
            local canUse = true
            local reason = ""
            
            if alreadyActive then
                text = text .. " |cFF666666(активен)|r"
                canUse = false
                reason = "Эффект уже активен на цели"
            elseif onCooldown then
                text = text .. " |cFF666666(КД: " .. cdRemaining .. ")|r"
                canUse = false
                reason = "Кулдаун: " .. cdRemaining .. " раунд(ов)"
            end
            
            -- Описание с параметрами
            local valueText = ""
            if def.type == "dot" then
                valueText = def.fixedValue .. " урона/раунд, " .. def.fixedDuration .. " раунд(ов)"
            elseif def.type == "buff" then
                if def.isHoT then
                    valueText = "+" .. def.fixedValue .. " HP/раунд, " .. def.fixedDuration .. " раунд(ов)"
                elseif def.statMod then
                    local modText = def.modType == "increase" and "+" or "-"
                    valueText = modText .. def.fixedValue .. " к " .. def.statMod .. ", " .. def.fixedDuration .. " раунд(ов)"
                end
            end
            
            table.insert(items, {
                text = "|cFF" .. colorHex .. text .. "|r",
                color = canUse and {r = def.color[1], g = def.color[2], b = def.color[3]} or {r = 0.4, g = 0.4, b = 0.4},
                tooltip = def.name,
                tooltipDesc = def.description .. "\n" .. valueText .. "\nСтоимость: " .. (def.energyCost or 1) .. " энергии" .. (reason ~= "" and ("\n|cFFFF6666" .. reason .. "|r") or ""),
                func = function()
                    if not canUse then
                        SBS.Utils:Error(reason)
                        return
                    end
                    SBS.Effects:PlayerApply(targetType, targetId, def.id)
                end
            })
        end
    end
    
    -- Кнопка отмены
    table.insert(items, {
        text = "|cFF888888Отмена|r",
        func = function() end
    })
    
    ShowMenu(EffectMenu, button, items)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ЛЕЧЕНИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowHealMenu(button)
    -- Если AoE исцеление активно, показываем специальное меню
    if SBS.Combat:IsAoEHealActive() then
        self:ShowAoEHealActionMenu(button)
        return
    end
    if SBS.Combat:IsAoEActive() then
        SBS.Utils:Error("Сначала завершите AoE атаку!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    local hasTarget = guid ~= nil
    local isPlayer = hasTarget and SBS.Utils:IsTargetPlayer()
    local role = SBS.Stats:GetRole()
    local isHealer = (role == "healer" or role == "Healer")
    local canShield = (isHealer or role == "universal" or role == "Universal")
    local canRemoveWound = isHealer
    
    local items = {}
    
    -- Исцеление (Дух) — всегда доступно
    table.insert(items, { text = "— Исцеление —", isTitle = true })
    table.insert(items, {
        text = "Исцеление",
        color = "66FF66",
        tooltip = "Исцеление",
        tooltipDesc = "Бросок d20 + Дух. Восстанавливает HP союзнику.",
        func = function() SBS.Combat:Heal() end
    })
    
    -- AoE Исцеление (только целитель, требует энергию)
    if isHealer then
        local aoeCost = SBS.Config.ENERGY_COST_AOE
        local energy = SBS.Stats:GetEnergy()
        local aoeAvailable = energy >= aoeCost
        local aoeColorSuffix = aoeAvailable and "" or " |cFF666666(нет энергии)|r"
        
        table.insert(items, { text = "— AoE Исцеление (" .. aoeCost .. " энергии) —", isTitle = true })
        table.insert(items, {
            text = "AoE Исцеление" .. aoeColorSuffix,
            color = aoeAvailable and "66FF66" or "666666",
            tooltip = "AoE Исцеление",
            tooltipDesc = "Порог " .. SBS.Config.AOE_THRESHOLD .. ". Макс. " .. SBS.Config.AOE_MAX_TARGETS .. " союзников.\nСтоимость: " .. aoeCost .. " энергии",
            func = function()
                if not aoeAvailable then
                    SBS.Utils:Error("Недостаточно энергии!")
                    return
                end
                SBS.Combat:StartAoEHeal()
            end
        })
    end
    
    -- Щит (целитель и универсал)
    if canShield then
        table.insert(items, { text = "— Щит —", isTitle = true })
        table.insert(items, {
            text = "Наложить щит",
            color = "66CCFF",
            tooltip = "Щит",
            tooltipDesc = "Создаёт временный щит, поглощающий урон.",
            func = function() SBS.Combat:Shield() end
        })
    end
    
    -- Снятие раны (только целитель)
    if canRemoveWound then
        if hasTarget and isPlayer then
            table.insert(items, { text = "— Раны —", isTitle = true })
            table.insert(items, {
                text = "Снять рану",
                color = "FF6666",
                tooltip = "Снять рану (Лекарь)",
                tooltipDesc = "Бросок d20 + Дух против порога 16. При успехе снимает одно ранение с цели.",
                func = function() SBS.Combat:RemoveWound() end
            })
        end
    end

    -- Диспел (только целитель, цель-игрок с дебаффами)
    if canRemoveWound then
        if hasTarget and isPlayer then
            local effectsCost = 1
            local energy = SBS.Stats:GetEnergy()
            local effectsAvailable = energy >= effectsCost
            local hasDebuffs = false
            local targetEffects = SBS.Effects:GetAll("player", name)
            for effectId, _ in pairs(targetEffects) do
                local def = SBS.Effects.Definitions[effectId]
                if def and (def.type == "debuff" or (def.type == "dot" and def.category == "master")) then
                    hasDebuffs = true
                    break
                end
            end
            if hasDebuffs then
                table.insert(items, { text = "— Диспел —", isTitle = true })
                table.insert(items, {
                    text = "Снять дебафф" .. (effectsAvailable and "" or " |cFF666666(нет энергии)|r"),
                    color = effectsAvailable and "66B3FF" or "666666",
                    tooltip = "Диспел",
                    tooltipDesc = "Снимает один дебафф с союзника.\nСтоимость: 1 энергия",
                    func = function()
                        if not effectsAvailable then
                            SBS.Utils:Error("Недостаточно энергии!")
                            return
                        end
                        SBS.Effects:Dispel(name, "Healer")
                    end
                })
            end
        end
    end

    ShowMenu(HealMenu, button, items)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ПРОВЕРКИ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowCheckMenu(button)
    local items = {
        { text = "— Атакующие —", isTitle = true },
    }
    
    local attackDescs = {
        Strength = "Физическая сила, ближний бой, поднятие тяжестей.",
        Dexterity = "Ловкость, скорость, уклонение, стрельба.",
        Intelligence = "Интеллект, магия, знания, логика.",
        Spirit = "Сила воли, харизма, исцеление.",
    }
    
    for _, stat in ipairs({"Strength", "Dexterity", "Intelligence", "Spirit"}) do
        local cfg = SBS.Config.StatColors[stat]
        local statName = SBS.Config.StatNames[stat] or stat
        table.insert(items, {
            text = statName,
            color = cfg,
            tooltip = "Проверка: " .. statName,
            tooltipDesc = attackDescs[stat],
            func = function() SBS.Combat:Check(stat) end
        })
    end
    
    table.insert(items, { text = "— Защитные —", isTitle = true })
    
    local defenseDescs = {
        Fortitude = "Сопротивление яду, болезням, физ. эффектам.",
        Reflex = "Уклонение от ловушек, AoE-атак.",
        Will = "Сопротивление ментальным атакам, страху.",
    }
    
    for _, stat in ipairs(SBS.Config.DefenseStats) do
        local cfg = SBS.Config.StatColors[stat]
        local statName = SBS.Config.StatNames[stat] or stat
        table.insert(items, {
            text = statName,
            color = cfg,
            tooltip = "Проверка: " .. statName,
            tooltipDesc = defenseDescs[stat],
            func = function() SBS.Combat:Check(stat) end
        })
    end

    -- Липкое меню, открывается вверх, как у "Действие"
    if CheckMenu:IsShown() and CheckMenu.anchorButton == button then
        CheckMenu:Hide()
        return
    end
    ShowMenu(CheckMenu, button, items, { position = "top", sticky = true, collapsible = true })
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ВЫБОРА РОЛИ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowSpecDialog()
    if not SBS.Stats:CanChooseRole() then
        SBS.Utils:Error("Роль доступна с " .. SBS.Config.ROLE_REQUIRED_LEVEL .. " уровня!")
        return
    end
    
    if SBS.Stats:GetRole() then
        SBS.Utils:Error("Роль уже выбрана! Смена только через ведущего.")
        return
    end
    
    local items = {
        { text = "Выберите роль", isTitle = true },
    }
    
    for key, data in pairs(SBS.Config.Roles) do
        local r = tonumber(data.color:sub(1,2), 16)/255
        local g = tonumber(data.color:sub(3,4), 16)/255
        local b = tonumber(data.color:sub(5,6), 16)/255
        table.insert(items, {
            text = data.name,
            color = {r = r, g = g, b = b},
            tooltip = data.name,
            tooltipDesc = data.description,
            func = function() 
                SBS.Stats:SetRole(key)
                if SBS.UI then SBS.UI:UpdateMainFrame() end
            end
        })
    end
    
    ShowMenu(SpecMenu, _G["SBS_MainFrame_ActionBar_SpecBtn"], items)
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ УСТАНОВКИ HP NPC
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowSetHPDialog()
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    -- Если есть цель, показываем её данные
    if guid then
        if SBS.Utils:IsTargetPlayer() then
            SBS_SetHPDialog_TargetName:SetText("|cFFFF6666" .. name .. " (игрок)|r")
        else
            local data = SBS.Units:Get(guid)
            SBS_SetHPDialog_TargetName:SetText(name)
            -- Если HP не задано, оставляем поле как есть (или пустым при первом открытии)
            if data and SBS_SetHPDialog_Input:GetText() == "" then
                SBS_SetHPDialog_Input:SetText(tostring(data.maxHp))
            end
        end
    else
        SBS_SetHPDialog_TargetName:SetText("|cFF888888Нет цели|r")
    end
    
    SBS_SetHPDialog:Show()
    SBS_SetHPDialog_Input:SetFocus()
end

function SBS.Dialogs:ApplySetHP()
    -- Берём ТЕКУЩУЮ цель, а не сохранённую при открытии
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    -- Только для NPC, не для игроков
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя задать HP игроку! Используйте HP Игрока.")
        return
    end
    
    local hp = tonumber(SBS_SetHPDialog_Input:GetText())
    if not hp or hp <= 0 then
        SBS.Utils:Error("Введите корректное HP!")
        return
    end
    
    if SBS.Units:SetHP(guid, name, hp, hp) then
        SBS.Utils:Info("HP для " .. SBS.Utils:Color("FFFFFF", name) .. ": " .. SBS.Utils:Color("FF0000", hp .. "/" .. hp))
        if SBS.CombatLog then
            SBS.CombatLog:AddMasterLog("Задал HP NPC '" .. name .. "': " .. hp, "master_action")
        end
        
        -- Обновляем имя цели в заголовке, значение НЕ очищаем
        SBS_SetHPDialog_TargetName:SetText(name)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ЗАЩИТЫ NPC
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowDefenseDialog()
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    -- Если есть цель, показываем её данные
    if guid then
        if SBS.Utils:IsTargetPlayer() then
            SBS_DefenseDialog_TargetName:SetText("|cFFFF6666" .. name .. " (игрок)|r")
        else
            local data = SBS.Units:Get(guid) or {}
            SBS_DefenseDialog_TargetName:SetText(name)
            -- Заполняем только если поля пустые (первое открытие)
            if SBS_DefenseDialog_FortInput:GetText() == "" then
                SBS_DefenseDialog_FortInput:SetText(tostring(data.fort or 10))
                SBS_DefenseDialog_ReflexInput:SetText(tostring(data.reflex or 10))
                SBS_DefenseDialog_WillInput:SetText(tostring(data.will or 10))
            end
        end
    else
        SBS_DefenseDialog_TargetName:SetText("|cFF888888Нет цели|r")
        -- Дефолтные значения если поля пустые
        if SBS_DefenseDialog_FortInput:GetText() == "" then
            SBS_DefenseDialog_FortInput:SetText("10")
            SBS_DefenseDialog_ReflexInput:SetText("10")
            SBS_DefenseDialog_WillInput:SetText("10")
        end
    end
    
    SBS_DefenseDialog:Show()
end

function SBS.Dialogs:ApplyDefense()
    -- Берём ТЕКУЩУЮ цель, а не сохранённую при открытии
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    -- Только для NPC, не для игроков
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя задать защиту игроку!")
        return
    end
    
    local fort = tonumber(SBS_DefenseDialog_FortInput:GetText()) or 10
    local reflex = tonumber(SBS_DefenseDialog_ReflexInput:GetText()) or 10
    local will = tonumber(SBS_DefenseDialog_WillInput:GetText()) or 10
    
    SBS.Units:SetDefenses(guid, name, fort, reflex, will)
    SBS.Utils:Info(name .. ": Стойк=" .. fort .. ", Снор=" .. reflex .. ", Воля=" .. will)
    
    -- Обновляем имя цели в заголовке, значения НЕ очищаем
    SBS_DefenseDialog_TargetName:SetText(name)
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ИЗМЕНЕНИЯ HP NPC
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowModifyNPCHPDialog()
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    -- Если есть цель, показываем её данные
    if guid then
        if SBS.Utils:IsTargetPlayer() then
            SBS_ModifyNPCHPDialog_TargetName:SetText("|cFFFF6666" .. name .. " (игрок)|r")
        else
            local data = SBS.Units:Get(guid)
            if data then
                SBS_ModifyNPCHPDialog_TargetName:SetText(name .. " (" .. data.hp .. "/" .. data.maxHp .. ")")
            else
                SBS_ModifyNPCHPDialog_TargetName:SetText(name .. " |cFFFF6666(HP не задан)|r")
            end
        end
    else
        SBS_ModifyNPCHPDialog_TargetName:SetText("|cFF888888Нет цели|r")
    end
    
    SBS_ModifyNPCHPDialog:Show()
    SBS_ModifyNPCHPDialog_Input:SetFocus()
end

function SBS.Dialogs:ApplyModifyNPCHP(direction)
    -- Берём ТЕКУЩУЮ цель, а не сохранённую при открытии
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    -- Только для NPC, не для игроков
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Это игрок! Используйте HP Игрока.")
        return
    end
    
    local amount = tonumber(SBS_ModifyNPCHPDialog_Input:GetText())
    if not amount or amount <= 0 then
        SBS.Utils:Error("Введите корректное значение!")
        return
    end
    
    local data = SBS.Units:Get(guid)
    if not data then 
        SBS.Utils:Error("HP не задан для " .. name .. "!") 
        return 
    end
    
    local val = amount * direction
    local newHP = SBS.Utils:Clamp(data.hp + val, 0, data.maxHp)
    if SBS.Units:ModifyHP(guid, newHP) then
        local txt = val > 0 and SBS.Utils:Color("00FF00", "+" .. amount) or SBS.Utils:Color("FF0000", "-" .. amount)
        SBS.Utils:Info(name .. ": " .. txt .. " HP (" .. newHP .. "/" .. data.maxHp .. ")")
        if SBS.CombatLog then
            SBS.CombatLog:AddMasterLog(string.format("Изменил HP NPC '%s': %+d (HP: %d/%d)", name, val, newHP, data.maxHp), "master_action")
        end
        
        if newHP <= 0 then
            SBS.Utils:Print("FF0000", name .. " — цель мертва!")
        end
        
        -- Обновляем отображение в диалоге, значение НЕ очищаем
        local updatedData = SBS.Units:Get(guid)
        if updatedData then
            SBS_ModifyNPCHPDialog_TargetName:SetText(name .. " (" .. updatedData.hp .. "/" .. updatedData.maxHp .. ")")
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ АТАКИ NPC
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowNPCAttackDialog()
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    
    SBS_NPCAttackDialog_TargetName:SetText(name)
    SBS_NPCAttackDialog_DamageInput:SetText("1")
    SBS_NPCAttackDialog_ThresholdInput:SetText("10")
    SBS_NPCAttackDialog.targetName = name
    SBS_NPCAttackDialog.targetGUID = guid
    SBS_NPCAttackDialog.selectedDefense = "Fortitude"
    SBS_NPCAttackDialog_DefenseDropdown:SetText("Стойкость")
    SBS_NPCAttackDialog:Show()
    SBS_NPCAttackDialog_DamageInput:SetFocus()
    
    -- Регистрируем событие смены таргета
    SBS_NPCAttackDialog:RegisterEvent("PLAYER_TARGET_CHANGED")
    SBS_NPCAttackDialog:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_TARGET_CHANGED" and self:IsShown() then
            local newGuid, newName = SBS.Utils:GetTargetGUID()
            if newName and SBS.Utils:IsTargetPlayer() then
                self.targetName = newName
                self.targetGUID = newGuid
                SBS_NPCAttackDialog_TargetName:SetText(newName)
            end
        end
    end)
    
    -- При закрытии - отписываемся от события
    SBS_NPCAttackDialog:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    end)
end

function SBS.Dialogs:ShowNPCAttackDefenseMenu(button)
    local DefenseMenu = CreateFrame("Frame", "SBS_CustomDefenseMenu", UIParent, "BackdropTemplate")
    DefenseMenu:SetSize(140, 105)
    DefenseMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    DefenseMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    DefenseMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    DefenseMenu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    DefenseMenu:EnableMouse(true)
    
    local defenses = {
        {"Fortitude", "Стойкость", {r=0.64, g=0.19, b=0.79}},
        {"Reflex", "Сноровка", {r=1, g=0.49, b=0.04}},
        {"Will", "Воля", {r=0.53, g=0.53, b=0.93}},
        {"Hybrid", "Гибрид", {r=0.2, g=0.8, b=0.8}}
    }
    
    local y = -6
    for _, def in ipairs(defenses) do
        local btn = CreateFrame("Button", nil, DefenseMenu, "BackdropTemplate")
        btn:SetSize(130, 22)
        btn:SetPoint("TOPLEFT", DefenseMenu, "TOPLEFT", 5, y)
        btn:SetBackdrop(SBS.Utils.Backdrops.NoEdge)
        btn:SetBackdropColor(0, 0, 0, 0)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("LEFT", 8, 0)
        btn.text:SetText(def[2])
        btn.text:SetTextColor(def[3].r, def[3].g, def[3].b)
        
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
        btn:SetScript("OnClick", function(self)
            SBS_NPCAttackDialog.selectedDefense = def[1]
            SBS_NPCAttackDialog_DefenseDropdown:SetText(def[2])
            DefenseMenu:Hide()
        end)
        y = y - 24
    end
    
    DefenseMenu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    DefenseMenu:Show()
    
    DefenseMenu:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
            self:Hide()
        end
    end)
end

function SBS.Dialogs:ApplyNPCAttack()
    local target = SBS_NPCAttackDialog.targetName
    local damage = tonumber(SBS_NPCAttackDialog_DamageInput:GetText())
    local threshold = tonumber(SBS_NPCAttackDialog_ThresholdInput:GetText())
    local defense = SBS_NPCAttackDialog.selectedDefense or "Fortitude"
    
    if not target or not damage or not threshold or damage <= 0 then
        SBS.Utils:Error("Введите корректные значения!")
        return
    end
    
    SBS.Combat:NPCAttack(target, damage, threshold, defense)
    -- Окно остаётся открытым для быстрых повторных атак
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ HP ИГРОКА (мастер)
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowModifyPlayerHPDialog()
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    -- Если есть цель, проверяем что это игрок
    if guid then
        if SBS.Utils:IsTargetPlayer() then
            SBS_ModifyPlayerHPDialog_TargetName:SetText(name)
        else
            SBS_ModifyPlayerHPDialog_TargetName:SetText("|cFFFF6666" .. name .. " (NPC)|r")
        end
    else
        SBS_ModifyPlayerHPDialog_TargetName:SetText("|cFF888888Нет игрока|r")
    end
    
    SBS_ModifyPlayerHPDialog:Show()
    SBS_ModifyPlayerHPDialog_Input:SetFocus()
end

function SBS.Dialogs:ApplyModifyPlayerHP(direction)
    -- Берём ТЕКУЩУЮ цель, а не сохранённую при открытии
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    
    -- Только для игроков, не для NPC
    if not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Это NPC! Используйте HP NPC.")
        return
    end
    
    local amount = tonumber(SBS_ModifyPlayerHPDialog_Input:GetText())
    if not amount or amount <= 0 then
        SBS.Utils:Error("Введите корректное значение!")
        return
    end
    
    local value = amount * direction
    SBS.Combat:ModifyPlayerHP(name, value)
    
    -- Обновляем имя цели в заголовке, значение НЕ очищаем
    SBS_ModifyPlayerHPDialog_TargetName:SetText(name)
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ДЕЙСТВИЙ МАСТЕРА НАД ИГРОКОМ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowPlayerActionsMenu(button)
    if not SBS.Utils:RequireMaster() then return end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    
    local items = {
        { text = "Действия: " .. name, isTitle = true, notCheckable = true },
        { text = " ", isTitle = true, notCheckable = true },
        
        -- HP
        { text = "|cFF66CCFFИзменить HP|r", notCheckable = true,
          func = function() self:ShowModifyPlayerHPDialog() end },
        
        { text = " ", isTitle = true, notCheckable = true },
        
        -- Роль
        { text = "|cFFA06AF1Сменить роль|r", notCheckable = true,
          func = function() self:ShowSetSpecMenu(name) end },
        
        { text = " ", isTitle = true, notCheckable = true },
        
        -- Ранения
        { text = "|cFFFF6666Добавить ранение|r", notCheckable = true,
          func = function() SBS.Sync:AddWound(name) end },
        { text = "|cFF66FF66Снять ранение|r", notCheckable = true,
          func = function() SBS.Sync:RemoveWound(name) end },
    }
    
    EasyMenu(items, CreateFrame("Frame", "SBS_PlayerActionsMenu", UIParent, "UIDropDownMenuTemplate"), button, 0, 0, "MENU")
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГИ XP (устаревшие, оставлены для совместимости)
-- ═══════════════════════════════════════════════════════════

-- XP система удалена в версии 2.0
-- Уровень теперь привязан к уровню персонажа на сервере
function SBS.Dialogs:ShowGiveXPDialog(targetName)
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.Dialogs:ApplyGiveXP()
    -- Устаревшая функция - XP система удалена в v2.0
end

function SBS.Dialogs:ShowRemoveXPDialog(targetName)
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.Dialogs:ShowSetLevelDialog(targetName)
    SBS.Utils:Warn("Уровень привязан к уровню персонажа на сервере.")
end

function SBS.Dialogs:ApplySetLevel()
    -- Устаревшая функция - уровень привязан к серверу
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ СМЕНЫ РОЛИ (МАСТЕР)
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowSetSpecMenu(targetName)
    local items = {
        { text = "Роль: " .. targetName, isTitle = true },
    }
    
    table.insert(items, {
        text = "Сбросить",
        color = {r = 0.5, g = 0.5, b = 0.5},
        tooltip = "Сбросить роль",
        tooltipDesc = "Убирает роль у игрока",
        func = function() SBS.Sync:SetSpec(targetName, nil) end
    })
    
    for key, data in pairs(SBS.Config.Roles) do
        local r = tonumber(data.color:sub(1,2), 16)/255
        local g = tonumber(data.color:sub(3,4), 16)/255
        local b = tonumber(data.color:sub(5,6), 16)/255
        table.insert(items, {
            text = data.name,
            color = {r = r, g = g, b = b},
            tooltip = data.name,
            tooltipDesc = data.description,
            func = function() SBS.Sync:SetSpec(targetName, key) end
        })
    end
    
    ShowMenu(MasterSpecMenu, nil, items)
end

-- Меню выбора своей роли
function SBS.Dialogs:ShowRoleMenu(button)
    if not SBS.Stats:CanChooseRole() then
        SBS.Utils:Error("Требуется " .. SBS.Config.ROLE_REQUIRED_LEVEL .. " уровень!")
        return
    end
    
    local items = {
        { text = "Выберите роль", isTitle = true },
    }
    
    for key, data in pairs(SBS.Config.Roles) do
        local r = tonumber(data.color:sub(1,2), 16)/255
        local g = tonumber(data.color:sub(3,4), 16)/255
        local b = tonumber(data.color:sub(5,6), 16)/255
        table.insert(items, {
            text = data.name,
            color = {r = r, g = g, b = b},
            tooltip = data.name,
            tooltipDesc = data.description,
            func = function() 
                SBS.Stats:SetRole(key)
                if SBS.UI then SBS.UI:UpdateMainFrame() end
            end
        })
    end

    -- Липкое меню, открывается вверх (без collapsible)
    if SpecMenu:IsShown() and SpecMenu.anchorButton == button then
        SpecMenu:Hide()
        return
    end
    ShowMenu(SpecMenu, button, items, { position = "top", sticky = true })
end

-- Алиас для совместимости
function SBS.Dialogs:ShowSpecMenu(button)
    self:ShowRoleMenu(button)
end

-- ═══════════════════════════════════════════════════════════
-- ОКНО ЗАЩИТЫ ОТ АТАКИ NPC (для игрока)
-- ═══════════════════════════════════════════════════════════

local DefenseFrame = nil
local defenseTimer = nil

local function CreateDefenseFrame()
    if DefenseFrame then return DefenseFrame end
    
    local f = CreateFrame("Frame", "SBS_DefenseFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 160)
    f:SetPoint("CENTER", 0, 100)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.2, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    
    -- Заголовок
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("|cFFFF6666ВАС АТАКУЮТ!|r")
    
    -- Имя NPC
    f.npcName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.npcName:SetPoint("TOP", 0, -35)
    f.npcName:SetText("")
    
    -- Защита (для обычного режима)
    f.defenseText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.defenseText:SetPoint("TOP", 0, -60)
    f.defenseText:SetText("")
    
    -- Таймер
    f.timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.timerText:SetPoint("TOP", 0, -85)
    f.timerText:SetText("")
    
    -- Кнопка защиты
    f.defendBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.defendBtn:SetSize(180, 32)
    f.defendBtn:SetPoint("BOTTOM", 0, 15)
    f.defendBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.defendBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    f.defendBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
    
    f.defendBtn.text = f.defendBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.defendBtn.text:SetPoint("CENTER")
    f.defendBtn.text:SetText("|cFF00FF00ЗАЩИТА|r")
    
    f.defendBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.3, 1)
    end)
    f.defendBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
    end)
    f.defendBtn:SetScript("OnClick", function(self)
        SBS.Dialogs:OnDefenseClicked()
    end)
    
    DefenseFrame = f
    return f
end

local function StopDefenseTimer()
    if defenseTimer then
        defenseTimer:Cancel()
        defenseTimer = nil
    end
end

local function StartDefenseTimer(duration, onTimeout)
    StopDefenseTimer()
    
    local f = DefenseFrame
    if not f then return end
    
    local endTime = GetTime() + duration
    
    defenseTimer = C_Timer.NewTicker(0.1, function()
        local remaining = endTime - GetTime()
        if remaining <= 0 then
            StopDefenseTimer()
            if onTimeout then onTimeout() end
            return
        end
        
        local color = remaining > 10 and "FFFFFF" or (remaining > 5 and "FFFF00" or "FF0000")
        f.timerText:SetText("|cFF" .. color .. string.format("%.1f", remaining) .. " сек|r")
    end)
end

function SBS.Dialogs:ShowNPCAttackAlert(npcName, defenseStat, damage, threshold)
    local f = CreateDefenseFrame()
    
    local statNames = {
        Fortitude = "|cFFA330C9Стойкость|r",
        Reflex = "|cFFFF7D0AСноровка|r",
        Will = "|cFF8787EDВоля|r"
    }
    
    f.npcName:SetText("|cFFFFFFFF" .. npcName .. "|r")
    f.defenseText:SetText("Против вашей " .. (statNames[defenseStat] or defenseStat))
    f.defenseText:Show()
    
    -- Если урон == 0, это проверка, а не атака
    if damage == 0 then
        f.title:SetText("|cFFFFD700ПРОВЕРКА!|r")
        f:SetBackdropBorderColor(0.8, 0.7, 0.2, 1)
        f.defendBtn.text:SetText("|cFFFFD700БРОСОК|r")
        f.defendBtn:SetBackdropColor(0.4, 0.35, 0.15, 1)
        f.defendBtn:SetBackdropBorderColor(0.7, 0.6, 0.2, 1)
    else
        f.title:SetText("|cFFFF6666ВАС АТАКУЮТ!|r")
        f:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        f.defendBtn.text:SetText("|cFF00FF00ЗАЩИТА|r")
        f.defendBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
        f.defendBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
    end
    
    -- Сохраняем данные
    f.pendingDamage = damage
    f.pendingThreshold = threshold
    f.pendingDefense = defenseStat
    f.pendingNPCName = npcName
    f.isHybrid = false
    
    f:Show()
    PlaySound(8959, "SFX") -- RAID_WARNING
    
    -- Запускаем таймер 30 сек
    StartDefenseTimer(30, function()
        -- Автонеудача
        SBS.Dialogs:OnDefenseTimeout()
    end)
end

function SBS.Dialogs:ShowHybridDefenseChoice(npcName, damage, threshold)
    local f = CreateDefenseFrame()
    
    f.npcName:SetText("|cFFFFFFFF" .. npcName .. "|r")
    f.defenseText:SetText("|cFF33CCCCВыберите защиту|r")
    f.defenseText:Show()
    f.defendBtn.text:SetText("|cFF33CCCCЗАЩИТА|r")
    
    -- Меняем цвет рамки на бирюзовый для гибрида
    f:SetBackdropBorderColor(0.2, 0.8, 0.8, 1)
    
    -- Сохраняем данные
    f.pendingDamage = damage
    f.pendingThreshold = threshold
    f.pendingDefense = nil
    f.pendingNPCName = npcName
    f.isHybrid = true
    
    f:Show()
    PlaySound(8959, "SFX") -- RAID_WARNING
    
    -- Запускаем таймер 30 сек
    StartDefenseTimer(30, function()
        SBS.Dialogs:OnDefenseTimeout()
    end)
end

function SBS.Dialogs:OnDefenseClicked()
    local f = DefenseFrame
    if not f then return end
    
    if f.isHybrid then
        -- Показываем выпадающее меню выбора защиты
        SBS.Dialogs:ShowDefenseDropdown(f.defendBtn)
    else
        -- Обычная защита — сразу бросаем
        StopDefenseTimer()
        f:Hide()
        
        if SBS.Combat and SBS.Combat.ProcessNPCAttack then
            SBS.Combat:ProcessNPCAttack(f.pendingDamage, f.pendingThreshold, f.pendingDefense, f.pendingNPCName)
        end
    end
end

function SBS.Dialogs:ShowDefenseDropdown(button)
    local menu = CreateFrame("Frame", "SBS_DefenseDropdownMenu", UIParent, "BackdropTemplate")
    menu:SetSize(180, 80)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local defenses = {
        {"Fortitude", "Стойкость", {r=0.64, g=0.19, b=0.79}},
        {"Reflex", "Сноровка", {r=1, g=0.49, b=0.04}},
        {"Will", "Воля", {r=0.53, g=0.53, b=0.93}}
    }
    
    local y = -5
    for _, def in ipairs(defenses) do
        local btn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        btn:SetSize(170, 24)
        btn:SetPoint("TOP", 0, y)
        btn:SetBackdrop(SBS.Utils.Backdrops.NoEdge)
        btn:SetBackdropColor(0, 0, 0, 0)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(def[2])
        btn.text:SetTextColor(def[3].r, def[3].g, def[3].b)
        
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(def[3].r * 0.3, def[3].g * 0.3, def[3].b * 0.3, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
        end)
        btn:SetScript("OnClick", function(self)
            menu:Hide()
            SBS.Dialogs:OnHybridDefenseSelected(def[1])
        end)
        
        y = y - 25
    end
    
    menu:SetPoint("BOTTOM", button, "TOP", 0, 5)
    menu:Show()
    
    -- Закрытие при клике вне меню
    menu:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and not button:IsMouseOver() and IsMouseButtonDown("LeftButton") then
            self:Hide()
        end
    end)
end

function SBS.Dialogs:OnHybridDefenseSelected(defenseStat)
    local f = DefenseFrame
    if not f then return end
    
    StopDefenseTimer()
    f:Hide()
    
    -- Выполняем бросок защиты с выбранной статой
    if SBS.Combat and SBS.Combat.ProcessNPCAttack then
        SBS.Combat:ProcessNPCAttack(f.pendingDamage, f.pendingThreshold, defenseStat, f.pendingNPCName)
    end
end

function SBS.Dialogs:OnDefenseTimeout()
    local f = DefenseFrame
    if not f or not f:IsShown() then return end
    
    local npcName = f.pendingNPCName or "NPC"
    local damage = f.pendingDamage or 0
    
    f:Hide()
    
    -- Автонеудача — получаем полный урон
    if SBS.Combat then
        SBS.Combat:ProcessDefenseFailure(damage, npcName)
    end
end

-- ═══════════════════════════════════════════════════════════
-- МЕНЮ ВЫБОРА КРИТА
-- ═══════════════════════════════════════════════════════════

local CritChoiceMenu = CreateCustomMenu("SBS_CritChoiceMenu", 220)

-- Показать меню выбора при крите атаки
function SBS.Dialogs:ShowCritChoiceMenu(actionType, callback, baseDamage, targetGuid, targetName)
    local role = SBS.Stats:GetRole()
    local items = {}
    
    table.insert(items, { text = "— КРИТ! Выберите бонус —", isTitle = true })
    
    -- +3 к урону/исцелению
    local bonusText = actionType == "heal" and "+3 к исцелению" or "+3 к урону"
    table.insert(items, {
        text = "|cFFFF6666" .. bonusText .. "|r",
        func = function()
            callback("bonus_damage", baseDamage + 3, targetGuid, targetName)
        end,
        tooltip = "Усиленный эффект",
        tooltipDesc = actionType == "heal" and "Исцеление увеличено на 3" or "Урон увеличен на 3"
    })
    
    -- +1 энергия
    local energy = SBS.Stats:GetEnergy()
    local maxEnergy = SBS.Stats:GetMaxEnergy()
    local energyColor = energy < maxEnergy and "66FF66" or "666666"
    table.insert(items, {
        text = "|cFF" .. energyColor .. "+1 энергия|r",
        func = function()
            SBS.Stats:AddEnergy(1)
            callback("energy", baseDamage, targetGuid, targetName)
        end,
        tooltip = "Восстановление энергии",
        tooltipDesc = "Текущая энергия: " .. energy .. "/" .. maxEnergy
    })
    
    -- Полное исцеление (только Целитель)
    if role == "healer" then
        table.insert(items, {
            text = "|cFF66FF66Полное исцеление|r",
            func = function()
                callback("full_heal", baseDamage, targetGuid, targetName)
            end,
            tooltip = "Целитель: полное исцеление",
            tooltipDesc = "Цель восстанавливает всё здоровье"
        })
    end
    
    -- 3 ед. щита (только Танк)
    if role == "tank" then
        table.insert(items, {
            text = "|cFF66CCFF+3 щита|r",
            func = function()
                SBS.Stats:AddShield(3)
                SBS.Utils:Info("Получено 3 ед. щита!")
                callback("shield", baseDamage, targetGuid, targetName)
            end,
            tooltip = "Танк: защитный щит",
            tooltipDesc = "Вы получаете 3 единицы щита"
        })
    end
    
    ShowMenu(CritChoiceMenu, nil, items)
end

-- Показать меню выбора при крите защиты
function SBS.Dialogs:ShowDefenseCritChoiceMenu(callback, attackerName, attackerGuid)
    local items = {}
    local energy, maxEnergy = SBS.Stats:GetEnergy(), SBS.Stats:GetMaxEnergy()
    local energyColor = energy < maxEnergy and "66FF66" or "666666"
    table.insert(items, { text = "— КРИТ ЗАЩИТЫ! —", isTitle = true })
    table.insert(items, { text = "|cFFFF6666Контратака|r", func = function() callback("counterattack", attackerName, attackerGuid) end, tooltip = "Мгновенная контратака", tooltipDesc = "100% успех против атакующего" })
    table.insert(items, { text = "|cFF" .. energyColor .. "+1 энергия|r", func = function() SBS.Stats:AddEnergy(1) callback("energy", attackerName, attackerGuid) end, tooltip = "Восстановление энергии", tooltipDesc = "Текущая энергия: " .. energy .. "/" .. maxEnergy })
    ShowMenu(CritChoiceMenu, nil, items)
end

-- Диалог выбора контратаки для танка (при успешной защите)
function SBS.Dialogs:ShowTankCounterattackChoice(callback, attackerName, attackerGuid)
    local items = {}
    table.insert(items, { text = "— ТАНК: КОНТРАТАКА —", isTitle = true })
    table.insert(items, { text = "|cFFFF6666Контратаковать|r", func = function() callback(true) end, tooltip = "Контратака", tooltipDesc = "Нанести урон атакующему" })
    table.insert(items, { text = "|cFF888888Отказаться|r", func = function() callback(false) end, tooltip = "Отказаться от контратаки", tooltipDesc = "Пропустить контратаку" })
    ShowMenu(CritChoiceMenu, nil, items)
end

-- Диалог добивания для бойца
function SBS.Dialogs:ShowDDFinisherChoice(callback, targetName, currentHP, maxHP)
    local items = {}
    local hpPercent = string.format("%.0f", (currentHP / maxHP) * 100)
    table.insert(items, { text = "— БОЕЦ: ДОБИВАНИЕ —", isTitle = true })
    table.insert(items, { text = "|cFF888888" .. targetName .. " (" .. currentHP .. "/" .. maxHP .. " HP, " .. hpPercent .. "%)|r", isTitle = true })
    table.insert(items, { text = "|cFFFF0000Добить|r", func = function() callback(true) end, tooltip = "Мгновенное убийство", tooltipDesc = "Цель будет убита" })
    table.insert(items, { text = "|cFF888888Пощадить|r", func = function() callback(false) end, tooltip = "Отказаться от добивания", tooltipDesc = "Оставить цель в живых" })
    ShowMenu(CritChoiceMenu, nil, items)
end

-- ═══════════════════════════════════════════════════════════
-- ОСОБОЕ ДЕЙСТВИЕ
-- ═══════════════════════════════════════════════════════════

local SpecialActionFrame = nil

local function CreateSpecialActionFrame()
    if SpecialActionFrame then return SpecialActionFrame end
    
    local f = CreateFrame("Frame", "SBS_SpecialActionFrame", UIParent, "BackdropTemplate")
    f:SetSize(400, 280)
    f:SetPoint("CENTER", 0, 50)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.4, 0.3, 0.6, 1)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    -- НЕ регистрируем drag на основном фрейме - это мешает EditBox
    f:Hide()
    
    -- Titlebar для перетаскивания (только за эту область можно тянуть)
    f.titleBar = CreateFrame("Frame", nil, f)
    f.titleBar:SetHeight(40)
    f.titleBar:SetPoint("TOPLEFT", 0, 0)
    f.titleBar:SetPoint("TOPRIGHT", 0, 0)
    f.titleBar:EnableMouse(true)
    f.titleBar:RegisterForDrag("LeftButton")
    f.titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    f.titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    
    -- Заголовок
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -15)
    f.title:SetText("|cFF9966FFЗапрос на особое действие|r")
    
    -- Описание
    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.desc:SetPoint("TOP", 0, -40)
    f.desc:SetText("Опишите ваше особое действие (до 1000 символов)")
    f.desc:SetTextColor(0.7, 0.7, 0.7)
    
    -- Контейнер для поля ввода с видимой рамкой
    f.inputContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.inputContainer:SetPoint("TOPLEFT", 15, -65)
    f.inputContainer:SetPoint("BOTTOMRIGHT", -15, 55)
    f.inputContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.inputContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    f.inputContainer:SetBackdropBorderColor(0.3, 0.25, 0.4, 1)
    
    -- Клик по контейнеру активирует EditBox
    f.inputContainer:EnableMouse(true)
    f.inputContainer:SetScript("OnMouseDown", function()
        f.editBox:SetFocus()
    end)
    
    -- Поле ввода (внутри контейнера)
    f.scrollFrame = CreateFrame("ScrollFrame", nil, f.inputContainer, "UIPanelScrollFrameTemplate")
    f.scrollFrame:SetPoint("TOPLEFT", 8, -8)
    f.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    
    -- Клик по ScrollFrame тоже активирует EditBox
    f.scrollFrame:EnableMouse(true)
    f.scrollFrame:SetScript("OnMouseDown", function()
        f.editBox:SetFocus()
    end)
    
    f.editBox = CreateFrame("EditBox", nil, f.scrollFrame)
    f.editBox:SetMultiLine(true)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(320)
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    f.editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local len = #text
        f.charCount:SetText(len .. "/" .. SBS.Config.SPECIAL_ACTION_MAX_TEXT)
        if len > SBS.Config.SPECIAL_ACTION_MAX_TEXT then
            f.charCount:SetTextColor(1, 0.3, 0.3)
            f.sendBtn:Disable()
        else
            f.charCount:SetTextColor(0.6, 0.6, 0.6)
            f.sendBtn:Enable()
        end
    end)
    
    f.scrollFrame:SetScrollChild(f.editBox)
    
    -- Счётчик символов (справа от кнопки Отмена)
    f.charCount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.charCount:SetPoint("BOTTOM", 0, 18)
    f.charCount:SetText("0/" .. SBS.Config.SPECIAL_ACTION_MAX_TEXT)
    f.charCount:SetTextColor(0.6, 0.6, 0.6)
    
    -- Кнопка отправки
    f.sendBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.sendBtn:SetSize(120, 30)
    f.sendBtn:SetPoint("BOTTOMRIGHT", -15, 10)
    f.sendBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.sendBtn:SetBackdropColor(0.3, 0.2, 0.5, 1)
    f.sendBtn:SetBackdropBorderColor(0.5, 0.3, 0.7, 1)
    
    f.sendBtn.text = f.sendBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.sendBtn.text:SetPoint("CENTER")
    f.sendBtn.text:SetText("|cFFFFFFFFОтправить запрос|r")
    
    f.sendBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.3, 0.6, 1)
    end)
    f.sendBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.5, 1)
    end)
    f.sendBtn:SetScript("OnClick", function(self)
        SBS.Dialogs:SubmitSpecialAction()
    end)
    
    -- Кнопка отмены
    f.cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.cancelBtn:SetSize(80, 30)
    f.cancelBtn:SetPoint("BOTTOMLEFT", 15, 10)
    f.cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.cancelBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    f.cancelBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    f.cancelBtn.text = f.cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.cancelBtn.text:SetPoint("CENTER")
    f.cancelBtn.text:SetText("|cFFAAAAAAОтмена|r")
    
    f.cancelBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Кнопка закрытия
    f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts")
    f.closeBtn:SetSize(20, 20)
    f.closeBtn:SetPoint("TOPRIGHT", -3, -3)
    f.closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    SpecialActionFrame = f
    return f
end

function SBS.Dialogs:ShowSpecialActionInput()
    local f = CreateSpecialActionFrame()
    f.editBox:SetText("")
    f.charCount:SetText("0/" .. SBS.Config.SPECIAL_ACTION_MAX_TEXT)
    f:Show()
    f.editBox:SetFocus()
end

-- Алиас для нового процесса запроса особого действия
function SBS.Dialogs:ShowSpecialActionRequestDialog()
    self:ShowSpecialActionInput()
end

function SBS.Dialogs:SubmitSpecialAction()
    local f = SpecialActionFrame
    if not f then return end

    local text = f.editBox:GetText()
    if #text == 0 then
        SBS.Utils:Error("Введите описание действия!")
        return
    end

    if #text > SBS.Config.SPECIAL_ACTION_MAX_TEXT then
        SBS.Utils:Error("Текст слишком длинный!")
        return
    end

    f:Hide()

    -- Сохраняем ожидающий запрос
    local playerName = UnitName("player")
    SBS.Combat.PendingSpecialAction = {
        playerName = playerName,
        description = text,
        timestamp = GetTime()
    }

    -- Если мы сами мастер - показать окно одобрения напрямую
    if SBS.Sync:IsMaster() then
        SBS.Dialogs:ShowMasterSpecialActionApproval(playerName, text)
        SBS.Utils:Info("Вы мастер - одобрите или отклоните своё действие.")
    else
        -- Отправляем запрос мастеру
        SBS.Sync:SendSpecialActionRequest(text)
        SBS.Utils:Info("Запрос на особое действие отправлен мастеру. Ожидайте одобрения...")
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОКНО МАСТЕРА ДЛЯ ОСОБЫХ ДЕЙСТВИЙ
-- ═══════════════════════════════════════════════════════════

-- Множественные окна одобрения для каждого игрока
local SpecialActionApprovalFrames = {}  -- {[playerName] = {frame=frame, timestamp=time}}
local FrameOffsetCounter = 0

function SBS.Dialogs:ShowMasterSpecialActionApproval(playerName, description)
    -- Если окно для этого игрока уже открыто, показать и поднять на передний план
    if SpecialActionApprovalFrames[playerName] then
        local data = SpecialActionApprovalFrames[playerName]
        data.frame:Show()
        data.frame:Raise()
        return
    end

    -- Создать уникальный фрейм для этого игрока
    local frameName = "SBS_MasterSpecialAction_" .. playerName:gsub(" ", "_")
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")

    -- Настроить размер и фон
    f:SetSize(400, 355)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.6, 0.4, 0.2, 1)
    f:SetFrameStrata("DIALOG")

    -- Сделать перемещаемым
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Расположить с смещением (каскадом)
    FrameOffsetCounter = FrameOffsetCounter + 40
    if FrameOffsetCounter > 200 then FrameOffsetCounter = 0 end
    f:SetPoint("CENTER", UIParent, "CENTER", FrameOffsetCounter, -FrameOffsetCounter)

    -- Заголовок
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -15)
    f.title:SetText("|cFFFFD700Запрос на особое действие|r")

    -- Имя игрока
    f.playerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.playerLabel:SetPoint("TOPLEFT", 20, -45)
    f.playerLabel:SetText("|cFFFFFFFFИгрок:|r |cFF66CCFF" .. playerName .. "|r")

    -- Контейнер для текста описания
    f.descContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.descContainer:SetPoint("TOPLEFT", 15, -70)
    f.descContainer:SetPoint("TOPRIGHT", -15, -70)
    f.descContainer:SetHeight(100)
    f.descContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.descContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    f.descContainer:SetBackdropBorderColor(0.3, 0.25, 0.4, 1)

    -- ScrollFrame для текста
    f.scrollFrame = CreateFrame("ScrollFrame", nil, f.descContainer, "UIPanelScrollFrameTemplate")
    f.scrollFrame:SetPoint("TOPLEFT", 5, -5)
    f.scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    -- Контент для скролла
    f.scrollContent = CreateFrame("Frame", nil, f.scrollFrame)
    f.scrollContent:SetSize(330, 1)
    f.scrollFrame:SetScrollChild(f.scrollContent)

    -- Текст описания действия
    f.descText = f.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.descText:SetPoint("TOPLEFT", 5, 0)
    f.descText:SetWidth(320)
    f.descText:SetWordWrap(true)
    f.descText:SetJustifyH("LEFT")
    f.descText:SetJustifyV("TOP")
    f.descText:SetText(description or "")
    f.descText:SetTextColor(0.9, 0.9, 0.9)

    -- Подгоняем высоту контента под текст
    f.scrollContent:SetHeight(math.max(90, f.descText:GetStringHeight() + 10))

    -- Поле ввода порога
    f.thresholdLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.thresholdLabel:SetPoint("TOPLEFT", 20, -180)
    f.thresholdLabel:SetText("Порог:")

    f.thresholdInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    f.thresholdInput:SetPoint("LEFT", f.thresholdLabel, "RIGHT", 10, 0)
    f.thresholdInput:SetSize(50, 24)
    f.thresholdInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.thresholdInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    f.thresholdInput:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f.thresholdInput:SetFontObject(ChatFontNormal)
    f.thresholdInput:SetText("14")
    f.thresholdInput:SetAutoFocus(false)
    f.thresholdInput:SetNumeric(true)
    f.thresholdInput:SetTextInsets(5, 5, 0, 0)
    f.thresholdInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.thresholdInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Выбор характеристики (кнопки — две строки)
    f.statLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.statLabel:SetPoint("TOPLEFT", 20, -215)
    f.statLabel:SetText("Характеристика:")

    f.selectedStat = "Strength"  -- По умолчанию

    local statButtons = {}
    local row1Stats = { "Strength", "Dexterity", "Intelligence", "Spirit" }
    local row2Stats = { "Fortitude", "Reflex", "Will" }

    local function CreateStatRow(stats, yOff)
        local xOff = 20
        for _, stat in ipairs(stats) do
            local statName = SBS.Config.StatNames[stat] or stat
            local statColor = SBS.Config.StatColors[stat] or "FFFFFF"

            local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
            btn:SetSize(85, 24)
            btn:SetPoint("TOPLEFT", xOff, yOff)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1
            })

            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.text:SetPoint("CENTER")
            btn.text:SetText("|cFF" .. statColor .. statName .. "|r")

            btn.stat = stat
            btn.statColor = statColor

            local function UpdateButtonStates()
                for _, b in ipairs(statButtons) do
                    if b.stat == f.selectedStat then
                        b:SetBackdropColor(0.2, 0.4, 0.2, 1)
                        b:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
                    else
                        b:SetBackdropColor(0.15, 0.15, 0.15, 1)
                        b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                    end
                end
            end

            btn:SetScript("OnClick", function()
                f.selectedStat = stat
                UpdateButtonStates()
            end)

            btn:SetScript("OnEnter", function(self)
                if self.stat ~= f.selectedStat then
                    self:SetBackdropColor(0.25, 0.25, 0.25, 1)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                UpdateButtonStates()
            end)

            table.insert(statButtons, btn)
            xOff = xOff + 90
        end
    end

    CreateStatRow(row1Stats, -235)
    CreateStatRow(row2Stats, -262)

    -- Обновить состояние кнопок
    for _, b in ipairs(statButtons) do
        if b.stat == f.selectedStat then
            b:SetBackdropColor(0.2, 0.4, 0.2, 1)
            b:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        else
            b:SetBackdropColor(0.15, 0.15, 0.15, 1)
            b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end

    -- Кнопка Одобрить
    f.approveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.approveBtn:SetSize(150, 32)
    f.approveBtn:SetPoint("BOTTOMLEFT", 30, 15)
    f.approveBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.approveBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    f.approveBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)

    f.approveBtn.text = f.approveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.approveBtn.text:SetPoint("CENTER")
    f.approveBtn.text:SetText("|cFF00FF00Одобрить|r")

    f.approveBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.3, 1)
    end)
    f.approveBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
    end)
    f.approveBtn:SetScript("OnClick", function()
        local threshold = tonumber(f.thresholdInput:GetText()) or 14
        local stat = f.selectedStat or "Strength"

        SBS.Sync:SendSpecialActionApproved(playerName, threshold, stat)
        SpecialActionApprovalFrames[playerName] = nil
        f:Hide()

        SBS.Utils:Info("Особое действие игрока " .. playerName .. " |cFF00FF00одобрено|r.")
    end)

    -- Кнопка Отклонить
    f.rejectBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.rejectBtn:SetSize(150, 32)
    f.rejectBtn:SetPoint("BOTTOMRIGHT", -30, 15)
    f.rejectBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.rejectBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    f.rejectBtn:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)

    f.rejectBtn.text = f.rejectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.rejectBtn.text:SetPoint("CENTER")
    f.rejectBtn.text:SetText("|cFFFF6666Отклонить|r")

    f.rejectBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.3, 0.3, 1)
    end)
    f.rejectBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.2, 1)
    end)
    f.rejectBtn:SetScript("OnClick", function()
        SBS.Sync:SendSpecialActionRejected(playerName)
        SpecialActionApprovalFrames[playerName] = nil
        f:Hide()

        SBS.Utils:Info("Особое действие игрока " .. playerName .. " |cFFFF6666отклонено|r.")
    end)

    -- Кнопка закрытия (X)
    f.closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.closeBtn:SetSize(20, 20)
    f.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    f.closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.closeBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    f.closeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    f.closeBtn.text = f.closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.closeBtn.text:SetPoint("CENTER", 0, 1)
    f.closeBtn.text:SetText("X")

    f.closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.15, 0.15, 1)
    end)
    f.closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 1)
    end)
    f.closeBtn:SetScript("OnClick", function()
        SpecialActionApprovalFrames[playerName] = nil
        f:Hide()
    end)

    -- Сохранить в таблице активных окон
    SpecialActionApprovalFrames[playerName] = {
        frame = f,
        timestamp = GetTime()
    }

    f:Show()
    PlaySound(8959, "SFX")
end

-- Алиас для обратной совместимости
function SBS.Dialogs:ShowMasterSpecialActionRequest(playerName, description)
    self:ShowMasterSpecialActionApproval(playerName, description)
end

-- ═══════════════════════════════════════════════════════════
-- ОКНО НАСТРОЕК
-- ═══════════════════════════════════════════════════════════

local SettingsFrame = nil

function SBS.Dialogs:ShowSettings()
    if SettingsFrame then
        SettingsFrame:Show()
        return
    end
    
    -- Создаём окно
    local f = CreateFrame("Frame", "SBS_SettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(280, 150)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    
    -- Заголовок
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop(SBS.Utils.Backdrops.NoEdge)
    titleBar:SetBackdropColor(0.15, 0.15, 0.15, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER")
    title:SetText("|cFFFFD700Настройки SBS|r")
    
    -- Кнопка закрытия
    local close = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -4, 0)
    close:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    close:SetBackdropColor(0.2, 0.2, 0.2, 1)
    close:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER", 0, 1)
    closeText:SetText("X")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.15, 0.15, 1) end)
    close:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 1) end)
    
    -- Метка слайдера
    local scaleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", 15, -45)
    scaleLabel:SetText("Масштаб интерфейса:")
    
    -- Текущее значение
    local scaleValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValue:SetPoint("TOPRIGHT", -15, -45)
    
    -- Слайдер
    local slider = CreateFrame("Slider", "SBS_ScaleSlider", f, "OptionsSliderTemplate")
    slider:SetWidth(250)
    slider:SetHeight(17)
    slider:SetPoint("TOP", 0, -70)
    slider:SetMinMaxValues(0.5, 1.5)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    
    -- Убираем стандартные надписи
    _G[slider:GetName().."Low"]:SetText("50%")
    _G[slider:GetName().."High"]:SetText("150%")
    _G[slider:GetName().."Text"]:SetText("")
    
    -- Обновление значения
    local function UpdateScaleDisplay(value)
        scaleValue:SetText(string.format("|cFF00FF00%d%%|r", value * 100))
    end
    
    -- Загружаем текущее значение
    local currentScale = SBS.db and SBS.db.profile and SBS.db.profile.uiScale or 1.0
    slider:SetValue(currentScale)
    UpdateScaleDisplay(currentScale)
    
    -- При изменении слайдера
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20  -- Округляем до 0.05
        UpdateScaleDisplay(value)
        
        -- Применяем масштаб
        if SBS.db and SBS.db.profile then
            SBS.db.profile.uiScale = value
            SBS.Utils:ApplyUIScale()
        end
    end)
    
    -- Кнопка сброса
    local resetBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    resetBtn:SetSize(120, 26)
    resetBtn:SetPoint("BOTTOM", 0, 15)
    resetBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    resetBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    resetBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetText:SetPoint("CENTER")
    resetText:SetText("Сбросить (100%)")
    
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 1) end)
    resetBtn:SetScript("OnClick", function()
        slider:SetValue(1.0)
    end)
    
    SettingsFrame = f
    f:Show()
end

function SBS.Dialogs:HideSettings()
    if SettingsFrame then
        SettingsFrame:Hide()
    end
end

function SBS.Dialogs:ToggleSettings()
    if SettingsFrame and SettingsFrame:IsShown() then
        SettingsFrame:Hide()
    else
        self:ShowSettings()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ МАСТЕРА: ПРИМЕНЕНИЕ ЭФФЕКТА
-- ═══════════════════════════════════════════════════════════

local MasterEffectDialog = nil

function SBS.Dialogs:ShowMasterEffectDialog(effectId, targetType, targetId)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return
    end

    local def = SBS.Effects.Definitions[effectId]
    if not def then
        SBS.Utils:Error("Неизвестный эффект: " .. effectId)
        return
    end

    -- Закрываем старый диалог
    if MasterEffectDialog then
        MasterEffectDialog:Hide()
    end

    -- Для stun не нужно поле "Значение"
    local needsValue = (effectId ~= "stun")
    local dialogHeight = needsValue and 160 or 130

    -- Создаём диалог
    local f = CreateFrame("Frame", "SBS_MasterEffectDialog", UIParent, "BackdropTemplate")
    f:SetSize(220, dialogHeight)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Заголовок
    local colorHex = SBS.Effects:GetColorHex(def.color)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF" .. colorHex .. def.name .. "|r")

    -- Имя цели
    local targetName = targetType == "npc"
        and (SBS.Units:Get(targetId) and SBS.Units:Get(targetId).name or "NPC")
        or targetId
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOP", 0, -32)
    targetText:SetText("Цель: |cFFFFFFFF" .. targetName .. "|r")

    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local valueInput = nil
    local nextY = -55

    -- Поле "Значение" (только если нужно)
    if needsValue then
        local valueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueLabel:SetPoint("TOPLEFT", 15, nextY)
        valueLabel:SetText("Значение:")

        valueInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        valueInput:SetSize(60, 22)
        valueInput:SetPoint("TOPRIGHT", -15, nextY + 3)
        valueInput:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        valueInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
        valueInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        valueInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        valueInput:SetTextColor(1, 1, 1)
        valueInput:SetJustifyH("CENTER")
        valueInput:SetAutoFocus(false)
        valueInput:SetNumeric(true)
        valueInput:SetText("3")
        valueInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        valueInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        nextY = nextY - 27
    end

    -- Поле "Раунды"
    local durationLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPLEFT", 15, nextY)
    durationLabel:SetText("Раундов:")

    local durationInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    durationInput:SetSize(60, 22)
    durationInput:SetPoint("TOPRIGHT", -15, nextY + 3)
    durationInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    durationInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    durationInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    durationInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    durationInput:SetTextColor(1, 1, 1)
    durationInput:SetJustifyH("CENTER")
    durationInput:SetAutoFocus(false)
    durationInput:SetNumeric(true)
    durationInput:SetText("2")
    durationInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    durationInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Кнопка "Применить"
    local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    applyBtn:SetSize(90, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 15, 15)
    applyBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    applyBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    applyBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)

    local applyText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    applyText:SetPoint("CENTER")
    applyText:SetText("Применить")

    applyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.6, 0.3, 1) end)
    applyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    applyBtn:SetScript("OnClick", function()
        local value = needsValue and (tonumber(valueInput:GetText()) or 0) or 0
        local duration = tonumber(durationInput:GetText()) or 0

        if needsValue and value <= 0 then
            SBS.Utils:Error("Значение должно быть больше 0")
            return
        end
        if duration <= 0 then
            SBS.Utils:Error("Длительность должна быть больше 0")
            return
        end

        SBS.Effects:MasterApply(targetType, targetId, effectId, value, duration)
        f:Hide()
    end)

    -- Кнопка "Отмена"
    local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Отмена")

    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    MasterEffectDialog = f
    f:Show()
    if valueInput then
        valueInput:SetFocus()
    else
        durationInput:SetFocus()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ УЯЗВИМОСТИ (Vulnerability) - выбор защитного стата
-- ═══════════════════════════════════════════════════════════

local VulnerabilityDialog = nil

function SBS.Dialogs:ShowVulnerabilityDialog(targetName)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return
    end

    -- Закрываем старый диалог
    if VulnerabilityDialog then
        VulnerabilityDialog:Hide()
    end

    local f = CreateFrame("Frame", "SBS_VulnerabilityDialog", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.5, 0.3, 0.5, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF804080Уязвимость|r")

    -- Имя цели
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOP", 0, -32)
    targetText:SetText("Цель: |cFFFFFFFF" .. targetName .. "|r")

    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Подпись "Выберите стат"
    local selectLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectLabel:SetPoint("TOP", 0, -52)
    selectLabel:SetText("|cFF888888Выберите снижаемый стат:|r")

    -- Поля ввода (значение и длительность)
    local valueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLabel:SetPoint("TOPLEFT", 15, -130)
    valueLabel:SetText("Снижение:")

    local valueInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    valueInput:SetSize(50, 22)
    valueInput:SetPoint("LEFT", valueLabel, "RIGHT", 10, 0)
    valueInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    valueInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    valueInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    valueInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    valueInput:SetTextColor(1, 1, 1)
    valueInput:SetJustifyH("CENTER")
    valueInput:SetAutoFocus(false)
    valueInput:SetNumeric(true)
    valueInput:SetText("2")
    valueInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local durationLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("LEFT", valueInput, "RIGHT", 15, 0)
    durationLabel:SetText("Раундов:")

    local durationInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    durationInput:SetSize(40, 22)
    durationInput:SetPoint("LEFT", durationLabel, "RIGHT", 5, 0)
    durationInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    durationInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    durationInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    durationInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    durationInput:SetTextColor(1, 1, 1)
    durationInput:SetJustifyH("CENTER")
    durationInput:SetAutoFocus(false)
    durationInput:SetNumeric(true)
    durationInput:SetText("3")
    durationInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    durationInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Кнопки выбора стата
    local stats = {
        { id = "vulnerability_fortitude", name = "Стойкость", color = "A330C9" },
        { id = "vulnerability_reflex", name = "Сноровка", color = "FF7D0A" },
        { id = "vulnerability_will", name = "Воля", color = "8787ED" },
    }

    for i, stat in ipairs(stats) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(70, 26)
        btn:SetPoint("TOP", (i - 2) * 75, -70)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER")
        txt:SetText("|cFF" .. stat.color .. stat.name .. "|r")

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.25, 0.25, 1)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end)

        btn:SetScript("OnClick", function()
            local value = tonumber(valueInput:GetText()) or 0
            local duration = tonumber(durationInput:GetText()) or 0

            if value <= 0 then
                SBS.Utils:Error("Значение должно быть больше 0")
                return
            end
            if duration <= 0 then
                SBS.Utils:Error("Длительность должна быть больше 0")
                return
            end

            SBS.Effects:MasterApply("player", targetName, stat.id, value, duration)
            f:Hide()
        end)
    end

    -- Кнопка "Отмена"
    local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetPoint("BOTTOM", 0, 15)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Отмена")

    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    VulnerabilityDialog = f
    f:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ БАФФОВ МАСТЕРА
-- ═══════════════════════════════════════════════════════════

local MasterBuffDialog = nil

function SBS.Dialogs:ShowMasterBuffDialog(targetName)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return
    end

    -- Закрываем старый диалог
    if MasterBuffDialog then
        MasterBuffDialog:Hide()
    end

    local f = CreateFrame("Frame", "SBS_MasterBuffDialog", UIParent, "BackdropTemplate")
    f:SetSize(280, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF66FF99Наложить бафф|r")

    -- Имя цели
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOP", 0, -32)
    targetText:SetText("Цель: |cFFFFFFFF" .. targetName .. "|r")

    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Список баффов
    local buffs = {
        { id = "empower", name = "Усиление", desc = "+1 к урону", color = "FF9933", duration = 3 },
        { id = "fortify_fortitude", name = "Укрепление (Стойк.)", desc = "+2 к Стойкости", color = "A330C9", duration = 3 },
        { id = "fortify_reflex", name = "Укрепление (Снор.)", desc = "+2 к Сноровке", color = "FF7D0A", duration = 3 },
        { id = "fortify_will", name = "Укрепление (Воля)", desc = "+2 к Воле", color = "8787ED", duration = 3 },
        { id = "regeneration", name = "Регенерация", desc = "+1 HP/раунд", color = "33E666", duration = 3 },
        { id = "blessing", name = "Благословение", desc = "+1 к исцелению", color = "FFF266", duration = 3 },
    }

    local yOffset = -55
    for _, buff in ipairs(buffs) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(250, 28)
        btn:SetPoint("TOP", 0, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("LEFT", 10, 0)
        txt:SetText("|cFF" .. buff.color .. buff.name .. "|r")

        local desc = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("RIGHT", -10, 0)
        desc:SetText("|cFF888888" .. buff.desc .. "|r")

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.25, 0.25, 1)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end)

        btn:SetScript("OnClick", function()
            local def = SBS.Effects.Definitions[buff.id]
            if def then
                SBS.Effects:MasterApply("player", targetName, buff.id, def.fixedValue, def.fixedDuration)
            end
            f:Hide()
        end)

        yOffset = yOffset - 32
    end

    -- Кнопка "Отмена"
    local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetPoint("BOTTOM", 0, 15)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Отмена")

    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    MasterBuffDialog = f
    f:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ОСЛАБЛЕНИЯ (Weakness) - разные варианты для NPC/Игрока
-- ═══════════════════════════════════════════════════════════

local WeaknessDialog = nil

function SBS.Dialogs:ShowWeaknessDialog(targetType, targetId, targetName)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return
    end
    
    -- Закрываем старый диалог
    if WeaknessDialog then
        WeaknessDialog:Hide()
    end
    
    local isNPC = targetType == "npc"
    local dialogHeight = isNPC and 180 or 200
    
    -- Создаём диалог
    local f = CreateFrame("Frame", "SBS_WeaknessDialog", UIParent, "BackdropTemplate")
    f:SetSize(240, dialogHeight)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.6, 0.4, 0.4, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF996666Ослабление|r")
    
    -- Имя цели
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOP", 0, -32)
    targetText:SetText("Цель: |cFFFFFFFF" .. targetName .. "|r")
    
    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    local selectedStat = nil
    local statButtons = {}
    
    if isNPC then
        -- Для NPC: выбор защитного стата
        local statLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statLabel:SetPoint("TOPLEFT", 15, -55)
        statLabel:SetText("Ослабить защиту:")
        
        local stats = {
            { id = "fortitude", name = "Стойкость", color = "A330C9" },
            { id = "reflex", name = "Сноровка", color = "FF7D0A" },
            { id = "will", name = "Воля", color = "8787ED" },
        }
        
        for i, stat in ipairs(stats) do
            local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
            btn:SetSize(65, 24)
            btn:SetPoint("TOPLEFT", 15 + (i-1) * 70, -72)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("CENTER")
            txt:SetText("|cFF" .. stat.color .. stat.name .. "|r")
            
            btn.statId = stat.id
            btn:SetScript("OnClick", function(self)
                selectedStat = stat.id
                for _, b in ipairs(statButtons) do
                    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
                self:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
            end)
            btn:SetScript("OnEnter", function(self) 
                if selectedStat ~= stat.id then
                    self:SetBackdropColor(0.2, 0.2, 0.2, 1) 
                end
            end)
            btn:SetScript("OnLeave", function(self) 
                if selectedStat ~= stat.id then
                    self:SetBackdropColor(0.15, 0.15, 0.15, 1) 
                end
            end)
            
            table.insert(statButtons, btn)
        end
        
        -- Выбираем первый по умолчанию
        selectedStat = "fortitude"
        statButtons[1]:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
    else
        -- Для Игрока: выбор урон/исцеление
        local typeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLabel:SetPoint("TOPLEFT", 15, -55)
        typeLabel:SetText("Снизить:")
        
        local types = {
            { id = "damage", name = "Урон", color = "FF6666" },
            { id = "healing", name = "Исцеление", color = "66FF66" },
        }
        
        for i, t in ipairs(types) do
            local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
            btn:SetSize(95, 24)
            btn:SetPoint("TOPLEFT", 15 + (i-1) * 105, -72)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("CENTER")
            txt:SetText("|cFF" .. t.color .. t.name .. "|r")
            
            btn.typeId = t.id
            btn:SetScript("OnClick", function(self)
                selectedStat = t.id
                for _, b in ipairs(statButtons) do
                    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
                self:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
            end)
            
            table.insert(statButtons, btn)
        end
        
        selectedStat = "damage"
        statButtons[1]:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
    end
    
    -- Поле "Значение"
    local valueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLabel:SetPoint("TOPLEFT", 15, isNPC and -105 or -105)
    valueLabel:SetText("Штраф (-N):")
    
    local valueInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    valueInput:SetSize(60, 22)
    valueInput:SetPoint("TOPRIGHT", -15, isNPC and -102 or -102)
    valueInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    valueInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    valueInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    valueInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    valueInput:SetTextColor(1, 1, 1)
    valueInput:SetJustifyH("CENTER")
    valueInput:SetAutoFocus(false)
    valueInput:SetNumeric(true)
    valueInput:SetText("2")
    valueInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Поле "Раунды"
    local durationLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPLEFT", 15, isNPC and -132 or -132)
    durationLabel:SetText("Раундов:")
    
    local durationInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    durationInput:SetSize(60, 22)
    durationInput:SetPoint("TOPRIGHT", -15, isNPC and -129 or -129)
    durationInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    durationInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    durationInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    durationInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    durationInput:SetTextColor(1, 1, 1)
    durationInput:SetJustifyH("CENTER")
    durationInput:SetAutoFocus(false)
    durationInput:SetNumeric(true)
    durationInput:SetText("2")
    durationInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    durationInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Кнопка "Применить"
    local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    applyBtn:SetSize(90, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 15, 15)
    applyBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    applyBtn:SetBackdropColor(0.5, 0.3, 0.3, 1)
    applyBtn:SetBackdropBorderColor(0.7, 0.4, 0.4, 1)
    
    local applyText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    applyText:SetPoint("CENTER")
    applyText:SetText("Применить")
    
    applyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.4, 0.4, 1) end)
    applyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.3, 0.3, 1) end)
    applyBtn:SetScript("OnClick", function()
        local value = tonumber(valueInput:GetText()) or 0
        local duration = tonumber(durationInput:GetText()) or 0
        
        if value <= 0 then
            SBS.Utils:Error("Значение должно быть больше 0")
            return
        end
        if duration <= 0 then
            SBS.Utils:Error("Длительность должна быть больше 0")
            return
        end
        if not selectedStat then
            SBS.Utils:Error("Выберите тип ослабления")
            return
        end
        
        -- Определяем эффект на основе выбора
        local effectId
        if isNPC then
            effectId = "weakness_" .. selectedStat
        else
            effectId = "weakness_" .. selectedStat
        end
        
        SBS.Effects:MasterApply(targetType, targetId, effectId, value, duration)
        f:Hide()
    end)
    
    -- Кнопка "Отмена"
    local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Отмена")
    
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
    
    WeaknessDialog = f
    f:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ УЯЗВИМОСТИ (Vulnerability) - выбор защитного стата
-- ═══════════════════════════════════════════════════════════

local VulnerabilityDialog = nil

function SBS.Dialogs:ShowVulnerabilityDialog(targetType, targetId, targetName)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return
    end
    
    -- Закрываем старый диалог
    if VulnerabilityDialog then
        VulnerabilityDialog:Hide()
    end
    
    -- Создаём диалог
    local f = CreateFrame("Frame", "SBS_VulnerabilityDialog", UIParent, "BackdropTemplate")
    f:SetSize(240, 185)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.5, 0.3, 0.5, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF805080Уязвимость|r")
    
    -- Имя цели
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOP", 0, -32)
    targetText:SetText("Цель: |cFFFFFFFF" .. targetName .. "|r")
    
    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Выбор защитного стата
    local statLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statLabel:SetPoint("TOPLEFT", 15, -55)
    statLabel:SetText("Защитный стат:")
    
    local selectedStat = "fortitude"
    local statButtons = {}
    
    local stats = {
        { id = "fortitude", name = "Стойкость", color = "A330C9" },
        { id = "reflex", name = "Сноровка", color = "FF7D0A" },
        { id = "will", name = "Воля", color = "8787ED" },
    }
    
    for i, stat in ipairs(stats) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(65, 24)
        btn:SetPoint("TOPLEFT", 15 + (i-1) * 70, -72)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER")
        txt:SetText("|cFF" .. stat.color .. stat.name .. "|r")
        
        btn.statId = stat.id
        btn:SetScript("OnClick", function(self)
            selectedStat = stat.id
            for _, b in ipairs(statButtons) do
                b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
            self:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
        end)
        
        table.insert(statButtons, btn)
    end
    
    -- Выбираем первый по умолчанию
    statButtons[1]:SetBackdropBorderColor(0.8, 0.8, 0.2, 1)
    
    -- Поле "Значение"
    local valueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLabel:SetPoint("TOPLEFT", 15, -105)
    valueLabel:SetText("Штраф (-N):")
    
    local valueInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    valueInput:SetSize(60, 22)
    valueInput:SetPoint("TOPRIGHT", -15, -102)
    valueInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    valueInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    valueInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    valueInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    valueInput:SetTextColor(1, 1, 1)
    valueInput:SetJustifyH("CENTER")
    valueInput:SetAutoFocus(false)
    valueInput:SetNumeric(true)
    valueInput:SetText("2")
    valueInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Поле "Раунды"
    local durationLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPLEFT", 15, -132)
    durationLabel:SetText("Раундов:")
    
    local durationInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    durationInput:SetSize(60, 22)
    durationInput:SetPoint("TOPRIGHT", -15, -129)
    durationInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    durationInput:SetBackdropColor(0.15, 0.15, 0.15, 1)
    durationInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    durationInput:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    durationInput:SetTextColor(1, 1, 1)
    durationInput:SetJustifyH("CENTER")
    durationInput:SetAutoFocus(false)
    durationInput:SetNumeric(true)
    durationInput:SetText("2")
    durationInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    durationInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Кнопка "Применить"
    local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    applyBtn:SetSize(90, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 15, 15)
    applyBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    applyBtn:SetBackdropColor(0.4, 0.2, 0.4, 1)
    applyBtn:SetBackdropBorderColor(0.6, 0.3, 0.6, 1)
    
    local applyText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    applyText:SetPoint("CENTER")
    applyText:SetText("Применить")
    
    applyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.5, 1) end)
    applyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.4, 1) end)
    applyBtn:SetScript("OnClick", function()
        local value = tonumber(valueInput:GetText()) or 0
        local duration = tonumber(durationInput:GetText()) or 0
        
        if value <= 0 then
            SBS.Utils:Error("Значение должно быть больше 0")
            return
        end
        if duration <= 0 then
            SBS.Utils:Error("Длительность должна быть больше 0")
            return
        end
        
        local effectId = "vulnerability_" .. selectedStat
        SBS.Effects:MasterApply(targetType, targetId, effectId, value, duration)
        f:Hide()
    end)
    
    -- Кнопка "Отмена"
    local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    cancelBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Отмена")
    
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
    
    VulnerabilityDialog = f
    f:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ОСЛАБЛЕНИЯ NPC ИГРОКОМ (выбор защитного стата)
-- ═══════════════════════════════════════════════════════════

local PlayerWeakenDialog = nil

function SBS.Dialogs:ShowPlayerWeakenNPCDialog(npcGuid, npcName)
    -- Закрываем старый диалог
    if PlayerWeakenDialog then
        PlayerWeakenDialog:Hide()
    end
    
    -- Проверяем энергию
    local currentEnergy = SBS.Stats:GetEnergy()
    if currentEnergy < 1 then
        SBS.Utils:Error("Недостаточно энергии!")
        return
    end
    
    -- Проверяем ход (если пошаговый бой)
    if SBS.TurnSystem and SBS.TurnSystem:IsActive() and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    -- Создаём диалог
    local f = CreateFrame("Frame", "SBS_PlayerWeakenDialog", UIParent, "BackdropTemplate")
    f:SetSize(230, 110)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.6, 0.4, 0.4, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFF996666Ослабить защиту|r")
    
    -- Имя цели
    local targetText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetText:SetPoint("TOP", 0, -28)
    targetText:SetText("Цель: |cFFFFFFFF" .. (npcName or "NPC") .. "|r")
    
    -- Подсказка
    local hintText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintText:SetPoint("TOP", 0, -42)
    hintText:SetText("|cFFAAAAAA-1..3 на 3 раунда, 1 энергия|r")
    
    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Кнопки выбора стата
    local stats = {
        { id = "fortitude", name = "Стойкость", color = "A330C9" },
        { id = "reflex", name = "Сноровка", color = "FF7D0A" },
        { id = "will", name = "Воля", color = "8787ED" },
    }
    
    for i, stat in ipairs(stats) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(65, 26)
        btn:SetPoint("BOTTOM", (i - 2) * 72, 12)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER")
        txt:SetText("|cFF" .. stat.color .. stat.name .. "|r")
        
        btn:SetScript("OnEnter", function(self) 
            self:SetBackdropColor(0.25, 0.25, 0.25, 1) 
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end)
        btn:SetScript("OnLeave", function(self) 
            self:SetBackdropColor(0.15, 0.15, 0.15, 1) 
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end)
        
        btn:SetScript("OnClick", function()
            -- Применяем ослабление
            local effectId = "weakness_" .. stat.id
            local randomValue = math.random(1, 3)
            local duration = 3
            
            SBS.Effects:PlayerApplyWeaken(npcGuid, effectId, randomValue, duration)
            f:Hide()
        end)
    end
    
    PlayerWeakenDialog = f
    f:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ БРОСКА ОСОБОГО ДЕЙСТВИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Dialogs:ShowSpecialActionRollDialog(threshold, stat, description)
    -- Используем названия и цвета из конфига
    local statName = SBS.Config.StatNames[stat] or stat
    local statColor = SBS.Config.StatColors[stat] or "FFFFFF"
    local modifier = SBS.Stats:GetTotal(stat)

    -- Создаем окно
    local f = CreateFrame("Frame", "SBS_SpecialActionRollDialog", UIParent, "BackdropTemplate")
    f:SetSize(400, 250)
    f:SetPoint("CENTER", 0, 100)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.6, 0.3, 0.8, 1)
    f:SetFrameStrata("DIALOG")

    -- Заголовок
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -15)
    f.title:SetText("|cFF9966FFОсобое действие одобрено!|r")

    -- Контейнер для описания
    f.descContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.descContainer:SetPoint("TOPLEFT", 15, -45)
    f.descContainer:SetPoint("TOPRIGHT", -15, -45)
    f.descContainer:SetHeight(90)
    f.descContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.descContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    f.descContainer:SetBackdropBorderColor(0.3, 0.25, 0.4, 1)

    -- ScrollFrame для текста
    f.scrollFrame = CreateFrame("ScrollFrame", nil, f.descContainer, "UIPanelScrollFrameTemplate")
    f.scrollFrame:SetPoint("TOPLEFT", 5, -5)
    f.scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    f.scrollContent = CreateFrame("Frame", nil, f.scrollFrame)
    f.scrollContent:SetSize(330, 1)
    f.scrollFrame:SetScrollChild(f.scrollContent)

    -- Описание действия
    f.desc = f.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.desc:SetPoint("TOPLEFT", 5, 0)
    f.desc:SetWidth(320)
    f.desc:SetWordWrap(true)
    f.desc:SetText(description or "")
    f.desc:SetJustifyH("LEFT")
    f.desc:SetJustifyV("TOP")
    f.desc:SetTextColor(0.9, 0.9, 0.9)

    f.scrollContent:SetHeight(math.max(50, f.desc:GetStringHeight() + 10))

    -- Информация о броске
    f.rollInfo = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.rollInfo:SetPoint("TOP", 0, -150)
    f.rollInfo:SetText(string.format("Бросок |cFF%s%s|r порог %d", statColor, statName, threshold))

    -- Кнопка броска
    f.rollBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.rollBtn:SetSize(180, 36)
    f.rollBtn:SetPoint("BOTTOM", 0, 15)
    f.rollBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    f.rollBtn:SetBackdropColor(0.3, 0.2, 0.5, 1)
    f.rollBtn:SetBackdropBorderColor(0.5, 0.3, 0.7, 1)

    f.rollBtn.text = f.rollBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.rollBtn.text:SetPoint("CENTER")
    f.rollBtn.text:SetText("|cFFFFFFFFБросить кубик!|r")

    f.rollBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.3, 0.6, 1)
    end)
    f.rollBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.5, 1)
    end)
    f.rollBtn:SetScript("OnClick", function()
        f:Hide()
        SBS.Combat:ProcessSpecialActionRoll(threshold, stat, description)
    end)

    f:Show()
    PlaySound(8959, "SFX")
end

-- ═══════════════════════════════════════════════════════════
-- АЛИАСЫ ДЛЯ XML
-- ═══════════════════════════════════════════════════════════

-- Алиасы перенесены в Core/Aliases.lua
