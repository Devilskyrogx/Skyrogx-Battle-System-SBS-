-- SBS/Core/Events.lua
-- Внутренняя event-система для развязки модулей

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local unpack = unpack
local table_insert = table.insert
local table_remove = table.remove
local C_Timer = C_Timer

SBS.Events = {
    -- Зарегистрированные обработчики { eventName = { handler1, handler2, ... } }
    handlers = {},
    
    -- Очередь отложенных событий
    deferredQueue = {},
    deferredTimer = nil,
}

-- ═══════════════════════════════════════════════════════════
-- РЕГИСТРАЦИЯ И ОТПИСКА
-- ═══════════════════════════════════════════════════════════

-- Подписаться на событие
-- @param eventName string - название события
-- @param handler function - обработчик (получает все аргументы события)
-- @param owner table|nil - владелец (для групповой отписки)
-- @return number - ID подписки для отписки
function SBS.Events:Register(eventName, handler, owner)
    if not self.handlers[eventName] then
        self.handlers[eventName] = {}
    end
    
    local entry = {
        handler = handler,
        owner = owner,
        id = self:GenerateID(),
    }
    
    table_insert(self.handlers[eventName], entry)
    return entry.id
end

-- Отписаться по ID
function SBS.Events:Unregister(eventName, handlerID)
    local handlers = self.handlers[eventName]
    if not handlers then return end
    
    for i = #handlers, 1, -1 do
        if handlers[i].id == handlerID then
            table_remove(handlers, i)
            return true
        end
    end
    return false
end

-- Отписать все обработчики владельца
function SBS.Events:UnregisterAll(owner)
    for eventName, handlers in pairs(self.handlers) do
        for i = #handlers, 1, -1 do
            if handlers[i].owner == owner then
                table_remove(handlers, i)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОТПРАВКА СОБЫТИЙ
-- ═══════════════════════════════════════════════════════════

-- Немедленная отправка события
function SBS.Events:Fire(eventName, ...)
    local handlers = self.handlers[eventName]
    if not handlers then return end
    
    for _, entry in ipairs(handlers) do
        -- Безопасный вызов
        local ok, err = pcall(entry.handler, ...)
        if not ok then
            SBS.Utils:Error("Event error [" .. eventName .. "]: " .. tostring(err))
        end
    end
end

-- Отложенная отправка (объединяет несколько вызовов в один)
-- Полезно для частых событий типа HP_CHANGED
function SBS.Events:FireDeferred(eventName, ...)
    -- Сохраняем только последние аргументы для каждого события
    self.deferredQueue[eventName] = {...}
    
    -- Запускаем таймер если ещё не запущен
    if not self.deferredTimer then
        self.deferredTimer = C_Timer.After(0, function()
            self:ProcessDeferredQueue()
        end)
    end
end

function SBS.Events:ProcessDeferredQueue()
    self.deferredTimer = nil
    
    local queue = self.deferredQueue
    self.deferredQueue = {}
    
    for eventName, args in pairs(queue) do
        self:Fire(eventName, unpack(args))
    end
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТЫ
-- ═══════════════════════════════════════════════════════════

local nextID = 0
function SBS.Events:GenerateID()
    nextID = nextID + 1
    return nextID
end

-- Отладка: показать все подписки
function SBS.Events:Debug()
    print("|cFF00FF00[SBS Events]|r Registered handlers:")
    for eventName, handlers in pairs(self.handlers) do
        print("  " .. eventName .. ": " .. #handlers .. " handlers")
    end
end

-- ═══════════════════════════════════════════════════════════
-- СПИСОК СОБЫТИЙ
-- ═══════════════════════════════════════════════════════════
--[[
Игрок:
    PLAYER_HP_CHANGED       (currentHP, maxHP)
    PLAYER_XP_CHANGED       (currentXP, xpToLevel)
    PLAYER_LEVEL_CHANGED    (newLevel, oldLevel)
    PLAYER_SPEC_CHANGED     (newSpec, oldSpec)
    PLAYER_STATS_CHANGED    ()
    PLAYER_WOUND_CHANGED    (wounds)
    PLAYER_SHIELD_CHANGED   (shield)
    PLAYER_DIED             ()
    PLAYER_RESET            ()

Юниты (NPC):
    UNIT_HP_CHANGED         (guid, currentHP, maxHP)
    UNIT_CREATED            (guid, data)
    UNIT_REMOVED            (guid)
    UNIT_DIED               (guid, name)

Бой:
    COMBAT_STARTED          (queue)
    COMBAT_ENDED            ()
    ROUND_STARTED           (roundNumber)
    TURN_CHANGED            (playerName, isMyTurn)
    PHASE_CHANGED           (phase) -- "players" / "npc"
    ACTION_PERFORMED        (actionType, data)
    AOE_STARTED             (stat, hitsCount)
    AOE_HIT                 (guid, damage, hitsLeft)
    AOE_ENDED               ()

Группа:
    MASTER_CHANGED          (masterName)
    PLAYER_DATA_RECEIVED    (playerName, data)
    GROUP_CHANGED           ()

UI:
    TARGET_CHANGED          (guid, name, isPlayer)
    MAIN_FRAME_TOGGLE       (isShown)
]]
