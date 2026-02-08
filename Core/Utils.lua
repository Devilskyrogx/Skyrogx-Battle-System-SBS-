-- SBS/Core/Utils.lua
-- Утилитарные функции

local ADDON_NAME, SBS = ...

-- ═══════════════════════════════════════════════════════════
-- КЭШИРОВАНИЕ ГЛОБАЛЬНЫХ ФУНКЦИЙ
-- ═══════════════════════════════════════════════════════════
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format

SBS.Utils = {}

-- ═══════════════════════════════════════════════════════════
-- ОБЩИЕ BACKDROP ШАБЛОНЫ (для переиспользования)
-- ═══════════════════════════════════════════════════════════
SBS.Utils.Backdrops = {
    Standard = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    },
    Standard2px = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    },
    NoEdge = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
    },
}

-- ═══════════════════════════════════════════════════════════
-- ВЫВОД СООБЩЕНИЙ
-- ═══════════════════════════════════════════════════════════

function SBS.Utils:Print(color, text)
    print("|cFF" .. color .. "[SBS]|r " .. text)
end

function SBS.Utils:Info(text)
    self:Print("00FF00", text)
end

function SBS.Utils:Warn(text)
    self:Print("FFFF00", text)
end

function SBS.Utils:Error(text)
    self:Print("FF0000", text)
end

-- ═══════════════════════════════════════════════════════════
-- ФОРМАТИРОВАНИЕ ТЕКСТА
-- ═══════════════════════════════════════════════════════════

function SBS.Utils:Color(color, text)
    return "|cFF" .. color .. text .. "|r"
end

function SBS.Utils:ColorStat(stat, text)
    local color = SBS.Config.StatColors[stat] or "FFFFFF"
    return self:Color(color, text or SBS.Config.StatNames[stat])
end

-- ═══════════════════════════════════════════════════════════
-- РАБОТА С ЦЕЛЬЮ
-- ═══════════════════════════════════════════════════════════

function SBS.Utils:GetTargetGUID()
    if not UnitExists("target") then
        return nil, nil
    end
    return UnitGUID("target"), UnitName("target")
end

function SBS.Utils:GetTargetInfo()
    if not UnitExists("target") then
        return nil
    end
    return {
        guid = UnitGUID("target"),
        name = UnitName("target"),
        isPlayer = UnitIsPlayer("target"),
    }
end

function SBS.Utils:IsTargetPlayer()
    return UnitExists("target") and UnitIsPlayer("target")
end

function SBS.Utils:RequireTarget(allowPlayer)
    local guid, name = self:GetTargetGUID()
    if not guid then
        self:Error("Нет цели!")
        return nil, nil
    end
    if not allowPlayer and UnitIsPlayer("target") then
        self:Error("Нельзя для игроков!")
        return nil, nil
    end
    return guid, name
end

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКА МАСТЕРА
-- ═══════════════════════════════════════════════════════════

function SBS.Utils:IsMaster()
    return SBS.Sync and SBS.Sync:IsMaster()
end

function SBS.Utils:RequireMaster(silent)
    if not self:IsMaster() and IsInGroup() then
        if not silent then
            self:Error("Только мастер может это делать!")
        end
        return false
    end
    return true
end

-- ═══════════════════════════════════════════════════════════
-- МАСШТАБИРОВАНИЕ UI
-- ═══════════════════════════════════════════════════════════

-- Базовое разрешение для которого UI выглядит оптимально
local BASE_HEIGHT = 768  -- Базовая высота экрана

-- Получить оптимальный масштаб для текущего разрешения
function SBS.Utils:GetUIScale()
    -- Если есть сохранённый пользовательский масштаб, используем его
    if SBS.db and SBS.db.profile and SBS.db.profile.uiScale then
        return SBS.db.profile.uiScale
    end
    
    -- Автоматический расчёт масштаба
    local screenHeight = GetScreenHeight()
    local uiScale = UIParent:GetEffectiveScale()
    
    -- Реальная высота в пикселях
    local realHeight = screenHeight * uiScale
    
    -- Масштаб относительно базового разрешения
    local scale = BASE_HEIGHT / realHeight
    
    -- Ограничиваем масштаб разумными пределами (0.6 - 1.2)
    return self:Clamp(scale, 0.6, 1.2)
end

-- Установить пользовательский масштаб
function SBS.Utils:SetUIScale(scale)
    if not SBS.db or not SBS.db.profile then return end
    
    scale = self:Clamp(scale or 1, 0.5, 1.5)
    SBS.db.profile.uiScale = scale
    
    -- Применить ко всем окнам
    self:ApplyUIScale()
    self:Info("Масштаб UI установлен: " .. string.format("%.1f", scale))
end

-- Сбросить масштаб на автоматический
function SBS.Utils:ResetUIScale()
    if SBS.db and SBS.db.profile then
        SBS.db.profile.uiScale = nil
    end
    self:ApplyUIScale()
    self:Info("Масштаб UI сброшен на автоматический")
end

-- Применить масштаб ко всем окнам аддона
function SBS.Utils:ApplyUIScale()
    local scale = self:GetUIScale()
    
    -- Список всех окон для масштабирования
    local frames = {
        SBS_MainFrame,
        SBS_GMPanel,
        SBS_TurnQueueFrame,
        SBS_AoEPanel,
        SBS_SetHPDialog,
        SBS_DefenseDialog,
        SBS_ModifyNPCHPDialog,
        SBS_NPCAttackDialog,
        SBS_ModifyPlayerHPDialog,
        SBS_GiveShieldDialog,
        SBS_SpecialActionFrame,
        SBS_MasterSpecialActionFrame,
        SBS_SettingsFrame,
    }
    
    for _, frame in ipairs(frames) do
        if frame then
            frame:SetScale(scale)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПРОЧЕЕ
-- ═══════════════════════════════════════════════════════════

function SBS.Utils:Roll(min, max)
    return math.random(min or 1, max or 20)
end

function SBS.Utils:Clamp(value, min, max)
    return math_max(min, math_min(max, value))
end

-- Обновить все UI компоненты
function SBS.Utils:UpdateAllUI()
    if SBS.UI then
        SBS.UI:UpdateMainFrame()
        SBS.UI:UpdateAllNameplates()
        SBS.UI:UpdateAoEPanel()
    end
end
