using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CitizenFX.Core;
using CitizenFX.Core.Native;
using FivePD.API;
using FivePD.API.Utils;

namespace SonoranPlugin
{
    public class SonoranPlugin : Plugin
    {
        internal SonoranPlugin()
        {
            Events.OnCalloutReceived += this.OnCalloutReceived;
            Events.OnCalloutAccepted += this.OnCalloutAccepted;
            Events.OnCalloutCompleted += this.OnCalloutCompleted;
            Events.OnDutyStatusChange += this.OnDutyStatusChange;
            Events.OnServiceCalled += this.OnServiceCalled;
            Events.OnRankChanged += this.OnRankChanged;
            Events.OnPedArrested += this.OnPedArrested;
        }
        private bool isDebugging = false;
        
        private void DebugLog(string message)
        {
            if (!isDebugging) return;
            Debug.WriteLine("SonoranCAD (FivePD Plugin): " + message);
        }

        public async Task OnCalloutReceived(Callout callout)
        {
            DebugLog("Callout Received!");
            string callIdent = callout.Identifier;
            string callId = callout.CaseID;
            string callName = callout.ShortName;
            string callDesc = callout.CalloutDescription;
            Vector3 callLoc = callout.Location;
            Blip callMarker = callout.Marker;
            int callResponse = callout.ResponseCode;
            TriggerServerEvent("SonoranCAD::fivepd:CalloutReceived", Game.Player.Character.NetworkId, callIdent, callId, callName, callDesc, callLoc, callMarker, callResponse);
        }

        public async Task OnCalloutAccepted(Callout callout)
        {
            DebugLog("Callout Accepted!");
            string callIdent = callout.Identifier;
            DebugLog("callIdent" + callIdent);
            string callId = callout.CaseID;
            DebugLog("callId" + callId);
            string callName = callout.ShortName;
            DebugLog("callName" + callName);
            string callDesc = callout.CalloutDescription;
            DebugLog("callDesc!" + callDesc);
            Vector3 callCoord = callout.Location;
            DebugLog("callLoc" + callCoord.ToString());
            uint var1 = 0;
            uint var2 = 0;

            API.GetStreetNameAtCoord(callCoord.X, callCoord.Y, callCoord.Z, ref var1, ref var2);

            var l1 = API.GetStreetNameFromHashKey(var1);
            var l2 = API.GetStreetNameFromHashKey(var2);

            string callLocation = (l2 != ""? l1 + " / " + l2: l1);

            int callResponse = callout.ResponseCode;
            DebugLog("callResponse" + callResponse);
            DebugLog("Sending Callout to CAD");
            TriggerServerEvent("SonoranCAD::fivepd:CalloutAccepted", Game.Player.Character.NetworkId, callIdent, callId, callName, callDesc, callResponse, callLocation, callCoord);
        }
        public async Task OnCalloutCompleted(Callout callout)
        {
            DebugLog("Callout Complete!");
            TriggerServerEvent("SonoranCAD::fivepd:CalloutCompleted", Game.Player.Character.NetworkId, callout);
        }

        public async Task OnDutyStatusChange(bool onDuty)
        {
            DebugLog("You are now " + (onDuty ? "on" : "off") + "duty");
            TriggerServerEvent("SonoranCAD::fivepd:DutyStatusChange", Game.Player.Character.NetworkId, onDuty);
        }

        public async Task OnServiceCalled(Utilities.Services service)
        {
            DebugLog("Called Service: " + service);
            TriggerServerEvent("SonoranCAD::fivepd:ServiceCalled", Game.Player.Character.NetworkId, service);
        }

        public async Task OnRankChanged(string rank)
        {
            DebugLog("Rank Changed!");
            TriggerServerEvent("SonoranCAD::fivepd:RankChanged", Game.Player.Character.NetworkId, rank);
        }

        public async Task OnPedArrested(Ped ped)
        {
            DebugLog("Ped Arrested!");
            PedData pedData = await Utilities.GetPedData(ped.NetworkId);
            TriggerServerEvent("SonoranCAD::fivepd:PedArrested", Game.Player.Character.NetworkId, pedData);
        }
    }
}
