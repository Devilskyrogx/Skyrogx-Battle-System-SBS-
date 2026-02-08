-- SBS/Sync/Core.lua
-- Базовые функции синхронизации: отправка, мастер, инициализация

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local type = type
local string_format = string.format
local string_sub = string.sub
local string_len = string.len
local table_insert = table.insert
local table_concat = table.concat
local wipe = wipe
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitIsGroupLeader = UnitIsGroupLeader
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer

SBS.Sync = {
    MasterName = nil,
    _isMaster = false,
    
    -- Данные игроков группы
    RaidData = {},
    
    -- Буфер для получения полных данных
    FullDataBuffer = {},
    FullDataExpected = 0,
    
    -- Ожидающие подтверждения
    PendingConfirmations = {},
    
    -- Обработчики (заполняются в Handlers.lua)
    Handlers = {},
}

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:Init()
    self:UpdateMasterStatus()
end

-- ═══════════════════════════════════════════════════════════
-- МАСТЕР (ВЕДУЩИЙ)
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:FindMaster()
    if IsInRaid() then
        for i = 1, 40 do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then
                return name
            end
        end
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then
            return UnitName("player")
        end
        for i = 1, 4 do
            if UnitIsGroupLeader("party" .. i) then
                return UnitName("party" .. i)
            end
        end
    end
    return UnitName("player")
end

function SBS.Sync:UpdateMasterStatus()
    local wasMaster = self._isMaster
    self.MasterName = self:FindMaster()
    self._isMaster = (self.MasterName == UnitName("player"))
    
    if self._isMaster and not wasMaster and IsInGroup() then
        self:Send("MASTER", self.MasterName)
        SBS.Utils:Info("Вы стали ведущим сессии")
        SBS.Events:Fire("MASTER_CHANGED", self.MasterName)
    end
end

function SBS.Sync:IsMaster()
    return self._isMaster or not IsInGroup()
end

function SBS.Sync:GetMasterName()
    return self.MasterName
end

-- ═══════════════════════════════════════════════════════════
-- ОТПРАВКА ДАННЫХ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:Send(cmd, data)
    if not IsInGroup() then return end
    
    local message = cmd
    if data then
        message = cmd .. ":" .. data
    end
    
    local channel = IsInRaid() and "RAID" or "PARTY"
    SBS.Addon:SendCommMessage(SBS.Config.ADDON_PREFIX, message, channel)
end

function SBS.Sync:BroadcastUnit(guid, data)
    if not data then
        self:Send("REMOVE", guid)
    else
        self:Send("UNIT", string.format("%s;%s;%d;%d;%d;%d;%d",
            guid,
            data.name or "Unknown",
            data.hp,
            data.maxHp,
            data.fort,
            data.reflex,
            data.will))
    end
end

function SBS.Sync:BroadcastPlayerData()
    local data = string.format("%d;%d;%d;%s;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d",
        SBS.Stats:GetCurrentHP(),
        SBS.Stats:GetMaxHP(),
        SBS.Stats:GetLevel(),
        SBS.Stats:GetRole() or "none",
        SBS.Stats:GetWounds(),
        SBS.Stats:GetShield(),
        SBS.Stats:GetTotal("Strength"),
        SBS.Stats:GetTotal("Dexterity"),
        SBS.Stats:GetTotal("Intelligence"),
        SBS.Stats:GetTotal("Spirit"),
        SBS.Stats:GetTotal("Fortitude"),
        SBS.Stats:GetTotal("Reflex"),
        SBS.Stats:GetTotal("Will"),
        SBS.Stats:GetEnergy(),
        SBS.Stats:GetMaxEnergy())

    self:Send("PLAYERDATA", data)
    self:UpdateMyRaidData()
end

function SBS.Sync:BroadcastMyHP()
    self:BroadcastPlayerData()
end

function SBS.Sync:BroadcastCombatLog(text)
    -- ВАЖНО: WoW API НЕ возвращает PARTY/RAID сообщения отправителю!
    -- Поэтому ВСЕГДА сначала добавляем в свой локальный лог
    if SBS.CombatLog then
        SBS.CombatLog:Add(text, UnitName("player"))
    end
    -- Затем отправляем другим (если в группе)
    if IsInGroup() then
        self:Send("COMBATLOG", text)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДАННЫЕ ГРУППЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:UpdateMyRaidData()
    local myName = UnitName("player")
    self.RaidData[myName] = {
        hp = SBS.Stats:GetCurrentHP(),
        maxHp = SBS.Stats:GetMaxHP(),
        level = SBS.Stats:GetLevel(),
        role = SBS.Stats:GetRole(),
        spec = SBS.Stats:GetRole(),  -- Алиас для совместимости
        wounds = SBS.Stats:GetWounds(),
        shield = SBS.Stats:GetShield(),
        -- Атакующие статы
        strength = SBS.Stats:GetTotal("Strength"),
        dexterity = SBS.Stats:GetTotal("Dexterity"),
        intelligence = SBS.Stats:GetTotal("Intelligence"),
        spirit = SBS.Stats:GetTotal("Spirit"),
        -- Защитные статы
        fortitude = SBS.Stats:GetTotal("Fortitude"),
        reflex = SBS.Stats:GetTotal("Reflex"),
        will = SBS.Stats:GetTotal("Will"),
        -- Энергия
        energy = SBS.Stats:GetEnergy(),
        maxEnergy = SBS.Stats:GetMaxEnergy(),
    }
end

function SBS.Sync:GetRaidData()
    return self.RaidData
end

function SBS.Sync:GetPlayerData(name)
    return self.RaidData[name]
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА ВХОДЯЩИХ СООБЩЕНИЙ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:OnMessage(message, sender)
    local senderName = sender:match("([^-]+)") or sender
    local cmd, args = message:match("^([^:]+):?(.*)")
    
    if not cmd then return end
    
    -- ПРОВЕРКА БЕЗОПАСНОСТИ
    local isValid, reason = self:ValidateCommand(cmd, senderName)
    if not isValid then
        self:LogSecurityEvent(cmd, senderName, reason)
        return
    end
    
    local handler = self.Handlers[cmd]
    if handler then
        handler(self, args, senderName)
    end
end

-- ═══════════════════════════════════════════════════════════
-- КОМАНДЫ МАСТЕРА
-- ═══════════════════════════════════════════════════════════

-- XP система отключена в v2.0 - уровень привязан к серверу
function SBS.Sync:GiveXP(targetName, amount)
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.Sync:RemoveXP(targetName, amount)
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.Sync:SetLevel(targetName, level)
    SBS.Utils:Warn("Уровень привязан к уровню персонажа на сервере.")
end

function SBS.Sync:SetSpec(targetName, spec)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("SETSPEC", targetName .. ";" .. (spec or "none"))
    
    if targetName == UnitName("player") then
        SBS.Stats:SetSpecialization(spec)
    end
    
    local specName = spec and (SBS.Config.Specializations[spec] and SBS.Config.Specializations[spec].name or spec) or "снята"
    SBS.Utils:Info("Специализация игрока " .. SBS.Utils:Color("FFFFFF", targetName) .. ": " .. SBS.Utils:Color("A06AF1", specName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Установил спек '" .. specName .. "' игроку '" .. targetName .. "'", "master_action")
    end
end

function SBS.Sync:AddWound(targetName)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("ADDWOUND", targetName)
    
    if targetName == UnitName("player") then
        SBS.Stats:AddWound()
    end
    
    SBS.Utils:Info("Добавлено ранение игроку " .. SBS.Utils:Color("FFFFFF", targetName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Добавил ранение игроку '" .. targetName .. "'", "master_action")
    end
end

function SBS.Sync:RemoveWound(targetName)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("REMOVEWOUND", targetName)
    
    if targetName == UnitName("player") then
        SBS.Stats:RemoveWound()
    end
    
    SBS.Utils:Info("Снято ранение с игрока " .. SBS.Utils:Color("FFFFFF", targetName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Снял ранение с игрока '" .. targetName .. "'", "master_action")
    end
end

function SBS.Sync:ResetPlayerStats(targetName)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("RESETSTATS", targetName)
    
    if targetName == UnitName("player") then
        SBS.Stats:ResetStats()
    end
    
    SBS.Utils:Info("Сброшены статы игрока " .. SBS.Utils:Color("FFFFFF", targetName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Сбросил статы игрока '" .. targetName .. "'", "master_action")
    end
end

function SBS.Sync:GiveShield(targetName, amount)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("GIVESHIELD", targetName .. ";" .. amount)
    
    if targetName == UnitName("player") then
        SBS.Stats:ApplyShield(amount)
    end
    
    SBS.Utils:Info("Дан щит " .. SBS.Utils:Color("66CCFF", amount) .. " игроку " .. SBS.Utils:Color("FFFFFF", targetName))
    
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Дал щит " .. amount .. " игроку '" .. targetName .. "'", "master_action")
    end
end

function SBS.Sync:ModifyPlayerHP(targetName, delta)
    if not SBS.Utils:RequireMaster() then return end
    
    self:Send("MODIFYHP", targetName .. ";" .. delta)
    
    if targetName == UnitName("player") then
        SBS.Stats:ModifyHP(delta)
    end
    
    local color = delta > 0 and "00FF00" or "FF0000"
    local sign = delta > 0 and "+" or ""
    SBS.Utils:Info("HP игрока " .. SBS.Utils:Color("FFFFFF", targetName) .. ": " .. SBS.Utils:Color(color, sign .. delta))
end

-- ═══════════════════════════════════════════════════════════
-- БОЕВАЯ СИНХРОНИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:SendNPCAttack(playerName, damage, threshold, defenseStat, npcName)
    self:Send("NPCATTACK", string.format("%s;%d;%d;%s;%s", playerName, damage, threshold, defenseStat, npcName or "NPC"))
end

function SBS.Sync:BroadcastFullData(target)
    local data = SBS.Units:Serialize()
    if data == "" then data = "EMPTY" end
    
    -- Разбиваем на чанки по 200 символов
    local chunks = {}
    local chunkSize = 200
    
    for i = 1, #data, chunkSize do
        table.insert(chunks, data:sub(i, i + chunkSize - 1))
    end
    
    -- Отправляем с задержкой
    for i, chunk in ipairs(chunks) do
        SBS.Addon:ScheduleTimer(function()
            if IsInGroup() then
                self:Send("FULLDATA", string.format("%d:%d:%s", i, #chunks, chunk))
            end
        end, i * 0.1)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОСОБОЕ ДЕЙСТВИЕ
-- ═══════════════════════════════════════════════════════════

-- Игрок отправляет запрос мастеру
function SBS.Sync:SendSpecialActionRequest(description)
    local playerName = UnitName("player")
    self:Send("SPECIALACTION_REQUEST", playerName .. ";" .. description)
end

-- Мастер одобряет запрос с порогом и характеристикой
function SBS.Sync:SendSpecialActionApproved(playerName, threshold, stat)
    local description = ""
    -- Получаем описание из запроса игрока
    if SBS.Combat.PendingSpecialAction and SBS.Combat.PendingSpecialAction.playerName == playerName then
        description = SBS.Combat.PendingSpecialAction.description or ""
    end

    -- Если одобряем самому себе - вызвать напрямую
    if playerName == UnitName("player") then
        SBS.Combat.PendingSpecialAction = nil
        SBS.Dialogs:ShowSpecialActionRollDialog(threshold, stat, description)
    else
        self:Send("SPECIALACTION_APPROVED", playerName .. ";" .. threshold .. ";" .. stat .. ";" .. description)
    end
end

-- Мастер отклоняет запрос
function SBS.Sync:SendSpecialActionRejected(playerName)
    -- Если отклоняем самому себе - вызвать напрямую
    if playerName == UnitName("player") then
        SBS.Combat.PendingSpecialAction = nil
        local currentRound = SBS.TurnSystem and SBS.TurnSystem.round or 0
        SBS.Combat.RejectedSpecialActions[playerName] = currentRound
        SBS.Utils:Warn("|cFFFF6666Особое действие отклонено.|r")
        PlaySound(8960, "SFX")
    else
        self:Send("SPECIALACTION_REJECTED", playerName)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ЭНЕРГИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:GiveEnergy(targetName, amount)
    if not SBS.Utils:RequireMaster() then return end

    self:Send("GIVEENERGY", targetName .. ";" .. amount)

    if targetName == UnitName("player") then
        SBS.Stats:AddEnergy(amount)
    end

    SBS.Utils:Info("Дано " .. SBS.Utils:Color("9966FF", amount .. " энергии") .. " игроку " .. SBS.Utils:Color("FFFFFF", targetName))
end

function SBS.Sync:TakeEnergy(targetName, amount)
    if not SBS.Utils:RequireMaster() then return end

    self:Send("TAKEENERGY", targetName .. ";" .. amount)

    if targetName == UnitName("player") then
        SBS.Stats:SpendEnergy(amount)
    end

    SBS.Utils:Info("Отнято " .. SBS.Utils:Color("9966FF", amount .. " энергии") .. " у игрока " .. SBS.Utils:Color("FFFFFF", targetName))
end
