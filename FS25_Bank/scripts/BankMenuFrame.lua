-- Copyright © 2026 ian. All rights reserved.
-- BankMenuFrame.lua
-- Aba "Banco" dentro do menu ESC (InGameMenu). Layout em gui/BankMenuFrame.xml.
-- Se algo falhar ao registrar a aba, o banco continua funcionando pelo ALT+B (BankUI).

if TabbedMenuFrameElement == nil then
    return
end

BankMenuFrame = {}
local BankMenuFrame_mt = Class(BankMenuFrame, TabbedMenuFrameElement)

BankMenuFrame.MAX_ROWS = 5
BankMenuFrame.PAGE_NAME = "pageBank"

function BankMenuFrame.new()
    local self = TabbedMenuFrameElement.new(nil, BankMenuFrame_mt)
    self.name = "BankMenuFrame"
    self.amount = BankUI.amount
    self.termIndex = BankUI.termIndex
    self.isShown = false
    self.menuButtonInfo = {}
    self.maxAllowed = BankManager.MAX_AMOUNT
    self.loanView = "active"
    self.loanPage = 1
    return self
end

---------------------------------------------------------------------
-- Perfis do mod. Tenta o loadProfiles normal; se o jogo nao registrar,
-- le o proprio XML e cria os perfis com o GuiProfile do jogo.
---------------------------------------------------------------------
function BankMenuFrame.loadModProfiles()
    local path = BankMain.dir .. "gui/guiProfiles.xml"
    pcall(g_gui.loadProfiles, g_gui, path)

    if g_gui.profiles == nil or g_gui.profiles["bankPage"] ~= nil then
        return
    end

    local xmlFile = loadXMLFile("bankProfiles", path)
    local i = 0
    while true do
        local key = string.format("GUIProfiles.Profiles.Profile(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local profile = GuiProfile.new(g_gui.profiles, g_gui.traits)
        if profile:loadFromXML(xmlFile, key, {}, false, false) then
            g_gui.profiles[profile.name] = profile
        end
        i = i + 1
    end
    delete(xmlFile)
end

---------------------------------------------------------------------
-- Registro da aba no menu ESC. Retorna true quando registrou,
-- false se o menu ainda nao existe (tenta de novo depois).
---------------------------------------------------------------------
function BankMenuFrame.register(inGameMenu)
    inGameMenu = inGameMenu or g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil or inGameMenu.pagingElement == nil then
        return false
    end

    if inGameMenu[BankMenuFrame.PAGE_NAME] ~= nil then
        BankMenuFrame.INSTANCE = inGameMenu[BankMenuFrame.PAGE_NAME]
        return true
    end

    if inGameMenu.registerPage == nil
        or inGameMenu.addPageTab == nil
        or inGameMenu.exposeControlsAsFields == nil
        or inGameMenu.controlIDs == nil
        or inGameMenu.pageFrames == nil
        or inGameMenu.pagingElement.addPage == nil
        or inGameMenu.pagingElement.removePageByElement == nil then
        error("API de registro de paginas do menu ESC incompleta")
    end

    BankMenuFrame.loadModProfiles()

    local template = BankMenuFrame.new()
    g_gui:loadGui(BankMain.dir .. "gui/BankMenuFrame.xml", "BankMenuFrame", template, true)

    local pageName = BankMenuFrame.PAGE_NAME
    local referencePath = BankMain.dir .. "gui/BankMenuFrameRef.xml"
    local xmlFile = loadXMLFile("BankMenuFrameReferences", referencePath)
    if xmlFile == nil or xmlFile == 0 then
        error("nao foi possivel carregar " .. referencePath)
    end

    inGameMenu.controlIDs[pageName] = nil
    g_gui:loadGuiRec(xmlFile, "FrameReferences", inGameMenu.pagingElement, inGameMenu)
    inGameMenu:exposeControlsAsFields(pageName)
    inGameMenu.pagingElement:updatePageMapping()
    delete(xmlFile)

    local frame = g_gui:resolveFrameReference(inGameMenu[pageName])
    if frame == nil or frame.initialize == nil then
        error("nao foi possivel resolver a referencia da pagina " .. pageName)
    end
    if frame.elements == nil or frame.elements[1] == nil then
        error("a pagina Banco nao possui elemento raiz")
    end

    frame.elements[1].title = g_i18n:getText("bank_title")
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:removePageByElement(frame)

    local pagePosition = #inGameMenu.pageFrames + 1
    local _, actualPosition = inGameMenu:registerPage(frame, pagePosition, function() return true end)
    if actualPosition == nil then
        error("o menu ESC nao retornou a posicao da pagina Banco")
    end

    local iconFile = Utils.getFilename("images/menuIcon.png", BankMain.dir)
    inGameMenu:addPageTab(frame, iconFile, GuiUtils.getUVs({0, 0, 1024, 1024}))
    inGameMenu.pagingElement:addPage(
        string.upper(pageName),
        frame,
        g_i18n:getText("bank_title"),
        actualPosition
    )

    frame:onGuiSetupFinished()
    frame:initialize()
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    inGameMenu:rebuildTabList()

    BankMenuFrame.INSTANCE = frame
    return true
end

---------------------------------------------------------------------
-- Interface exigida pelo menu
---------------------------------------------------------------------
function BankMenuFrame:onGuiSetupFinished()
    BankMenuFrame:superClass().onGuiSetupFinished(self)
end

function BankMenuFrame:initialize()
    BankMenuFrame:superClass().initialize(self)
end

function BankMenuFrame:getMenuButtonInfo()
    return self.menuButtonInfo
end

function BankMenuFrame:onFrameOpen()
    BankMenuFrame:superClass().onFrameOpen(self)
    self.isShown = true
    self:safeRefresh()
end

function BankMenuFrame:onFrameClose()
    BankMenuFrame:superClass().onFrameClose(self)
    self.isShown = false
end

function BankMenuFrame:onDataChanged()
    if self.isShown then
        self:safeRefresh()
    end
end

function BankMenuFrame:safeRefresh()
    local ok, err = pcall(self.refresh, self)
    if not ok then
        Logging.error("[BancoModerno] erro ao atualizar a aba: %s", tostring(err))
    end
end

---------------------------------------------------------------------
-- Helpers tolerantes
---------------------------------------------------------------------
function BankMenuFrame:setTextOf(id, text)
    local element = self[id]
    if element ~= nil and element.setText ~= nil then
        element:setText(text)
    end
end

function BankMenuFrame:setDisabledOf(id, disabled)
    local element = self[id]
    if element ~= nil and element.setDisabled ~= nil then
        element:setDisabled(disabled)
    end
end

function BankMenuFrame:setVisibleOf(id, visible)
    local element = self[id]
    if element ~= nil and element.setVisible ~= nil then
        element:setVisible(visible)
    end
end

function BankMenuFrame:updateProgressBar(fillId, trackId, ratio)
    local fill = self[fillId]
    local track = self[trackId]
    if fill == nil or track == nil or fill.absSize == nil or track.absSize == nil then
        return
    end
    if fill._baseHeight == nil then
        fill._baseHeight = fill.absSize[2]
    end
    fill:setSize(track.absSize[1] * math.max(0, math.min(1, ratio)), fill._baseHeight)
end

---------------------------------------------------------------------
-- Atualiza textos e botoes
---------------------------------------------------------------------
function BankMenuFrame:refresh()
    local bm = g_bankManager
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if bm == nil or farm == nil then
        return
    end

    local fmt = BankManager.formatMoney
    local score = bm:getScore(farmId)
    local debt = bm:getTotalDebt(farmId)
    local maxAllowed = bm:getMaxLoanAmount(farmId)
    self.maxAllowed = maxAllowed
    self.amount = math.max(BankManager.MIN_AMOUNT, math.min(self.amount, maxAllowed))
    BankUI.amount = self.amount
    BankUI.termIndex = self.termIndex

    local months = BankManager.TERMS[self.termIndex]
    local rate = bm:getAnnualRate(farmId, months)
    local installment = BankManager.calcInstallment(self.amount, rate, months)
    local totalPay = installment * months
    local available = bm:getAvailableCredit(farmId)
    local loans = bm:getFarmLoans(farmId)
    local closedLoans = bm:getClosedLoans(farmId)
    local monthlyPayments = 0
    for _, loan in ipairs(loans) do
        monthlyPayments = monthlyPayments + loan.installment
    end
    local usedRatio = debt + available > 0 and debt / (debt + available) or 0
    local scoreRatio = score / BankManager.SCORE_MAX
    local tierKey
    if scoreRatio >= 0.8 then
        tierKey = "bank_tier_excellent"
    elseif scoreRatio >= 0.6 then
        tierKey = "bank_tier_good"
    elseif scoreRatio >= 0.4 then
        tierKey = "bank_tier_fair"
    else
        tierKey = "bank_tier_low"
    end

    self:setTextOf("farmNameText", tostring(farm.name or ""))
    self:setTextOf("balanceText", fmt(farm:getBalance()))
    self:setTextOf("availableText", fmt(available))
    self:setTextOf("availableUsageText", string.format(g_i18n:getText("bank_in_use"), math.floor(usedRatio * 100 + 0.5)))
    self:setTextOf("debtText", fmt(debt))
    self:setTextOf("monthlyLoansText", string.format(g_i18n:getText("bank_monthly_total"), fmt(monthlyPayments)))
    self:setTextOf("scoreText", string.format("%d/%d", score, BankManager.SCORE_MAX))
    self:setTextOf("scoreTierText", g_i18n:getText(tierKey))
    self:setTextOf("currentRateText", string.format("%.2f%%", rate * 100))

    self:setTextOf("amountText", fmt(self.amount))
    if bm:hasOverdue(farmId) then
        self:setTextOf("loanLimitText", string.format(g_i18n:getText("bank_overdue_limit"), fmt(maxAllowed)))
    elseif maxAllowed < BankManager.MAX_AMOUNT then
        self:setTextOf("loanLimitText", string.format(g_i18n:getText("bank_score_limit"), fmt(maxAllowed)))
    else
        self:setTextOf("loanLimitText", "")
    end

    self:setTextOf("monthlyPaymentText", fmt(installment))
    self:setTextOf("totalPayText", fmt(totalPay))
    self:setTextOf("interestText", fmt(totalPay - self.amount))
    self:setTextOf("rateText", string.format("%.1f%%", rate * 100))

    local canBorrow = self.amount <= available and self.amount <= maxAllowed and #loans < BankManager.MAX_LOANS_PER_FARM
    if self.amount > available then
        self:setTextOf("summaryWarningText", g_i18n:getText("bank_over_limit"))
    elseif #loans >= BankManager.MAX_LOANS_PER_FARM then
        self:setTextOf("summaryWarningText", g_i18n:getText("bank_max_loans"))
    else
        self:setTextOf("summaryWarningText", "")
    end

    self:setDisabledOf("borrowButton", not canBorrow)
    self:setDisabledOf("amountDownBtn", self.amount <= BankManager.MIN_AMOUNT)
    self:setDisabledOf("amountUpBtn", self.amount >= math.min(BankManager.MAX_AMOUNT, maxAllowed))

    for i, amount in ipairs(BankUI.QUICK_AMOUNTS) do
        local selected = self.amount == amount
        local normalId = "amountPreset" .. i
        local selectedId = normalId .. "Selected"
        local text = fmt(amount)
        self:setTextOf(normalId, text)
        self:setTextOf(selectedId, text)
        self:setVisibleOf(normalId, not selected)
        self:setVisibleOf(selectedId, selected)
        self:setDisabledOf(normalId, amount > maxAllowed)
    end

    for i, term in ipairs(BankManager.TERMS) do
        local selected = self.termIndex == i
        local normalId = "termChoice" .. i
        local selectedId = normalId .. "Selected"
        local text = string.format(g_i18n:getText("bank_term_value"), term)
        self:setTextOf(normalId, text)
        self:setTextOf(selectedId, text)
        self:setVisibleOf(normalId, not selected)
        self:setVisibleOf(selectedId, selected)
    end

    self:updateProgressBar("availableBarFill", "availableBarTrack", usedRatio)
    self:updateProgressBar("scoreBarFill", "scoreBarTrack", scoreRatio)
    self:updateProgressBar(
        "amountSliderFill",
        "amountSliderTrack",
        (self.amount - BankManager.MIN_AMOUNT) / (BankManager.MAX_AMOUNT - BankManager.MIN_AMOUNT)
    )

    local showingClosed = self.loanView == "closed"
    local displayedLoans = showingClosed and closedLoans or loans
    local pageCount = math.max(1, math.ceil(#displayedLoans / BankMenuFrame.MAX_ROWS))
    self.loanPage = math.max(1, math.min(self.loanPage, pageCount))
    self:setVisibleOf("activeLoansTab", showingClosed)
    self:setVisibleOf("activeLoansTabSelected", not showingClosed)
    self:setVisibleOf("closedLoansTab", not showingClosed)
    self:setVisibleOf("closedLoansTabSelected", showingClosed)
    self:setTextOf("loanCountText", showingClosed
        and string.format(g_i18n:getText("bank_closed_count"), #closedLoans)
        or string.format("%d/%d", #loans, BankManager.MAX_LOANS_PER_FARM))
    self:setTextOf("loanPageText", string.format(g_i18n:getText("bank_page_value"), self.loanPage, pageCount))
    self:setDisabledOf("loanPrevBtn", self.loanPage <= 1)
    self:setDisabledOf("loanNextBtn", self.loanPage >= pageCount)
    self:setTextOf("emptyLoansText", g_i18n:getText(showingClosed and "bank_no_closed_loans" or "bank_no_loans"))
    self:setVisibleOf("emptyLoansText", #displayedLoans == 0)

    for i = 1, BankMenuFrame.MAX_ROWS do
        local loanIndex = showingClosed
            and (#displayedLoans - (self.loanPage - 1) * BankMenuFrame.MAX_ROWS - i + 1)
            or ((self.loanPage - 1) * BankMenuFrame.MAX_ROWS + i)
        local loan = displayedLoans[loanIndex]
        local textId = "loanText" .. i
        local buttonId = "payoffBtn" .. i
        local backgroundId = "loanRowBg" .. i

        if loan ~= nil then
            if showingClosed then
                local closedStatus = loan.closedType == BankManager.CLOSED_LOAN_PAID_EARLY
                    and g_i18n:getText("bank_closed_early")
                    or g_i18n:getText("bank_closed_complete")
                self:setTextOf(textId, string.format(
                    g_i18n:getText("bank_closed_row"),
                    fmt(loan.principal),
                    fmt(loan.paidAmount),
                    closedStatus,
                    loan.annualRate * 100
                ))
            else
                self:setTextOf(textId, string.format(g_i18n:getText("bank_row"), fmt(loan.remaining), fmt(loan.installment), loan.monthsLeft, loan.annualRate * 100))
            end
            self:setVisibleOf(textId, true)
            self:setVisibleOf(buttonId, not showingClosed)
            self:setVisibleOf(backgroundId, true)
        else
            self:setVisibleOf(textId, false)
            self:setVisibleOf(buttonId, false)
            self:setVisibleOf(backgroundId, false)
        end
    end
end

---------------------------------------------------------------------
-- Botoes
---------------------------------------------------------------------
function BankMenuFrame:onClickAmountDown()
    self.amount = math.max(BankManager.MIN_AMOUNT, self.amount - BankManager.AMOUNT_STEP)
    self:safeRefresh()
end

function BankMenuFrame:onClickAmountUp()
    self.amount = math.min(math.min(BankManager.MAX_AMOUNT, self.maxAllowed), self.amount + BankManager.AMOUNT_STEP)
    self:safeRefresh()
end

function BankMenuFrame:setLoanView(view)
    if view ~= self.loanView then
        self.loanView = view
        self.loanPage = 1
        self:safeRefresh()
    end
end

function BankMenuFrame:changeLoansPage(offset)
    local farmId = g_currentMission:getFarmId()
    local loans = self.loanView == "closed"
        and g_bankManager:getClosedLoans(farmId)
        or g_bankManager:getFarmLoans(farmId)
    local pageCount = math.max(1, math.ceil(#loans / BankMenuFrame.MAX_ROWS))
    self.loanPage = math.max(1, math.min(self.loanPage + offset, pageCount))
    self:safeRefresh()
end

function BankMenuFrame:onClickActiveLoansTab()
    self:setLoanView("active")
end

function BankMenuFrame:onClickClosedLoansTab()
    self:setLoanView("closed")
end

function BankMenuFrame:onClickPreviousLoansPage()
    self:changeLoansPage(-1)
end

function BankMenuFrame:onClickNextLoansPage()
    self:changeLoansPage(1)
end

function BankMenuFrame:onClickPreviousLoansTab()
    self:setLoanView(self.loanView == "active" and "closed" or "active")
end

function BankMenuFrame:onClickNextLoansTab()
    self:setLoanView(self.loanView == "active" and "closed" or "active")
end

function BankMenuFrame:setAmountPreset(index)
    local amount = BankUI.QUICK_AMOUNTS[index]
    if amount ~= nil and amount <= self.maxAllowed then
        self.amount = amount
        self:safeRefresh()
    end
end

function BankMenuFrame:setTermChoice(index)
    if index >= 1 and index <= #BankManager.TERMS then
        self.termIndex = index
        self:safeRefresh()
    end
end

function BankMenuFrame:onClickAmountPreset1() self:setAmountPreset(1) end
function BankMenuFrame:onClickAmountPreset2() self:setAmountPreset(2) end
function BankMenuFrame:onClickAmountPreset3() self:setAmountPreset(3) end
function BankMenuFrame:onClickAmountPreset4() self:setAmountPreset(4) end
function BankMenuFrame:onClickAmountPreset5() self:setAmountPreset(5) end

function BankMenuFrame:onClickTermChoice1() self:setTermChoice(1) end
function BankMenuFrame:onClickTermChoice2() self:setTermChoice(2) end
function BankMenuFrame:onClickTermChoice3() self:setTermChoice(3) end
function BankMenuFrame:onClickTermChoice4() self:setTermChoice(4) end

function BankMenuFrame:onClickBorrow()
    g_bankManager:request(BankManager.ACTION_BORROW, self.amount, BankManager.TERMS[self.termIndex])
end

function BankMenuFrame:payoffRow(index)
    local loan = g_bankManager:getFarmLoans(g_currentMission:getFarmId())[index]
    if loan ~= nil then
        g_bankManager:request(BankManager.ACTION_PAYOFF, loan.id, 0)
    end
end

function BankMenuFrame:onClickPayoff1() self:payoffRow(1) end
function BankMenuFrame:onClickPayoff2() self:payoffRow(2) end
function BankMenuFrame:onClickPayoff3() self:payoffRow(3) end
function BankMenuFrame:onClickPayoff4() self:payoffRow(4) end
function BankMenuFrame:onClickPayoff5() self:payoffRow(5) end
