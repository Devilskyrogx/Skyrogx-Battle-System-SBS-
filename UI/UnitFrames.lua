-- SBS/UI/UnitFrames.lua
-- Компактные Unit Frames для игрока и цели

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local tonumber = tonumber
local tostring = tostring
local string_format = string.format
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitIsGroupLeader = UnitIsGroupLeader
local SetPortraitTexture = SetPortraitTexture
local MouseIsOver = MouseIsOver
local GameTooltip = GameTooltip
local C_Timer = C_Timer
local IsInGroup = IsInGroup

SBS.UI = SBS.UI or {}
SBS.UI.UnitFrames = {
    PlayerFrame = nil,
    TargetFrame = nil,
    EffectFrames = {
        Player = {},
        Target = {},
    },
    MAX_EFFECT_ICONS = 8,
    EFFECT_ICON_SIZE = 22,
}

local UF = SBS.UI.UnitFrames

-- ═══════════════════════════════════════════════════════════
-- КОНСТАНТЫ
-- ═══════════════════════════════════════════════════════════

local TEX_PATH = "Interface\\AddOns\\SBS\\texture\\"
local BAR_TEXTURE = "Interface\\AddOns\\SBS\\texture\\bar_texture"

local COLORS = {
    -- Фон и рамки
    bg = { 0.08, 0.08, 0.08, 0.95 },
    border = { 0.2, 0.2, 0.2, 1 },
    borderHover = { 0.4, 0.4, 0.4, 1 },

    -- HP бар
    hpHigh = { 0.07, 0.56, 0.27 },    -- Зелёный (>50%)
    hpMid = { 0.8, 0.6, 0.1 },        -- Жёлтый (25-50%)
    hpLow = { 0.7, 0.15, 0.1 },       -- Красный (<25%)
    hpNPC = { 0.55, 0, 0 },           -- Красный для NPC

    -- Щит
    shield = { 0.4, 0.78, 1.0, 0.7 },

    -- Энергия
    energy = { 0.13, 0.5, 0.69 },

    -- Эффекты
    buffBorder = { 0.18, 0.54, 0.18, 1 },
    debuffBorder = { 0.54, 0.18, 0.18, 1 },
    woundBorder = { 0.8, 0, 0, 1 },

    -- Пороги защиты NPC
    fortitude = { 0.64, 0.19, 0.79 },  -- #a330c9
    reflex = { 1.0, 0.49, 0.04 },      -- #ff7d0a
    will = { 0.53, 0.53, 0.93 },       -- #8787ed

    -- Кнопки управления
    btnActive = { 0.2, 0.8, 0.2, 1 },
    btnInactive = { 0.25, 0.25, 0.25, 1 },
    btnLocked = { 0.8, 0.8, 0.2, 1 },
}

local BACKDROP = SBS.Utils.Backdrops.Standard

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function UF:Init()
    -- Создаём фреймы
    self:CreatePlayerFrame()
    self:CreateTargetFrame()

    -- Регистрируем события
    self:RegisterEvents()

    -- Загружаем позиции
    self:LoadPosition("player")
    self:LoadPosition("target")

    -- Применяем масштаб
    self:ApplyScale("player")
    self:ApplyScale("target")

    -- Показываем фрейм игрока если включён
    if SBS.db.profile.unitFrames.player.enabled then
        self.PlayerFrame:Show()
        self:UpdatePlayerFrame()
    end

    -- Обновляем кнопки управления
    self:UpdateControlButtons()
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER FRAME
-- ═══════════════════════════════════════════════════════════

function UF:CreatePlayerFrame()
    local frame = CreateFrame("Frame", "SBS_PlayerUnitFrame", UIParent, "BackdropTemplate")
    frame:SetSize(240, 100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(COLORS.bg))
    frame:SetBackdropBorderColor(unpack(COLORS.border))

    -- Перетаскивание
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not SBS.db.profile.unitFrames.player.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        UF:SavePosition("player")
    end)

    -- Создаём компоненты
    self:CreatePlayerPortrait(frame)
    self:CreatePlayerInfo(frame)
    self:CreatePlayerBars(frame)
    self:CreatePlayerEffectsRow(frame)

    -- Показывать кнопки +/- только при наведении (для лидера/соло)
    frame:HookScript("OnEnter", function(self)
        if not IsInGroup() or UnitIsGroupLeader("player") then
            if self.bars and self.bars.hpBar and self.bars.energyBar then
                -- Отменяем таймер скрытия если он есть
                if self.bars.hideTimer then
                    self.bars.hideTimer:Cancel()
                    self.bars.hideTimer = nil
                end
                self.bars.hpBar.minusBtn:Show()
                self.bars.hpBar.plusBtn:Show()
                self.bars.energyBar.minusBtn:Show()
                self.bars.energyBar.plusBtn:Show()
            end
        end
    end)
    frame:HookScript("OnLeave", function(self)
        if self.bars and self.bars.hpBar and self.bars.energyBar then
            -- Прячем кнопки с задержкой
            UF:HideModifyButtonsDelayed(self.bars)
        end
    end)

    self.PlayerFrame = frame
    return frame
end

function UF:CreatePlayerPortrait(parent)
    -- Контейнер портрета
    local container = CreateFrame("Frame", "$parent_Portrait", parent, "BackdropTemplate")
    container:SetSize(48, 48)
    container:SetPoint("TOPLEFT", 8, -8)

    container:SetBackdrop(BACKDROP)
    container:SetBackdropColor(0.05, 0.05, 0.05, 1)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Текстура портрета
    local texture = container:CreateTexture("$parent_Texture", "ARTWORK")
    texture:SetSize(44, 44)
    texture:SetPoint("CENTER")
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Обрезка для круглого вида
    container.texture = texture

    -- Маска для круглого портрета
    local mask = container:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)

    -- Бейдж уровня
    local levelBadge = CreateFrame("Frame", "$parent_LevelBadge", container, "BackdropTemplate")
    levelBadge:SetSize(24, 16)
    levelBadge:SetPoint("BOTTOM", 0, -6)
    levelBadge:SetBackdrop(BACKDROP)
    levelBadge:SetBackdropColor(0.15, 0.15, 0.15, 1)
    levelBadge:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local levelText = levelBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("CENTER")
    levelText:SetTextColor(1, 0.82, 0)
    levelBadge.text = levelText

    parent.portrait = container
    parent.levelBadge = levelBadge
end

function UF:CreatePlayerInfo(parent)
    -- Контейнер для имени и иконок
    local info = CreateFrame("Frame", "$parent_Info", parent)
    info:SetSize(170, 20)
    info:SetPoint("TOPLEFT", parent.portrait, "TOPRIGHT", 8, -2)

    -- Имя игрока
    local name = info:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("LEFT", 0, 0)
    name:SetTextColor(1, 0.82, 0)
    name:SetJustifyH("LEFT")
    name:SetWidth(100)
    info.name = name

    -- Иконка роли
    local roleIcon = info:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(16, 16)
    roleIcon:SetPoint("LEFT", name, "RIGHT", 4, 0)
    info.roleIcon = roleIcon

    -- Кнопка информации (показывает статы)
    local infoBtn = CreateFrame("Button", "$parent_InfoBtn", info, "BackdropTemplate")
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("RIGHT", 0, 0)
    infoBtn:SetBackdrop(BACKDROP)
    infoBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    infoBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local infoIcon = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoIcon:SetPoint("CENTER")
    infoIcon:SetText("i")
    infoIcon:SetTextColor(0.7, 0.7, 0.7)

    infoBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        infoIcon:SetTextColor(1, 1, 1)
        UF:ShowPlayerStatsTooltip(self)
    end)
    infoBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        infoIcon:SetTextColor(0.7, 0.7, 0.7)
        GameTooltip:Hide()
    end)

    info.infoBtn = infoBtn
    parent.info = info
end

function UF:CreatePlayerBars(parent)
    -- Контейнер для баров
    local barsContainer = CreateFrame("Frame", "$parent_Bars", parent)
    barsContainer:SetSize(170, 36)
    barsContainer:SetPoint("TOPLEFT", parent.portrait, "TOPRIGHT", 8, -24)

    -- HP бар
    local hpBar = CreateFrame("StatusBar", "$parent_HPBar", barsContainer, "BackdropTemplate")
    hpBar:SetSize(170, 18)
    hpBar:SetPoint("TOP")
    hpBar:SetStatusBarTexture(BAR_TEXTURE)
    hpBar:SetStatusBarColor(unpack(COLORS.hpHigh))
    hpBar:SetBackdrop(BACKDROP)
    hpBar:SetBackdropColor(0.04, 0.04, 0.04, 1)
    hpBar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- Щит (overlay)
    local shieldBar = CreateFrame("StatusBar", "$parent_ShieldBar", hpBar)
    shieldBar:SetSize(166, 14)
    shieldBar:SetPoint("LEFT", 2, 0)
    shieldBar:SetStatusBarTexture(BAR_TEXTURE)
    shieldBar:SetStatusBarColor(unpack(COLORS.shield))
    shieldBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    shieldBar:Hide()
    hpBar.shieldBar = shieldBar

    -- HP текст
    local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpText:SetPoint("CENTER")
    hpText:SetTextColor(1, 1, 1)
    hpText:SetFont(SBS.Config.FONT, 10, "OUTLINE")
    hpBar.text = hpText

    -- Текст щита (справа)
    local shieldText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shieldText:SetPoint("RIGHT", -4, 0)
    shieldText:SetTextColor(0.4, 0.78, 1)
    shieldText:SetFont(SBS.Config.FONT, 9, "OUTLINE")
    shieldText:Hide()
    hpBar.shieldText = shieldText

    -- HP кнопки +/-
    local hpMinusBtn = CreateFrame("Button", "$parent_HPMinusBtn", hpBar, "BackdropTemplate")
    hpMinusBtn:SetSize(16, 16)
    hpMinusBtn:SetPoint("LEFT", 2, 0)
    hpMinusBtn:SetBackdrop(BACKDROP)
    hpMinusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    hpMinusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    hpMinusBtn:SetFrameLevel(hpBar:GetFrameLevel() + 2)
    hpMinusBtn:Hide()

    local hpMinusText = hpMinusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpMinusText:SetPoint("CENTER")
    hpMinusText:SetText("-")
    hpMinusText:SetTextColor(0.8, 0.3, 0.3)

    hpMinusBtn:SetScript("OnClick", function()
        if SBS.Stats and SBS.Stats.ModifyHP then
            SBS.Stats:ModifyHP(-1)
        end
    end)
    hpMinusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        -- Отменяем скрытие кнопок
        if barsContainer.hideTimer then
            barsContainer.hideTimer:Cancel()
            barsContainer.hideTimer = nil
        end
    end)
    hpMinusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        -- Прячем кнопки с задержкой
        UF:HideModifyButtonsDelayed(barsContainer)
    end)
    hpBar.minusBtn = hpMinusBtn

    local hpPlusBtn = CreateFrame("Button", "$parent_HPPlusBtn", hpBar, "BackdropTemplate")
    hpPlusBtn:SetSize(16, 16)
    hpPlusBtn:SetPoint("RIGHT", -2, 0)
    hpPlusBtn:SetBackdrop(BACKDROP)
    hpPlusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    hpPlusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    hpPlusBtn:SetFrameLevel(hpBar:GetFrameLevel() + 2)
    hpPlusBtn:Hide()

    local hpPlusText = hpPlusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpPlusText:SetPoint("CENTER")
    hpPlusText:SetText("+")
    hpPlusText:SetTextColor(0.3, 0.8, 0.3)

    hpPlusBtn:SetScript("OnClick", function()
        if SBS.Stats and SBS.Stats.ModifyHP then
            SBS.Stats:ModifyHP(1)
        end
    end)
    hpPlusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        -- Отменяем скрытие кнопок
        if barsContainer.hideTimer then
            barsContainer.hideTimer:Cancel()
            barsContainer.hideTimer = nil
        end
    end)
    hpPlusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        -- Прячем кнопки с задержкой
        UF:HideModifyButtonsDelayed(barsContainer)
    end)
    hpBar.plusBtn = hpPlusBtn

    barsContainer.hpBar = hpBar

    -- Энергия бар
    local energyBar = CreateFrame("StatusBar", "$parent_EnergyBar", barsContainer, "BackdropTemplate")
    energyBar:SetSize(170, 14)
    energyBar:SetPoint("TOP", hpBar, "BOTTOM", 0, -2)
    energyBar:SetStatusBarTexture(BAR_TEXTURE)
    energyBar:SetStatusBarColor(unpack(COLORS.energy))
    energyBar:SetBackdrop(BACKDROP)
    energyBar:SetBackdropColor(0.04, 0.04, 0.04, 1)
    energyBar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- Энергия текст
    local energyText = energyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyText:SetPoint("CENTER")
    energyText:SetTextColor(0.9, 0.9, 1)
    energyText:SetFont(SBS.Config.FONT, 9, "OUTLINE")
    energyBar.text = energyText

    -- Energy кнопки +/-
    local energyMinusBtn = CreateFrame("Button", "$parent_EnergyMinusBtn", energyBar, "BackdropTemplate")
    energyMinusBtn:SetSize(14, 12)
    energyMinusBtn:SetPoint("LEFT", 2, 0)
    energyMinusBtn:SetBackdrop(BACKDROP)
    energyMinusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    energyMinusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    energyMinusBtn:SetFrameLevel(energyBar:GetFrameLevel() + 2)
    energyMinusBtn:Hide()

    local energyMinusText = energyMinusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyMinusText:SetPoint("CENTER")
    energyMinusText:SetText("-")
    energyMinusText:SetTextColor(0.8, 0.3, 0.3)

    energyMinusBtn:SetScript("OnClick", function()
        if SBS.Stats and SBS.Stats.ModifyEnergy then
            SBS.Stats:ModifyEnergy(-1)
        end
    end)
    energyMinusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        -- Отменяем скрытие кнопок
        if barsContainer.hideTimer then
            barsContainer.hideTimer:Cancel()
            barsContainer.hideTimer = nil
        end
    end)
    energyMinusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        -- Прячем кнопки с задержкой
        UF:HideModifyButtonsDelayed(barsContainer)
    end)
    energyBar.minusBtn = energyMinusBtn

    local energyPlusBtn = CreateFrame("Button", "$parent_EnergyPlusBtn", energyBar, "BackdropTemplate")
    energyPlusBtn:SetSize(14, 12)
    energyPlusBtn:SetPoint("RIGHT", -2, 0)
    energyPlusBtn:SetBackdrop(BACKDROP)
    energyPlusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    energyPlusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    energyPlusBtn:SetFrameLevel(energyBar:GetFrameLevel() + 2)
    energyPlusBtn:Hide()

    local energyPlusText = energyPlusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyPlusText:SetPoint("CENTER")
    energyPlusText:SetText("+")
    energyPlusText:SetTextColor(0.3, 0.8, 0.3)

    energyPlusBtn:SetScript("OnClick", function()
        if SBS.Stats and SBS.Stats.ModifyEnergy then
            SBS.Stats:ModifyEnergy(1)
        end
    end)
    energyPlusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        -- Отменяем скрытие кнопок
        if barsContainer.hideTimer then
            barsContainer.hideTimer:Cancel()
            barsContainer.hideTimer = nil
        end
    end)
    energyPlusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        -- Прячем кнопки с задержкой
        UF:HideModifyButtonsDelayed(barsContainer)
    end)
    energyBar.plusBtn = energyPlusBtn

    barsContainer.energyBar = energyBar
    parent.bars = barsContainer
end

function UF:CreatePlayerEffectsRow(parent)
    local row = CreateFrame("Frame", "$parent_EffectsRow", parent)
    row:SetSize(220, 24)
    row:SetPoint("BOTTOMLEFT", 8, 8)

    for i = 1, self.MAX_EFFECT_ICONS do
        self.EffectFrames.Player[i] = self:CreateEffectIcon(row, i)
    end

    parent.effectsRow = row
end

-- ═══════════════════════════════════════════════════════════
-- TARGET FRAME
-- ═══════════════════════════════════════════════════════════

function UF:CreateTargetFrame()
    local frame = CreateFrame("Frame", "SBS_TargetUnitFrame", UIParent, "BackdropTemplate")
    frame:SetSize(220, 115)  -- Увеличен размер для энергия бара
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(COLORS.bg))
    frame:SetBackdropBorderColor(unpack(COLORS.border))

    -- Перетаскивание
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not SBS.db.profile.unitFrames.target.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        UF:SavePosition("target")
    end)

    -- Создаём компоненты
    self:CreateTargetPortrait(frame)
    self:CreateTargetInfo(frame)
    self:CreateTargetHPBar(frame)
    self:CreateTargetEnergyBar(frame)  -- Новый энергия бар
    self:CreateTargetDefenseRow(frame)
    self:CreateTargetEffectsRow(frame)
    self:CreateTargetNoDataText(frame)  -- Текст "Нет данных"

    -- Показывать кнопки +/- только при наведении (только для мастера)
    frame:HookScript("OnEnter", function(self)
        if SBS.Sync and SBS.Sync:IsMaster() then
            UF:ShowTargetModifyButtons()
        end
    end)
    frame:HookScript("OnLeave", function(self)
        UF:HideTargetModifyButtonsDelayed()
    end)

    self.TargetFrame = frame
    return frame
end

function UF:CreateTargetPortrait(parent)
    local container = CreateFrame("Frame", "$parent_Portrait", parent, "BackdropTemplate")
    container:SetSize(40, 40)
    container:SetPoint("TOPLEFT", 8, -8)

    container:SetBackdrop(BACKDROP)
    container:SetBackdropColor(0.05, 0.05, 0.05, 1)
    container:SetBackdropBorderColor(0.5, 0.2, 0.2, 1)

    -- Текстура портрета
    local texture = container:CreateTexture("$parent_Texture", "ARTWORK")
    texture:SetSize(36, 36)
    texture:SetPoint("CENTER")
    container.texture = texture

    -- Череп (для NPC)
    local skull = container:CreateTexture("$parent_Skull", "OVERLAY")
    skull:SetSize(14, 14)
    skull:SetPoint("BOTTOMRIGHT", 4, -4)
    skull:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
    skull:SetVertexColor(0.8, 0.2, 0.2)
    container.skull = skull

    parent.portrait = container
end

function UF:CreateTargetInfo(parent)
    local info = CreateFrame("Frame", "$parent_Info", parent)
    info:SetSize(160, 20)
    info:SetPoint("TOPLEFT", parent.portrait, "TOPRIGHT", 8, 0)

    -- Имя
    local name = info:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("LEFT", 0, 0)
    name:SetTextColor(1, 0.4, 0.4)
    name:SetJustifyH("LEFT")
    name:SetWidth(135)
    info.name = name

    -- Кнопка информации (показывает статы игрока)
    local infoBtn = CreateFrame("Button", "$parent_InfoBtn", info, "BackdropTemplate")
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("RIGHT", 0, 0)
    infoBtn:SetBackdrop(BACKDROP)
    infoBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    infoBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local infoIcon = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoIcon:SetPoint("CENTER")
    infoIcon:SetText("i")
    infoIcon:SetTextColor(0.7, 0.7, 0.7)

    infoBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        infoIcon:SetTextColor(1, 1, 1)
        UF:ShowTargetPlayerStatsTooltip(self)
    end)
    infoBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        infoIcon:SetTextColor(0.7, 0.7, 0.7)
        GameTooltip:Hide()
    end)
    infoBtn:Hide()  -- Скрыта по умолчанию, показывается только для игроков

    info.infoBtn = infoBtn
    parent.info = info
end

function UF:CreateTargetHPBar(parent)
    local hpBar = CreateFrame("StatusBar", "$parent_HPBar", parent, "BackdropTemplate")
    hpBar:SetSize(160, 16)
    hpBar:SetPoint("TOPLEFT", parent.portrait, "TOPRIGHT", 8, -22)
    hpBar:SetStatusBarTexture(BAR_TEXTURE)
    hpBar:SetStatusBarColor(unpack(COLORS.hpNPC))
    hpBar:SetBackdrop(BACKDROP)
    hpBar:SetBackdropColor(0.04, 0.04, 0.04, 1)
    hpBar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpText:SetPoint("CENTER")
    hpText:SetTextColor(1, 1, 1)
    hpText:SetFont(SBS.Config.FONT, 10, "OUTLINE")
    hpBar.text = hpText

    -- HP кнопки +/- (только для мастера)
    local hpMinusBtn = CreateFrame("Button", "$parent_HPMinusBtn", hpBar, "BackdropTemplate")
    hpMinusBtn:SetSize(16, 16)
    hpMinusBtn:SetPoint("LEFT", 2, 0)
    hpMinusBtn:SetBackdrop(BACKDROP)
    hpMinusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    hpMinusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    hpMinusBtn:SetFrameLevel(hpBar:GetFrameLevel() + 2)
    hpMinusBtn:Hide()

    local hpMinusText = hpMinusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpMinusText:SetPoint("CENTER")
    hpMinusText:SetText("-")
    hpMinusText:SetTextColor(0.8, 0.3, 0.3)

    hpMinusBtn:SetScript("OnClick", function()
        UF:ModifyTargetHP(-1)
    end)
    hpMinusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        if UF.TargetFrame and UF.TargetFrame.hideTimer then
            UF.TargetFrame.hideTimer:Cancel()
            UF.TargetFrame.hideTimer = nil
        end
    end)
    hpMinusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        UF:HideTargetModifyButtonsDelayed()
    end)
    hpBar.minusBtn = hpMinusBtn

    local hpPlusBtn = CreateFrame("Button", "$parent_HPPlusBtn", hpBar, "BackdropTemplate")
    hpPlusBtn:SetSize(16, 16)
    hpPlusBtn:SetPoint("RIGHT", -2, 0)
    hpPlusBtn:SetBackdrop(BACKDROP)
    hpPlusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    hpPlusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    hpPlusBtn:SetFrameLevel(hpBar:GetFrameLevel() + 2)
    hpPlusBtn:Hide()

    local hpPlusText = hpPlusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpPlusText:SetPoint("CENTER")
    hpPlusText:SetText("+")
    hpPlusText:SetTextColor(0.3, 0.8, 0.3)

    hpPlusBtn:SetScript("OnClick", function()
        UF:ModifyTargetHP(1)
    end)
    hpPlusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        if UF.TargetFrame and UF.TargetFrame.hideTimer then
            UF.TargetFrame.hideTimer:Cancel()
            UF.TargetFrame.hideTimer = nil
        end
    end)
    hpPlusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        UF:HideTargetModifyButtonsDelayed()
    end)
    hpBar.plusBtn = hpPlusBtn

    parent.hpBar = hpBar
end

function UF:CreateTargetEnergyBar(parent)
    local energyBar = CreateFrame("StatusBar", "$parent_EnergyBar", parent, "BackdropTemplate")
    energyBar:SetSize(160, 12)
    energyBar:SetPoint("TOPLEFT", parent.hpBar, "BOTTOMLEFT", 0, -2)
    energyBar:SetStatusBarTexture(BAR_TEXTURE)
    energyBar:SetStatusBarColor(unpack(COLORS.energy))
    energyBar:SetBackdrop(BACKDROP)
    energyBar:SetBackdropColor(0.04, 0.04, 0.04, 1)
    energyBar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local energyText = energyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyText:SetPoint("CENTER")
    energyText:SetTextColor(0.9, 0.9, 1)
    energyText:SetFont(SBS.Config.FONT, 9, "OUTLINE")
    energyBar.text = energyText

    -- Energy кнопки +/- (только для мастера)
    local energyMinusBtn = CreateFrame("Button", "$parent_EnergyMinusBtn", energyBar, "BackdropTemplate")
    energyMinusBtn:SetSize(14, 12)
    energyMinusBtn:SetPoint("LEFT", 2, 0)
    energyMinusBtn:SetBackdrop(BACKDROP)
    energyMinusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    energyMinusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    energyMinusBtn:SetFrameLevel(energyBar:GetFrameLevel() + 2)
    energyMinusBtn:Hide()

    local energyMinusText = energyMinusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyMinusText:SetPoint("CENTER")
    energyMinusText:SetText("-")
    energyMinusText:SetTextColor(0.8, 0.3, 0.3)

    energyMinusBtn:SetScript("OnClick", function()
        UF:ModifyTargetEnergy(-1)
    end)
    energyMinusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        if UF.TargetFrame and UF.TargetFrame.hideTimer then
            UF.TargetFrame.hideTimer:Cancel()
            UF.TargetFrame.hideTimer = nil
        end
    end)
    energyMinusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        UF:HideTargetModifyButtonsDelayed()
    end)
    energyBar.minusBtn = energyMinusBtn

    local energyPlusBtn = CreateFrame("Button", "$parent_EnergyPlusBtn", energyBar, "BackdropTemplate")
    energyPlusBtn:SetSize(14, 12)
    energyPlusBtn:SetPoint("RIGHT", -2, 0)
    energyPlusBtn:SetBackdrop(BACKDROP)
    energyPlusBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    energyPlusBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    energyPlusBtn:SetFrameLevel(energyBar:GetFrameLevel() + 2)
    energyPlusBtn:Hide()

    local energyPlusText = energyPlusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    energyPlusText:SetPoint("CENTER")
    energyPlusText:SetText("+")
    energyPlusText:SetTextColor(0.3, 0.8, 0.3)

    energyPlusBtn:SetScript("OnClick", function()
        UF:ModifyTargetEnergy(1)
    end)
    energyPlusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        if UF.TargetFrame and UF.TargetFrame.hideTimer then
            UF.TargetFrame.hideTimer:Cancel()
            UF.TargetFrame.hideTimer = nil
        end
    end)
    energyPlusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        UF:HideTargetModifyButtonsDelayed()
    end)
    energyBar.plusBtn = energyPlusBtn

    parent.energyBar = energyBar
end

function UF:CreateTargetNoDataText(parent)
    local noData = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noData:SetPoint("CENTER", 10, 0)
    noData:SetText("|cFF888888Нет данных|r")
    noData:Hide()
    parent.noDataText = noData
end

function UF:CreateTargetDefenseRow(parent)
    local row = CreateFrame("Frame", "$parent_DefenseRow", parent)
    row:SetSize(200, 18)
    row:SetPoint("TOPLEFT", parent.hpBar, "BOTTOMLEFT", 0, -4)

    -- Стойкость
    local fort = self:CreateDefenseStat(row, "fort", "Стойкость", COLORS.fortitude, 0)
    -- Сноровка
    local reflex = self:CreateDefenseStat(row, "reflex", "Сноровка", COLORS.reflex, 55)
    -- Воля
    local will = self:CreateDefenseStat(row, "will", "Воля", COLORS.will, 110)

    row.fortitude = fort
    row.reflex = reflex
    row.will = will

    parent.defenseRow = row
end

function UF:CreateDefenseStat(parent, statType, statName, color, xOffset)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(50, 18)
    container:SetPoint("LEFT", xOffset, 0)

    -- Иконка
    local icon = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTextColor(unpack(color))

    if statType == "fort" then
        icon:SetText("Сто:")
    elseif statType == "reflex" then
        icon:SetText("Сно:")
    else
        icon:SetText("Вол:")
    end

    -- Значение
    local value = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    value:SetPoint("LEFT", icon, "RIGHT", 2, 0)
    value:SetTextColor(unpack(color))
    container.value = value

    -- Тултип
    container:EnableMouse(true)
    container:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(statName, unpack(color))
        if statType == "fort" then
            GameTooltip:AddLine("Защита от физических атак (Сила)", 0.7, 0.7, 0.7)
        elseif statType == "reflex" then
            GameTooltip:AddLine("Защита от точных атак (Ловкость)", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Защита от магических атак (Интеллект)", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    container:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return container
end

function UF:CreateTargetEffectsRow(parent)
    local row = CreateFrame("Frame", "$parent_EffectsRow", parent)
    row:SetSize(200, 24)
    row:SetPoint("BOTTOMLEFT", 8, 8)

    for i = 1, self.MAX_EFFECT_ICONS do
        self.EffectFrames.Target[i] = self:CreateEffectIcon(row, i)
    end

    parent.effectsRow = row
end

-- ═══════════════════════════════════════════════════════════
-- ИКОНКИ ЭФФЕКТОВ
-- ═══════════════════════════════════════════════════════════

function UF:CreateEffectIcon(parent, index)
    local size = self.EFFECT_ICON_SIZE
    local spacing = 2

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("LEFT", (index - 1) * (size + spacing), 0)

    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Иконка
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size - 4, size - 4)
    icon:SetPoint("CENTER")
    frame.icon = icon

    -- Длительность (снизу справа)
    local duration = frame:CreateFontString(nil, "OVERLAY")
    duration:SetFont(SBS.Config.FONT, 8, "OUTLINE")
    duration:SetPoint("BOTTOMRIGHT", 2, -2)
    duration:SetTextColor(1, 1, 1)
    frame.duration = duration

    -- Стаки (сверху слева)
    local stacks = frame:CreateFontString(nil, "OVERLAY")
    stacks:SetFont(SBS.Config.FONT, 8, "OUTLINE")
    stacks:SetPoint("TOPLEFT", -2, 2)
    stacks:SetTextColor(0.3, 1, 0.3)
    stacks:Hide()
    frame.stacks = stacks

    -- Тултип
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if self.effectData then
            UF:ShowEffectTooltip(self)
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:Hide()
    return frame
end

function UF:SetupEffectIcon(frame, effectDef, effectData)
    if not effectDef then return end

    -- Иконка
    if effectDef.icon then
        frame.icon:SetTexture(effectDef.icon)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Цвет рамки по типу
    local borderColor = COLORS.buffBorder
    if effectDef.type == "debuff" then
        borderColor = COLORS.debuffBorder
    elseif effectDef.type == "dot" then
        borderColor = COLORS.woundBorder
    end
    frame:SetBackdropBorderColor(unpack(borderColor))

    -- Длительность
    if effectData.remainingRounds and effectData.remainingRounds > 0 then
        frame.duration:SetText(effectData.remainingRounds)
        frame.duration:Show()
    else
        frame.duration:Hide()
    end

    -- Стаки
    if effectData.stacks and effectData.stacks > 1 then
        frame.stacks:SetText("x" .. effectData.stacks)
        frame.stacks:Show()
    else
        frame.stacks:Hide()
    end

    frame.effectData = effectData
    frame.effectDef = effectDef
    frame:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ ФРЕЙМОВ
-- ═══════════════════════════════════════════════════════════

function UF:UpdatePlayerFrame()
    local frame = self.PlayerFrame
    if not frame or not frame:IsShown() then return end

    -- Портрет
    SetPortraitTexture(frame.portrait.texture, "player")

    -- Уровень
    local level = SBS.Stats and SBS.Stats:GetLevel() or UnitLevel("player")
    frame.levelBadge.text:SetText(level)

    -- Имя
    frame.info.name:SetText(UnitName("player"))

    -- Иконка роли
    local role = SBS.Stats and SBS.Stats:GetRole()
    if role and SBS.Config.Roles[role] then
        frame.info.roleIcon:SetTexture(SBS.Config.Roles[role].icon)
        frame.info.roleIcon:Show()
    else
        frame.info.roleIcon:Hide()
    end

    -- HP бар
    local currentHP = SBS.Stats and SBS.Stats:GetCurrentHP() or 5
    local maxHP = SBS.Stats and SBS.Stats:GetMaxHP() or 5
    frame.bars.hpBar:SetMinMaxValues(0, maxHP)
    frame.bars.hpBar:SetValue(currentHP)
    frame.bars.hpBar.text:SetText(currentHP .. "/" .. maxHP)

    -- Цвет HP по проценту
    local pct = currentHP / maxHP
    if pct > 0.5 then
        frame.bars.hpBar:SetStatusBarColor(unpack(COLORS.hpHigh))
    elseif pct > 0.25 then
        frame.bars.hpBar:SetStatusBarColor(unpack(COLORS.hpMid))
    else
        frame.bars.hpBar:SetStatusBarColor(unpack(COLORS.hpLow))
    end

    -- Щит
    local shield = SBS.Stats and SBS.Stats:GetShield() or 0
    if shield > 0 then
        frame.bars.hpBar.shieldBar:SetMinMaxValues(0, maxHP)
        frame.bars.hpBar.shieldBar:SetValue(shield)
        frame.bars.hpBar.shieldBar:Show()
        frame.bars.hpBar.shieldText:SetText("+" .. shield)
        frame.bars.hpBar.shieldText:Show()
    else
        frame.bars.hpBar.shieldBar:Hide()
        frame.bars.hpBar.shieldText:Hide()
    end

    -- Энергия бар
    local energy = SBS.Stats and SBS.Stats:GetEnergy() or 2
    local maxEnergy = SBS.Stats and SBS.Stats:GetMaxEnergy() or 2
    frame.bars.energyBar:SetMinMaxValues(0, maxEnergy)
    frame.bars.energyBar:SetValue(energy)
    frame.bars.energyBar.text:SetText(energy .. "/" .. maxEnergy)

    -- Обновляем эффекты
    self:UpdatePlayerEffects()
end

function UF:UpdateTargetFrame()
    local frame = self.TargetFrame
    if not frame then return end

    -- Проверяем включён ли фрейм
    if not SBS.db.profile.unitFrames.target.enabled then
        frame:Hide()
        return
    end

    -- Проверяем есть ли цель
    if not UnitExists("target") then
        frame:Hide()
        return
    end

    local isPlayer = UnitIsPlayer("target")
    local targetName = UnitName("target")
    local guid = UnitGUID("target")

    -- Определяем тип цели и получаем данные
    local playerData, npcData
    if isPlayer then
        -- Если таргетим себя - берём данные напрямую из SBS.Stats (всегда актуальные)
        if UnitIsUnit("target", "player") then
            playerData = {
                hp = SBS.Stats:GetCurrentHP(),
                maxHp = SBS.Stats:GetMaxHP(),
                level = SBS.Stats:GetLevel(),
                wounds = SBS.Stats:GetWounds(),
                shield = SBS.Stats:GetShield(),
                energy = SBS.Stats:GetEnergy(),
                maxEnergy = SBS.Stats:GetMaxEnergy(),
            }
        else
            playerData = SBS.Sync and SBS.Sync:GetPlayerData(targetName)
        end
    else
        npcData = SBS.Units and SBS.Units:Get(guid)
    end

    -- Если нет данных ни для игрока ни для NPC - показываем "Нет данных"
    if not playerData and not npcData then
        frame:Show()
        SetPortraitTexture(frame.portrait.texture, "target")
        frame.info.name:SetText(targetName)
        frame.info.infoBtn:Hide()
        frame.hpBar:Hide()
        frame.energyBar:Hide()
        frame.defenseRow:Hide()
        frame.effectsRow:Hide()
        frame.noDataText:Show()
        self:HideTargetModifyButtons()
        return
    end

    frame:Show()
    frame.noDataText:Hide()

    -- Портрет
    SetPortraitTexture(frame.portrait.texture, "target")

    -- === ИГРОК С АДДОНОМ ===
    if playerData then
        frame.info.name:SetText(targetName)
        frame.info.name:SetTextColor(1, 1, 1)  -- Белый для игроков
        frame.info.infoBtn:Show()  -- Показываем кнопку статов

        -- HP бар
        frame.hpBar:Show()
        frame.hpBar:SetStatusBarColor(unpack(COLORS.hpHigh))
        frame.hpBar:SetMinMaxValues(0, playerData.maxHp or 1)
        frame.hpBar:SetValue(playerData.hp or 0)
        frame.hpBar.text:SetText((playerData.hp or 0) .. "/" .. (playerData.maxHp or 0))

        -- Энергия бар
        frame.energyBar:Show()
        frame.energyBar:SetMinMaxValues(0, playerData.maxEnergy or 1)
        frame.energyBar:SetValue(playerData.energy or 0)
        frame.energyBar.text:SetText((playerData.energy or 0) .. "/" .. (playerData.maxEnergy or 0))

        -- Скрываем пороги защиты (для игроков)
        frame.defenseRow:Hide()

        -- Показываем эффекты
        frame.effectsRow:Show()
        self:UpdateTargetEffects()

    -- === NPC С ДАННЫМИ ===
    else
        frame.info.name:SetText(npcData.name or targetName)
        frame.info.name:SetTextColor(1, 0.4, 0.4)  -- Красный для NPC
        frame.info.infoBtn:Hide()  -- Скрываем кнопку статов для NPC

        -- HP бар
        frame.hpBar:Show()
        frame.hpBar:SetStatusBarColor(unpack(COLORS.hpNPC))
        frame.hpBar:SetMinMaxValues(0, npcData.maxHp or 1)
        frame.hpBar:SetValue(npcData.hp or 0)

        if (npcData.hp or 0) <= 0 then
            frame.hpBar.text:SetText("|cFFFF0000DEAD|r")
        else
            frame.hpBar.text:SetText((npcData.hp or 0) .. "/" .. (npcData.maxHp or 0))
        end

        -- Скрываем энергия бар и кнопки энергии (для NPC)
        frame.energyBar:Hide()
        if frame.energyBar.minusBtn then
            frame.energyBar.minusBtn:Hide()
            frame.energyBar.plusBtn:Hide()
        end

        -- Пороги защиты
        frame.defenseRow:Show()
        local fortMod = SBS.Effects and SBS.Effects:GetModifier("npc", guid, "fort") or 0
        local reflexMod = SBS.Effects and SBS.Effects:GetModifier("npc", guid, "reflex") or 0
        local willMod = SBS.Effects and SBS.Effects:GetModifier("npc", guid, "will") or 0

        local effectiveFort = math.max(1, (npcData.fort or 10) + fortMod)
        local effectiveReflex = math.max(1, (npcData.reflex or 10) + reflexMod)
        local effectiveWill = math.max(1, (npcData.will or 10) + willMod)

        frame.defenseRow.fortitude.value:SetText(effectiveFort)
        frame.defenseRow.reflex.value:SetText(effectiveReflex)
        frame.defenseRow.will.value:SetText(effectiveWill)

        -- Показываем эффекты
        frame.effectsRow:Show()
        self:UpdateTargetEffects()
    end
end

function UF:UpdatePlayerEffects()
    self:HideAllEffects(self.EffectFrames.Player)

    if not SBS.Effects then return end

    local myName = UnitName("player")
    local effects = SBS.Effects:GetAll("player", myName)

    if not effects then return end

    local index = 1
    for effectId, effectData in pairs(effects) do
        if index > self.MAX_EFFECT_ICONS then break end

        local def = SBS.Effects.Definitions and SBS.Effects.Definitions[effectId]
        if def then
            self:SetupEffectIcon(self.EffectFrames.Player[index], def, effectData)
            index = index + 1
        end
    end
end

function UF:UpdateTargetEffects()
    self:HideAllEffects(self.EffectFrames.Target)

    if not SBS.Effects or not UnitExists("target") then return end

    local guid = UnitGUID("target")
    local name = UnitName("target")
    local isPlayer = UnitIsPlayer("target")

    -- Получаем эффекты в зависимости от типа цели
    local effects
    if isPlayer then
        effects = SBS.Effects:GetAll("player", name)
    else
        effects = SBS.Effects:GetAll("npc", guid)
    end

    if not effects then return end

    local index = 1
    for effectId, effectData in pairs(effects) do
        if index > self.MAX_EFFECT_ICONS then break end

        local def = SBS.Effects.Definitions and SBS.Effects.Definitions[effectId]
        if def then
            self:SetupEffectIcon(self.EffectFrames.Target[index], def, effectData)
            index = index + 1
        end
    end
end

function UF:HideAllEffects(frames)
    for _, frame in ipairs(frames) do
        frame:Hide()
        frame.effectData = nil
        frame.effectDef = nil
    end
end

-- ═══════════════════════════════════════════════════════════
-- ТУЛТИПЫ
-- ═══════════════════════════════════════════════════════════

function UF:ShowPlayerStatsTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cFFFFD700" .. UnitName("player") .. "|r")
    GameTooltip:AddLine(" ")

    -- Роль
    local role = SBS.Stats and SBS.Stats:GetRole()
    if role and SBS.Config.Roles[role] then
        local roleData = SBS.Config.Roles[role]
        GameTooltip:AddDoubleLine("Роль:", roleData.name, 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddLine(" ")
    end

    -- Статы
    if SBS.Stats and SBS.Config.AllStats then
        for _, stat in ipairs(SBS.Config.AllStats) do
            local value = SBS.Stats:GetTotal(stat) or 0
            local name = SBS.Config.StatNames[stat] or stat
            local colorHex = SBS.Config.StatColors[stat] or "FFFFFF"
            local r = tonumber(colorHex:sub(1,2), 16) / 255
            local g = tonumber(colorHex:sub(3,4), 16) / 255
            local b = tonumber(colorHex:sub(5,6), 16) / 255
            GameTooltip:AddDoubleLine(name .. ":", value, r, g, b, 1, 1, 1)
        end
    end

    -- Ранения
    local wounds = SBS.Stats and SBS.Stats:GetWounds() or 0
    if wounds > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Ранения:", wounds .. "/" .. SBS.Config.MAX_WOUNDS, 1, 0.3, 0.3, 1, 0.3, 0.3)
    end

    GameTooltip:Show()
end

function UF:ShowTargetPlayerStatsTooltip(frame)
    if not UnitExists("target") or not UnitIsPlayer("target") then return end

    local targetName = UnitName("target")
    local playerData = SBS.Sync and SBS.Sync:GetPlayerData(targetName)

    if not playerData then return end

    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cFFFFD700" .. targetName .. "|r")
    GameTooltip:AddLine(" ")

    -- Роль
    if playerData.role and SBS.Config.Roles[playerData.role] then
        local roleData = SBS.Config.Roles[playerData.role]
        GameTooltip:AddDoubleLine("Роль:", roleData.name, 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddLine(" ")
    end

    -- Статы (в playerData они хранятся в lowercase: strength, dexterity и т.д.)
    if SBS.Config.AllStats then
        for _, stat in ipairs(SBS.Config.AllStats) do
            -- Преобразуем имя стата в lowercase для доступа к playerData
            local statKey = stat:lower()
            local value = playerData[statKey] or 0
            local name = SBS.Config.StatNames[stat] or stat
            local colorHex = SBS.Config.StatColors[stat] or "FFFFFF"
            local r = tonumber(colorHex:sub(1,2), 16) / 255
            local g = tonumber(colorHex:sub(3,4), 16) / 255
            local b = tonumber(colorHex:sub(5,6), 16) / 255
            GameTooltip:AddDoubleLine(name .. ":", value, r, g, b, 1, 1, 1)
        end
    end

    -- Ранения
    if playerData.wounds and playerData.wounds > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Ранения:", playerData.wounds .. "/" .. SBS.Config.MAX_WOUNDS, 1, 0.3, 0.3, 1, 0.3, 0.3)
    end

    GameTooltip:Show()
end

function UF:ShowEffectTooltip(frame)
    local def = frame.effectDef
    local data = frame.effectData

    if not def or not data then return end

    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    -- Название эффекта
    local name = def.name or "Unknown"
    GameTooltip:AddLine(name, 1, 0.82, 0)

    -- Тип
    local typeText = "Эффект"
    local r, g, b = 0.7, 0.7, 0.7
    if def.type == "buff" then
        typeText = "Бафф"
        r, g, b = 0.2, 0.8, 0.2
    elseif def.type == "debuff" then
        typeText = "Дебафф"
        r, g, b = 0.8, 0.2, 0.2
    elseif def.type == "dot" then
        typeText = "Периодический урон"
        r, g, b = 1, 0.5, 0
    end
    GameTooltip:AddLine(typeText, r, g, b)

    -- Описание
    if def.description then
        GameTooltip:AddLine(def.description, 0.8, 0.8, 0.8, true)
    end

    -- Длительность
    if data.remainingRounds and data.remainingRounds > 0 then
        GameTooltip:AddLine("Осталось: " .. data.remainingRounds .. " ход(ов)", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ПОЗИЦИИ И МАСШТАБ
-- ═══════════════════════════════════════════════════════════

function UF:SavePosition(frameType)
    local frame = frameType == "player" and self.PlayerFrame or self.TargetFrame
    if not frame then return end

    local point, _, relPoint, x, y = frame:GetPoint()
    SBS.db.profile.unitFrames[frameType].position = {
        point = point,
        relPoint = relPoint or point,
        x = x,
        y = y,
    }
end

function UF:LoadPosition(frameType)
    local frame = frameType == "player" and self.PlayerFrame or self.TargetFrame
    if not frame then return end

    local pos = SBS.db.profile.unitFrames[frameType].position
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end
end

function UF:ResetPosition(frameType)
    local defaults = {
        player = { point = "CENTER", relPoint = "CENTER", x = -400, y = -200 },
        target = { point = "CENTER", relPoint = "CENTER", x = -400, y = -300 },
    }

    SBS.db.profile.unitFrames[frameType].position = defaults[frameType]
    self:LoadPosition(frameType)
end

function UF:ApplyScale(frameType)
    local frame = frameType == "player" and self.PlayerFrame or self.TargetFrame
    if not frame then return end

    local scale = SBS.db.profile.unitFrames[frameType].scale or 1.0
    frame:SetScale(scale)
end

-- ═══════════════════════════════════════════════════════════
-- КНОПКИ УПРАВЛЕНИЯ
-- ═══════════════════════════════════════════════════════════

function UF:TogglePlayerFrame()
    local enabled = not SBS.db.profile.unitFrames.player.enabled
    SBS.db.profile.unitFrames.player.enabled = enabled

    if enabled then
        self.PlayerFrame:Show()
        self:UpdatePlayerFrame()
    else
        self.PlayerFrame:Hide()
    end

    self:UpdateControlButtons()
end

function UF:ToggleTargetFrame()
    local enabled = not SBS.db.profile.unitFrames.target.enabled
    SBS.db.profile.unitFrames.target.enabled = enabled

    self:UpdateControlButtons()
    self:UpdateTargetFrame()
end

function UF:ToggleLock()
    local locked = not SBS.db.profile.unitFrames.player.locked
    SBS.db.profile.unitFrames.player.locked = locked
    SBS.db.profile.unitFrames.target.locked = locked

    self:UpdateControlButtons()

    if SBS.Utils then
        SBS.Utils:Info("Фреймы " .. (locked and "заблокированы" or "разблокированы"))
    end
end

function UF:UpdateControlButtons()
    local playerBtn = _G["SBS_MainFrame_TopBar_PlayerFrameBtn"]
    local targetBtn = _G["SBS_MainFrame_TopBar_TargetFrameBtn"]
    local lockBtn = _G["SBS_MainFrame_TopBar_LockFramesBtn"]

    if playerBtn then
        local enabled = SBS.db.profile.unitFrames.player.enabled
        if enabled then
            playerBtn:SetBackdropBorderColor(unpack(COLORS.btnActive))
        else
            playerBtn:SetBackdropBorderColor(unpack(COLORS.btnInactive))
        end
    end

    if targetBtn then
        local enabled = SBS.db.profile.unitFrames.target.enabled
        if enabled then
            targetBtn:SetBackdropBorderColor(unpack(COLORS.btnActive))
        else
            targetBtn:SetBackdropBorderColor(unpack(COLORS.btnInactive))
        end
    end

    if lockBtn then
        local locked = SBS.db.profile.unitFrames.player.locked
        if locked then
            lockBtn:SetBackdropBorderColor(unpack(COLORS.btnLocked))
        else
            lockBtn:SetBackdropBorderColor(unpack(COLORS.btnInactive))
        end
    end
end

function UF:HideModifyButtonsDelayed(barsContainer)
    -- Отменяем существующий таймер, если он есть
    if barsContainer.hideTimer then
        barsContainer.hideTimer:Cancel()
        barsContainer.hideTimer = nil
    end

    -- Создаём новый таймер с задержкой 0.2 секунды
    barsContainer.hideTimer = C_Timer.NewTimer(0.2, function()
        -- Проверяем, находится ли курсор на фрейме или кнопках
        local mouseOver = MouseIsOver(UF.PlayerFrame)
        if not mouseOver and barsContainer.hpBar and barsContainer.energyBar then
            -- Также проверяем, не на кнопках ли мышь
            local onButton = MouseIsOver(barsContainer.hpBar.minusBtn) or
                           MouseIsOver(barsContainer.hpBar.plusBtn) or
                           MouseIsOver(barsContainer.energyBar.minusBtn) or
                           MouseIsOver(barsContainer.energyBar.plusBtn)

            if not onButton then
                -- Скрываем все кнопки
                barsContainer.hpBar.minusBtn:Hide()
                barsContainer.hpBar.plusBtn:Hide()
                barsContainer.energyBar.minusBtn:Hide()
                barsContainer.energyBar.plusBtn:Hide()
            end
        end
        barsContainer.hideTimer = nil
    end)
end

-- ═══════════════════════════════════════════════════════════
-- КНОПКИ +/- ТАРГЕТ ФРЕЙМА (ТОЛЬКО МАСТЕР)
-- ═══════════════════════════════════════════════════════════

function UF:ShowTargetModifyButtons()
    local frame = self.TargetFrame
    if not frame or not frame:IsShown() then return end

    -- Отменяем таймер скрытия если он есть
    if frame.hideTimer then
        frame.hideTimer:Cancel()
        frame.hideTimer = nil
    end

    -- HP кнопки показываем всегда (для игроков и NPC)
    if frame.hpBar and frame.hpBar:IsShown() and frame.hpBar.minusBtn then
        frame.hpBar.minusBtn:Show()
        frame.hpBar.plusBtn:Show()
    end

    -- Energy кнопки показываем только если энергия бар виден (только для игроков)
    if frame.energyBar and frame.energyBar:IsShown() and frame.energyBar.minusBtn then
        frame.energyBar.minusBtn:Show()
        frame.energyBar.plusBtn:Show()
    end
end

function UF:HideTargetModifyButtons()
    local frame = self.TargetFrame
    if not frame then return end

    if frame.hpBar and frame.hpBar.minusBtn then
        frame.hpBar.minusBtn:Hide()
        frame.hpBar.plusBtn:Hide()
    end
    if frame.energyBar and frame.energyBar.minusBtn then
        frame.energyBar.minusBtn:Hide()
        frame.energyBar.plusBtn:Hide()
    end
end

function UF:HideTargetModifyButtonsDelayed()
    local frame = self.TargetFrame
    if not frame then return end

    -- Отменяем существующий таймер
    if frame.hideTimer then
        frame.hideTimer:Cancel()
        frame.hideTimer = nil
    end

    frame.hideTimer = C_Timer.NewTimer(0.2, function()
        if not frame:IsShown() then
            frame.hideTimer = nil
            return
        end

        local mouseOver = MouseIsOver(frame)
        if not mouseOver then
            -- Проверяем, не на кнопках ли мышь
            local onButton = false
            if frame.hpBar and frame.hpBar.minusBtn then
                onButton = onButton or MouseIsOver(frame.hpBar.minusBtn) or MouseIsOver(frame.hpBar.plusBtn)
            end
            if frame.energyBar and frame.energyBar.minusBtn then
                onButton = onButton or MouseIsOver(frame.energyBar.minusBtn) or MouseIsOver(frame.energyBar.plusBtn)
            end

            if not onButton then
                UF:HideTargetModifyButtons()
            end
        end
        frame.hideTimer = nil
    end)
end

function UF:ModifyTargetHP(delta)
    if not SBS.Sync or not SBS.Sync:IsMaster() then return end
    if not UnitExists("target") then return end

    local targetName = UnitName("target")
    local isPlayer = UnitIsPlayer("target")

    if isPlayer then
        if UnitIsUnit("target", "player") then
            SBS.Stats:ModifyHP(delta)
        else
            SBS.Sync:ModifyPlayerHP(targetName, delta)
        end
    else
        local guid = UnitGUID("target")
        local npcData = SBS.Units and SBS.Units:Get(guid)
        if npcData then
            SBS.Units:ModifyHP(guid, npcData.hp + delta)
        end
    end

    -- Обновляем таргет фрейм
    C_Timer.After(0.05, function()
        UF:UpdateTargetFrame()
    end)
end

function UF:ModifyTargetEnergy(delta)
    if not SBS.Sync or not SBS.Sync:IsMaster() then return end
    if not UnitExists("target") then return end
    if not UnitIsPlayer("target") then return end

    local targetName = UnitName("target")

    if UnitIsUnit("target", "player") then
        SBS.Stats:ModifyEnergy(delta)
    else
        if delta > 0 then
            SBS.Sync:GiveEnergy(targetName, delta)
        elseif delta < 0 then
            SBS.Sync:TakeEnergy(targetName, math.abs(delta))
        end
    end

    -- Обновляем таргет фрейм
    C_Timer.After(0.05, function()
        UF:UpdateTargetFrame()
    end)
end

-- ═══════════════════════════════════════════════════════════
-- РЕГИСТРАЦИЯ СОБЫТИЙ
-- ═══════════════════════════════════════════════════════════

function UF:RegisterEvents()
    if not SBS.Events then return end

    -- Хелпер: обновить TargetFrame если таргетим себя
    local function UpdateTargetIfSelf()
        if UnitIsUnit("target", "player") then
            UF:UpdateTargetFrame()
            UF:UpdateTargetEffects()
        end
    end

    -- Обновление при входе в мир (для портрета) и при смене цели
    self.PlayerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.PlayerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.PlayerFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    self.PlayerFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, function()
                UF:UpdatePlayerFrame()
            end)
        elseif event == "UNIT_PORTRAIT_UPDATE" then
            local unit = ...
            if unit == "player" then
                UF:UpdatePlayerFrame()
            end
            if unit == "target" then
                UF:UpdateTargetFrame()
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            UF:UpdateTargetFrame()
            UF:UpdateTargetEffects()
        end
    end)

    -- HP игрока изменилось
    SBS.Events:Register("PLAYER_HP_CHANGED", function(currentHP, maxHP)
        UF:UpdatePlayerFrame()
        UpdateTargetIfSelf()
    end, UF)

    -- Щит игрока изменился
    SBS.Events:Register("PLAYER_SHIELD_CHANGED", function(shield)
        UF:UpdatePlayerFrame()
        UpdateTargetIfSelf()
    end, UF)

    -- Энергия игрока изменилась
    SBS.Events:Register("PLAYER_ENERGY_CHANGED", function(currentEnergy, maxEnergy)
        UF:UpdatePlayerFrame()
        UpdateTargetIfSelf()
    end, UF)

    -- Статы игрока изменились
    SBS.Events:Register("PLAYER_STATS_CHANGED", function()
        UF:UpdatePlayerFrame()
        UpdateTargetIfSelf()
    end, UF)

    -- Уровень изменился
    SBS.Events:Register("PLAYER_LEVEL_CHANGED", function(newLevel, oldLevel)
        UF:UpdatePlayerFrame()
        UpdateTargetIfSelf()
    end, UF)

    -- Роль изменилась
    SBS.Events:Register("PLAYER_SPEC_CHANGED", function(newSpec, oldSpec)
        UF:UpdatePlayerFrame()
    end, UF)

    -- HP юнита (NPC) изменилось
    SBS.Events:Register("UNIT_HP_CHANGED", function(guid, currentHP, maxHP)
        UF:UpdateTargetFrame()
    end, UF)

    -- Юнит создан
    SBS.Events:Register("UNIT_CREATED", function(guid, data)
        UF:UpdateTargetFrame()
    end, UF)

    -- Юнит удалён
    SBS.Events:Register("UNIT_REMOVED", function(guid)
        UF:UpdateTargetFrame()
    end, UF)

    -- Эффект применён
    SBS.Events:Register("EFFECT_APPLIED", function(targetType, targetId, effectId)
        -- Обновляем свои эффекты если применён на себя
        if targetType == "player" and targetId == UnitName("player") then
            UF:UpdatePlayerEffects()
        end
        -- Обновляем эффекты цели если применён на текущую цель
        if UnitExists("target") then
            local isTargetPlayer = UnitIsPlayer("target")
            local targetName = UnitName("target")
            local targetGuid = UnitGUID("target")
            if (targetType == "player" and isTargetPlayer and targetId == targetName) or
               (targetType == "npc" and not isTargetPlayer and targetId == targetGuid) then
                UF:UpdateTargetEffects()
            end
        end
    end, UF)

    -- Эффект удалён
    SBS.Events:Register("EFFECT_REMOVED", function(targetType, targetId, effectId)
        -- Обновляем свои эффекты если удалён с себя
        if targetType == "player" and targetId == UnitName("player") then
            UF:UpdatePlayerEffects()
        end
        -- Обновляем эффекты цели если удалён с текущей цели
        if UnitExists("target") then
            local isTargetPlayer = UnitIsPlayer("target")
            local targetName = UnitName("target")
            local targetGuid = UnitGUID("target")
            if (targetType == "player" and isTargetPlayer and targetId == targetName) or
               (targetType == "npc" and not isTargetPlayer and targetId == targetGuid) then
                UF:UpdateTargetEffects()
            end
        end
    end, UF)

    -- Данные другого игрока обновились (мастер изменил HP/Energy)
    SBS.Events:Register("PLAYER_DATA_RECEIVED", function(playerName)
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = UnitName("target")
            if targetName == playerName then
                UF:UpdateTargetFrame()
                UF:UpdateTargetEffects()
            end
        end
    end, UF)

    -- Эффекты синхронизированы
    SBS.Events:Register("EFFECTS_SYNCED", function()
        UF:UpdatePlayerEffects()
        UF:UpdateTargetEffects()
    end, UF)

    -- Принудительное обновление портрета после инициализации
    -- (на случай если PLAYER_ENTERING_WORLD уже произошёл до регистрации)
    C_Timer.After(0.1, function()
        UF:UpdatePlayerFrame()
        UF:UpdateTargetFrame()
    end)
end
