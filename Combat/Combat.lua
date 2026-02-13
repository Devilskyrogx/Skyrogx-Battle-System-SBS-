-- SBS/Combat/Combat.lua
-- Боевая система: атаки, защита, исцеление, щит

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local math_random = math.random
local math_max = math.max
local math_min = math.min
local string_format = string.format
local GetTime = GetTime
local UnitName = UnitName
local UnitGUID = UnitGUID
local PlaySound = PlaySound

SBS.Combat = {
    AttackingNPC = nil,  -- { guid = "...", name = "..." }
    
    -- Состояние AoE атаки
    AoEState = {
        active = false,      -- Режим AoE активен
        stat = nil,          -- Атакующая стата
        hitsLeft = 0,        -- Осталось ударов
        hitTargets = {},     -- GUID уже атакованных целей
    },
    
    -- Состояние AoE исцеления
    AoEHealState = {
        active = false,      -- Режим AoE хила активен
        healsLeft = 0,       -- Осталось исцелений
        healedTargets = {},  -- Имена уже исцелённых целей
    },
    
    -- Ожидающие атаки на игроков (защита от повторных атак)
    PendingAttacks = {},  -- { [playerName] = timestamp }
    PENDING_TIMEOUT = 60, -- Таймаут pending атаки в секундах

    -- Система особого действия
    PendingSpecialAction = nil,  -- { playerName = "...", description = "...", timestamp = 123.45 }
    RejectedSpecialActions = {}, -- { [playerName] = roundNumber }
}

-- ═══════════════════════════════════════════════════════════
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ═══════════════════════════════════════════════════════════

-- Проверка 50/50 при равенстве броска и порога
function SBS.Combat:Check5050(total, threshold)
    if total == threshold then
        return math_random(1, 2) == 1
    end
    return total > threshold
end

-- Определение успеха с учётом 50/50
function SBS.Combat:IsSuccess(total, threshold)
    if total > threshold then
        return true
    elseif total < threshold then
        return false
    else
        return self:Check5050(total, threshold)
    end
end

-- Расчёт урона с учётом уровня и роли
function SBS.Combat:CalculateDamage(isCrit)
    local level = SBS.Stats:GetLevel()
    local role = SBS.Stats:GetRole()
    local range = SBS.Config:GetDamageRange(level, role)
    
    local damage = SBS.Utils:Roll(range.min, range.max)
    
    if isCrit then
        damage = damage + 1
    end
    
    return damage
end

-- Расчёт исцеления с учётом уровня и роли
function SBS.Combat:CalculateHealing(isCrit)
    local level = SBS.Stats:GetLevel()
    local role = SBS.Stats:GetRole()
    local range = SBS.Config:GetHealingRange(level, role)
    
    local heal = SBS.Utils:Roll(range.min, range.max)
    
    if isCrit then
        heal = heal + 1
    end
    
    return heal
end

-- Форматирование результата броска
function SBS.Combat:FormatRollResult(attackerName, statName, targetName, total, roll, modifier, threshold, isSuccess, resultText)
    local compareSign = isSuccess and ">=" or "<="
    local resultColor = isSuccess and "00FF00" or "FF6666"
    local statColor = SBS.Config.StatColors[statName] or "FFFFFF"
    
    local line1 = string.format("%s использует %s против %s.",
        attackerName,
        SBS.Utils:Color(statColor, SBS.Config.StatNames[statName] or statName),
        targetName)
    
    local line2 = string.format("Результат: %s (%d+%d) %s %d - %s",
        SBS.Utils:Color("FFFF00", total),
        roll, modifier,
        compareSign,
        threshold,
        SBS.Utils:Color(resultColor, resultText))
    
    return line1, line2
end

-- ═══════════════════════════════════════════════════════════
-- АТАКУЮЩИЙ NPC (для мастера)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:SetAttackingNPC()
    local guid, name = SBS.Utils:GetTargetGUID()
    
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите NPC, а не игрока!")
        return
    end
    
    self.AttackingNPC = {
        guid = guid,
        name = name,
    }
    
    SBS.Utils:Info("Атакующий NPC: " .. SBS.Utils:Color("FF6666", name))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Назначен атакующий NPC: " .. name, "master_action")
    end
end

function SBS.Combat:GetAttackingNPCName()
    if self.AttackingNPC then
        return self.AttackingNPC.name
    end
    return "NPC"
end

function SBS.Combat:ClearAttackingNPC()
    self.AttackingNPC = nil
    SBS.Utils:Info("Атакующий NPC сброшен")
end

-- ═══════════════════════════════════════════════════════════
-- АТАКА ИГРОКА ПО NPC
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:Attack(stat)
    -- Проверка AoE режима
    if self:IsAoEActive() then
        SBS.Utils:Error("Сначала завершите AoE атаку!")
        return
    end
    
    if self:IsAoEHealActive() then
        SBS.Utils:Error("Сначала завершите AoE исцеление!")
        return
    end
    
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя атаковать игроков!")
        return
    end
    
    local data = SBS.Units:Get(guid)
    if not data then
        SBS.Utils:Error("У цели не установлен HP!")
        return
    end
    
    if data.hp <= 0 then
        SBS.Utils:Error("Цель мертва!")
        return
    end
    
    -- Бросок атаки
    local modifier = SBS.Stats:GetTotal(stat)
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    
    -- Определяем порог защиты
    local defenseStat = SBS.Config.AttackVsDefense[stat]
    local defenseKey = defenseStat == "Fortitude" and "fort" or 
                       (defenseStat == "Reflex" and "reflex" or "will")
    local baseThreshold = data[defenseKey] or 10
    
    -- Учитываем эффекты ослабления защиты на NPC
    local effectMod = SBS.Effects:GetModifier("npc", guid, defenseKey)
    local threshold = math_max(1, baseThreshold + effectMod)
    
    -- Результат
    local damage = 0
    local resultText = ""
    local isSuccess = false
    local isCrit = false
    local floatType = "miss"
    
    if roll == 1 then
        isSuccess = false
        resultText = "крит. провал"
        floatType = "crit_fail"
    elseif roll == 20 then
        isSuccess = true
        isCrit = true
        -- Базовый урон без +3 бонуса (игрок выберет в меню)
        damage = self:CalculateDamage(false)
        resultText = "крит. успех"
        floatType = "crit_success"
    else
        isSuccess = self:IsSuccess(total, threshold)
        if isSuccess then
            damage = self:CalculateDamage(false)
            resultText = "удачно"
            floatType = "hit"
        else
            resultText = "неудачно"
            floatType = "miss"
        end
    end
    
    -- Форматируем вывод
    local playerName = UnitName("player")
    local line1, line2 = self:FormatRollResult(playerName, stat, name, total, roll, modifier, threshold, isSuccess, resultText)
    
    -- Добавляем информацию об уроне (пока базовый)
    if damage > 0 then
        line2 = line2 .. " Урон: " .. SBS.Utils:Color("FF6666", damage)
    end
    
    -- Лог боя (отправляем всем через Sync, включая себя)
    SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
    
    -- Всплывающий текст
    if SBS.UI then
        SBS.UI:ShowAttackResult(name, floatType, damage)
    end
    
    -- При крите - показываем меню выбора
    if isCrit and damage > 0 then
        SBS.Dialogs:ShowCritChoiceMenu("attack", function(choice, finalDamage, targetGuid, targetName)
            self:ApplyCritAttackChoice(choice, finalDamage, targetGuid, targetName)
        end, damage, guid, name)
    elseif damage > 0 then
        -- Обычный урон - применяем сразу
        local newHP = math.max(0, data.hp - damage)
        SBS.Units:ModifyHP(guid, newHP)

        -- Убрано дублирующееся сообщение "получает Х урона! HP:"
        -- Информация уже выведена в line1 и line2 выше

        if newHP <= 0 then
            SBS.Utils:Print("FF0000", name .. " — цель мертва!")
        else
            -- Механика бойца: 50% шанс на добивание после успешной атаки
            if SBS.Stats:GetRole() == "dd" then
                self:ProcessDDFinisherBonus(guid, name, newHP, data.maxHp)
            end
        end
    end
    
    -- Оповещаем пошаговую систему (при крите это делается после выбора в меню)
    if SBS.TurnSystem and not isCrit then
        SBS.TurnSystem:OnActionPerformed()
    end


end

-- Применить выбор крита при атаке
function SBS.Combat:ApplyCritAttackChoice(choice, baseDamage, targetGuid, targetName)
    local data = SBS.Units:Get(targetGuid)
    if not data then
        -- Даже если цель не найдена, завершаем ход
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    end

    local finalDamage = baseDamage

    if choice == "bonus_damage" then
        -- +3 к урону
        finalDamage = baseDamage + 3
        SBS.Utils:Info("Крит: +" .. SBS.Utils:Color("FF6666", "3 урона") .. "!")
    elseif choice == "energy" then
        -- Энергия уже добавлена в меню
        SBS.Utils:Info("Крит: +" .. SBS.Utils:Color("9966FF", "1 энергия") .. "!")
    elseif choice == "full_heal" then
        -- Полное исцеление цели (Целитель)
        local maxHP = data.maxHp or 10
        SBS.Units:ModifyHP(targetGuid, maxHP)
        SBS.Utils:Info("Крит: Цель " .. SBS.Utils:Color("66FF66", "полностью исцелена") .. "!")
        -- Завершаем ход (не наносим урон)
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    elseif choice == "shield" then
        -- Щит уже добавлен в меню
        SBS.Utils:Info("Крит: +" .. SBS.Utils:Color("66CCFF", "3 щита") .. "!")
    end

    -- Применяем урон
    local newHP = math.max(0, data.hp - finalDamage)
    SBS.Units:ModifyHP(targetGuid, newHP)

    SBS.Utils:Warn(targetName .. " получает " .. SBS.Utils:Color("FF0000", finalDamage) ..
        " урона! HP: " .. SBS.Utils:Color("FF0000", newHP .. "/" .. data.maxHp))

    if newHP <= 0 then
        SBS.Utils:Print("FF0000", targetName .. " — цель мертва!")
    end

    -- Оповещаем пошаговую систему о завершении хода
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
end

-- ═══════════════════════════════════════════════════════════
-- AoE АТАКА
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:StartAoEAttack(stat)
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    -- Нельзя начать AoE если уже в режиме AoE
    if self.AoEState.active then
        SBS.Utils:Error("AoE атака уже активна!")
        return
    end
    
    -- Проверка энергии
    local energyCost = SBS.Config.ENERGY_COST_AOE
    if not SBS.Stats:HasEnergy(energyCost) then
        SBS.Utils:Error("Недостаточно энергии! Нужно: " .. energyCost)
        return
    end
    
    -- Тратим энергию
    SBS.Stats:SpendEnergy(energyCost)
    
    -- Бросок на успех AoE (порог из конфига)
    local modifier = SBS.Stats:GetTotal(stat)
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    local threshold = SBS.Config.AOE_THRESHOLD
    local maxTargets = SBS.Config.AOE_MAX_TARGETS
    
    local playerName = UnitName("player")
    local statColor = SBS.Config.StatColors[stat] or "FFFFFF"
    local statName = SBS.Config.StatNames[stat] or stat
    
    -- Крит провал (1) — просто промах
    if roll == 1 then
        local line1 = string.format("%s пытается использовать AoE %s.",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) < %d - %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("FF6666", "крит. провал"))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        -- Ход тратится
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    end
    
    -- Проверка успеха
    local isSuccess = total >= threshold
    
    if not isSuccess then
        local line1 = string.format("%s пытается использовать AoE %s.",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) < %d - %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("FF6666", "промах"))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        -- Ход тратится
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    end
    
    -- Успех! Количество целей = максимум из конфига
    local targets = maxTargets
    
    -- Крит (20) — выбор игрока (энергия или бонус)
    if roll == 20 then
        local line1 = string.format("%s активирует AoE %s!",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) >= %d - %s! Целей: %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("00FF00", "крит. успех"),
            SBS.Utils:Color("FFD700", targets))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        -- Возвращаем энергию за крит
        SBS.Stats:AddEnergy(SBS.Config.ENERGY_GAIN_CRIT_CHOICE)
    else
        local line1 = string.format("%s активирует AoE %s!",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) >= %d - %s Целей: %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("00FF00", "успех!"),
            SBS.Utils:Color("FFD700", targets))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
    end
    
    -- Активируем режим AoE
    self.AoEState.active = true
    self.AoEState.stat = stat
    self.AoEState.hitsLeft = targets
    self.AoEState.hitTargets = {}
    
    SBS.Utils:Info("AoE режим активен! Выберите " .. SBS.Utils:Color("FFD700", targets) .. " целей.")
    
    -- Обновляем UI

    
    -- Показываем окно AoE
    if SBS.UI and SBS.UI.ShowAoEPanel then
        SBS.UI:ShowAoEPanel()
    end
end

function SBS.Combat:AoEHit()
    -- Проверка режима AoE
    if not self.AoEState.active then
        SBS.Utils:Error("AoE режим не активен!")
        return
    end
    
    if self.AoEState.hitsLeft <= 0 then
        SBS.Utils:Error("Все удары использованы!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя атаковать игроков!")
        return
    end
    
    -- Проверка на повторную атаку
    if self.AoEState.hitTargets[guid] then
        SBS.Utils:Error("Эта цель уже атакована! Выберите другую.")
        return
    end
    
    local data = SBS.Units:Get(guid)
    if not data then
        SBS.Utils:Error("У цели не установлен HP!")
        return
    end
    
    if data.hp <= 0 then
        SBS.Utils:Error("Цель мертва!")
        return
    end
    
    -- AoE удар автоматически успешен, но бросаем на крит и урон
    local stat = self.AoEState.stat
    local roll = SBS.Utils:Roll(1, 20)
    local isCrit = (roll == 20)
    local damage = self:CalculateDamage(isCrit)
    
    local playerName = UnitName("player")
    local statColor = SBS.Config.StatColors[stat] or "FFFFFF"
    local statName = SBS.Config.StatNames[stat] or stat
    
    local resultText = isCrit and SBS.Utils:Color("00FF00", "крит!") or SBS.Utils:Color("00FF00", "удар!")
    local line = string.format("%s [AoE %s] -> %s: %s Урон: %s",
        playerName,
        SBS.Utils:Color(statColor, statName),
        name,
        resultText,
        SBS.Utils:Color("FF6666", damage))
    
    print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line)
    SBS.Sync:BroadcastCombatLog(line)
    
    -- Всплывающий текст
    local floatType = isCrit and "crit_success" or "hit"
    if SBS.UI then
        SBS.UI:ShowAttackResult(name, floatType, damage)
    end
    
    -- Применяем урон
    local newHP = math.max(0, data.hp - damage)
    SBS.Units:ModifyHP(guid, newHP)
    
    SBS.Utils:Warn(name .. " получает " .. SBS.Utils:Color("FF0000", damage) ..
        " урона! HP: " .. SBS.Utils:Color("FF0000", newHP .. "/" .. data.maxHp))
    
    if newHP <= 0 then
        SBS.Utils:Print("FF0000", name .. " — цель мертва!")
    end
    
    -- Запоминаем цель и уменьшаем счётчик
    self.AoEState.hitTargets[guid] = true
    self.AoEState.hitsLeft = self.AoEState.hitsLeft - 1
    
    SBS.Utils:Info("Осталось ударов: " .. SBS.Utils:Color("FFD700", self.AoEState.hitsLeft))
    
    -- Обновляем панель AoE
    if SBS.UI and SBS.UI.UpdateAoEPanel then
        SBS.UI:UpdateAoEPanel()
    end
    
    -- Проверяем окончание AoE
    if self.AoEState.hitsLeft <= 0 then
        self:EndAoE()
    end
end

function SBS.Combat:EndAoE()
    if not self.AoEState.active then return end
    
    local usedHits = 0
    for _ in pairs(self.AoEState.hitTargets) do
        usedHits = usedHits + 1
    end
    
    SBS.Utils:Info("AoE атака завершена! Поражено целей: " .. SBS.Utils:Color("FFD700", usedHits))
    
    -- Сбрасываем состояние
    self.AoEState.active = false
    self.AoEState.stat = nil
    self.AoEState.hitsLeft = 0
    self.AoEState.hitTargets = {}
    
    -- Скрываем панель AoE
    if SBS.UI and SBS.UI.HideAoEPanel then
        SBS.UI:HideAoEPanel()
    end
    
    -- Оповещаем пошаговую систему
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
    

end

function SBS.Combat:CancelAoE()
    if not self.AoEState.active then return end
    
    SBS.Utils:Warn("AoE атака отменена!")
    self:EndAoE()
end

function SBS.Combat:IsAoEActive()
    return self.AoEState.active
end

function SBS.Combat:GetAoEHitsLeft()
    return self.AoEState.hitsLeft
end

function SBS.Combat:GetAoEStat()
    return self.AoEState.stat
end

-- ═══════════════════════════════════════════════════════════
-- AoE ИСЦЕЛЕНИЕ (для целителей)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:StartAoEHeal()
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    -- Нельзя начать AoE хил если уже в режиме AoE
    if self.AoEState.active then
        SBS.Utils:Error("Сначала завершите AoE атаку!")
        return
    end
    
    if self.AoEHealState.active then
        SBS.Utils:Error("AoE исцеление уже активно!")
        return
    end
    
    -- Проверка энергии
    local energyCost = SBS.Config.ENERGY_COST_AOE
    if not SBS.Stats:HasEnergy(energyCost) then
        SBS.Utils:Error("Недостаточно энергии! Нужно: " .. energyCost)
        return
    end
    
    -- Тратим энергию
    SBS.Stats:SpendEnergy(energyCost)
    
    -- Бросок на успех AoE хила (Дух)
    local modifier = SBS.Stats:GetTotal("Spirit")
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    local threshold = SBS.Config.AOE_THRESHOLD
    local maxTargets = SBS.Config.AOE_MAX_TARGETS
    
    local playerName = UnitName("player")
    local statColor = SBS.Config.StatColors["Spirit"] or "FFE066"
    local statName = SBS.Config.StatNames["Spirit"] or "Дух"
    
    -- Крит провал (1) — промах
    if roll == 1 then
        local line1 = string.format("%s пытается использовать AoE %s.",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) < %d - %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("FF6666", "крит. провал"))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    end
    
    -- Проверка успеха
    local isSuccess = total >= threshold
    
    if not isSuccess then
        local line1 = string.format("%s пытается использовать AoE %s.",
            playerName, SBS.Utils:Color(statColor, statName))
        local line2 = string.format("Результат: %s (%d+%d) < %d - %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("FF6666", "промах"))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        if SBS.TurnSystem then
            SBS.TurnSystem:OnActionPerformed()
        end
        return
    end
    
    -- Успех!
    local targets = maxTargets
    
    if roll == 20 then
        local line1 = string.format("%s активирует AoE исцеление!",
            playerName)
        local line2 = string.format("Результат: %s (%d+%d) >= %d - %s! Целей: %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("00FF00", "крит. успех"),
            SBS.Utils:Color("FFD700", targets))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
        
        -- Возвращаем энергию за крит
        SBS.Stats:AddEnergy(SBS.Config.ENERGY_GAIN_CRIT_CHOICE)
    else
        local line1 = string.format("%s активирует AoE исцеление!",
            playerName)
        local line2 = string.format("Результат: %s (%d+%d) >= %d - %s Целей: %s",
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("00FF00", "успех!"),
            SBS.Utils:Color("FFD700", targets))
        
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line1)
        print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line2)
        SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
    end
    
    -- Активируем режим AoE хила
    self.AoEHealState.active = true
    self.AoEHealState.healsLeft = targets
    self.AoEHealState.healedTargets = {}
    
    SBS.Utils:Info("AoE исцеление активно! Выберите " .. SBS.Utils:Color("FFD700", targets) .. " союзников.")
    
    -- Показываем панель AoE хила
    if SBS.UI and SBS.UI.ShowAoEHealPanel then
        SBS.UI:ShowAoEHealPanel()
    end
end

function SBS.Combat:AoEHealTarget()
    if not self.AoEHealState.active then
        SBS.Utils:Error("AoE исцеление не активно!")
        return
    end
    
    if self.AoEHealState.healsLeft <= 0 then
        SBS.Utils:Error("Все исцеления использованы!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    if not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Можно лечить только игроков!")
        return
    end
    
    -- Проверка на повторное исцеление
    if self.AoEHealState.healedTargets[name] then
        SBS.Utils:Error("Этот игрок уже исцелён! Выберите другого.")
        return
    end
    
    -- AoE хил автоматически успешен, бросаем на крит и количество
    local roll = SBS.Utils:Roll(1, 20)
    local isCrit = (roll == 20)
    local heal = self:CalculateHealing(isCrit)
    local removeWound = false
    
    -- Хилер при крите снимает ранение
    if isCrit and SBS.Stats:GetRole() == "healer" then
        removeWound = true
    end
    
    local playerName = UnitName("player")
    local statColor = SBS.Config.StatColors["Spirit"] or "FFE066"
    
    local resultText = isCrit and SBS.Utils:Color("00FF00", "крит!") or SBS.Utils:Color("00FF00", "успех!")
    local line = string.format("%s [AoE Исцеление] -> %s: %s Лечение: %s",
        playerName, name, resultText,
        SBS.Utils:Color("66FF66", heal))
    
    print(SBS.Utils:Color(statColor, "[SBS]") .. " " .. line)
    SBS.Sync:BroadcastCombatLog(line)
    
    -- Всплывающий текст
    local floatType = isCrit and "crit_heal" or "heal"
    if SBS.UI then
        SBS.UI:ShowAttackResult(name, floatType, heal)
    end
    
    -- Применяем исцеление
    if UnitIsUnit("target", "player") then
        -- Себя
        local maxHP = SBS.Stats:GetMaxHP()
        local currentHP = SBS.Stats:GetCurrentHP()
        local newHP = math.min(maxHP, currentHP + heal)
        SBS.Stats:SetCurrentHP(newHP)
        
        SBS.Utils:Info("Вы восстановили " .. SBS.Utils:Color("00FF00", heal) ..
            " HP! (" .. newHP .. "/" .. maxHP .. ")")
        
        if removeWound and SBS.Stats:GetWounds() > 0 then
            SBS.Stats:RemoveWound()
        end
        
        if SBS.Sync then
            SBS.Sync:BroadcastPlayerData()
        end
    else
        -- Другого игрока
        SBS.Sync:Send("HEAL", name .. ";" .. heal .. ";" .. (removeWound and "1" or "0"))
        SBS.Utils:Info(name .. " восстановил " .. SBS.Utils:Color("00FF00", heal) .. " HP!")
    end
    
    -- Запоминаем цель и уменьшаем счётчик
    self.AoEHealState.healedTargets[name] = true
    self.AoEHealState.healsLeft = self.AoEHealState.healsLeft - 1
    
    SBS.Utils:Info("Осталось исцелений: " .. SBS.Utils:Color("FFD700", self.AoEHealState.healsLeft))
    
    -- Обновляем панель
    if SBS.UI and SBS.UI.UpdateAoEHealPanel then
        SBS.UI:UpdateAoEHealPanel()
    end
    
    -- Проверяем окончание AoE хила
    if self.AoEHealState.healsLeft <= 0 then
        self:EndAoEHeal()
    end
end

function SBS.Combat:EndAoEHeal()
    if not self.AoEHealState.active then return end
    
    local healed = 0
    for _ in pairs(self.AoEHealState.healedTargets) do
        healed = healed + 1
    end
    
    SBS.Utils:Info("AoE исцеление завершено! Исцелено союзников: " .. SBS.Utils:Color("FFD700", healed))
    
    -- Сбрасываем состояние
    self.AoEHealState.active = false
    self.AoEHealState.healsLeft = 0
    self.AoEHealState.healedTargets = {}
    
    -- Скрываем панель
    if SBS.UI and SBS.UI.HideAoEHealPanel then
        SBS.UI:HideAoEHealPanel()
    end
    
    -- Оповещаем пошаговую систему
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
end

function SBS.Combat:CancelAoEHeal()
    if not self.AoEHealState.active then return end
    
    SBS.Utils:Warn("AoE исцеление отменено!")
    self:EndAoEHeal()
end

function SBS.Combat:IsAoEHealActive()
    return self.AoEHealState.active
end

function SBS.Combat:GetAoEHealsLeft()
    return self.AoEHealState.healsLeft
end

-- ═══════════════════════════════════════════════════════════
-- ОСОБОЕ ДЕЙСТВИЕ
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:SpecialAction()
    -- Проверка хода
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end

    -- Проверка не было ли уже отклонено в этом раунде
    local playerName = UnitName("player")
    local currentRound = SBS.TurnSystem and SBS.TurnSystem.round or 0
    if self.RejectedSpecialActions[playerName] == currentRound then
        SBS.Utils:Error("Особое действие отклонено мастером в этом раунде!")
        return
    end

    -- Проверяем энергию (но не тратим пока)
    local energyCost = SBS.Config.ENERGY_COST_SPECIAL
    if not SBS.Stats:HasEnergy(energyCost) then
        SBS.Utils:Error("Недостаточно энергии! Нужно: " .. energyCost)
        return
    end

    -- Показываем диалог запроса
    SBS.Dialogs:ShowSpecialActionRequestDialog()
end

-- Обработка броска особого действия после одобрения мастера
function SBS.Combat:ProcessSpecialActionRoll(threshold, stat, description)
    local playerName = UnitName("player")

    -- Тратим энергию с проверкой
    local energyCost = SBS.Config.ENERGY_COST_SPECIAL
    local success = SBS.Stats:SpendEnergy(energyCost)
    if not success then
        SBS.Utils:Error("Недостаточно энергии для особого действия!")
        return
    end

    -- Получаем модификатор характеристики
    local modifier = SBS.Stats:GetTotal(stat)

    -- Бросок d20
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier

    -- Используем названия и цвета из конфига
    local statName = SBS.Config.StatNames[stat] or stat
    local statColor = SBS.Config.StatColors[stat] or "FFFFFF"

    -- Крит провал (1)
    if roll == 1 then
        local line = string.format("%s пытается: %s (%s). Результат: %s (%d+%d) - %s",
            playerName, description, SBS.Utils:Color(statColor, statName),
            SBS.Utils:Color("FFFF00", total), roll, modifier,
            SBS.Utils:Color("FF6666", "крит. провал!"))
        SBS.Sync:BroadcastCombatLog(line)

    -- Проверка успеха
    elseif total >= threshold then
        -- Крит успех (20)
        if roll == 20 then
            SBS.Stats:AddEnergy(SBS.Config.ENERGY_GAIN_CRIT_CHOICE)
            local line = string.format("%s совершает: %s (%s). Результат: %s (%d+%d) >= %d - %s",
                playerName, description, SBS.Utils:Color(statColor, statName),
                SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
                SBS.Utils:Color("00FF00", "крит. успех!"))
            SBS.Sync:BroadcastCombatLog(line)
        else
            local line = string.format("%s совершает: %s (%s). Результат: %s (%d+%d) >= %d - %s",
                playerName, description, SBS.Utils:Color(statColor, statName),
                SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
                SBS.Utils:Color("00FF00", "успех!"))
            SBS.Sync:BroadcastCombatLog(line)
        end
    else
        -- Неудача
        local line = string.format("%s пытается: %s (%s). Результат: %s (%d+%d) < %d - %s",
            playerName, description, SBS.Utils:Color(statColor, statName),
            SBS.Utils:Color("FFFF00", total), roll, modifier, threshold,
            SBS.Utils:Color("FF6666", "неудача"))
        SBS.Sync:BroadcastCombatLog(line)
    end

    -- Ход переходит к следующему игроку
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИСЦЕЛЕНИЕ
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:Heal()
    -- Проверка AoE режима
    if self:IsAoEActive() then
        SBS.Utils:Error("Сначала завершите AoE атаку!")
        return
    end
    
    if self:IsAoEHealActive() then
        SBS.Utils:Error("Сначала завершите AoE исцеление!")
        return
    end
    
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    local isPlayer = SBS.Utils:IsTargetPlayer()
    local data = SBS.Units:Get(guid)
    
    if not isPlayer and not data then
        SBS.Utils:Error("У цели не установлен HP!")
        return
    end
    
    -- Бросок исцеления
    local modifier = SBS.Stats:GetTotal("Spirit")
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    local threshold = 10
    
    local heal = 0
    local resultText = ""
    local isSuccess = false
    local isCrit = false
    local floatType = "miss"
    local removeWound = false
    
    if roll == 1 then
        isSuccess = false
        resultText = "крит. провал"
        floatType = "crit_fail"
    elseif roll == 20 then
        isSuccess = true
        isCrit = true
        heal = self:CalculateHealing(true)
        resultText = "крит. успех"
        floatType = "crit_heal"
        
        -- Хилер при крите снимает ранение
        if SBS.Stats:GetRole() == "healer" then
            removeWound = true
        end
    else
        isSuccess = self:IsSuccess(total, threshold)
        if isSuccess then
            heal = self:CalculateHealing(false)
            resultText = "удачно"
            floatType = "heal"
        else
            resultText = "неудачно"
            floatType = "miss"
        end
    end
    
    -- Форматируем вывод
    local playerName = UnitName("player")
    local line1, line2 = self:FormatRollResult(playerName, "Spirit", name, total, roll, modifier, threshold, isSuccess, resultText)
    
    -- Добавляем информацию об исцелении
    if heal > 0 then
        line2 = line2 .. " Лечение: " .. SBS.Utils:Color("66FF66", heal)
    end
    
    -- Лог боя (CombatLog:Add сам решает: записать в журнал или вывести в чат)
    SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)

    -- Всплывающий текст для исцеления
    if SBS.UI and heal > 0 then
        SBS.UI:ShowAttackResult(name, floatType, heal)
    end
    
    -- Применяем исцеление
    if heal > 0 then
        if isPlayer then
            if UnitIsUnit("target", "player") then
                -- Себя
                local maxHP = SBS.Stats:GetMaxHP()
                local currentHP = SBS.Stats:GetCurrentHP()
                local newHP = math.min(maxHP, currentHP + heal)
                SBS.Stats:SetCurrentHP(newHP)
                
                SBS.Utils:Info("Вы восстановили " .. SBS.Utils:Color("00FF00", heal) ..
                    " HP! (" .. newHP .. "/" .. maxHP .. ")")
                
                -- Снятие ранения при крите хила
                if removeWound and SBS.Stats:GetWounds() > 0 then
                    SBS.Stats:RemoveWound()
                end
                
                if SBS.Sync then
                    SBS.Sync:BroadcastPlayerData()
                end
            else
                -- Другого игрока
                SBS.Sync:Send("HEAL", name .. ";" .. heal .. ";" .. (removeWound and "1" or "0"))
                SBS.Utils:Info(name .. " восстановил " .. SBS.Utils:Color("00FF00", heal) .. " HP!")
            end
        else
            -- NPC
            local newHP = math.min(data.maxHp, data.hp + heal)
            SBS.Units:ModifyHP(guid, newHP)
            SBS.Utils:Info(name .. " восстановил " .. SBS.Utils:Color("00FF00", heal) ..
                " HP! (" .. newHP .. "/" .. data.maxHp .. ")")
        end
    end
    
    -- Оповещаем пошаговую систему
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- ЩИТ (только для хила)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:Shield()
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    -- Проверка специализации (целитель или универсал)
    local role = SBS.Stats:GetRole()
    if role ~= "healer" and role ~= "universal" then
        SBS.Utils:Error("Только целители и универсалы могут накладывать щит!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    local isPlayer = SBS.Utils:IsTargetPlayer()
    
    -- Бросок щита
    local modifier = SBS.Stats:GetTotal("Spirit")
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    
    local shieldAmount, isCrit = SBS.Config:GetShieldAmount(total)
    local fullHeal = false
    
    local resultText = ""
    local floatType = "shield"
    
    if roll == 1 then
        shieldAmount = 0
        resultText = "крит. провал"
        floatType = "crit_fail"
    elseif isCrit then
        fullHeal = true
        resultText = "крит. успех"
        floatType = "crit_shield"
    else
        resultText = "успех"
    end
    
    -- Форматируем вывод
    local playerName = UnitName("player")

    local line1 = string.format("%s накладывает щит на %s.",
        playerName,
        name)
    
    local line2 = string.format("Бросок: %s (%d+%d) - %s",
        SBS.Utils:Color("FFFF00", total),
        roll, modifier,
        SBS.Utils:Color(shieldAmount > 0 and "66CCFF" or "FF6666", resultText))
    
    if shieldAmount > 0 then
        line2 = line2 .. " Щит: " .. SBS.Utils:Color("66CCFF", shieldAmount)
    end
    
    if fullHeal then
        line2 = line2 .. " + " .. SBS.Utils:Color("66FF66", "полное исцеление")
    end
    
    -- Лог боя (CombatLog:Add сам решает: записать в журнал или вывести в чат)
    SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)

    -- Применяем щит
    if shieldAmount > 0 then
        if isPlayer then
            if UnitIsUnit("target", "player") then
                -- Себя
                if SBS.Stats:HasShield() then
                    SBS.Utils:Warn("Щит уже активен!")
                else
                    SBS.Stats:ApplyShield(shieldAmount)
                    
                    if fullHeal then
                        SBS.Stats:SetCurrentHP(SBS.Stats:GetMaxHP())
                        SBS.Utils:Print("66FF66", "Здоровье полностью восстановлено!")
                    end
                    
                    if SBS.Sync then
                        SBS.Sync:BroadcastPlayerData()
                    end
                end
            else
                -- Другого игрока
                SBS.Sync:Send("SHIELD", name .. ";" .. shieldAmount .. ";" .. (fullHeal and "1" or "0"))
                SBS.Utils:Info("Щит наложен на " .. name)
            end
        else
            -- NPC - не поддерживается пока
            SBS.Utils:Warn("Щит на NPC пока не поддерживается")
        end
    end
    
    -- Оповещаем пошаговую систему
    if SBS.TurnSystem then
        SBS.TurnSystem:OnActionPerformed()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- СНЯТИЕ РАНЫ (только для хила)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:RemoveWound()
    -- Проверка пошагового режима
    if SBS.TurnSystem and not SBS.TurnSystem:CanAct() then
        SBS.Utils:Error("Сейчас не ваш ход!")
        return
    end
    
    -- Проверка специализации
    if SBS.Stats:GetRole() ~= "healer" then
        SBS.Utils:Error("Только целители могут снимать раны!")
        return
    end
    
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    -- Только для игроков
    if not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Можно снимать раны только с игроков!")
        return
    end
    
    -- Бросок снятия раны
    local modifier = SBS.Stats:GetTotal("Spirit")
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    local threshold = 16
    
    local isSuccess = false
    local resultText = ""
    
    if roll == 1 then
        isSuccess = false
        resultText = "крит. провал"
    elseif roll == 20 then
        isSuccess = true
        resultText = "крит. успех"
    else
        isSuccess = self:IsSuccess(total, threshold)
        resultText = isSuccess and "удачно" or "неудачно"
    end
    
    -- Форматируем вывод
    local playerName = UnitName("player")
    local color = SBS.Config.StatColors["Spirit"]
    
    local line1 = string.format("%s пытается снять рану с %s.",
        playerName,
        name)
    
    local compareSign = isSuccess and ">=" or "<"
    local resultColor = isSuccess and "00FF00" or "FF6666"
    
    local line2 = string.format("Бросок %s: %s (%d+%d) %s %d - %s",
        SBS.Utils:Color(color, "Дух"),
        SBS.Utils:Color("FFFF00", total),
        roll, modifier,
        compareSign,
        threshold,
        SBS.Utils:Color(resultColor, resultText))
    
    -- Лог боя (CombatLog:Add сам решает: записать в журнал или вывести в чат)
    SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)

    -- Применяем снятие раны
    if isSuccess then
        if UnitIsUnit("target", "player") then
            -- Себя
            if SBS.Stats:GetWounds() > 0 then
                SBS.Stats:RemoveWound()
                SBS.Utils:Info("Рана успешно снята!")
            else
                SBS.Utils:Info("У вас нет ранений.")
            end
            
            if SBS.Sync then
                SBS.Sync:BroadcastPlayerData()
            end
        else
            -- Другого игрока
            SBS.Sync:Send("REMOVEWOUND", name)
            SBS.Utils:Info("Рана снята с " .. name .. "!")
        end
    else
        SBS.Utils:Error("Не удалось снять рану.")
    end
    
    -- Оповещаем о действии в пошаговом режиме
    if SBS.TurnSystem and SBS.TurnSystem:IsActive() then
        SBS.TurnSystem:OnActionPerformed()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКА ХАРАКТЕРИСТИКИ
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:Check(stat)
    -- Проверки не тратят ход, доступны в любой момент боя
    if not SBS.TurnSystem or not SBS.TurnSystem:IsActive() then
        SBS.Utils:Error("Бой не активен!")
        return
    end
    
    local modifier = SBS.Stats:GetTotal(stat)
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    
    local color = SBS.Config.StatColors[stat] or "FFFFFF"
    local playerName = UnitName("player")
    
    local line1 = string.format("%s совершает проверку %s.",
        playerName,
        SBS.Utils:Color(color, SBS.Config.StatNames[stat]))
    
    local line2 = string.format("Результат: %s (%d+%d)",
        SBS.Utils:Color("FFFF00", total),
        roll, modifier)
    
    print(SBS.Utils:Color(color, "[SBS]") .. " " .. line1)
    print(SBS.Utils:Color(color, "[SBS]") .. " " .. line2)
    
    SBS.Sync:BroadcastCombatLog(line1 .. " " .. line2)
end

-- ═══════════════════════════════════════════════════════════
-- ЗАЩИТА ОТ АТАКИ NPC (обработка входящей атаки)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:ProcessNPCAttack(damage, threshold, defenseStat, npcName)
    local modifier = SBS.Stats:GetTotal(defenseStat)
    local roll = SBS.Utils:Roll(1, 20)
    local total = roll + modifier
    
    local dmg = 0
    local resultText = ""
    local isSuccess = false
    local isCrit = false
    
    if roll == 1 then
        isSuccess = false
        dmg = damage
        resultText = "крит. провал"
    elseif roll == 20 then
        isSuccess = true
        isCrit = true
        resultText = "крит. защита"
    else
        isSuccess = self:IsSuccess(total, threshold)
        if isSuccess then
            resultText = "удачно"
        else
            dmg = damage
            resultText = "неудачно"
        end
    end
    
    -- Форматируем вывод
    local playerName = UnitName("player")
    local attackerName = npcName or "NPC"
    
    local color = SBS.Config.StatColors[defenseStat] or "FFFFFF"
    
    local line1 = string.format("%s атакует %s.",
        SBS.Utils:Color("FF6666", attackerName),
        playerName)
    
    local compareSign = isSuccess and ">=" or "<="
    local resultColor = isSuccess and "00FF00" or "FF6666"
    
    local line2 = string.format("%s защищается %s: %s (%d+%d) %s %d - %s",
        playerName,
        SBS.Utils:Color(color, SBS.Config.StatNames[defenseStat]),
        SBS.Utils:Color("FFFF00", total),
        roll, modifier,
        compareSign,
        threshold,
        SBS.Utils:Color(resultColor, resultText))
    
    print(SBS.Utils:Color(color, "[SBS]") .. " " .. line1)
    print(SBS.Utils:Color(color, "[SBS]") .. " " .. line2)
    
    local logText = line1 .. " " .. line2
    
    if dmg > 0 then
        -- Используем ModifyHP который учитывает щит и ранения
        SBS.Stats:ModifyHP(-dmg)
        logText = logText .. " Урон: " .. SBS.Utils:Color("FF0000", dmg)
    end
    
    SBS.Sync:BroadcastCombatLog(logText)

    -- Отправляем мастеру что защита завершена
    if SBS.Sync then
        -- Если мы сами мастер, очищаем флаг напрямую
        if SBS.Sync:IsMaster() then
            SBS.Combat.PendingAttacks[playerName] = nil
        else
            -- Если мы не мастер, отправляем сообщение мастеру
            SBS.Sync:Send("DEFENSE_DONE", playerName)
        end
        SBS.Sync:BroadcastPlayerData()
    end
    
    -- При крите защиты - показываем меню выбора
    if isCrit then
        SBS.Dialogs:ShowDefenseCritChoiceMenu(function(choice, attackerNameArg, attackerGuidArg)
            self:ApplyCritDefenseChoice(choice, attackerNameArg, attackerGuidArg)
        end, attackerName, nil)
    -- Механика танка: при обычной успешной защите 10% шанс на щит или контратаку
    elseif isSuccess and not isCrit and SBS.Stats:GetRole() == "tank" then
        self:ProcessTankDefenseBonus(attackerName, nil)
    end

end

-- Применить выбор крита при защите
function SBS.Combat:ApplyCritDefenseChoice(choice, attackerName, attackerGuid)
    if choice == "counterattack" then
        SBS.Utils:Info("Крит защиты: " .. SBS.Utils:Color("FF6666", "Контратака") .. "!")
        if attackerGuid then
            local data = SBS.Units:Get(attackerGuid)
            if data then
                local damage = self:CalculateDamage(false)
                local newHP = math.max(0, data.hp - damage)
                SBS.Units:ModifyHP(attackerGuid, newHP)
                SBS.Utils:Warn(attackerName .. " получает " .. SBS.Utils:Color("FF0000", damage) .. " контратаки! HP: " .. SBS.Utils:Color("FF0000", newHP .. "/" .. data.maxHp))
            end
        else
            local damage = self:CalculateDamage(false)
            SBS.Utils:Info("Вы можете нанести " .. SBS.Utils:Color("FF6666", damage) .. " урона контратакой!")
        end
    elseif choice == "energy" then
        SBS.Utils:Info("Крит защиты: +" .. SBS.Utils:Color("9966FF", "1 энергия") .. "!")
    end
end

-- Механика танка: 10% шанс на щит или контратаку после успешной защиты
function SBS.Combat:ProcessTankDefenseBonus(attackerName, attackerGuid)
    if SBS.Utils:Roll(1, 100) > 10 then return end
    local bonusType = SBS.Utils:Roll(1, 2) == 1 and "shield" or "counterattack"
    if bonusType == "shield" then
        local shieldAmount = SBS.Utils:Roll(1, 2)
        if SBS.Stats:GetShield() > 0 then
            SBS.Utils:Info("Танк: щит не получен (уже есть щит).")
        else
            SBS.Stats:SetShield(shieldAmount)
            SBS.Utils:Info("Танк: успешная защита! Получен " .. SBS.Utils:Color("66CCFF", "щит " .. shieldAmount) .. "!")
            if SBS.Sync then SBS.Sync:BroadcastPlayerData() end
        end
    else
        SBS.Dialogs:ShowTankCounterattackChoice(function(accepted)
            if accepted then self:ApplyTankCounterattack(attackerName, attackerGuid)
            else SBS.Utils:Info("Танк: контратака отклонена.") end
        end, attackerName, attackerGuid)
    end
end

-- Применить контратаку танка
function SBS.Combat:ApplyTankCounterattack(attackerName, attackerGuid)
    SBS.Utils:Info("Танк: " .. SBS.Utils:Color("FF6666", "Контратака") .. "!")
    if attackerGuid then
        local data = SBS.Units:Get(attackerGuid)
        if data then
            local damage = self:CalculateDamage(false)
            local newHP = math.max(0, data.hp - damage)
            SBS.Units:ModifyHP(attackerGuid, newHP)
            SBS.Utils:Warn(attackerName .. " получает " .. SBS.Utils:Color("FF0000", damage) .. " контратаки! HP: " .. SBS.Utils:Color("FF0000", newHP .. "/" .. data.maxHp))
        end
    else
        local damage = self:CalculateDamage(false)
        SBS.Utils:Info("Вы можете нанести " .. SBS.Utils:Color("FF6666", damage) .. " урона контратакой!")
    end
end

-- ═══════════════════════════════════════════════════════════
-- МЕХАНИКА БОЙЦА: ДОБИВАНИЕ
-- ═══════════════════════════════════════════════════════════

-- Механика бойца: 10% шанс на добивание после успешной атаки
function SBS.Combat:ProcessDDFinisherBonus(targetGuid, targetName, currentHP, maxHP)
    if SBS.Utils:Roll(1, 100) > 10 then return end
    local hpPercent = (currentHP / maxHP) * 100
    if hpPercent > 20 then
        SBS.Utils:Info("Боец: шанс на добивание! Но цель выше 20% HP (" .. string.format("%.0f", hpPercent) .. "%).")
        return
    end
    SBS.Dialogs:ShowDDFinisherChoice(function(accepted)
        if accepted then self:ApplyDDFinisher(targetGuid, targetName)
        else SBS.Utils:Info("Боец: добивание отклонено.") end
    end, targetName, currentHP, maxHP)
end

-- Применить добивание бойца
function SBS.Combat:ApplyDDFinisher(targetGuid, targetName)
    local data = SBS.Units:Get(targetGuid)
    if not data then SBS.Utils:Error("Цель не найдена!") return end
    SBS.Units:ModifyHP(targetGuid, 0)
    SBS.Utils:Print("FF6666", "Боец: " .. SBS.Utils:Color("FF0000", "ДОБИВАНИЕ") .. "! " .. targetName .. " мгновенно убит!")
    SBS.Sync:BroadcastCombatLog(UnitName("player") .. " добивает " .. targetName .. "!")
end

-- Автонеудача при истечении времени на защиту
function SBS.Combat:ProcessDefenseFailure(damage, npcName)
    local playerName = UnitName("player")
    local attackerName = npcName or "NPC"
    
    local line1 = string.format("%s атакует %s.",
        SBS.Utils:Color("FF6666", attackerName),
        playerName)
    
    local line2 = string.format("%s не успел защититься - %s!",
        playerName,
        SBS.Utils:Color("FF0000", "автонеудача"))
    
    print(SBS.Utils:Color("FF6666", "[SBS]") .. " " .. line1)
    print(SBS.Utils:Color("FF6666", "[SBS]") .. " " .. line2)
    
    local logText = line1 .. " " .. line2

    if damage > 0 then
        SBS.Stats:ModifyHP(-damage)
        logText = logText .. " Урон: " .. SBS.Utils:Color("FF0000", damage)
        SBS.Utils:Error("Время вышло! Получен урон: " .. damage)
    end

    SBS.Sync:BroadcastCombatLog(logText)

    if SBS.Sync then
        -- Если мы сами мастер, очищаем флаг напрямую
        if SBS.Sync:IsMaster() then
            SBS.Combat.PendingAttacks[playerName] = nil
        else
            -- Если мы не мастер, отправляем сообщение мастеру
            SBS.Sync:Send("DEFENSE_DONE", playerName)
        end
        SBS.Sync:BroadcastPlayerData()
    end

    -- Очищаем флаг ожидающей атаки локально (на всякий случай)
    if not SBS.Sync or not SBS.Sync:IsMaster() then
        SBS.Combat.PendingAttacks[playerName] = nil
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИЗМЕНЕНИЕ HP ИГРОКА МАСТЕРОМ
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:ProcessModifyHP(value, source)
    local currentHP = SBS.Stats:GetCurrentHP()
    local maxHP = SBS.Stats:GetMaxHP()
    
    if value < 0 then
        -- Урон через ModifyHP (учитывает щит)
        SBS.Stats:ModifyHP(value)
    else
        -- Исцеление напрямую
        local newHP = SBS.Utils:Clamp(currentHP + value, 0, maxHP)
        SBS.Stats:SetCurrentHP(newHP)
        
        local color = "00FF00"
        SBS.Utils:Info("Мастер восстановил " .. SBS.Utils:Color(color, value) ..
            " здоровья! HP: " .. newHP .. "/" .. maxHP)
    end
    
    local logText = string.format("%s %s %d HP (мастер). HP: %d/%d",
        UnitName("player"), value > 0 and "получил" or "потерял",
        math.abs(value), SBS.Stats:GetCurrentHP(), SBS.Stats:GetMaxHP())
    
    SBS.Sync:BroadcastCombatLog(logText)
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ ИСЦЕЛЕНИЯ ОТ ДРУГОГО ИГРОКА
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:ProcessHeal(heal, healer, removeWound)
    local currentHP = SBS.Stats:GetCurrentHP()
    local maxHP = SBS.Stats:GetMaxHP()
    local newHP = math.min(maxHP, currentHP + heal)
    SBS.Stats:SetCurrentHP(newHP)
    
    SBS.Utils:Info(healer .. " исцелил вас на " .. SBS.Utils:Color("00FF00", heal) ..
        "! HP: " .. newHP .. "/" .. maxHP)
    
    -- Снятие ранения при крите хила
    if removeWound and SBS.Stats:GetWounds() > 0 then
        SBS.Stats:RemoveWound()
    end
    
    SBS.Sync:BroadcastCombatLog(string.format("%s получил исцеление от %s. HP: %d/%d",
        UnitName("player"), healer, newHP, maxHP))
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ ЩИТА ОТ ДРУГОГО ИГРОКА
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:ProcessShield(amount, caster, fullHeal)
    if SBS.Stats:HasShield() then
        SBS.Utils:Warn("Щит уже активен! Новый щит не наложен.")
        return
    end
    
    SBS.Stats:ApplyShield(amount)
    SBS.Utils:Info(caster .. " наложил на вас щит: " .. SBS.Utils:Color("66CCFF", amount))
    
    if fullHeal then
        SBS.Stats:SetCurrentHP(SBS.Stats:GetMaxHP())
        SBS.Utils:Print("66FF66", "Здоровье полностью восстановлено!")
    end
    
    SBS.Sync:BroadcastCombatLog(string.format("%s получил щит (%d) от %s",
        UnitName("player"), amount, caster))
    
    if SBS.Sync then
        SBS.Sync:BroadcastPlayerData()
    end
    

end

-- ═══════════════════════════════════════════════════════════
-- АТАКА NPC ПО ИГРОКУ (мастер)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:NPCAttack(targetName, damage, threshold, defenseStat)
    if not SBS.Utils:RequireMaster() then return end

    -- Проверяем нет ли уже ожидающей атаки на этого игрока
    local pendingTime = self.PendingAttacks[targetName]
    if pendingTime then
        local elapsed = GetTime() - pendingTime
        if elapsed < self.PENDING_TIMEOUT then
            SBS.Utils:Error(targetName .. " ещё не защитился от предыдущей атаки!")
            return
        else
            -- Таймаут истёк, очищаем
            self.PendingAttacks[targetName] = nil
        end
    end

    local npcName = self:GetAttackingNPCName()

    -- Отмечаем что атака отправлена
    self.PendingAttacks[targetName] = GetTime()
    
    SBS.Sync:Send("NPCATTACK", string.format("%s;%d;%d;%s;%s",
        targetName, damage, threshold, defenseStat, npcName))
    
    -- Если цель - мы сами
    if targetName == UnitName("player") then
        if defenseStat == "Hybrid" then
            -- Гибрид — показываем окно выбора защиты
            SBS.Dialogs:ShowHybridDefenseChoice(npcName, damage, threshold)
        else
            -- Обычная защита — показываем окно с кнопкой
            SBS.Dialogs:ShowNPCAttackAlert(npcName, defenseStat, damage, threshold)
        end
    end
    
    -- Лог мастера
    if SBS.CombatLog then
        local defName = defenseStat == "Hybrid" and "Гибрид" or SBS.Config.StatNames[defenseStat]
        SBS.CombatLog:AddMasterLog(string.format(
            "%s атакует '%s': урон %d, порог %d, защита: %s",
            npcName, targetName, damage, threshold, defName),
            "master_action")
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИЗМЕНЕНИЕ HP ИГРОКА (мастер)
-- ═══════════════════════════════════════════════════════════

function SBS.Combat:ModifyPlayerHP(targetName, value)
    if not SBS.Utils:RequireMaster() then return end
    
    SBS.Sync:Send("MODIFYHP", targetName .. ";" .. value)
    
    if targetName == UnitName("player") then
        self:ProcessModifyHP(value, "Мастер")
    end
    
    local action = value > 0 and "Добавлено" or "Отнято"
    local color = value > 0 and "00FF00" or "FF0000"
    
    SBS.Utils:Info(action .. " " .. SBS.Utils:Color(color, math.abs(value)) ..
        " HP игроку " .. SBS.Utils:Color("FFFFFF", targetName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog(string.format("Изменил HP игрока '%s': %+d",
            targetName, value), "master_action")
    end
end

-- ═══════════════════════════════════════════════════════════
-- АЛИАСЫ ДЛЯ СОВМЕСТИМОСТИ
-- ═══════════════════════════════════════════════════════════

-- Алиасы перенесены в Core/Aliases.lua
