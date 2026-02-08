-- SBS/UI/Effects.lua
-- UI для отображения статус-эффектов

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local GameTooltip = GameTooltip
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer

SBS.UI = SBS.UI or {}
SBS.UI.Effects = {
    PlayerFrames = {},      -- Иконки на игроке (в PlayerHeader)
    TargetNPCFrames = {},   -- Иконки на цели NPC
    TargetPlayerFrames = {}, -- Иконки на цели-игроке
    MAX_ICONS = 8,          -- Макс иконок в ряд
    ICON_SIZE = 32,
    ICON_SPACING = 4,
}

local TEX_PATH = "Interface\\AddOns\\SBS\\texture\\"

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ ИКОНКИ ЭФФЕКТА
-- ═══════════════════════════════════════════════════════════

function SBS.UI.Effects:CreateIcon(parent, index)
    local size = self.ICON_SIZE
    local spacing = self.ICON_SPACING
    
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("LEFT", (index - 1) * (size + spacing), 0)
    
    -- Фон
    frame:SetBackdrop(SBS.Utils.Backdrops.Standard)
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Иконка
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size - 4, size - 4)
    icon:SetPoint("CENTER")
    frame.icon = icon
    
    -- Счётчик раундов (справа внизу)
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", 2, -2)
    countText:SetFont(countText:GetFont(), 11, "OUTLINE")
    countText:SetTextColor(1, 1, 1)
    frame.count = countText

    -- Счётчик стаков (слева вверху)
    local stackText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stackText:SetPoint("TOPLEFT", -2, 2)
    stackText:SetFont(stackText:GetFont(), 11, "OUTLINE")
    stackText:SetTextColor(0.3, 1, 0.3)
    frame.stacks = stackText
    
    -- Тултип
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if self.effectData then
            SBS.UI.Effects:ShowTooltip(self)
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    frame:Hide()
    return frame
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ КОНТЕЙНЕРОВ
-- ═══════════════════════════════════════════════════════════

function SBS.UI.Effects:Init()
    -- Иконки для игрока в главном меню ОТКЛЮЧЕНЫ
    -- (эффекты показываются только в UnitFrames)

    -- Создаём иконки для цели-NPC (контейнер под NPCStats)
    local npcTargetContainer = _G["SBS_MainFrame_TargetFrame_Info_EffectsRow_Icons"]
    if npcTargetContainer then
        for i = 1, self.MAX_ICONS do
            self.TargetNPCFrames[i] = self:CreateIcon(npcTargetContainer, i)
        end
    end
    
    -- Создаём иконки для цели-игрока (контейнер внутри PlayerStats)
    local playerTargetContainer = _G["SBS_MainFrame_TargetFrame_Info_PlayerStats_EffectsRow_Icons"]
    if playerTargetContainer then
        for i = 1, self.MAX_ICONS do
            self.TargetPlayerFrames[i] = self:CreateIcon(playerTargetContainer, i)
        end
    end
    
    -- Регистрируем события
    SBS.Events:Register("EFFECT_APPLIED", function(targetType, targetId, effectId)
        self:UpdateAll()
    end)
    
    SBS.Events:Register("EFFECT_REMOVED", function(targetType, targetId, effectId)
        self:UpdateAll()
    end)
    
    SBS.Events:Register("EFFECTS_CLEARED", function()
        self:UpdateAll()
    end)
    
    SBS.Events:Register("EFFECTS_SYNCED", function()
        self:UpdateAll()
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ ОТОБРАЖЕНИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.UI.Effects:UpdateAll()
    -- UpdatePlayer отключён - эффекты показываются только в UnitFrames
    self:UpdateTarget()
end

function SBS.UI.Effects:UpdatePlayer()
    -- ОТКЛЮЧЕНО - эффекты игрока показываются только в UnitFrames
    -- local myName = UnitName("player")
    -- local effects = SBS.Effects:GetAll("player", myName)
    -- self:UpdateContainer(self.PlayerFrames, effects)
end

function SBS.UI.Effects:UpdateTarget()
    -- Контейнеры для NPC (главный EffectsRow)
    local npcEffectsRow = _G["SBS_MainFrame_TargetFrame_Info_EffectsRow"]
    local npcEffectsIcons = _G["SBS_MainFrame_TargetFrame_Info_EffectsRow_Icons"]

    -- Контейнеры для игроков (внутри PlayerStats)
    local playerEffectsRow = _G["SBS_MainFrame_TargetFrame_Info_PlayerStats_EffectsRow"]
    local playerEffectsIcons = _G["SBS_MainFrame_TargetFrame_Info_PlayerStats_EffectsRow_Icons"]

    -- Ленивая инициализация иконок для NPC
    if #self.TargetNPCFrames == 0 and npcEffectsIcons then
        for i = 1, self.MAX_ICONS do
            self.TargetNPCFrames[i] = self:CreateIcon(npcEffectsIcons, i)
        end
    end

    -- Ленивая инициализация иконок для игроков
    if #self.TargetPlayerFrames == 0 and playerEffectsIcons then
        for i = 1, self.MAX_ICONS do
            self.TargetPlayerFrames[i] = self:CreateIcon(playerEffectsIcons, i)
        end
    end

    -- Если нет цели - скрываем всё
    if not UnitExists("target") then
        self:HideAll(self.TargetNPCFrames)
        self:HideAll(self.TargetPlayerFrames)
        if npcEffectsRow then npcEffectsRow:Hide() end
        if playerEffectsRow then playerEffectsRow:Hide() end
        return
    end

    local guid = UnitGUID("target")
    local name = UnitName("target")
    local isPlayer = UnitIsPlayer("target")

    local effects
    if isPlayer then
        effects = SBS.Effects:GetAll("player", name)
    else
        effects = SBS.Effects:GetAll("npc", guid)
    end

    -- Считаем количество эффектов
    local effectCount = 0
    for _ in pairs(effects) do effectCount = effectCount + 1 end

    if isPlayer then
        -- Для игроков: используем контейнер внутри PlayerStats
        self:HideAll(self.TargetNPCFrames)
        if npcEffectsRow then npcEffectsRow:Hide() end

        if playerEffectsRow then
            if effectCount > 0 then
                playerEffectsRow:Show()
                if playerEffectsIcons then playerEffectsIcons:Show() end
            else
                playerEffectsRow:Hide()
            end
        end
        self:UpdateContainer(self.TargetPlayerFrames, effects)
    else
        -- Для NPC: используем главный контейнер EffectsRow
        self:HideAll(self.TargetPlayerFrames)
        if playerEffectsRow then playerEffectsRow:Hide() end

        if npcEffectsRow then
            if effectCount > 0 then
                npcEffectsRow:Show()
                if npcEffectsIcons then npcEffectsIcons:Show() end
            else
                npcEffectsRow:Hide()
            end
        end
        self:UpdateContainer(self.TargetNPCFrames, effects)
    end
end

function SBS.UI.Effects:UpdateContainer(frames, effects)
    if not frames then return end
    -- Скрываем все иконки
    self:HideAll(frames)

    -- Отображаем активные эффекты
    local index = 1
    for effectId, effectData in pairs(effects) do
        if index > self.MAX_ICONS then break end

        local frame = frames[index]
        if frame then
            local def = SBS.Effects.Definitions[effectId]
            if def then
                self:SetupIcon(frame, def, effectData)
                frame:Show()
                index = index + 1
            end
        end
    end
end

function SBS.UI.Effects:SetupIcon(frame, def, effectData)
    -- Иконка
    frame.icon:SetTexture(def.icon)
    
    -- Цвет рамки по типу эффекта
    local borderColor
    if def.type == "buff" then
        borderColor = {0.2, 0.8, 0.2, 1}  -- Зелёный
    elseif def.type == "debuff" then
        borderColor = {0.8, 0.2, 0.2, 1}  -- Красный
    elseif def.type == "dot" then
        borderColor = {0.9, 0.5, 0.1, 1}  -- Оранжевый
    else
        borderColor = {0.5, 0.5, 0.5, 1}  -- Серый
    end
    frame:SetBackdropBorderColor(unpack(borderColor))
    
    -- Счётчик раундов
    frame.count:SetText(effectData.remainingRounds)
    
    -- Счётчик стаков (показываем только если > 1)
    local stacks = effectData.stacks or 1
    if stacks > 1 then
        frame.stacks:SetText("x" .. stacks)
        frame.stacks:Show()
    else
        frame.stacks:SetText("")
        frame.stacks:Hide()
    end
    
    -- Данные для тултипа
    frame.effectData = effectData
    frame.effectDef = def
end

function SBS.UI.Effects:HideAll(frames)
    if not frames then return end
    for _, frame in ipairs(frames) do
        frame:Hide()
        frame.effectData = nil
        frame.effectDef = nil
    end
end

-- ═══════════════════════════════════════════════════════════
-- ТУЛТИП
-- ═══════════════════════════════════════════════════════════

function SBS.UI.Effects:ShowTooltip(frame)
    local def = frame.effectDef
    local data = frame.effectData
    
    if not def or not data then return end
    
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    
    -- Название с цветом
    local colorHex = SBS.Effects:GetColorHex(def.color)
    local nameText = "|cFF" .. colorHex .. def.name .. "|r"
    if data.stacks and data.stacks > 1 then
        nameText = nameText .. " |cFF00FF00(x" .. data.stacks .. ")|r"
    end
    GameTooltip:AddLine(nameText)
    
    -- Тип
    local typeText = ""
    if def.type == "buff" then
        typeText = "|cFF00FF00Бафф|r"
    elseif def.type == "debuff" then
        typeText = "|cFFFF0000Дебафф|r"
    elseif def.type == "dot" then
        typeText = "|cFFFF8800Периодический урон|r"
    end
    GameTooltip:AddLine(typeText, 1, 1, 1)
    
    -- Описание
    GameTooltip:AddLine(def.description, 0.8, 0.8, 0.8, true)
    
    -- Значение
    if data.value and data.value > 0 then
        if def.type == "dot" or def.isHoT then
            local actionText = def.isHoT and "Лечит" or "Урон"
            GameTooltip:AddLine(actionText .. ": |cFFFFFFFF" .. data.value .. "|r за раунд", 1, 0.82, 0)
        elseif def.statMod then
            local modText = def.modType == "increase" and "+" or "-"
            GameTooltip:AddLine("Модификатор: |cFFFFFFFF" .. modText .. data.value .. "|r", 1, 0.82, 0)
        end
    end
    
    -- Длительность
    GameTooltip:AddLine("Осталось: |cFFFFFFFF" .. (data.remainingRounds or 0) .. "|r раунд(ов)", 0.7, 0.7, 0.7)
    
    -- Кто наложил
    if data.casters and #data.casters > 0 then
        local castersText
        if #data.casters == 1 then
            castersText = "Наложил: |cFFAAAAAA" .. data.casters[1] .. "|r"
        else
            castersText = "Наложили: |cFFAAAAAA" .. table.concat(data.casters, ", ") .. "|r"
        end
        GameTooltip:AddLine(castersText, 0.5, 0.5, 0.5)
    elseif data.caster then
        GameTooltip:AddLine("Наложил: |cFFAAAAAA" .. data.caster .. "|r", 0.5, 0.5, 0.5)
    end
    
    GameTooltip:Show()
end

-- ═══════════════════════════════════════════════════════════
-- РЕГИСТРАЦИЯ В ОСНОВНОЙ ИНИЦИАЛИЗАЦИИ
-- ═══════════════════════════════════════════════════════════

-- Вызывается из InitMainFrameUI
function SBS.UI:InitEffectsUI()
    SBS.UI.Effects:Init()
end
