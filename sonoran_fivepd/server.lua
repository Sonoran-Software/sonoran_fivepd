local prefix = 'SonoranCAD::fivepd:v2:'
local queue, queued, sessions, limits, active = {}, {}, {}, {}, {}
local state, stateKey = { calls = {}, records = {} }, nil
local nextRequest = {}
local ttl = tonumber(Config.deleteAfterMinutes)
assert(ttl and ttl >= 1 and ttl <= 1440 and ttl % 1 == 0, 'deleteAfterMinutes must be 1-1440')

local function log(message)
    print('[sonoran_fivepd] ' .. message)
end

local function text(value, max)
    if type(value) ~= 'string' then return '' end
    return value:gsub('%c', ' '):sub(1, max or 128):match('^%s*(.-)%s*$')
end

local function number(value, max)
    return type(value) == 'number' and value == value and math.abs(value) <= max
end

local function key(...)
    return json.encode({...})
end

local function prune()
    for _, entries in pairs(state) do
        for id, entry in pairs(entries) do
            if type(entry) ~= 'table' or type(entry.expires) ~= 'number' or entry.expires <= os.time() then
                entries[id] = nil
            end
        end
    end
end

local function save()
    prune()
    SetResourceKvp(stateKey, json.encode(state))
end

local function initialize()
    local community = exports.sonorancad:getCommunityId()
    local server = exports.sonorancad:getServerId()
    if not community or not server then error('Configure sonorancad before starting this resource.') end
    local currentKey = 'fivepd:v2:' .. community .. ':' .. tostring(server)
    if stateKey ~= currentKey then
        stateKey = currentKey
        state = { calls = {}, records = {} }
        active = {}
        local saved = GetResourceKvpString(stateKey)
        local ok, decoded = pcall(json.decode, saved or '')
        if ok and type(decoded) == 'table' and type(decoded.calls) == 'table' and type(decoded.records) == 'table' then
            state = decoded
        end
    end
    prune()
    return server
end

local function authorized(src)
    if not GetPlayerName(src) then return nil end
    if Config.acePermission ~= '' and not IsPlayerAceAllowed(src, Config.acePermission) then return nil end
    local unit = exports.sonorancad:GetUnitByPlayerId(src)
    if type(unit) ~= 'table' then return nil end
    local linked = exports.sonorancad:getPlayerCommunityUserId(src)
    if type(linked) ~= 'string' or linked == '' then return nil end
    return linked
end

-- One worker serializes writes, including while the SDK yields for HTTP responses.
local function enqueue(src, id, action)
    if type(src) ~= 'number' or src <= 0 or not GetPlayerName(src) then return end
    local bucket = limits[src]
    if not bucket or bucket.reset <= os.time() then
        bucket = { count = 0, reset = os.time() + 60 }
        limits[src] = bucket
    end
    if bucket.count >= 30 or #queue >= 128 then return end
    local queueKey = key(src, sessions[src] or 0, id)
    if queued[queueKey] then return end
    bucket.count = bucket.count + 1
    queued[queueKey] = true
    queue[#queue + 1] = { src = src, session = sessions[src] or 0, key = queueKey,
        created = os.time(), action = action }
end

local function request(job, method, ...)
    local intervals = { createRecordV2 = 2500, createDispatchCallV2 = 3500,
        attachUnitsToDispatchCallV2 = 6500, addDispatchNoteV2 = 1100 }
    local remaining = (nextRequest[method] or 0) - GetGameTimer()
    if remaining > 0 then Wait(remaining) end
    if authorized(job.src) ~= job.linked or (sessions[job.src] or 0) ~= job.session then return nil end
    nextRequest[method] = GetGameTimer() + intervals[method]
    local cad = exports.sonorancad:getCadClient()
    local response = cad[method](cad, ...)
    if type(response) ~= 'table' or response.success ~= true then
        local reason = type(response) == 'table' and response.reason or nil
        local status = type(reason) == 'table' and reason.status or 'unknown'
        log(method .. ' failed (HTTP ' .. tostring(status) .. '). Check CAD API access and record mappings.')
        return nil
    end
    return response
end

local function responseId(response)
    local data = response and response.data
    if type(data) == 'table' then data = data.id or data.callId or data.recordId or data.dispatchCallId end
    local id = tonumber(data)
    if id and id > 0 and id % 1 == 0 then return id end
end

local function note(job, server, call, message)
    if not call.id or call.expires <= os.time() then return end
    return request(job, 'addDispatchNoteV2', call.id,
        { serverId = server, note = message, noteType = 'text', label = 'FivePD' })
end

local function cleanCall(data)
    if type(data) ~= 'table' then return nil end
    if not number(data.x, 100000) or not number(data.y, 100000) or not number(data.z, 100000) then return nil end
    local identifier, caseId = text(data.identifier), text(data.caseId)
    if identifier == '' then return nil end
    local title = text(data.title, 160)
    return { identifier = identifier, caseId = caseId, title = title ~= '' and title or 'FivePD callout',
        description = text(data.description, 2000), address = text(data.address, 200),
        responseCode = number(data.responseCode, 999) and data.responseCode or -1,
        x = data.x, y = data.y, z = data.z }
end

RegisterNetEvent(prefix .. 'callout', function(action, data)
    local src = source
    if not Config.callouts or (action ~= 'accepted' and action ~= 'completed') then return end
    data = cleanCall(data)
    if not data then return end
    -- Identifier is generated per callout instance by FivePD; CaseID can arrive later.
    local callKey = data.identifier
    enqueue(src, key(action, callKey), function(job, server, linked)
        local call = state.calls[callKey]
        if action == 'completed' then
            if not call or not call.members[linked] then return end
            if Config.completionNotes and not call.completed[linked] then
                if note(job, server, call, 'Unit ' .. linked .. ' completed FivePD callout ' .. data.title .. '.') then
                    call.completed[linked] = true
                    save()
                end
            end
            if active[src] == callKey then active[src] = nil end
            return
        end
        if call and call.completed[linked] then return end
        if not call then
            local postal = ''
            if Config.postalResource ~= '' and GetResourceState(Config.postalResource) == 'started' then
                local ok, result = pcall(function()
                    return exports[Config.postalResource]:getPostalServer({data.x, data.y})
                end)
                if ok and type(result) == 'table' then postal = tostring(result.code or '') end
            end
            local priority = Config.responsePriorities[data.responseCode] or Config.defaultPriority
            local response = request(job, 'createDispatchCallV2', {
                serverId = server, origin = 1, status = 1, priority = priority,
                title = data.title, description = data.description, address = data.address,
                postal = postal, block = '', code = Config.callCodes[data.title] or '',
                notes = {{ time = os.date('!%Y-%m-%dT%H:%M:%SZ'), label = 'FivePD', type = 'text',
                    content = 'FivePD case: ' .. (data.caseId ~= '' and data.caseId or data.identifier) }},
                communityUserIds = { linked }, deleteAfterMinutes = ttl,
                metaData = { x = tostring(data.x), y = tostring(data.y), z = tostring(data.z),
                    fivepdCaseId = data.caseId, fivepdIdentifier = data.identifier }
            })
            if not response then return end
            call = { id = responseId(response), expires = os.time() + ttl * 60,
                members = { [linked] = true }, completed = {} }
            state.calls[callKey] = call
            save()
            if not call.id then log('CAD created a call without returning its ID; further call updates are skipped.') end
        elseif not call.members[linked] and call.id then
            if not request(job, 'attachUnitsToDispatchCallV2', call.id,
                { serverId = server, communityUserIds = { linked } }) then return end
            call.members[linked] = true
            save()
        end
        if (sessions[src] or 0) == job.session then active[src] = callKey end
    end)
end)

local services = { Ambulance = true, AirAmbulance = true, FireDept = true, Coroner = true,
    AnimalControl = true, TowTruck = true, Mechanic = true, PrisonTransport = true }
RegisterNetEvent(prefix .. 'service', function(service)
    local src = source
    if not Config.serviceNotes or not services[service] then return end
    enqueue(src, key('service', service), function(job, server, linked)
        local call = state.calls[active[src]]
        if call and call.members[linked] then note(job, server, call, 'Unit ' .. linked .. ' requested ' .. service .. '.') end
    end)
end)

local function cleanRecord(data, kind)
    if type(data) ~= 'table' or not number(data.NetworkID, 65535)
        or data.NetworkID <= 0 or data.NetworkID % 1 ~= 0 then return nil end
    local fields = kind == 'ped'
        and { 'FirstName', 'LastName', 'DateOfBirth', 'Gender', 'Address', 'Warrant',
            'DriverLicenseStatus', 'DriverLicenseExpiration', 'HuntingLicenseStatus', 'HuntingLicenseExpiration',
            'FishingLicenseStatus', 'FishingLicenseExpiration', 'WeaponLicenseStatus', 'WeaponLicenseExpiration' }
        or { 'LicensePlate', 'Flag', 'OwnerFirstName', 'OwnerLastName', 'Color', 'Name' }
    local result = {}
    for _, field in ipairs(fields) do result[field] = text(data[field], 256) end
    if kind == 'ped' then
        if result.FirstName == '' or result.LastName == '' or result.DateOfBirth == '' then return nil end
        result.Age = number(data.Age, 150) and math.max(0, math.floor(data.Age)) or ''
    else
        if result.LicensePlate == '' or type(data.Insurance) ~= 'boolean' or type(data.Registration) ~= 'boolean' then return nil end
        result.LicensePlate = result.LicensePlate:upper()
        result.Insurance, result.Registration = data.Insurance, data.Registration
    end
    return result
end

local function createRecord(job, kind, identity, data)
    local config = Config.records[kind]
    if not config or not config.enabled then return end
    local recordKey = key(kind, config.recordTypeId, identity)
    if state.records[recordKey] then return end
    local values = {}
    for field, mapping in pairs(config.fields) do
        local value
        if type(mapping) == 'function' then value = mapping(data) else value = data[mapping] end
        if value ~= nil then values[field] = tostring(value) end
    end
    local response = request(job, 'createRecordV2', {
        -- v2 explicitly accepts the unowned NPC UUID through its user selector.
        user = '00000000-0000-0000-0000-000000000000', useDictionary = true,
        recordTypeId = config.recordTypeId, replaceValues = values, deleteAfterMinutes = ttl
    })
    if response then
        state.records[recordKey] = { expires = os.time() + ttl * 60 }
        save()
    end
end

RegisterNetEvent(prefix .. 'ped', function(data)
    local src = source
    data = cleanRecord(data, 'ped')
    if not data then return end
    local identity = key(data.FirstName, data.LastName, data.DateOfBirth, data.Address)
    enqueue(src, key('ped', identity), function(job)
        createRecord(job, 'civilian', identity, data)
        for _, license in ipairs({ 'Driver', 'Hunting', 'Fishing', 'Weapon' }) do
            local status = data[license .. 'LicenseStatus']
            if status == 'Valid' or status == 'Expired' or status == 'Revoked' or status == 'Suspended' then
                data.LicenseType, data.LicenseStatus = license:upper(), status
                data.LicenseExpiration = data[license .. 'LicenseExpiration']
                createRecord(job, 'license', key(identity, license), data)
            end
        end
        local warrant = data.Warrant:lower()
        if warrant ~= '' and warrant ~= 'none' and warrant ~= 'no warrant' and warrant ~= 'n/a' then
            createRecord(job, 'warrant', identity, data)
        end
    end)
end)

RegisterNetEvent(prefix .. 'vehicle', function(data)
    local src = source
    data = cleanRecord(data, 'vehicle')
    if not data then return end
    enqueue(src, key('vehicle', data.LicensePlate), function(job)
        createRecord(job, 'vehicle', data.LicensePlate, data)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src] = (sessions[src] or 0) + 1
    active[src], limits[src] = nil, nil
end)

CreateThread(function()
    log('2.0.0 started. Unofficial, unsupported and not maintained. CAD v2 only.')
    while true do
        local job = table.remove(queue, 1)
        if job then
            local ok, err = pcall(function()
                if os.time() - job.created > 180 or (sessions[job.src] or 0) ~= job.session then return end
                if GetResourceState('sonorancad') ~= 'started' then return end
                local linked = authorized(job.src)
                if not linked then return end
                job.linked = linked
                local server = initialize()
                job.action(job, server, linked)
            end)
            queued[job.key] = nil
            if not ok then log('Bridge error: ' .. tostring(err)) end
        end
        Wait(100)
    end
end)
