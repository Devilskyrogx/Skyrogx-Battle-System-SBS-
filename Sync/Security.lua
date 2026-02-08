-- SBS/Sync/Security.lua
-- Система безопасности: валидация команд, подтверждения

local ADDON_NAME, SBS = ...

-- ═══════════════════════════════════════════════════════════
-- КЛАССИФИКАЦИЯ КОМАНД
-- ═══════════════════════════════════════════════════════════

-- Команды только для мастера
local MASTER_ONLY_COMMANDS = {
    GIVEXP = true,
    REMOVEXP = true,
    SETLEVEL = true,
    SETSPEC = true,
    ADDWOUND = true,
    REMOVEWOUND_MASTER = true,
    RESETSTATS = true,
    GIVESHIELD = true,
    MODIFYHP = true,
    NPCATTACK = true,
    COMBAT_START = true,
    COMBAT_END = true,
    ROUND_START = true,
    TURN_CHANGE = true,
    PHASE_CHANGE = true,
    SKIP_TURN = true,
    FREE_ACTION = true,
    ACTED = true,
    EFFECT_TICK = true,    -- Тик эффектов только от мастера
    GIVEENERGY = true,
    TAKEENERGY = true,
    RESTOREENERGY = true,
    SPECIALACTION_APPROVED = true,
    SPECIALACTION_REJECTED = true,
}

-- Безопасные команды (от любого в группе)
local SAFE_COMMANDS = {
    PLAYERDATA = true,
    PLAYERHP = true,
    REQUESTHP = true,
    COMBATLOG = true,
    MASTER = true,
    PING = true,
    HEAL = true,
    SHIELD = true,
    REMOVEWOUND = true,
    ACTION_DONE = true,
    PLAYER_SKIP = true,
    DEFENSE_RESULT = true,
    PLAYERHPCHANGE = true,
    CONFIRM_RESPONSE = true,
    UNIT = true,
    HPCHANGE = true,
    REMOVE = true,
    CLEAR = true,
    REQUEST = true,
    FULLDATA = true,
    PARTICIPANT_ADD = true,
    PARTICIPANT_REMOVE = true,
    PLAYER_ACTED = true,
    EFFECT_APPLY = true,   -- Применение эффекта
    EFFECT_REMOVE = true,  -- Снятие эффекта
}

-- ═══════════════════════════════════════════════════════════
-- ПРОВЕРКА ГРУППЫ
-- ═══════════════════════════════════════════════════════════

local function IsInMyGroup(senderName)
    if not IsInGroup() then return false end
    
    if senderName == UnitName("player") then return true end
    
    if IsInRaid() then
        for i = 1, 40 do
            local name = GetRaidRosterInfo(i)
            if name and name == senderName then
                return true
            end
        end
    else
        for i = 1, 4 do
            local name = UnitName("party" .. i)
            if name and name == senderName then
                return true
            end
        end
    end
    
    return false
end

local function IsSenderMaster(senderName)
    return SBS.Sync.MasterName == senderName
end

-- ═══════════════════════════════════════════════════════════
-- ВАЛИДАЦИЯ
-- ═══════════════════════════════════════════════════════════

function SBS.Sync:ValidateCommand(cmd, sender)
    -- Свои команды всегда разрешены
    if sender == UnitName("player") then
        return true
    end
    
    -- Вне группы — блокируем всё от других
    if not IsInGroup() then
        return false, "not_in_group"
    end
    
    -- Отправитель не в группе
    if not IsInMyGroup(sender) then
        return false, "not_in_group"
    end
    
    -- Мастер-команда от не-мастера
    if MASTER_ONLY_COMMANDS[cmd] and not IsSenderMaster(sender) then
        return false, "not_master"
    end
    
    return true
end

function SBS.Sync:LogSecurityEvent(cmd, sender, reason)
    local reasonText = {
        not_in_group = "не в группе",
        not_master = "не является мастером",
    }
    SBS.Utils:Warn("Заблокировано: " .. cmd .. " от " .. sender .. " (" .. (reasonText[reason] or reason) .. ")")
end

-- ═══════════════════════════════════════════════════════════
-- ДИАЛОГ ПОДТВЕРЖДЕНИЯ
-- ═══════════════════════════════════════════════════════════

local confirmDialog = nil

function SBS.Sync:ShowConfirmDialog(cmdType, sender, title, message, onAccept)
    -- Закрываем предыдущий диалог если есть
    if confirmDialog then
        confirmDialog:Hide()
    end
    
    -- Создаём фрейм
    confirmDialog = CreateFrame("Frame", "SBS_ConfirmDialog", UIParent, "BackdropTemplate")
    confirmDialog:SetSize(320, 180)
    confirmDialog:SetPoint("CENTER")
    confirmDialog:SetFrameStrata("DIALOG")
    confirmDialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    confirmDialog:SetBackdropColor(0.1, 0.05, 0.05, 0.95)
    confirmDialog:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    
    -- Заголовок
    local titleText = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -15)
    titleText:SetText("|cFFFF6666" .. title .. "|r")
    
    -- Отправитель
    local senderText = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    senderText:SetPoint("TOP", 0, -40)
    senderText:SetText("От: |cFFA06AF1" .. sender .. "|r")
    
    -- Сообщение
    local msgText = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgText:SetPoint("TOP", 0, -65)
    msgText:SetPoint("LEFT", 20, 0)
    msgText:SetPoint("RIGHT", -20, 0)
    msgText:SetText(message)
    msgText:SetJustifyH("CENTER")
    msgText:SetWordWrap(true)
    
    -- Кнопка Подтвердить
    local acceptBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
    acceptBtn:SetSize(100, 28)
    acceptBtn:SetPoint("BOTTOMLEFT", 30, 15)
    acceptBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    acceptBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    acceptBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    local acceptText = acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    acceptText:SetPoint("CENTER")
    acceptText:SetText("|cFFFFFFFFПодтвердить|r")
    
    acceptBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.3, 1)
    end)
    acceptBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
    end)
    acceptBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if onAccept then onAccept() end
        SBS.Sync:Send("CONFIRM_RESPONSE", cmdType .. ";ACCEPTED;" .. sender)
    end)
    
    -- Кнопка Отклонить
    local declineBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
    declineBtn:SetSize(100, 28)
    declineBtn:SetPoint("BOTTOMRIGHT", -30, 15)
    declineBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    declineBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    declineBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    
    local declineText = declineBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    declineText:SetPoint("CENTER")
    declineText:SetText("|cFFFFFFFFОтклонить|r")
    
    declineBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.3, 0.3, 1)
    end)
    declineBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.2, 1)
    end)
    declineBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        SBS.Utils:Info("Действие отклонено")
        SBS.Sync:Send("CONFIRM_RESPONSE", cmdType .. ";DECLINED;" .. sender)
    end)
    
    -- Звук предупреждения
    PlaySound(8959, "SFX") -- RAID_WARNING
    
    confirmDialog:Show()
    
    -- Автоматическое закрытие через 30 секунд
    C_Timer.After(30, function()
        if confirmDialog and confirmDialog:IsShown() then
            confirmDialog:Hide()
            SBS.Utils:Warn("Время на подтверждение истекло — действие отклонено")
            SBS.Sync:Send("CONFIRM_RESPONSE", cmdType .. ";TIMEOUT;" .. sender)
        end
    end)
end
