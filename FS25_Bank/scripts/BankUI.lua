-- Copyright © 2026 ian. All rights reserved.
-- BankUI.lua
-- Interface moderna do banco, desenhada por script (drawFilledRect + renderText).
-- Cantos arredondados, sombra, animacao de entrada, slider, chips e barras de progresso.
-- Coordenadas em "px" de uma tela de referencia 1920x1080 (origem: canto inferior esquerdo).

BankUI = {}

BankUI.PANEL = {x = 440, y = 180, w = 1040, h = 720}
BankUI.QUICK_AMOUNTS = {10000, 50000, 100000, 250000, 500000}

local COLOR = {
    -- Cores em sRGB (o desenho aplica correcao de gama; o jogo clareia cores cruas)
    panel       = {0.105, 0.120, 0.135, 0.98},
    card        = {0.010, 0.010, 0.010, 1.00},
    row         = {0.022, 0.022, 0.022, 1.00},
    line        = {1.000, 1.000, 1.000, 0.08},
    track       = {0.055, 0.055, 0.055, 1.00},
    accent      = {0.722, 0.976, 0.000, 1.00},   -- #B8F900 Cor ian Modding
    accentHover = {0.820, 1.000, 0.250, 1.00},
    onAccent    = {0.040, 0.060, 0.020, 1.00},   -- texto escuro sobre o verde-limao
    ghost       = {0.035, 0.035, 0.035, 1.00},
    ghostHover  = {0.085, 0.085, 0.085, 1.00},
    disabled    = {0.015, 0.015, 0.015, 1.00},
    danger      = {0.760, 0.290, 0.270, 1.00},
    dangerHover = {0.900, 0.390, 0.350, 1.00},
    white       = {1.000, 1.000, 1.000, 1.00},
    text        = {0.920, 0.940, 0.960, 1.00},
    muted       = {0.660, 0.720, 0.780, 1.00},
    mutedOff    = {0.440, 0.480, 0.530, 1.00},
    green       = {0.722, 0.976, 0.000, 1.00},   -- #B8F900 Cor ian Modding
    lime        = {0.480, 0.850, 0.300, 1.00},
    rowLate     = {0.065, 0.025, 0.025, 1.00},
    warn        = {0.950, 0.720, 0.220, 1.00},
    bad         = {0.930, 0.350, 0.320, 1.00}
}

-- O jogo trata cores de drawFilledRect/renderText como lineares (ficam lavadas).
-- Convertendo de sRGB para linear, a cor na tela fica exatamente a escolhida (#B8F900 etc).
local GAMMA = 2.2
local function lin(v)
    return v ^ GAMMA
end

BankUI.INPUT_CONTEXT = "BANK_UI_CONTEXT"
BankUI.contextActive = false

BankUI.isOpen = false
BankUI.amount = 50000
BankUI.termIndex = 2 -- 12 meses
BankUI.investmentAmount = 50000
BankUI.investmentTermIndex = 3 -- 12 meses
BankUI.activeTab = "loans"
BankUI.mouseX = 0
BankUI.mouseY = 0
BankUI.hitRects = {}
BankUI.available = 0
BankUI.debt = 0
BankUI.balance = 0
BankUI.refreshTimer = 0
BankUI.anim = 0
BankUI.alpha = 1
BankUI.dragging = false
BankUI.maxAllowed = BankManager.MAX_AMOUNT
BankUI.slider = nil
BankUI.iconOverlay = nil

---------------------------------------------------------------------
-- Abrir / fechar
---------------------------------------------------------------------
function BankUI:open()
    if self.isOpen or drawFilledRect == nil then
        return
    end
    self.isOpen = true
    self.anim = 0
    self.dragging = false
    self.refreshTimer = 0
    self:refreshData()
    self:lockInput()
    g_inputBinding:setShowMouseCursor(true)

    if self.iconOverlay == nil and createImageOverlay ~= nil then
        local ok, overlay = pcall(createImageOverlay, Utils.getFilename("images/menuIcon.png", BankMain.dir))
        if ok and overlay ~= nil and overlay ~= 0 then
            self.iconOverlay = overlay
        end
    end
end

function BankUI:close()
    if not self.isOpen then
        return
    end
    self.isOpen = false
    self.dragging = false
    g_inputBinding:setShowMouseCursor(false)
    self:unlockInput()
end

-- Entra num contexto de entrada proprio: camera, andar e demais acoes do jogador ficam
-- desativados enquanto o banco esta aberto (so o mouse da nossa tela funciona).
function BankUI:lockInput()
    if self.contextActive then
        return
    end
    local ok = pcall(function()
        g_inputBinding:setContext(BankUI.INPUT_CONTEXT, true, false)
    end)
    self.contextActive = ok
end

function BankUI:unlockInput()
    if not self.contextActive then
        return
    end
    self.contextActive = false
    pcall(function()
        g_inputBinding:revertContext(true)
    end)
end

function BankUI:toggle()
    if self.isOpen then
        self:close()
    else
        self:open()
    end
end

function BankUI:deleteOverlay()
    if self.iconOverlay ~= nil then
        delete(self.iconOverlay)
        self.iconOverlay = nil
    end
end

---------------------------------------------------------------------
-- Dados (cache para nao recalcular patrimonio a cada frame)
---------------------------------------------------------------------
function BankUI:refreshData()
    if not self.isOpen or g_bankManager == nil then
        return
    end
    local farmId = g_currentMission:getFarmId()
    self.available = g_bankManager:getAvailableCredit(farmId)
    self.debt = g_bankManager:getTotalDebt(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    self.balance = farm ~= nil and math.max(0, farm:getBalance()) or 0
end

function BankUI:update(dt)
    if not self.isOpen then
        return
    end
    if g_gui:getIsGuiVisible() or g_currentMission:getFarmId() == FarmManager.SPECTATOR_FARM_ID then
        self:close()
        return
    end
    self.anim = math.min(1, self.anim + dt / 220)
    self.refreshTimer = self.refreshTimer + dt
    if self.refreshTimer > 500 then
        self.refreshTimer = 0
        self:refreshData()
    end
end

---------------------------------------------------------------------
-- Entrada
---------------------------------------------------------------------
function BankUI:setAmountFromMouse()
    local s = self.slider
    if s == nil then
        return
    end
    local ratio = math.max(0, math.min(1, (self.mouseX - s.x) / s.w))
    local step = BankManager.AMOUNT_STEP
    local top = self.activeTab == "investments"
        and math.min(BankManager.MAX_AMOUNT, math.floor(self.balance / step) * step)
        or math.min(BankManager.MAX_AMOUNT, self.maxAllowed or BankManager.MAX_AMOUNT)
    local raw = BankManager.MIN_AMOUNT + ratio * (top - BankManager.MIN_AMOUNT)
    local amount = math.max(BankManager.MIN_AMOUNT, math.min(top, math.floor(raw / step + 0.5) * step))
    if self.activeTab == "investments" then
        self.investmentAmount = amount
    else
        self.amount = amount
    end
end

function BankUI:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isOpen then
        return
    end
    self.mouseX = posX * 1920
    self.mouseY = posY * 1080

    if self.dragging then
        self:setAmountFromMouse()
        if isUp and button == Input.MOUSE_BUTTON_LEFT then
            self.dragging = false
        end
        return
    end

    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        for _, r in ipairs(self.hitRects) do
            if self.mouseX >= r.x and self.mouseX <= r.x + r.w and self.mouseY >= r.y and self.mouseY <= r.y + r.h then
                if r.id == "slider" then
                    self.dragging = true
                    self:setAmountFromMouse()
                else
                    self:onClick(r.id)
                end
                break
            end
        end
    end
end

function BankUI:keyEvent(unicode, sym, modifier, isDown)
    if self.isOpen and isDown and sym == Input.KEY_esc then
        self:close()
    end
end

function BankUI:onClick(id)
    local bm = g_bankManager
    if id == "close" then
        self:close()
    elseif id == "tabLoans" then
        self.activeTab = "loans"
    elseif id == "tabInvestments" then
        self.activeTab = "investments"
    elseif id == "invest" then
        bm:request(BankManager.ACTION_INVEST, self.investmentAmount, BankManager.INVESTMENT_TERMS[self.investmentTermIndex])
    elseif id == "amountDown" then
        if self.activeTab == "investments" then
            self.investmentAmount = math.max(BankManager.MIN_AMOUNT, self.investmentAmount - BankManager.AMOUNT_STEP)
        else
            self.amount = math.max(BankManager.MIN_AMOUNT, self.amount - BankManager.AMOUNT_STEP)
        end
    elseif id == "amountUp" then
        if self.activeTab == "investments" then
            local maxAmount = math.min(BankManager.MAX_AMOUNT, math.floor(self.balance / BankManager.AMOUNT_STEP) * BankManager.AMOUNT_STEP)
            self.investmentAmount = math.min(maxAmount, self.investmentAmount + BankManager.AMOUNT_STEP)
        else
            self.amount = math.min(math.min(BankManager.MAX_AMOUNT, self.maxAllowed), self.amount + BankManager.AMOUNT_STEP)
        end
    elseif string.sub(id, 1, 3) == "amt" then
        local amount = tonumber(string.sub(id, 4))
        if amount ~= nil then
            if self.activeTab == "investments" then
                self.investmentAmount = amount
            else
                self.amount = amount
            end
        end
    elseif string.sub(id, 1, 10) == "investTerm" then
        self.investmentTermIndex = tonumber(string.sub(id, 11))
    elseif string.sub(id, 1, 4) == "term" then
        self.termIndex = tonumber(string.sub(id, 5))
    elseif id == "borrow" then
        bm:request(BankManager.ACTION_BORROW, self.amount, BankManager.TERMS[self.termIndex])
    elseif string.sub(id, 1, 6) == "payoff" then
        local index = tonumber(string.sub(id, 7))
        local loan = bm:getFarmLoans(g_currentMission:getFarmId())[index]
        if loan ~= nil then
            bm:request(BankManager.ACTION_PAYOFF, loan.id, 0)
        end
    end
end

---------------------------------------------------------------------
-- Primitivas de desenho (todas respeitam a animacao de entrada via self.alpha)
---------------------------------------------------------------------
function BankUI:rect(x, y, w, h, c, alphaMul)
    drawFilledRect(x / 1920, y / 1080, w / 1920, h / 1080, lin(c[1]), lin(c[2]), lin(c[3]), c[4] * self.alpha * (alphaMul or 1))
end

-- Retangulo com cantos arredondados (r deve ser par). Faixas de 2px aproximam o circulo.
function BankUI:roundRect(x, y, w, h, r, c, alphaMul)
    r = math.min(r, math.floor(h / 2), math.floor(w / 2))
    r = r - (r % 2)
    if r < 2 then
        self:rect(x, y, w, h, c, alphaMul)
        return
    end

    local step = 2
    self:rect(x, y + r, w, h - 2 * r, c, alphaMul)
    for k = 0, r / step - 1 do
        local d = (k + 0.5) * step
        local inset = r - math.sqrt(math.max(r * r - (r - d) * (r - d), 0))
        self:rect(x + inset, y + k * step, w - 2 * inset, step, c, alphaMul)
        self:rect(x + inset, y + h - (k + 1) * step, w - 2 * inset, step, c, alphaMul)
    end
end

-- (x, y) = ancora; y e o CENTRO vertical do texto
function BankUI:text(x, y, size, str, c, align, bold)
    setTextBold(bold == true)
    setTextColor(lin(c[1]), lin(c[2]), lin(c[3]), c[4] * self.alpha)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    renderText(x / 1920, y / 1080, size / 1080, str)

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
end

function BankUI:isHover(x, y, w, h)
    return self.mouseX >= x and self.mouseX <= x + w and self.mouseY >= y and self.mouseY <= y + h
end

function BankUI:button(id, x, y, w, h, label, enabled, style, textSize, radius)
    local hover = enabled and self:isHover(x, y, w, h)
    local c
    if not enabled then
        c = COLOR.disabled
    elseif style == "accent" then
        c = hover and COLOR.accentHover or COLOR.accent
    elseif style == "danger" then
        c = hover and COLOR.dangerHover or COLOR.danger
    else
        c = hover and COLOR.ghostHover or COLOR.ghost
    end

    self:roundRect(x, y, w, h, radius or 10, c)
    local textColor = COLOR.white
    if not enabled then
        textColor = COLOR.mutedOff
    elseif style == "accent" then
        textColor = COLOR.onAccent
    end
    self:text(x + w / 2, y + h / 2, textSize or 20, label, textColor, RenderText.ALIGN_CENTER, true)

    if enabled then
        table.insert(self.hitRects, {id = id, x = x, y = y, w = w, h = h})
    end
end

function BankUI:chip(id, x, y, w, h, label, selected, enabled)
    if enabled == nil then
        enabled = true
    end
    local hover = enabled and self:isHover(x, y, w, h)
    local c = COLOR.ghost
    if not enabled then
        c = COLOR.disabled
    elseif selected then
        c = COLOR.accent
    elseif hover then
        c = COLOR.ghostHover
    end
    self:roundRect(x, y, w, h, 10, c)

    local textColor = COLOR.text
    if not enabled then
        textColor = COLOR.mutedOff
    elseif selected then
        textColor = COLOR.onAccent
    end
    self:text(x + w / 2, y + h / 2, 17, label, textColor, RenderText.ALIGN_CENTER, selected and enabled)
    if enabled then
        table.insert(self.hitRects, {id = id, x = x, y = y, w = w, h = h})
    end
end

function BankUI:bar(x, y, w, h, ratio, c)
    ratio = math.max(0, math.min(1, ratio))
    self:roundRect(x, y, w, h, h, COLOR.track)
    if ratio > 0 then
        self:roundRect(x, y, math.max(h, w * ratio), h, h, c)
    end
end

local function scoreStyle(score)
    local f = score / BankManager.SCORE_MAX
    if f >= 0.8 then
        return COLOR.green, "bank_tier_excellent"
    elseif f >= 0.6 then
        return COLOR.lime, "bank_tier_good"
    elseif f >= 0.4 then
        return COLOR.warn, "bank_tier_fair"
    end
    return COLOR.bad, "bank_tier_low"
end

---------------------------------------------------------------------
-- Desenho do painel
---------------------------------------------------------------------
function BankUI:draw()
    if not self.isOpen then
        return
    end
    local ok, err = pcall(self.drawPanel, self)
    if not ok then
        Logging.error("[BancoModerno] erro ao desenhar a tela: %s", tostring(err))
        self:close() -- nunca deixa o jogador preso
    end
end

function BankUI:drawInvestmentPanel(ox, oy, W, farmId)
    local bm = g_bankManager
    local farm = g_farmManager:getFarmById(farmId)
    if bm == nil or farm == nil then
        return
    end

    local T = function(key) return g_i18n:getText(key) end
    local fmt = BankManager.formatMoney
    local investments = bm:getInvestments(farmId)
    local maxAmount = math.min(
        BankManager.MAX_AMOUNT,
        math.floor(math.max(farm:getBalance(), 0) / BankManager.AMOUNT_STEP) * BankManager.AMOUNT_STEP
    )
    if maxAmount >= BankManager.MIN_AMOUNT then
        self.investmentAmount = math.min(self.investmentAmount, maxAmount)
    else
        self.investmentAmount = BankManager.MIN_AMOUNT
    end

    local termMonths = BankManager.INVESTMENT_TERMS[self.investmentTermIndex]
    local annualRate = BankManager.INVESTMENT_RATES[termMonths]
    local maturityValue = math.floor(self.investmentAmount * (1 + annualRate / 12) ^ termMonths + 0.5)
    local profit = maturityValue - self.investmentAmount
    local canInvest = maxAmount >= BankManager.MIN_AMOUNT
        and #investments < BankManager.MAX_INVESTMENTS_PER_FARM
        and self.investmentAmount <= maxAmount
    local investmentSlotsUsed = #investments / BankManager.MAX_INVESTMENTS_PER_FARM

    local nx, nw = ox + 24, W - 48
    local ny = oy + 272
    self:roundRect(nx, ny, nw, 224, 14, COLOR.card)
    self:text(nx + 24, ny + 200, 22, T("bank_new_investment"), COLOR.green, RenderText.ALIGN_LEFT, true)
    if #investments >= BankManager.MAX_INVESTMENTS_PER_FARM then
        self:text(nx + nw - 24, ny + 200, 15, T("bank_investment_limit"), COLOR.warn, RenderText.ALIGN_RIGHT, true)
    elseif maxAmount < BankManager.MIN_AMOUNT then
        self:text(nx + nw - 24, ny + 200, 15, T("bank_investment_insufficient"), COLOR.warn, RenderText.ALIGN_RIGHT, true)
    else
        self:text(nx + nw - 24, ny + 200, 16, string.format(
            T("bank_investment_estimate"),
            fmt(maturityValue),
            fmt(profit),
            annualRate * 100
        ), COLOR.muted, RenderText.ALIGN_RIGHT)
    end
    self:text(nx + 24, ny + 178, 14, T("bank_investment_lock"), COLOR.muted)
    self:text(nx + 24, ny + 145, 44, fmt(self.investmentAmount), COLOR.white, RenderText.ALIGN_LEFT, true)
    self:button("amountDown", nx + nw - 132, ny + 125, 48, 40, T("bank_minus"), self.investmentAmount > BankManager.MIN_AMOUNT, "ghost", 26, 10)
    self:button("amountUp", nx + nw - 72, ny + 125, 48, 40, T("bank_plus"), self.investmentAmount < maxAmount, "ghost", 26, 10)

    local tx, ty, tw = nx + 24, ny + 100, nw - 48
    local ratio = maxAmount > BankManager.MIN_AMOUNT
        and (self.investmentAmount - BankManager.MIN_AMOUNT) / (maxAmount - BankManager.MIN_AMOUNT)
        or 0
    self:bar(tx, ty, tw, 10, ratio, canInvest and COLOR.accent or COLOR.mutedOff)
    local handleX = tx + ratio * tw - 12
    self:roundRect(handleX - 2, ty - 7, 28, 28, 14, {0, 0, 0, 0.35})
    self:roundRect(handleX, ty - 5, 24, 24, 12, COLOR.white)
    self.slider = {x = tx, y = ty, w = tw}
    table.insert(self.hitRects, {id = "slider", x = tx - 12, y = ty - 16, w = tw + 24, h = 44})

    local quickAmounts = BankUI.QUICK_AMOUNTS
    local gap = 12
    local chipWidth = (tw - (#quickAmounts - 1) * gap) / #quickAmounts
    for index, amount in ipairs(quickAmounts) do
        self:chip(
            "amt" .. amount,
            tx + (index - 1) * (chipWidth + gap),
            ny + 52,
            chipWidth,
            36,
            fmt(amount),
            self.investmentAmount == amount,
            amount <= maxAmount
        )
    end

    self:text(nx + 24, ny + 26, 18, T("bank_term"), COLOR.muted)
    local firstTermX = nx + 130
    local termCount = #BankManager.INVESTMENT_TERMS
    local termWidth = (nw - 154 - (termCount - 1) * gap) / termCount
    for index, months in ipairs(BankManager.INVESTMENT_TERMS) do
        local x = firstTermX + (index - 1) * (termWidth + gap)
        self:chip(
            "investTerm" .. index,
            x,
            ny + 8,
            termWidth,
            32,
            string.format(T("bank_term_value"), months),
            self.investmentTermIndex == index
        )
    end

    local listY, listHeight = oy + 24, 232
    self:roundRect(nx, listY, nw, listHeight, 14, COLOR.card)
    self:text(nx + 24, listY + 208, 22, T("bank_my_investments"), COLOR.green, RenderText.ALIGN_LEFT, true)
    self:text(nx + nw - 24, listY + 208, 16, string.format(
        T("bank_investment_count"),
        #investments
    ), COLOR.muted, RenderText.ALIGN_RIGHT)

    if #investments == 0 then
        self:text(nx + nw / 2, listY + 105, 20, T("bank_no_investments"), COLOR.muted, RenderText.ALIGN_CENTER)
    else
        self:text(nx + 32, listY + 184, 14, T("bank_amount"), COLOR.muted)
        self:text(nx + 320, listY + 184, 14, T("bank_term"), COLOR.muted)
        self:text(nx + nw - 32, listY + 184, 14, T("bank_investment_maturity_value"), COLOR.muted, RenderText.ALIGN_RIGHT)

        for index = 1, math.min(#investments, BankManager.MAX_INVESTMENTS_PER_FARM) do
            local investment = investments[index]
            local rowY = listY + 150 - (index - 1) * 32
            self:roundRect(nx + 20, rowY, nw - 40, 28, 8, COLOR.row)
            self:text(nx + 32, rowY + 14, 16, fmt(investment.principal), COLOR.white, RenderText.ALIGN_LEFT, true)
            self:text(nx + 320, rowY + 14, 15, string.format(
                T("bank_investment_term_left"),
                investment.monthsLeft,
                investment.annualRate * 100
            ), COLOR.muted)
            self:text(nx + nw - 32, rowY + 14, 16, fmt(investment.maturityValue), COLOR.green, RenderText.ALIGN_RIGHT, true)
        end
    end

    self:button(
        "invest",
        nx + nw - 184,
        ny + 14,
        160,
        46,
        T("bank_invest"),
        canInvest,
        "accent",
        20,
        12
    )
end

function BankUI:drawPanel()
    local bm = g_bankManager
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if bm == nil or farm == nil then
        return
    end

    self.hitRects = {}
    self.slider = nil

    local t = 1 - (1 - self.anim) ^ 3
    self.alpha = t

    local fmt = BankManager.formatMoney
    local T = function(key) return g_i18n:getText(key) end
    local months = BankManager.TERMS[self.termIndex]
    local rate = bm:getAnnualRate(farmId, months)
    local installment = BankManager.calcInstallment(self.amount, rate, months)
    local totalPay = installment * months
    local loans = bm:getFarmLoans(farmId)
    local investments = bm:getInvestments(farmId)
    local investedPrincipal = 0
    for _, investment in ipairs(investments) do
        investedPrincipal = investedPrincipal + investment.principal
    end
    local isInvestmentsTab = self.activeTab == "investments"
    local score = bm:getScore(farmId)
    self.maxAllowed = bm:getMaxLoanAmount(farmId)
    if self.amount > self.maxAllowed then
        self.amount = math.max(BankManager.MIN_AMOUNT, self.maxAllowed)
    end
    local hasOverdue = bm:hasOverdue(farmId)
    local overLimit = self.amount > self.available
    local maxLoans = #loans >= BankManager.MAX_LOANS_PER_FARM
    local canBorrow = not overLimit and not maxLoans

    local P = BankUI.PANEL
    local ox, oy = P.x, P.y - (1 - t) * 28
    local W = P.w

    -- fundo escurecido, sombra e painel
    drawFilledRect(0, 0, 1, 1, 0, 0, 0, 0.55 * t)
    for i = 1, 5 do
        self:roundRect(ox - i * 5, oy - i * 5 - 8, W + i * 10, P.h + i * 10, 18 + i * 2, {0, 0, 0, 0.06})
    end
    self:roundRect(ox, oy, W, P.h, 18, COLOR.panel)

    ---------------- cabecalho ----------------
    self:roundRect(ox + 24, oy + 652, 56, 56, 14, COLOR.accent)
    if self.iconOverlay ~= nil then
        setOverlayColor(self.iconOverlay, lin(0.04), lin(0.06), lin(0.02), self.alpha)
        renderOverlay(self.iconOverlay, (ox + 32) / 1920, (oy + 660) / 1080, 40 / 1920, 40 / 1080)
    end
    self:text(ox + 96, oy + 693, 32, T("bank_title"), COLOR.white, RenderText.ALIGN_LEFT, true)
    self:text(ox + 96, oy + 666, 17, tostring(farm.name or ""), COLOR.muted)

    self:text(ox + W - 96, oy + 700, 15, T("bank_balance_label"), COLOR.muted, RenderText.ALIGN_RIGHT)
    self:text(ox + W - 96, oy + 674, 30, fmt(farm:getBalance()), COLOR.green, RenderText.ALIGN_RIGHT, true)
    self:button("close", ox + W - 68, oy + 658, 44, 44, T("bank_close"), true, "ghost", 20, 12)

    self:rect(ox + 24, oy + 636, W - 48, 1, COLOR.line)

    ---------------- cartoes de status ----------------
    local sy = oy + 512
    local cardW = (W - 48 - 32) / 3

    -- credito disponivel
    local x1 = ox + 24
    self:roundRect(x1, sy, cardW, 108, 14, COLOR.card)
    self:text(x1 + 20, sy + 88, 16, isInvestmentsTab and T("bank_invested_total") or T("bank_available"), COLOR.muted)
    self:text(x1 + 20, sy + 56, 30, fmt(isInvestmentsTab and investedPrincipal or self.available), COLOR.white, RenderText.ALIGN_LEFT, true)
    local used = self.debt + self.available > 0 and self.debt / (self.debt + self.available) or 0
    local firstCardSub = isInvestmentsTab
        and string.format(T("bank_investment_count"), #investments)
        or string.format(T("bank_in_use"), math.floor(used * 100 + 0.5))
    local firstCardRatio = used
    local firstCardColor = used > 0.8 and COLOR.warn or COLOR.accent
    if isInvestmentsTab then
        firstCardRatio = investmentSlotsUsed
        firstCardColor = COLOR.accent
    end
    self:text(x1 + cardW - 20, sy + 88, 15, firstCardSub, COLOR.muted, RenderText.ALIGN_RIGHT)
    self:bar(
        x1 + 20,
        sy + 20,
        cardW - 40,
        8,
        firstCardRatio,
        firstCardColor
    )

    -- divida total
    local x2 = ox + 24 + cardW + 16
    local monthly = 0
    for _, loan in ipairs(loans) do
        monthly = monthly + loan.installment
    end
    self:roundRect(x2, sy, cardW, 108, 14, COLOR.card)
    self:text(x2 + 20, sy + 88, 16, T("bank_debt_title"), COLOR.muted)
    self:text(x2 + 20, sy + 56, 30, fmt(self.debt), self.debt > 0 and COLOR.warn or COLOR.white, RenderText.ALIGN_LEFT, true)
    self:text(x2 + 20, sy + 30, 15, string.format(T("bank_active_loans"), #loans, BankManager.MAX_LOANS_PER_FARM), COLOR.muted)
    self:text(x2 + 20, sy + 12, 15, string.format(T("bank_monthly_total"), fmt(monthly)), COLOR.muted)

    -- score
    local x3 = ox + 24 + (cardW + 16) * 2
    local scoreColor, tierKey = scoreStyle(score)
    self:roundRect(x3, sy, cardW, 108, 14, COLOR.card)
    self:text(x3 + 20, sy + 88, 16, T("bank_score_title"), COLOR.muted)
    self:text(x3 + 20, sy + 56, 30, string.format("%d/%d", score, BankManager.SCORE_MAX), scoreColor, RenderText.ALIGN_LEFT, true)
    self:text(x3 + cardW - 20, sy + 88, 16, T(tierKey), scoreColor, RenderText.ALIGN_RIGHT, true)
    self:bar(x3 + 20, sy + 20, cardW - 40, 8, score / BankManager.SCORE_MAX, scoreColor)

    self:button("tabLoans", ox + 24, oy + 640, 200, 32, T("bank_tab_loans"), true, not isInvestmentsTab and "accent" or "ghost", 17, 8)
    self:button("tabInvestments", ox + 236, oy + 640, 220, 32, T("bank_tab_investments"), true, isInvestmentsTab and "accent" or "ghost", 17, 8)

    if isInvestmentsTab then
        self:drawInvestmentPanel(ox, oy, W, farmId)
        return
    end

    ---------------- novo emprestimo ----------------
    local ny, nh, nw = oy + 272, 224, 620
    local nx = ox + 24
    self:roundRect(nx, ny, nw, nh, 14, COLOR.card)
    self:text(nx + 24, ny + 200, 22, T("bank_new_loan"), COLOR.green, RenderText.ALIGN_LEFT, true)
    if hasOverdue then
        self:text(nx + nw - 24, ny + 200, 15, string.format(T("bank_overdue_limit"), fmt(self.maxAllowed)), COLOR.bad, RenderText.ALIGN_RIGHT, true)
    elseif self.maxAllowed < BankManager.MAX_AMOUNT then
        self:text(nx + nw - 24, ny + 200, 15, string.format(T("bank_score_limit"), fmt(self.maxAllowed)), COLOR.warn, RenderText.ALIGN_RIGHT, true)
    end
    self:text(nx + 24, ny + 158, 44, fmt(self.amount), COLOR.white, RenderText.ALIGN_LEFT, true)
    self:button("amountDown", nx + nw - 132, ny + 138, 48, 40, T("bank_minus"), self.amount > BankManager.MIN_AMOUNT, "ghost", 26, 10)
    self:button("amountUp", nx + nw - 72, ny + 138, 48, 40, T("bank_plus"), self.amount < math.min(BankManager.MAX_AMOUNT, self.maxAllowed), "ghost", 26, 10)

    -- slider
    local tx, ty, tw = nx + 24, ny + 112, nw - 48
    local ratio = (self.amount - BankManager.MIN_AMOUNT) / (BankManager.MAX_AMOUNT - BankManager.MIN_AMOUNT)
    self:bar(tx, ty, tw, 10, ratio, overLimit and COLOR.warn or COLOR.accent)
    local lockRatio = (math.min(self.maxAllowed, BankManager.MAX_AMOUNT) - BankManager.MIN_AMOUNT) / (BankManager.MAX_AMOUNT - BankManager.MIN_AMOUNT)
    if lockRatio < 1 then
        self:roundRect(tx + tw * lockRatio, ty, tw * (1 - lockRatio), 10, 4, COLOR.bad, 0.55)
    end
    local handleX = tx + ratio * tw - 12
    self:roundRect(handleX - 2, ty - 7, 28, 28, 14, {0, 0, 0, 0.35})
    self:roundRect(handleX, ty - 5, 24, 24, 12, COLOR.white)
    self.slider = {x = tx, y = ty, w = tw}
    table.insert(self.hitRects, {id = "slider", x = tx - 12, y = ty - 16, w = tw + 24, h = 44})

    -- valores rapidos
    local qn = #BankUI.QUICK_AMOUNTS
    local qgap = 12
    local qw = (tw - (qn - 1) * qgap) / qn
    for i, value in ipairs(BankUI.QUICK_AMOUNTS) do
        self:chip("amt" .. value, tx + (i - 1) * (qw + qgap), ny + 64, qw, 36, fmt(value), self.amount == value, value <= self.maxAllowed)
    end

    -- prazo
    self:text(nx + 24, ny + 32, 18, T("bank_term"), COLOR.muted)
    local cx0 = nx + 120
    local tn = #BankManager.TERMS
    local cw = (nw - 24 - 120 - (tn - 1) * qgap) / tn
    for i, m in ipairs(BankManager.TERMS) do
        self:chip("term" .. i, cx0 + (i - 1) * (cw + qgap), ny + 14, cw, 36, string.format(T("bank_term_value"), m), self.termIndex == i)
    end

    ---------------- resumo ----------------
    local rx, rw = ox + 24 + nw + 16, W - 48 - nw - 16
    self:roundRect(rx, ny, rw, nh, 14, COLOR.card)
    self:text(rx + 24, ny + 200, 22, T("bank_summary"), COLOR.green, RenderText.ALIGN_LEFT, true)
    if overLimit then
        self:text(rx + rw - 24, ny + 200, 15, T("bank_over_limit"), COLOR.bad, RenderText.ALIGN_RIGHT, true)
    elseif maxLoans then
        self:text(rx + rw - 24, ny + 200, 15, T("bank_max_loans"), COLOR.bad, RenderText.ALIGN_RIGHT, true)
    end

    local lines = {
        {T("bank_monthly"), fmt(installment), COLOR.white},
        {T("bank_total"), fmt(totalPay), COLOR.text},
        {T("bank_interest"), fmt(totalPay - self.amount), COLOR.warn},
        {T("bank_rate_label"), string.format("%.1f%%", rate * 100), COLOR.text}
    }
    for i, line in ipairs(lines) do
        local ly = ny + 164 - (i - 1) * 30
        self:text(rx + 24, ly, 17, line[1], COLOR.muted)
        self:text(rx + rw - 24, ly, 19, line[2], line[3], RenderText.ALIGN_RIGHT, true)
    end
    self:button("borrow", rx + 16, ny + 14, rw - 32, 46, T("bank_borrow"), canBorrow, "accent", 22, 12)

    ---------------- meus emprestimos ----------------
    local ly0, lh = oy + 24, 232
    self:roundRect(nx, ly0, W - 48, lh, 14, COLOR.card)
    self:text(nx + 24, ly0 + 208, 22, T("bank_my_loans"), COLOR.green, RenderText.ALIGN_LEFT, true)
    self:text(nx + W - 48 - 24, ly0 + 208, 16, string.format("%d/%d", #loans, BankManager.MAX_LOANS_PER_FARM), COLOR.muted, RenderText.ALIGN_RIGHT)

    if #loans == 0 then
        self:text(nx + (W - 48) / 2, ly0 + 100, 20, T("bank_no_loans"), COLOR.muted, RenderText.ALIGN_CENTER)
    end

    for i = 1, BankManager.MAX_LOANS_PER_FARM do
        local loan = loans[i]
        if loan ~= nil then
            local ry = oy + 176 - (i - 1) * 36
            local cy = ry + 16
            local late = loan.missed > 0
            self:roundRect(nx + 20, ry, W - 48 - 40, 32, 10, late and COLOR.rowLate or COLOR.row)
            self:text(nx + 36, cy, 19, string.format(T("bank_remaining"), fmt(loan.remaining)), COLOR.white, RenderText.ALIGN_LEFT, true)
            if late then
                self:text(nx + 250, cy, 16, string.format(T("bank_row_overdue"), fmt(loan.installment), loan.monthsLeft), COLOR.bad, RenderText.ALIGN_LEFT, true)
            else
                self:text(nx + 250, cy, 16, string.format(T("bank_row_detail"), fmt(loan.installment), loan.monthsLeft, loan.annualRate * 100), COLOR.muted)
            end

            local paid = loan.principal > 0 and 1 - loan.remaining / loan.principal or 0
            self:bar(nx + 640, cy - 4, 140, 8, paid, COLOR.accent)
            self:text(nx + 792, cy, 15, string.format(T("bank_paid"), math.max(0, math.floor(paid * 100 + 0.5))), COLOR.muted)
            self:button("payoff" .. i, nx + W - 48 - 20 - 100, ry + 3, 100, 26, T("bank_payoff"), true, "danger", 16, 8)
        end
    end
end

addModEventListener(BankUI)
