-- SBS/Core/Aliases.lua
-- Алиасы функций для вызова из XML и совместимости
-- Компактная версия с автогенерацией

local ADDON_NAME, SBS = ...

-- ═══════════════════════════════════════════════════════════
-- АВТОГЕНЕРАЦИЯ АЛИАСОВ
-- ═══════════════════════════════════════════════════════════

-- Формат: { "SBS:Method", "Module", "ModuleMethod" }
-- Если ModuleMethod не указан, используется Method
local aliases = {
    -- Combat
    { "Attack", "Combat" },
    { "Heal", "Combat" },
    { "Shield", "Combat" },
    { "DoCheck", "Combat", "Check" },
    { "ProcessNPCAttack", "Combat" },
    { "ProcessModifyHP", "Combat" },
    { "ProcessHeal", "Combat" },
    { "ProcessShield", "Combat" },
    { "SetAttackingNPC", "Combat" },

    -- UI
    { "UpdateMainFrame", "UI" },
    { "ToggleGMPanel", "UI" },
    { "SetGMPanelTab", "UI" },
    { "ToggleMasterFrame", "UI", "ToggleGMPanel" },
    { "UpdateAttackingNPCDisplay", "UI" },
    { "InitMainFrameUI", "UI" },
    { "MasterAddWound", "UI" },
    { "MasterRemoveWound", "UI" },
    { "MasterGiveXP", "UI" },
    { "MasterRemoveXP", "UI" },
    { "MasterSetLevel", "UI" },
    { "MasterSetSpec", "UI" },
    { "MasterResetStats", "UI" },
    { "MasterGiveShield", "UI" },
    { "ApplyGiveShield", "UI" },
    { "MasterSync", "UI" },
    { "MasterGiveEnergy", "UI" },
    { "MasterTakeEnergy", "UI" },
    { "MasterRestoreEnergy", "UI" },
    
    -- Dialogs
    { "ShowAttackMenu", "Dialogs" },
    { "ShowCheckMenu", "Dialogs" },
    { "ShowSetHPDialog", "Dialogs" },
    { "ApplySetHP", "Dialogs" },
    { "ShowDefenseDialog", "Dialogs" },
    { "ApplyDefenseFromDialog", "Dialogs", "ApplyDefense" },
    { "ShowModifyNPCHPDialog", "Dialogs" },
    { "ApplyModifyNPCHP", "Dialogs" },
    { "ShowNPCAttackDialog", "Dialogs" },
    { "ShowNPCAttackDefenseMenu", "Dialogs" },
    { "ApplyNPCAttack", "Dialogs" },
    { "ShowModifyPlayerHPDialog", "Dialogs" },
    { "ApplyModifyPlayerHP", "Dialogs" },
    { "ShowPlayerActionsMenu", "Dialogs" },
    { "ShowSpecDialog", "Dialogs" },
    { "ApplyGiveXP", "Dialogs" },
    { "ApplySetLevel", "Dialogs" },
    
    -- CombatLog
    { "AddToCombatLog", "CombatLog", "Add" },
    { "AddToMasterLog", "CombatLog", "AddMasterLog" },
    { "ToggleCombatLog", "CombatLog", "Toggle" },
    
    -- TurnSystem
    { "StartCombat", "TurnSystem" },
    { "EndCombat", "TurnSystem" },
    { "NPCTurn", "TurnSystem", "StartNPCTurn" },
    { "PlayersTurn", "TurnSystem", "StartPlayersTurn" },
    { "AddToCombat", "TurnSystem", "AddParticipant" },
    { "RemoveFromCombat", "TurnSystem", "RemoveParticipant" },
    { "GiveFreeAction", "TurnSystem" },
    { "CanAct", "TurnSystem" },
    { "IsMyTurn", "TurnSystem" },
    { "IsCombatActive", "TurnSystem", "IsActive" },
    { "OnActionPerformed", "TurnSystem" },
}

-- Генерируем алиасы
for _, alias in ipairs(aliases) do
    local method, module, target = alias[1], alias[2], alias[3] or alias[1]
    SBS[method] = function(self, ...)
        local mod = SBS[module]
        if mod and mod[target] then
            return mod[target](mod, ...)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- СПЕЦИАЛЬНЫЕ АЛИАСЫ (с логикой)
-- ═══════════════════════════════════════════════════════════

function SBS:ShowTooltip(frame, title, desc)
    SBS.UI:ShowModernTooltip(frame, title, desc)
end

function SBS:ModifyPlayerHealth(amount)
    -- Блокируем изменение HP когда в группе с мастером
    if not SBS.Stats:CanModifyHP() then
        SBS.Utils:Error("Изменение HP заблокировано! Обратитесь к ведущему.")
        return
    end
    SBS.Stats:ModifyHP(amount)
    if SBS.Sync then SBS.Sync:BroadcastPlayerData() end
end

function SBS:RemoveTargetHP()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Нет цели!")
        return
    end
    if SBS.Units then
        SBS.Units:Remove(guid)
        SBS.Utils:Info("Удалено: " .. name)
    end
end

function SBS:ClearAllNPCConfirm()
    if SBS.Units then SBS.Units:ClearAllConfirm() end
end

function SBS:SkipTurn()
    if SBS.Sync:IsMaster() then
        SBS.TurnSystem:SkipTurn()
    else
        SBS.TurnSystem:PlayerSkipTurn()
    end
end

function SBS:ToggleTurnQueue()
    if SBS.UI and SBS.UI.ToggleTurnQueue then
        SBS.UI:ToggleTurnQueue()
    end
end

function SBS:ClearAttackingNPC()
    if SBS.Combat and SBS.Combat.ClearAttackingNPC then
        SBS.Combat:ClearAttackingNPC()
    end
    if SBS.UI and SBS.UI.UpdateAttackingNPCDisplay then
        SBS.UI:UpdateAttackingNPCDisplay()
    end
end

-- ═══════════════════════════════════════════════════════════
-- GM ПАНЕЛЬ - ПОШАГОВЫЙ БОЙ
-- ═══════════════════════════════════════════════════════════

function SBS:UpdateExcludeMasterButton()
    local btn = SBS_GMPanel_ExcludeMasterBtn
    local textFS = SBS_GMPanel_ExcludeMasterBtn_Text
    if not btn or not textFS then return end

    if btn.excludeMaster then
        textFS:SetText("|cFF66FF66Без ведущего в очереди|r")
    else
        textFS:SetText("|cFFFFFF00С ведущим в очереди|r")
    end
end

-- Переключение режима боя (радиокнопки)
function SBS:GMToggleModeCheckbox(checkbox, mode)
    local freeBtn = SBS_GMPanel_ModeFreeCheckBtn
    local queueBtn = SBS_GMPanel_ModeQueueCheckBtn

    if mode == "free" then
        freeBtn:SetChecked(true)
        queueBtn:SetChecked(false)
    else
        freeBtn:SetChecked(false)
        queueBtn:SetChecked(true)
    end
end

-- Переключение использования таймера
function SBS:GMToggleTimerCheckbox()
    local timerCheckbox = SBS_GMPanel_UseTimerCheckBtn
    local timerFrame = SBS_GMPanel_TimerFrame

    if timerCheckbox:GetChecked() then
        timerFrame:Show()
    else
        timerFrame:Hide()
    end
end

-- Получить выбранный режим
function SBS:GMGetSelectedMode()
    local freeBtn = SBS_GMPanel_ModeFreeCheckBtn
    if freeBtn and freeBtn:GetChecked() then
        return "free"
    else
        return "queue"
    end
end

-- Получить настройку таймера
function SBS:GMGetUseTimer()
    local timerCheckbox = SBS_GMPanel_UseTimerCheckBtn
    return timerCheckbox and timerCheckbox:GetChecked() or false
end

function SBS:GMStartCombat()
    if SBS.TurnSystem:IsActive() then
        SBS.TurnSystem:EndCombat()
    else
        -- Получаем режим боя
        local mode = self:GMGetSelectedMode()

        -- Получаем настройку таймера
        local useTimer = self:GMGetUseTimer()

        -- Получаем длительность (только если таймер включен)
        local duration = 60
        if useTimer then
            local timerInput = SBS_GMPanel_TimerFrame_Input
            duration = timerInput and tonumber(timerInput:GetText()) or 60
            duration = math.max(10, math.min(300, duration))
        end

        -- Получаем настройку исключения мастера
        local btn = SBS_GMPanel_ExcludeMasterBtn
        local excludeMaster = btn and btn.excludeMaster or false

        -- Запускаем бой с новой сигнатурой
        SBS.TurnSystem:StartCombat(mode, useTimer, duration, excludeMaster)
    end
    SBS.UI:UpdateGMCombatButtons()
end

function SBS:GMSkipTurn()
    if not SBS.TurnSystem:IsActive() then
        SBS.Utils:Error("Бой не начат!")
        return
    end
    SBS.TurnSystem:SkipTurn()
end

function SBS:GMToggleNPCTurn()
    if not SBS.TurnSystem:IsActive() then
        SBS.Utils:Error("Бой не начат!")
        return
    end
    
    if SBS.TurnSystem.phase == "npc" then
        SBS.TurnSystem:StartPlayersTurn()
    else
        SBS.TurnSystem:StartNPCTurn()
    end
    SBS.UI:UpdateGMCombatButtons()
end

function SBS:GMFreeAction()
    if not SBS.TurnSystem:IsActive() then
        SBS.Utils:Error("Бой не начат!")
        return
    end
    
    local target = UnitName("target")
    if not target then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    
    if not UnitIsPlayer("target") then
        SBS.Utils:Error("Цель должна быть игроком!")
        return
    end
    
    SBS.TurnSystem:GiveFreeAction(target)
end

-- ═══════════════════════════════════════════════════════════
-- КНОПКИ ЭФФЕКТОВ МАСТЕРА (GM Panel)
-- ═══════════════════════════════════════════════════════════

function SBS:MasterApplyStun()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    local isPlayer = SBS.Utils:IsTargetPlayer()
    local targetType = isPlayer and "player" or "npc"
    local targetId = isPlayer and name or guid
    SBS.Dialogs:ShowMasterEffectDialog("stun", targetType, targetId)
end

function SBS:MasterApplyDot()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    local isPlayer = SBS.Utils:IsTargetPlayer()
    local targetType = isPlayer and "player" or "npc"
    local targetId = isPlayer and name or guid
    SBS.Dialogs:ShowMasterEffectDialog("dot_master", targetType, targetId)
end

function SBS:MasterApplyVulnerability()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    local isPlayer = SBS.Utils:IsTargetPlayer()
    local targetType = isPlayer and "player" or "npc"
    local targetId = isPlayer and name or guid
    local targetName = isPlayer and name or (SBS.Units:Get(guid) and SBS.Units:Get(guid).name or "NPC")
    SBS.Dialogs:ShowVulnerabilityDialog(targetType, targetId, targetName)
end

function SBS:MasterApplyWeakness()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    local targetType = UnitIsPlayer("target") and "player" or "npc"
    local targetId = targetType == "player" and name or guid
    
    SBS.Dialogs:ShowWeaknessDialog(targetType, targetId, name)
end

function SBS:MasterApplyBuff()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not UnitIsPlayer("target") then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    SBS.Dialogs:ShowMasterBuffDialog(name)
end

function SBS:MasterPurge()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    local targetType = UnitIsPlayer("target") and "player" or "npc"
    local targetId = targetType == "player" and name or guid
    
    -- Ищем баффы для снятия
    local effects = SBS.Effects:GetAll(targetType, targetId)
    local buffsFound = false
    for effectId, _ in pairs(effects) do
        local def = SBS.Effects.Definitions[effectId]
        if def and def.type == "buff" then
            SBS.Effects:Remove(targetType, targetId, effectId)
            SBS.Utils:Info("Снят бафф: " .. def.name .. " с " .. name)
            buffsFound = true
            break
        end
    end
    
    if not buffsFound then
        SBS.Utils:Error("На цели нет баффов!")
    end
end

function SBS:MasterDispel()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    local targetType = UnitIsPlayer("target") and "player" or "npc"
    local targetId = targetType == "player" and name or guid
    
    -- Ищем дебаффы для снятия
    local effects = SBS.Effects:GetAll(targetType, targetId)
    local debuffsFound = false
    for effectId, _ in pairs(effects) do
        local def = SBS.Effects.Definitions[effectId]
        if def and (def.type == "debuff" or def.type == "dot") then
            SBS.Effects:Remove(targetType, targetId, effectId)
            SBS.Utils:Info("Снят дебафф: " .. def.name .. " с " .. name)
            debuffsFound = true
            break
        end
    end
    
    if not debuffsFound then
        SBS.Utils:Error("На цели нет дебаффов!")
    end
end

function SBS:MasterClearAllEffects()
    if not SBS.Utils:RequireMaster() then return end
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end
    
    local targetType = UnitIsPlayer("target") and "player" or "npc"
    local targetId = targetType == "player" and name or guid
    
    SBS.Effects:ClearTarget(targetType, targetId)
    SBS.Utils:Info("Все эффекты сняты с " .. name)
end
