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

import core.atomic;
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

    @disable this();

    @disable this(this);

    /**
     * Returns the capacity of the cache.
     */
    size_t capacity() const @nogc nothrow pure
    {
        return capacity_;
    }

    /// Ditto.
    size_t capacity() shared const @nogc nothrow
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
    size_t length() shared const @nogc nothrow
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
    bool empty() shared const @nogc nothrow
    {
        return length_.atomicLoad == 0;
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
     * Yields a pointer to the value in the cache mapped to
     * by `key`.
     * If no value exists for `key`, returns `null`.
     */
    scope V* get(K key) @nogc nothrow pure
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
    scope shared(V)* get(K key) shared @nogc nothrow
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
    bool insert(K key, V value) shared
    {
        synchronized
        {
            auto nodePtr = key in aa_;
            if (nodePtr !is null)
            {
                (**nodePtr).value = value;
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
            length_.atomicOp!"+="(1);
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
            removeNode(node);
            assert(length_ > 0);
            length_.atomicOp!("-=")(1);
            return aa_.remove(key);
        }
    }

private:
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

    void addNode(shared Node!(K, V)* node) shared @nogc nothrow
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
    }

    void removeNode(shared Node!(K, V)* node) shared @nogc nothrow
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
    }

    void evict() @nogc nothrow pure
    {
        Node!(K, V)* node = null;
        if (hand_ !is null)
        {
            node = hand_;
        }
        else if (tail_ !is null)
        {
            node = tail_;
        }
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

    void evict() shared @nogc nothrow
    {
        shared Node!(K, V)* node = null;
        if (hand_ !is null)
        {
            node = hand_;
        }
        else if (tail_ !is null)
        {
            node = tail_;
        }
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
            length_.atomicOp!("-=")(1);
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
    auto cache = SieveCache!(string, string)(3);
    assert(cache.capacity == 3);
    assert(cache.empty());
    cache.insert("foo", "foocontent");
    cache.insert("bar", "barcontent");
    assert(cache.remove("bar"));
    cache.insert("bar2", "bar2content");
    cache.insert("bar3", "bar3content");
    assert(*cache.get("foo") == "foocontent");
    assert(cache.contains("foo"));
    assert(cache.get("bar") is null);
    assert(*cache.get("bar2") == "bar2content");
    assert(*cache.get("bar3") == "bar3content");
    assert(cache.length == 3);
}

@("smoke test for shared")
unittest
{
    auto cache = shared SieveCache!(string, string)(3);
    assert(cache.capacity == 3);
    assert(cache.empty());
    cache.insert("foo", "foocontent");
    cache.insert("bar", "barcontent");
    assert(cache.remove("bar"));
    cache.insert("bar2", "bar2content");
    cache.insert("bar3", "bar3content");
    assert(*cache.get("foo") == "foocontent");
    assert(cache.contains("foo"));
    assert(cache.get("bar") is null);
    assert(*cache.get("bar2") == "bar2content");
    assert(*cache.get("bar3") == "bar3content");
    assert(cache.length == 3);
}
