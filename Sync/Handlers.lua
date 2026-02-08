-- SBS/Sync/Handlers.lua
-- Обработчики входящих сообщений синхронизации

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local string_match = string.match
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat
local strsplit = strsplit
local UnitName = UnitName
local UnitGUID = UnitGUID
local GetTime = GetTime
local PlaySound = PlaySound

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТЧИКИ СООБЩЕНИЙ
-- ═══════════════════════════════════════════════════════════

SBS.Sync.Handlers = {
    -- ═══════════════════════════════════════════════════════════
    -- МАСТЕР И БАЗОВЫЕ
    -- ═══════════════════════════════════════════════════════════
    
    MASTER = function(self, args, sender)
        self.MasterName = args
        self._isMaster = (args == UnitName("player"))
        SBS.Utils:Info("Мастер: " .. SBS.Utils:Color("A06AF1", args))
        SBS.Events:Fire("MASTER_CHANGED", args)
    end,

    -- ═══════════════════════════════════════════════════════════
    -- ПРОВЕРКА ВЕРСИЙ
    -- ═══════════════════════════════════════════════════════════

    VERSION_REQUEST = function(self, args, sender)
        -- Отправляем свою версию в ответ
        self:Send("VERSION_RESPONSE", SBS.Config.VERSION)
    end,

    VERSION_RESPONSE = function(self, args, sender)
        -- Сохраняем ответ от игрока
        if not self.VersionResponses then
            self.VersionResponses = {}
        end
        self.VersionResponses[sender] = args
    end,

    -- ═══════════════════════════════════════════════════════════
    -- ДАННЫЕ NPC
    -- ═══════════════════════════════════════════════════════════
    
    UNIT = function(self, args, sender)
        local guid, name, hp, maxHp, fort, reflex, will = 
            args:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)")
        if guid then
            SBS.db.global.unitData[guid] = {
                name = name,
                hp = tonumber(hp),
                maxHp = tonumber(maxHp),
                fort = tonumber(fort),
                reflex = tonumber(reflex),
                will = tonumber(will),
            }
            SBS.Events:FireDeferred("UNIT_HP_CHANGED", guid, tonumber(hp), tonumber(maxHp))
        end
    end,
    
    HPCHANGE = function(self, args, sender)
        local guid, hp, maxHp = args:match("([^;]+);([^;]+);([^;]+)")
        if guid and SBS.db.global.unitData[guid] then
            SBS.db.global.unitData[guid].hp = tonumber(hp)
            SBS.db.global.unitData[guid].maxHp = tonumber(maxHp)
            SBS.Events:FireDeferred("UNIT_HP_CHANGED", guid, tonumber(hp), tonumber(maxHp))
        end
    end,
    
    REMOVE = function(self, args, sender)
        SBS.db.global.unitData[args] = nil
        SBS.Events:Fire("UNIT_REMOVED", args)
    end,
    
    CLEAR = function(self, args, sender)
        SBS.db.global.unitData = {}
        SBS.Events:Fire("UNITS_CLEARED")
    end,
    
    REQUEST = function(self, args, sender)
        if self:IsMaster() then
            self:BroadcastFullData(sender)
        end
    end,
    
    FULLDATA = function(self, args, sender)
        local idx, total, data = args:match("^(%d+):(%d+):(.*)")
        idx, total = tonumber(idx), tonumber(total)
        
        if idx == 1 then
            self.FullDataBuffer = {}
            self.FullDataExpected = total
        end
        
        self.FullDataBuffer[idx] = data
        
        local complete = true
        for i = 1, self.FullDataExpected do
            if not self.FullDataBuffer[i] then
                complete = false
                break
            end
        end
        
        if complete then
            local fullData = table.concat(self.FullDataBuffer)
            if fullData ~= "EMPTY" then
                SBS.Units:ImportData(SBS.Units:Deserialize(fullData))
            end

            -- Показываем сообщение только если сам игрок запросил данные
            if self.WaitingForFullData then
                local count = SBS.Units:Count()
                SBS.Utils:Info("Данные от мастера: " .. count .. " NPC")
                self.WaitingForFullData = false
            end

            self.FullDataBuffer = {}
            self.FullDataExpected = 0
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- ДАННЫЕ ИГРОКОВ
    -- ═══════════════════════════════════════════════════════════
    
    PLAYERDATA = function(self, args, sender)
        -- Инициализируем кэш если его нет
        if not self._playerDataCache then
            self._playerDataCache = {}
        end
        
        -- Проверяем кэш - если данные не изменились, пропускаем парсинг
        if self._playerDataCache[sender] == args then
            return
        end
        self._playerDataCache[sender] = args
        
        local hp, maxHp, level, role, wounds, shield, str, dex, int, spi, fort, refl, wil, energy, maxEnergy =
            args:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]*);?([^;]*);?([^;]*);?([^;]*);?([^;]*);?([^;]*);?([^;]*);?([^;]*);?([^;]*)")

        if hp then
            self.RaidData[sender] = {
                hp = tonumber(hp),
                maxHp = tonumber(maxHp),
                level = tonumber(level),
                role = role ~= "none" and role or nil,
                spec = role ~= "none" and role or nil,  -- Алиас для совместимости
                wounds = tonumber(wounds),
                shield = tonumber(shield),
                -- Атакующие статы (плоская структура)
                strength = (str and str ~= "") and tonumber(str) or 0,
                dexterity = (dex and dex ~= "") and tonumber(dex) or 0,
                intelligence = (int and int ~= "") and tonumber(int) or 0,
                spirit = (spi and spi ~= "") and tonumber(spi) or 0,
                -- Защитные статы
                fortitude = (fort and fort ~= "") and tonumber(fort) or 0,
                reflex = (refl and refl ~= "") and tonumber(refl) or 0,
                will = (wil and wil ~= "") and tonumber(wil) or 0,
                -- Энергия
                energy = (energy and energy ~= "") and tonumber(energy) or 0,
                maxEnergy = (maxEnergy and maxEnergy ~= "") and tonumber(maxEnergy) or 2,
            }

            SBS.Events:FireDeferred("PLAYER_DATA_RECEIVED", sender, self.RaidData[sender])
        end
    end,
    
    PLAYERHP = function(self, args, sender)
        local current, max = args:match("([^;]+);([^;]+)")
        if current then
            if not self.RaidData[sender] then
                self.RaidData[sender] = {}
            end
            self.RaidData[sender].hp = tonumber(current)
            self.RaidData[sender].maxHp = tonumber(max)
        end
    end,
    
    REQUESTHP = function(self, args, sender)
        self:BroadcastPlayerData()
    end,
    
    COMBATLOG = function(self, args, sender)
        -- Игнорируем свои сообщения - мы уже добавили их в BroadcastCombatLog
        if sender == UnitName("player") then return end
        if SBS.CombatLog then
            SBS.CombatLog:Add(args, sender)
        end
    end,
    
    PLAYERHPCHANGE = function(self, args, sender)
        local playerName, oldHP, newHP = args:match("([^;]+);([^;]+);([^;]+)")
        if playerName and self:IsMaster() and playerName ~= UnitName("player") then
            local diff = tonumber(newHP) - tonumber(oldHP)
            if SBS.CombatLog then
                SBS.CombatLog:AddMasterLog(
                    string.format("%s изменил здоровье: %s → %s (%s%d)",
                        playerName, oldHP, newHP, diff > 0 and "+" or "", diff),
                    "hp_change")
            end
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- БОЙ И ЭФФЕКТЫ
    -- ═══════════════════════════════════════════════════════════
    
    NPCATTACK = function(self, args, sender)
        local target, dmg, threshold, defense, npcName = args:match("([^;]+);([^;]+);([^;]+);([^;]+);?(.*)")
        if target == UnitName("player") then
            local damage = tonumber(dmg)
            local thresh = tonumber(threshold)
            local npc = (npcName and npcName ~= "") and npcName or "NPC"
            
            if defense == "Hybrid" then
                if SBS.Dialogs and SBS.Dialogs.ShowHybridDefenseChoice then
                    SBS.Dialogs:ShowHybridDefenseChoice(npc, damage, thresh)
                end
            else
                if SBS.Dialogs and SBS.Dialogs.ShowNPCAttackAlert then
                    SBS.Dialogs:ShowNPCAttackAlert(npc, defense, damage, thresh)
                end
            end
        end
    end,
    
    MODIFYHP = function(self, args, sender)
        local target, value = args:match("([^;]+);([^;-]*-?%d+)")
        if target == UnitName("player") and SBS.Combat then
            SBS.Combat:ProcessModifyHP(tonumber(value), sender)
        end
    end,
    
    HEAL = function(self, args, sender)
        local target, heal, removeWound = args:match("([^;]+);([^;]+);?([^;]*)")
        if target == UnitName("player") and SBS.Combat then
            SBS.Combat:ProcessHeal(tonumber(heal), sender, removeWound == "1")
        end
    end,
    
    SHIELD = function(self, args, sender)
        local target, amount, fullHeal = args:match("([^;]+);([^;]+);([^;]+)")
        if target == UnitName("player") and SBS.Combat then
            SBS.Combat:ProcessShield(tonumber(amount), sender, fullHeal == "1")
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- УСТАРЕВШИЕ КОМАНДЫ (XP/Level система отключена в v2.0)
    -- ═══════════════════════════════════════════════════════════
    
    GIVEXP = function(self, args, sender)
        -- XP система отключена
    end,
    
    REMOVEXP = function(self, args, sender)
        -- XP система отключена
    end,
    
    SETLEVEL = function(self, args, sender)
        -- Уровень привязан к серверу
    end,
    
    SETSPEC = function(self, args, sender)
        local target, spec = args:match("([^;]+);([^;]+)")
        if target == UnitName("player") then
            local specValue = spec ~= "none" and spec or nil
            local currentRole = SBS.Stats:GetRole()
            
            if currentRole and not specValue then
                SBS.Sync:ShowConfirmDialog(
                    "SETSPEC", sender, "Снятие роли",
                    sender .. " хочет снять вашу роль |cFFA06AF1" .. currentRole .. "|r.\n\nПодтвердить?",
                    function()
                        SBS.Stats:SetRole(nil)
                        SBS.Utils:Warn("Роль снята мастером " .. sender)
                    end
                )
            else
                SBS.Stats:SetRole(specValue)
                if specValue then
                    SBS.Utils:Info("Роль изменена на " .. SBS.Utils:Color("A06AF1", specValue) .. " мастером " .. sender)
                end
            end
        end
    end,
    
    ADDWOUND = function(self, args, sender)
        if args == UnitName("player") then
            SBS.Stats:AddWound()
            SBS.Utils:Warn("Получено ранение от " .. sender)
        end
    end,
    
    REMOVEWOUND = function(self, args, sender)
        if args == UnitName("player") then
            SBS.Stats:RemoveWound()
            SBS.Utils:Info(sender .. " снял с вас рану!")
        end
    end,
    
    RESETSTATS = function(self, args, sender)
        if args == UnitName("player") then
            SBS.Sync:ShowConfirmDialog(
                "RESETSTATS", sender, "Сброс характеристик",
                sender .. " хочет |cFFFF0000СБРОСИТЬ|r ваши характеристики!\n\n|cFFFF6666Это удалит:|r\n- Роль\n- Распределённые очки\n\nПодтвердить?",
                function()
                    SBS.Stats:ResetStats()
                    SBS.Utils:Warn("Характеристики сброшены мастером " .. sender)
                end
            )
        end
    end,
    
    GIVESHIELD = function(self, args, sender)
        local target, amount = args:match("^([^;]+);(%d+)$")
        if target == UnitName("player") and amount then
            SBS.Stats:ApplyShield(tonumber(amount))
            SBS.Utils:Info("Получен щит: " .. SBS.Utils:Color("66CCFF", amount))
        end
    end,
    
    CONFIRM_RESPONSE = function(self, args, sender)
        local cmdType, result, targetMaster = args:match("([^;]+);([^;]+);([^;]+)")
        
        if not self:IsMaster() then return end
        if targetMaster ~= UnitName("player") then return end
        
        local cmdNames = {
            RESETSTATS = "Сброс характеристик",
            SETSPEC = "Снятие роли",
        }
        local cmdName = cmdNames[cmdType] or cmdType
        
        if result == "ACCEPTED" then
            SBS.Utils:Info(sender .. " |cFF66FF66подтвердил|r: " .. cmdName)
            if SBS.CombatLog then
                SBS.CombatLog:AddMasterLog(sender .. " подтвердил: " .. cmdName, "confirm_accept")
            end
        elseif result == "DECLINED" then
            SBS.Utils:Warn(sender .. " |cFFFF6666отклонил|r: " .. cmdName)
            if SBS.CombatLog then
                SBS.CombatLog:AddMasterLog(sender .. " отклонил: " .. cmdName, "confirm_decline")
            end
        elseif result == "TIMEOUT" then
            SBS.Utils:Warn(sender .. " не ответил вовремя: " .. cmdName)
            if SBS.CombatLog then
                SBS.CombatLog:AddMasterLog(sender .. " не ответил: " .. cmdName, "confirm_timeout")
            end
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- ПОШАГОВАЯ СИСТЕМА
    -- ═══════════════════════════════════════════════════════════
    
    COMBAT_START = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleCombatStart(args)
        end
    end,
    
    COMBAT_END = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleCombatEnd()
        end
    end,
    
    PHASE_CHANGE = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandlePhaseChange(args)
        end
    end,
    
    ROUND_START = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleRoundStart(args)
        end
    end,
    
    TURN_CHANGE = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleTurnChange(args)
        end
    end,
    
    PLAYER_ACTED = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandlePlayerActed(args)
        end
    end,
    
    PARTICIPANT_ADD = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleParticipantAdd(args)
        end
    end,
    
    PARTICIPANT_REMOVE = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleParticipantRemove(args)
        end
    end,
    
    FREE_ACTION = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleFreeAction(args)
        end
    end,
    
    PLAYER_SKIP = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandlePlayerSkip(args)
        end
    end,
    
    ACTION_DONE = function(self, args, sender)
        if SBS.TurnSystem then
            SBS.TurnSystem:HandleActionDone(args)
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- ОСОБОЕ ДЕЙСТВИЕ
    -- ═══════════════════════════════════════════════════════════

    -- Мастер получает запрос от игрока
    SPECIALACTION_REQUEST = function(self, args, sender)
        if not SBS.Sync:IsMaster() then return end

        local playerName, description = args:match("([^;]+);(.+)")
        if playerName and description then
            SBS.Dialogs:ShowMasterSpecialActionApproval(playerName, description)
        end
    end,

    -- Игрок получает одобрение от мастера
    SPECIALACTION_APPROVED = function(self, args, sender)
        if sender ~= self.MasterName then return end

        local playerName, threshold, stat, description = args:match("([^;]+);([^;]+);([^;]+);(.*)")
        if playerName == UnitName("player") then
            threshold = tonumber(threshold) or 14
            -- Очищаем PendingSpecialAction
            SBS.Combat.PendingSpecialAction = nil
            -- Показываем диалог броска
            SBS.Dialogs:ShowSpecialActionRollDialog(threshold, stat, description)
        end
    end,

    -- Игрок получает отклонение от мастера
    SPECIALACTION_REJECTED = function(self, args, sender)
        if sender ~= self.MasterName then return end

        local playerName = args
        if playerName == UnitName("player") then
            -- Очищаем PendingSpecialAction
            SBS.Combat.PendingSpecialAction = nil
            -- Записываем текущий раунд для блокировки повторных попыток
            local currentRound = SBS.TurnSystem and SBS.TurnSystem.round or 0
            SBS.Combat.RejectedSpecialActions[playerName] = currentRound

            SBS.Utils:Warn("|cFFFF6666Мастер отклонил ваше особое действие.|r")
            PlaySound(8960, "SFX")
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- ЭНЕРГИЯ
    -- ═══════════════════════════════════════════════════════════
    
    GIVEENERGY = function(self, args, sender)
        -- Проверяем что отправитель - мастер
        if sender ~= self.MasterName then return end

        local target, amount = args:match("([^;]+);([^;]+)")
        if target == UnitName("player") then
            SBS.Stats:AddEnergy(tonumber(amount) or 0)
            SBS.Utils:Info("Получено " .. SBS.Utils:Color("9966FF", amount .. " энергии") .. " от " .. sender)
        end
    end,

    TAKEENERGY = function(self, args, sender)
        -- Проверяем что отправитель - мастер
        if sender ~= self.MasterName then return end

        local target, amount = args:match("([^;]+);([^;]+)")
        if target == UnitName("player") then
            SBS.Stats:SpendEnergy(tonumber(amount) or 0)
            SBS.Utils:Warn("Мастер отнял " .. SBS.Utils:Color("9966FF", amount .. " энергии"))
        end
    end,
    
    RESTOREENERGY = function(self, args, sender)
        -- Только от мастера
        if sender ~= self.MasterName then return end
        
        local targetName = args
        if targetName == UnitName("player") then
            SBS.Stats:RestoreEnergy()
        end
    end,
    
    -- ═══════════════════════════════════════════════════════════
    -- ЭФФЕКТЫ (БАФФЫ/ДЕБАФФЫ/DoT)
    -- ═══════════════════════════════════════════════════════════
    
    EFFECT_APPLY = function(self, args, sender)
        -- Игнорируем свои собственные сообщения (мы уже применили эффект локально)
        if sender == UnitName("player") then
            return
        end

        local targetType, targetId, effectId, value, duration, caster =
            args:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)")

        if targetType and effectId and SBS.Effects then
            -- Применяем эффект локально без повторной синхронизации
            local storage = targetType == "npc" and SBS.Effects.NPCEffects or SBS.Effects.PlayerEffects
            if not storage[targetId] then
                storage[targetId] = {}
            end

            -- Проверяем, есть ли уже такой эффект (стакинг)
            if storage[targetId][effectId] then
                local existing = storage[targetId][effectId]
                -- Добавляем кастера если его нет
                if existing.casters then
                    local found = false
                    for _, c in ipairs(existing.casters) do
                        if c == caster then found = true break end
                    end
                    if not found then
                        table.insert(existing.casters, caster)
                        existing.stacks = (existing.stacks or 1) + 1
                        existing.value = (existing.value or 0) + tonumber(value)
                    end
                end
            else
                -- Новый эффект
                storage[targetId][effectId] = {
                    id = effectId,
                    value = tonumber(value),
                    duration = tonumber(duration),
                    remainingRounds = tonumber(duration),
                    casters = { caster },
                    stacks = 1,
                    appliedAt = GetTime(),
                }
            end

            SBS.Events:Fire("EFFECT_APPLIED", targetType, targetId, effectId)

            -- Обновляем UI
            if SBS.UI.Effects then
                SBS.UI.Effects:UpdateAll()
            end
        end
    end,
    
    EFFECT_REMOVE = function(self, args, sender)
        local targetType, targetId, effectId = args:match("([^;]+);([^;]+);([^;]+)")
        
        if targetType and effectId and SBS.Effects then
            local storage = targetType == "npc" and SBS.Effects.NPCEffects or SBS.Effects.PlayerEffects
            if storage[targetId] then
                storage[targetId][effectId] = nil
                if next(storage[targetId]) == nil then
                    storage[targetId] = nil
                end
            end
            
            SBS.Events:Fire("EFFECT_REMOVED", targetType, targetId, effectId)
        end
    end,
    
    EFFECT_TICK = function(self, args, sender)
        -- Обработка тика эффекта (урон/лечение)
        local targetType, targetId = args:match("([^;]+);([^;]+)")
        
        if SBS.Effects then
            SBS.Effects:ProcessRound(targetType, targetId)
        end
    end,
    
    DEFENSE_DONE = function(self, args, sender)
        -- Игрок защитился, очищаем pending атаку
        local playerName = args
        if self:IsMaster() and SBS.Combat and SBS.Combat.PendingAttacks then
            SBS.Combat.PendingAttacks[playerName] = nil
        end
    end,
    
    EFFECTS_CLEAR_TARGET = function(self, args, sender)
        local targetType, targetId = args:match("([^;]+);([^;]+)")
        if targetType and targetId and SBS.Effects then
            local storage = targetType == "npc" and SBS.Effects.NPCEffects or SBS.Effects.PlayerEffects
            storage[targetId] = nil
            SBS.Events:Fire("EFFECTS_CLEARED", targetType, targetId)
        end
    end,
    
    EFFECT_SYNC = function(self, args, sender)
        -- Мастер не обрабатывает свои собственные синхронизации
        if self:IsMaster() then
            return
        end
        
        -- Синхронизация состояния эффекта от мастера
        local targetType, targetId, effectId, value, remaining, castersStr = 
            args:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]*)")
        
        if targetType and effectId and SBS.Effects then
            local storage = targetType == "npc" and SBS.Effects.NPCEffects or SBS.Effects.PlayerEffects
            if not storage[targetId] then
                storage[targetId] = {}
            end
            
            -- Парсим кастеров
            local casters = {}
            if castersStr and castersStr ~= "" then
                for caster in castersStr:gmatch("[^,]+") do
                    table.insert(casters, caster)
                end
            end
            
            -- Обновляем или создаём эффект
            if storage[targetId][effectId] then
                -- Обновляем существующий
                storage[targetId][effectId].value = tonumber(value)
                storage[targetId][effectId].remainingRounds = tonumber(remaining)
                if #casters > 0 then
                    storage[targetId][effectId].casters = casters
                    storage[targetId][effectId].stacks = #casters
                end
            else
                -- Создаём новый
                local def = SBS.Effects.Definitions[effectId]
                storage[targetId][effectId] = {
                    id = effectId,
                    value = tonumber(value),
                    duration = def and def.fixedDuration or tonumber(remaining),
                    remainingRounds = tonumber(remaining),
                    casters = #casters > 0 and casters or { "Unknown" },
                    stacks = #casters > 0 and #casters or 1,
                    appliedAt = GetTime(),
                }
            end
            
            -- Обновляем UI
            if SBS.UI.Effects then
                SBS.UI.Effects:UpdateAll()
            end
        end
    end,
    
    EFFECT_STACK = function(self, args, sender)
        -- Игнорируем свои собственные сообщения
        if sender == UnitName("player") then
            return
        end

        -- Синхронизация стакнутого эффекта
        local targetType, targetId, effectId, value, remaining, stacks, castersStr =
            args:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]*)")

        if targetType and effectId and SBS.Effects then
            local storage = targetType == "npc" and SBS.Effects.NPCEffects or SBS.Effects.PlayerEffects
            if not storage[targetId] then
                storage[targetId] = {}
            end

            -- Парсим кастеров
            local casters = {}
            if castersStr and castersStr ~= "" then
                for caster in castersStr:gmatch("[^,]+") do
                    table.insert(casters, caster)
                end
            end

            local def = SBS.Effects.Definitions[effectId]
            storage[targetId][effectId] = {
                id = effectId,
                value = tonumber(value),
                duration = def and def.fixedDuration or tonumber(remaining),
                remainingRounds = tonumber(remaining),
                casters = casters,
                stacks = tonumber(stacks),
                appliedAt = GetTime(),
            }

            -- Обновляем UI
            if SBS.UI.Effects then
                SBS.UI.Effects:UpdateAll()
            end

            SBS.Events:Fire("EFFECT_APPLIED", targetType, targetId, effectId)
        end
    end,
}
