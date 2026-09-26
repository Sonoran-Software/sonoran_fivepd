Config = {
    -- Uses the existing sonorancad API configuration. No API key belongs here.
    deleteAfterMinutes = 60, -- CAD deletes imported records and calls after this many minutes.
    acePermission = '', -- Optional: e.g. 'sonoran_fivepd.use'. Empty allows linked, on-duty CAD units.
    callouts = true,
    completionNotes = true,
    serviceNotes = true,
    defaultPriority = 2, -- CAD: 1 = highest, 3 = lowest.
    responsePriorities = { [1] = 3, [2] = 2, [3] = 1, [99] = 1 },
    callCodes = {}, -- ['FivePD callout short name'] = 'CAD call code'
    postalResource = '', -- Optional resource exposing getPostalServer({x, y}).

    -- Keys are CAD field mapping IDs; values are FivePD data fields or functions.
    -- Match these to Admin > Custom Records before enabling an optional record.
    records = {
        civilian = {
            enabled = true, recordTypeId = 7,
            fields = { first = 'FirstName', last = 'LastName', dob = 'DateOfBirth',
                sex = 'Gender', age = 'Age', residence = 'Address' }
        },
        vehicle = {
            enabled = true, recordTypeId = 5,
            fields = { plate = 'LicensePlate', first = 'OwnerFirstName', last = 'OwnerLastName',
                model = 'Name', color = 'Color', status = function(data)
                    if data.Flag:lower() == 'stolen' then return 'STOLEN' end
                    return data.Registration and 'VALID' or 'EXPIRED'
                end,
                -- Add your insurance/flag fields here, for example:
                -- ['YOUR_INSURANCE_FIELD'] = function(data) return data.Insurance and 'VALID' or 'EXPIRED' end,
                -- ['YOUR_FLAG_FIELD'] = 'Flag'
            }
        },
        license = {
            enabled = false, recordTypeId = 4,
            fields = { first = 'FirstName', last = 'LastName', dob = 'DateOfBirth' }
            -- Add mappings for LicenseType, LicenseStatus and LicenseExpiration.
            -- Types: DRIVER, HUNTING, FISHING, WEAPON. Statuses: Valid, Expired, Revoked, Suspended.
        },
        warrant = {
            enabled = false, recordTypeId = 2,
            fields = { first = 'FirstName', last = 'LastName', dob = 'DateOfBirth' }
            -- Add your warrant description field mapped to 'Warrant'.
        }
    }
}
