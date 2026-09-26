using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;

namespace SonoranPlugin
{
    internal static class CalloutEntityCollector
    {
        // FivePD callouts retain spawned entities in fields, including auto-property backing fields.
        // Inspect only those fields and ordinary collections; never invoke plugin property getters.
        public static List<T> Collect<T>(object callout, Type stopAt) where T : class
        {
            var result = new List<T>();
            var pending = new Queue<object>();
            for (Type type = callout?.GetType(); type != null && type != stopAt; type = type.BaseType)
            {
                foreach (var field in type.GetFields(BindingFlags.Instance | BindingFlags.Public
                    | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
                {
                    if (pending.Count >= 256) break;
                    try { pending.Enqueue(field.GetValue(callout)); }
                    catch (Exception) { /* One inaccessible field must not block the other entities. */ }
                }
            }

            var visited = new HashSet<object>(ReferenceComparer.Instance);
            int examined = 0;
            while (pending.Count > 0 && examined++ < 512 && result.Count < 64)
            {
                object value = pending.Dequeue();
                if (value == null || !visited.Add(value)) continue;
                if (value is T entity) { result.Add(entity); continue; }
                if (value is Array array)
                {
                    foreach (var item in array) { if (pending.Count >= 256) break; pending.Enqueue(item); }
                }
                else if (value.GetType().IsGenericType && value.GetType().GetGenericTypeDefinition() == typeof(List<>))
                {
                    foreach (var item in (IList)value) { if (pending.Count >= 256) break; pending.Enqueue(item); }
                }
                else if (value.GetType().IsGenericType && value.GetType().GetGenericTypeDefinition() == typeof(Dictionary<,>))
                {
                    foreach (DictionaryEntry item in (IDictionary)value)
                    {
                        if (pending.Count >= 256) break;
                        pending.Enqueue(item.Value);
                    }
                }
            }
            return result;
        }

        private sealed class ReferenceComparer : IEqualityComparer<object>
        {
            public static readonly ReferenceComparer Instance = new ReferenceComparer();
            public new bool Equals(object x, object y) => ReferenceEquals(x, y);
            public int GetHashCode(object value) => System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(value);
        }
    }
}
