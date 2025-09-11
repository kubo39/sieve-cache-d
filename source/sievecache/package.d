/**
 * This is an implementation of the [SIEVE](https://cachemon.github.io/SIEVE-website)
 * cache replacement algorithm for D.
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2024 Hiroki Noda
 * License: MIT
 */
module sievecache;

@safe:

private:

import core.atomic : atomicLoad;
import std.exception : enforce;
import std.traits : isEqualityComparable, isSomeFunction, isTypeTuple;

// https://github.com/dlang/dmd/blob/5b5fba8b6af4a3b66f1cf0c2157a69305094ff27/compiler/src/dmd/typesem.d#L1598-L1605
enum bool isKeyableType(T) = !(is(isSomeFunction!T) || is(T == void) || is(isTypeTuple!T));

public:

/**
 * A cache based on the SIEVE eviction algorithm.
 */
struct SieveCache(K, V) if (isEqualityComparable!K && isKeyableType!K)
{
    /**
     * Create a new cache with given capacity.
     */
    this(size_t capacity) pure
    {
        enforce(capacity > 0, "capacity must be greater than zero.");
        capacity_ = capacity;
        length_ = 0;
    }

    /**
     * Returns the capacity of the cache.
     */
    size_t capacity() const @nogc nothrow pure
    {
        return capacity_;
    }

    /// Ditto.
    size_t capacity() shared const @nogc nothrow pure
    {
        return capacity_;
    }

    /**
     * Returns the length of the cache.
     */
    size_t length() const @nogc nothrow pure
    {
        return length_;
    }

    /// Ditto.
    size_t length() shared const @nogc nothrow pure
    {
        return length_.atomicLoad;
    }

    /**
     * Returns `true` when no value are currently cached.
     */
    bool empty() const @nogc nothrow pure
    {
        return length_ == 0;
    }

    /// Ditto.
    bool empty() shared const @nogc nothrow pure
    {
        return length_.atomicLoad == 0;
    }

    /**
     * Supports $(B key in aa) syntax.
     */
    V* opBinaryRight(string op)(K key) nothrow pure if (op == "in")
    {
        return get(key);
    }

    /// Ditto.
    shared(V)* opBinaryRight(string op)(K key) shared if (op == "in")
    {
        return get(key);
    }

    /**
     * Returns `true` if there is a value in the cache mapped to
     * by `key`.
     */
    bool contains(K key) const @nogc nothrow pure
    {
        return (key in aa_) !is null;
    }

    /// Ditto.
    bool contains(K key) shared const @nogc nothrow
    {
        synchronized
        {
            return (key in aa_) !is null;
        }
    }

    /**
     * Supports `aa[key]` syntax.
     */
    ref opIndex(K key) pure
    {
        import std.conv : text;

        auto p = get(key);
        enforce(p !is null, "'" ~ text(key) ~ "' not found in the cache.");
        return *p;
    }

    /// Ditto.
    ref opIndex(K key) shared
    {
        import std.conv : text;

        auto p = get(key);
        enforce(p !is null, "'" ~ text(key) ~ "' not found in the cache.");
        return *p;
    }

    /**
     * Yields a pointer to the value in the cache mapped to
     * by `key`.
     * If no value exists for `key`, returns `null`.
     */
    V* get(K key) @nogc nothrow pure
    {
        Node!(K, V)** nodePtr = key in aa_;
        if (nodePtr is null)
        {
            return null;
        }
        (*nodePtr).visited = true;
        return &(*nodePtr).value;
    }

    /// Ditto.
    shared(V)* get(K key) shared @nogc nothrow
    {
        synchronized
        {
            auto nodePtr = key in aa_;
            if (nodePtr is null)
            {
                return null;
            }
            (*nodePtr).visited = true;
            return &(*nodePtr).value;
        }
    }

    /**
     * Supports $(B aa[key] = value;) syntax.
     */
    void opIndexAssign(V value, K key) nothrow pure
    {
        insert(key, value);
    }

    /// Ditto.
    void opIndexAssign(shared V value, K key) shared
    {
        insert(key, value);
    }

    /**
     * Map `key` to `value` in the cache, possibly evicting old entries.
     * Returns `true` when this is a new entry, and `false` if an existing
     * entry was updated.
     */
    bool insert(K key, V value) nothrow pure
    {
        Node!(K, V)** nodePtr = key in aa_;
        if (nodePtr !is null)
        {
            (**nodePtr).value = value;
            (**nodePtr).visited = true;
            return false;
        }
        if (length_ >= capacity_)
        {
            evict();
        }
        Node!(K, V)* node = new Node!(K, V)(key, value);
        addNode(node);
        aa_[key] = node;
        assert(length_ < capacity_);
        length_++;
        return true;
    }

    /// Ditto.
    bool insert(K key, shared V value) shared
    {
        synchronized
        {
            auto nodePtr = key in aa_;
            if (nodePtr !is null)
            {
                (**nodePtr).value = value;
                (**nodePtr).visited = true;
                return false;
            }
            if (length_ >= capacity_)
            {
                evict();
            }
            auto node = new shared Node!(K, V)(key, value);
            addNode(node);
            aa_[key] = node;
            assert(length_ < capacity_);
            () @trusted { (cast() length_)++; }();
        }
        return true;
    }

    /**
     * Removes the cache entry mapped to by `key`.
     * Returns `true` and removes it from the cache if the given key
     * does exist.
     * If `key` did not map to any value, then this returns `false`.
     */
    bool remove(K key) @nogc nothrow pure
    {
        Node!(K, V)** nodePtr = key in aa_;
        if (nodePtr is null)
        {
            return false;
        }
        Node!(K, V)* node = *nodePtr;
        if (node is hand_)
        {
            hand_ = node.prev !is null ? node.prev : tail_;
        }
        removeNode(node);
        assert(length_ > 0);
        length_--;
        return aa_.remove(key);
    }

    /// Ditto.
    bool remove(K key) shared @nogc nothrow
    {
        synchronized
        {
            auto nodePtr = key in aa_;
            if (nodePtr is null)
            {
                return false;
            }
            auto node = *nodePtr;
            if (node is hand_)
            {
                hand_ = node.prev !is null ? node.prev : tail_;
            }
            removeNode(node);
            assert(length_ > 0);
            () @trusted { (cast() length_)--; }();
            return aa_.remove(key);
        }
    }

    /**
     * Removes all remining keys and values from the cache.
     */
    void clear() nothrow pure
    {
        aa_.clear;
        head_ = null;
        tail_ = null;
        hand_ = null;
        length_ = 0;
    }

    /// Ditto.
    void clear() @trusted shared nothrow
    {
        synchronized
        {
            (cast() aa_).clear;
            head_ = null;
            tail_ = null;
            hand_ = null;
            length_ = 0;
        }
    }

private:
    @disable this();

    @disable this(this);

    void addNode(Node!(K, V)* node) @nogc nothrow pure
    {
        node.next = head_;
        node.prev = null;
        if (head_ !is null)
        {
            head_.prev = node;
        }
        head_ = node;
        if (tail_ is null)
        {
            tail_ = head_;
        }
    }

    void addNode(shared Node!(K, V)* node) shared @nogc nothrow pure
    {
        node.next = head_;
        node.prev = null;
        if (head_ !is null)
        {
            head_.prev = node;
        }
        head_ = node;
        if (tail_ is null)
        {
            tail_ = head_;
        }
    }

    void removeNode(Node!(K, V)* node) @nogc nothrow pure
    {
        if (node.prev !is null)
        {
            node.prev.next = node.next;
        }
        else
        {
            head_ = node.next;
        }

        if (node.next !is null)
        {
            node.next.prev = node.prev;
        }
        else
        {
            tail_ = node.prev;
        }
        node.prev = null;
        node.next = null;
        assert(node !is hand_);
    }

    void removeNode(shared Node!(K, V)* node) shared @nogc nothrow pure
    {
        if (node.prev !is null)
        {
            node.prev.next = node.next;
        }
        else
        {
            head_ = node.next;
        }

        if (node.next !is null)
        {
            node.next.prev = node.prev;
        }
        else
        {
            tail_ = node.prev;
        }
        node.prev = null;
        node.next = null;
        assert(node !is hand_);
    }

    void evict() @nogc nothrow pure
    {
        Node!(K, V)* node = hand_ !is null ? hand_ : tail_;
        while (node !is null)
        {
            if (!node.visited)
            {
                break;
            }
            node.visited = false;
            if (node.prev !is null)
            {
                node = node.prev;
            }
            else
            {
                node = tail_;
            }
        }

        if (node !is null)
        {
            hand_ = node.prev;
            aa_.remove(node.key);
            removeNode(node);
            assert(length_ > 0);
            length_--;
        }
    }

    void evict() shared @nogc nothrow pure
    {
        shared Node!(K, V)* node = hand_ !is null ? hand_ : tail_;
        while (node !is null)
        {
            if (!node.visited)
            {
                break;
            }
            node.visited = false;
            if (node.prev !is null)
            {
                node = node.prev;
            }
            else
            {
                node = tail_;
            }
        }

        if (node !is null)
        {
            hand_ = node.prev;
            aa_.remove(node.key);
            removeNode(node);
            assert(length_ > 0);
            () @trusted { (cast() length_)--; }();
        }
    }

    Node!(K, V)*[K] aa_;
    Node!(K, V)* head_;
    Node!(K, V)* tail_;
    Node!(K, V)* hand_;
    immutable size_t capacity_;
    size_t length_;

    struct Node(K, V)
    {
        K key;
        V value;
        Node!(K, V)* prev;
        Node!(K, V)* next;
        bool visited;
    }
}

@("smoke test")
unittest
{
    import std.exception;

    auto cache = SieveCache!(string, string)(3);
    assert(cache.capacity == 3);
    assert(cache.empty());
    assert(cache.insert("foo", "foocontent"));
    cache["bar"] = "barcontent";
    assert(cache.remove("bar"));
    assert(cache.insert("bar2", "bar2content"));
    assert(cache.insert("bar3", "bar3content"));
    assert(*cache.get("foo") == "foocontent");
    assert(cache.contains("foo"));
    assert(cache.get("bar") is null);
    assertThrown(cache["bar"]);
    assert(cache["bar2"] == "bar2content");
    assert(*("bar3" in cache) == "bar3content");
    assert(cache.length == 3);
    cache.clear();
    assert(cache.length == 0);
    assert(!cache.contains("foo"));
}

@("smoke test for shared")
unittest
{
    import std.exception;

    auto cache = shared SieveCache!(string, string)(3);
    assert(cache.capacity == 3);
    assert(cache.empty());
    assert(cache.insert("foo", "foocontent"));
    cache["bar"] = "barcontent";
    assert(cache.remove("bar"));
    assert(cache.insert("bar2", "bar2content"));
    assert(cache.insert("bar3", "bar3content"));
    assert(*cache.get("foo") == "foocontent");
    assert(cache.contains("foo"));
    assert(cache.get("bar") is null);
    assertThrown(cache["bar"]);
    assert(cache["bar2"] == "bar2content");
    assert(*("bar3" in cache) == "bar3content");
    assert(cache.length == 3);
    cache.clear();
    assert(cache.length == 0);
    assert(!cache.contains("foo"));
}

@("test for update visited flag")
unittest
{
    auto cache = SieveCache!(string, string)(2);
    cache["key1"] = "value1";
    cache["key2"] = "value2";
    // update key1 entry.
    cache["key1"] = "updated";
    // add new entry
    cache["key3"] = "value3";
    assert(cache.contains("key1"));
}

@("test get")
unittest
{
    auto cache = SieveCache!(string, int)(1);
    cache["key1"] = 0;
    assert(++cache["key1"] == 1);
    assert(cache["key1"] == 1);
}

@("insert never exceeds capacity when all visited")
unittest
{
    import std.exception : assertNotThrown;
    auto cache = SieveCache!(string, int)(2);
    cache["a"] = 1;
    cache["b"] = 2;
    assertNotThrown(cache["a"]);
    assertNotThrown(cache["b"]);
    cache["c"] = 3;
    assert(cache.length <= cache.capacity);
}
