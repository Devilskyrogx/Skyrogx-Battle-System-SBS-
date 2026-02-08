-- SBS/Core/Compat.lua
-- Совместимость со старым API для WoW 9.2.7

-- SetResizeBounds появилась в 10.0+, в 9.x используются SetMinResize/SetMaxResize
local frameMeta = getmetatable(CreateFrame("Frame")).__index

-- Добавляем SetResizeBounds если его нет (для 9.x)
if not frameMeta.SetResizeBounds then
    frameMeta.SetResizeBounds = function(self, minW, minH, maxW, maxH)
        if self.SetMinResize then
            self:SetMinResize(minW, minH)
        end
        if self.SetMaxResize and maxW and maxH then
            self:SetMaxResize(maxW, maxH)
        end
    end
end

-- Добавляем SetMinResize если его нет (для 10.0+)
if not frameMeta.SetMinResize then
    frameMeta.SetMinResize = function(self, minW, minH)
        self._minW = minW
        self._minH = minH
        local maxW = self._maxW or minW * 10
        local maxH = self._maxH or minH * 10
        if self.SetResizeBounds then
            self:SetResizeBounds(minW, minH, maxW, maxH)
        end
    end
end

-- Добавляем SetMaxResize если его нет (для 10.0+)
if not frameMeta.SetMaxResize then
    frameMeta.SetMaxResize = function(self, maxW, maxH)
        self._maxW = maxW
        self._maxH = maxH
        local minW = self._minW or 1
        local minH = self._minH or 1
        if self.SetResizeBounds then
            self:SetResizeBounds(minW, minH, maxW, maxH)
        end
    end
end
