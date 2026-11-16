-- Copyright © 2026 ian. All rights reserved.

BankDiag = {}
BankDiag.installed = false

local MAX_DEPTH = 80

local function describe(element)
    if element == nil then
        return "nil"
    end
    return string.format("%s(id=%s)", tostring(element.name or "?"), tostring(element.id))
end

local function chain(element)
    local parts = {}
    local current = element
    for _ = 1, 8 do
        if current == nil then
            break
        end
        table.insert(parts, describe(current))
        current = current.parent
    end
    return table.concat(parts, " <- ")
end

local function guard(methodName)
    local original = GuiElement[methodName]
    if original == nil then
        return
    end

    local depth = 0
    local reported = false

    GuiElement[methodName] = function(self, ...)
        if depth >= MAX_DEPTH then
            if not reported then
                reported = true
                local okTb, tb = pcall(debug.traceback, "", 2)
                Logging.error("[BancoModerno] RECURSAO em GuiElement:%s no elemento %s | pais: %s", methodName, describe(self), chain(self))
                Logging.error("[BancoModerno] pilha (inicio): %s", string.sub(tostring(okTb and tb or "sem traceback"), 1, 2500))
            end
            return nil
        end

        depth = depth + 1
        local ok, r1, r2, r3 = pcall(original, self, ...)
        depth = depth - 1

        if not ok then
            error(r1, 0)
        end
        return r1, r2, r3
    end
end

function BankDiag.install()
    if BankDiag.installed or GuiElement == nil then
        return
    end
    BankDiag.installed = true
    guard("update")
    guard("mouseEvent")
    Logging.info("[BancoModerno] diagnostico de recursao instalado")
end
