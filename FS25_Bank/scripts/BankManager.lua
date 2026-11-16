-- Copyright © 2026 ian. All rights reserved.
-- BankManager.lua
-- Logica do banco: emprestimos, juros, parcelas, score e limite de credito.
-- O servidor e a autoridade; clientes so recebem copias via BankSyncEvent.

BankManager = {}
local BankManager_mt = Class(BankManager)

BankManager.ACTION_BORROW = 1
BankManager.ACTION_PAYOFF = 2
BankManager.CLOSED_LOAN_PAID_EARLY = 1
BankManager.CLOSED_LOAN_COMPLETED = 2

BankManager.MAX_LOANS_PER_FARM = 5
BankManager.MIN_AMOUNT = 5000
BankManager.MAX_AMOUNT = 500000
BankManager.AMOUNT_STEP = 5000
BankManager.TERMS = {6, 12, 24, 36}          -- prazos em meses (periodos do jogo)
BankManager.BASE_ANNUAL_RATE = 0.08          -- 8% a.a. base
BankManager.LATE_FEE = 0.02                  -- multa de 2% sobre o saldo devedor
BankManager.CREDIT_FACTOR = 0.5              -- limite = patrimonio * 50%
BankManager.MIN_CREDIT_LIMIT = 50000
BankManager.SCORE_MAX = 750
BankManager.DEFAULT_SCORE = 375          -- comeca no meio (Regular)
BankManager.SCORE_PAID = 15              -- parcela paga em dia
BankManager.SCORE_PAID_AFTER_LATE = 8    -- parcela paga depois de atraso
BankManager.SCORE_PAYOFF = 22            -- emprestimo quitado

-- Valor maximo por emprestimo conforme o score (atraso derruba o score e fecha o credito alto)
BankManager.SCORE_TIERS = {
    {min = 600, max = 500000},
    {min = 450, max = 250000},
    {min = 300, max = 100000},
    {min = 0,  max = 25000}
}
BankManager.OVERDUE_MAX_AMOUNT = 10000   -- com parcela em atraso, so emprestimo pequeno
BankManager.LATE_PENALTY_BASE = 75       -- pontos perdidos no 1o atraso
BankManager.LATE_PENALTY_STEP = 40        -- extra por atraso consecutivo
BankManager.LATE_PENALTY_MAX = 190

BankManager.NOTICE = {
    NONE = 0, TAKEN = 1, PAID = 2, MISSED = 3, PAID_OFF = 4,
    ERR_LIMIT = 5, ERR_FUNDS = 6, ERR_MAX = 7, ERR_INVALID = 8, ERR_SCORE = 9
}

BankManager.NOTICE_TEXT = {
    [1] = "bank_notice_taken",
    [2] = "bank_notice_paid",
    [3] = "bank_notice_missed",
    [4] = "bank_notice_paid_off",
    [5] = "bank_notice_err_limit",
    [6] = "bank_notice_err_funds",
    [7] = "bank_notice_err_max",
    [8] = "bank_notice_err_invalid",
    [9] = "bank_notice_err_score"
}

function BankManager.new()
    local self = setmetatable({}, BankManager_mt)
    self.loans = {}        -- [farmId] = { loan, loan, ... }
    self.closedLoans = {}  -- [farmId] = { loan, loan, ... }
    self.scores = {}       -- [farmId] = 0..750
    self.nextLoanId = 1
    return self
end

function BankManager:subscribe()
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
end

function BankManager:delete()
    g_messageCenter:unsubscribeAll(self)
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
function BankManager.formatMoney(value)
    return g_i18n:formatMoney(value, 0, true, true)
end

function BankManager.calcInstallment(principal, annualRate, months)
    local r = annualRate / 12
    if r <= 0 then
        return principal / months
    end
    return principal * r / (1 - (1 + r) ^ (-months))
end

function BankManager:getFarmLoans(farmId)
    return self.loans[farmId] or {}
end

function BankManager:getClosedLoans(farmId)
    return self.closedLoans[farmId] or {}
end

function BankManager:archiveLoan(farmId, loan, closedType, paidAmount)
    local closedLoans = self.closedLoans[farmId]
    if closedLoans == nil then
        closedLoans = {}
        self.closedLoans[farmId] = closedLoans
    end

    table.insert(closedLoans, {
        id = loan.id,
        principal = loan.principal,
        paidAmount = paidAmount,
        annualRate = loan.annualRate,
        installment = loan.installment,
        monthsLeft = loan.monthsLeft,
        missed = loan.missed,
        closedType = closedType
    })
end

function BankManager:getScore(farmId)
    return self.scores[farmId] or BankManager.DEFAULT_SCORE
end

function BankManager:adjustScore(farmId, delta)
    self.scores[farmId] = math.max(0, math.min(BankManager.SCORE_MAX, self:getScore(farmId) + delta))
end

-- Algum emprestimo com parcela em atraso (inadimplente)?
function BankManager:hasOverdue(farmId)
    for _, loan in ipairs(self:getFarmLoans(farmId)) do
        if loan.missed > 0 then
            return true
        end
    end
    return false
end

-- Maior valor que a fazenda pode pedir de uma vez (depende do score e de atrasos)
function BankManager:getMaxLoanAmount(farmId)
    local score = self:getScore(farmId)
    local cap = BankManager.SCORE_TIERS[#BankManager.SCORE_TIERS].max
    for _, tier in ipairs(BankManager.SCORE_TIERS) do
        if score >= tier.min then
            cap = tier.max
            break
        end
    end
    if self:hasOverdue(farmId) then
        cap = math.min(cap, BankManager.OVERDUE_MAX_AMOUNT)
    end
    return math.min(cap, BankManager.MAX_AMOUNT)
end

function BankManager:getTotalDebt(farmId)
    local total = 0
    for _, loan in ipairs(self:getFarmLoans(farmId)) do
        total = total + loan.remaining
    end
    return total
end

-- Taxa anual: base + premio por prazo curto +/- ajuste pelo score
function BankManager:getAnnualRate(farmId, months)
    local rate = BankManager.BASE_ANNUAL_RATE
    if months <= 6 then
        rate = rate + 0.04
    elseif months <= 12 then
        rate = rate + 0.02
    end
    rate = rate + (BankManager.DEFAULT_SCORE - self:getScore(farmId)) * 0.00008
    return math.max(rate, 0.02)
end

-- Patrimonio = saldo + veiculos + terras (VALIDE estes nomes de API no seu FS25)
function BankManager:getAssetsValue(farmId)
    local total = 0
    local farm = g_farmManager:getFarmById(farmId)
    if farm ~= nil then
        total = total + math.max(farm:getBalance(), 0)
    end

    local vehicles = nil
    if g_currentMission.vehicleSystem ~= nil then
        vehicles = g_currentMission.vehicleSystem.vehicles
    end
    for _, vehicle in ipairs(vehicles or {}) do
        if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId and vehicle.getSellPrice ~= nil then
            total = total + vehicle:getSellPrice()
        end
    end

    for _, farmland in pairs(g_farmlandManager:getFarmlands()) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            total = total + (farmland.price or 0)
        end
    end

    return total
end

function BankManager:getCreditLimit(farmId)
    return math.max(BankManager.MIN_CREDIT_LIMIT, self:getAssetsValue(farmId) * BankManager.CREDIT_FACTOR)
end

function BankManager:getAvailableCredit(farmId)
    return math.max(0, self:getCreditLimit(farmId) - self:getTotalDebt(farmId))
end

---------------------------------------------------------------------
-- Pedidos (cliente -> servidor)
---------------------------------------------------------------------
function BankManager:request(action, value, months)
    local farmId = g_currentMission:getFarmId()
    if g_currentMission:getIsServer() then
        self:handleRequest(farmId, action, value, months)
    else
        g_client:getServerConnection():sendEvent(BankRequestEvent.new(action, value, months))
    end
end

-- Roda SOMENTE no servidor
function BankManager:handleRequest(farmId, action, value, months)
    local notice = BankManager.NOTICE.ERR_INVALID
    if action == BankManager.ACTION_BORROW then
        notice = self:borrow(farmId, value, months)
    elseif action == BankManager.ACTION_PAYOFF then
        notice = self:payoff(farmId, value)
    end
    self:broadcast(farmId, notice)
end

function BankManager:borrow(farmId, amount, months)
    local N = BankManager.NOTICE

    local validTerm = false
    for _, t in ipairs(BankManager.TERMS) do
        if t == months then validTerm = true end
    end
    if not validTerm or amount < BankManager.MIN_AMOUNT or amount > BankManager.MAX_AMOUNT or amount % BankManager.AMOUNT_STEP ~= 0 then
        return N.ERR_INVALID
    end

    local loans = self.loans[farmId]
    if loans == nil then
        loans = {}
        self.loans[farmId] = loans
    end
    if #loans >= BankManager.MAX_LOANS_PER_FARM then
        return N.ERR_MAX
    end
    if amount > self:getMaxLoanAmount(farmId) then
        return N.ERR_SCORE
    end
    if amount > self:getAvailableCredit(farmId) then
        return N.ERR_LIMIT
    end

    local rate = self:getAnnualRate(farmId, months)
    local loan = {
        id = self.nextLoanId,
        principal = amount,
        remaining = amount,
        annualRate = rate,
        installment = BankManager.calcInstallment(amount, rate, months),
        monthsLeft = months,
        missed = 0
    }
    self.nextLoanId = self.nextLoanId + 1
    table.insert(loans, loan)
    self.scores[farmId] = self:getScore(farmId)

    g_currentMission:addMoney(amount, farmId, MoneyType.LOAN, true, true)
    return N.TAKEN
end

function BankManager:payoff(farmId, loanId)
    local N = BankManager.NOTICE
    local loans = self:getFarmLoans(farmId)
    local farm = g_farmManager:getFarmById(farmId)

    for i, loan in ipairs(loans) do
        if loan.id == loanId then
            if farm == nil or farm:getBalance() < loan.remaining then
                return N.ERR_FUNDS
            end
            g_currentMission:addMoney(-loan.remaining, farmId, MoneyType.LOAN, true, true)
            self:archiveLoan(farmId, loan, BankManager.CLOSED_LOAN_PAID_EARLY, loan.remaining)
            table.remove(loans, i)
            self:adjustScore(farmId, BankManager.SCORE_PAYOFF)
            return N.PAID_OFF
        end
    end
    return N.ERR_INVALID
end

---------------------------------------------------------------------
-- Cobranca mensal (inicio de cada periodo do jogo) - SOMENTE servidor
---------------------------------------------------------------------
function BankManager:onPeriodChanged()
    if not g_currentMission:getIsServer() then
        return
    end
    local N = BankManager.NOTICE

    for farmId, loans in pairs(self.loans) do
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and #loans > 0 then
            local notice = N.NONE

            for i = #loans, 1, -1 do
                local loan = loans[i]
                local interest = loan.remaining * (loan.annualRate / 12)
                local due = loan.installment
                if loan.monthsLeft <= 1 or loan.remaining + interest <= due then
                    due = loan.remaining + interest   -- ultima parcela zera o saldo
                end

                if farm:getBalance() >= due then
                    g_currentMission:addMoney(-due, farmId, MoneyType.LOAN, true, true)
                    loan.remaining = loan.remaining + interest - due
                    loan.monthsLeft = loan.monthsLeft - 1
                    self:adjustScore(farmId, loan.missed > 0 and BankManager.SCORE_PAID_AFTER_LATE or BankManager.SCORE_PAID)
                    loan.missed = 0 -- em dia de novo (missed = atrasos consecutivos)
                    if notice ~= N.MISSED then
                        notice = N.PAID
                    end
                    if loan.monthsLeft <= 0 or loan.remaining < 1 then
                        self:archiveLoan(farmId, loan, BankManager.CLOSED_LOAN_COMPLETED, due)
                        table.remove(loans, i)
                    end
                else
                    -- parcela atrasada: juros + multa entram no saldo e o score cai
                    local penalty = math.min(BankManager.LATE_PENALTY_MAX, BankManager.LATE_PENALTY_BASE + BankManager.LATE_PENALTY_STEP * loan.missed)
                    loan.missed = loan.missed + 1
                    loan.remaining = (loan.remaining + interest) * (1 + BankManager.LATE_FEE)
                    self:adjustScore(farmId, -penalty)
                    notice = N.MISSED
                end
            end

            self:broadcast(farmId, notice)
        end
    end
end

---------------------------------------------------------------------
-- Sincronizacao e avisos
---------------------------------------------------------------------
function BankManager:broadcast(farmId, notice)
    g_server:broadcastEvent(BankSyncEvent.new(
        farmId,
        self:getFarmLoans(farmId),
        self:getScore(farmId),
        notice,
        self:getClosedLoans(farmId)
    ), false)
    self:notify(farmId, notice)
    self:fireChanged()
end

-- Chamado nos clientes ao receber dados do servidor
function BankManager:setFarmData(farmId, loans, score, closedLoans)
    self.loans[farmId] = loans
    self.scores[farmId] = score
    self.closedLoans[farmId] = closedLoans or {}
    self:fireChanged()
end

function BankManager:fireChanged()
    if BankUI ~= nil then
        BankUI:refreshData()
    end
    if BankMenuFrame ~= nil and BankMenuFrame.INSTANCE ~= nil then
        BankMenuFrame.INSTANCE:onDataChanged()
    end
end

function BankManager:notify(farmId, notice)
    local N = BankManager.NOTICE
    if notice == nil or notice == N.NONE or g_dedicatedServer ~= nil then
        return
    end
    if g_currentMission:getFarmId() ~= farmId then
        return
    end

    local kind = FSBaseMission.INGAME_NOTIFICATION_INFO
    if notice == N.TAKEN or notice == N.PAID_OFF then
        kind = FSBaseMission.INGAME_NOTIFICATION_OK
    elseif notice >= N.MISSED and notice ~= N.PAID_OFF then
        kind = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    end
    g_currentMission:addIngameNotification(kind, g_i18n:getText(BankManager.NOTICE_TEXT[notice]))
end

---------------------------------------------------------------------
-- Save / Load (modernBank.xml na pasta do savegame)
---------------------------------------------------------------------
function BankManager.registerXMLPaths(schema)
    schema:register(XMLValueType.INT, "modernBank#nextLoanId", "Next loan id", 1)
    schema:register(XMLValueType.INT, "modernBank#scoreScale", "Score scale (100 = saves antigos)", 100)
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?)#farmId", "Farm id")
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?)#score", "Credit score", 50)
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).loan(?)#id", "Loan id")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).loan(?)#principal", "Principal")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).loan(?)#remaining", "Remaining")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).loan(?)#annualRate", "Annual rate")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).loan(?)#installment", "Installment")
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).loan(?)#monthsLeft", "Months left")
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).loan(?)#missed", "Missed payments", 0)
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).closedLoan(?)#id", "Closed loan id")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).closedLoan(?)#principal", "Closed loan principal")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).closedLoan(?)#paidAmount", "Amount paid to close loan")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).closedLoan(?)#annualRate", "Closed loan annual rate")
    schema:register(XMLValueType.FLOAT, "modernBank.farms.farm(?).closedLoan(?)#installment", "Closed loan installment")
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).closedLoan(?)#monthsLeft", "Months left when closed")
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).closedLoan(?)#missed", "Missed payments when closed", 0)
    schema:register(XMLValueType.INT, "modernBank.farms.farm(?).closedLoan(?)#closedType", "Loan closure type")
end

BankManager.xmlSchema = XMLSchema.new("modernBank")
BankManager.registerXMLPaths(BankManager.xmlSchema)

function BankManager:getSavePath()
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/modernBank.xml"
end

function BankManager:save()
    local path = self:getSavePath()
    if path == nil then
        return
    end
    local xmlFile = XMLFile.create("modernBankXML", path, "modernBank", BankManager.xmlSchema)
    if xmlFile == nil then
        return
    end

    xmlFile:setInt("modernBank#nextLoanId", self.nextLoanId)
    xmlFile:setInt("modernBank#scoreScale", BankManager.SCORE_MAX)

    local i = 0
    for farmId, score in pairs(self.scores) do
        local fKey = string.format("modernBank.farms.farm(%d)", i)
        xmlFile:setInt(fKey .. "#farmId", farmId)
        xmlFile:setInt(fKey .. "#score", score)

        for j, loan in ipairs(self:getFarmLoans(farmId)) do
            local lKey = string.format("%s.loan(%d)", fKey, j - 1)
            xmlFile:setInt(lKey .. "#id", loan.id)
            xmlFile:setFloat(lKey .. "#principal", loan.principal)
            xmlFile:setFloat(lKey .. "#remaining", loan.remaining)
            xmlFile:setFloat(lKey .. "#annualRate", loan.annualRate)
            xmlFile:setFloat(lKey .. "#installment", loan.installment)
            xmlFile:setInt(lKey .. "#monthsLeft", loan.monthsLeft)
            xmlFile:setInt(lKey .. "#missed", loan.missed)
        end

        for j, loan in ipairs(self:getClosedLoans(farmId)) do
            local lKey = string.format("%s.closedLoan(%d)", fKey, j - 1)
            xmlFile:setInt(lKey .. "#id", loan.id)
            xmlFile:setFloat(lKey .. "#principal", loan.principal)
            xmlFile:setFloat(lKey .. "#paidAmount", loan.paidAmount)
            xmlFile:setFloat(lKey .. "#annualRate", loan.annualRate)
            xmlFile:setFloat(lKey .. "#installment", loan.installment)
            xmlFile:setInt(lKey .. "#monthsLeft", loan.monthsLeft)
            xmlFile:setInt(lKey .. "#missed", loan.missed)
            xmlFile:setInt(lKey .. "#closedType", loan.closedType)
        end
        i = i + 1
    end

    xmlFile:save()
    xmlFile:delete()
end

function BankManager:load()
    local path = self:getSavePath()
    if path == nil then
        return
    end
    local xmlFile = XMLFile.loadIfExists("modernBankXML", path, BankManager.xmlSchema)
    if xmlFile == nil then
        return
    end

    self.nextLoanId = xmlFile:getInt("modernBank#nextLoanId", 1)
    local savedScale = xmlFile:getInt("modernBank#scoreScale", 100)

    xmlFile:iterate("modernBank.farms.farm", function(_, fKey)
        local farmId = xmlFile:getInt(fKey .. "#farmId")
        if farmId ~= nil then
            local savedScore = xmlFile:getInt(fKey .. "#score", BankManager.DEFAULT_SCORE)
            if savedScale ~= BankManager.SCORE_MAX then
                savedScore = math.floor(savedScore * BankManager.SCORE_MAX / savedScale + 0.5) -- migra saves antigos (0..100)
            end
            self.scores[farmId] = math.max(0, math.min(BankManager.SCORE_MAX, savedScore))
            self.loans[farmId] = {}
            self.closedLoans[farmId] = {}
            xmlFile:iterate(fKey .. ".loan", function(_, lKey)
                table.insert(self.loans[farmId], {
                    id = xmlFile:getInt(lKey .. "#id"),
                    principal = xmlFile:getFloat(lKey .. "#principal"),
                    remaining = xmlFile:getFloat(lKey .. "#remaining"),
                    annualRate = xmlFile:getFloat(lKey .. "#annualRate"),
                    installment = xmlFile:getFloat(lKey .. "#installment"),
                    monthsLeft = xmlFile:getInt(lKey .. "#monthsLeft"),
                    missed = xmlFile:getInt(lKey .. "#missed", 0)
                })
            end)
            xmlFile:iterate(fKey .. ".closedLoan", function(_, lKey)
                table.insert(self.closedLoans[farmId], {
                    id = xmlFile:getInt(lKey .. "#id"),
                    principal = xmlFile:getFloat(lKey .. "#principal"),
                    paidAmount = xmlFile:getFloat(lKey .. "#paidAmount"),
                    annualRate = xmlFile:getFloat(lKey .. "#annualRate"),
                    installment = xmlFile:getFloat(lKey .. "#installment"),
                    monthsLeft = xmlFile:getInt(lKey .. "#monthsLeft"),
                    missed = xmlFile:getInt(lKey .. "#missed", 0),
                    closedType = xmlFile:getInt(lKey .. "#closedType", BankManager.CLOSED_LOAN_COMPLETED)
                })
            end)
        end
    end)

    xmlFile:delete()
end
