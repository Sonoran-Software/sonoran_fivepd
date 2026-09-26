local handlers, worker, requests, kvp = {}, nil, {}, {}
local now, milliseconds, serial = 100000, 0, 100
local players = { [11] = 'officer-one', [12] = 'officer-two', [13] = 'unlinked' }
local linked = { [11] = 'cad-one', [12] = 'cad-two' }
local units = { [11] = {}, [12] = {} }
local failNext, missingId, onRequest = false, false, nil
local function copy(value) return json.decode(json.encode(value)) end

os.time = function() return now end
function GetGameTimer() return milliseconds end
function GetPlayerName(src) return players[src] end
local aceAllowed = true
function IsPlayerAceAllowed() return aceAllowed end
function GetResourceState() return 'started' end
function SetConvarReplicated() end
function GetResourceKvpString(id) return kvp[id] end
function SetResourceKvp(id, value) kvp[id] = value end
function RegisterNetEvent(name, fn) handlers[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function CreateThread(fn) worker = coroutine.create(fn) end
function Wait(ms)
    milliseconds = milliseconds + ms
    coroutine.yield()
end

local cad = {}
local function dispatch(method, ...)
    requests[#requests + 1] = { method = method, args = copy({...}), at = milliseconds }
    if onRequest then local fn = onRequest; onRequest = nil; fn() end
    if failNext then failNext = false; return { success = false, reason = { status = 503 } } end
    serial = serial + 1
    return { success = true, data = missingId and {} or { id = serial } }
end
for _, method in ipairs({ 'createRecordV2', 'createDispatchCallV2', 'attachUnitsToDispatchCallV2', 'addDispatchNoteV2' }) do
    cad[method] = function(_, ...) return dispatch(method, ...) end
end

local httpRequests = {}
if cad_root then
    local factory = dofile(cad_root .. '/sonorancad/lua/sonoran/client.lua')
    local sdk = factory({ product = 0, apiKey = 'test-key', defaultServerId = 7, logLevel = 'OFF' }, {
        encode = function(value) return json.encode(value) end,
        decode = function(value) return json.decode(value) end,
        encodeURIComponent = function(value) return value end,
        request = function(options)
            assert(options.method == 'POST', 'Only expected v2 POSTs are used')
            assert(options.url:match('^https://api%.sonorancad%.com/v2/'), 'Non-v2 request rejected')
            httpRequests[#httpRequests + 1] = { url = options.url, data = json.decode(options.body) }
            return { status = 201, headers = { ['content-type'] = 'application/json' }, body = json.encode({ id = serial }) }
        end
    }).cad
    for method, _ in pairs(cad) do
        cad[method] = function(_, ...)
            local result = dispatch(method, ...)
            if not result.success or missingId then return result end
            return sdk[method](sdk, ...)
        end
    end
end

exports = { sonorancad = {
    getCommunityId = function() return 'community-test' end,
    getServerId = function() return 7 end,
    GetUnitByPlayerId = function(_, src) return units[src] end,
    getPlayerCommunityUserId = function(_, src) return linked[src] end,
    getCadClient = function() return cad end
} }

local function boot()
    handlers = {}
    dofile('sonoran_fivepd/config.lua')
    Config.records.license.enabled = false
    Config.records.warrant.enabled = false
    dofile('sonoran_fivepd/server.lua')
end
local function event(src, name, ...)
    source = src
    handlers['SonoranCAD::fivepd:v2:' .. name](...)
    source = nil
end
local function drain()
    for _ = 1, 180 do
        local ok, err = coroutine.resume(worker)
        assert(ok, err)
    end
end
local function count(method)
    local result = 0
    for _, request in ipairs(requests) do if request.method == method then result = result + 1 end end
    return result
end
local function last(method)
    for i = #requests, 1, -1 do if requests[i].method == method then return requests[i] end end
end
local function same(actual, expected, description)
    assert(actual == expected, description .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local call = { identifier = 'call-unique', caseId = '2026-1', title = 'Traffic incident',
    description = 'A reported incident', address = 'Alta Street', responseCode = 3, x = 1, y = 2, z = 3 }
local ped = { NetworkID = 32, FirstName = 'Jane', LastName = 'Doe', DateOfBirth = '02/03/1990',
    Age = 36, Gender = 'Female', Address = 'Alta Street', Warrant = 'None', DriverLicenseStatus = 'Valid' }
local vehicle = { NetworkID = 33, LicensePlate = ' TEST123 ', OwnerFirstName = 'Jane', OwnerLastName = 'Doe',
    Name = 'Sultan', Color = 'Black', Insurance = false, Registration = false, Flag = '' }

boot()
event(13, 'callout', 'accepted', call)
event(0, 'callout', 'accepted', call)
event(11, 'callout', 'accepted', { identifier = 'broken', x = 0/0, y = 2, z = 3 })
drain()
same(#requests, 0, 'Unlinked, local and malformed events are rejected')

event(11, 'callout', 'accepted', call)
event(11, 'callout', 'accepted', call)
event(12, 'callout', 'accepted', call)
drain()
same(count('createDispatchCallV2'), 1, 'Shared call created once')
same(count('attachUnitsToDispatchCallV2'), 1, 'Second officer attached')
local payload = last('createDispatchCallV2').args[1]
same(payload.communityUserIds[1], 'cad-one', 'Server resolves real event source')
same(payload.priority, 1, 'Code 3 maps to CAD priority 1')
same(payload.deleteAfterMinutes, 60, 'Call expiration')
same(payload.serverId, 7, 'Configured CAD server')

call.caseId = '2026-1-updated'
event(12, 'callout', 'accepted', call)
event(11, 'service', 'TowTruck')
event(11, 'callout', 'completed', call)
event(11, 'callout', 'completed', call)
drain()
same(count('createDispatchCallV2'), 1, 'Late CaseID does not create a second call')
same(count('addDispatchNoteV2'), 2, 'Service and completion notes, no duplicate completion')

event(11, 'ped', ped)
event(12, 'ped', ped)
event(11, 'vehicle', vehicle)
drain()
same(count('createRecordV2'), 2, 'One civilian and one vehicle across officers')
payload = last('createRecordV2').args[1]
same(payload.replaceValues.plate, 'TEST123', 'Plate normalized')
same(payload.replaceValues.status, 'EXPIRED', 'Invalid registration retained')
same(payload.deleteAfterMinutes, 60, 'Record expiration is sent to CAD')
same(payload.user, '00000000-0000-0000-0000-000000000000', 'NPC is not owned by reporting officer')

boot()
event(12, 'callout', 'accepted', call)
event(12, 'ped', ped)
event(12, 'vehicle', vehicle)
drain()
same(count('createRecordV2'), 2, 'Record deduplication survives restart')
same(count('createDispatchCallV2'), 1, 'Call deduplication survives restart')
same(count('attachUnitsToDispatchCallV2'), 1, 'Attachment deduplication survives restart')

Config.records.license.enabled = true
Config.records.license.fields.status = 'LicenseStatus'
Config.records.warrant.enabled = true
Config.records.warrant.fields.description = 'Warrant'
ped.Warrant = 'Failure to appear'
event(11, 'ped', ped)
drain()
same(count('createRecordV2'), 4, 'Optional license and warrant imported independently')
same(last('createRecordV2').args[1].replaceValues.description, 'Failure to appear', 'Warrant mapped')

now = now + 3601
event(11, 'vehicle', vehicle)
drain()
same(count('createRecordV2'), 5, 'Expired records can be imported again')
vehicle.LicensePlate = 'RETRY'
failNext = true
event(11, 'vehicle', vehicle)
drain()
event(11, 'vehicle', vehicle)
drain()
same(count('createRecordV2'), 7, 'Failed create is not marked successful')

local before = #requests
event(11, 'vehicle', { NetworkID = 1, LicensePlate = 'INVALID', Insurance = {}, Registration = true })
event(11, 'ped', { NetworkID = 1, FirstName = {}, LastName = 'bad' })
drain()
same(#requests, before, 'Malformed record fields rejected')

vehicle.LicensePlate = 'DISCONNECTED'
event(11, 'vehicle', vehicle)
source = 11
handlers.playerDropped()
source = nil
drain()
same(#requests, before, 'Queued writes from a disconnected session rejected')

call.identifier = 'concurrent-call'
onRequest = function() event(12, 'callout', 'accepted', call) end
event(11, 'callout', 'accepted', call)
drain()
same(count('createDispatchCallV2'), 2, 'In-flight acceptance serialized')
same(count('attachUnitsToDispatchCallV2'), 2, 'In-flight second officer attached')

call.identifier = 'missing-id'
missingId = true
event(11, 'callout', 'accepted', call)
drain()
missingId = false
event(11, 'callout', 'accepted', call)
drain()
same(count('createDispatchCallV2'), 3, 'Successful create without ID does not duplicate')

before = #requests
Config.records.vehicle.enabled = false
vehicle.LicensePlate = 'DISABLED'
event(11, 'vehicle', vehicle)
drain()
same(#requests, before, 'Disabled import does not write')

Config.records.vehicle.enabled = true
Config.acePermission = 'sonoran_fivepd.use'
aceAllowed = false
event(11, 'vehicle', vehicle)
drain()
same(#requests, before, 'ACE restrictions enforced')
aceAllowed = true
units[11] = nil
event(11, 'vehicle', vehicle)
drain()
same(#requests, before, 'No active CAD unit means no import')
units[11] = {}
Config.acePermission = ''

Config.records.vehicle.fields.insurance = function(data) return data.Insurance end
event(11, 'vehicle', vehicle)
drain()
same(last('createRecordV2').args[1].replaceValues.insurance, 'false', 'Mapping preserves false values')

before = #requests
vehicle.LicensePlate = 'RELINKED'
milliseconds = last('createRecordV2').at + 100
event(11, 'vehicle', vehicle)
local ok, err = coroutine.resume(worker)
assert(ok, err)
linked[11] = 'different-account'
drain()
same(#requests, before, 'Account change during pacing wait cancels write')
linked[11] = 'cad-one'

now = now + 60
before = #requests
for i = 1, 50 do
    vehicle.LicensePlate = 'BURST' .. i
    event(11, 'vehicle', vehicle)
end
drain()
same(#requests - before, 30, 'Per-player burst bounded')

local previous = {}
for _, request in ipairs(requests) do
    if request.method == 'createRecordV2' and previous[request.method] then
        assert(request.at - previous[request.method] >= 2500, 'Record writes must be paced')
    end
    previous[request.method] = request.at
end

-- Exercise the shipped defaults, including the original and CAD-sanitized license UIDs.
now = now + 3601
boot()
Config.records.license.enabled = true
Config.records.warrant.enabled = true
ped.FirstName = 'Default'
ped.DriverLicenseStatus, ped.DriverLicenseExpiration = 'Revoked', '09/26/2027'
ped.HuntingLicenseStatus, ped.WeaponLicenseStatus, ped.FishingLicenseStatus = 'Valid', 'Expired', 'Valid'
before = #requests
event(11, 'ped', ped)
drain()
same(#requests - before, 5, 'Defaults create civilian, three supported licenses and warrant; not fishing')
local licenses = 0
for i = before + 1, #requests do
    local record = requests[i].args[1]
    local values = record.replaceValues
    same(values.first, 'Default', 'Default identity UID')
    same(values.sex, 'F', 'Default sex dropdown value')
    if record.recordTypeId == 4 then
        licenses = licenses + 1
        same(values['252c425-0da9-421c-bd'], '1', 'Default license DMV approval')
        same(values['252c4250da9421cbd'], '1', 'Saved license DMV UID alias')
        same(values['878766af4964853a7'], values['878766a-f496-4853-a7'], 'License status UID alias')
        same(values['7eddab31daf4a0182'], values['7eddab3-1daf-4a01-82'], 'License type UID alias')
        if values['7eddab3-1daf-4a01-82'] == 'DRIVER' then
            same(values['878766a-f496-4853-a7'], 'SUSPENDED', 'Revoked mapped to default suspended option')
            same(values['_54iz1scv7'], '09/26/2027', 'License expiration UID')
        end
    elseif record.recordTypeId == 2 then
        same(values['_avb6wvgyi'], 'Failure to appear', 'Default warrant narrative UID')
        same(values['_f9krngjbm'], '0', 'Default warrant open status')
    else
        same(record.recordTypeId, 7, 'Default civilian record type')
    end
end
same(licenses, 3, 'Driver, hunting and weapon licenses')
before = #requests
event(12, 'ped', ped)
drain()
same(#requests, before, 'Entire automatic bundle deduplicated between officers')
vehicle.LicensePlate, vehicle.Flag = 'STOLEN1', 'Stolen'
event(11, 'vehicle', vehicle)
drain()
payload = last('createRecordV2').args[1]
same(payload.replaceValues.status, 'STOLEN', 'Default vehicle stolen option')
same(payload.replaceValues['_wsakvwigt'], '1', 'Default vehicle DMV approval UID')
same(payload.replaceValues.insurance, nil, 'No nonexistent insurance UID sent by default')

Config.records.license.types.Fishing = 'FISHING'
event(11, 'ped', ped)
drain()
same(last('createRecordV2').args[1].replaceValues['7eddab3-1daf-4a01-82'], 'FISHING', 'Custom fishing option can be enabled')
if cad_root then
    assert(#httpRequests > 0, 'SDK requests were exercised')
    for _, request in ipairs(httpRequests) do
        if request.url:match('/general/records$') then
            same(request.data.deleteAfterMinutes, 60, 'SDK preserves automatic expiry')
            same(request.data.user, '00000000-0000-0000-0000-000000000000', 'SDK preserves NPC ownership selector')
        end
        if request.url:match('/dispatch%-calls$') then
            same(type(request.data.notes[1]), 'table', 'Initial notes serialize as an array')
            same(request.data.notes[1].type, 'text', 'Initial note uses CAD callNote fields')
        end
    end
    print('PASS: real Sonoran.lua SDK transport: ' .. #httpRequests .. ' v2 requests')
end
print('PASS: authorization, validation, shared calls, notes, records, expiry, persistence, retries and concurrency')
