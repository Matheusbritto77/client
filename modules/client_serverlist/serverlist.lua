ServerList = {}

function safeDecrypt(text)
    if not text or text == '' then
        return ''
    end
    local success, result = pcall(g_crypt.decrypt, text)
    return success and result or ''
end

-- private variables
local serverListWindow = nil
local serverTextList = nil
local removeWindow = nil
local servers = {}

local function copyServerEntry(entry)
    return {
        port = entry.port,
        protocol = entry.protocol,
        httpLogin = entry.httpLogin == true,
        useAuthenticator = entry.useAuthenticator == true,
        account = entry.account or '',
        password = entry.password or '',
        autologin = entry.autologin == true
    }
end

local function isConfiguredServer(host)
    return Servers_init and Servers_init[host] ~= nil
end

-- public functions
function ServerList.init()
    serverListWindow = g_ui.displayUI('serverlist')
    serverTextList = serverListWindow:getChildById('serverList')

    local addButton = serverListWindow:getChildById('buttonAdd')
    if addButton then
        addButton:setVisible(false)
    end

    servers = {}

    if Servers_init then
        local savedServers = g_settings.getNode('ServerList') or {}
        for host, value in pairs(Servers_init) do
            servers[host] = copyServerEntry(value)
            if savedServers[host] then
                servers[host].account = savedServers[host].account or servers[host].account
                servers[host].password = savedServers[host].password or servers[host].password
                servers[host].autologin = savedServers[host].autologin == true
            end
        end
    else
        servers = g_settings.getNode('ServerList') or {}
    end

    if servers then
        ServerList.load()
    end
end

function ServerList.terminate()
    ServerList.destroy()

    ServerList.save()

    ServerList = nil
    serverListWindow = nil
    serverTextList = nil
end

function ServerList.load()
    for host, server in pairs(servers) do
        ServerList.add(host, server.port, server.protocol, server.httpLogin, true)
        local widget = serverTextList:getChildById(host)
        if widget then
            local removeButton = widget:getChildById('remove')
            if removeButton then
                removeButton:setVisible(false)
                removeButton:setEnabled(false)
            end
        end
    end
end

function ServerList.select()
    local selected = serverTextList:getFocusedChild()
    if selected then
        local server = servers[selected:getId()]
        if server then
            EnterGame.setDefaultServer(selected:getId(), server.port, server.protocol)
            EnterGame.setAccountName(server.account)
            EnterGame.setPassword(server.password)
            EnterGame.setHttpLogin(server.httpLogin)
            ServerList.hide()
        end
    end
end

function ServerList.add(host, port, protocol, httpLogin, load)
    if not host or not port or not protocol then
        return false, 'Failed to load settings'
    elseif not load and servers[host] then
        return false, 'Server already exists'
    elseif not load and Servers_init and next(Servers_init) ~= nil and not isConfiguredServer(host) then
        return false, 'This client is locked to the configured server'
    elseif host == '' or port == '' then
        return false, 'Required fields are missing'
    elseif httpLogin == nil then
        httpLogin = false
    end
    local widget = g_ui.createWidget('ServerWidget', serverTextList)
    widget:setId(host)

    if not load then
        servers[host] = {
            port = port,
            protocol = protocol,
            account = '',
            password = '',
            httpLogin = httpLogin
        }
    end

    local details = widget:getChildById('details')
    details:setText(host .. ':' .. port)

    local proto = widget:getChildById('protocol')
    proto:setText(protocol)

    connect(widget, {
        onDoubleClick = function()
            ServerList.select()
            return true
        end
    })
    return true
end

function ServerList.remove(widget)
    local host = widget:getId()

    if isConfiguredServer(host) then
        displayInfoBox(tr('Locked server'), tr('This client is locked to the configured server.'))
        return
    end

    if removeWindow then
        return
    end

    local yesCallback = function()
        widget:destroy()
        servers[host] = nil
        removeWindow:destroy()
        removeWindow = nil
    end
    local noCallback = function()
        removeWindow:destroy()
        removeWindow = nil
    end

    removeWindow = displayGeneralBox(tr('Remove'), tr('Remove ' .. host .. '?'), {
        {
            text = tr('Yes'),
            callback = yesCallback
        },
        {
            text = tr('No'),
            callback = noCallback
        },
        anchor = AnchorHorizontalCenter
    }, yesCallback, noCallback)
end

function ServerList.destroy()
    if serverListWindow then
        serverTextList = nil
        serverListWindow:destroy()
        serverListWindow = nil
    end
end

function ServerList.show()
    if g_game.isOnline() then
        return
    end
    serverListWindow:show()
    serverListWindow:raise()
    serverListWindow:focus()
end

function ServerList.hide()
    serverListWindow:hide()
end

function ServerList.setServerAccount(host, account)
    servers[host] = servers[host] or {}
    servers[host].account = g_crypt.encrypt(account)
end

function ServerList.setServerPassword(host, password)
    servers[host] = servers[host] or {}
    servers[host].password = g_crypt.encrypt(password)
end

function ServerList.setServerAutologin(host, auto)
    servers[host] = servers[host] or {}
    servers[host].autologin = auto and true or false
end

function ServerList.getServerAutologin(host)
    local servers = g_settings.getNode('ServerList') or {}
    return servers[host] and servers[host].autologin or false
end

function ServerList.save()
    g_settings.setNode('ServerList', servers)
    g_configs.saveSettings()
end

function ServerList.getServers()
    return servers
end
