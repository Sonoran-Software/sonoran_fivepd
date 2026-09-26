using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CitizenFX.Core;
using CitizenFX.Core.Native;
using FivePD.API;
using FivePD.API.Utils;

namespace SonoranPlugin
{
    public sealed class SonoranPlugin : Plugin
    {
        private const string Prefix = "SonoranCAD::fivepd:v2:";
        private static readonly Task Done = Task.FromResult(0);
        private readonly Dictionary<int, int> recentPeds = new Dictionary<int, int>();
        private readonly Dictionary<int, int> recentVehicles = new Dictionary<int, int>();
        private bool importing;
        private int lastCallSync = -60000;
        private Callout acceptedCallout;
        private int calloutCursor;

        public SonoranPlugin()
        {
            Events.OnCalloutAccepted += callout =>
            {
                acceptedCallout = callout;
                calloutCursor = 0;
                return SendCallout("accepted", callout);
            };
            Events.OnCalloutCompleted += callout =>
            {
                if (acceptedCallout?.Identifier == callout?.Identifier) acceptedCallout = null;
                return SendCallout("completed", callout);
            };
            Events.OnServiceCalled += service => SendService(service);
            Events.OnPedArrested += ped => Guard(() => ImportPed(ped, true));
            Tick += PollEncounters;
            API.RegisterCommand("fivepdcadped", new Action<int, List<object>, string>((_, args, raw) =>
                RunCommand(false)), false);
            API.RegisterCommand("fivepdcadvehicle", new Action<int, List<object>, string>((_, args, raw) =>
                RunCommand(true)), false);
            Debug.WriteLine("[sonoran_fivepd] Bridge 2.1.1 loaded (unofficial, unsupported).");
        }

        private static bool Ready()
        {
            return API.GetResourceState("sonoran_fivepd") == "started"
                && Utilities.IsPlayerOnDuty != null && Utilities.IsPlayerOnDuty();
        }

        private static async Task Guard(Func<Task> action)
        {
            try { if (Ready()) await action(); }
            catch (Exception ex) { Debug.WriteLine("[sonoran_fivepd] " + ex.Message); }
        }

        private static Task SendCallout(string action, Callout callout)
        {
            return Guard(() =>
            {
                if (callout == null) return Done;
                uint street = 0, crossing = 0;
                var pos = callout.Location;
                API.GetStreetNameAtCoord(pos.X, pos.Y, pos.Z, ref street, ref crossing);
                var address = API.GetStreetNameFromHashKey(street);
                if (crossing != 0) address += " / " + API.GetStreetNameFromHashKey(crossing);
                TriggerServerEvent(Prefix + "callout", action, new Dictionary<string, object>
                {
                    ["identifier"] = callout.Identifier ?? "",
                    ["caseId"] = callout.CaseID ?? "",
                    ["title"] = callout.ShortName ?? "FivePD callout",
                    ["description"] = callout.CalloutDescription ?? "",
                    ["responseCode"] = callout.ResponseCode,
                    ["address"] = address ?? "",
                    ["x"] = pos.X, ["y"] = pos.Y, ["z"] = pos.Z
                });
                return Done;
            });
        }

        private static Task SendService(Utilities.Services service)
        {
            return Guard(() =>
            {
                TriggerServerEvent(Prefix + "service", service.ToString());
                return Done;
            });
        }

        private static bool Eligible(Entity entity, int entityType, bool calloutEntity = false)
        {
            return entity != null && entity.Exists() && API.GetEntityType(entity.Handle) == entityType
                && API.NetworkGetEntityIsNetworked(entity.Handle)
                && (entityType != 1 || !API.IsPedAPlayer(entity.Handle))
                && (calloutEntity || entity.Position.DistanceTo(Game.Player.Character.Position) <= 80f);
        }

        private static bool Recent(Dictionary<int, int> cache, int id, bool force)
        {
            int now = API.GetGameTimer();
            if (!force && cache.TryGetValue(id, out int previous) && now >= previous && now - previous < 60000)
                return true;
            if (cache.Count > 256) cache.Clear();
            return false;
        }

        private async Task ImportPed(Ped ped, bool force = false, bool calloutEntity = false)
        {
            if (!Eligible(ped, 1, calloutEntity) || Utilities.GetPedData == null) return;
            int id = ped.NetworkId;
            if (Recent(recentPeds, id, force)) return;
            var request = Utilities.GetPedData(id);
            if (request == null || await Task.WhenAny(request, Delay(5000)) != request) return;
            PedData data = await request;
            if (data == null || !Eligible(ped, 1, calloutEntity) || ped.NetworkId != id || !Ready()) return;
            if (string.IsNullOrWhiteSpace(data.FirstName) || string.IsNullOrWhiteSpace(data.LastName)) return;
            var payload = new Dictionary<string, object>
            {
                ["FirstName"] = data.FirstName, ["LastName"] = data.LastName,
                ["DateOfBirth"] = data.DateOfBirth ?? "", ["Gender"] = data.Gender.ToString(),
                ["Age"] = data.Age, ["Address"] = data.Address ?? "", ["Warrant"] = data.Warrant ?? "",
                ["NetworkID"] = id
            };
            AddLicense(payload, "Driver", data.DriverLicense);
            AddLicense(payload, "Hunting", data.HuntingLicense);
            AddLicense(payload, "Fishing", data.FishingLicense);
            AddLicense(payload, "Weapon", data.WeaponLicense);
            TriggerServerEvent(Prefix + "ped", payload);
            recentPeds[id] = API.GetGameTimer();
        }

        private static void AddLicense(Dictionary<string, object> payload, string name, PedData.License license)
        {
            if (license == null) return;
            payload[name + "LicenseStatus"] = license.LicenseStatus.ToString();
            payload[name + "LicenseExpiration"] = license.ExpirationDate ?? "";
        }

        private async Task ImportVehicle(Vehicle vehicle, bool force = false, bool calloutEntity = false)
        {
            if (!Eligible(vehicle, 2, calloutEntity) || Utilities.GetVehicleData == null) return;
            int id = vehicle.NetworkId;
            if (Recent(recentVehicles, id, force)) return;
            var request = Utilities.GetVehicleData(id);
            if (request == null || await Task.WhenAny(request, Delay(5000)) != request) return;
            VehicleData data = await request;
            if (data == null || !Eligible(vehicle, 2, calloutEntity) || vehicle.NetworkId != id || !Ready()) return;
            if (string.IsNullOrWhiteSpace(data.LicensePlate)) return;
            TriggerServerEvent(Prefix + "vehicle", new Dictionary<string, object>
            {
                ["LicensePlate"] = data.LicensePlate.Trim(), ["Flag"] = data.Flag ?? "",
                ["OwnerFirstName"] = data.OwnerFirstName ?? "", ["OwnerLastName"] = data.OwnerLastName ?? "",
                ["Insurance"] = data.Insurance, ["Registration"] = data.Registration,
                ["Color"] = data.Color ?? "", ["Name"] = data.Name ?? "", ["NetworkID"] = id
            });
            recentVehicles[id] = API.GetGameTimer();
        }

        private async Task PollEncounters()
        {
            await Delay(2000);
            if (importing) return;
            importing = true;
            try
            {
                await Guard(async () =>
                {
                    var currentCallout = Utilities.GetCurrentCallout != null ? Utilities.GetCurrentCallout() : acceptedCallout;
                    acceptedCallout = currentCallout;
                    int now = API.GetGameTimer();
                    if (now < lastCallSync || now - lastCallSync >= 60000)
                    {
                        lastCallSync = now;
                        await SendCallout("accepted", currentCallout);
                    }
                    await ImportCalloutEntities(currentCallout);
                    if (Utilities.IsPlayerPerformingTrafficStop == null || !Utilities.IsPlayerPerformingTrafficStop()) return;
                    if (Utilities.GetVehicleFromTrafficStop != null) await ImportVehicle(Utilities.GetVehicleFromTrafficStop());
                    if (Utilities.GetDriverFromTrafficStop != null) await ImportPed(Utilities.GetDriverFromTrafficStop());
                    if (Utilities.GetPassengersFromTrafficStop != null)
                    {
                        var passengers = Utilities.GetPassengersFromTrafficStop();
                        if (passengers != null)
                            foreach (var ped in passengers) await ImportPed(ped);
                    }
                });
            }
            finally { importing = false; }
        }

        private async Task ImportCalloutEntities(Callout callout)
        {
            if (callout == null || API.GetConvarInt("sonoran_fivepd_autoCalloutRecords", 1) == 0) return;
            var entities = CalloutEntityCollector.Collect<Entity>(callout, typeof(Callout));
            int attempted = 0;
            int start = entities.Count == 0 ? 0 : calloutCursor % entities.Count;
            for (int i = 0; i < entities.Count && attempted < 4; i++)
            {
                if (!ReferenceEquals(acceptedCallout, callout) || !Ready()) return;
                int index = (start + i) % entities.Count;
                var entity = entities[index];
                calloutCursor = index + 1;
                if (entity is Ped ped && Eligible(ped, 1, true) && !Recent(recentPeds, ped.NetworkId, false))
                {
                    attempted++;
                    await Guard(() => ImportPed(ped, false, true));
                }
                else if (entity is Vehicle vehicle && Eligible(vehicle, 2, true) && !Recent(recentVehicles, vehicle.NetworkId, false))
                {
                    attempted++;
                    await Guard(() => ImportVehicle(vehicle, false, true));
                }
            }
        }

        private async void RunCommand(bool vehicle)
        {
            await Guard(async () =>
            {
                var position = Game.Player.Character.Position;
                if (vehicle)
                {
                    Vehicle nearest = null;
                    float distance = 15f;
                    foreach (var candidate in World.GetAllVehicles())
                    {
                        float next = candidate.Position.DistanceTo(position);
                        if (Eligible(candidate, 2) && next < distance) { nearest = candidate; distance = next; }
                    }
                    if (nearest != null) await ImportVehicle(nearest, true);
                    else Debug.WriteLine("[sonoran_fivepd] No networked vehicle within 15 metres.");
                }
                else
                {
                    Ped nearest = null;
                    float distance = 5f;
                    foreach (var candidate in World.GetAllPeds())
                    {
                        float next = candidate.Position.DistanceTo(position);
                        if (Eligible(candidate, 1) && next < distance) { nearest = candidate; distance = next; }
                    }
                    if (nearest != null) await ImportPed(nearest, true);
                    else Debug.WriteLine("[sonoran_fivepd] No networked NPC within 5 metres.");
                }
            });
        }
    }
}
