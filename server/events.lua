-- Event Handler

AddEventHandler('chatMessage', function(_, _, message)
    if string.sub(message, 1, 1) == '/' then
        CancelEvent()
        return
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if not RSGCore.Players[src] then return end
    local Player = RSGCore.Players[src]
    TriggerEvent('rsg-log:server:CreateLog', 'joinleave', 'Dropped', 'red', '**' .. GetPlayerName(src) .. '** (' .. Player.PlayerData.license .. ') left..' .. '\n **Reason:** ' .. reason)
    TriggerEvent('RSGCore:Server:PlayerDropped', Player)
    Player.Functions.Save()
    RSGCore.Player_Buckets[Player.PlayerData.license] = nil
    RSGCore.Players[src] = nil
end)

-- Player Connecting
local readyFunction = MySQL.ready
local databaseConnected, bansTableExists = readyFunction == nil, readyFunction == nil
if readyFunction ~= nil then
    MySQL.ready(function()
        databaseConnected = true
    
        local DatabaseInfo = RSGCore.Functions.GetDatabaseInfo()
        if not DatabaseInfo or not DatabaseInfo.exists then return end

        local result = MySQL.query.await('SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = "bans";', {DatabaseInfo.database})
        if result and result[1] then
            bansTableExists = true
        end
    end)
end

local function onPlayerConnecting(name, _, deferrals)
    local src = source
    deferrals.defer()

    if RSGCore.Config.Server.Closed and not IsPlayerAceAllowed(src, 'qbadmin.join') then
        return deferrals.done(RSGCore.Config.Server.ClosedReason)
    end

    if not databaseConnected then
        return deferrals.done(Lang:t('error.connecting_database_error'))
    end

    if RSGCore.Config.Server.Whitelist then
        Wait(0)
        deferrals.update(string.format(Lang:t('info.checking_whitelisted'), name))
        if not RSGCore.Functions.IsWhitelisted(src) then
            return deferrals.done(Lang:t('error.not_whitelisted'))
        end
    end

    Wait(0)
    deferrals.update(string.format('Hello %s. Your license is being checked', name))
    local license = RSGCore.Functions.GetIdentifier(src, 'license')

    if not license then
        return deferrals.done(Lang:t('error.no_valid_license'))
    elseif RSGCore.Config.Server.CheckDuplicateLicense and RSGCore.Functions.IsLicenseInUse(license) then
        return deferrals.done(Lang:t('error.duplicate_license'))
    end

    Wait(0)
    deferrals.update(string.format(Lang:t('info.checking_ban'), name))

    if not bansTableExists then
        return deferrals.done(Lang:t('error.ban_table_not_found'))
    end

    local success, isBanned, reason = pcall(RSGCore.Functions.IsPlayerBanned, src)
    if not success then return deferrals.done(Lang:t('error.connecting_database_error')) end
    if isBanned then return deferrals.done(reason) end

    Wait(0)
    deferrals.update(string.format(Lang:t('info.join_server'), name))
    deferrals.done()

    TriggerClientEvent('RSGCore:Client:SharedUpdate', src, RSGCore.Shared)
end

AddEventHandler('playerConnecting', onPlayerConnecting)

-- Open & Close Server (prevents players from joining)

RegisterNetEvent('RSGCore:Server:CloseServer', function(reason)
    local src = source
    if RSGCore.Functions.HasPermission(src, 'admin') then
        reason = reason or 'No reason specified'
        RSGCore.Config.Server.Closed = true
        RSGCore.Config.Server.ClosedReason = reason
        for k in pairs(RSGCore.Players) do
            if not RSGCore.Functions.HasPermission(k, RSGCore.Config.Server.WhitelistPermission) then
                RSGCore.Functions.Kick(k, reason, nil, nil)
            end
        end
    else
        RSGCore.Functions.Kick(src, Lang:t('error.no_permission'), nil, nil)
    end
end)

RegisterNetEvent('RSGCore:Server:OpenServer', function()
    local src = source
    if RSGCore.Functions.HasPermission(src, 'admin') then
        RSGCore.Config.Server.Closed = false
    else
        RSGCore.Functions.Kick(src, Lang:t('error.no_permission'), nil, nil)
    end
end)

-- Callback Events --

-- Client Callback
RegisterNetEvent('RSGCore:Server:TriggerClientCallback', function(name, ...)
    if RSGCore.ClientCallbacks[name] then
        RSGCore.ClientCallbacks[name](...)
        RSGCore.ClientCallbacks[name] = nil
    end
end)

-- Server Callback
RegisterNetEvent('RSGCore:Server:TriggerCallback', function(name, ...)
    local src = source
    RSGCore.Functions.TriggerCallback(name, src, function(...)
        TriggerClientEvent('RSGCore:Client:TriggerCallback', src, name, ...)
    end, ...)
end)

-- Player

RegisterNetEvent('RSGCore:UpdatePlayer', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local newHunger = Player.PlayerData.metadata['hunger'] - RSGCore.Config.Player.HungerRate
    local newThirst = Player.PlayerData.metadata['thirst'] - RSGCore.Config.Player.ThirstRate
    if newHunger <= 0 then
        newHunger = 0
    end
    if newThirst <= 0 then
        newThirst = 0
    end
    Player.Functions.SetMetaData('thirst', newThirst)
    Player.Functions.SetMetaData('hunger', newHunger)
    TriggerClientEvent('hud:client:UpdateNeeds', src, newHunger, newThirst)
    Player.Functions.Save()
end)

RegisterNetEvent('RSGCore:ToggleDuty', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.onduty then
        Player.Functions.SetJobDuty(false)
        TriggerClientEvent('RSGCore:Notify', src, Lang:t('info.off_duty'))
    else
        Player.Functions.SetJobDuty(true)
        TriggerClientEvent('RSGCore:Notify', src, Lang:t('info.on_duty'))
    end

    TriggerEvent('RSGCore:Server:SetDuty', src, Player.PlayerData.job.onduty)
    TriggerClientEvent('RSGCore:Client:SetDuty', src, Player.PlayerData.job.onduty)
end)

-- BaseEvents

-- Vehicles
RegisterServerEvent('baseevents:enteringVehicle', function(veh, seat, modelName)
    local src = source
    local data = {
        vehicle = veh,
        seat = seat,
        name = modelName,
        event = 'Entering'
    }
    TriggerClientEvent('RSGCore:Client:VehicleInfo', src, data)
end)

RegisterServerEvent('baseevents:enteredVehicle', function(veh, seat, modelName)
    local src = source
    local data = {
        vehicle = veh,
        seat = seat,
        name = modelName,
        event = 'Entered'
    }
    TriggerClientEvent('RSGCore:Client:VehicleInfo', src, data)
end)

RegisterServerEvent('baseevents:enteringAborted', function()
    local src = source
    TriggerClientEvent('RSGCore:Client:AbortVehicleEntering', src)
end)

RegisterServerEvent('baseevents:leftVehicle', function(veh, seat, modelName)
    local src = source
    local data = {
        vehicle = veh,
        seat = seat,
        name = modelName,
        event = 'Left'
    }
    TriggerClientEvent('RSGCore:Client:VehicleInfo', src, data)
end)

-- Items

-- This event is exploitable and should not be used. It has been deprecated, and will be removed soon.
RegisterNetEvent('RSGCore:Server:UseItem', function(item)
    print(string.format('%s triggered RSGCore:Server:UseItem by ID %s with the following data. This event is deprecated due to exploitation, and will be removed soon. Check rsg-inventory for the right use on this event.', GetInvokingResource(), source))
    RSGCore.Debug(item)
end)

-- This event is exploitable and should not be used. It has been deprecated, and will be removed soon. function(itemName, amount, slot)
RegisterNetEvent('RSGCore:Server:RemoveItem', function(itemName, amount)
    local src = source
    print(string.format('%s triggered RSGCore:Server:RemoveItem by ID %s for %s %s. This event is deprecated due to exploitation, and will be removed soon. Adjust your events accordingly to do this server side with player functions.', GetInvokingResource(), src, amount, itemName))
end)

-- This event is exploitable and should not be used. It has been deprecated, and will be removed soon. function(itemName, amount, slot, info)
RegisterNetEvent('RSGCore:Server:AddItem', function(itemName, amount)
    local src = source
    print(string.format('%s triggered RSGCore:Server:AddItem by ID %s for %s %s. This event is deprecated due to exploitation, and will be removed soon. Adjust your events accordingly to do this server side with player functions.', GetInvokingResource(), src, amount, itemName))
end)

-- Non-Chat Command Calling (ex: rsg-adminmenu)

RegisterNetEvent('RSGCore:CallCommand', function(command, args)
    local src = source
    if not RSGCore.Commands.List[command] then return end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local hasPerm = RSGCore.Functions.HasPermission(src, 'command.' .. RSGCore.Commands.List[command].name)
    if hasPerm then
        if RSGCore.Commands.List[command].argsrequired and #RSGCore.Commands.List[command].arguments ~= 0 and not args[#RSGCore.Commands.List[command].arguments] then
            TriggerClientEvent('RSGCore:Notify', src, Lang:t('error.missing_args2'), 'error')
        else
            RSGCore.Commands.List[command].callback(src, args)
        end
    else
        TriggerClientEvent('RSGCore:Notify', src, Lang:t('error.no_access'), 'error')
    end
end)

-- Use this for player vehicle spawning
-- Vehicle server-side spawning callback (netId)
-- use the netid on the client with the NetworkGetEntityFromNetworkId native
-- convert it to a vehicle via the NetToVeh native
RSGCore.Functions.CreateCallback('RSGCore:Server:SpawnVehicle', function(source, cb, model, coords, warp)
    local veh = RSGCore.Functions.SpawnVehicle(source, model, coords, warp)
    cb(NetworkGetNetworkIdFromEntity(veh))
end)

-- Use this for long distance vehicle spawning
-- vehicle server-side spawning callback (netId)
-- use the netid on the client with the NetworkGetEntityFromNetworkId native
-- convert it to a vehicle via the NetToVeh native
RSGCore.Functions.CreateCallback('RSGCore:Server:CreateVehicle', function(source, cb, model, coords, warp)
    local veh = RSGCore.Functions.CreateAutomobile(source, model, coords, warp)
    cb(NetworkGetNetworkIdFromEntity(veh))
end)

--RSGCore.Functions.CreateCallback('RSGCore:HasItem', function(source, cb, items, amount)
-- https://github.com/qbcore-framework/rsg-inventory/blob/e4ef156d93dd1727234d388c3f25110c350b3bcf/server/main.lua#L2066
--end)
