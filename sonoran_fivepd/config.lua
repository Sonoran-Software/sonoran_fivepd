local function sex(data)
    if data.Gender == 'Male' or data.Gender == 'M' then return 'M' end
    if data.Gender == 'Female' or data.Gender == 'F' then return 'F' end
    return ''
end

Config = {
    -- Uses the existing sonorancad API configuration. No API key belongs here.
    deleteAfterMinutes = 60, -- CAD deletes imported records and calls after this many minutes.
    acePermission = '', -- Optional: 'sonoran_fivepd.use'. Empty allows linked, on-duty CAD units.
    automaticCalloutRecords = true, -- Import the accepted callout's NPCs and vehicles as they spawn/stream in.
    callouts = true,
    completionNotes = true,
    serviceNotes = true,
    defaultPriority = 2, -- CAD: 1 = highest, 3 = lowest.
    responsePriorities = { [1] = 3, [2] = 2, [3] = 1, [99] = 1 },
    callCodes = {}, -- ['FivePD callout short name'] = 'CAD call code'
    postalResource = '', -- Optional resource exposing getPostalServer({x, y}).

    -- Default CAD record UIDs. Keys are CAD field mapping IDs;
    -- values are FivePD fields or functions. Copy custom IDs from the record editor.
    records = {
        civilian = {
            enabled = true, recordTypeId = 7,
            fields = {
                first = 'FirstName', last = 'LastName', dob = 'DateOfBirth',
                sex = sex, age = 'Age', residence = 'Address'
            }
        },
        vehicle = {
            enabled = true, recordTypeId = 5,
            fields = {
                plate = 'LicensePlate', first = 'OwnerFirstName', last = 'OwnerLastName',
                model = 'Name', color = 'Color',
                ['_wsakvwigt'] = function() return '1' end, -- DMV Status: approved
                status = function(data)
                    if data.Flag:lower() == 'stolen' then return 'STOLEN' end
                    return data.Registration and 'VALID' or 'EXPIRED'
                end,
                -- FivePD provides no registration expiration date, make, or year.
                -- The default CAD template has no insurance/flag field. Add your own if desired:
                -- ['YOUR_INSURANCE_FIELD'] = function(data) return data.Insurance and 'VALID' or 'EXPIRED' end,
                -- ['YOUR_FLAG_FIELD'] = 'Flag',
            }
        },
        license = {
            enabled = true, recordTypeId = 4,
            -- FISHING is not in CAD's default Type dropdown. Add it there before enabling it here.
            types = { Driver = 'DRIVER', Hunting = 'HUNTING', Weapon = 'WEAPON' },
            fields = {
                first = 'FirstName', last = 'LastName', dob = 'DateOfBirth',
                sex = sex, age = 'Age', residence = 'Address',
                ['252c425-0da9-421c-bd'] = function() return '1' end, -- DMV Status: approved
                ['878766a-f496-4853-a7'] = function(data) -- License Status
                    if data.LicenseStatus == 'Revoked' then return 'SUSPENDED' end
                    return data.LicenseStatus:upper()
                end,
                ['7eddab3-1daf-4a01-82'] = 'LicenseType',
                ['_54iz1scv7'] = 'LicenseExpiration',
            },
            -- Saving a default template in CAD removes hyphens from these older UIDs.
            -- Both forms are supplied; CAD ignores keys absent from its template.
            fieldAliases = {
                ['252c425-0da9-421c-bd'] = '252c4250da9421cbd',
                ['878766a-f496-4853-a7'] = '878766af4964853a7',
                ['7eddab3-1daf-4a01-82'] = '7eddab31daf4a0182',
            }
        },
        warrant = {
            enabled = true, recordTypeId = 2,
            fields = {
                first = 'FirstName', last = 'LastName', dob = 'DateOfBirth',
                sex = sex, age = 'Age', residence = 'Address',
                ['_avb6wvgyi'] = 'Warrant', -- Narrative
                ['_f9krngjbm'] = function() return '0' end, -- Status: open
            }
        }
    }
}
