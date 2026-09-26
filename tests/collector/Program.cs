using System;
using System.Collections.Generic;
using SonoranPlugin;

static class Program
{
    static void Assert(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    static void Main()
    {
        var callout = new ExampleCallout();
        var entities = CalloutEntityCollector.Collect<Entity>(callout, typeof(Callout));
        Assert(entities.Count == 5, "Private, inherited, array, dictionary and auto-property fields are collected once");
        Assert(!entities.Contains(Callout.Player), "FivePD base fields are excluded");
        Assert(!entities.Contains(ExampleCallout.Shared), "Static fields are excluded");
        Assert(!entities.Contains(callout.Hidden.Entity), "Unrelated helper objects are not traversed");
        Assert(!entities.Contains(callout.Custom[0]), "Custom collection subclasses are not enumerated");
        callout.Later.Add(new Entity());
        Assert(CalloutEntityCollector.Collect<Entity>(callout, typeof(Callout)).Count == 6, "Later spawns are discovered");
        callout.Cycle.Add(callout.Cycle);
        Assert(CalloutEntityCollector.Collect<Entity>(callout, typeof(Callout)).Count == 6, "Collection cycles terminate");
        for (int i = 0; i < 1000; i++) callout.Later.Add(new Entity());
        Assert(CalloutEntityCollector.Collect<Entity>(callout, typeof(Callout)).Count == 64, "Large callouts have bounded results");
        Assert(CalloutEntityCollector.Collect<Entity>(null, typeof(Callout)).Count == 0, "No current callout is harmless");
        Console.WriteLine("PASS: callout entity discovery, delayed spawns, deduplication, isolation, cycles and bounds");
    }

    class Entity { }
    class Callout { public static readonly Entity Player = new Entity(); private Entity assignedPlayer = Player; }
    class BaseCallout : Callout { private Entity inherited = new Entity(); }
    class Helper { public Entity Entity = new Entity(); }
    class CustomCollection : List<Entity> { }
    class ExampleCallout : BaseCallout
    {
        private Entity suspect = new Entity();
        public Entity Victim { get; } = new Entity();
        public Entity Getter => throw new Exception("Property getters must never execute");
        public static Entity Shared = new Entity();
        public Helper Hidden = new Helper();
        public CustomCollection Custom = new CustomCollection { new Entity() };
        public List<Entity> Later = new List<Entity>();
        public List<object> Cycle = new List<object>();
        private Entity[] array = { new Entity() };
        private Dictionary<string, Entity> vehicles;
        public ExampleCallout() { vehicles = new Dictionary<string, Entity> { ["vehicle"] = new Entity(), ["duplicate"] = suspect }; }
    }
}
