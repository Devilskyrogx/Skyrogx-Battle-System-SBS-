-- SBS/Core/Init.lua
-- Инициализация аддона через Ace3

local ADDON_NAME, SBS = ...
_G.SBS = SBS

-- Создаём аддон через AceAddon
local Addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, 
    "AceEvent-3.0",     -- События
    "AceComm-3.0",      -- Коммуникация между игроками
    "AceTimer-3.0",     -- Таймеры
    "AceSerializer-3.0" -- Сериализация данных
)

SBS.Addon = Addon

-- ═══════════════════════════════════════════════════════════
-- ACE CALLBACKS
-- ═══════════════════════════════════════════════════════════

function Addon:OnInitialize()
    -- Инициализация базы данных через AceDB
    self.db = LibStub("AceDB-3.0"):New("SBS_DB", SBS.Defaults, true)
    SBS.db = self.db
    
    -- Регистрация префикса для коммуникации
    self:RegisterComm(SBS.Config.ADDON_PREFIX)
    
    -- Миграция старых данных если есть
    self:MigrateOldData()
end

function Addon:OnEnable()
    -- Регистрация событий
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LEVEL_UP")  -- Отслеживаем повышение уровня
    
    -- Инициализация модулей
    if SBS.Stats then SBS.Stats:Init() end
    if SBS.Units then SBS.Units:Init() end
    if SBS.Sync then SBS.Sync:Init() end
    if SBS.UI then SBS.UI:Init() end

    -- Инициализация Unit Frames (после загрузки UI)
    self:ScheduleTimer(function()
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:Init()
        end
    end, 0.5)
    
    -- Отложенная инициализация после полной загрузки
    self:ScheduleTimer(function()
        -- Синхронизируем уровень при загрузке
        if SBS.Stats then
            SBS.Stats:SyncLevelWithGame()
        end
        
        if SBS.Sync then
            SBS.Sync:UpdateMasterStatus()
            if IsInGroup() then
                SBS.Sync:BroadcastPlayerData()
                SBS.Sync:Send("REQUESTHP")
            end
        end
        
        -- Применяем масштаб UI
        if SBS.Utils then
            SBS.Utils:ApplyUIScale()
        end
    end, 2)
    
    SBS.Utils:Info("v" .. SBS.Config.VERSION .. " загружен! /sbs для справки")
end

function Addon:OnDisable()
    -- Отключение (если нужно)
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТЧИКИ СОБЫТИЙ
-- ═══════════════════════════════════════════════════════════

-- Throttling для GROUP_ROSTER_UPDATE
local lastGroupSyncTime = 0

function Addon:GROUP_ROSTER_UPDATE()
    if SBS.Sync then
        SBS.Sync:UpdateMasterStatus()

        -- Throttling: синхронизация не чаще раза в 5 секунд
        local now = GetTime()
        if IsInGroup() and (now - lastGroupSyncTime) > 5 then
            lastGroupSyncTime = now

            self:ScheduleTimer(function()
                SBS.Sync:BroadcastPlayerData()
                SBS.Sync:Send("REQUESTHP")
            end, 1)

            if not SBS.Sync:IsMaster() then
                self:ScheduleTimer(function()
                    SBS.Sync.WaitingForFullData = true
                    SBS.Sync:Send("REQUEST")
                end, 2)
            end
        end
    end

    -- Обновляем видимость кнопки GM Panel (всегда)
    if SBS.UI then
        SBS.UI:UpdateGMButtonVisibility()
    end
end

function Addon:PLAYER_TARGET_CHANGED()
    if SBS.UI then
        SBS.UI:UpdateMainFrame()
        -- Обязательно обновляем эффекты цели при смене
        if SBS.UI.Effects then
            SBS.UI.Effects:UpdateTarget()
        end
        -- Обновляем фрейм цели
        if SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:UpdateTargetFrame()
        end
    end
end

function Addon:NAME_PLATE_UNIT_ADDED(event, unitId)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
    if nameplate and SBS.UI then
        SBS.UI:UpdateNameplateFrame(nameplate, unitId)
    end
end

function Addon:NAME_PLATE_UNIT_REMOVED(event, unitId)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
    if nameplate and SBS.UI and SBS.UI.NameplateFrames[nameplate] then
        SBS.UI.NameplateFrames[nameplate]:Hide()
    end
end

function Addon:PLAYER_ENTERING_WORLD()
    -- Синхронизируем уровень при входе в мир
    if SBS.Stats then
        SBS.Stats:SyncLevelWithGame()
    end
    
    if SBS.Sync then
        SBS.Sync:UpdateMasterStatus()
        SBS.Sync:BroadcastPlayerData()
    end
end

function Addon:PLAYER_LEVEL_UP(event, newLevel)
    -- Игрок повысил уровень - синхронизируем
    if SBS.Stats then
        SBS.Stats:SyncLevelWithGame()
    end
    
    -- Обновляем UI
    if SBS.UI then
        SBS.UI:UpdateMainFrame()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА СООБЩЕНИЙ (AceComm)
-- ═══════════════════════════════════════════════════════════

function Addon:OnCommReceived(prefix, message, distribution, sender)
    if prefix == SBS.Config.ADDON_PREFIX and SBS.Sync then
        SBS.Sync:OnMessage(message, sender)
    end
end

-- ═══════════════════════════════════════════════════════════
-- МИГРАЦИЯ СТАРЫХ ДАННЫХ
-- ═══════════════════════════════════════════════════════════

function Addon:MigrateOldData()
    -- Миграция из старого формата SBS_DB
    if SBS_DB and not SBS_DB.profileKeys then
        -- Это старый формат, мигрируем
        local oldDB = SBS_DB
        
        if oldDB.Stats then
            for stat, value in pairs(oldDB.Stats) do
                if stat ~= "HP" then
                    self.db.char.stats[stat] = value
                end
            end
        end
        
        if oldDB.PointsLeft then
            self.db.char.pointsLeft = oldDB.PointsLeft
        end
        
        if oldDB.CurrentHP then
            self.db.char.currentHP = oldDB.CurrentHP
        end
        
        if oldDB.UnitData then
            self.db.global.unitData = oldDB.UnitData
        end
        
        if oldDB.CombatLog then
            self.db.global.combatLog = oldDB.CombatLog
        end
        
        if oldDB.MinimapAngle then
            self.db.profile.minimapAngle = oldDB.MinimapAngle
        end
        
        -- Устанавливаем текущий уровень как lastKnownLevel
        self.db.char.lastKnownLevel = UnitLevel("player")
        
        -- Миграция специализации -> роль
        if oldDB.specialization then
            self.db.char.role = oldDB.specialization
            self.db.char.specialization = oldDB.specialization
        end
        
        -- Новые поля
        self.db.char.wounds = oldDB.wounds or 0
        self.db.char.shield = oldDB.shield or 0
        
        SBS.Utils:Info("Данные мигрированы в новый формат v2.0")
    end
    
    -- Миграция из версии 1.x в 2.0
    if self.db.char.level then
        -- Старая система с level и xp
        self.db.char.lastKnownLevel = UnitLevel("player")
        self.db.char.level = nil
        self.db.char.xp = nil
        
        -- Пересчитываем очки по текущему уровню
        if SBS.Stats then
            SBS.Stats:RecalculatePoints()
        end
        
        SBS.Utils:Info("Данные мигрированы в систему уровней 2.0")
    end
    
    -- Миграция specialization -> role
    if self.db.char.specialization and not self.db.char.role then
        self.db.char.role = self.db.char.specialization
    end
    
    -- Миграция из profile в char (для существующих пользователей)
    if self.db.profile.stats and self.db.profile.stats.Strength and self.db.profile.stats.Strength > 0 then
        -- Копируем данные из profile в char
        for stat, value in pairs(self.db.profile.stats) do
            if self.db.char.stats[stat] == 0 then
                self.db.char.stats[stat] = value
            end
        end
        self.db.char.pointsLeft = self.db.profile.pointsLeft or self.db.char.pointsLeft
        self.db.char.currentHP = self.db.profile.currentHP or self.db.char.currentHP
        self.db.char.role = self.db.profile.role or self.db.char.role
        self.db.char.specialization = self.db.profile.specialization or self.db.char.specialization
        self.db.char.wounds = self.db.profile.wounds or self.db.char.wounds
        self.db.char.shield = self.db.profile.shield or self.db.char.shield
        self.db.char.lastKnownLevel = self.db.profile.lastKnownLevel or self.db.char.lastKnownLevel
        self.db.char.energy = self.db.profile.energy or self.db.char.energy
        
        -- Очищаем старые данные из profile
        self.db.profile.stats = nil
        self.db.profile.pointsLeft = nil
        self.db.profile.currentHP = nil
        self.db.profile.role = nil
        self.db.profile.specialization = nil
        self.db.profile.wounds = nil
        self.db.profile.shield = nil
        self.db.profile.lastKnownLevel = nil
        self.db.profile.energy = nil
        
        SBS.Utils:Info("Данные персонажа перенесены в отдельное хранилище")
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - СПРАВКА
-- ═══════════════════════════════════════════════════════════

SLASH_SBSHELP1 = "/sbshelp"
SLASH_SBSHELP2 = "/sbs?"
SlashCmdList["SBSHELP"] = function()
    print("|cFFFFD700=== SBS (Skyrogx Battle System) v" .. SBS.Config.VERSION .. " ===|r")
    print("|cFF66CCFF— Основные окна —|r")
    print("  |cFF00FF00/sbs|r — главное окно")
    print("  |cFF00FF00/sbs log|r — журнал боя")
    print("  |cFF00FF00/sbs master|r — панель мастера")
    print("  |cFF00FF00/sbs settings|r — настройки (масштаб UI)")
    print("  |cFF00FF00/sbs stats|r — инфо о персонаже")
    print("|cFF66CCFF— Роли —|r")
    print("  |cFF00FF00/sbsrole|r — выбрать роль")
    print("  |cFF00FF00/sbsrole <игрок> tank|dd|healer|none|r — установить (мастер)")
    print("|cFF66CCFF— Ранения —|r")
    print("  |cFF00FF00/sbswound <игрок>|r — добавить ранение (мастер)")
    print("  |cFF00FF00/sbshealwound <игрок>|r — снять ранение (мастер)")
    print("|cFF66CCFF— Управление игроками (мастер) —|r")
    print("  |cFF00FF00/sbssetrole <игрок>|r — задать роль игроку")
    print("  |cFF00FF00/sbsresetstats <игрок>|r — сбросить статы игрока")
    print("  |cFF00FF00/sbsgiveenergy <игрок>|r — дать +1 энергию")
    print("  |cFF00FF00/sbsrestoreenergy <игрок>|r — восстановить полную энергию")
    print("  |cFF00FF00/sbsmodifyplayerhp <игрок> ±число|r — изменить HP игрока")
    print("  |cFF00FF00/sbsgiveshield <игрок> <число>|r — дать щит игроку")
    print("  |cFF00FF00/sbsaddwound|r — добавить ранение (цель)")
    print("  |cFF00FF00/sbsremwound|r — снять ранение (цель)")
    print("|cFF66CCFF— Управление NPC (мастер) —|r")
    print("  |cFF00FF00/sbshp|r — показать HP цели")
    print("  |cFF00FF00/sbshp <число>|r — задать HP цели")
    print("  |cFF00FF00/sbssethp <число>|r — задать HP цели")
    print("  |cFF00FF00/sbsdefense <с> <сн> <в>|r — задать защиту NPC")
    print("  |cFF00FF00/sbsmodifynpchp ±число|r — изменить HP NPC")
    print("  |cFF00FF00/sbsremovenpc|r — удалить цель из базы")
    print("  |cFF00FF00/sbsattacker|r — назначить NPC атакующим")
    print("  |cFF00FF00/sbsnpcattack <игрок|%%t> <урон> <порог> <защита>|r — атака NPC")
    print("  |cFF00FF00/sbsnpceffect <эффект> [значение] [раунды]|r — эффект на НПЦ (цель)")
    print("  |cFF00FF00/sbsnpcstun [раунды]|r — оглушить НПЦ (цель)")
    print("  |cFF00FF00/sbsbuff <игрок|%%t> <эффект> [значение] [раунды]|r — бафф на игрока")
    print("  |cFF00FF00/sbsdebuff <игрок|%%t> <эффект> [значение] [раунды]|r — дебафф на игрока")
    print("  |cFF00FF00/sbshplist|r — список NPC")
    print("  |cFF00FF00/sbshpclear|r — очистить базу NPC")
    print("|cFF66CCFF— Боевые действия —|r")
    print("  |cFF00FF00/sbsattack str|dex|int|r — атака")
    print("  |cFF00FF00/sbsshield|r — наложить щит (целитель)")
    print("|cFF66CCFF— Пошаговый бой (мастер) —|r")
    print("  |cFF00FF00/sbscombat start [сек]|r — начать бой")
    print("  |cFF00FF00/sbscombat end|r — окончить бой")
    print("  |cFF00FF00/sbscombat help|r — все команды боя")
    print("|cFF888888Уровень синхронизируется с уровнем персонажа (10-100)|r")
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - ОСНОВНЫЕ
-- ═══════════════════════════════════════════════════════════

SLASH_SBS1 = "/sbs"
SlashCmdList["SBS"] = function(msg)
    local cmd = msg:lower():trim()
    
    if cmd == "" then
        if SBS.UI then SBS.UI:ToggleMainFrame() end
    elseif cmd == "help" then
        SlashCmdList["SBSHELP"]()
    elseif cmd == "reset" then
        if SBS.UI then SBS.UI:TryResetStats() end
    elseif cmd == "fullreset" then
        if SBS.Stats then SBS.Stats:FullReset() end
    elseif cmd == "log" then
        if SBS.UI then SBS.UI:ToggleCombatLog() end
    elseif cmd == "master" then
        if SBS.UI then SBS.UI:ToggleMasterFrame() end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        if SBS.Dialogs then SBS.Dialogs:ToggleSettings() end
    elseif cmd == "sync" then
        if not IsInGroup() then
            SBS.Utils:Error("Вы не в группе!")
            return
        end
        if SBS.Sync then
            if SBS.Sync:IsMaster() then
                SBS.Sync:BroadcastFullData()
                SBS.Utils:Info("Данные отправлены")
            else
                SBS.Sync.WaitingForFullData = true
                SBS.Sync:Send("REQUEST")
                SBS.Utils:Info("Запрос отправлен")
            end
        end
    elseif cmd == "stats" then
        if SBS.Stats then SBS.Stats:PrintStats() end
    elseif cmd == "level" then
        -- Показать информацию об уровне
        if SBS.Stats then
            local level = SBS.Stats:GetLevel()
            local gameLevel = SBS.Stats:GetGameLevel()
            local pointsLeft = SBS.Stats:GetPointsLeft()
            local totalPoints = SBS.Stats:GetTotalPoints()

            print("|cFFFFD700=== Уровень SBS ===|r")
            print("Уровень персонажа: |cFFFFD700" .. gameLevel .. "|r")
            print("Уровень в системе: |cFFFFD700" .. level .. "|r (диапазон: " ..
                SBS.Config.MIN_LEVEL .. "-" .. SBS.Config.MAX_LEVEL .. ")")
            print("Очки: |cFFFFD700" .. pointsLeft .. "/" .. totalPoints .. "|r")
            print("Базовое HP: |cFF66FF66" .. SBS.Config:GetBaseHPForLevel(level) .. "|r")
        end
    elseif cmd == "frames" or cmd == "frame" or cmd == "uf" then
        -- Управление Unit Frames
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:TogglePlayerFrame()
        end
    elseif cmd == "frames reset" then
        -- Сброс позиций фреймов
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ResetPosition("player")
            SBS.UI.UnitFrames:ResetPosition("target")
            SBS.Utils:Info("Позиции Unit Frames сброшены")
        end
    elseif cmd == "frames lock" then
        -- Блокировка фреймов
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ToggleLock()
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - UNIT FRAMES
-- ═══════════════════════════════════════════════════════════

SLASH_SBSFRAMES1 = "/sbsframes"
SLASH_SBSFRAMES2 = "/sbsuf"
SlashCmdList["SBSFRAMES"] = function(msg)
    local cmd = msg:lower():trim()

    if cmd == "" or cmd == "toggle" then
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:TogglePlayerFrame()
        end
    elseif cmd == "reset" then
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ResetPosition("player")
            SBS.UI.UnitFrames:ResetPosition("target")
            SBS.Utils:Info("Позиции Unit Frames сброшены")
        end
    elseif cmd == "lock" then
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ToggleLock()
        end
    elseif cmd == "player" then
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:TogglePlayerFrame()
        end
    elseif cmd == "target" then
        if SBS.UI and SBS.UI.UnitFrames then
            SBS.UI.UnitFrames:ToggleTargetFrame()
        end
    else
        print("|cFFFFD700=== Unit Frames ===|r")
        print("  |cFF00FF00/sbsframes|r — показать/скрыть фрейм игрока")
        print("  |cFF00FF00/sbsframes player|r — показать/скрыть фрейм игрока")
        print("  |cFF00FF00/sbsframes target|r — показать/скрыть фрейм цели")
        print("  |cFF00FF00/sbsframes reset|r — сбросить позиции")
        print("  |cFF00FF00/sbsframes lock|r — заблокировать перемещение")
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - РОЛИ (бывшие специализации)
-- ═══════════════════════════════════════════════════════════

SLASH_SBSROLE1 = "/sbsrole"
SLASH_SBSROLE2 = "/sbsspec"  -- Алиас для совместимости
SlashCmdList["SBSROLE"] = function(msg)
    msg = msg:trim()
    
    if msg == "" then
        -- Выбор своей роли
        if not SBS.Stats:CanChooseRole() then
            SBS.Utils:Error("Требуется " .. SBS.Config.ROLE_REQUIRED_LEVEL .. " уровень!")
            return
        end
        if SBS.Dialogs then
            SBS.Dialogs:ShowRoleMenu()
        end
        return
    end
    
    if not SBS.Utils:RequireMaster() then return end
    
    local target, role = msg:match("^(%S+)%s+(%S+)$")
    if not target or not role then
        SBS.Utils:Error("Использование: /sbsrole <игрок> tank|dd|healer|none")
        return
    end
    
    role = role:lower()
    if role == "none" or role == "reset" then
        role = nil
    elseif role ~= "tank" and role ~= "dd" and role ~= "healer" then
        SBS.Utils:Error("Роли: tank, dd, healer, none")
        return
    end
    
    SBS.Sync:SetSpec(target, role)
end

-- Алиас для совместимости
SLASH_SBSSPEC1 = "/sbsspec"
SlashCmdList["SBSSPEC"] = SlashCmdList["SBSROLE"]

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - РАНЕНИЯ
-- ═══════════════════════════════════════════════════════════

SLASH_SBSWOUND1 = "/sbswound"
SlashCmdList["SBSWOUND"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end
    
    local target = msg:trim()
    if target == "" then
        -- Использовать цель
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbswound <игрок>")
            return
        end
        target = name
    end
    
    SBS.Sync:AddWound(target)
end

SLASH_SBSHEALWOUND1 = "/sbshealwound"
SLASH_SBSHEALWOUND2 = "/sbsunwound"
SlashCmdList["SBSHEALWOUND"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end
    
    local target = msg:trim()
    if target == "" then
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbshealwound <игрок>")
            return
        end
        target = name
    end
    
    SBS.Sync:RemoveWound(target)
end

-- AoE Исцеление
SLASH_SBSAOEHEAL1 = "/sbsaoeheal"
SlashCmdList["SBSAOEHEAL"] = function()
    SBS.Combat:StartAoEHeal()
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - ЩИТ
-- ═══════════════════════════════════════════════════════════

SLASH_SBSSHIELD1 = "/sbsshield"
SlashCmdList["SBSSHIELD"] = function()
    if SBS.Combat then
        SBS.Combat:Shield()
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - HP NPC
-- ═══════════════════════════════════════════════════════════

SLASH_SBSHP1 = "/sbshp"
SlashCmdList["SBSHP"] = function(msg)
    msg = msg:trim()
    local guid, name = SBS.Utils:GetTargetGUID()
    
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    
    if UnitIsPlayer("target") then
        SBS.Utils:Error("Нельзя для игроков!")
        return
    end
    
    if msg == "" then
        -- Показать HP
        local data = SBS.Units:Get(guid)
        if data then
            SBS.Utils:Info(name .. ": HP " .. data.hp .. "/" .. data.maxHp .. 
                " [С:" .. data.fort .. " Сн:" .. data.reflex .. " В:" .. data.will .. "]")
        else
            SBS.Utils:Warn(name .. ": HP не задан")
        end
        return
    end
    
    if not SBS.Utils:RequireMaster() then return end
    
    -- Формат current/max
    local cur, max = msg:match("^(%d+)/(%d+)$")
    if cur and max then
        SBS.Units:Set(guid, name, tonumber(cur), tonumber(max))
        return
    end
    
    -- Просто число
    local hp = tonumber(msg)
    if hp then
        if hp <= 0 then
            SBS.Units:Remove(guid)
            SBS.Utils:Warn("Данные для " .. name .. " удалены")
        else
            SBS.Units:Set(guid, name, hp, hp)
            SBS.Utils:Info(name .. ": HP " .. hp .. "/" .. hp)
        end
        return
    end
    
    SBS.Utils:Error("Использование: /sbshp [текущий/макс]")
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - АТАКА
-- ═══════════════════════════════════════════════════════════

SLASH_SBSATTACK1 = "/sbsattack"
SlashCmdList["SBSATTACK"] = function(msg)
    local map = { str = "Strength", dex = "Dexterity", int = "Intelligence" }
    local stat = map[msg:trim():lower()]
    
    if stat and SBS.Combat then
        SBS.Combat:Attack(stat)
    else
        SBS.Utils:Error("Использование: /sbsattack str|dex|int")
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - ПРОЧЕЕ
-- ═══════════════════════════════════════════════════════════

SLASH_SBSHPLIST1 = "/sbshplist"
SlashCmdList["SBSHPLIST"] = function()
    if SBS.Units then SBS.Units:PrintList() end
end

SLASH_SBSHPCLEAR1 = "/sbshpclear"
SlashCmdList["SBSHPCLEAR"] = function()
    if SBS.Units then SBS.Units:ClearAllConfirm() end
end

SLASH_SBSRESET1 = "/sbsreset"
SlashCmdList["SBSRESET"] = function()
    if SBS.UI then SBS.UI:TryResetStats() end
end

SLASH_SBSSYNC1 = "/sbssync"
SlashCmdList["SBSSYNC"] = function()
    SlashCmdList["SBS"]("sync")
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - ПОШАГОВЫЙ БОЙ
-- ═══════════════════════════════════════════════════════════

SLASH_SBSCOMBAT1 = "/sbscombat"
SLASH_SBSCOMBAT2 = "/sbsfight"
SlashCmdList["SBSCOMBAT"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    
    if cmd == "start" or cmd == "" then
        -- /sbscombat start [секунды]
        if not SBS.Utils:RequireMaster() then return end
        local duration = tonumber(arg) or 60
        SBS.TurnSystem:StartCombat(duration)
        
    elseif cmd == "end" or cmd == "stop" then
        if not SBS.Utils:RequireMaster() then return end
        SBS.TurnSystem:EndCombat()
        
    elseif cmd == "skip" then
        if SBS.Sync:IsMaster() then
            SBS.TurnSystem:SkipTurn()
        else
            SBS.TurnSystem:PlayerSkipTurn()
        end
        
    elseif cmd == "npc" then
        if not SBS.Utils:RequireMaster() then return end
        SBS.TurnSystem:StartNPCTurn()
        
    elseif cmd == "players" then
        if not SBS.Utils:RequireMaster() then return end
        SBS.TurnSystem:StartPlayersTurn()
        
    elseif cmd == "add" then
        if not SBS.Utils:RequireMaster() then return end
        if arg == "" then
            SBS.Utils:Error("Использование: /sbscombat add <имя>")
            return
        end
        SBS.TurnSystem:AddParticipant(arg)
        
    elseif cmd == "remove" or cmd == "kick" then
        if not SBS.Utils:RequireMaster() then return end
        if arg == "" then
            SBS.Utils:Error("Использование: /sbscombat remove <имя>")
            return
        end
        SBS.TurnSystem:RemoveParticipant(arg)
        
    elseif cmd == "free" then
        if not SBS.Utils:RequireMaster() then return end
        if arg == "" then
            SBS.Utils:Error("Использование: /sbscombat free <имя>")
            return
        end
        SBS.TurnSystem:GiveFreeAction(arg)
        
    elseif cmd == "queue" then
        if SBS.UI and SBS.UI.ToggleTurnQueue then
            SBS.UI:ToggleTurnQueue()
        end
        
    else
        print("|cFFFFD700=== Пошаговый бой ===|r")
        print("  |cFF00FF00/sbscombat start [сек]|r — начать бой (таймер по умолчанию 60с)")
        print("  |cFF00FF00/sbscombat end|r — окончить бой")
        print("  |cFF00FF00/sbscombat skip|r — пропустить ход")
        print("  |cFF00FF00/sbscombat npc|r — фаза NPC (мастер)")
        print("  |cFF00FF00/sbscombat players|r — фаза игроков (мастер)")
        print("  |cFF00FF00/sbscombat add <имя>|r — добавить в бой (мастер)")
        print("  |cFF00FF00/sbscombat remove <имя>|r — убрать из боя (мастер)")
        print("  |cFF00FF00/sbscombat free <имя>|r — внеочередной ход (мастер)")
        print("  |cFF00FF00/sbscombat queue|r — окно очереди")
    end
end

SLASH_SBSSKIP1 = "/sbsskip"
SlashCmdList["SBSSKIP"] = function()
    SlashCmdList["SBSCOMBAT"]("skip")
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - УПРАВЛЕНИЕ ИГРОКАМИ (МАСТЕР)
-- ═══════════════════════════════════════════════════════════

-- Задать роль игроку
SLASH_SBSSETROLE1 = "/sbssetrole"
SlashCmdList["SBSSETROLE"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local targetName = msg:trim()
    if targetName == "" then
        -- Используем цель
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbssetrole <игрок>")
            return
        end
        targetName = name
    end

    if SBS.Dialogs then
        SBS.Dialogs:ShowSetSpecMenu(targetName)
    end
end

-- Сбросить статы игрока
SLASH_SBSRESETSTATS1 = "/sbsresetstats"
SlashCmdList["SBSRESETSTATS"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local targetName = msg:trim()
    if targetName == "" then
        -- Используем цель
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbsresetstats <игрок>")
            return
        end
        targetName = name
    end

    if SBS.Sync then
        SBS.Sync:ResetPlayerStats(targetName)
    end
end

-- Дать энергию игроку
SLASH_SBSGIVEENERGY1 = "/sbsgiveenergy"
SlashCmdList["SBSGIVEENERGY"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local targetName = msg:trim()
    if targetName == "" then
        -- Используем цель
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbsgiveenergy <игрок>")
            return
        end
        targetName = name
    end

    if SBS.Sync then
        SBS.Sync:GiveEnergy(targetName, 1)
    end
end

-- Восстановить полную энергию игроку
SLASH_SBSRESTOREENERGY1 = "/sbsrestoreenergy"
SlashCmdList["SBSRESTOREENERGY"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local targetName = msg:trim()
    if targetName == "" then
        -- Используем цель
        local guid, name = SBS.Utils:GetTargetGUID()
        if not guid or not SBS.Utils:IsTargetPlayer() then
            SBS.Utils:Error("Выберите игрока или укажите имя: /sbsrestoreenergy <игрок>")
            return
        end
        targetName = name
    end

    if SBS.Sync then
        SBS.Sync:Send("RESTOREENERGY", targetName)
        SBS.Utils:Info("Энергия игрока " .. SBS.Utils:Color("FFFFFF", targetName) .. " восстановлена до максимума.")
    end
end

-- ═══════════════════════════════════════════════════════════
-- SLASH КОМАНДЫ - ДЕЙСТВИЯ С NPC/ИГРОКАМИ
-- ═══════════════════════════════════════════════════════════

-- Задать HP цели (NPC)
-- Использование: /sbssethp 100 (для текущей цели)
SLASH_SBSSETHP1 = "/sbssethp"
SlashCmdList["SBSSETHP"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local hp = tonumber(msg:trim())
    if not hp or hp <= 0 then
        SBS.Utils:Error("Использование: /sbssethp <число>")
        return
    end

    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end

    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя задать HP игроку! Используйте /sbsmodifyplayerhp")
        return
    end

    if SBS.Units:SetHP(guid, name, hp, hp) then
        SBS.Utils:Info(name .. ": HP " .. hp .. "/" .. hp)
        if SBS.UI then SBS.UI:UpdateMainFrame() end
    end
end

-- Задать защиту NPC
-- Использование: /sbsdefense 12 15 10 (fortitude reflex will для текущей цели)
SLASH_SBSDEFENSE1 = "/sbsdefense"
SlashCmdList["SBSDEFENSE"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local fort, reflex, will = msg:match("^(%d+)%s+(%d+)%s+(%d+)$")
    if not fort or not reflex or not will then
        SBS.Utils:Error("Использование: /sbsdefense <стойк> <снор> <воля>")
        return
    end

    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end

    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Нельзя задать защиту игроку!")
        return
    end

    SBS.Units:SetDefenses(guid, name, tonumber(fort), tonumber(reflex), tonumber(will))
    SBS.Utils:Info(name .. ": Стойк=" .. fort .. ", Снор=" .. reflex .. ", Воля=" .. will)
    if SBS.UI then SBS.UI:UpdateMainFrame() end
end

-- Изменить HP NPC (±)
-- Использование: /sbsmodifynpchp +50 или /sbsmodifynpchp -20 (для текущей цели)
SLASH_SBSMODIFYNPCHP1 = "/sbsmodifynpchp"
SlashCmdList["SBSMODIFYNPCHP"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local delta = tonumber(msg:trim())
    if not delta then
        SBS.Utils:Error("Использование: /sbsmodifynpchp +число или -число")
        return
    end

    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end

    if SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Это игрок! Используйте /sbsmodifyplayerhp")
        return
    end

    local data = SBS.Units:Get(guid)
    if not data then
        SBS.Utils:Error("HP для " .. name .. " не задано!")
        return
    end

    local newHP = math.max(0, data.hp + delta)
    if SBS.Units:ModifyHP(guid, newHP) then
        local color = delta > 0 and "00FF00" or "FF0000"
        local sign = delta > 0 and "+" or ""
        SBS.Utils:Info(name .. ": HP " .. SBS.Utils:Color(color, sign .. delta) .. " (" .. newHP .. "/" .. data.maxHp .. ")")
        if SBS.UI then SBS.UI:UpdateMainFrame() end
    end
end

-- Удалить NPC из базы
SLASH_SBSREMOVENPC1 = "/sbsremovenpc"
SlashCmdList["SBSREMOVENPC"] = function()
    if not SBS.Utils:RequireMaster() then return end
    if SBS then
        SBS:RemoveTargetHP()
        if SBS.UI then
            SBS.UI:UpdateMainFrame()
        end
    end
end

-- Назначить NPC атакующим
SLASH_SBSATTACKER1 = "/sbsattacker"
SlashCmdList["SBSATTACKER"] = function()
    if not SBS.Utils:RequireMaster() then return end
    if SBS then
        SBS:SetAttackingNPC()
        if SBS.UI then
            SBS.UI:UpdateMainFrame()
        end
    end
end

-- Атака NPC на игрока
-- Функция подстановки %t -> имя цели
local function ResolveTarget(msg)
    if msg:find("%%t") then
        local targetName = UnitName("target")
        if not targetName then
            SBS.Utils:Error("Нет цели! Выберите цель для подстановки %t")
            return nil
        end
        return msg:gsub("%%t", targetName)
    end
    return msg
end

-- Атака NPC (мастер)
-- Использование: /sbsnpcattack Игрок 10 15 Fortitude (или Hybrid)
SLASH_SBSNPCATTACK1 = "/sbsnpcattack"
SlashCmdList["SBSNPCATTACK"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    msg = ResolveTarget(msg)
    if not msg then return end

    local target, damage, threshold, defense = msg:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%S+)$")
    if not target or not damage or not threshold or not defense then
        SBS.Utils:Error("Использование: /sbsnpcattack <игрок|%%t> <урон> <порог> <защита>")
        SBS.Utils:Info("Защита: Fortitude, Reflex, Will, Hybrid")
        return
    end

    -- Гибридная защита — игрок сам выбирает
    if defense == "Hybrid" or defense == "hybrid" then
        if SBS.Combat then
            SBS.Combat:NPCAttackHybrid(target, tonumber(damage), tonumber(threshold))
        end
        return
    end

    -- Проверяем валидность защиты
    if defense ~= "Fortitude" and defense ~= "Reflex" and defense ~= "Will" then
        SBS.Utils:Error("Защита должна быть: Fortitude, Reflex, Will или Hybrid")
        return
    end

    if SBS.Combat then
        SBS.Combat:NPCAttack(target, tonumber(damage), tonumber(threshold), defense)
    end
end

-- Изменить HP игрока (±)
-- Использование: /sbsmodifyplayerhp Игрок +10 или /sbsmodifyplayerhp %t -5
SLASH_SBSMODIFYPLAYERHP1 = "/sbsmodifyplayerhp"
SlashCmdList["SBSMODIFYPLAYERHP"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    msg = ResolveTarget(msg)
    if not msg then return end

    local target, delta = msg:match("^(%S+)%s+([+-]?%d+)$")
    if not target or not delta then
        SBS.Utils:Error("Использование: /sbsmodifyplayerhp <игрок|%%t> +число или -число")
        return
    end

    if SBS.Sync then
        SBS.Sync:ModifyPlayerHP(target, tonumber(delta))
    end
end

-- Добавить ранение игроку (на основе цели)
SLASH_SBSADDWOUND1 = "/sbsaddwound"
SlashCmdList["SBSADDWOUND"] = function()
    if not SBS.Utils:RequireMaster() then return end
    if SBS.UI then
        SBS.UI:MasterAddWound()
    end
end

-- Снять ранение игроку (на основе цели)
SLASH_SBSREMWOUND1 = "/sbsremwound"
SlashCmdList["SBSREMWOUND"] = function()
    if not SBS.Utils:RequireMaster() then return end
    if SBS.UI then
        SBS.UI:MasterRemoveWound()
    end
end

-- Дать щит игроку
-- Использование: /sbsgiveshield Игрок 5
SLASH_SBSGIVESHIELD1 = "/sbsgiveshield"
SlashCmdList["SBSGIVESHIELD"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local target, amount = msg:match("^(%S+)%s+(%d+)$")
    if not target or not amount then
        SBS.Utils:Error("Использование: /sbsgiveshield <игрок> <количество>")
        return
    end

    if SBS.Sync then
        SBS.Sync:GiveShield(target, tonumber(amount))
    end
end

-- ═══════════════════════════════════════════════════════════
-- МАКРОСЫ ДЛЯ МАСТЕРА: БАФФЫ, ДЕБАФФЫ, ЭФФЕКТЫ НПЦ
-- ═══════════════════════════════════════════════════════════

-- Наложить бафф на игрока
-- /sbsbuff <игрок|%t> <эффект> [значение] [раунды]
-- Эффекты: empower, fortify_fortitude, fortify_reflex, fortify_will, regeneration, blessing
SLASH_SBSBUFF1 = "/sbsbuff"
SlashCmdList["SBSBUFF"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    msg = ResolveTarget(msg)
    if not msg then return end

    local target, effectId, value, rounds = msg:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%d*)$")
    if not target or not effectId then
        SBS.Utils:Error("Использование: /sbsbuff <игрок|%%t> <эффект> [значение] [раунды]")
        SBS.Utils:Info("Эффекты: empower, fortify_fortitude, fortify_reflex, fortify_will, regeneration, blessing")
        return
    end

    local def = SBS.Effects.Definitions[effectId]
    if not def or def.type ~= "buff" then
        SBS.Utils:Error("Неизвестный бафф: " .. effectId)
        return
    end

    value = tonumber(value) or def.fixedValue or 1
    rounds = tonumber(rounds) or def.fixedDuration or 3

    SBS.Effects:Apply("player", target, effectId, value, rounds, "Мастер")
    SBS.Effects:BroadcastAllEffects()
    SBS.Utils:Info("Бафф |cFF00FF00" .. def.name .. "|r наложен на |cFFFFFFFF" .. target .. "|r")
    SBS.Sync:BroadcastCombatLog("Мастер накладывает " .. def.name .. " на " .. target .. " (" .. value .. ", " .. rounds .. " р.)")
end

-- Наложить дебафф на игрока
-- /sbsdebuff <игрок|%t> <эффект> [значение] [раунды]
-- Эффекты: stun, weakness_damage, weakness_healing, vulnerability_fortitude, vulnerability_reflex, vulnerability_will, dot_master
SLASH_SBSDEBUFF1 = "/sbsdebuff"
SlashCmdList["SBSDEBUFF"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    msg = ResolveTarget(msg)
    if not msg then return end

    local target, effectId, value, rounds = msg:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%d*)$")
    if not target or not effectId then
        SBS.Utils:Error("Использование: /sbsdebuff <игрок|%%t> <эффект> [значение] [раунды]")
        SBS.Utils:Info("Эффекты: stun, weakness_damage, weakness_healing, vulnerability_fortitude, vulnerability_reflex, vulnerability_will, dot_master")
        return
    end

    local def = SBS.Effects.Definitions[effectId]
    if not def or (def.type ~= "debuff" and def.type ~= "dot") then
        SBS.Utils:Error("Неизвестный дебафф: " .. effectId)
        return
    end

    value = tonumber(value) or def.fixedValue or 1
    rounds = tonumber(rounds) or def.fixedDuration or 2

    SBS.Effects:Apply("player", target, effectId, value, rounds, "Мастер")
    SBS.Effects:BroadcastAllEffects()
    SBS.Utils:Info("Дебафф |cFFFF6666" .. def.name .. "|r наложен на |cFFFFFFFF" .. target .. "|r")
    SBS.Sync:BroadcastCombatLog("Мастер накладывает " .. def.name .. " на " .. target .. " (" .. value .. ", " .. rounds .. " р.)")
end

-- Наложить эффект на НПЦ (по цели в игре)
-- /sbsnpceffect <эффект> [значение] [раунды]
-- Эффекты: stun, weakness_fortitude, weakness_reflex, weakness_will, bleeding
SLASH_SBSNPCEFFECT1 = "/sbsnpceffect"
SlashCmdList["SBSNPCEFFECT"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local effectId, value, rounds = msg:match("^(%S+)%s*(%d*)%s*(%d*)$")
    if not effectId then
        SBS.Utils:Error("Использование: /sbsnpceffect <эффект> [значение] [раунды]")
        SBS.Utils:Info("Эффекты: stun, weakness_fortitude, weakness_reflex, weakness_will, bleeding")
        return
    end

    local npcGuid = UnitGUID("target")
    if not npcGuid then
        SBS.Utils:Error("Выберите НПЦ в качестве цели!")
        return
    end

    local npcData = SBS.Units:Get(npcGuid)
    if not npcData then
        SBS.Utils:Error("Цель не является НПЦ в системе SBS!")
        return
    end

    local def = SBS.Effects.Definitions[effectId]
    if not def then
        SBS.Utils:Error("Неизвестный эффект: " .. effectId)
        return
    end

    value = tonumber(value) or def.fixedValue or 1
    rounds = tonumber(rounds) or def.fixedDuration or 2

    SBS.Effects:Apply("npc", npcGuid, effectId, value, rounds, "Мастер")
    SBS.Effects:BroadcastAllEffects()
    local npcName = npcData.name or "НПЦ"
    SBS.Utils:Info("Эффект |cFFFFD700" .. def.name .. "|r наложен на |cFFFF6666" .. npcName .. "|r")
    SBS.Sync:BroadcastCombatLog("Мастер накладывает " .. def.name .. " на " .. npcName .. " (" .. value .. ", " .. rounds .. " р.)")
end

-- Быстро оглушить НПЦ
-- /sbsnpcstun [раунды]
SLASH_SBSNPCSTUN1 = "/sbsnpcstun"
SlashCmdList["SBSNPCSTUN"] = function(msg)
    if not SBS.Utils:RequireMaster() then return end

    local rounds = tonumber(msg) or 1

    local npcGuid = UnitGUID("target")
    if not npcGuid then
        SBS.Utils:Error("Выберите НПЦ в качестве цели!")
        return
    end

    local npcData = SBS.Units:Get(npcGuid)
    if not npcData then
        SBS.Utils:Error("Цель не является НПЦ в системе SBS!")
        return
    end

    SBS.Effects:Apply("npc", npcGuid, "stun", 0, rounds, "Мастер")
    SBS.Effects:BroadcastAllEffects()
    local npcName = npcData.name or "НПЦ"
    SBS.Utils:Info("|cFFFF6666" .. npcName .. "|r оглушен на |cFFFFD700" .. rounds .. "|r р.")
    SBS.Sync:BroadcastCombatLog("Мастер оглушает " .. npcName .. " на " .. rounds .. " р.")
end

-- ═══════════════════════════════════════════════════════════
-- ИНФОРМАЦИЯ ОБ АДДОНЕ
-- ═══════════════════════════════════════════════════════════

function SBS:ShowAddonInfoTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cFFFFD700SBS — Story Battle System|r", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Версия:", "|cFF00FF00" .. SBS.Config.VERSION .. "|r", 0.7, 0.7, 0.7)
    GameTooltip:AddDoubleLine("Разработчик:", "|cFF66CCFF" .. SBS.Config.AUTHOR .. "|r", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFF888888Система пошагового боя для RP|r", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКА ВЕРСИЙ (МАСТЕР)
-- ═══════════════════════════════════════════════════════════

function SBS:MasterCheckVersions()
    if not SBS.Utils:RequireMaster() then return end
    if not IsInGroup() then
        SBS.Utils:Error("Вы не в группе!")
        return
    end

    -- Очищаем старые данные
    SBS.Sync.VersionResponses = {}
    SBS.Sync.VersionCheckTime = GetTime()

    -- Запрашиваем версии
    SBS.Sync:Send("VERSION_REQUEST")
    SBS.Utils:Info("Запрос версий отправлен...")

    -- Через 3 секунды показываем результаты
    C_Timer.After(3, function()
        SBS:ShowVersionCheckResults()
    end)
end

function SBS:ShowVersionCheckResults()
    local responses = SBS.Sync.VersionResponses or {}
    local myName = UnitName("player")

    print("|cFFFFD700[SBS]|r |cFF66CCFF=== Версии аддона ===|r")

    -- Добавляем себя
    print(string.format("  |cFFFFFFFF%s|r: |cFF00FF00%s|r", myName, SBS.Config.VERSION))

    -- Показываем ответы
    for name, version in pairs(responses) do
        local color = version == SBS.Config.VERSION and "00FF00" or "FF6666"
        print(string.format("  |cFFFFFFFF%s|r: |cFF%s%s|r", name, color, version))
    end

    -- Проверяем кто не ответил
    local noResponse = {}
    local numMembers = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"

    for i = 1, numMembers do
        local unit = prefix .. i
        local name = UnitName(unit)
        if name and name ~= myName and not responses[name] then
            table.insert(noResponse, name)
        end
    end

    if #noResponse > 0 then
        print("|cFF888888  Не ответили (нет аддона?): " .. table.concat(noResponse, ", ") .. "|r")
    end
end
