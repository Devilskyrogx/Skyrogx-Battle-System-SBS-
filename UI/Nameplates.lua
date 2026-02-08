-- SBS/UI/Nameplates.lua
-- HP на неймплейтах и всплывающий текст урона

local ADDON_NAME, SBS = ...

SBS.UI = SBS.UI or {}
SBS.UI.NameplateFrames = SBS.UI.NameplateFrames or {}
SBS.UI.FloatingTextPool = SBS.UI.FloatingTextPool or {}

function SBS.UI:UpdateNameplateFrame(np, unitId)
    if not np or not unitId then return end
    local guid = UnitGUID(unitId)
    if not guid then return end
    
    local data = SBS.Units:Get(guid)
    
    if not self.NameplateFrames[np] then
        local fr = CreateFrame("Frame", nil, np)
        fr:SetSize(60, 36)
        fr:SetPoint("BOTTOM", np, "TOP", 0, -15)
        fr:SetFrameStrata("HIGH")
        fr:SetFrameLevel(100)
        
        fr.icon = fr:CreateTexture(nil, "OVERLAY")
        fr.icon:SetSize(18, 18)
        fr.icon:SetPoint("TOP", fr, "TOP", 0, 0)
        fr.icon:SetTexture("Interface\\AddOns\\SBS\\texture\\delves-scenario-heart-icon-2x")
        
        fr.skull = fr:CreateTexture(nil, "OVERLAY")
        fr.skull:SetSize(18, 18)
        fr.skull:SetPoint("TOP", fr, "TOP", 0, 0)
        fr.skull:SetTexture("Interface\\WorldMap\\Skull_64Grey")
        fr.skull:Hide()
        
        fr.text = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
        fr.text:SetPoint("TOP", fr.icon, "BOTTOM", 0, -1)
        fr.text:SetFont(SBS.Config.FONT, 11, "OUTLINE")
        
        self.NameplateFrames[np] = fr
    end
    
    local fr = self.NameplateFrames[np]
    fr.unitGUID = guid
    
    if data and data.hp ~= nil and data.maxHp then
        local dead = data.hp <= 0
        fr.icon:SetShown(not dead)
        fr.skull:SetShown(dead)
        fr.text:ClearAllPoints()
        fr.text:SetPoint("TOP", dead and fr.skull or fr.icon, "BOTTOM", 0, -1)
        
        if dead then
            fr.text:SetText("Цель мертва")
            fr.text:SetTextColor(1, 0, 0)
        else
            local pct = data.hp / data.maxHp
            fr.text:SetText(data.hp .. "/" .. data.maxHp)
            if pct > 0.5 then fr.text:SetTextColor(0.2, 1, 0.2)
            elseif pct > 0.25 then fr.text:SetTextColor(1, 0.8, 0.2)
            else fr.text:SetTextColor(1, 0.2, 0.2) end
        end
        fr:Show()
    else
        fr:Hide()
    end
end

function SBS.UI:UpdateAllNameplates()
    local nps = C_NamePlate.GetNamePlates()
    if not nps then return end
    for _, np in ipairs(nps) do
        if np.namePlateUnitToken then
            self:UpdateNameplateFrame(np, np.namePlateUnitToken)
        end
    end
end

-- Всплывающий текст
function SBS.UI:GetFloatingTextFrame(parent)
    for _, ft in ipairs(self.FloatingTextPool) do
        if not ft.inUse then
            ft.inUse = true
            ft:SetParent(parent)
            ft:ClearAllPoints()
            return ft
        end
    end
    
    local ft = CreateFrame("Frame", nil, parent)
    ft:SetSize(200, 50)
    ft:SetFrameStrata("TOOLTIP")
    ft:SetFrameLevel(1000)
    ft.text = ft:CreateFontString(nil, "OVERLAY")
    ft.text:SetFont(SBS.Config.FONT, 18, "OUTLINE")
    ft.text:SetPoint("CENTER")
    ft.text:SetShadowOffset(2, -2)
    ft.text:SetShadowColor(0, 0, 0, 0.8)
    ft.inUse = true
    table.insert(self.FloatingTextPool, ft)
    return ft
end

function SBS.UI:ShowFloatingText(unitName, text, r, g, b, isCrit)
    local np = C_NamePlate.GetNamePlateForUnit("target")
    if not np or UnitName("target") ~= unitName then return false end
    
    local ft = self:GetFloatingTextFrame(np)
    ft:SetPoint("CENTER", np, "CENTER", 0, 30)
    ft.text:SetText(text)
    ft.text:SetTextColor(r or 1, g or 1, b or 1, 1)
    ft.text:SetFont(SBS.Config.FONT, isCrit and 24 or 18, "OUTLINE")
    ft:SetAlpha(1)
    ft:Show()
    
    local elapsed, duration, startY, endY = 0, 1.5, 30, 70
    ft:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = elapsed / duration
        if progress >= 1 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
            self.inUse = false
            return
        end
        local moveProgress = 1 - (1 - progress)^2
        self:ClearAllPoints()
        self:SetPoint("CENTER", np, "CENTER", 0, startY + (endY - startY) * moveProgress)
        if progress > 0.6 then self:SetAlpha(1 - (progress - 0.6) / 0.4) end
    end)
    return true
end

function SBS.UI:ShowAttackResult(unitName, resultType, damage)
    local texts = {
        crit_fail = { "Крит. провал!", 1, 0, 0, true },
        crit_success = { "Крит! -" .. (damage or 0), 1, 0.84, 0, true },
        hit = { "Попадание! -" .. (damage or 0), 0.2, 1, 0.2, false },
        miss = { "Промах!", 0.7, 0.7, 0.7, false },
        heal = { "+" .. (damage or 0) .. " HP", 0.2, 1, 0.2, false },
        crit_heal = { "Крит! +" .. (damage or 0) .. " HP", 0.2, 1, 0.2, true },
    }
    local t = texts[resultType]
    if t then return self:ShowFloatingText(unitName, t[1], t[2], t[3], t[4], t[5]) end
end

-- Алиасы
function SBS:UpdateAllNameplates() SBS.UI:UpdateAllNameplates() end
function SBS:ShowAttackResult(name, rtype, dmg) return SBS.UI:ShowAttackResult(name, rtype, dmg) end