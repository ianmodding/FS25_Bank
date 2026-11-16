-- BankEvents.lua
-- Copyright © 2026 ian. All rights reserved.

---------------------------------------------------------------------
-- Pedido do cliente
---------------------------------------------------------------------
BankRequestEvent = {}
local BankRequestEvent_mt = Class(BankRequestEvent, Event)
InitEventClass(BankRequestEvent, "BankRequestEvent")

function BankRequestEvent.emptyNew()
    return Event.new(BankRequestEvent_mt)
end

function BankRequestEvent.new(action, value, months)
    local self = BankRequestEvent.emptyNew()
    self.action = action
    self.value = value
    self.months = months or 0
    return self
end

function BankRequestEvent:readStream(streamId, connection)
    self.action = streamReadUIntN(streamId, 3)
    self.value = streamReadInt32(streamId)
    self.months = streamReadUInt8(streamId)
    self:run(connection)
end

function BankRequestEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.action, 3)
    streamWriteInt32(streamId, self.value)
    streamWriteUInt8(streamId, self.months)
end

function BankRequestEvent:run(connection)
    if connection:getIsServer() then
        return -- so o servidor processa pedidos
    end
    -- descobre a fazenda pelo jogador da conexao (nunca confie no cliente)
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = g_farmManager:getFarmByUserId(userId)
    if farm == nil or farm.farmId == FarmManager.SPECTATOR_FARM_ID then
        return
    end
    g_bankManager:handleRequest(farm.farmId, self.action, self.value, self.months)
end

---------------------------------------------------------------------
-- Sincronizacao do servidor
---------------------------------------------------------------------
BankSyncEvent = {}
local BankSyncEvent_mt = Class(BankSyncEvent, Event)
InitEventClass(BankSyncEvent, "BankSyncEvent")

function BankSyncEvent.emptyNew()
    return Event.new(BankSyncEvent_mt)
end

function BankSyncEvent.new(farmId, loans, score, notice, closedLoans, investments)
    local self = BankSyncEvent.emptyNew()
    self.farmId = farmId
    self.loans = loans
    self.score = score
    self.notice = notice or 0
    self.closedLoans = closedLoans or {}
    self.investments = investments or {}
    return self
end

function BankSyncEvent:readStream(streamId, connection)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.score = streamReadUInt16(streamId)
    self.notice = streamReadUInt8(streamId)

    self.loans = {}
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        table.insert(self.loans, {
            id = streamReadInt32(streamId),
            principal = streamReadFloat32(streamId),
            remaining = streamReadFloat32(streamId),
            annualRate = streamReadFloat32(streamId),
            installment = streamReadFloat32(streamId),
            monthsLeft = streamReadUInt8(streamId),
            missed = streamReadUInt8(streamId)
        })
    end

    self.closedLoans = {}
    local closedCount = streamReadUInt16(streamId)
    for _ = 1, closedCount do
        table.insert(self.closedLoans, {
            id = streamReadInt32(streamId),
            principal = streamReadFloat32(streamId),
            paidAmount = streamReadFloat32(streamId),
            annualRate = streamReadFloat32(streamId),
            installment = streamReadFloat32(streamId),
            monthsLeft = streamReadUInt8(streamId),
            missed = streamReadUInt8(streamId),
            closedType = streamReadUInt8(streamId)
        })
    end

    self.investments = {}
    local investmentCount = streamReadUInt8(streamId)
    for _ = 1, investmentCount do
        table.insert(self.investments, {
            id = streamReadInt32(streamId),
            principal = streamReadFloat32(streamId),
            maturityValue = streamReadFloat32(streamId),
            annualRate = streamReadFloat32(streamId),
            termMonths = streamReadUInt8(streamId),
            monthsLeft = streamReadUInt8(streamId)
        })
    end
    self:run(connection)
end

function BankSyncEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteUInt16(streamId, self.score)
    streamWriteUInt8(streamId, self.notice)
    streamWriteUInt8(streamId, #self.loans)
    for _, loan in ipairs(self.loans) do
        streamWriteInt32(streamId, loan.id)
        streamWriteFloat32(streamId, loan.principal)
        streamWriteFloat32(streamId, loan.remaining)
        streamWriteFloat32(streamId, loan.annualRate)
        streamWriteFloat32(streamId, loan.installment)
        streamWriteUInt8(streamId, math.min(loan.monthsLeft, 255))
        streamWriteUInt8(streamId, math.min(loan.missed, 255))
    end

    streamWriteUInt16(streamId, #self.closedLoans)
    for _, loan in ipairs(self.closedLoans) do
        streamWriteInt32(streamId, loan.id)
        streamWriteFloat32(streamId, loan.principal)
        streamWriteFloat32(streamId, loan.paidAmount)
        streamWriteFloat32(streamId, loan.annualRate)
        streamWriteFloat32(streamId, loan.installment)
        streamWriteUInt8(streamId, math.min(loan.monthsLeft, 255))
        streamWriteUInt8(streamId, math.min(loan.missed, 255))
        streamWriteUInt8(streamId, loan.closedType)
    end

    streamWriteUInt8(streamId, #self.investments)
    for _, investment in ipairs(self.investments) do
        streamWriteInt32(streamId, investment.id)
        streamWriteFloat32(streamId, investment.principal)
        streamWriteFloat32(streamId, investment.maturityValue)
        streamWriteFloat32(streamId, investment.annualRate)
        streamWriteUInt8(streamId, math.min(investment.termMonths, 255))
        streamWriteUInt8(streamId, math.min(investment.monthsLeft, 255))
    end
end

function BankSyncEvent:run(connection)
    if g_bankManager == nil then
        return
    end
    g_bankManager:setFarmData(self.farmId, self.loans, self.score, self.closedLoans, self.investments)
    g_bankManager:notify(self.farmId, self.notice)
end
