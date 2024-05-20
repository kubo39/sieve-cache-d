private:

import sievecache;

import std.datetime.stopwatch;
import std.random;
import std.stdio;

struct S { ubyte[] a; ulong b; }

void main()
{
    auto sw = StopWatch(AutoStart.no);
    // Sequence.
    {
        auto cache = SieveCache!(ulong, ulong)(68);

        sw.start();
        foreach (i; 1 .. 1000)
        {
            const n = i % 100;
            cache[n] = n;
        }
        foreach (i; 1 .. 1000)
        {
            const n = i % 100;
            cache.get(n);
        }
        sw.stop();
        writeln("Sequence: ", sw.peek);
    }
    sw.reset();

    // Composite.
    {
        auto cache = SieveCache!(ulong, S)(68);

        sw.start();
        foreach (_; 1 .. 1000)
        {
            const n = uniform(0, 100);
            cache[n] = S(new ubyte[12], n);
        }
        foreach (_; 1 .. 1000)
        {
            const n = uniform(0, 100);
            cache.get(n);
        }
        sw.stop();
        writeln("Composite: ", sw.peek);
    }
    sw.reset();

    // CompositeNormal.
    {
        enum SIGMA = 50.0 / 3.0;
        auto cache = SieveCache!(ulong, S)(cast(size_t) SIGMA);

        sw.start();
        foreach (_; 1 .. 1000)
        {
            const n = uniform(0, 100);
            cache[n] = S(new ubyte[12], n);
        }
        foreach (_; 1 .. 1000)
        {
            const n = uniform(0, 100);
            cache.get(n);
        }
        sw.stop();
        writeln("CompositeNormal: ", sw.peek);
    }
}
