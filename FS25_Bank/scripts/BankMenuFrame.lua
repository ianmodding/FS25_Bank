-- Copyright © 2026 ian. All rights reserved.
-- BankMenuFrame.lua
-- Aba "Banco" dentro do menu ESC (InGameMenu). Layout em gui/BankMenuFrame.xml.
-- Se algo falhar ao registrar a aba, o banco continua funcionando pelo ALT+B (BankUI).

if TabbedMenuFrameElement == nil then
    return
end

BankMenuFrame = {}
local BankMenuFrame_mt = Class(BankMenuFrame, TabbedMenuFrameElement)

BankMenuFrame.PAGE_NAME = "pageBank"
BankMenuFrame.TAB = {
    ACTIVE = 1,
    CLOSED = 2,
}
BankMenuFrame.SCREEN_EDGE_SLIDER_MARGIN_X = 0
BankMenuFrame.NATIVE_DOCKED_SLIDER_OFFSET_Y = 10
BankMenuFrame.COLOR_ACTIVE = {0.33716, 0.55834, 0.0003, 1}
BankMenuFrame.COLOR_CLOSED = {0.40, 0.85, 0.40, 1}
BankMenuFrame.COLOR_OVERDUE = {0.95, 0.72, 0.22, 1}

function BankMenuFrame.new()
    local self = TabbedMenuFrameElement.new(nil, BankMenuFrame_mt)
    self.name = "BankMenuFrame"
    self.amount = BankUI.amount
    self.termIndex = BankUI.termIndex
    self.isShown = false
    self.maxAllowed = BankManager.MAX_AMOUNT
    self.currentTab = BankMenuFrame.TAB.ACTIVE
    self.currentView = "dashboard"
    self.selectedLoan = nil
    self.loansList = {}
    return self
end

---------------------------------------------------------------------
-- Perfis do mod. Tenta o loadProfiles normal; se o jogo nao registrar,
-- le o proprio XML e cria os perfis com o GuiProfile do jogo.
---------------------------------------------------------------------
function BankMenuFrame.loadModProfiles()
    local path = BankMain.dir .. "gui/guiProfiles.xml"
    if g_overlayManager ~= nil
        and (g_overlayManager.textureConfigs == nil or g_overlayManager.textureConfigs.fs25Bank == nil) then
        g_overlayManager:addTextureConfigFile(BankMain.dir .. "images/menuIcon.xml", "fs25Bank")
    end
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
    if self.listLoans ~= nil then
        self.listLoans:setDataSource(self)
        self.listLoans:setDelegate(self)
    end
    if self.listPaidLoans ~= nil then
        self.listPaidLoans:setDataSource(self)
        self.listPaidLoans:setDelegate(self)
    end
end

function BankMenuFrame:initialize()
    BankMenuFrame:superClass().initialize(self)
    for i, tab in pairs(self.subCategoryTabs or {}) do
        local tabIndex = i
        local background = tab:getDescendantByName("background")
        if background ~= nil then
            background.getIsSelected = function()
                return tabIndex == self.subCategoryPaging:getState()
            end
        end
        tab.getIsSelected = function()
            return tabIndex == self.subCategoryPaging:getState()
        end
    end

    self.btnBack = {inputAction = InputAction.MENU_BACK}
    self.btnNewLoan = {
        text = g_i18n:getText("bank_new_loan"),
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function() self:onClickNewLoan() end
    }
    self.btnPayoff = {
        text = g_i18n:getText("bank_payoff"),
        inputAction = InputAction.MENU_ACCEPT,
        disabled = true,
        callback = function() self:onClickPayoffSelected() end
    }
    self.btnFormBorrow = {
        text = g_i18n:getText("bank_borrow"),
        inputAction = InputAction.MENU_ACTIVATE,
        disabled = true,
        callback = function() self:onClickBorrow() end
    }
    self.btnFormBack = {
        text = g_i18n:getText("bank_modal_close"),
        inputAction = InputAction.MENU_BACK,
        callback = function() self:onClickBackToDashboard() end
    }
    self.menuButtonInfoByView = {
        active = {self.btnBack, self.btnNewLoan, self.btnPayoff},
        closed = {self.btnBack, self.btnNewLoan},
        loanForm = {self.btnFormBorrow, self.btnFormBack}
    }
end

function BankMenuFrame:getMenuButtonInfo()
    if self.menuButtonInfoByView == nil then
        return {}
    end
    local view = self.currentView == "loanForm"
        and "loanForm"
        or (self.currentTab == BankMenuFrame.TAB.ACTIVE and "active" or "closed")
    return self.menuButtonInfoByView[view] or {}
end

function BankMenuFrame:onFrameOpen()
    BankMenuFrame:superClass().onFrameOpen(self)
    self.isShown = true
    self.currentView = "dashboard"
    self.currentTab = BankMenuFrame.TAB.ACTIVE
    if self.subCategoryPaging ~= nil and self.subCategoryBox ~= nil then
        local texts = {
            g_i18n:getText("bank_active_tab"),
            g_i18n:getText("bank_closed_tab"),
        }
        self.subCategoryBox:invalidateLayout()
        self.subCategoryPaging:setTexts(texts)
        self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
        self.subCategoryPaging:setState(self.currentTab, true)
    end
    if self.setMenuButtonInfoDirty ~= nil then
        self:setMenuButtonInfoDirty()
    end
    self:safeRefresh()
end

function BankMenuFrame:onFrameClose()
    BankMenuFrame:superClass().onFrameClose(self)
    self.isShown = false
end

function BankMenuFrame:update(dt)
    BankMenuFrame:superClass().update(self, dt)
    self:updateScreenEdgeSliders()
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
    self:refreshDashboard()
    self:refreshList()
    self:updateViewVisibility()
end

function BankMenuFrame:refreshDashboard()
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

    self:updateBalanceDisplay(farm)
    self:setTextOf("dashAvailableValue", fmt(available))
    self:setTextOf("dashOutstandingValue", fmt(debt))
    self:setTextOf("dashOutstandingSubValue", string.format(
        g_i18n:getText("bank_debt_usage"),
        math.floor(usedRatio * 100 + 0.5)
    ))
    self:setTextOf("dashMonthlyTotalValue", fmt(monthlyPayments))
    self:setTextOf("dashRateValue", string.format("%.2f%% →", rate * 100))
    self:setTextOf("scoreText", string.format("%d/%d", score, BankManager.SCORE_MAX))
    self:setTextOf("scoreTierText", g_i18n:getText(tierKey))
    self:updateProgressBar("scoreProgressFill", "scoreProgressTrack", scoreRatio)

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
    if self.btnFormBorrow ~= nil then
        self.btnFormBorrow.disabled = not canBorrow
    end
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

    self:updateProgressBar(
        "amountSliderFill",
        "amountSliderTrack",
        (self.amount - BankManager.MIN_AMOUNT) / (BankManager.MAX_AMOUNT - BankManager.MIN_AMOUNT)
    )
end

function BankMenuFrame:updateBalanceDisplay(farm)
    if farm == nil or self.currentBalanceText == nil then
        return
    end
    if farm:getBalance() <= -1 then
        self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY_NEGATIVE, nil, true)
    else
        self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY, nil, true)
    end
    self.currentBalanceText:setText(BankManager.formatMoney(farm:getBalance()))
    if self.shopMoneyBox ~= nil then
        self.shopMoneyBox:invalidateLayout()
        if self.shopMoneyBoxBg ~= nil and self.shopMoneyBox.flowSizes ~= nil then
            self.shopMoneyBoxBg:setSize(self.shopMoneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
        end
    end
end

function BankMenuFrame:refreshList()
    self.selectedLoan = nil
    self.loansList = {}

    local bm = g_bankManager
    if bm ~= nil then
        local farmId = g_currentMission:getFarmId()
        local source = self.currentTab == BankMenuFrame.TAB.ACTIVE
            and bm:getFarmLoans(farmId)
            or bm:getClosedLoans(farmId)
        for _, loan in ipairs(source) do
            table.insert(self.loansList, loan)
        end
        table.sort(self.loansList, function(a, b)
            return (a.id or 0) > (b.id or 0)
        end)
    end

    if self.currentTab == BankMenuFrame.TAB.ACTIVE and self.listLoans ~= nil then
        self.listLoans:reloadData()
    elseif self.currentTab == BankMenuFrame.TAB.CLOSED and self.listPaidLoans ~= nil then
        self.listPaidLoans:reloadData()
    end

    self:updateEmptyState()
    self:refreshLoanSliders()
    self:updateSliderVisibility()
    self:updateButtonStates()
end

function BankMenuFrame:updateSubCategoryPages()
    if self.subCategoryPaging == nil then
        return
    end
    self.currentTab = self.subCategoryPaging:getState()
    self:refreshList()
    self:updateViewVisibility()
end

function BankMenuFrame:updateViewVisibility()
    local showModal = self.currentView == "loanForm"
    self:setVisibleOf("loanModalBackdrop", showModal)
    self:setVisibleOf("loanFormView", showModal)

    for index, page in pairs(self.subCategoryPages or {}) do
        page:setVisible(index == self.currentTab)
    end
    self:updateSliderVisibility()
end

function BankMenuFrame:updateEmptyState()
    local hasLoans = #self.loansList > 0
    if self.currentTab == BankMenuFrame.TAB.ACTIVE then
        self:setVisibleOf("loansListContainer", hasLoans)
        self:setVisibleOf("emptyListContainer", not hasLoans)
    else
        self:setVisibleOf("paidLoansListContainer", hasLoans)
        self:setVisibleOf("emptyPaidListContainer", not hasLoans)
    end
end

function BankMenuFrame:updateButtonStates()
    if self.btnPayoff == nil then
        return
    end
    local canPayoff = self.currentView == "dashboard"
        and self.currentTab == BankMenuFrame.TAB.ACTIVE
        and self.selectedLoan ~= nil
    self.btnPayoff.disabled = not canPayoff
    self:setDisabledOf("payoffSelectedButton", not canPayoff)
    self:setVisibleOf("payoffActionBar",
        self.currentView == "dashboard"
        and self.currentTab == BankMenuFrame.TAB.ACTIVE
        and #self.loansList > 0)
    if canPayoff then
        self:setTextOf("payoffSelectionText", string.format(
            g_i18n:getText("bank_payoff_selected"),
            BankManager.formatMoney(self.selectedLoan.remaining or 0)
        ))
    else
        self:setTextOf("payoffSelectionText", g_i18n:getText("bank_select_loan_to_payoff"))
    end
    if self.setMenuButtonInfoDirty ~= nil then
        self:setMenuButtonInfoDirty()
    end
end

function BankMenuFrame:refreshLoanSliders()
    if self.loansSlider ~= nil and self.listLoans ~= nil then
        self.loansSlider:onBindUpdate(self.listLoans)
    end
    if self.paidSlider ~= nil and self.listPaidLoans ~= nil then
        self.paidSlider:onBindUpdate(self.listPaidLoans)
    end
end

function BankMenuFrame:updateSliderVisibility()
    local showDashboard = self.currentView == "dashboard"
    self:setVisibleOf("loansSliderBox", showDashboard and self.currentTab == BankMenuFrame.TAB.ACTIVE)
    self:setVisibleOf("paidSliderBox", showDashboard and self.currentTab == BankMenuFrame.TAB.CLOSED)
end

function BankMenuFrame:updateScreenEdgeSliders()
    for _, sliderBox in pairs({self.loansSliderBox, self.paidSliderBox}) do
        if sliderBox ~= nil
            and sliderBox.absPosition ~= nil
            and sliderBox.absPosition[2] ~= nil
            and sliderBox.absSize ~= nil
            and sliderBox.absSize[1] ~= nil then
            sliderBox:updateAbsolutePosition()
            local x = 1 - sliderBox.absSize[1] - BankMenuFrame.SCREEN_EDGE_SLIDER_MARGIN_X
            local y = sliderBox.absPosition[2]
                + BankMenuFrame.NATIVE_DOCKED_SLIDER_OFFSET_Y * (g_pixelSizeScaledY or 0)
            sliderBox:setAbsolutePosition(x, y)
            for _, child in ipairs(sliderBox.elements or {}) do
                child:updateAbsolutePosition()
            end
        end
    end
end

function BankMenuFrame:getNumberOfSections()
    return 1
end

function BankMenuFrame:getNumberOfItemsInSection(list, section)
    return #self.loansList
end

function BankMenuFrame:getTitleForSectionHeader(list, section)
    return nil
end

function BankMenuFrame:getSectionHeaderHeight(list, section)
    return 0
end

function BankMenuFrame:populateCellForItemInSection(list, section, index, cell)
    local loan = self.loansList[index]
    if loan == nil then
        return
    end

    local closed = self.currentTab == BankMenuFrame.TAB.CLOSED
    local typeText = g_i18n:getText("bank_loan_type")
    local amountText = BankManager.formatMoney(loan.principal or loan.remaining or 0)
    local monthlyText = BankManager.formatMoney(loan.installment or 0)
    local rateText = string.format("%.2f%%", (loan.annualRate or 0) * 100)
    local durationText = closed
        and "-"
        or string.format(g_i18n:getText("bank_term_value"), loan.monthsLeft or 0)
    local remainingText = BankManager.formatMoney(
        closed and (loan.paidAmount or 0) or (loan.remaining or 0)
    )
    local statusText
    local statusColor
    if closed then
        statusText = loan.closedType == BankManager.CLOSED_LOAN_PAID_EARLY
            and g_i18n:getText("bank_closed_early")
            or g_i18n:getText("bank_closed_complete")
        statusColor = BankMenuFrame.COLOR_CLOSED
    elseif (loan.missed or 0) > 0 then
        statusText = g_i18n:getText("bank_status_overdue")
        statusColor = BankMenuFrame.COLOR_OVERDUE
    else
        statusText = g_i18n:getText("bank_status_active")
        statusColor = BankMenuFrame.COLOR_ACTIVE
    end

    local values = {
        cellType = typeText,
        cellAmount = amountText,
        cellMonthly = monthlyText,
        cellRate = rateText,
        cellDuration = durationText,
        cellRest = remainingText,
        cellStatus = statusText,
    }
    for name, value in pairs(values) do
        local element = cell:getDescendantByName(name)
        if element ~= nil then
            element:setText(value)
            if name == "cellStatus" then
                element:setTextColor(unpack(statusColor))
            end
        end
    end
end

function BankMenuFrame:onListSelectionChanged(list, section, index)
    if list == self.listLoans
        and self.currentTab == BankMenuFrame.TAB.ACTIVE
        and index > 0
        and index <= #self.loansList then
        self.selectedLoan = self.loansList[index]
    else
        self.selectedLoan = nil
    end
    self:updateButtonStates()
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

function BankMenuFrame:onClickTabActive()
    self.subCategoryPaging:setState(BankMenuFrame.TAB.ACTIVE, true)
    self:setMenuButtonInfoDirty()
end

function BankMenuFrame:onClickTabClosed()
    self.subCategoryPaging:setState(BankMenuFrame.TAB.CLOSED, true)
    self:setMenuButtonInfoDirty()
end

function BankMenuFrame:onClickNewLoan()
    self.currentView = "loanForm"
    if self.setMenuButtonInfoDirty ~= nil then
        self:setMenuButtonInfoDirty()
    end
    self:safeRefresh()
end

function BankMenuFrame:onClickBackToDashboard()
    self.currentView = "dashboard"
    if self.setMenuButtonInfoDirty ~= nil then
        self:setMenuButtonInfoDirty()
    end
    self:safeRefresh()
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
    if self.currentView ~= "loanForm"
        or (self.btnFormBorrow ~= nil and self.btnFormBorrow.disabled) then
        return
    end
    g_bankManager:request(BankManager.ACTION_BORROW, self.amount, BankManager.TERMS[self.termIndex])
end

function BankMenuFrame:onClickPayoffSelected()
    if self.selectedLoan ~= nil and self.currentTab == BankMenuFrame.TAB.ACTIVE then
        g_bankManager:request(BankManager.ACTION_PAYOFF, self.selectedLoan.id, 0)
    end
end
