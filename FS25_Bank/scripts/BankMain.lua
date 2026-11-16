-- BankMain.lua
-- Ponto de entrada do mod: carrega scripts, registra hooks e tecla de atalho.
-- Copyright © 2026 ian. All rights reserved.

local modDirectory = g_currentModDirectory
local modName = g_currentModName

BankMain = {}
BankMain.dir = modDirectory
BankMain.modName = modName

-- Aba "Banco" no menu ESC: DESLIGADA. Ela registra, mas causa "stack overflow" no GuiElement do jogo.
-- Mude para true apenas para testar de novo.
BankMain.ENABLE_MENU_TAB = false

source(modDirectory .. "scripts/BankManager.lua")
source(modDirectory .. "scripts/BankEvents.lua")
source(modDirectory .. "scripts/BankUI.lua")
source(modDirectory .. "scripts/BankMenuFrame.lua")

---------------------------------------------------------------------
-- Ciclo de vida do mapa
---------------------------------------------------------------------
function BankMain:loadMap()
    g_bankManager = BankManager.new()
    g_bankManager:subscribe()

    if g_currentMission:getIsServer() then
        g_bankManager:load()
    end
end

-- Registra a aba no menu ESC assim que o menu existir (uma unica vez, protegido por pcall)
function BankMain:update(dt)
    if not BankMain.ENABLE_MENU_TAB or self.tabDone or BankMenuFrame == nil then
        return
    end

    self.tabTries = (self.tabTries or 0) + 1
    local ok, registered = pcall(BankMenuFrame.register)
    if not ok then
        self.tabDone = true
        Logging.error("[BancoModerno] falha ao registrar a aba no menu ESC: %s", tostring(registered))
    elseif registered then
        self.tabDone = true
    elseif self.tabTries > 600 then
        self.tabDone = true -- menu nunca apareceu: desiste (o ALT+B continua funcionando)
    end
end

function BankMain:deleteMap()
    if g_bankManager ~= nil then
        g_bankManager:delete()
        g_bankManager = nil
    end
    BankUI:close()
    BankUI:deleteOverlay()
end

---------------------------------------------------------------------
-- Tecla de atalho (ALT+B, a pe)
---------------------------------------------------------------------
function BankMain.registerActionEvents()
    if InputAction.OPEN_BANK == nil then
        return
    end

    local _, eventId = g_inputBinding:registerActionEvent(InputAction.OPEN_BANK, BankMain, BankMain.onOpenBank, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_OPEN_BANK"))
    end
end

function BankMain:onOpenBank()
    if g_bankManager == nil or g_gui:getIsGuiVisible() then
        return
    end
    if g_currentMission:getFarmId() == FarmManager.SPECTATOR_FARM_ID then
        return
    end
    BankUI:toggle()
end

---------------------------------------------------------------------
-- Save / sincronizacao de quem entra no multiplayer
---------------------------------------------------------------------
function BankMain.onSaveSavegame()
    if g_bankManager ~= nil and g_currentMission:getIsServer() then
        g_bankManager:save()
    end
end

function BankMain.onSendInitialClientState(_, connection)
    if g_bankManager == nil then
        return
    end
    for farmId, score in pairs(g_bankManager.scores) do
        connection:sendEvent(BankSyncEvent.new(farmId, g_bankManager:getFarmLoans(farmId), score, BankManager.NOTICE.NONE))
    end
end

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, BankMain.registerActionEvents)
FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, BankMain.onSaveSavegame)
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, BankMain.onSendInitialClientState)

addModEventListener(BankMain)
