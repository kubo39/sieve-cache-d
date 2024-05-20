import sievecache;

import std.stdio;

void main()
{
    auto cache = SieveCache!(string, string)(10_000);

    cache["foo"] = "foocontent";
    cache["bar"] = "barcontent";
    cache.remove("bar");

    writeln(cache["foo"]);           // "foocontent"
    writeln(!cache.contains("bar")); // false
    writeln(cache.length);           // 1
    writeln(cache.capacity);         // 10000
}
