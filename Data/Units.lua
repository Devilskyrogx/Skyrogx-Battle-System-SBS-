-- SBS/Data/Units.lua
-- Управление данными NPC (HP, защиты)

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local next = next
local string_format = string.format
local string_gsub = string.gsub
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local wipe = wipe
local UnitName = UnitName
local IsInGroup = IsInGroup

SBS.Units = {}

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Units:Init()
    -- Данные уже в SBS.db.global.unitData
end

-- ═══════════════════════════════════════════════════════════
-- ГЕТТЕРЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Units:Get(guid)
    return SBS.db.global.unitData[guid]
end

function SBS.Units:GetAll()
    return SBS.db.global.unitData
end

-- ═══════════════════════════════════════════════════════════
-- СЕТТЕРЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Units:Set(guid, name, hp, maxHp, fort, reflex, will)
    if not SBS.Utils:RequireMaster() then return false end
    
    local isNew = not self:Get(guid)
    
    SBS.db.global.unitData[guid] = {
        name = name or "Unknown",
        hp = hp,
        maxHp = maxHp or hp,
        fort = fort or 10,
        reflex = reflex or 10,
        will = will or 10,
    }
    
    -- Событие
    if isNew then
        SBS.Events:Fire("UNIT_CREATED", guid, SBS.db.global.unitData[guid])
    else
        SBS.Events:FireDeferred("UNIT_HP_CHANGED", guid, hp, maxHp)
    end
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:BroadcastUnit(guid, SBS.db.global.unitData[guid])
    end
    
    return true
end

function SBS.Units:SetHP(guid, name, hp, maxHp)
    local data = self:Get(guid)
    return self:Set(guid, name, hp, maxHp,
        data and data.fort or 10,
        data and data.reflex or 10,
        data and data.will or 10)
end

function SBS.Units:SetDefenses(guid, name, fort, reflex, will)
    local data = self:Get(guid)
    if data then
        return self:Set(guid, name, data.hp, data.maxHp, fort, reflex, will)
    else
        return self:Set(guid, name, 1, 1, fort, reflex, will)
    end
end

-- ═══════════════════════════════════════════════════════════
-- МОДИФИКАЦИЯ HP
-- ═══════════════════════════════════════════════════════════

function SBS.Units:ModifyHP(guid, newHP)
    local data = self:Get(guid)
    if not data then return false end
    
    local oldHP = data.hp
    local wasDead = data.hp <= 0
    data.hp = SBS.Utils:Clamp(newHP, 0, data.maxHp)
    
    -- Событие
    SBS.Events:FireDeferred("UNIT_HP_CHANGED", guid, data.hp, data.maxHp)
    
    -- Проверка смерти NPC
    if data.hp <= 0 and not wasDead then
        SBS.Events:Fire("UNIT_DIED", guid, data.name)
    end
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:Send("HPCHANGE", guid .. ";" .. data.hp .. ";" .. data.maxHp)
    end
    
    return true
end

function SBS.Units:Damage(guid, amount)
    local data = self:Get(guid)
    if not data then return false end
    return self:ModifyHP(guid, data.hp - amount)
end

function SBS.Units:Heal(guid, amount)
    local data = self:Get(guid)
    if not data then return false end
    return self:ModifyHP(guid, data.hp + amount)
end

-- ═══════════════════════════════════════════════════════════
-- УДАЛЕНИЕ
-- ═══════════════════════════════════════════════════════════

function SBS.Units:Remove(guid)
    if not SBS.Utils:RequireMaster() then return false end
    
    local data = self:Get(guid)
    local name = data and data.name or "Unknown"
    
    SBS.db.global.unitData[guid] = nil
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:Send("REMOVE", guid)
    end
    
    -- Лог мастера
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Удалил NPC '" .. name .. "'", "master_action")
    end
    
    SBS.Events:Fire("UNIT_REMOVED", guid)
    
    return true
end

function SBS.Units:Clear()
    if not SBS.Utils:RequireMaster() then return false end
    
    SBS.db.global.unitData = {}
    
    -- Синхронизация
    if SBS.Sync then
        SBS.Sync:Send("CLEAR")
    end
    
    -- Лог мастера
    if SBS.CombatLog then
        SBS.CombatLog:AddMasterLog("Очистил базу всех NPC", "master_action")
    end
    
    SBS.Events:Fire("UNITS_CLEARED")
    
    SBS.Utils:Warn("База NPC очищена")
    
    return true
end

function SBS.Units:ClearAllConfirm()
    if not SBS.Utils:RequireMaster() then return end
    
    StaticPopupDialogs["SBS_CLEAR_ALL_NPC"] = {
        text = "Удалить ВСЕ данные о NPC?",
        button1 = "Да",
        button2 = "Нет",
        OnAccept = function()
            SBS.Units:Clear()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("SBS_CLEAR_ALL_NPC")
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТЫ
-- ═══════════════════════════════════════════════════════════

function SBS.Units:PrintList()
    print("|cFF00FF00=== SBS NPC List ===|r")
    
    local count = 0
    for guid, data in pairs(SBS.db.global.unitData) do
        if data then
            local name = data.name or "Unknown"
            local status
            if data.hp <= 0 then
                status = "|cFFFF0000Мёртв|r"
            else
                status = "|cFFFF0000" .. data.hp .. "/" .. data.maxHp .. "|r"
            end
            print("|cFFFFFFFF" .. name .. "|r: " .. status .. 
                " |cFF888888[С:" .. data.fort .. " Сн:" .. data.reflex .. " В:" .. data.will .. "]|r")
            count = count + 1
        end
    end
    
    if count == 0 then
        SBS.Utils:Warn("Список пуст")
    end
end

function SBS.Units:Count()
    local count = 0
    for _ in pairs(SBS.db.global.unitData) do
        count = count + 1
    end
    return count
end

-- ═══════════════════════════════════════════════════════════
-- СЕРИАЛИЗАЦИЯ (для синхронизации)
-- ═══════════════════════════════════════════════════════════

function SBS.Units:Serialize()
    local parts = {}
    for guid, data in pairs(SBS.db.global.unitData) do
        if data then
            table.insert(parts, string.format("%s;%s;%d;%d;%d;%d;%d",
                guid,
                data.name or "Unknown",
                data.hp or 0,
                data.maxHp or 0,
                data.fort or 10,
                data.reflex or 10,
                data.will or 10))
        end
    end
    return table.concat(parts, "|")
end

function SBS.Units:Deserialize(str)
    local data = {}
    if not str or str == "" then return data end
    
    for entry in str:gmatch("[^|]+") do
        local guid, name, hp, maxHp, fort, reflex, will = 
            entry:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)")
        if guid then
            data[guid] = {
                name = name,
                hp = tonumber(hp) or 0,
                maxHp = tonumber(maxHp) or 0,
                fort = tonumber(fort) or 10,
                reflex = tonumber(reflex) or 10,
                will = tonumber(will) or 10,
            }
        end
    end
    
    return data
end

function SBS.Units:ImportData(data)
    SBS.db.global.unitData = data
    SBS.Events:Fire("UNITS_IMPORTED")
end

-- Алиасы для совместимости
function SBS:GetUnitData(guid)
    return SBS.Units:Get(guid)
end

function SBS:SetUnitHP(guid, name, hp, maxHp)
    return SBS.Units:SetHP(guid, name, hp, maxHp)
end

function SBS:SetUnitData(guid, name, hp, maxHp, fort, reflex, will)
    if hp == nil then
        return SBS.Units:Remove(guid)
    end
    return SBS.Units:Set(guid, name, hp, maxHp, fort, reflex, will)
end

function SBS:ModifyUnitHP(guid, newHP)
    return SBS.Units:ModifyHP(guid, newHP)
end

function SBS:RemoveTargetHP()
    local guid, name = SBS.Utils:RequireTarget(false)
    if guid then
        SBS.Units:Remove(guid)
    end
end

function SBS:ClearAllNPCConfirm()
    SBS.Units:ClearAllConfirm()
end
