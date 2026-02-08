-- SBS/UI/Settings.lua
-- Панель настроек аддона в игровом меню (Интерфейс -> Модификации)

local ADDON_NAME, SBS = ...

-- ═══════════════════════════════════════════════════════════
-- ПЕРЕМЕННЫЕ НАСТРОЕК
-- ═══════════════════════════════════════════════════════════

SBS.Settings = SBS.Settings or {}

-- Настройки по умолчанию
local defaults = {
    combatLogEnabled = true, -- Включен ли журнал боя (true = только журнал, false = только чат)
    uiScale = 1.0, -- Масштаб главного окна (0.5 - 2.0)
}

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ НАСТРОЕК
-- ═══════════════════════════════════════════════════════════

function SBS.Settings:Init()
    -- Инициализируем SavedVariables если их нет
    if not SBS_DB then
        SBS_DB = {}
    end
    if not SBS_DB.settings then
        SBS_DB.settings = {}
    end

    -- Применяем значения по умолчанию для отсутствующих настроек
    for key, value in pairs(defaults) do
        if SBS_DB.settings[key] == nil then
            SBS_DB.settings[key] = value
        end
    end
end

-- Получить значение настройки
function SBS.Settings:Get(key)
    if not SBS_DB or not SBS_DB.settings then
        return defaults[key]
    end
    local value = SBS_DB.settings[key]
    if value == nil then
        return defaults[key]
    end
    return value
end

-- Установить значение настройки
function SBS.Settings:Set(key, value)
    if not SBS_DB then
        SBS_DB = {}
    end
    if not SBS_DB.settings then
        SBS_DB.settings = {}
    end
    SBS_DB.settings[key] = value

    -- Применяем изменения
    if key == "combatLogEnabled" then
        self:ApplyCombatLogSetting()
    elseif key == "uiScale" then
        self:ApplyUIScale()
    end
end

-- Применить настройку журнала боя
function SBS.Settings:ApplyCombatLogSetting()
    local enabled = self:Get("combatLogEnabled")

    -- Если журнал выключен, скрываем его окно
    if not enabled then
        if SBS.CombatLog and SBS.CombatLog.Frame and SBS.CombatLog.Frame:IsShown() then
            SBS.CombatLog.Frame:Hide()
        end
    end

    -- Обновляем видимость кнопки журнала боя
    if SBS.UI and SBS.UI.UpdateCombatLogButton then
        SBS.UI:UpdateCombatLogButton()
    end
end

-- Применить настройку масштаба UI
function SBS.Settings:ApplyUIScale()
    local scale = self:Get("uiScale")
    if not scale then scale = 1.0 end

    -- Применяем масштаб к главному окну
    local mainFrame = _G["SBS_MainFrame"]
    if mainFrame then
        mainFrame:SetScale(scale)
    end
end

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ ПАНЕЛИ НАСТРОЕК
-- ═══════════════════════════════════════════════════════════

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", "SBS_SettingsPanel")
    panel.name = "SBS"

    -- Заголовок
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFFFFA500SBS - Skyrogx Battle System|r")

    -- Версия
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    version:SetText("|cFF888888Версия 1.2|r")

    -- Описание
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    desc:SetText("Настройки аддона боевой системы")
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")

    -- ═══════════════════════════════════════════════════════════
    -- НАСТРОЙКИ ЖУРНАЛА БОЯ
    -- ═══════════════════════════════════════════════════════════

    local logHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    logHeader:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -24)
    logHeader:SetText("|cFFFFD700Журнал боя|r")

    -- Чекбокс: Включить журнал боя
    local logCheckbox = CreateFrame("CheckButton", "SBS_Settings_LogCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    logCheckbox:SetPoint("TOPLEFT", logHeader, "BOTTOMLEFT", 0, -8)
    logCheckbox.Text:SetText("Включить журнал боя")

    logCheckbox.tooltipText = "Когда включено: все сообщения боя отображаются в журнале.\nКогда выключено: сообщения боя отображаются в чате, журнал недоступен."

    logCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        SBS.Settings:Set("combatLogEnabled", checked)

        if checked then
            SBS.Utils:Info("Журнал боя включен")
        else
            SBS.Utils:Info("Журнал боя выключен, сообщения будут в чате")
        end
    end)

    -- Описание настройки
    local logDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    logDesc:SetPoint("TOPLEFT", logCheckbox, "BOTTOMLEFT", 24, -4)
    logDesc:SetWidth(480)
    logDesc:SetJustifyH("LEFT")
    logDesc:SetTextColor(0.7, 0.7, 0.7)
    logDesc:SetText("Включено: все логи боя отображаются в окне журнала (ничего в чат).\nВыключено: журнал недоступен, все логи идут только в чат.")

    -- ═══════════════════════════════════════════════════════════
    -- НАСТРОЙКИ МАСШТАБА ОКНА
    -- ═══════════════════════════════════════════════════════════

    local scaleHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scaleHeader:SetPoint("TOPLEFT", logDesc, "BOTTOMLEFT", -24, -24)
    scaleHeader:SetText("|cFFFFD700Масштаб окна|r")

    -- Слайдер масштаба
    local scaleSlider = CreateFrame("Slider", "SBS_Settings_ScaleSlider", panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleHeader, "BOTTOMLEFT", 4, -16)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetWidth(300)

    _G[scaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[scaleSlider:GetName() .. "High"]:SetText("200%")
    _G[scaleSlider:GetName() .. "Text"]:SetText("Масштаб интерфейса")

    -- Значение слайдера
    local scaleValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100 -- Округляем до 2 знаков
        scaleValue:SetText(string.format("%.0f%%", value * 100))
        SBS.Settings:Set("uiScale", value)
    end)

    -- Описание настройки
    local scaleDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scaleDesc:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -8)
    scaleDesc:SetWidth(480)
    scaleDesc:SetJustifyH("LEFT")
    scaleDesc:SetTextColor(0.7, 0.7, 0.7)
    scaleDesc:SetText("Изменяет размер главного окна SBS. Требуется перезагрузка UI для полного применения.")

    -- ═══════════════════════════════════════════════════════════
    -- НАСТРОЙКИ UNIT FRAMES
    -- ═══════════════════════════════════════════════════════════

    local ufHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ufHeader:SetPoint("TOPLEFT", scaleDesc, "BOTTOMLEFT", -4, -24)
    ufHeader:SetText("|cFFFFD700Компактные фреймы|r")

    -- Чекбокс: Показывать фрейм игрока
    local playerFrameCheckbox = CreateFrame("CheckButton", "SBS_Settings_PlayerFrameCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    playerFrameCheckbox:SetPoint("TOPLEFT", ufHeader, "BOTTOMLEFT", 0, -8)
    playerFrameCheckbox.Text:SetText("Показывать фрейм игрока")
    playerFrameCheckbox.tooltipText = "Отображать компактный фрейм с HP, энергией и эффектами игрока."

    playerFrameCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if SBS.db and SBS.db.profile and SBS.db.profile.unitFrames then
            SBS.db.profile.unitFrames.player.enabled = checked
            if SBS.UI and SBS.UI.UnitFrames then
                if checked then
                    SBS.UI.UnitFrames.PlayerFrame:Show()
                    SBS.UI.UnitFrames:UpdatePlayerFrame()
                else
                    SBS.UI.UnitFrames.PlayerFrame:Hide()
                end
                SBS.UI.UnitFrames:UpdateControlButtons()
            end
        end
    end)

    -- Чекбокс: Показывать фрейм цели
    local targetFrameCheckbox = CreateFrame("CheckButton", "SBS_Settings_TargetFrameCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    targetFrameCheckbox:SetPoint("TOPLEFT", playerFrameCheckbox, "BOTTOMLEFT", 0, -4)
    targetFrameCheckbox.Text:SetText("Показывать фрейм цели (NPC)")
    targetFrameCheckbox.tooltipText = "Отображать компактный фрейм с HP и защитой выбранного NPC."

    targetFrameCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if SBS.db and SBS.db.profile and SBS.db.profile.unitFrames then
            SBS.db.profile.unitFrames.target.enabled = checked
            if SBS.UI and SBS.UI.UnitFrames then
                SBS.UI.UnitFrames:UpdateControlButtons()
                SBS.UI.UnitFrames:UpdateTargetFrame()
            end
        end
    end)

    -- Чекбокс: Заблокировать перемещение
    local lockFramesCheckbox = CreateFrame("CheckButton", "SBS_Settings_LockFramesCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    lockFramesCheckbox:SetPoint("TOPLEFT", targetFrameCheckbox, "BOTTOMLEFT", 0, -4)
    lockFramesCheckbox.Text:SetText("Заблокировать перемещение")
    lockFramesCheckbox.tooltipText = "Запретить перемещение фреймов мышью."

    lockFramesCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if SBS.db and SBS.db.profile and SBS.db.profile.unitFrames then
            SBS.db.profile.unitFrames.player.locked = checked
            SBS.db.profile.unitFrames.target.locked = checked
            if SBS.UI and SBS.UI.UnitFrames then
                SBS.UI.UnitFrames:UpdateControlButtons()
            end
        end
    end)

    -- Слайдер масштаба Unit Frames
    local ufScaleSlider = CreateFrame("Slider", "SBS_Settings_UFScaleSlider", panel, "OptionsSliderTemplate")
    ufScaleSlider:SetPoint("TOPLEFT", lockFramesCheckbox, "BOTTOMLEFT", 4, -20)
    ufScaleSlider:SetMinMaxValues(0.5, 2.0)
    ufScaleSlider:SetValueStep(0.05)
    ufScaleSlider:SetObeyStepOnDrag(true)
    ufScaleSlider:SetWidth(200)

    _G[ufScaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[ufScaleSlider:GetName() .. "High"]:SetText("200%")
    _G[ufScaleSlider:GetName() .. "Text"]:SetText("Масштаб фреймов")

    local ufScaleValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ufScaleValue:SetPoint("LEFT", ufScaleSlider, "RIGHT", 10, 0)

    ufScaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        ufScaleValue:SetText(string.format("%.0f%%", value * 100))
        if SBS.db and SBS.db.profile and SBS.db.profile.unitFrames then
            SBS.db.profile.unitFrames.player.scale = value
            SBS.db.profile.unitFrames.target.scale = value
            if SBS.UI and SBS.UI.UnitFrames then
                SBS.UI.UnitFrames:ApplyScale("player")
                SBS.UI.UnitFrames:ApplyScale("target")
            end
        end
    end)

    -- Кнопка сброса позиций
    local resetPosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPosBtn:SetPoint("TOPLEFT", ufScaleSlider, "BOTTOMLEFT", -4, -12)
    resetPosBtn:SetSize(150, 22)
    resetPosBtn:SetText("Сбросить позиции")
    resetPosBtn:SetScript("OnClick", function()
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ResetPosition("player")
            SBS.UI.UnitFrames:ResetPosition("target")
            SBS.Utils:Info("Позиции фреймов сброшены")
        end
    end)

    -- ═══════════════════════════════════════════════════════════
    -- КНОПКИ
    -- ═══════════════════════════════════════════════════════════

    -- Кнопка сброса настроек
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetPoint("BOTTOMLEFT", 16, 16)
    resetBtn:SetSize(150, 25)
    resetBtn:SetText("Сбросить настройки")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("SBS_RESET_SETTINGS")
    end)

    -- Функция обновления UI при открытии панели
    panel.refresh = function()
        logCheckbox:SetChecked(SBS.Settings:Get("combatLogEnabled"))

        local scale = SBS.Settings:Get("uiScale")
        scaleSlider:SetValue(scale)
        scaleValue:SetText(string.format("%.0f%%", scale * 100))

        -- Unit Frames settings
        if SBS.db and SBS.db.profile and SBS.db.profile.unitFrames then
            playerFrameCheckbox:SetChecked(SBS.db.profile.unitFrames.player.enabled)
            targetFrameCheckbox:SetChecked(SBS.db.profile.unitFrames.target.enabled)
            lockFramesCheckbox:SetChecked(SBS.db.profile.unitFrames.player.locked)
            local ufScale = SBS.db.profile.unitFrames.player.scale or 1.0
            ufScaleSlider:SetValue(ufScale)
            ufScaleValue:SetText(string.format("%.0f%%", ufScale * 100))
        end
    end

    return panel
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ПОДТВЕРЖДЕНИЯ СБРОСА
-- ═══════════════════════════════════════════════════════════

StaticPopupDialogs["SBS_RESET_SETTINGS"] = {
    text = "Сбросить все настройки SBS к значениям по умолчанию?",
    button1 = "Да",
    button2 = "Нет",
    OnAccept = function()
        -- Сбрасываем настройки
        SBS_DB.settings = {}
        SBS.Settings:Init()

        -- Обновляем UI если панель открыта
        local panel = _G["SBS_SettingsPanel"]
        if panel and panel.refresh then
            panel.refresh()
        end

        -- Применяем настройки
        SBS.Settings:ApplyCombatLogSetting()

        SBS.Utils:Info("Настройки сброшены к значениям по умолчанию")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ═══════════════════════════════════════════════════════════
-- РЕГИСТРАЦИЯ ПАНЕЛИ
-- ═══════════════════════════════════════════════════════════

local function RegisterSettings()
    -- Проверяем, доступен ли новый API (Dragonflight+)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Новый API (10.0+)
        local panel = CreateSettingsPanel()
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        -- Старый API (9.x)
        local panel = CreateSettingsPanel()
        InterfaceOptions_AddCategory(panel)
    else
        -- Fallback для очень старых версий
        print("|cFFFFA500[SBS]|r Не удалось зарегистрировать панель настроек")
    end
end

-- Регистрируем панель после загрузки аддона
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "SBS" then
        SBS.Settings:Init()
        RegisterSettings()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
