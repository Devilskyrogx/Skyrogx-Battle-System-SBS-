-- SBS/Core/Config.lua
-- Константы, справочники и настройки

local ADDON_NAME, SBS = ...

SBS.Config = {
    -- Версия и разработчик
    VERSION = "0.95",
    AUTHOR = "Skyrogx",
    -- Синхронизация
    ADDON_PREFIX = "SBS_SYNC",
    -- ═══════════════════════════════════════════════════════════
    -- СИСТЕМА УРОВНЕЙ (привязка к уровню персонажа на сервере)
    -- ═══════════════════════════════════════════════════════════
    MIN_LEVEL = 10, MAX_LEVEL = 100,
    -- Лимиты характеристик
    MAX_STAT = 10, MAX_TOTAL_POINTS = 20,
    -- Прочие лимиты
    MAX_WOUNDS = 3, COMBAT_LOG_MAX = 100, MASTER_LOG_MAX = 200,
    -- Шрифт
    FONT = "Fonts\\FRIZQT___CYR.TTF",
    FONT_SIZES = { small = 10, normal = 12, large = 14, title = 16, floating = 18, floatingCrit = 24 },
    -- ═══════════════════════════════════════════════════════════
    -- СИСТЕМА ОЧКОВ ХАРАКТЕРИСТИК
    -- ═══════════════════════════════════════════════════════════
    -- Уровни, на которых выдаются очки
    -- На 10 уровне: 2 очка (стартовый бонус)
    -- Далее каждые 5 уровней: по 1 очку
    -- Итого: 2 + 18 = 20 очков
    PointsAtLevel = {
        [10] = 2, [15] = 1, [20] = 1, [25] = 1, [30] = 1, [35] = 1, [40] = 1, [45] = 1, [50] = 1, [55] = 1,
        [60] = 1, [65] = 1, [70] = 1, [75] = 1, [80] = 1, [85] = 1, [90] = 1, [95] = 1, [100] = 1,
    },
    -- ═══════════════════════════════════════════════════════════
    -- СИСТЕМА HP
    -- ═══════════════════════════════════════════════════════════
    -- HP по уровням: 10 лвл = 5 HP, каждые 10 уровней +1 HP, 80+ лвл = 12 HP (потолок)
    HPAtLevel = { [10] = 5, [20] = 6, [30] = 7, [40] = 8, [50] = 9, [60] = 10, [70] = 11, [80] = 12 },
    -- ═══════════════════════════════════════════════════════════
    -- СИСТЕМА ЭНЕРГИИ
    -- ═══════════════════════════════════════════════════════════
    EnergyAtLevel = { [10] = 2, [40] = 3, [70] = 4, [100] = 5 },
    -- Стоимость действий в энергии
    ENERGY_COST_AOE = 1, ENERGY_COST_SPECIAL = 1,
    -- Восстановление энергии
    ENERGY_GAIN_SKIP_TURN = 1, ENERGY_GAIN_CRIT_CHOICE = 1,
    -- ═══════════════════════════════════════════════════════════
    -- ОСОБОЕ ДЕЙСТВИЕ
    -- ═══════════════════════════════════════════════════════════
    SPECIAL_ACTION_THRESHOLD = 14, SPECIAL_ACTION_MAX_TEXT = 1000,
    -- ═══════════════════════════════════════════════════════════
    -- AOE АТАКА
    -- ═══════════════════════════════════════════════════════════
    AOE_THRESHOLD = 12, AOE_MAX_TARGETS = 3,
    -- ═══════════════════════════════════════════════════════════
    -- РОЛИ (бывшие специализации)
    -- ═══════════════════════════════════════════════════════════
    Roles = {
        tank = { name = "Танк", color = "CC8040", description = "Высокая выживаемость. HP = Базовое + Стойкость/2. Сниженный урон и хил. После успешной защиты 10% шанс на щит (1-2) или контратаку.", icon = "Interface\\AddOns\\SBS\\texture\\roleicon-tiny-tank" },
        dd = { name = "Боец", color = "FF6666", description = "Повышенный урон в бою. Сниженный хил. После успешной атаки 10% шанс на добивание (если цель ≤20% HP).", icon = "Interface\\AddOns\\SBS\\texture\\roleicon-tiny-dps" },
        healer = { name = "Целитель", color = "66FF66", description = "Усиленное исцеление, щиты и снятие ран. Сниженный урон.", icon = "Interface\\AddOns\\SBS\\texture\\roleicon-tiny-healer" },
        universal = { name = "Универсал", color = "AAAAAA", description = "Базовые значения без бонусов. Доступны щиты, но нет снятия ран.", icon = "Interface\\AddOns\\SBS\\texture\\roleicon-tiny-dps" },
    },
    -- Алиас для обратной совместимости
    Specializations = nil,
    ROLE_REQUIRED_LEVEL = 10, SPEC_REQUIRED_LEVEL = 10,
    -- ═══════════════════════════════════════════════════════════
    -- ТАБЛИЦЫ УРОНА (масштабированы по новым уровням)
    -- ═══════════════════════════════════════════════════════════
    -- Урон для Универсала (базовый)
    DamageNormal = {
        [10] = {min=2,max=3}, [20] = {min=2,max=3}, [30] = {min=2,max=4}, [40] = {min=2,max=4}, [50] = {min=3,max=4},
        [60] = {min=3,max=4}, [70] = {min=3,max=5}, [80] = {min=3,max=5}, [90] = {min=4,max=5}, [100] = {min=4,max=5},
    },
    -- Урон для Танка (сниженный)
    DamageReduced = {
        [10] = {min=1,max=2}, [20] = {min=1,max=2}, [30] = {min=1,max=3}, [40] = {min=1,max=3}, [50] = {min=2,max=3},
        [60] = {min=2,max=3}, [70] = {min=2,max=4}, [80] = {min=2,max=4}, [90] = {min=3,max=4}, [100] = {min=3,max=4},
    },
    -- Урон для Целителя (минимальный)
    DamageMinimal = {
        [10] = {min=1,max=1}, [20] = {min=1,max=1}, [30] = {min=1,max=1}, [40] = {min=1,max=1}, [50] = {min=1,max=1},
        [60] = {min=1,max=1}, [70] = {min=1,max=1}, [80] = {min=1,max=1}, [90] = {min=1,max=1}, [100] = {min=1,max=1},
    },
    -- Урон для ДД (повышенный)
    DamageDD = {
        [10] = {min=3,max=4}, [20] = {min=3,max=4}, [30] = {min=3,max=5}, [40] = {min=3,max=5}, [50] = {min=4,max=6},
        [60] = {min=4,max=6}, [70] = {min=5,max=7}, [80] = {min=5,max=7}, [90] = {min=6,max=8}, [100] = {min=6,max=8},
    },
    -- ═══════════════════════════════════════════════════════════
    -- ТАБЛИЦЫ ИСЦЕЛЕНИЯ
    -- ═══════════════════════════════════════════════════════════
    -- Исцеление для Универсала (базовое)
    HealingNormal = {
        [10] = {min=2,max=3}, [20] = {min=2,max=3}, [30] = {min=2,max=4}, [40] = {min=2,max=4}, [50] = {min=3,max=4},
        [60] = {min=3,max=4}, [70] = {min=3,max=5}, [80] = {min=3,max=5}, [90] = {min=4,max=5}, [100] = {min=4,max=5},
    },
    -- Исцеление для Танка и ДД (минимальное)
    HealingMinimal = {
        [10] = {min=1,max=1}, [20] = {min=1,max=1}, [30] = {min=1,max=1}, [40] = {min=1,max=1}, [50] = {min=1,max=1},
        [60] = {min=1,max=1}, [70] = {min=1,max=1}, [80] = {min=1,max=1}, [90] = {min=1,max=1}, [100] = {min=1,max=1},
    },
    -- Исцеление для Хила (повышенное)
    HealingHealer = {
        [10] = {min=3,max=4}, [20] = {min=3,max=4}, [30] = {min=3,max=5}, [40] = {min=3,max=5}, [50] = {min=4,max=6},
        [60] = {min=4,max=6}, [70] = {min=5,max=7}, [80] = {min=5,max=7}, [90] = {min=6,max=8}, [100] = {min=6,max=8},
    },
    -- ═══════════════════════════════════════════════════════════
    -- ЩИТ (только Хил)
    -- ═══════════════════════════════════════════════════════════
    -- Результат броска d20+Дух -> количество щита
    ShieldTable = {
        { threshold = 1, shield = 1 }, { threshold = 6, shield = 1 },
        { threshold = 12, shield = 2 }, { threshold = 18, shield = 3 },
    },
    SHIELD_CRIT_AMOUNT = 3,
    -- ═══════════════════════════════════════════════════════════
    -- РАНЕНИЯ
    -- ═══════════════════════════════════════════════════════════
    WoundPenalties = { [0] = 0, [1] = -1, [2] = -2, [3] = -4 },
    -- ═══════════════════════════════════════════════════════════
    -- НАЗВАНИЯ И ЦВЕТА
    -- ═══════════════════════════════════════════════════════════
    StatNames = { Strength = "Сила", Dexterity = "Ловкость", Intelligence = "Интеллект", Spirit = "Дух", Fortitude = "Стойкость", Reflex = "Сноровка", Will = "Воля" },
    StatShortNames = { Strength = "Str", Dexterity = "Dex", Intelligence = "Int", Spirit = "Spi", Fortitude = "Fort", Reflex = "Reflex", Will = "Will" },
    StatColors = { Strength = "FF6666", Dexterity = "66FF66", Intelligence = "66CCFF", Spirit = "FFE066", Fortitude = "CC8040", Reflex = "99CC66", Will = "B080FF" },
    AttackVsDefense = { Strength = "Fortitude", Dexterity = "Reflex", Intelligence = "Will" },
    AttackStats = { "Strength", "Dexterity", "Intelligence" },
    DefenseStats = { "Fortitude", "Reflex", "Will" },
    AllStats = { "Strength", "Dexterity", "Intelligence", "Spirit", "Fortitude", "Reflex", "Will" },
}

-- Алиас для обратной совместимости
SBS.Config.Specializations = SBS.Config.Roles

-- ═══════════════════════════════════════════════════════════
-- ХЕЛПЕРЫ ДЛЯ ПОЛУЧЕНИЯ ДАННЫХ
-- ═══════════════════════════════════════════════════════════

function SBS.Config:GetPointsForLevel(level)
    local totalPoints = 0
    for lvl, points in pairs(self.PointsAtLevel) do
        if lvl <= level then totalPoints = totalPoints + points end
    end
    return totalPoints
end

function SBS.Config:GetBaseHPForLevel(level)
    local hp = 5
    for lvl, hpValue in pairs(self.HPAtLevel) do
        if lvl <= level and lvl >= 10 then hp = math.max(hp, hpValue) end
    end
    return hp
end

function SBS.Config:GetMaxStat() return self.MAX_STAT end
function SBS.Config:GetWoundPenalty(wounds) return self.WoundPenalties[wounds] or 0 end

function SBS.Config:GetDamageRange(level, role)
    local tbl
    if role == "dd" then tbl = self.DamageDD
    elseif role == "tank" then tbl = self.DamageReduced
    elseif role == "healer" then tbl = self.DamageMinimal
    else tbl = self.DamageNormal end
    local damage = { min = 1, max = 1 }
    for lvl, dmg in pairs(tbl) do if lvl <= level then damage = dmg end end
    return damage
end

function SBS.Config:GetHealingRange(level, role)
    local tbl
    if role == "healer" then tbl = self.HealingHealer
    elseif role == "tank" or role == "dd" then tbl = self.HealingMinimal
    else tbl = self.HealingNormal end
    local healing = { min = 1, max = 1 }
    for lvl, heal in pairs(tbl) do if lvl <= level then healing = heal end end
    return healing
end

function SBS.Config:GetShieldAmount(rollResult)
    if rollResult >= 20 then return self.SHIELD_CRIT_AMOUNT, true end
    local shield = 1
    for _, entry in ipairs(self.ShieldTable) do
        if rollResult >= entry.threshold then shield = entry.shield end
    end
    return shield, false
end

function SBS.Config:GetPointsAtLevel(level) return self.PointsAtLevel[level] or 0 end

function SBS.Config:GetPointLevels()
    local levels = {}
    for lvl, _ in pairs(self.PointsAtLevel) do table.insert(levels, lvl) end
    table.sort(levels)
    return levels
end

function SBS.Config:GetMaxEnergyForLevel(level)
    local maxEnergy = 2
    for lvl, energy in pairs(self.EnergyAtLevel) do
        if lvl <= level then maxEnergy = math.max(maxEnergy, energy) end
    end
    return maxEnergy
end

function SBS.Config:GetHighestAttackStat(stats)
    local highest, highestValue = "Strength", stats.Strength or 0
    if (stats.Dexterity or 0) > highestValue then highest, highestValue = "Dexterity", stats.Dexterity end
    if (stats.Intelligence or 0) > highestValue then highest, highestValue = "Intelligence", stats.Intelligence end
    return highest, highestValue
end

-- ═══════════════════════════════════════════════════════════
-- ДЕФОЛТНЫЕ ЗНАЧЕНИЯ ДЛЯ AceDB
-- ═══════════════════════════════════════════════════════════

SBS.Defaults = {
    char = {
        -- Персональные данные персонажа (сохраняются отдельно для каждого персонажа)
        lastKnownLevel = 10,
        role = nil, specialization = nil,
        wounds = 0, shield = 0, energy = 2,
        stats = { Strength = 0, Dexterity = 0, Intelligence = 0, Spirit = 0, Fortitude = 0, Reflex = 0, Will = 0 },
        pointsLeft = 2, currentHP = 5,
    },
    profile = {
        -- Настройки интерфейса (общие для всех персонажей аккаунта)
        minimapAngle = 220, uiScale = 1.0,
        minimap = { hide = false },
        -- Unit Frames (компактные фреймы игрока и цели)
        unitFrames = {
            player = {
                enabled = true,
                locked = false,
                scale = 1.0,
                position = { point = "CENTER", x = -400, y = -200 },
            },
            target = {
                enabled = true,
                locked = false,
                scale = 1.0,
                position = { point = "CENTER", x = -400, y = -300 },
            },
        },
    },
    global = { unitData = {}, combatLog = {} },
}
