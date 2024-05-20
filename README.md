# SIEVE cache in D

An implementation of the [SIEVE][1] Cache algorithm for D.
This implementation is fully inspired by [Rust's sieve-cache implementation][2].

- [`code.dlang.org` page][3]

## Usage

```d
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
```

## Development

### Testing

```console
dub test
```

### Lint

```console
dub lint
```

## Serve the docmentation on a local server

```console
dub run -b ddox
```

[1]: https://cachemon.github.io/SIEVE-website/
[2]: https://github.com/jedisct1/rust-sieve-cache
[3]: https://code.dlang.org/packages/sievecache
