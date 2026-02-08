-- SBS/Combat/TurnSystem.lua
-- Пошаговая боевая система

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local math_random = math.random
local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local tonumber = tonumber
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local C_Timer = C_Timer
local PlaySound = PlaySound
local strsplit = strsplit

SBS.TurnSystem = {
    -- Состояние
    phase = "idle",             -- idle / rolling / players / npc
    participants = {},          -- {{name, guid, roll, acted}, ...}
    participantsByGuid = {},    -- ИНДЕКС: guid -> participant (для быстрого поиска O(1))
    currentIndex = 0,           -- Индекс текущего игрока
    round = 0,                  -- Номер раунда

    -- Настройки
    mode = "free",              -- "queue" (очередь) или "free" (свободная)
    useTimer = false,           -- Использовать таймер или нет
    turnDuration = 60,          -- Секунды на ход
    turnStartTime = 0,          -- Время начала хода

    -- Свободная очередь
    actedThisRound = {},        -- Список GUID кто сходил в этом раунде (для free mode)
    roundStartTime = 0,         -- Время начала раунда (для free mode с таймером)

    -- Специальные
    freeActionGUID = nil,       -- Кто может ходить вне очереди

    -- Таймер
    timerHandle = nil,
}

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТЫ
-- ═══════════════════════════════════════════════════════════

-- Проверяет, является ли игрок участником текущего боя
function SBS.TurnSystem:IsParticipant(guid)
    if not guid then guid = UnitGUID("player") end
    -- Используем индекс для O(1) поиска
    if self.participantsByGuid then
        return self.participantsByGuid[guid] ~= nil
    end
    -- Fallback на линейный поиск
    for _, p in ipairs(self.participants) do
        if p.guid == guid then
            return true
        end
    end
    return false
end

-- Построить индекс участников для быстрого поиска
function SBS.TurnSystem:BuildParticipantIndex()
    self.participantsByGuid = {}
    for _, p in ipairs(self.participants) do
        self.participantsByGuid[p.guid] = p
    end
end

local function GetGroupMembers()
    local members = {}
    
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                local guid = UnitGUID("raid" .. i)
                if guid then
                    table_insert(members, {name = name, guid = guid})
                end
            end
        end
    elseif IsInGroup() then
        -- Добавляем себя
        local myName = UnitName("player")
        local myGUID = UnitGUID("player")
        table_insert(members, {name = myName, guid = myGUID})
        
        -- Добавляем членов группы
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitIsConnected(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                if name and guid then
                    table_insert(members, {name = name, guid = guid})
                end
            end
        end
    else
        -- Соло — только игрок
        local myName = UnitName("player")
        local myGUID = UnitGUID("player")
        table_insert(members, {name = myName, guid = myGUID})
    end
    
    return members
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАТИВА
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:RollInitiative(excludeMaster)
    local members = GetGroupMembers()
    self.participants = {}
    
    local masterGUID = nil
    if excludeMaster and SBS.Sync:IsMaster() then
        masterGUID = UnitGUID("player")
    end
    
    for _, member in ipairs(members) do
        -- Пропускаем мастера если excludeMaster
        if not (excludeMaster and member.guid == masterGUID) then
            local roll = math_random(1, 100)
            table_insert(self.participants, {
                name = member.name,
                guid = member.guid,
                roll = roll,
                acted = false,
            })
        end
    end
    
    -- Сортировка по убыванию (больше = раньше)
    table_sort(self.participants, function(a, b)
        return a.roll > b.roll
    end)
    
    -- Построить индекс для быстрого поиска
    self:BuildParticipantIndex()
end

-- Собирает участников без броска инициативы (для свободного режима)
function SBS.TurnSystem:GatherParticipants(excludeMaster)
    local members = GetGroupMembers()
    self.participants = {}

    local masterGUID = nil
    if excludeMaster and SBS.Sync:IsMaster() then
        masterGUID = UnitGUID("player")
    end

    for _, member in ipairs(members) do
        -- Пропускаем мастера если excludeMaster
        if not (excludeMaster and member.guid == masterGUID) then
            table_insert(self.participants, {
                name = member.name,
                guid = member.guid,
                roll = 0,  -- Нет броска в свободном режиме
                acted = false,
            })
        end
    end

    -- Сортировки нет в свободном режиме
    -- Построить индекс для быстрого поиска
    self:BuildParticipantIndex()
end

-- ═══════════════════════════════════════════════════════════
-- УПРАВЛЕНИЕ БОЕМ (МАСТЕР)
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:StartCombat(mode, useTimer, duration, excludeMaster)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может начать бой!")
        return false
    end

    self.mode = mode or "free"
    self.useTimer = useTimer or false
    self.turnDuration = duration or 60
    self.phase = "rolling"
    self.round = 0
    self.freeActionGUID = nil
    self.masterExcluded = excludeMaster or false
    self.actedThisRound = {}
    self.roundStartTime = 0

    -- Выбираем способ формирования списка участников
    if self.mode == "queue" then
        -- Очередной режим - бросаем инициативу
        self:RollInitiative(excludeMaster)
    else
        -- Свободный режим - собираем без броска
        self:GatherParticipants(excludeMaster)
    end

    if #self.participants == 0 then
        SBS.Utils:Error("Нет участников для боя!")
        self.phase = "idle"
        return false
    end

    -- Событие
    SBS.Events:Fire("COMBAT_STARTED", self.participants)

    -- Синхронизация
    self:BroadcastCombatStart()

    -- Показываем окно очереди для ведущего
    if SBS.UI and SBS.UI.ShowTurnQueue then
        SBS.UI:ShowTurnQueue()
    end

    -- Начинаем первый раунд
    self:StartRound()

    return true
end

function SBS.TurnSystem:EndCombat()
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может окончить бой!")
        return
    end
    
    self:StopTimer()
    
    self.phase = "idle"
    self.participants = {}
    self.participantsByGuid = {}  -- Очищаем индекс
    self.currentIndex = 0
    self.round = 0
    self.freeActionGUID = nil
    
    -- Очищаем все эффекты (баффы и дебаффы)
    if SBS.Effects then
        for playerName, _ in pairs(SBS.Effects.PlayerEffects) do
            SBS.Effects:ClearAll("player", playerName)
        end
        for guid, _ in pairs(SBS.Effects.NPCEffects) do
            SBS.Effects:ClearAll("npc", guid)
        end
    end

    -- Событие
    SBS.Events:Fire("COMBAT_ENDED")

    -- Синхронизация
    self:BroadcastCombatEnd()
    
    -- Показываем уведомление об окончании боя
    if SBS.UI and SBS.UI.ShowCombatEndAlert then
        SBS.UI:ShowCombatEndAlert()
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:StartNPCTurn()
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может переключить фазу!")
        return
    end
    
    self:StopTimer()
    self.phase = "npc"
    
    -- Синхронизация
    self:BroadcastPhaseChange("npc")
    
    -- Показываем уведомление
    if SBS.UI and SBS.UI.ShowNPCPhaseAlert then
        SBS.UI:ShowNPCPhaseAlert()
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:StartPlayersTurn()
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может переключить фазу!")
        return
    end
    
    -- Сбрасываем acted для нового раунда
    self:StartRound()
end

-- ═══════════════════════════════════════════════════════════
-- РАУНДЫ И ХОДЫ
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:StartRound()
    local isFirstRound = (self.round == 0)

    self.round = self.round + 1
    self.phase = "players"

    -- Сброс acted
    for _, p in ipairs(self.participants) do
        p.acted = false
    end
    self.actedThisRound = {}

    -- ══════ ОБРАБОТКА ЭФФЕКТОВ (только мастер, не первый раунд) ══════
    if not isFirstRound and SBS.Sync:IsMaster() and SBS.Effects then
        -- Обрабатываем все эффекты (DoT, HoT, уменьшение длительности)
        SBS.Effects:ProcessAllEffects()

        -- Тикаем оглушения для всех участников (при смене раунда)
        for _, p in ipairs(self.participants) do
            if SBS.Effects:IsStunned(p.name) then
                SBS.Effects:TickStun(p.name)
            end
        end

        -- Логируем в боевой журнал
        if SBS.CombatLog then
            SBS.CombatLog:Add("|cFFFFD700══ Раунд " .. self.round .. " ══|r")
        end
    end

    -- Синхронизация
    self:BroadcastRoundStart()

    -- Обновляем UI после обработки эффектов
    if not isFirstRound and SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end

    -- ══════ РЕЖИМЫ БОЕВОЙ СИСТЕМЫ ══════
    if self.mode == "queue" then
        -- Очередной режим - начинаем ход первого игрока
        self.currentIndex = 1

        -- Показываем уведомление (если не первый раунд — т.е. после фазы NPC)
        if not isFirstRound and SBS.UI and SBS.UI.ShowPlayersPhaseAlert then
            SBS.UI:ShowPlayersPhaseAlert()
        end

        self:StartCurrentTurn()
    else
        -- Свободный режим - игроки ходят в любом порядке
        self.currentIndex = 0  -- Нет текущего игрока

        -- Показываем уведомление в свободном режиме
        if SBS.UI then
            -- Общее уведомление для всех
            if SBS.UI.ShowPlayersPhaseAlert then
                SBS.UI:ShowPlayersPhaseAlert()
            end
            -- Персональное уведомление "ВАШ ХОД" для текущего игрока
            if SBS.UI.ShowYourTurnAlert then
                SBS.UI:ShowYourTurnAlert()
            end
        end

        if self.useTimer then
            -- Запускаем таймер раунда
            self.roundStartTime = GetTime()
            self:StartRoundTimer()
        end

        -- Обновляем UI
        if SBS.UI and SBS.UI.UpdateTurnQueue then
            SBS.UI:UpdateTurnQueue()
        end
    end
end

-- Запускает ход текущего игрока (только для режима "queue")
function SBS.TurnSystem:StartCurrentTurn()
    if self.currentIndex > #self.participants then
        -- Все походили — фаза NPC
        self:StartNPCTurn()
        return
    end
    
    local current = self.participants[self.currentIndex]
    if not current then return end
    
    -- ══════ ПРОВЕРКА НА ОГЛУШЕНИЕ ══════
    if SBS.Effects and SBS.Effects:IsStunned(current.name) then
        -- Получаем оставшееся время стана
        local stunEffect = SBS.Effects:Get("player", current.name, "stun")
        local remainingRounds = stunEffect and stunEffect.remainingRounds or 0
        
        -- Игрок оглушён — пропускаем его ход
        if SBS.Sync then
            SBS.Sync:BroadcastCombatLog(current.name .. " пропускает ход (оглушение, осталось: " .. remainingRounds .. ")")
        end

        -- Уведомляем игрока если это его ход
        local myGUID = UnitGUID("player")
        if current.guid == myGUID then
            SBS.Utils:Warn("Вы оглушены и пропускаете ход! Осталось раундов: " .. remainingRounds)
        end

        -- Помечаем что походил (пропустил)
        current.acted = true

        -- Оглушение тикает в StartRound(), не здесь
        
        -- Переходим к следующему
        self.currentIndex = self.currentIndex + 1
        self:StartCurrentTurn()
        return
    end
    
    self.turnStartTime = GetTime()

    -- Запускаем таймер
    if self.useTimer then
        self:StartTimer()
    end

    -- Событие
    local myGUID = UnitGUID("player")
    local isMyTurn = (current.guid == myGUID)
    SBS.Events:Fire("TURN_CHANGED", current.name, isMyTurn)
    
    -- Оповещение
    if isMyTurn then
        self:ShowYourTurn()
    end
    
    -- Синхронизация
    self:BroadcastTurnChange()
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:NextTurn()
    -- Отмечаем текущего как походившего
    local current = self.participants[self.currentIndex]
    if current then
        current.acted = true
    end
    
    -- Сбрасываем freeAction
    self.freeActionGUID = nil
    
    self:StopTimer()
    
    -- Следующий игрок
    self.currentIndex = self.currentIndex + 1
    
    -- Синхронизация acted
    self:BroadcastActed(current and current.guid)
    
    -- Начинаем следующий ход
    self:StartCurrentTurn()
end

function SBS.TurnSystem:SkipTurn()
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может пропустить ход!")
        return
    end

    if self.mode == "queue" then
        -- Очередной режим - переходим к следующему игроку
        self:NextTurn()
    else
        -- Свободный режим - помечаем текущего игрока как походившего
        local myGUID = UnitGUID("player")
        for _, p in ipairs(self.participants) do
            if p.guid == myGUID then
                p.acted = true
                self.actedThisRound[myGUID] = true
                break
            end
        end

        -- Синхронизация
        self:BroadcastActed(myGUID)

        -- Проверяем завершение раунда
        self:CheckRoundComplete()

        -- Обновляем UI
        if SBS.UI and SBS.UI.UpdateTurnQueue then
            SBS.UI:UpdateTurnQueue()
        end
    end
end

function SBS.TurnSystem:PlayerSkipTurn()
    if self.mode == "queue" then
        -- В очередном режиме проверяем, что это наш ход
        if not self:IsMyTurn() then
            SBS.Utils:Error("Сейчас не ваш ход!")
            return
        end
    end

    if SBS.Sync:IsMaster() then
        -- Мастер обрабатывает локально
        self:SkipTurn()
    else
        -- Оповещаем мастера
        self:SendSkipToMaster()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ТАЙМЕР
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:StartTimer()
    if not self.useTimer then
        return
    end

    self:StopTimer()

    self.timerHandle = SBS.Addon:ScheduleRepeatingTimer(function()
        self:OnTimerTick()
    end, 1)
end

function SBS.TurnSystem:StopTimer()
    if self.timerHandle then
        SBS.Addon:CancelTimer(self.timerHandle)
        self.timerHandle = nil
    end
end

function SBS.TurnSystem:OnTimerTick()
    local remaining = self:GetTimeRemaining()
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnTimer then
        SBS.UI:UpdateTurnTimer(remaining)
    end

    -- Автопропуск
    if self.useTimer and remaining <= 0 then
        if SBS.Sync:IsMaster() then
            self:NextTurn()
        end
    end
end

function SBS.TurnSystem:GetTimeRemaining()
    if self.phase ~= "players" or self.turnStartTime == 0 then
        return self.turnDuration
    end

    local elapsed = GetTime() - self.turnStartTime
    return math.max(0, self.turnDuration - elapsed)
end

-- Запускает таймер раунда (для свободного режима)
function SBS.TurnSystem:StartRoundTimer()
    self:StopTimer()

    self.timerHandle = SBS.Addon:ScheduleRepeatingTimer(function()
        self:OnRoundTimerTick()
    end, 1)
end

-- Тик таймера раунда (для свободного режима)
function SBS.TurnSystem:OnRoundTimerTick()
    local remaining = self:GetRoundTimeRemaining()

    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnTimer then
        SBS.UI:UpdateTurnTimer(remaining)
    end

    -- Автозавершение раунда при истечении времени
    if remaining <= 0 then
        if SBS.Sync:IsMaster() then
            -- Помечаем всех не сходивших как сходивших
            for _, p in ipairs(self.participants) do
                if not p.acted then
                    p.acted = true
                    self.actedThisRound[p.guid] = true
                end
            end
            -- Переходим к фазе NPC
            self:StartNPCTurn()
        end
    end
end

-- Возвращает оставшееся время раунда (для свободного режима)
function SBS.TurnSystem:GetRoundTimeRemaining()
    if self.mode ~= "free" or not self.useTimer or self.roundStartTime == 0 then
        return self.turnDuration
    end

    local elapsed = GetTime() - self.roundStartTime
    return math.max(0, self.turnDuration - elapsed)
end

-- ═══════════════════════════════════════════════════════════
-- УПРАВЛЕНИЕ УЧАСТНИКАМИ
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:AddParticipant(name)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может добавлять участников!")
        return
    end
    
    -- Проверяем что ещё нет в списке
    for _, p in ipairs(self.participants) do
        if p.name == name then
            SBS.Utils:Error(name .. " уже в бою!")
            return
        end
    end
    
    -- Ищем GUID
    local guid = nil
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local raidName = GetRaidRosterInfo(i)
            if raidName == name then
                guid = UnitGUID("raid" .. i)
                break
            end
        end
    elseif IsInGroup() then
        if UnitName("player") == name then
            guid = UnitGUID("player")
        else
            for i = 1, GetNumGroupMembers() - 1 do
                if UnitName("party" .. i) == name then
                    guid = UnitGUID("party" .. i)
                    break
                end
            end
        end
    end
    
    if not guid then
        SBS.Utils:Error("Игрок " .. name .. " не найден в группе!")
        return
    end
    
    -- Бросок инициативы
    local roll = math_random(1, 100)
    
    -- Создаём участника
    local participant = {
        name = name,
        guid = guid,
        roll = roll,
        acted = false,
    }
    
    -- Добавляем в список и индекс
    table_insert(self.participants, participant)
    self.participantsByGuid[guid] = participant
    
    -- Пересортировка
    table_sort(self.participants, function(a, b)
        return a.roll > b.roll
    end)
    
    -- Пересчитываем currentIndex
    for i, p in ipairs(self.participants) do
        if p.guid == self.participants[self.currentIndex].guid then
            self.currentIndex = i
            break
        end
    end
    
    -- Синхронизация
    self:BroadcastParticipantAdd(name, guid, roll)
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:RemoveParticipant(name)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может удалять участников!")
        return
    end
    
    local removedIndex = nil
    local removedGUID = nil
    
    for i, p in ipairs(self.participants) do
        if p.name == name then
            removedIndex = i
            removedGUID = p.guid
            table_remove(self.participants, i)
            break
        end
    end
    
    if not removedIndex then
        SBS.Utils:Error(name .. " не найден в бою!")
        return
    end
    
    -- Удаляем из индекса
    if removedGUID then
        self.participantsByGuid[removedGUID] = nil
    end
    
    -- Корректируем currentIndex
    if removedIndex < self.currentIndex then
        self.currentIndex = self.currentIndex - 1
    elseif removedIndex == self.currentIndex then
        -- Удалили текущего — переходим к следующему
        if self.currentIndex > #self.participants then
            self.currentIndex = #self.participants
        end
        self:StartCurrentTurn()
    end
    
    -- Синхронизация
    self:BroadcastParticipantRemove(removedGUID)
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:GiveFreeAction(name)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может давать внеочередной ход!")
        return
    end
    
    -- Ищем игрока
    for _, p in ipairs(self.participants) do
        if p.name == name then
            self.freeActionGUID = p.guid
            
            -- Синхронизация
            self:BroadcastFreeAction(p.guid)
            return
        end
    end
    
    SBS.Utils:Error(name .. " не найден в бою!")
end

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКИ
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:IsActive()
    return self.phase ~= "idle"
end

function SBS.TurnSystem:IsMyTurn()
    if self.phase ~= "players" then return false end
    
    local current = self.participants[self.currentIndex]
    if not current then return false end
    
    local myGUID = UnitGUID("player")
    return current.guid == myGUID
end

function SBS.TurnSystem:CanAct()
    -- Бой не активен — свобода
    if self.phase == "idle" then return true end

    -- Фаза NPC — игроки не могут действовать
    if self.phase == "npc" then return false end

    -- Фаза игроков
    if self.phase == "players" then
        local myGUID = UnitGUID("player")

        -- Внеочередной ход (работает в обоих режимах)
        if self.freeActionGUID == myGUID then return true end

        if self.mode == "queue" then
            -- Очередной режим - только мой ход
            if self:IsMyTurn() then return true end
        else
            -- Свободный режим - могу действовать если ещё не ходил
            if not self.actedThisRound[myGUID] then
                return true
            end
        end
    end

    return false
end

function SBS.TurnSystem:GetCurrentPlayer()
    return self.participants[self.currentIndex]
end

-- ═══════════════════════════════════════════════════════════
-- УВЕДОМЛЕНИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:ShowYourTurn()
    -- Звук
    PlaySound(8960, "SFX") -- READY_CHECK
    
    -- UI уведомление
    if SBS.UI and SBS.UI.ShowYourTurnAlert then
        SBS.UI:ShowYourTurnAlert()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ДЕЙСТВИЕ ВЫПОЛНЕНО
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:OnActionPerformed()
    -- Вызывается после атаки/лечения
    if not self:IsActive() then return end

    local myGUID = UnitGUID("player")

    -- Если это был внеочередной ход — игрок сбрасывает локально,
    -- мастер сбросит через HandlePlayerActed
    if self.freeActionGUID == myGUID then
        self.freeActionGUID = nil
        self:BroadcastActed(myGUID)
        return
    end

    if self.mode == "queue" then
        -- Очередной режим - переход к следующему игроку
        if self:IsMyTurn() then
            if SBS.Sync:IsMaster() then
                -- Мастер обрабатывает локально (сообщения самому себе не доходят)
                self:NextTurn()
            else
                -- Оповещаем мастера
                self:SendActionDoneToMaster()
            end
        end
    else
        -- Свободный режим - помечаем что сходили
        for _, p in ipairs(self.participants) do
            if p.guid == myGUID then
                p.acted = true
                self.actedThisRound[myGUID] = true
                break
            end
        end

        -- Синхронизация
        self:BroadcastActed(myGUID)

        -- Проверяем завершение раунда (только мастер)
        if SBS.Sync:IsMaster() then
            self:CheckRoundComplete()
        end

        -- Обновляем UI
        if SBS.UI and SBS.UI.UpdateTurnQueue then
            SBS.UI:UpdateTurnQueue()
        end
    end
end

-- Проверяет завершение раунда в свободном режиме
function SBS.TurnSystem:CheckRoundComplete()
    if self.mode ~= "free" then return end

    local allActed = true
    for _, p in ipairs(self.participants) do
        if not p.acted then
            allActed = false
            break
        end
    end

    if allActed then
        -- Все игроки походили - переходим к фазе NPC
        self:StopTimer()
        self:StartNPCTurn()
    end
end

-- Пропускает ход конкретного игрока (для мастера в свободном режиме)
function SBS.TurnSystem:SkipPlayerTurn(playerGUID)
    if not SBS.Sync:IsMaster() then
        SBS.Utils:Error("Только мастер может пропустить игрока!")
        return
    end

    if self.mode ~= "free" then
        -- В очередном режиме используем обычный SkipTurn
        local current = self.participants[self.currentIndex]
        if current and current.guid == playerGUID then
            self:SkipTurn()
        end
        return
    end

    -- Свободный режим - помечаем игрока как сходившего
    for _, p in ipairs(self.participants) do
        if p.guid == playerGUID then
            p.acted = true
            self.actedThisRound[playerGUID] = true

            -- Синхронизация
            self:BroadcastActed(playerGUID)

            -- Проверяем завершение раунда
            self:CheckRoundComplete()

            -- Обновляем UI
            if SBS.UI and SBS.UI.UpdateTurnQueue then
                SBS.UI:UpdateTurnQueue()
            end
            break
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- СИНХРОНИЗАЦИЯ (заглушки — реализуем в Comm.lua)
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:BroadcastCombatStart()
    if not SBS.Sync then return end

    local parts = {}
    for _, p in ipairs(self.participants) do
        table.insert(parts, p.name .. "," .. p.guid .. "," .. p.roll)
    end

    -- Формат: mode;useTimer;duration;participant1;participant2;...
    local data = self.mode .. ";" ..
                 (self.useTimer and "1" or "0") .. ";" ..
                 self.turnDuration .. ";" ..
                 table.concat(parts, ";")
    SBS.Sync:Send("COMBAT_START", data)
end

function SBS.TurnSystem:BroadcastCombatEnd()
    if not SBS.Sync then return end
    SBS.Sync:Send("COMBAT_END", "")
end

function SBS.TurnSystem:BroadcastPhaseChange(phase)
    if not SBS.Sync then return end
    SBS.Sync:Send("PHASE_CHANGE", phase)
end

function SBS.TurnSystem:BroadcastRoundStart()
    if not SBS.Sync then return end
    SBS.Sync:Send("ROUND_START", self.round .. ";" .. self.currentIndex)
end

function SBS.TurnSystem:BroadcastTurnChange()
    if not SBS.Sync then return end
    -- Передаём оставшееся время вместо turnStartTime (которое разное на разных клиентах)
    local remaining = self:GetTimeRemaining()
    SBS.Sync:Send("TURN_CHANGE", self.currentIndex .. ";" .. remaining)
end

function SBS.TurnSystem:BroadcastActed(guid)
    if not SBS.Sync then return end
    SBS.Sync:Send("PLAYER_ACTED", guid or "")
end

function SBS.TurnSystem:BroadcastParticipantAdd(name, guid, roll)
    if not SBS.Sync then return end
    SBS.Sync:Send("PARTICIPANT_ADD", name .. ";" .. guid .. ";" .. roll)
end

function SBS.TurnSystem:BroadcastParticipantRemove(guid)
    if not SBS.Sync then return end
    SBS.Sync:Send("PARTICIPANT_REMOVE", guid)
end

function SBS.TurnSystem:BroadcastFreeAction(guid)
    if not SBS.Sync then return end
    SBS.Sync:Send("FREE_ACTION", guid or "")
end

function SBS.TurnSystem:SendSkipToMaster()
    if not SBS.Sync then return end
    SBS.Sync:Send("PLAYER_SKIP", UnitGUID("player"))
end

function SBS.TurnSystem:SendActionDoneToMaster()
    if not SBS.Sync then return end
    SBS.Sync:Send("ACTION_DONE", UnitGUID("player"))
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА ВХОДЯЩИХ СООБЩЕНИЙ (вызывается из Comm.lua)
-- ═══════════════════════════════════════════════════════════

function SBS.TurnSystem:HandleCombatStart(data)
    local parts = {strsplit(";", data)}

    -- Парсим параметры: mode;useTimer;duration;participant1;participant2;...
    self.mode = parts[1] or "queue"
    self.useTimer = (parts[2] == "1")
    self.turnDuration = tonumber(parts[3]) or 60
    self.participants = {}
    self.actedThisRound = {}

    for i = 4, #parts do
        local name, guid, roll = strsplit(",", parts[i])
        if name and guid and roll then
            table.insert(self.participants, {
                name = name,
                guid = guid,
                roll = tonumber(roll) or 0,
                acted = false,
            })
        end
    end

    self.phase = "players"
    self.round = 1
    
    -- Построить индекс для быстрого поиска
    self:BuildParticipantIndex()

    -- Показываем окно очереди
    if SBS.UI and SBS.UI.ShowTurnQueue then
        SBS.UI:ShowTurnQueue()
    end

    if self.mode == "queue" then
        -- Очередной режим
        self.currentIndex = 1
        self.turnStartTime = GetTime()

        -- Оповещаем если наш ход
        if self:IsMyTurn() then
            self:ShowYourTurn()
        end

        -- Запускаем таймер хода если включен
        if self.useTimer then
            self:StartTimer()
        end
    else
        -- Свободный режим
        self.currentIndex = 0

        -- Запускаем таймер раунда если включен
        if self.useTimer then
            self.roundStartTime = GetTime()
            self:StartRoundTimer()
        end
    end
end

function SBS.TurnSystem:HandleCombatEnd()
    self:StopTimer()

    self.phase = "idle"
    self.participants = {}
    self.participantsByGuid = {}  -- Очищаем индекс
    self.currentIndex = 0
    self.round = 0

    -- Очищаем все эффекты (баффы и дебаффы)
    if SBS.Effects then
        for playerName, _ in pairs(SBS.Effects.PlayerEffects) do
            SBS.Effects:ClearAll("player", playerName)
        end
        for guid, _ in pairs(SBS.Effects.NPCEffects) do
            SBS.Effects:ClearAll("npc", guid)
        end
    end

    -- Показываем уведомление об окончании боя
    if SBS.UI and SBS.UI.ShowCombatEndAlert then
        SBS.UI:ShowCombatEndAlert()
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandlePhaseChange(phase)
    self.phase = phase
    
    if phase == "npc" then
        self:StopTimer()
        -- Показываем уведомление о фазе NPC
        if SBS.UI and SBS.UI.ShowNPCPhaseAlert then
            SBS.UI:ShowNPCPhaseAlert()
        end
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandleRoundStart(data)
    local round, currentIndex = strsplit(";", data)
    local prevRound = self.round
    
    self.round = tonumber(round) or 1
    self.currentIndex = tonumber(currentIndex) or 1
    self.phase = "players"
    self.turnStartTime = GetTime()
    
    -- Сброс acted
    for _, p in ipairs(self.participants) do
        p.acted = false
    end
    self.actedThisRound = {}  -- ВАЖНО: сбрасываем для свободного режима

    -- Запускаем таймер
    if self.useTimer then
        if self.mode == "queue" then
            self:StartTimer()
        else
            self.roundStartTime = GetTime()
            self:StartRoundTimer()
        end
    end

    -- ══════ ОБРАБОТКА КУЛДАУНОВ (для клиентов) ══════
    -- Мастер уже обработал через ProcessAllEffects, клиенты тикают свои кулдауны
    if prevRound > 0 and not SBS.Sync:IsMaster() and SBS.Effects then
        SBS.Effects:TickCooldowns()
    end
    
    -- ══════ ОБНОВЛЕНИЕ UI ЭФФЕКТОВ ══════
    if prevRound > 0 and SBS.UI and SBS.UI.Effects then
        SBS.UI.Effects:UpdateAll()
    end
    
    -- Логируем новый раунд (для клиентов)
    if prevRound > 0 and SBS.CombatLog and not SBS.Sync:IsMaster() then
        SBS.CombatLog:Add("|cFFFFD700══ Раунд " .. self.round .. " ══|r")
    end
    
    -- Показываем уведомление о фазе игроков (если не первый раунд)
    if prevRound > 0 and SBS.UI and SBS.UI.ShowPlayersPhaseAlert then
        SBS.UI:ShowPlayersPhaseAlert()
    end
    
    -- Оповещаем если наш ход
    if self:IsMyTurn() then
        self:ShowYourTurn()
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandleTurnChange(data)
    local currentIndex, remainingTime = strsplit(";", data)
    self.currentIndex = tonumber(currentIndex) or 1
    -- Вычисляем turnStartTime из оставшегося времени
    local remaining = tonumber(remainingTime) or self.turnDuration
    self.turnStartTime = GetTime() - (self.turnDuration - remaining)
    
    -- Оповещаем если наш ход
    if self:IsMyTurn() then
        self:ShowYourTurn()
    end
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandlePlayerActed(guid)
    -- Если это был внеочередной ход — мастер сбрасывает
    if self.freeActionGUID == guid and SBS.Sync:IsMaster() then
        self.freeActionGUID = nil
        self:BroadcastFreeAction(nil)
    end

    -- Используем индекс для O(1) доступа
    local p = self.participantsByGuid[guid]
    if p then
        p.acted = true
        self.actedThisRound[guid] = true
    end

    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end

    -- Мастер проверяет завершение раунда в свободном режиме
    if self.mode == "free" and SBS.Sync:IsMaster() then
        self:CheckRoundComplete()
    end
end

function SBS.TurnSystem:HandleParticipantAdd(data)
    local name, guid, roll = strsplit(";", data)
    
    local participant = {
        name = name,
        guid = guid,
        roll = tonumber(roll) or 0,
        acted = false,
    }
    
    table_insert(self.participants, participant)
    self.participantsByGuid[guid] = participant  -- Добавляем в индекс
    
    -- Пересортировка
    table_sort(self.participants, function(a, b)
        return a.roll > b.roll
    end)
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandleParticipantRemove(guid)
    for i, p in ipairs(self.participants) do
        if p.guid == guid then
            table_remove(self.participants, i)
            break
        end
    end
    
    -- Удаляем из индекса
    self.participantsByGuid[guid] = nil
    
    -- Обновляем UI
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

function SBS.TurnSystem:HandleFreeAction(guid)
    self.freeActionGUID = (guid and guid ~= "") and guid or nil
    
    -- Если это мы — оповещаем звуком и показываем алерт
    if self.freeActionGUID == UnitGUID("player") then
        PlaySound(8960, "SFX") -- READY_CHECK
        -- Показываем визуальное оповещение
        if SBS.UI and SBS.UI.ShowFreeActionAlert then
            SBS.UI:ShowFreeActionAlert()
        end
        SBS.Utils:Info("|cFFFFD700Вам дан внеочередной ход!|r Выполните действие.")
    end
    
    -- Обновляем окно очереди чтобы показать пометку
    if SBS.UI and SBS.UI.UpdateTurnQueue then
        SBS.UI:UpdateTurnQueue()
    end
end

-- Обработка от игроков (только мастер)
function SBS.TurnSystem:HandlePlayerSkip(guid)
    if not SBS.Sync:IsMaster() then return end

    if self.mode == "free" then
        self:SkipPlayerTurn(guid)
    else
        local current = self.participants[self.currentIndex]
        if current and current.guid == guid then
            self:NextTurn()
        end
    end
end

function SBS.TurnSystem:HandleActionDone(guid)
    if not SBS.Sync:IsMaster() then return end

    if self.mode == "free" then
        for _, p in ipairs(self.participants) do
            if p.guid == guid then
                p.acted = true
                self.actedThisRound[guid] = true
                self:BroadcastActed(guid)
                self:CheckRoundComplete()
                if SBS.UI and SBS.UI.UpdateTurnQueue then
                    SBS.UI:UpdateTurnQueue()
                end
                break
            end
        end
    else
        local current = self.participants[self.currentIndex]
        if current and current.guid == guid then
            self:NextTurn()
        end
    end
end
