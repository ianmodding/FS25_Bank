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
    self.amount = BankManager.MIN_AMOUNT
    self.termIndex = 2 -- 12 meses
    self.isShown = false
    self.menuButtonInfo = {}
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
    local months = BankManager.TERMS[self.termIndex]
    local rate = bm:getAnnualRate(farmId, months)
    local installment = BankManager.calcInstallment(self.amount, rate, months)
    local available = bm:getAvailableCredit(farmId)
    local loans = bm:getFarmLoans(farmId)

    self:setTextOf("balanceText", string.format(g_i18n:getText("bank_balance"), fmt(farm:getBalance())))
    self:setTextOf("limitText", string.format(g_i18n:getText("bank_limit"), fmt(available)))
    self:setTextOf("debtText", string.format(g_i18n:getText("bank_debt"), fmt(bm:getTotalDebt(farmId))))
    self:setTextOf("scoreText", string.format(g_i18n:getText("bank_score"), bm:getScore(farmId)))
    self:setTextOf("rateText", string.format(g_i18n:getText("bank_rate"), rate * 100))

    self:setTextOf("amountText", fmt(self.amount))
    self:setTextOf("termText", string.format(g_i18n:getText("bank_term_value"), months))
    self:setTextOf("installmentText", string.format(g_i18n:getText("bank_installment"), fmt(installment), fmt(installment * months)))

    local canBorrow = self.amount <= available and #loans < BankManager.MAX_LOANS_PER_FARM
    self:setDisabledOf("borrowButton", not canBorrow)
    self:setDisabledOf("amountDownBtn", self.amount <= BankManager.MIN_AMOUNT)
    self:setDisabledOf("amountUpBtn", self.amount >= BankManager.MAX_AMOUNT)
    self:setDisabledOf("termDownBtn", self.termIndex <= 1)
    self:setDisabledOf("termUpBtn", self.termIndex >= #BankManager.TERMS)

    for i = 1, BankMenuFrame.MAX_ROWS do
        local loan = loans[i]
        local textId = "loanText" .. i
        local buttonId = "payoffBtn" .. i

        if loan ~= nil then
            self:setTextOf(textId, string.format(g_i18n:getText("bank_row"), fmt(loan.remaining), fmt(loan.installment), loan.monthsLeft, loan.annualRate * 100))
            self:setVisibleOf(textId, true)
            self:setVisibleOf(buttonId, true)
        elseif i == 1 then
            self:setTextOf(textId, g_i18n:getText("bank_no_loans"))
            self:setVisibleOf(textId, true)
            self:setVisibleOf(buttonId, false)
        else
            self:setVisibleOf(textId, false)
            self:setVisibleOf(buttonId, false)
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
    self.amount = math.min(BankManager.MAX_AMOUNT, self.amount + BankManager.AMOUNT_STEP)
    self:safeRefresh()
end

function BankMenuFrame:onClickTermDown()
    self.termIndex = math.max(1, self.termIndex - 1)
    self:safeRefresh()
end

function BankMenuFrame:onClickTermUp()
    self.termIndex = math.min(#BankManager.TERMS, self.termIndex + 1)
    self:safeRefresh()
end

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
