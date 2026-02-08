-- SBS/UI/MainFrame.lua
-- Modern UI - Main Frame Logic

local ADDON_NAME, SBS = ...

-- Кэширование глобальных функций
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local string_format = string.format
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local SetPortraitTexture = SetPortraitTexture
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate

SBS.UI = SBS.UI or {}
SBS.UI.NameplateFrames = {}
SBS.UI.FloatingTextPool = {}

-- Throttling для обновлений UI
local pendingMainFrameUpdate = false
local pendingNameplateUpdate = false
local THROTTLE_DELAY = 0.05

-- Текстуры
local TEX_PATH = "Interface\\AddOns\\SBS\\texture\\"

-- Конфиг статов
local STAT_CONFIG = {
    Strength = {
        label = "Сила",
        icon = TEX_PATH .. "sword",
        color = {0.77, 0.12, 0.23},
    },
    Dexterity = {
        label = "Ловкость", 
        icon = TEX_PATH .. "activity",
        color = {0, 1, 0.59},
    },
    Intelligence = {
        label = "Интеллект",
        icon = TEX_PATH .. "brain",
        color = {0, 0.44, 0.87},
    },
    Spirit = {
        label = "Дух",
        icon = TEX_PATH .. "ghost",
        color = {1, 1, 1},
    },
    Fortitude = {
        label = "Стойкость",
        icon = TEX_PATH .. "shield",
        color = {0.64, 0.19, 0.79},
    },
    Reflex = {
        label = "Сноровка",
        icon = TEX_PATH .. "activity",
        color = {1, 0.49, 0.04},
    },
    Will = {
        label = "Воля",
        icon = TEX_PATH .. "ghost",
        color = {0.53, 0.53, 0.93},
    },
}

local STAT_ORDER = {"Strength", "Dexterity", "Intelligence", "Spirit", "Fortitude", "Reflex", "Will"}

function SBS.UI:Init()
    self:CreateMinimapButton()
    self:RegisterEvents()
end

-- Регистрация на внутренние события SBS
function SBS.UI:RegisterEvents()
    local UI = self  -- Захватываем self для замыканий

    -- ═══════════════════════════════════════════════════════════
    -- THROTTLED ОБНОВЛЕНИЯ (предотвращают множественные обновления за один frame)
    -- ═══════════════════════════════════════════════════════════
    
    local function QueueMainFrameUpdate()
        if pendingMainFrameUpdate then return end
        pendingMainFrameUpdate = true
        C_Timer.After(THROTTLE_DELAY, function()
            pendingMainFrameUpdate = false
            UI:UpdateMainFrame()
        end)
    end
    
    local function QueueNameplateUpdate()
        if pendingNameplateUpdate then return end
        pendingNameplateUpdate = true
        C_Timer.After(THROTTLE_DELAY, function()
            pendingNameplateUpdate = false
            UI:UpdateAllNameplates()
        end)
    end

    -- ═══════════════════════════════════════════════════════════
    -- WoW СОБЫТИЯ (через отдельный фрейм)
    -- ═══════════════════════════════════════════════════════════
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            -- Обновляем секцию цели
            UI:UpdateTargetSection()
            -- Обновляем эффекты на цели
            if SBS.UI.Effects then
                SBS.UI.Effects:UpdateTarget()
            end
        end
    end)

    -- ═══════════════════════════════════════════════════════════
    -- ВНУТРЕННИЕ СОБЫТИЯ SBS
    -- ═══════════════════════════════════════════════════════════

    -- Хелпер: обновить таргет-фрейм если смотрим на себя
    local function UpdateTargetIfSelf()
        if UnitIsUnit("target", "player") then
            UI:UpdateTargetSection()
            -- Также обновляем эффекты
            if SBS.UI.Effects then
                SBS.UI.Effects:UpdateTarget()
            end
        end
    end

    -- HP изменилось
    SBS.Events:Register("PLAYER_HP_CHANGED", function(currentHP, maxHP)
        QueueMainFrameUpdate()
        QueueNameplateUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- XP изменился
    SBS.Events:Register("PLAYER_XP_CHANGED", function(currentXP, xpToLevel)
        QueueMainFrameUpdate()
    end, UI)

    -- Уровень изменился
    SBS.Events:Register("PLAYER_LEVEL_CHANGED", function(newLevel, oldLevel)
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Ранения изменились
    SBS.Events:Register("PLAYER_WOUND_CHANGED", function(wounds)
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Щит изменился
    SBS.Events:Register("PLAYER_SHIELD_CHANGED", function(shield)
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Статы изменились
    SBS.Events:Register("PLAYER_STATS_CHANGED", function()
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Специализация изменилась
    SBS.Events:Register("PLAYER_SPEC_CHANGED", function(newSpec, oldSpec)
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Энергия изменилась
    SBS.Events:Register("PLAYER_ENERGY_CHANGED", function(currentEnergy, maxEnergy)
        QueueMainFrameUpdate()
        UpdateTargetIfSelf()
    end, UI)

    -- Юнит HP изменился (NPC)
    SBS.Events:Register("UNIT_HP_CHANGED", function(guid, currentHP, maxHP)
        UI:UpdateTargetSection()
        QueueNameplateUpdate()
    end, UI)
    
    -- NPC удалён/очищен/импортирован/создан
    SBS.Events:Register("UNIT_CREATED", function(guid, data)
        UI:UpdateTargetSection()
        QueueNameplateUpdate()
    end, UI)
    
    SBS.Events:Register("UNIT_REMOVED", function(guid)
        UI:UpdateTargetSection()
        QueueNameplateUpdate()
    end, UI)
    
    SBS.Events:Register("UNITS_CLEARED", function()
        UI:UpdateTargetSection()
        QueueNameplateUpdate()
    end, UI)
    
    SBS.Events:Register("UNITS_IMPORTED", function()
        UI:UpdateTargetSection()
        QueueNameplateUpdate()
    end, UI)
    
    -- Бой начался/закончился
    SBS.Events:Register("COMBAT_STARTED", function()
        UI:UpdateMainFrame()
    end, UI)
    
    SBS.Events:Register("COMBAT_ENDED", function()
        UI:UpdateMainFrame()
    end, UI)
    
    -- Ход сменился
    SBS.Events:Register("TURN_CHANGED", function(playerName, isMyTurn)
        UI:UpdateMainFrame()
    end, UI)
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ ФРЕЙМА
-- ═══════════════════════════════════════════════════════════

function SBS.UI:InitMainFrameUI()
    -- Применяем масштаб из настроек
    if SBS.Settings and SBS.Settings.ApplyUIScale then
        SBS.Settings:ApplyUIScale()
    end

    local p = "SBS_MainFrame_"

    -- Топ-бар иконка
    local topIcon = _G[p.."TopBar_Icon"]
    if topIcon then
        topIcon:SetTexture(TEX_PATH .. "sword")
        topIcon:SetVertexColor(0.96, 0.55, 0.73)
    end
    
    -- Портрет игрока
    local portrait = _G[p.."PlayerHeader_Portrait_Texture"]
    if portrait then
        SetPortraitTexture(portrait, "player")
    end
    
    -- Points badge icon (теперь в StatsPanel)
    local pointsIcon = _G[p.."StatsPanel_PointsBadge_Icon"]
    if pointsIcon then
        pointsIcon:SetTexture(TEX_PATH .. "plus")
        pointsIcon:SetVertexColor(0.9, 0.75, 0)
    end
    
    -- Wounds icon (новый путь через HPContainer)
    local woundsIcon = _G[p.."HealthSection_HPContainer_WoundsBadge_Icon"]
    if woundsIcon then
        woundsIcon:SetTexture(TEX_PATH .. "skull")
        woundsIcon:SetVertexColor(1, 0.4, 0.4)
    end
    
    -- Target portrait icon
    local targetIcon = _G[p.."TargetFrame_Portrait_Icon"]
    if targetIcon then
        targetIcon:SetTexture(TEX_PATH .. "skull")
        targetIcon:SetVertexColor(0.5, 0, 0)
    end
    
    -- Инициализация строк статов
    self:InitStatRows()
    
    -- Инициализация UI эффектов
    if self.InitEffectsUI then
        self:InitEffectsUI()
    end
    
    -- Обновить всё
    self:UpdateMainFrame()
end

function SBS.UI:InitStatRows()
    local p = "SBS_MainFrame_StatsPanel_"
    
    for _, stat in ipairs(STAT_ORDER) do
        local cfg = STAT_CONFIG[stat]
        local rowPrefix = p .. stat .. "_"
        
        -- Иконка
        local icon = _G[rowPrefix .. "Icon"]
        if icon then
            icon:SetTexture(cfg.icon)
            icon:SetVertexColor(cfg.color[1], cfg.color[2], cfg.color[3], 0.9)
        end
        
        -- Название
        local label = _G[rowPrefix .. "Label"]
        if label then
            label:SetText(cfg.label)
        end
        
        -- Значение - цвет
        local value = _G[rowPrefix .. "Value"]
        if value then
            value:SetTextColor(cfg.color[1], cfg.color[2], cfg.color[3])
        end
        
        -- Кнопка добавления
        local addBtn = _G[rowPrefix .. "AddBtn"]
        if addBtn then
            addBtn:SetScript("OnClick", function()
                SBS:AddPoint(stat)
                SBS:UpdateMainFrame()
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПЕРЕКЛЮЧЕНИЕ ОКОН
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ToggleMainFrame()
    if SBS_MainFrame then
        if SBS_MainFrame:IsShown() then
            SBS_MainFrame:Hide()
            if SBS_GMPanel then SBS_GMPanel:Hide() end
        else
            SBS_MainFrame:Show()
        end
    end
end

function SBS.UI:ToggleGMPanel()
    if not SBS_GMPanel then return end
    if not SBS.Sync:IsMaster() and IsInGroup() then 
        SBS.Utils:Error("Только ведущий!") 
        return 
    end
    if SBS_GMPanel:IsShown() then
        SBS_GMPanel:Hide()
    else
        SBS_GMPanel:Show()
        self:SetGMPanelTab(1) -- Открываем на первой вкладке
        self:UpdateGMCombatButtons() -- Синхронизируем состояние чекбоксов
    end
end

-- Управление видимостью кнопки GM Panel (шестерёнка)
function SBS.UI:UpdateGMButtonVisibility()
    local gmBtn = _G["SBS_MainFrame_TopBar_GMBtn"]
    if not gmBtn then return end

    -- Показываем только если ведущий группы/рейда или не в группе
    local canShow = not IsInGroup() or UnitIsGroupLeader("player")

    if canShow then
        gmBtn:Show()
    else
        gmBtn:Hide()
        -- Также скрываем GM Panel если она открыта
        if SBS_GMPanel and SBS_GMPanel:IsShown() then
            SBS_GMPanel:Hide()
        end
    end

    -- Обновляем отображение атакующего NPC
    self:UpdateAttackingNPCDisplay()
end

-- Управление видимостью кнопки журнала боя
function SBS.UI:UpdateCombatLogButton()
    -- Эта функция вызывается из Settings.lua при изменении настройки
    -- Кнопка журнала в миникарте всегда видна, но при клике проверяется настройка
end

function SBS.UI:UpdateAttackingNPCDisplay()
    local displayText = _G["SBS_GMPanel_AttackerDisplay_Text"]
    local clearBtn = _G["SBS_GMPanel_AttackerDisplay_ClearBtn"]

    if not displayText or not clearBtn then return end

    if SBS.Combat and SBS.Combat.AttackingNPC and SBS.Combat.AttackingNPC.name then
        displayText:SetText("Атакующий: " .. SBS.Combat.AttackingNPC.name)
        clearBtn:Show()
    else
        displayText:SetText("")
        clearBtn:Hide()
    end
end

-- Управление доступностью кнопок энергии (блокируются в группе)
function SBS.UI:UpdateEnergyButtonsState()
    local p = "SBS_MainFrame_HealthSection_"
    local energyMinusBtn = _G[p.."EnergyMinusBtn"]
    local energyPlusBtn = _G[p.."EnergyPlusBtn"]
    
    -- Кнопки доступны только если не в группе или сам лидер
    local canUse = not IsInGroup() or UnitIsGroupLeader("player")
    
    if energyMinusBtn then
        if canUse then
            energyMinusBtn:Enable()
            energyMinusBtn:SetAlpha(1)
        else
            energyMinusBtn:Disable()
            energyMinusBtn:SetAlpha(0.4)
        end
    end
    
    if energyPlusBtn then
        if canUse then
            energyPlusBtn:Enable()
            energyPlusBtn:SetAlpha(1)
        else
            energyPlusBtn:Disable()
            energyPlusBtn:SetAlpha(0.4)
        end
    end
end

function SBS.UI:SetGMPanelTab(tabIndex)
    if not SBS_GMPanel then return end

    -- Сохраняем текущую вкладку
    SBS_GMPanel.currentTab = tabIndex

    local tabs = {
        SBS_GMPanel_Tab1,
        SBS_GMPanel_Tab2,
        SBS_GMPanel_Tab3,
        SBS_GMPanel_Tab4
    }

    local contents = {
        SBS_GMPanel_TabContent1,
        SBS_GMPanel_TabContent2,
        SBS_GMPanel_TabContent3,
        SBS_GMPanel_TabContent4
    }

    -- Высоты контента каждой вкладки (определяются по самому нижнему элементу + отступ)
    local contentHeights = {
        242,  -- Tab1: Цель (AttackerDisplay -198 + высота 20 + отступ 24)
        204,  -- Tab2: Прогресс (RestoreEnergyBtn -176 + высота 24 + отступ 4)
        326,  -- Tab3: Бой (VersionCheckBtn -292 + высота 24 + отступ 10)
        270   -- Tab4: Эффекты (ClearEffectsBtn -236 + высота 24 + отступ 10)
    }

    for i, tab in ipairs(tabs) do
        if tab then
            if i == tabIndex then
                -- Активная вкладка
                tab:SetBackdropColor(0.2, 0.2, 0.2, 1)
                tab:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                local text = _G[tab:GetName() .. "_Text"]
                if text then text:SetTextColor(0.9, 0.9, 0.9) end
            else
                -- Неактивная вкладка
                tab:SetBackdropColor(0.12, 0.12, 0.12, 1)
                tab:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                local text = _G[tab:GetName() .. "_Text"]
                if text then text:SetTextColor(0.6, 0.6, 0.6) end
            end
        end
    end

    for i, content in ipairs(contents) do
        if content then
            if i == tabIndex then
                content:Show()
            else
                content:Hide()
            end
        end
    end

    -- Автоматическое изменение высоты GM Panel
    local baseHeight = 70  -- Заголовок (12) + Вкладки (34) + отступы сверху и снизу (24)
    local newHeight = baseHeight + (contentHeights[tabIndex] or 240)
    SBS_GMPanel:SetHeight(newHeight)
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ UI
-- ═══════════════════════════════════════════════════════════

function SBS.UI:UpdateMainFrame()
    if not SBS_MainFrame or not SBS_MainFrame:IsShown() then return end
    
    local p = "SBS_MainFrame_"
    local level = SBS.Stats:GetLevel()
    local gameLevel = SBS.Stats:GetGameLevel()
    local role = SBS.Stats:GetRole()
    local pointsLeft = SBS.Stats:GetPointsLeft()
    
    -- Уровень
    local levelText = _G[p.."PlayerHeader_Portrait_LevelFrame_Text"]
    if levelText then
        levelText:SetText(level)
    end
    
    -- Имя игрока
    local nameText = _G[p.."PlayerHeader_Info_Name"]
    if nameText then
        nameText:SetText(UnitName("player"))
    end
    
    -- Прогресс-бар (показывает прогресс до следующего уровня с очком)
    local xpBar = _G[p.."PlayerHeader_Info_XPBar"]
    local xpText = _G[p.."PlayerHeader_Info_XPBar_Text"]
    if xpBar and xpText then
        if gameLevel < SBS.Config.MIN_LEVEL then
            -- Уровень ниже минимального
            xpBar:SetMinMaxValues(0, SBS.Config.MIN_LEVEL)
            xpBar:SetValue(gameLevel)
            xpBar:SetStatusBarColor(0.4, 0.4, 0.4)
            xpText:SetText("Уровень " .. gameLevel .. " / " .. SBS.Config.MIN_LEVEL .. " для системы")
        elseif level >= SBS.Config.MAX_LEVEL then
            -- Максимальный уровень
            xpBar:SetMinMaxValues(0, 1)
            xpBar:SetValue(1)
            xpBar:SetStatusBarColor(0.8, 0.6, 0.2)
            xpText:SetText("МАКС. УРОВЕНЬ (" .. level .. ")")
        else
            -- Находим следующий уровень с очком
            local nextPointLevel = nil
            for lvl, pts in pairs(SBS.Config.PointsAtLevel) do
                if lvl > level and (not nextPointLevel or lvl < nextPointLevel) then
                    nextPointLevel = lvl
                end
            end
            
            if nextPointLevel then
                -- Показываем прогресс до следующего уровня с очком
                local prevPointLevel = level
                for lvl, pts in pairs(SBS.Config.PointsAtLevel) do
                    if lvl <= level and lvl > prevPointLevel then
                        prevPointLevel = lvl
                    end
                end
                -- Корректируем prevPointLevel если нужно
                for lvl, pts in pairs(SBS.Config.PointsAtLevel) do
                    if lvl <= level then
                        prevPointLevel = math.max(prevPointLevel, lvl)
                    end
                end
                
                local progress = level - SBS.Config.MIN_LEVEL
                local target = nextPointLevel - SBS.Config.MIN_LEVEL
                xpBar:SetMinMaxValues(0, target)
                xpBar:SetValue(progress)
                xpBar:SetStatusBarColor(0.35, 0.2, 0.46)
                xpText:SetText("Уровень " .. level .. " -> " .. nextPointLevel .. " (+1 очко)")
            else
                xpBar:SetMinMaxValues(0, 1)
                xpBar:SetValue(1)
                xpBar:SetStatusBarColor(0.8, 0.6, 0.2)
                xpText:SetText("Уровень " .. level)
            end
        end
    end
    
    -- Points badge (теперь в StatsPanel)
    local pointsBadge = _G[p.."StatsPanel_PointsBadge"]
    local pointsBadgeText = _G[p.."StatsPanel_PointsBadge_Text"]
    if pointsBadge then
        if pointsLeft > 0 then
            if pointsBadgeText then
                pointsBadgeText:SetText("+ " .. pointsLeft .. " Очков")
            end
            pointsBadge:Show()
        else
            pointsBadge:Hide()
        end
    end
    
    -- Health Bar (новый путь через HPContainer)
    local currentHP = SBS.Stats:GetCurrentHP()
    local maxHP = SBS.Stats:GetMaxHP()
    local shield = SBS.Stats:GetShield()
    
    local hpBar = _G[p.."HealthSection_HPContainer_HPBar"]
    local hpText = _G[p.."HealthSection_HPContainer_TextFrame_HPText"]
    local shieldBar = _G[p.."HealthSection_HPContainer_ShieldBar"]
    local shieldText = _G[p.."HealthSection_HPContainer_TextFrame_ShieldText"]
    
    if hpBar then
        hpBar:SetMinMaxValues(0, maxHP)
        hpBar:SetValue(currentHP)
        
        local pct = currentHP / maxHP
        if pct > 0.5 then
            hpBar:SetStatusBarColor(0.07, 0.56, 0.27)
        elseif pct > 0.25 then
            hpBar:SetStatusBarColor(0.8, 0.6, 0.1)
        else
            hpBar:SetStatusBarColor(0.7, 0.15, 0.1)
        end
    end
    
    if hpText then
        if shield > 0 then
            hpText:SetText(currentHP .. " / " .. maxHP)
        else
            hpText:SetText(currentHP .. " / " .. maxHP)
        end
    end
    
    -- Shield Bar (overlay)
    if shieldBar then
        -- Щит отображается как дополнительная полоска поверх HP
        -- Максимум = maxHP для масштабирования
        shieldBar:SetMinMaxValues(0, maxHP)
        shieldBar:SetValue(shield)
        
        if shield > 0 then
            shieldBar:Show()
        else
            shieldBar:Hide()
        end
    end
    
    if shieldText then
        if shield > 0 then
            shieldText:SetText("+" .. shield)
            shieldText:Show()
        else
            shieldText:Hide()
        end
    end
    
    -- Wounds badge (новый путь)
    local woundsBadge = _G[p.."HealthSection_HPContainer_WoundsBadge"]
    local woundsText = _G[p.."HealthSection_HPContainer_WoundsBadge_Text"]
    if woundsBadge then
        local wounds = SBS.Stats:GetWounds()
        if wounds > 0 then
            if woundsText then woundsText:SetText(wounds) end
            woundsBadge:Show()
        else
            woundsBadge:Hide()
        end
    end
    
    -- Energy Bar
    local energy = SBS.Stats:GetEnergy()
    local maxEnergy = SBS.Stats:GetMaxEnergy()
    
    local energyBar = _G[p.."HealthSection_EnergyBar"]
    local energyText = _G[p.."HealthSection_EnergyBar_Text"]
    
    if energyBar then
        energyBar:SetMinMaxValues(0, maxEnergy)
        energyBar:SetValue(energy)
        
        -- Цвет в зависимости от заполненности
        if energy == maxEnergy then
            energyBar:SetStatusBarColor(0.3, 0.5, 0.3)  -- Зелёный оттенок
        elseif energy == 0 then
            energyBar:SetStatusBarColor(0.5, 0.2, 0.2)  -- Красный оттенок
        else
            energyBar:SetStatusBarColor(0.4, 0.25, 0.6)  -- Фиолетовый
        end
    end
    
    if energyText then
        energyText:SetText(energy .. " / " .. maxEnergy)
    end
    
    -- Блокировка кнопок энергии в группе
    self:UpdateEnergyButtonsState()
    
    -- GM Panel settings button visibility
    self:UpdateGMButtonVisibility()
    
    -- Stats
    self:UpdateStats()
    
    -- Damage/Healing values
    local dmgValue = _G[p.."StatsPanel_DamageValue"]
    local healValue = _G[p.."StatsPanel_HealValue"]
    if dmgValue and healValue then
        local playerName = UnitName("player")
        local dmgRange = SBS.Config:GetDamageRange(level, role)
        local healRange = SBS.Config:GetHealingRange(level, role)

        -- Применяем модификаторы от баффов
        local dmgMod = SBS.Effects:GetModifier("player", playerName, "damage")
        local healMod = SBS.Effects:GetModifier("player", playerName, "healing")

        local effectiveDmgMin = dmgRange.min + dmgMod
        local effectiveDmgMax = dmgRange.max + dmgMod
        local effectiveHealMin = healRange.min + healMod
        local effectiveHealMax = healRange.max + healMod

        -- Форматируем с отображением модификатора если он есть
        local dmgStr = effectiveDmgMin .. "-" .. effectiveDmgMax
        if dmgMod ~= 0 then
            dmgStr = dmgStr .. " |cFF33FF66(+" .. dmgMod .. "-" .. dmgMod .. ")|r"
        end

        local healStr = effectiveHealMin .. "-" .. effectiveHealMax
        if healMod ~= 0 then
            healStr = healStr .. " |cFF33FF66(+" .. healMod .. "-" .. healMod .. ")|r"
        end

        dmgValue:SetText(dmgStr)
        healValue:SetText(healStr)
    end
    
    -- Role button (бывшая Spec button)
    local specBtnText = _G[p.."ActionBar_SpecBtn_Text"]
    if specBtnText then
        if SBS.Stats:CanChooseRole() and not role then
            specBtnText:SetText("|cFFFFD700Выбрать роль|r")
        elseif role then
            local data = SBS.Config.Roles[role]
            local r = tonumber(data.color:sub(1,2), 16)/255
            local g = tonumber(data.color:sub(3,4), 16)/255
            local b = tonumber(data.color:sub(5,6), 16)/255
            specBtnText:SetText(data.name)
            specBtnText:SetTextColor(r, g, b)
        else
            specBtnText:SetText("Роль")
            specBtnText:SetTextColor(0.53, 0.53, 0.53)
        end
    end
    
    -- Target
    self:UpdateTargetSection()
end

function SBS.UI:UpdateStats()
    local p = "SBS_MainFrame_StatsPanel_"
    local pointsLeft = SBS.Stats:GetPointsLeft()
    local maxStat = SBS.Stats:GetMaxStat()
    local playerName = UnitName("player")

    for _, stat in ipairs(STAT_ORDER) do
        local cfg = STAT_CONFIG[stat]
        local rowPrefix = p .. stat .. "_"

        local base = SBS.Stats:Get(stat)
        local woundPenalty = SBS.Stats:GetWoundPenalty()
        local total = SBS.Stats:GetTotal(stat)

        -- Проверяем модификаторы от баффов для защитных характеристик
        local buffMod = 0
        if stat == "Fortitude" then
            buffMod = SBS.Effects:GetModifier("player", playerName, "fortitude")
        elseif stat == "Reflex" then
            buffMod = SBS.Effects:GetModifier("player", playerName, "reflex")
        elseif stat == "Will" then
            buffMod = SBS.Effects:GetModifier("player", playerName, "will")
        end

        -- Значение
        local value = _G[rowPrefix .. "Value"]
        if value then
            local text = tostring(base)
            if woundPenalty < 0 then
                text = text .. "|cFFFF6666" .. woundPenalty .. "|r=" .. total
            end
            -- Добавляем модификатор от баффа если есть
            if buffMod ~= 0 then
                local finalTotal = total + buffMod
                if woundPenalty < 0 then
                    text = tostring(base) .. "|cFFFF6666" .. woundPenalty .. "|r" .. "|cFF33FF66+" .. buffMod .. "|r=" .. finalTotal
                else
                    text = text .. "|cFF33FF66+" .. buffMod .. "|r=" .. finalTotal
                end
            end
            value:SetText(text)
        end

        -- Кнопка добавления
        local addBtn = _G[rowPrefix .. "AddBtn"]
        if addBtn then
            if base < maxStat and pointsLeft > 0 then
                addBtn:Show()
                addBtn:Enable()
            else
                addBtn:Hide()
            end
        end
    end
end

function SBS.UI:UpdateTargetSection()
    local p = "SBS_MainFrame_TargetFrame_"
    
    local nameText = _G[p.."Info_Name"]
    local hpBar = _G[p.."Info_HPBar"]
    local hpBarText = _G[p.."Info_HPBar_Text"]
    local shieldBar = _G[p.."Info_ShieldBar"]
    local portraitTexture = _G[p.."Portrait_Texture"]
    local levelFrame = _G[p.."Portrait_LevelFrame"]
    local levelText = _G[p.."Portrait_LevelFrame_Text"]
    local attackerIndicator = _G[p.."Info_AttackerIndicator"]
    local playerStatsFrame = _G[p.."Info_PlayerStats"]
    local playerStatsText = _G[p.."Info_PlayerStats_Stats"]
    local playerWoundsText = _G[p.."Info_PlayerStats_Wounds"]
    local playerEffectsRow = _G[p.."Info_PlayerStats_EffectsRow"]
    local npcStatsFrame = _G[p.."Info_NPCStats"]
    local fortText = _G[p.."Info_NPCStats_Fort"]
    local reflexText = _G[p.."Info_NPCStats_Reflex"]
    local willText = _G[p.."Info_NPCStats_Will"]
    
    -- Функция сброса UI
    local function ResetUI()
        if nameText then nameText:SetText("Нет цели") nameText:SetTextColor(0.5, 0.5, 0.5) end
        if hpBar then hpBar:SetValue(0) end
        if hpBarText then hpBarText:SetText("") end
        if shieldBar then shieldBar:Hide() end
        if levelFrame then levelFrame:Hide() end
        if attackerIndicator then attackerIndicator:Hide() end
        if playerStatsFrame then playerStatsFrame:Hide() end
        if npcStatsFrame then npcStatsFrame:Hide() end
        if portraitTexture then portraitTexture:SetTexture(nil) end
    end
    
    -- Нет цели - сбрасываем всё
    if not UnitExists("target") then
        ResetUI()
        return
    end
    
    local guid = UnitGUID("target")
    local name = UnitName("target")
    local isPlayer = UnitIsPlayer("target")
    
    -- Имя и портрет
    if nameText then 
        nameText:SetText(name) 
        if isPlayer then
            local _, class = UnitClass("target")
            local color = RAID_CLASS_COLORS[class] or {r=0.86, g=0.86, b=0.86}
            nameText:SetTextColor(color.r, color.g, color.b)
        else
            nameText:SetTextColor(0.86, 0.86, 0.86)
        end
    end
    
    if portraitTexture then
        SetPortraitTexture(portraitTexture, "target")
    end
    
    -- Определяем, это атакующий NPC?
    local isAttacker = SBS.Combat and SBS.Combat.AttackingNPC and SBS.Combat.AttackingNPC.guid == guid
    
    if isPlayer then
        -- ═══════════ ИГРОК ═══════════
        local playerData

        -- Если таргетим себя - берём данные напрямую из SBS.Stats (всегда актуальные)
        if UnitIsUnit("target", "player") then
            playerData = {
                hp = SBS.Stats:GetCurrentHP(),
                maxHp = SBS.Stats:GetMaxHP(),
                level = SBS.Stats:GetLevel(),
                wounds = SBS.Stats:GetWounds(),
                shield = SBS.Stats:GetShield(),
                strength = SBS.Stats:GetTotal("Strength"),
                dexterity = SBS.Stats:GetTotal("Dexterity"),
                intelligence = SBS.Stats:GetTotal("Intelligence"),
                spirit = SBS.Stats:GetTotal("Spirit"),
                fortitude = SBS.Stats:GetTotal("Fortitude"),
                reflex = SBS.Stats:GetTotal("Reflex"),
                will = SBS.Stats:GetTotal("Will"),
                energy = SBS.Stats:GetEnergy(),
                maxEnergy = SBS.Stats:GetMaxEnergy(),
            }
        else
            -- Для других игроков - из синхронизированных данных
            playerData = SBS.Sync and SBS.Sync:GetPlayerData(name)
        end

        -- Скрываем NPC элементы
        if npcStatsFrame then npcStatsFrame:Hide() end
        if attackerIndicator then attackerIndicator:Hide() end

        if playerData then
            -- HP
            if hpBar then
                hpBar:SetMinMaxValues(0, playerData.maxHp or 1)
                hpBar:SetValue(playerData.hp or 0)
                hpBar:SetStatusBarColor(0.2, 0.6, 0.2) -- Зелёный для игроков
            end
            if hpBarText then 
                hpBarText:SetText((playerData.hp or 0) .. " / " .. (playerData.maxHp or 0))
            end
            
            -- Щит
            if shieldBar then
                if playerData.shield and playerData.shield > 0 then
                    shieldBar:SetMinMaxValues(0, playerData.maxHp or 1)
                    shieldBar:SetValue(playerData.shield)
                    shieldBar:Show()
                else
                    shieldBar:Hide()
                end
            end
            
            -- Уровень
            if levelFrame and levelText then
                levelText:SetText(playerData.level or 1)
                levelFrame:Show()
            end
            
            -- Статы и ранения
            if playerStatsFrame then
                playerStatsFrame:Show()
                if playerStatsText then
                    -- Получаем модификаторы от баффов для защитных характеристик
                    local fortMod = SBS.Effects:GetModifier("player", name, "fortitude")
                    local reflexMod = SBS.Effects:GetModifier("player", name, "reflex")
                    local willMod = SBS.Effects:GetModifier("player", name, "will")

                    local baseFort = playerData.fortitude or 0
                    local baseReflex = playerData.reflex or 0
                    local baseWill = playerData.will or 0

                    local effectiveFort = baseFort + fortMod
                    local effectiveReflex = baseReflex + reflexMod
                    local effectiveWill = baseWill + willMod

                    -- Форматируем с модификаторами если есть
                    local fortStr = effectiveFort .. (fortMod ~= 0 and " |cFF33FF66(+" .. fortMod .. ")|r" or "")
                    local reflexStr = effectiveReflex .. (reflexMod ~= 0 and " |cFF33FF66(+" .. reflexMod .. ")|r" or "")
                    local willStr = effectiveWill .. (willMod ~= 0 and " |cFF33FF66(+" .. willMod .. ")|r" or "")

                    -- Объединённые статы: атакующие + защитные в одну строку
                    local statsStr = string.format("|cFFC41E3AСил|r %d     |cFF00FF96Лов|r %d     |cFF0070DEИнт|r %d     |cFFFFFFFFДух|r %d     |cFFA330C9Сто|r %s     |cFFFF7D0AСно|r %s     |cFF8787EDВол|r %s",
                        playerData.strength or 0,
                        playerData.dexterity or 0,
                        playerData.intelligence or 0,
                        playerData.spirit or 0,
                        fortStr,
                        reflexStr,
                        willStr)
                    playerStatsText:SetText(statsStr)
                end
                if playerWoundsText then
                    if playerData.wounds and playerData.wounds > 0 then
                        playerWoundsText:SetText("|cFFFF6666Ранения: " .. playerData.wounds .. "|r")
                    else
                        playerWoundsText:SetText("")
                    end
                end
            end
        else
            -- Нет данных о игроке
            if hpBar then hpBar:SetValue(0) end
            if hpBarText then hpBarText:SetText("Нет данных") end
            if shieldBar then shieldBar:Hide() end
            if levelFrame then levelFrame:Hide() end
            if playerStatsFrame then playerStatsFrame:Hide() end
        end
    else
        -- ═══════════ NPC ═══════════
        local npcData = SBS.Units:Get(guid)
        
        -- Скрываем элементы игрока
        if shieldBar then shieldBar:Hide() end
        if levelFrame then levelFrame:Hide() end
        if playerStatsFrame then playerStatsFrame:Hide() end
        
        -- Индикатор атакующего
        if attackerIndicator then
            if isAttacker then
                attackerIndicator:Show()
            else
                attackerIndicator:Hide()
            end
        end
        
        if npcData then
            -- HP
            if hpBar then
                hpBar:SetMinMaxValues(0, npcData.maxHp or 1)
                hpBar:SetValue(npcData.hp or 0)
                hpBar:SetStatusBarColor(0.55, 0, 0) -- Красный для NPC
            end
            
            if hpBarText then
                if npcData.hp <= 0 then
                    hpBarText:SetText("|cFFFF0000МЁРТВ|r")
                else
                    hpBarText:SetText(npcData.hp .. " / " .. npcData.maxHp)
                end
            end
            
            -- Защитные статы (с учётом эффектов ослабления)
            if npcStatsFrame then
                npcStatsFrame:Show()
                local fortMod = SBS.Effects:GetModifier("npc", guid, "fort")
                local reflexMod = SBS.Effects:GetModifier("npc", guid, "reflex")
                local willMod = SBS.Effects:GetModifier("npc", guid, "will")

                local effectiveFort = math.max(1, npcData.fort + fortMod)
                local effectiveReflex = math.max(1, npcData.reflex + reflexMod)
                local effectiveWill = math.max(1, npcData.will + willMod)

                local fortStr = effectiveFort .. (fortMod ~= 0 and " |cFFFF6666(" .. fortMod .. ")|r" or "")
                local reflexStr = effectiveReflex .. (reflexMod ~= 0 and " |cFFFF6666(" .. reflexMod .. ")|r" or "")
                local willStr = effectiveWill .. (willMod ~= 0 and " |cFFFF6666(" .. willMod .. ")|r" or "")

                if fortText then fortText:SetText("|cFFA330C9Стойкость|r " .. fortStr) end
                if reflexText then reflexText:SetText("|cFFFF7D0AСноровка|r " .. reflexStr) end
                if willText then willText:SetText("|cFF8787EDВоля|r " .. willStr) end
            end
        else
            -- Нет данных о NPC
            if hpBar then hpBar:SetValue(0) end
            if hpBarText then hpBarText:SetText("") end
            if npcStatsFrame then npcStatsFrame:Hide() end
        end
    end
    
    -- Обновляем кнопки действий (блокируем во время боя)
    self:UpdateActionButtons()
    
    -- Обновляем иконки эффектов на цели
    if SBS.UI.Effects then
        SBS.UI.Effects:UpdateTarget()
    end
end

function SBS.UI:UpdateActionButtons()
    local attackBtn = SBS_MainFrame_ActionSection_AttackBtn
    local checkBtn = SBS_MainFrame_ActionSection_CheckBtn
    
    if not attackBtn or not checkBtn then return end
    
    local ts = SBS.TurnSystem
    local isCombatActive = ts and ts:IsActive()
    
    if isCombatActive then
        -- Блокируем кнопки во время боя
        attackBtn:Disable()
        attackBtn:SetAlpha(0.4)
        
        checkBtn:Disable()
        checkBtn:SetAlpha(0.4)
    else
        -- Разблокируем
        attackBtn:Enable()
        attackBtn:SetAlpha(1)
        
        checkBtn:Enable()
        checkBtn:SetAlpha(1)
    end
end

function SBS.UI:UpdateAttackingNPCDisplay()
    -- Теперь индикатор обновляется в UpdateTargetSection
    self:UpdateTargetSection()
end

-- ═══════════════════════════════════════════════════════════
-- ТУЛТИПЫ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:ShowModernTooltip(frame, title, text, r, g, b)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, r or 1, g or 0.82, b or 0)
    if text then
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function SBS.UI:HideTooltip()
    GameTooltip:Hide()
end

-- ═══════════════════════════════════════════════════════════
-- ФУНКЦИИ МАСТЕРА
-- ═══════════════════════════════════════════════════════════

function SBS.UI:MasterAddWound()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then SBS.Utils:Error("Выберите игрока!") return end
    SBS.Sync:AddWound(name)
end

function SBS.UI:MasterRemoveWound()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then SBS.Utils:Error("Выберите игрока!") return end
    SBS.Sync:RemoveWound(name)
end

function SBS.UI:MasterGiveXP()
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.UI:MasterRemoveXP()
    SBS.Utils:Warn("XP система отключена. Уровень привязан к уровню персонажа.")
end

function SBS.UI:MasterSetLevel()
    SBS.Utils:Warn("Уровень привязан к уровню персонажа на сервере.")
end

function SBS.UI:MasterSetSpec()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then SBS.Utils:Error("Выберите игрока!") return end
    SBS.Dialogs:ShowSetSpecMenu(name)
end

function SBS.UI:MasterResetStats()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then SBS.Utils:Error("Выберите игрока!") return end
    SBS.Sync:ResetPlayerStats(name)
end

function SBS.UI:MasterGiveShield()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then SBS.Utils:Error("Выберите игрока!") return end
    _G["SBS_GiveShieldDialog_TargetName"]:SetText(name)
    _G["SBS_GiveShieldDialog_Input"]:SetText("1")
    SBS_GiveShieldDialog.targetName = name
    SBS_GiveShieldDialog:Show()
    _G["SBS_GiveShieldDialog_Input"]:SetFocus()
end

function SBS.UI:ApplyGiveShield()
    local target = SBS_GiveShieldDialog.targetName
    local amount = tonumber(_G["SBS_GiveShieldDialog_Input"]:GetText())
    if not target or not amount or amount <= 0 then SBS.Utils:Error("Некорректное значение!") return end
    SBS.Sync:GiveShield(target, amount)
    SBS_GiveShieldDialog:Hide()
end

function SBS.UI:MasterSync()
    if SBS.Sync then
        SBS.Sync:BroadcastFullData()
        SBS.Utils:Info("Синхронизировано")
    end
end

-- Мастер: +1 энергия выбранному игроку
function SBS.UI:MasterGiveEnergy()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then 
        SBS.Utils:Error("Выберите игрока!") 
        return 
    end
    SBS.Sync:GiveEnergy(name, 1)
end

-- Мастер: -1 энергия выбранному игроку
function SBS.UI:MasterTakeEnergy()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    SBS.Sync:TakeEnergy(name, 1)
end

-- Мастер: Полное восстановление энергии выбранному игроку
function SBS.UI:MasterRestoreEnergy()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите игрока!")
        return
    end

    -- В соло режиме или если цель — мы сами, обрабатываем локально
    if name == UnitName("player") then
        SBS.Stats:RestoreEnergy()
    end

    -- Отправляем команду в группу (если есть)
    if IsInGroup() then
        SBS.Sync:Send("RESTOREENERGY", name)
    end

    SBS.Utils:Info("Энергия игрока " .. SBS.Utils:Color("FFFFFF", name) .. " восстановлена до максимума.")
end

-- ═══════════════════════════════════════════════════════════
-- ФУНКЦИИ МАСТЕРА: ЭФФЕКТЫ
-- ═══════════════════════════════════════════════════════════

-- Мастер: Оглушение (на NPC или игрока)
function SBS.UI:MasterApplyStun()
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

-- Мастер: Периодический урон (на NPC или игрока)
function SBS.UI:MasterApplyDot()
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

-- Мастер: Уязвимость (на NPC или игрока)
function SBS.UI:MasterApplyVulnerability()
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

-- Мастер: Ослабление (на NPC или игрока)
function SBS.UI:MasterApplyWeakness()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then
        SBS.Utils:Error("Выберите цель!")
        return
    end

    local isPlayer = SBS.Utils:IsTargetPlayer()
    local targetType = isPlayer and "player" or "npc"
    local targetId = isPlayer and name or guid
    local targetName = isPlayer and name or (SBS.Units:Get(guid) and SBS.Units:Get(guid).name or "NPC")

    SBS.Dialogs:ShowWeaknessDialog(targetType, targetId, targetName)
end

-- Мастер: Бафф игрока
function SBS.UI:MasterApplyBuff()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then
        SBS.Utils:Error("Выберите игрока!")
        return
    end
    SBS.Dialogs:ShowMasterBuffDialog(name)
end

-- Мастер: Пурж (снять бафф)
function SBS.UI:MasterPurge()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then 
        SBS.Utils:Error("Выберите игрока!") 
        return 
    end
    SBS.Effects:Purge(name)
end

-- Мастер: Диспел (снять дебафф)
function SBS.UI:MasterDispel()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid or not SBS.Utils:IsTargetPlayer() then 
        SBS.Utils:Error("Выберите игрока!") 
        return 
    end
    
    -- Мастер может снимать дебаффы без ограничений
    local effects = SBS.Effects:GetAll("player", name)
    local dispelled = false
    
    for effectId, _ in pairs(effects) do
        local def = SBS.Effects.Definitions[effectId]
        if def and (def.type == "debuff" or def.type == "dot") then
            SBS.Effects:Remove("player", name, effectId)
            dispelled = true
            break
        end
    end
    
    if dispelled then
        SBS.Utils:Info("Снят дебафф с " .. SBS.Utils:Color("FFFFFF", name))
    else
        SBS.Utils:Warn("Нет дебаффов для снятия")
    end
end

-- Мастер: Снять ВСЕ эффекты
function SBS.UI:MasterClearAllEffects()
    local guid, name = SBS.Utils:GetTargetGUID()
    if not guid then 
        SBS.Utils:Error("Выберите цель!") 
        return 
    end
    
    local isPlayer = SBS.Utils:IsTargetPlayer()
    local targetType = isPlayer and "player" or "npc"
    local targetId = isPlayer and name or guid
    
    SBS.Effects:ClearAll(targetType, targetId)
    SBS.Utils:Info("Сняты все эффекты с " .. SBS.Utils:Color("FFFFFF", isPlayer and name or "NPC"))
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ КНОПОК ПОШАГОВОГО БОЯ В GM ПАНЕЛИ
-- ═══════════════════════════════════════════════════════════

function SBS.UI:UpdateGMCombatButtons()
    local startBtn = SBS_GMPanel_StartCombatBtn
    local skipBtn = SBS_GMPanel_SkipTurnBtn
    local npcBtn = SBS_GMPanel_NPCTurnBtn
    local freeBtn = SBS_GMPanel_FreeActionBtn
    local timerFrame = SBS_GMPanel_TimerFrame
    local excludeBtn = SBS_GMPanel_ExcludeMasterBtn
    local modeFreeCheckBtn = SBS_GMPanel_ModeFreeCheckBtn
    local modeQueueCheckBtn = SBS_GMPanel_ModeQueueCheckBtn
    local useTimerCheckBtn = SBS_GMPanel_UseTimerCheckBtn
    local tab3 = SBS_GMPanel_TabContent3
    local modeFreeLabel = tab3 and tab3.modeFreeLabel
    local modeQueueLabel = tab3 and tab3.modeQueueLabel
    local useTimerLabel = tab3 and tab3.useTimerLabel
    local utilitiesLabel = tab3 and tab3.utilitiesLabel
    local showQueueBtn = SBS_GMPanel_ShowQueueBtn
    local clearAllBtn = SBS_GMPanel_ClearAllBtn
    local syncBtn = SBS_GMPanel_SyncBtn
    local versionCheckBtn = SBS_GMPanel_VersionCheckBtn

    if not startBtn then return end

    local ts = SBS.TurnSystem
    local isActive = ts and ts:IsActive()

    -- Динамическое изменение высоты панели GM для вкладки 3 (Бой)
    local currentTab = SBS_GMPanel.currentTab or 1
    if currentTab == 3 and SBS_GMPanel then
        local baseHeight = 70  -- Заголовок + вкладки + отступы
        local contentHeight
        if isActive then
            -- Бой активен - меньше высота (скрыты чекбоксы, лейблы, ExcludeBtn, TimerFrame)
            contentHeight = 236  -- Уменьшенная высота без настроек
        else
            -- Бой не активен - полная высота
            contentHeight = 326  -- Полная высота с настройками
        end
        SBS_GMPanel:SetHeight(baseHeight + contentHeight)
    end

    if isActive then
        -- Бой активен
        startBtn:SetText("|cFFFF6666Окончить бой|r")

        -- Скрываем контролы настроек боя
        if timerFrame then timerFrame:Hide() end
        if excludeBtn then excludeBtn:Hide() end
        if modeFreeCheckBtn then modeFreeCheckBtn:Hide() end
        if modeQueueCheckBtn then modeQueueCheckBtn:Hide() end
        if useTimerCheckBtn then useTimerCheckBtn:Hide() end
        if modeFreeLabel then modeFreeLabel:Hide() end
        if modeQueueLabel then modeQueueLabel:Hide() end
        if useTimerLabel then useTimerLabel:Hide() end

        -- Перемещаем кнопки вверх (смещение на 90 пикселей)
        if startBtn then
            startBtn:ClearAllPoints()
            startBtn:SetPoint("TOP", 34, -16)
        end
        if skipBtn then
            skipBtn:ClearAllPoints()
            skipBtn:SetPoint("TOP", -46, -44)
        end
        if npcBtn then
            npcBtn:ClearAllPoints()
            npcBtn:SetPoint("TOP", 46, -44)
        end
        if showQueueBtn then
            showQueueBtn:ClearAllPoints()
            showQueueBtn:SetPoint("TOP", 0, -70)
        end
        if freeBtn then
            freeBtn:ClearAllPoints()
            freeBtn:SetPoint("TOP", 0, -96)
        end
        if clearAllBtn then
            clearAllBtn:ClearAllPoints()
            clearAllBtn:SetPoint("TOP", 0, -150)
        end
        if syncBtn then
            syncBtn:ClearAllPoints()
            syncBtn:SetPoint("TOP", 0, -176)
        end
        if versionCheckBtn then
            versionCheckBtn:ClearAllPoints()
            versionCheckBtn:SetPoint("TOP", 0, -202)
        end
        if utilitiesLabel then
            utilitiesLabel:ClearAllPoints()
            utilitiesLabel:SetPoint("TOP", 0, -134)
        end

        -- Кнопка пропуска
        if skipBtn then
            if ts.phase == "players" then
                skipBtn:Enable()
                skipBtn:SetAlpha(1)
            else
                skipBtn:Disable()
                skipBtn:SetAlpha(0.5)
            end
        end

        -- Кнопка фазы NPC (всегда активна во время боя)
        if npcBtn then
            npcBtn:Enable()
            npcBtn:SetAlpha(1)
            if ts.phase == "npc" then
                npcBtn:SetText("|cFF00FF00Ход игроков|r")
            else
                npcBtn:SetText("|cFFA06AF1Ход противника|r")
            end
        end

        -- Кнопка внеочередного хода
        if freeBtn then
            if ts.phase == "players" then
                freeBtn:Enable()
                freeBtn:SetAlpha(1)
            else
                freeBtn:Disable()
                freeBtn:SetAlpha(0.5)
            end
        end
    else
        -- Бой не активен
        startBtn:SetText("|cFF00FF00Начать бой|r")

        -- Показываем контролы настроек боя
        if excludeBtn then excludeBtn:Show() end
        if modeFreeCheckBtn then modeFreeCheckBtn:Show() end
        if modeQueueCheckBtn then modeQueueCheckBtn:Show() end
        if useTimerCheckBtn then useTimerCheckBtn:Show() end
        if modeFreeLabel then modeFreeLabel:Show() end
        if modeQueueLabel then modeQueueLabel:Show() end
        if useTimerLabel then useTimerLabel:Show() end

        -- Возвращаем кнопки на исходные позиции
        if startBtn then
            startBtn:ClearAllPoints()
            startBtn:SetPoint("TOP", 34, -106)
        end
        if skipBtn then
            skipBtn:ClearAllPoints()
            skipBtn:SetPoint("TOP", -46, -134)
        end
        if npcBtn then
            npcBtn:ClearAllPoints()
            npcBtn:SetPoint("TOP", 46, -134)
        end
        if showQueueBtn then
            showQueueBtn:ClearAllPoints()
            showQueueBtn:SetPoint("TOP", 0, -160)
        end
        if freeBtn then
            freeBtn:ClearAllPoints()
            freeBtn:SetPoint("TOP", 0, -186)
        end
        if clearAllBtn then
            clearAllBtn:ClearAllPoints()
            clearAllBtn:SetPoint("TOP", 0, -240)
        end
        if syncBtn then
            syncBtn:ClearAllPoints()
            syncBtn:SetPoint("TOP", 0, -266)
        end
        if versionCheckBtn then
            versionCheckBtn:ClearAllPoints()
            versionCheckBtn:SetPoint("TOP", 0, -292)
        end
        if utilitiesLabel then
            utilitiesLabel:ClearAllPoints()
            utilitiesLabel:SetPoint("TOP", 0, -224)
        end

        -- Синхронизируем чекбоксы с текущим состоянием TurnSystem
        if modeFreeCheckBtn and modeQueueCheckBtn then
            if ts.mode == "free" then
                modeFreeCheckBtn:SetChecked(true)
                modeQueueCheckBtn:SetChecked(false)
            else
                modeFreeCheckBtn:SetChecked(false)
                modeQueueCheckBtn:SetChecked(true)
            end
        end

        if useTimerCheckBtn then
            useTimerCheckBtn:SetChecked(ts.useTimer)
        end

        -- TimerFrame показываем только если чекбокс таймера включен
        if timerFrame and useTimerCheckBtn then
            if useTimerCheckBtn:GetChecked() then
                timerFrame:Show()
            else
                timerFrame:Hide()
            end
        end

        -- Деактивируем кнопки
        if skipBtn then
            skipBtn:Disable()
            skipBtn:SetAlpha(0.5)
        end
        if npcBtn then
            npcBtn:SetText("|cFFA06AF1Ход противника|r")
            npcBtn:Disable()
            npcBtn:SetAlpha(0.5)
        end
        if freeBtn then
            freeBtn:Disable()
            freeBtn:SetAlpha(0.5)
        end
    end
end

function SBS.UI:ToggleMasterFrame()
    self:ToggleGMPanel()
    self:UpdateGMCombatButtons()
end

-- Алиасы перенесены в Core/Aliases.lua
