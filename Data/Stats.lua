-- SBS/Data/Stats.lua
-- Управление характеристиками игрока, уровнем, ролью

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format
local UnitLevel = UnitLevel
local UnitName = UnitName
local IsInGroup = IsInGroup
local UnitIsGroupLeader = UnitIsGroupLeader

SBS.Stats = {}

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:Init()
    -- Синхронизируем уровень с игрой при инициализации
    self:SyncLevelWithGame()
    
    -- Проверяем что текущее HP не больше максимума
    local currentHP = self:GetCurrentHP()
    local maxHP = self:GetMaxHP()
    if currentHP > maxHP then
        self:SetCurrentHP(maxHP)
    end
end

-- ═══════════════════════════════════════════════════════════
-- УРОВЕНЬ (привязан к уровню персонажа в игре)
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:GetLevel()
    -- Получаем уровень напрямую из игры
    local gameLevel = UnitLevel("player")
    
    -- Ограничиваем диапазоном системы
    if gameLevel < SBS.Config.MIN_LEVEL then
        return SBS.Config.MIN_LEVEL
    elseif gameLevel > SBS.Config.MAX_LEVEL then
        return SBS.Config.MAX_LEVEL
    end
    
    return gameLevel
end

function SBS.Stats:GetGameLevel()
    -- Реальный уровень из игры без ограничений
    return UnitLevel("player")
end

function SBS.Stats:GetLastKnownLevel()
    return SBS.db.char.lastKnownLevel or SBS.Config.MIN_LEVEL
end

function SBS.Stats:SetLastKnownLevel(level)
    SBS.db.char.lastKnownLevel = level
end

-- Синхронизация уровня с игрой (вызывается при загрузке и levelup)
function SBS.Stats:SyncLevelWithGame()
    local currentLevel = self:GetLevel()
    local lastKnownLevel = self:GetLastKnownLevel()
    
    if currentLevel ~= lastKnownLevel then
        -- Уровень изменился
        if currentLevel > lastKnownLevel then
            -- Повышение уровня - проверяем новые очки
            self:OnLevelUp(currentLevel, lastKnownLevel)
        else
            -- Понижение уровня (редкий случай, возможно сброс персонажа)
            self:OnLevelDown(currentLevel, lastKnownLevel)
        end
        
        self:SetLastKnownLevel(currentLevel)
    end
end

function SBS.Stats:OnLevelUp(newLevel, oldLevel)
    -- Подсчитываем новые очки между старым и новым уровнем
    local newPoints = 0
    for lvl = oldLevel + 1, newLevel do
        local pointsAtLvl = SBS.Config:GetPointsAtLevel(lvl)
        if pointsAtLvl > 0 then
            newPoints = newPoints + pointsAtLvl
        end
    end
    
    if newPoints > 0 then
        -- Добавляем очки
        self:SetPointsLeft(self:GetPointsLeft() + newPoints)
        
        SBS.Utils:Print("FFD700", "═══ УРОВЕНЬ " .. newLevel .. "! ═══")
        SBS.Utils:Info("+" .. newPoints .. " очков характеристик!")
    end
    
    -- Проверяем, нужно ли обновить HP
    local oldBaseHP = SBS.Config:GetBaseHPForLevel(oldLevel)
    local newBaseHP = SBS.Config:GetBaseHPForLevel(newLevel)
    if newBaseHP > oldBaseHP then
        local hpDiff = newBaseHP - oldBaseHP
        self:SetCurrentHP(math.min(self:GetCurrentHP() + hpDiff, self:GetMaxHP()))
        SBS.Utils:Info("+" .. hpDiff .. " к максимальному здоровью!")
    end
    
    -- Событие
    SBS.Events:Fire("PLAYER_LEVEL_CHANGED", newLevel, oldLevel)
    
    -- Лог
    if SBS.CombatLog then
        SBS.CombatLog:Add(UnitName("player") .. " достиг " .. newLevel .. " уровня!", UnitName("player"))
    end
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
end

function SBS.Stats:OnLevelDown(newLevel, oldLevel)
    -- Понижение уровня - пересчитываем очки
    SBS.Utils:Print("FF6666", "═══ Уровень понижен до " .. newLevel .. " ═══")
    
    -- Пересчитываем доступные очки
    self:RecalculatePoints()
    
    -- Событие
    SBS.Events:Fire("PLAYER_LEVEL_CHANGED", newLevel, oldLevel)
    
    SBS.Utils:Warn("Характеристики могут потребовать перераспределения")
end

-- Пересчёт очков при понижении уровня или сбросе
function SBS.Stats:RecalculatePoints()
    local level = self:GetLevel()
    local totalPointsAvailable = SBS.Config:GetPointsForLevel(level)
    
    -- Считаем использованные очки
    local usedPoints = 0
    for _, stat in ipairs(SBS.Config.AllStats) do
        usedPoints = usedPoints + self:Get(stat)
    end
    
    -- Если использовано больше чем доступно - нужен сброс
    if usedPoints > totalPointsAvailable then
        self:ResetStats()
        SBS.Utils:Warn("Характеристики сброшены из-за недостатка очков!")
    else
        self:SetPointsLeft(totalPointsAvailable - usedPoints)
    end
end

-- ═══════════════════════════════════════════════════════════
-- РОЛЬ (бывшая специализация)
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:GetRole()
    return SBS.db.char.role or SBS.db.char.specialization
end

function SBS.Stats:SetRole(role)
    if role and not SBS.Config.Roles[role] then
        SBS.Utils:Error("Неизвестная роль: " .. tostring(role))
        return false
    end
    
    SBS.db.char.role = role
    SBS.db.char.specialization = role  -- Для совместимости
    
    if role then
        local roleData = SBS.Config.Roles[role]
        SBS.Utils:Print(roleData.color, "Роль: " .. roleData.name)
    else
        SBS.Utils:Info("Роль сброшена")
    end
    
    -- Пересчитываем HP (для танка)
    self:SetCurrentHP(math.min(self:GetCurrentHP(), self:GetMaxHP()))
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    SBS.Events:Fire("PLAYER_SPEC_CHANGED", role, nil)
    return true
end

-- Алиасы для совместимости
function SBS.Stats:GetSpecialization()
    return self:GetRole()
end

function SBS.Stats:SetSpecialization(spec)
    return self:SetRole(spec)
end

function SBS.Stats:GetRoleName()
    local role = self:GetRole()
    if not role then return "Нет" end
    return SBS.Config.Roles[role].name
end

function SBS.Stats:GetRoleColor()
    local role = self:GetRole()
    if not role then return "888888" end
    return SBS.Config.Roles[role].color
end

-- Алиасы для совместимости
function SBS.Stats:GetSpecName()
    return self:GetRoleName()
end

function SBS.Stats:GetSpecColor()
    return self:GetRoleColor()
end

function SBS.Stats:CanChooseRole()
    return self:GetLevel() >= SBS.Config.ROLE_REQUIRED_LEVEL
end

function SBS.Stats:CanChooseSpec()
    return self:CanChooseRole()
end

-- ═══════════════════════════════════════════════════════════
-- РАНЕНИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:GetWounds()
    return SBS.db.char.wounds or 0
end

function SBS.Stats:SetWounds(wounds)
    SBS.db.char.wounds = SBS.Utils:Clamp(wounds, 0, SBS.Config.MAX_WOUNDS)
end

function SBS.Stats:AddWound()
    local wounds = self:GetWounds()
    if wounds >= SBS.Config.MAX_WOUNDS then
        SBS.Utils:Print("FF0000", "Критическое состояние! Судьба персонажа решается мастером.")
        return false
    end
    
    wounds = wounds + 1
    self:SetWounds(wounds)
    
    local penalty = SBS.Config:GetWoundPenalty(wounds)
    SBS.Utils:Print("FF6666", "Получено ранение! (" .. wounds .. "/" .. SBS.Config.MAX_WOUNDS .. 
        ") Штраф: " .. penalty .. " ко всем характеристикам")
    
    -- HP восстанавливается до 1
    self:SetCurrentHP(1)
    
    -- Событие
    SBS.Events:Fire("PLAYER_WOUND_CHANGED", wounds)
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    return true
end

function SBS.Stats:RemoveWound()
    local wounds = self:GetWounds()
    if wounds <= 0 then
        SBS.Utils:Warn("Нет ранений для снятия")
        return false
    end
    
    wounds = wounds - 1
    self:SetWounds(wounds)
    
    if wounds > 0 then
        local penalty = SBS.Config:GetWoundPenalty(wounds)
        SBS.Utils:Print("66FF66", "Ранение исцелено! Осталось: " .. wounds .. 
            ". Штраф: " .. penalty)
    else
        SBS.Utils:Print("66FF66", "Все ранения исцелены!")
    end
    
    -- Событие
    SBS.Events:Fire("PLAYER_WOUND_CHANGED", wounds)
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    return true
end

function SBS.Stats:GetWoundPenalty()
    return SBS.Config:GetWoundPenalty(self:GetWounds())
end

-- ═══════════════════════════════════════════════════════════
-- ЩИТ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:GetShield()
    return SBS.db.char.shield or 0
end

function SBS.Stats:SetShield(value)
    SBS.db.char.shield = math.max(0, value)
end

function SBS.Stats:HasShield()
    return self:GetShield() > 0
end

function SBS.Stats:ApplyShield(amount)
    if self:HasShield() then
        SBS.Utils:Warn("Щит уже активен! Дождитесь его поглощения.")
        return false
    end
    
    self:SetShield(amount)
    SBS.Utils:Print("66CCFF", "Наложен щит: " .. amount)
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    SBS.Events:Fire("PLAYER_SHIELD_CHANGED", amount)
    return true
end

-- Добавить к существующему щиту (для бонусов крита)
function SBS.Stats:AddShield(amount)
    local current = self:GetShield()
    local newShield = current + amount
    self:SetShield(newShield)
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    SBS.Events:Fire("PLAYER_SHIELD_CHANGED", newShield)
    
    if SBS.UI and SBS.UI.UpdateMainFrame then
        SBS.UI:UpdateMainFrame()
    end
    
    return newShield
end

function SBS.Stats:AbsorbDamage(damage)
    local shield = self:GetShield()
    if shield <= 0 then
        return damage, 0  -- Нет щита, весь урон проходит
    end
    
    local absorbed = math.min(shield, damage)
    local remaining = damage - absorbed
    
    self:SetShield(shield - absorbed)
    
    if absorbed > 0 then
        SBS.Utils:Print("66CCFF", "Щит поглотил " .. absorbed .. " урона!")
    end
    
    if self:GetShield() <= 0 then
        SBS.Utils:Print("888888", "Щит разрушен!")
    end
    
    return remaining, absorbed
end

-- ═══════════════════════════════════════════════════════════
-- ХАРАКТЕРИСТИКИ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:Get(stat)
    return SBS.db.char.stats[stat] or 0
end

function SBS.Stats:GetTotal(stat)
    local base = self:Get(stat)
    local wound = self:GetWoundPenalty()
    
    return math.max(0, base + wound)
end

function SBS.Stats:GetMaxStat()
    return SBS.Config:GetMaxStat()
end

function SBS.Stats:GetPointsLeft()
    return SBS.db.char.pointsLeft or 0
end

function SBS.Stats:GetTotalPoints()
    return SBS.Config:GetPointsForLevel(self:GetLevel())
end

function SBS.Stats:GetUsedPoints()
    local used = 0
    for _, stat in ipairs(SBS.Config.AllStats) do
        used = used + self:Get(stat)
    end
    return used
end

function SBS.Stats:Set(stat, value)
    SBS.db.char.stats[stat] = value
end

function SBS.Stats:SetPointsLeft(value)
    SBS.db.char.pointsLeft = math.max(0, value)
end

function SBS.Stats:Modify(stat, delta)
    local current = self:Get(stat)
    local newValue = current + delta
    local pointsLeft = self:GetPointsLeft()
    local maxStat = self:GetMaxStat()
    
    -- Проверки
    if delta > 0 and pointsLeft < delta then
        SBS.Utils:Error("Недостаточно очков!")
        return false
    end
    
    if newValue < 0 then
        SBS.Utils:Error("Характеристика не может быть отрицательной!")
        return false
    end
    
    -- Проверка лимита характеристики
    if newValue > maxStat then
        SBS.Utils:Error("Максимум в характеристику: " .. maxStat)
        return false
    end
    
    -- Применяем изменения
    self:Set(stat, newValue)
    self:SetPointsLeft(pointsLeft - delta)
    
    SBS.Events:Fire("PLAYER_STATS_CHANGED")
    
    return true
end

function SBS.Stats:AddPoint(stat)
    return self:Modify(stat, 1)
end

-- ═══════════════════════════════════════════════════════════
-- ЗДОРОВЬЕ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:GetCurrentHP()
    return SBS.db.char.currentHP or 1
end

function SBS.Stats:GetBaseHP()
    return SBS.Config:GetBaseHPForLevel(self:GetLevel())
end

function SBS.Stats:GetMaxHP()
    local baseHP = self:GetBaseHP()
    local role = self:GetRole()
    local wound = self:GetWoundPenalty()
    
    -- Бонус танка: +floor(Стойкость/2)
    local tankBonus = 0
    if role == "tank" then
        local fort = self:GetTotal("Fortitude")
        tankBonus = math.floor(fort / 2)
    end
    
    return math.max(1, baseHP + tankBonus + wound)
end

function SBS.Stats:SetCurrentHP(value)
    local maxHP = self:GetMaxHP()
    SBS.db.char.currentHP = SBS.Utils:Clamp(value, 0, maxHP)
end

function SBS.Stats:ModifyHP(delta)
    local oldHP = self:GetCurrentHP()
    local maxHP = self:GetMaxHP()
    
    -- Если получаем урон, сначала щит
    if delta < 0 then
        local damage = math.abs(delta)
        local remaining, absorbed = self:AbsorbDamage(damage)
        delta = -remaining
        
        if remaining == 0 then
            -- Весь урон поглощён щитом
            SBS.Events:FireDeferred("PLAYER_SHIELD_CHANGED", self:GetShield())
            if SBS.Sync then
                SBS.Sync:BroadcastPlayerData()
            end
            return true
        end
    end
    
    local newHP = SBS.Utils:Clamp(oldHP + delta, 0, maxHP)
    
    if newHP == oldHP then
        SBS.Utils:Warn(delta > 0 and "Здоровье на максимуме!" or "Здоровье на минимуме!")
        return false
    end
    
    self:SetCurrentHP(newHP)
    
    -- Сообщение
    local color = delta > 0 and "00FF00" or "FF0000"
    local sign = delta > 0 and "+" or ""
    SBS.Utils:Info("Здоровье: " .. SBS.Utils:Color(color, newHP .. "/" .. maxHP .. " (" .. sign .. delta .. ")"))
    
    -- Событие HP
    SBS.Events:FireDeferred("PLAYER_HP_CHANGED", newHP, maxHP)
    
    -- Проверка смерти -> ранение
    if newHP <= 0 then
        SBS.Events:Fire("PLAYER_DIED")
        self:AddWound()
    end
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:Send("PLAYERHPCHANGE", string.format("%s;%d;%d;%d", UnitName("player"), oldHP, newHP, maxHP))
        SBS.Sync:BroadcastPlayerData()
    end
    
    -- Лог мастера
    if SBS.Sync and SBS.Sync:IsMaster() and SBS.CombatLog then
        SBS.CombatLog:AddMasterLog(string.format("%s изменил здоровье: %d → %d (%+d)", 
            UnitName("player"), oldHP, newHP, delta), "hp_change")
    end
    
    return true
end

-- ═══════════════════════════════════════════════════════════
-- СБРОС
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:ResetStats()
    -- Сбрасываем все статы
    for _, stat in ipairs(SBS.Config.AllStats) do
        SBS.db.char.stats[stat] = 0
    end
    
    -- Устанавливаем очки по уровню
    self:SetPointsLeft(SBS.Config:GetPointsForLevel(self:GetLevel()))
    
    -- Восстанавливаем HP
    self:SetCurrentHP(self:GetMaxHP())
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    
    SBS.Events:Fire("PLAYER_STATS_CHANGED")
    
    SBS.Utils:Info("Характеристики сброшены")
end

function SBS.Stats:FullReset()
    -- Полный сброс (роль, ранения)
    SBS.db.char.role = nil
    SBS.db.char.specialization = nil
    SBS.db.char.wounds = 0
    SBS.db.char.shield = 0
    SBS.db.char.lastKnownLevel = self:GetLevel()
    
    self:ResetStats()
    
    SBS.Utils:Print("FFD700", "Персонаж полностью сброшен")
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Stats:PrintStats()
    local level = self:GetLevel()
    local gameLevel = self:GetGameLevel()
    
    print("|cFFFFD700=== SBS Персонаж ===|r")
    
    if gameLevel < SBS.Config.MIN_LEVEL then
        print("Уровень: |cFFFF6666" .. gameLevel .. "|r (мин. " .. SBS.Config.MIN_LEVEL .. " для системы)")
    else
        print("Уровень: |cFFFFD700" .. level .. "|r")
    end
    
    print("Роль: |cFF" .. self:GetRoleColor() .. self:GetRoleName() .. "|r")
    
    local wounds = self:GetWounds()
    if wounds > 0 then
        print("Ранения: |cFFFF6666" .. wounds .. "/" .. SBS.Config.MAX_WOUNDS .. 
            " (штраф: " .. self:GetWoundPenalty() .. ")|r")
    end
    
    local shield = self:GetShield()
    if shield > 0 then
        print("Щит: |cFF66CCFF" .. shield .. "|r")
    end
    
    print("HP: " .. self:GetCurrentHP() .. "/" .. self:GetMaxHP())
    
    for _, stat in ipairs(SBS.Config.AllStats) do
        local base = self:Get(stat)
        local wound = self:GetWoundPenalty()
        local total = self:GetTotal(stat)
        
        local suffix = ""
        if wound < 0 then 
            suffix = " (|cFFFF6666" .. wound .. "|r)"
        end
        
        print("  " .. SBS.Config.StatNames[stat] .. ": " .. total .. suffix)
    end
    
    print("Очков: |cFFFFD700" .. self:GetPointsLeft() .. "/" .. self:GetTotalPoints() .. "|r")
    
    -- Показываем следующий уровень с очком
    local nextPointLevel = nil
    for lvl, pts in pairs(SBS.Config.PointsAtLevel) do
        if lvl > level and (not nextPointLevel or lvl < nextPointLevel) then
            nextPointLevel = lvl
        end
    end
    if nextPointLevel then
        print("След. очко на уровне: |cFF66CCFF" .. nextPointLevel .. "|r")
    end
end

-- ═══════════════════════════════════════════════════════════
-- СИСТЕМА ЭНЕРГИИ
-- ═══════════════════════════════════════════════════════════

-- Получить текущую энергию
function SBS.Stats:GetEnergy()
    return SBS.db.char.energy or 0
end

-- Получить максимум энергии
function SBS.Stats:GetMaxEnergy()
    local level = self:GetLevel()
    return SBS.Config:GetMaxEnergyForLevel(level)
end

-- Установить энергию
function SBS.Stats:SetEnergy(value)
    local maxEnergy = self:GetMaxEnergy()
    local newEnergy = math.max(0, math.min(value, maxEnergy))
    SBS.db.char.energy = newEnergy

    -- Событие
    SBS.Events:Fire("PLAYER_ENERGY_CHANGED", newEnergy, maxEnergy)

    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end

    if SBS.UI and SBS.UI.UpdateMainFrame then
        SBS.UI:UpdateMainFrame()
    end
end

-- Добавить энергию
function SBS.Stats:AddEnergy(amount)
    local current = self:GetEnergy()
    local maxEnergy = self:GetMaxEnergy()
    local newEnergy = math.min(current + amount, maxEnergy)
    self:SetEnergy(newEnergy)
    
    if newEnergy > current then
        SBS.Utils:Info("+" .. (newEnergy - current) .. " энергии (" .. newEnergy .. "/" .. maxEnergy .. ")")
    end
    
    return newEnergy - current  -- Сколько реально добавлено
end

-- Потратить энергию
function SBS.Stats:SpendEnergy(amount)
    local current = self:GetEnergy()
    if current < amount then
        return false, "Недостаточно энергии!"
    end
    
    self:SetEnergy(current - amount)
    return true
end

-- Проверить, достаточно ли энергии
function SBS.Stats:HasEnergy(amount)
    return self:GetEnergy() >= amount
end

-- Восстановить энергию до максимума
function SBS.Stats:RestoreEnergy()
    local maxEnergy = self:GetMaxEnergy()
    self:SetEnergy(maxEnergy)
    SBS.Utils:Info("Энергия восстановлена: " .. maxEnergy .. "/" .. maxEnergy)
end

-- Изменить энергию (аналогично ModifyHP)
function SBS.Stats:ModifyEnergy(delta)
    local oldEnergy = self:GetEnergy()
    local maxEnergy = self:GetMaxEnergy()
    local newEnergy = math.max(0, math.min(oldEnergy + delta, maxEnergy))

    if newEnergy == oldEnergy then
        SBS.Utils:Warn(delta > 0 and "Энергия на максимуме!" or "Энергия на минимуме!")
        return false
    end

    self:SetEnergy(newEnergy)

    -- Сообщение
    local color = delta > 0 and "66CCFF" or "FF6666"
    local sign = delta > 0 and "+" or ""
    SBS.Utils:Info("Энергия: " .. SBS.Utils:Color(color, newEnergy .. "/" .. maxEnergy .. " (" .. sign .. delta .. ")"))

    -- Событие
    SBS.Events:Fire("PLAYER_ENERGY_CHANGED", newEnergy, maxEnergy)

    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end

    return true
end

-- Проверить, можно ли восстановить энергию (не в группе/рейде с лидером)
function SBS.Stats:CanRestoreEnergy()
    -- Если не в группе - можно
    if not IsInGroup() then
        return true
    end
    
    -- Если сам лидер - можно
    if UnitIsGroupLeader("player") then
        return true
    end
    
    -- В группе/рейде с другим лидером - нельзя
    return false
end

-- Проверить, можно ли изменять HP (не в группе/рейде с лидером)
function SBS.Stats:CanModifyHP()
    -- Если не в группе - можно
    if not IsInGroup() then
        return true
    end
    
    -- Если сам лидер - можно
    if UnitIsGroupLeader("player") then
        return true
    end
    
    -- В группе/рейде с другим лидером - нельзя
    return false
end

-- Получить наивысшую атакующую характеристику для особого действия
function SBS.Stats:GetHighestAttackStat()
    local stats = SBS.db.char.stats
    return SBS.Config:GetHighestAttackStat(stats)
end

-- ═══════════════════════════════════════════════════════════
-- АЛИАСЫ ДЛЯ СОВМЕСТИМОСТИ С XML
-- ═══════════════════════════════════════════════════════════

function SBS:AddPoint(stat)
    SBS.Stats:AddPoint(stat)
end

function SBS:GetTotalStat(stat)
    return SBS.Stats:GetTotal(stat)
end

function SBS:GetMaxHP()
    return SBS.Stats:GetMaxHP()
end

function SBS:ModifyPlayerHealth(delta)
    SBS.Stats:ModifyHP(delta)
end

function SBS:ResetStats()
    SBS.Stats:ResetStats()
end

function SBS:GetLevel()
    return SBS.Stats:GetLevel()
end

function SBS:GetSpecialization()
    return SBS.Stats:GetRole()
end

function SBS:GetRole()
    return SBS.Stats:GetRole()
end

function SBS:GetWounds()
    return SBS.Stats:GetWounds()
end

function SBS:GetShield()
    return SBS.Stats:GetShield()
end

function SBS:GetEnergy()
    return SBS.Stats:GetEnergy()
end

function SBS:GetMaxEnergy()
    return SBS.Stats:GetMaxEnergy()
end

function SBS:SpendEnergy(amount)
    return SBS.Stats:SpendEnergy(amount)
end

function SBS:AddEnergy(amount)
    return SBS.Stats:AddEnergy(amount)
end

function SBS:RestoreEnergy()
    return SBS.Stats:RestoreEnergy()
end
