-- SBS/Data/Effects.lua
-- Система статус-эффектов (баффы, дебаффы, DoT)

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local type = type
local next = next
local string_format = string.format
local string_match = string.match
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local table_insert = table.insert
local table_remove = table.remove
local UnitName = UnitName
local GetTime = GetTime
local IsInGroup = IsInGroup

SBS.Effects = {
    -- Активные эффекты на игроках: { [playerName] = { [effectId] = effectData, ... }, ... }
    PlayerEffects = {},
    
    -- Активные эффекты на NPC: { [guid] = { [effectId] = effectData, ... }, ... }
    NPCEffects = {},
    
    -- Кулдауны: { [casterName] = { [effectId] = remainingRounds, ... }, ... }
    Cooldowns = {},
    
    -- UI фреймы для отображения
    PlayerEffectFrames = {},
    TargetEffectFrames = {},
}

local TEX_PATH = "Interface\\AddOns\\SBS\\texture\\"

-- Fallback иконки из стандартного WoW (пока не созданы кастомные)
local FALLBACK_ICONS = {
    effect_bleeding = "Interface\\Icons\\Ability_Rogue_Rupture",           -- Периодический урон
    effect_stun = "Interface\\Icons\\Spell_Nature_Polymorph",              -- Оглушение
    effect_weakness = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",     -- Ослабление
    effect_vulnerability = "Interface\\Icons\\Ability_Warrior_Sunder",     -- Уязвимость
    effect_empower = "Interface\\Icons\\Spell_Holy_PowerWordShield",       -- Усиление
    effect_fortify = "Interface\\Icons\\Spell_Holy_DivineProtection",      -- Укрепление
    effect_regen = "Interface\\Icons\\Spell_Nature_Regeneration",          -- Регенерация
    effect_blessing = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings", -- Благословение
}

-- Кулдауны игрока: { [effectId] = expirationTime, ... }
SBS.Effects.Cooldowns = {}

-- Функция получения иконки с fallback
local function GetEffectIcon(iconPath)
    local iconName = iconPath:match("([^\\]+)$")
    if FALLBACK_ICONS[iconName] then
        return FALLBACK_ICONS[iconName]
    end
    return iconPath
end

-- ═══════════════════════════════════════════════════════════
-- ОПРЕДЕЛЕНИЕ ЭФФЕКТОВ
-- ═══════════════════════════════════════════════════════════

SBS.Effects.Definitions = {
    -- ══════════ DoT (Игрок → NPC) ══════════
    bleeding = {
        id = "bleeding",
        name = "Периодический урон",
        icon = GetEffectIcon(TEX_PATH .. "effect_bleeding"),
        type = "dot",
        category = "basic",
        targetType = "npc",
        color = {0.8, 0.1, 0.1},
        description = "Урон каждый раунд",
        fixedValue = 2,
        fixedDuration = 3,
        energyCost = 1,
    },
    
    -- ══════════ Дебаффы (Мастер → Игрок) ══════════
    stun = {
        id = "stun",
        name = "Оглушение",
        icon = GetEffectIcon(TEX_PATH .. "effect_stun"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {1, 1, 0},
        description = "Пропуск хода",
        skipTurn = true,
        -- Мастер задаёт сам
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    -- ══════════ Ослабление защитных статов NPC (игрок → NPC) ══════════
    weakness_fortitude = {
        id = "weakness_fortitude",
        name = "Ослабление (Стойкость)",
        icon = GetEffectIcon(TEX_PATH .. "effect_weakness"),
        type = "debuff",
        category = "master",
        targetType = "npc",
        color = {0.64, 0.2, 0.79},
        description = "Снижает Стойкость NPC",
        statMod = "fort",  -- используем короткий ключ как в данных NPC
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    weakness_reflex = {
        id = "weakness_reflex",
        name = "Ослабление (Сноровка)",
        icon = GetEffectIcon(TEX_PATH .. "effect_weakness"),
        type = "debuff",
        category = "master",
        targetType = "npc",
        color = {1, 0.49, 0.04},
        description = "Снижает Сноровку NPC",
        statMod = "reflex",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    weakness_will = {
        id = "weakness_will",
        name = "Ослабление (Воля)",
        icon = GetEffectIcon(TEX_PATH .. "effect_weakness"),
        type = "debuff",
        category = "master",
        targetType = "npc",
        color = {0.53, 0.53, 0.93},
        description = "Снижает Волю NPC",
        statMod = "will",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    -- ══════════ Ослабление игрока (мастер → игрок) ══════════
    weakness_damage = {
        id = "weakness_damage",
        name = "Ослабление (урон)",
        icon = GetEffectIcon(TEX_PATH .. "effect_weakness"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {0.8, 0.4, 0.4},
        description = "Снижает наносимый урон игрока",
        statMod = "damage",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    weakness_healing = {
        id = "weakness_healing",
        name = "Ослабление (лечение)",
        icon = GetEffectIcon(TEX_PATH .. "effect_weakness"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {0.6, 0.8, 0.5},
        description = "Снижает исцеление игрока",
        statMod = "healing",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    -- ══════════ Уязвимость по защитным статам (мастер → игрок) ══════════
    vulnerability_fortitude = {
        id = "vulnerability_fortitude",
        name = "Уязвимость (Стойкость)",
        icon = GetEffectIcon(TEX_PATH .. "effect_vulnerability"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {0.64, 0.2, 0.79},
        description = "Снижает Стойкость игрока",
        statMod = "fortitude",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    vulnerability_reflex = {
        id = "vulnerability_reflex",
        name = "Уязвимость (Сноровка)",
        icon = GetEffectIcon(TEX_PATH .. "effect_vulnerability"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {1, 0.49, 0.04},
        description = "Снижает Сноровку игрока",
        statMod = "reflex",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    vulnerability_will = {
        id = "vulnerability_will",
        name = "Уязвимость (Воля)",
        icon = GetEffectIcon(TEX_PATH .. "effect_vulnerability"),
        type = "debuff",
        category = "master",
        targetType = "player",
        color = {0.53, 0.53, 0.93},
        description = "Снижает Волю игрока",
        statMod = "will",
        modType = "reduce",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    dot_master = {
        id = "dot_master",
        name = "Периодический урон",
        icon = GetEffectIcon(TEX_PATH .. "effect_bleeding"),
        type = "dot",
        category = "master",
        targetType = "player",
        color = {0.8, 0.2, 0.2},
        description = "Урон от NPC каждый раунд",
        fixedValue = nil,
        fixedDuration = nil,
        energyCost = 0,
    },
    
    -- ══════════ Баффы (Игрок → Игрок) ══════════
    empower = {
        id = "empower",
        name = "Усиление",
        icon = GetEffectIcon(TEX_PATH .. "effect_empower"),
        type = "buff",
        category = "basic",
        targetType = "player",
        color = {1, 0.6, 0.2},
        description = "Увеличивает наносимый урон (+1-1)",
        statMod = "damage",
        modType = "increase",
        fixedValue = 1,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
    },
    -- Укрепление требует выбора стата, поэтому делаем 3 варианта
    fortify_fortitude = {
        id = "fortify_fortitude",
        name = "Укрепление (Стойкость)",
        icon = GetEffectIcon(TEX_PATH .. "effect_fortify"),
        type = "buff",
        category = "Tank",
        targetType = "player",
        color = {0.64, 0.2, 0.79},
        description = "+2 к Стойкости",
        statMod = "fortitude",
        modType = "increase",
        fixedValue = 2,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
        fortifyGroup = true, -- Общий кулдаун для всех fortify
    },
    fortify_reflex = {
        id = "fortify_reflex",
        name = "Укрепление (Сноровка)",
        icon = GetEffectIcon(TEX_PATH .. "effect_fortify"),
        type = "buff",
        category = "Tank",
        targetType = "player",
        color = {1, 0.49, 0.04},
        description = "+2 к Сноровке",
        statMod = "reflex",
        modType = "increase",
        fixedValue = 2,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
        fortifyGroup = true,
    },
    fortify_will = {
        id = "fortify_will",
        name = "Укрепление (Воля)",
        icon = GetEffectIcon(TEX_PATH .. "effect_fortify"),
        type = "buff",
        category = "Tank",
        targetType = "player",
        color = {0.53, 0.53, 0.93},
        description = "+2 к Воле",
        statMod = "will",
        modType = "increase",
        fixedValue = 2,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
        fortifyGroup = true,
    },
    regeneration = {
        id = "regeneration",
        name = "Регенерация",
        icon = GetEffectIcon(TEX_PATH .. "effect_regen"),
        type = "buff",
        category = "Healer",
        targetType = "player",
        color = {0.2, 0.9, 0.3},
        description = "+1 HP каждый раунд",
        isHoT = true,
        fixedValue = 1,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
    },
    blessing = {
        id = "blessing",
        name = "Благословение",
        icon = GetEffectIcon(TEX_PATH .. "effect_blessing"),
        type = "buff",
        category = "Healer",
        targetType = "player",
        color = {1, 0.95, 0.6},
        description = "Увеличивает исцеление (+1-1)",
        statMod = "healing",
        modType = "increase",
        fixedValue = 1,
        fixedDuration = 3,
        cooldownDuration = 5,
        energyCost = 1,
    },
}

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКА ДОСТУПА
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:CanApply(effectId, casterRole, casterName)
    local def = self.Definitions[effectId]
    if not def then return false, "Неизвестный эффект" end
    
    -- Master-эффекты только для мастера
    if def.category == "master" then
        if not SBS.Sync:IsMaster() then
            return false, "Только мастер может использовать этот эффект"
        end
        return true
    end
    
    -- Проверка кулдауна (для fortify группы общий кулдаун)
    local cdKey = effectId
    if def.fortifyGroup then
        cdKey = "fortify_group"
    end
    if self:IsOnCooldown(casterName or UnitName("player"), cdKey) then
        local cd = self:GetCooldown(casterName or UnitName("player"), cdKey)
        return false, "Кулдаун: " .. cd .. " раунд(ов)"
    end
    
    -- Проверка энергии
    if def.energyCost and def.energyCost > 0 then
        local currentEnergy = SBS.Stats:GetEnergy()
        if currentEnergy < def.energyCost then
            return false, "Недостаточно энергии (нужно " .. def.energyCost .. ")"
        end
    end
    
    -- Basic-эффекты доступны всем
    if def.category == "basic" then
        return true
    end
    
    -- Ролевые эффекты - проверка роли
    if def.category == casterRole then
        return true
    end
    
    -- Universal получает только basic
    if casterRole == "Universal" and def.category ~= "basic" then
        return false, "Универсал может использовать только базовые эффекты"
    end
    
    return false, "Требуется роль: " .. def.category
end

-- ═══════════════════════════════════════════════════════════
-- КУЛДАУНЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:IsOnCooldown(casterName, effectId)
    if not self.Cooldowns[casterName] then return false end
    return (self.Cooldowns[casterName][effectId] or 0) > 0
end

function SBS.Effects:GetCooldown(casterName, effectId)
    if not self.Cooldowns[casterName] then return 0 end
    return self.Cooldowns[casterName][effectId] or 0
end

function SBS.Effects:SetCooldown(casterName, effectId, rounds)
    if not self.Cooldowns[casterName] then
        self.Cooldowns[casterName] = {}
    end
    self.Cooldowns[casterName][effectId] = rounds
end

function SBS.Effects:TickCooldowns()
    for casterName, cooldowns in pairs(self.Cooldowns) do
        for effectId, remaining in pairs(cooldowns) do
            if remaining > 0 then
                cooldowns[effectId] = remaining - 1
            end
            if cooldowns[effectId] <= 0 then
                cooldowns[effectId] = nil
            end
        end
        if next(cooldowns) == nil then
            self.Cooldowns[casterName] = nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПРИМЕНЕНИЕ ЭФФЕКТОВ
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:Apply(targetType, targetId, effectId, value, duration, casterName)
    local def = self.Definitions[effectId]
    if not def then
        SBS.Utils:Error("Неизвестный эффект: " .. effectId)
        return false
    end
    
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    casterName = casterName or UnitName("player")
    
    -- Создаём хранилище для цели если нет
    if not storage[targetId] then
        storage[targetId] = {}
    end
    
    -- Для игроков используем фиксированные значения (если не мастер или мастер-участник боя)
    local isMaster = SBS.Sync:IsMaster()
    local isMasterParticipant = isMaster and SBS.TurnSystem and SBS.TurnSystem:IsParticipant()
    local hasPlayerLimits = not isMaster or isMasterParticipant
    
    local finalValue = value
    local finalDuration = duration
    
    if hasPlayerLimits and def.fixedValue then
        finalValue = def.fixedValue
    end
    if hasPlayerLimits and def.fixedDuration then
        finalDuration = def.fixedDuration
    end
    
    -- Проверяем, не висит ли уже такой эффект
    local existingEffect = storage[targetId][effectId]
    if existingEffect then
        -- Проверяем, есть ли этот кастер уже в списке
        local casterExists = false
        if existingEffect.casters then
            for _, c in ipairs(existingEffect.casters) do
                if c == casterName then
                    casterExists = true
                    break
                end
            end
        elseif existingEffect.caster == casterName then
            casterExists = true
        end
        
        if casterExists then
            SBS.Utils:Warn(def.name .. " уже наложен вами на эту цель")
            return false
        end

        -- Стакаем эффект от другого игрока
        if not existingEffect.casters then
            -- Конвертируем старый формат в новый
            existingEffect.casters = { existingEffect.caster }
            existingEffect.caster = nil
        end
        table.insert(existingEffect.casters, casterName)
        existingEffect.stacks = (existingEffect.stacks or 1) + 1
        existingEffect.value = (existingEffect.value or 0) + finalValue
        -- Обновляем длительность до максимальной
        if finalDuration > existingEffect.remainingRounds then
            existingEffect.remainingRounds = finalDuration
        end

        -- Тратим энергию
        if hasPlayerLimits and def.energyCost and def.energyCost > 0 then
            if not SBS.Stats:SpendEnergy(def.energyCost) then
                -- Откатываем изменения
                table.remove(existingEffect.casters)
                existingEffect.stacks = existingEffect.stacks - 1
                existingEffect.value = existingEffect.value - finalValue
                SBS.Utils:Error("Недостаточно энергии!")
                return false
            end
        end

        -- Устанавливаем кулдаун
        if hasPlayerLimits then
            local cooldownRounds = def.cooldownDuration or 5
            local cdKey = def.fortifyGroup and "fortify_group" or effectId
            self:SetCooldown(casterName, cdKey, cooldownRounds)
        end

        -- Логируем
        local targetName = targetType == "npc" and (SBS.Units:Get(targetId) and SBS.Units:Get(targetId).name or "NPC") or targetId
        SBS.Utils:Info(string.format("%s усилен на %s (стаки: %d)",
            SBS.Utils:Color(self:GetColorHex(def.color), def.name),
            SBS.Utils:Color("FFFFFF", targetName),
            existingEffect.stacks))

        -- Синхронизация
        if SBS.Sync and IsInGroup() then
            local castersStr = table.concat(existingEffect.casters, ",")
            SBS.Sync:Send("EFFECT_STACK", string.format("%s;%s;%s;%d;%d;%d;%s",
                targetType, targetId, effectId, existingEffect.value, existingEffect.remainingRounds, existingEffect.stacks, castersStr))
        end
        
        SBS.Events:Fire("EFFECT_APPLIED", targetType, targetId, effectId)
        if SBS.UI.Effects then
            SBS.UI.Effects:UpdateAll()
        end
        return true
    end
    
    -- Тратим энергию (для игроков и мастера-участника)
    if hasPlayerLimits and def.energyCost and def.energyCost > 0 then
        if not SBS.Stats:SpendEnergy(def.energyCost) then
            SBS.Utils:Error("Недостаточно энергии!")
            return false
        end
    end

    -- Применяем новый эффект
    storage[targetId][effectId] = {
        id = effectId,
        value = finalValue,
        duration = finalDuration,
        remainingRounds = finalDuration,
        casters = { casterName },
        stacks = 1,
        appliedAt = GetTime(),
    }

    -- Устанавливаем кулдаун (для игроков и мастера-участника)
    if hasPlayerLimits then
        local cooldownRounds = def.cooldownDuration or 5
        local cdKey = def.fortifyGroup and "fortify_group" or effectId
        self:SetCooldown(casterName, cdKey, cooldownRounds)
    end

    -- Логируем
    local targetName = targetType == "npc" and (SBS.Units:Get(targetId) and SBS.Units:Get(targetId).name or "NPC") or targetId
    SBS.Utils:Info(string.format("%s наложен на %s (%d раундов, %d)",
        SBS.Utils:Color(self:GetColorHex(def.color), def.name),
        SBS.Utils:Color("FFFFFF", targetName),
        finalDuration,
        finalValue))

    -- Лог в бой (броадкаст всем)
    if SBS.Sync then
        SBS.Sync:BroadcastCombatLog(string.format("%s накладывает %s на %s",
            casterName, def.name, targetName))
    end

    -- Отправляем синхронизацию
    if SBS.Sync and IsInGroup() then
        SBS.Sync:Send("EFFECT_APPLY", string.format("%s;%s;%s;%d;%d;%s",
            targetType, targetId, effectId, finalValue, finalDuration, casterName))
    end
    
    -- Обновляем UI
    SBS.Events:Fire("EFFECT_APPLIED", targetType, targetId, effectId)
    if SBS.UI.Effects then
        SBS.UI.Effects:UpdateAll()
    end
    
    return true
end

-- Применение эффекта игроком (использует фиксированные значения)
function SBS.Effects:PlayerApply(targetType, targetId, effectId)
    local def = self.Definitions[effectId]
    if not def then return false end
    
    -- Проверка пошагового режима - игрок должен иметь право действовать
    if SBS.TurnSystem and SBS.TurnSystem:IsActive() and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return false
    end
    
    local casterName = UnitName("player")
    local casterRole = SBS.Stats:GetRole() or "Universal"
    
    -- Проверяем доступность
    local canApply, reason = self:CanApply(effectId, casterRole, casterName)
    if not canApply then
        SBS.Utils:Error(reason)
        return false
    end
    
    -- Применяем с фиксированными значениями
    local success = self:Apply(targetType, targetId, effectId, def.fixedValue, def.fixedDuration, casterName)
    
    if success then
        -- Оповещаем пошаговую систему о завершении действия
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
    end
    
    return success
end

-- Применение эффекта мастером (кастомные значения)
function SBS.Effects:MasterApply(targetType, targetId, effectId, value, duration)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может использовать эту функцию")
        return false
    end
    
    -- Мастер может накладывать эффекты в любое время (это мастерское действие, не игровое)
    local success = self:Apply(targetType, targetId, effectId, value, duration, UnitName("player"))
    
    return success
end

-- Применение ослабления NPC игроком (специальная функция)
-- Игрок выбирает стат (fortitude/reflex/will), значение случайное 1-3, длительность 3 раунда
function SBS.Effects:PlayerApplyWeaken(npcGuid, effectId, value, duration)
    local def = self.Definitions[effectId]
    if not def then 
        SBS.Utils:Error("Неизвестный эффект: " .. effectId)
        return false 
    end
    
    -- Проверка пошагового режима
    if SBS.TurnSystem and SBS.TurnSystem:IsActive() and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return false
    end
    
    local casterName = UnitName("player")
    
    -- Проверка энергии
    local currentEnergy = SBS.Stats:GetEnergy()
    if currentEnergy < 1 then
        SBS.Utils:Error("Недостаточно энергии!")
        return false
    end
    
    -- Проверка кулдауна (используем базовый effectId "weakness" для общего кулдауна)
    if self:IsOnCooldown(casterName, "weakness") then
        local cd = self:GetCooldown(casterName, "weakness")
        SBS.Utils:Error("Ослабление на кулдауне ещё " .. cd .. " раунд(ов)")
        return false
    end
    
    -- Проверка что эффект ещё не висит
    if self:HasEffect("npc", npcGuid, effectId) then
        SBS.Utils:Error(def.name .. " уже активно на этой цели")
        return false
    end
    
    -- Применяем эффект
    local success = self:Apply("npc", npcGuid, effectId, value, duration, casterName)
    
    if success then
        -- Тратим энергию
        SBS.Stats:SpendEnergy(1)
        
        -- Ставим кулдаун на "weakness" (общий для всех типов ослабления игроком)
        self:SetCooldown(casterName, "weakness", 5)
        
        -- Броадкастим в журнал боя
        local npcData = SBS.Units:Get(npcGuid)
        local targetName = npcData and npcData.name or "NPC"
        local logMessage = string.format("%s накладывает |cFF%s%s|r (-%d) на %s на %d раунда",
            casterName, self:GetColorHex(def.color), def.name, value, targetName, duration)
        if SBS.Sync then
            SBS.Sync:BroadcastCombatLog(logMessage)
        end
        
        -- Оповещаем пошаговую систему
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
    end
    
    return success
end

function SBS.Effects:Remove(targetType, targetId, effectId, silent)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    
    if not storage[targetId] or not storage[targetId][effectId] then
        return false
    end
    
    local def = self.Definitions[effectId]
    storage[targetId][effectId] = nil
    
    -- Очищаем пустые таблицы
    if next(storage[targetId]) == nil then
        storage[targetId] = nil
    end
    
    if not silent then
        local targetName = targetType == "npc" and (SBS.Units:Get(targetId) and SBS.Units:Get(targetId).name or "NPC") or targetId
        SBS.Utils:Info(def.name .. " снят с " .. SBS.Utils:Color("FFFFFF", targetName))
    end
    
    -- Синхронизация
    if SBS.Sync and IsInGroup() then
        SBS.Sync:Send("EFFECT_REMOVE", string.format("%s;%s;%s", targetType, targetId, effectId))
    end
    
    -- Обновляем UI
    SBS.Events:Fire("EFFECT_REMOVED", targetType, targetId, effectId)
    
    return true
end

-- Снятие всех эффектов с цели
function SBS.Effects:ClearAll(targetType, targetId)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    
    if storage[targetId] then
        for effectId, _ in pairs(storage[targetId]) do
            self:Remove(targetType, targetId, effectId, true)
        end
    end
    
    SBS.Events:Fire("EFFECTS_CLEARED", targetType, targetId)
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА РАУНДА
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:ProcessRound(targetType, targetId)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    
    if not storage[targetId] then return end
    
    -- Для NPC проверяем что цель жива
    if targetType == "npc" then
        local npc = SBS.Units:Get(targetId)
        if not npc or npc.hp <= 0 then
            return
        end
    end
    
    local toRemove = {}
    
    for effectId, effectData in pairs(storage[targetId]) do
        local def = self.Definitions[effectId]
        
        -- Применяем эффект раунда (только фиксированный урон без модификаторов)
        if def.type == "dot" then
            -- Берём фиксированное значение из определения, игнорируя effectData.value
            local fixedDamage = def.fixedValue or effectData.value
            self:ApplyDamage(targetType, targetId, fixedDamage, def.name)
        elseif def.isHoT then
            -- Лечим
            self:ApplyHealing(targetType, targetId, effectData.value)
        end
        
        -- Уменьшаем длительность (кроме эффектов skipTurn - они тикают при пропуске хода)
        if not def.skipTurn then
            effectData.remainingRounds = effectData.remainingRounds - 1
            
            if effectData.remainingRounds <= 0 then
                table.insert(toRemove, effectId)
            end
        end
    end
    
    -- Удаляем истёкшие эффекты
    for _, effectId in ipairs(toRemove) do
        self:Remove(targetType, targetId, effectId)
    end
end

-- Обработка всех эффектов в начале раунда
function SBS.Effects:ProcessAllEffects()
    -- Обрабатываем эффекты на NPC
    for guid, _ in pairs(self.NPCEffects) do
        self:ProcessRound("npc", guid)
    end
    
    -- Обрабатываем эффекты на игроках
    for playerName, _ in pairs(self.PlayerEffects) do
        self:ProcessRound("player", playerName)
    end
    
    -- Тикаем кулдауны
    self:TickCooldowns()
    
    -- Синхронизируем состояние всех эффектов с клиентами
    if SBS.Sync and SBS.Sync:IsMaster() and IsInGroup() then
        self:BroadcastAllEffects()
    end
    
    -- Обновляем UI
    if SBS.UI.Effects then
        SBS.UI.Effects:UpdateAll()
    end
end

-- Синхронизация всех эффектов с клиентами
function SBS.Effects:BroadcastAllEffects()
    -- Синхронизируем эффекты на NPC
    for guid, effects in pairs(self.NPCEffects) do
        for effectId, effectData in pairs(effects) do
            local castersStr = ""
            if effectData.casters then
                castersStr = table.concat(effectData.casters, ",")
            elseif effectData.caster then
                castersStr = effectData.caster
            end
            SBS.Sync:Send("EFFECT_SYNC", string.format("npc;%s;%s;%d;%d;%s",
                guid, effectId, effectData.value or 0, effectData.remainingRounds or 0, castersStr))
        end
    end
    
    -- Синхронизируем эффекты на игроках
    for playerName, effects in pairs(self.PlayerEffects) do
        for effectId, effectData in pairs(effects) do
            local castersStr = ""
            if effectData.casters then
                castersStr = table.concat(effectData.casters, ",")
            elseif effectData.caster then
                castersStr = effectData.caster
            end
            SBS.Sync:Send("EFFECT_SYNC", string.format("player;%s;%s;%d;%d;%s",
                playerName, effectId, effectData.value or 0, effectData.remainingRounds or 0, castersStr))
        end
    end
end

function SBS.Effects:ApplyDamage(targetType, targetId, damage, sourceName)
    if targetType == "npc" then
        local npc = SBS.Units:Get(targetId)
        if npc and npc.hp > 0 then
            -- DoT не может убить NPC напрямую - оставляем минимум 1 HP
            local newHP = npc.hp - damage
            if newHP < 1 then
                newHP = 1
            end
            local actualDamage = npc.hp - newHP
            
            if actualDamage > 0 then
                SBS.Units:ModifyHP(targetId, newHP)
                if SBS.Sync then
                    SBS.Sync:BroadcastCombatLog(string.format("%s получает %d урона от %s. HP: %d/%d",
                        npc.name, actualDamage, sourceName, newHP, npc.maxHp))
                end
            end
        end
    else
        -- Игрок: мастер синхронизирует через ModifyPlayerHP (обрабатывает и локальное применение)
        if SBS.Sync:IsMaster() then
            SBS.Sync:ModifyPlayerHP(targetId, -damage)
            SBS.Sync:BroadcastCombatLog(string.format("%s получает %d урона от %s",
                targetId, damage, sourceName))
        elseif targetId == UnitName("player") then
            -- Не мастер, но цель — текущий игрок (fallback)
            SBS.Stats:ModifyHP(-damage)
        end
    end
end

function SBS.Effects:ApplyHealing(targetType, targetId, amount)
    if targetType == "player" then
        -- Мастер синхронизирует через ModifyPlayerHP (обрабатывает и локальное применение)
        if SBS.Sync:IsMaster() then
            SBS.Sync:ModifyPlayerHP(targetId, amount)
            SBS.Sync:BroadcastCombatLog(string.format("%s восстанавливает %d HP",
                targetId, amount))
        elseif targetId == UnitName("player") then
            -- Не мастер, но цель — текущий игрок (fallback)
            SBS.Stats:ModifyHP(amount)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ ДАННЫХ
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:Get(targetType, targetId, effectId)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    if storage[targetId] then
        return storage[targetId][effectId]
    end
    return nil
end

function SBS.Effects:GetAll(targetType, targetId)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    return storage[targetId] or {}
end

function SBS.Effects:HasEffect(targetType, targetId, effectId)
    return self:Get(targetType, targetId, effectId) ~= nil
end

function SBS.Effects:IsStunned(playerName)
    local effect = self:Get("player", playerName, "stun")
    return effect ~= nil
end

-- Проверка оглушения NPC (по GUID)
function SBS.Effects:IsNPCStunned(npcGuid)
    local effect = self:Get("npc", npcGuid, "stun")
    return effect ~= nil
end

-- Тикнуть оглушение при пропуске хода
function SBS.Effects:TickStun(playerName)
    local effect = self:Get("player", playerName, "stun")
    if effect then
        effect.remainingRounds = effect.remainingRounds - 1
        if effect.remainingRounds <= 0 then
            self:Remove("player", playerName, "stun")
        end
        -- Синхронизируем
        if SBS.Sync and SBS.Sync:IsMaster() and IsInGroup() then
            self:BroadcastAllEffects()
        end
    end
end

-- Тикнуть оглушение NPC
function SBS.Effects:TickNPCStun(npcGuid)
    local effect = self:Get("npc", npcGuid, "stun")
    if effect then
        effect.remainingRounds = effect.remainingRounds - 1
        if effect.remainingRounds <= 0 then
            self:Remove("npc", npcGuid, "stun")
            local npcData = SBS.Units:Get(npcGuid)
            local npcName = npcData and npcData.name or "НПЦ"
            SBS.Utils:Info("|cFFFFFF00" .. npcName .. "|r больше не оглушен!")
        end
        -- Синхронизируем
        if SBS.Sync and SBS.Sync:IsMaster() and IsInGroup() then
            self:BroadcastAllEffects()
        end
    end
end

-- Получить модификатор от эффектов
function SBS.Effects:GetModifier(targetType, targetId, statType)
    local effects = self:GetAll(targetType, targetId)
    local modifier = 0

    for effectId, effectData in pairs(effects) do
        local def = self.Definitions[effectId]
        if def and def.statMod == statType then
            local value = effectData.value or 0
            if def.modType == "increase" then
                modifier = modifier + value
            elseif def.modType == "reduce" then
                modifier = modifier - value
            end
        end
    end

    return modifier
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:GetColorHex(color)
    return string.format("%02X%02X%02X", 
        math.floor(color[1] * 255),
        math.floor(color[2] * 255),
        math.floor(color[3] * 255))
end

-- Получить список доступных эффектов для роли
function SBS.Effects:GetAvailable(role, targetType)
    local available = {}
    local casterName = UnitName("player")
    
    for effectId, def in pairs(self.Definitions) do
        -- Проверяем тип цели
        if def.targetType == targetType or def.targetType == "any" then
            -- Проверяем доступность по роли (без проверки кулдауна/энергии)
            local categoryOk = false
            if def.category == "master" then
                categoryOk = SBS.Sync:IsMaster()
            elseif def.category == "basic" then
                categoryOk = true
            elseif def.category == role then
                categoryOk = true
            end
            
            if categoryOk then
                -- Добавляем информацию о кулдауне (для fortify группы общий кулдаун)
                local cdKey = def.fortifyGroup and "fortify_group" or effectId
                local onCooldown = self:IsOnCooldown(casterName, cdKey)
                local cdRemaining = self:GetCooldown(casterName, cdKey)

                table.insert(available, {
                    def = def,
                    onCooldown = onCooldown,
                    cooldownRemaining = cdRemaining,
                })
            end
        end
    end
    
    return available
end

-- Получить список мастерских эффектов
function SBS.Effects:GetMasterEffects()
    local effects = {}
    for effectId, def in pairs(self.Definitions) do
        if def.category == "master" then
            table.insert(effects, def)
        end
    end
    return effects
end

-- ═══════════════════════════════════════════════════════════
-- ДИСПЕЛ (СНЯТИЕ ЭФФЕКТОВ ХИЛЕРОМ)
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:Dispel(targetName, casterRole)
    -- Только хилер может диспелить
    if casterRole ~= "Healer" then
        SBS.Utils:Error("Только Healer может снимать дебаффы")
        return false
    end
    
    -- Проверка энергии
    local currentEnergy = SBS.Stats:GetEnergy()
    if currentEnergy < 1 then
        SBS.Utils:Error("Недостаточно энергии для диспела")
        return false
    end
    
    local effects = self:GetAll("player", targetName)
    local dispelled = false
    
    for effectId, _ in pairs(effects) do
        local def = self.Definitions[effectId]
        if def.type == "debuff" or (def.type == "dot" and def.category == "master") then
            self:Remove("player", targetName, effectId)
            dispelled = true
            break -- Снимаем один эффект за раз
        end
    end
    
    if dispelled then
        SBS.Stats:SpendEnergy(1)
        SBS.Utils:Info("Снят дебафф с " .. SBS.Utils:Color("FFFFFF", targetName))
        if SBS.Sync then
            SBS.Sync:BroadcastCombatLog(UnitName("player") .. " снимает дебафф с " .. targetName)
        end
        -- Диспел засчитывается как ход
        if SBS.TurnSystem and SBS.TurnSystem:IsActive() then
            SBS.TurnSystem:OnActionPerformed()
        end
        return true
    else
        SBS.Utils:Warn("Нет дебаффов для снятия")
        return false
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПУРЖ (СНЯТИЕ БАФФОВ МАСТЕРОМ)
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:Purge(targetName)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может снимать баффы")
        return false
    end
    
    local effects = self:GetAll("player", targetName)
    local purged = false
    
    for effectId, _ in pairs(effects) do
        local def = self.Definitions[effectId]
        if def.type == "buff" then
            self:Remove("player", targetName, effectId)
            purged = true
            break
        end
    end
    
    if purged then
        SBS.Utils:Info("Снят бафф с " .. SBS.Utils:Color("FFFFFF", targetName))
        return true
    else
        SBS.Utils:Warn("Нет баффов для снятия")
        return false
    end
end

-- ═══════════════════════════════════════════════════════════
-- СИНХРОНИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Effects:Serialize()
    local data = {
        players = self.PlayerEffects,
        npcs = self.NPCEffects,
    }
    return SBS.Utils:TableToString(data)
end

function SBS.Effects:Deserialize(data)
    local parsed = SBS.Utils:StringToTable(data)
    if parsed then
        self.PlayerEffects = parsed.players or {}
        self.NPCEffects = parsed.npcs or {}
        SBS.Events:Fire("EFFECTS_SYNCED")
    end
end

-- Очистка всех эффектов на цели
function SBS.Effects:ClearTarget(targetType, targetId)
    local storage = targetType == "npc" and self.NPCEffects or self.PlayerEffects
    
    if storage[targetId] then
        -- Собираем список эффектов для удаления
        local toRemove = {}
        for effectId, _ in pairs(storage[targetId]) do
            table.insert(toRemove, effectId)
        end
        
        -- Удаляем каждый эффект
        for _, effectId in ipairs(toRemove) do
            self:Remove(targetType, targetId, effectId)
        end
    end
    
    -- Синхронизируем
    if SBS.Sync and IsInGroup() then
        SBS.Sync:Send("EFFECTS_CLEAR_TARGET", targetType .. ";" .. targetId)
    end
    
    -- Обновляем UI
    SBS.Events:Fire("EFFECTS_CLEARED", targetType, targetId)
end
