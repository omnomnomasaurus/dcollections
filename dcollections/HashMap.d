/*********************************************************
   Copyright: (C) 2008 by Steven Schveighoffer.
              All rights reserved

   License: $(LICENSE)

**********************************************************/
module dcollections.HashMap;

public import dcollections.model.Map;
public import dcollections.DefaultFunctions;
private import dcollections.Hash;

private import dcollections.Iterators;

version(unittest)
{
    import std.traits;
    static import std.algorithm;

    bool rangeEqual(R, V, K)(R range, V[K] arr)
    {
        uint len = 0;
        while(!range.empty)
        {
            V *x = range.key in arr;
            if(!x || *x != range.front)
                return false;
            ++len;
            range.popFront();
        }
        return len == arr.length;
    }

    V[K] makeAA(V, K)(HashMap!(K, V).range range)
    {
        V[K] result;
        while(!range.empty)
        {
            result[range.key] = range.front;
            range.popFront();
        }
        return result;
    }
}

/**
 * A map implementation which uses a Hash to have near O(1) insertion,
 * deletion and lookup time.
 *
 * Adding an element might invalidate cursors depending on the implementation.
 *
 * Removing an element only invalidates cursors that were pointing at that
 * element.
 *
 * You can replace the Hash implementation with a custom implementation, the
 * Hash must be a struct template which can be instantiated with a single
 * template argument V, and must implement the following members (non-function
 * members can be get/set properties unless otherwise specified):
 *
 * uint count -> count of the elements in the hash
 *
 * position -> must be a struct/class with the following member:
 *   ptr -> must define the following member:
 *     value -> the value which is pointed to by this position (cannot be a
 *                property)
 *   position next -> next position in the hash map
 *   position prev -> previous position in the hash map
 *
 * bool add(V v) -> add the given value to the hash.  The hash of the value
 * will be given by hashFunction(v).  If the value already exists in the hash,
 * this should call updateFunction(v) and should not increment count.
 *
 * position begin -> must be a position that points to the very first valid
 * element in the hash, or end if no elements exist.
 *
 * position end -> must be a position that points to just past the very last
 * valid element.
 *
 * position find(V v) -> returns a position that points to the element that
 * contains v, or end if the element doesn't exist.
 *
 * position remove(position p) -> removes the given element from the hash,
 * returns the next valid element or end if p was last in the hash.
 *
 * void clear() -> removes all elements from the hash, sets count to 0.
 */
class HashMap(K, V, alias ImplTemp=Hash, alias hashFunction=DefaultHash) : Map!(K, V)
{
    version(unittest) enum doUnittest = isIntegral!K && is(V == uint);

    /**
     * used to implement the key/value pair stored in the hash implementation
     */
    struct element
    {
        K key;
        V val;

        /**
         * compare 2 elements for equality.  Only compares the keys.
         */
        bool opEquals(ref const(element) e) const
        {
            return key == e.key;
        }
    }

    static if(doUnittest) unittest
    {
        element e1, e2;
        e1.key = 1;
        e1.val = 2;
        e2.key = 1;
        e2.val = 3;
        assert(e1 == e2);
        e2.key = 2;
        e2.val = 2;
        assert(e1 != e2);
    }

    private KeyIterator _keys;

    /**
     * Function to get the hash of an element
     */
    static uint _hashFunction(ref element e)
    {
        return hashFunction(e.key);
    }

    /**
     * Function to update an element according to the new element.
     */
    static void _updateFunction(ref element orig, ref element newelem)
    {
        //
        // only copy the value, leave the key alone
        //
        orig.val = newelem.val;
    }

    /**
     * convenience alias
     */
    alias ImplTemp!(element, _hashFunction, _updateFunction) Impl;

    private Impl _hash;

    /**
     * A cursor for the hash map.
     */
    struct cursor
    {
        private Impl.position position;
        private bool _empty = false;

        /**
         * get the value at this cursor
         */
        @property V front()
        {
            assert(!_empty, "Attempting to read the value of an empty cursor of " ~ HashMap.stringof);
            return position.ptr.value.val;
        }

        /**
         * get the key at this cursor
         */
        @property K key()
        {
            assert(!_empty, "Attempting to read the key of an empty cursor of " ~ HashMap.stringof);
            return position.ptr.value.key;
        }

        /**
         * set the value at this cursor
         */
        @property V front(V v)
        {
            assert(!_empty, "Attempting to write the value of an empty cursor of " ~ HashMap.stringof);
            position.ptr.value.val = v;
            return v;
        }

        /**
         * Tell if this cursor is empty (doesn't point to any value)
         */
        @property bool empty() const
        {
            return _empty;
        }

        /**
         * Move to the next element.
         */
        void popFront()
        {
            assert(!_empty, "Attempting to popFront() an empty cursor of " ~ HashMap.stringof);
            _empty = true;
            position = position.next;
        }

        /**
         * compare two cursors for equality.  Note that only the position of
         * the cursor is checked, whether it's empty or not is not checked.
         */
        bool opEquals(ref const(cursor) it) const
        {
            return it.position is position;
        }

        /*
         * TODO, this should compile, but currently doesn't!
         *
         * compare two cursors for equality.  Note that only the position of
         * the cursor is checked, whether it's empty or not is not checked.
         */
        /*bool opEquals(const cursor it) const
        {
            return it.position is position;
        }*/
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        auto cu = hm.elemAt(3);
        assert(!cu.empty);
        assert(cu.front == 3);
        assert((cu.front = 8)  == 8);
        assert(cu.front == 8);
        assert(hm == cast(V[K])[1:1, 2:2, 3:8, 4:4, 5:5]);
        cu.popFront();
        assert(cu.empty);
        assert(hm == cast(V[K])[1:1, 2:2, 3:8, 4:4, 5:5]);
    }


    /**
     * A range that can be used to iterate over the elements in the hash.
     */
    struct range
    {
        private Impl.position _begin;
        private Impl.position _end;

        /**
         * is the range empty?
         */
        @property bool empty()
        {
            return _begin is _end;
        }

        /**
         * Get a cursor to the first element in the range
         */
        @property cursor begin()
        {
            cursor c;
            c.position = _begin;
            c._empty = empty;
            return c;
        }

        /**
         * Get a cursor to the end element in the range
         */
        @property cursor end()
        {
            cursor c;
            c.position = _end;
            c._empty = true;
            return c;
        }

        /**
         * Get the first value in the range
         */
        @property V front()
        {
            assert(!empty, "Attempting to read front of an empty range of " ~ HashMap.stringof);
            return _begin.ptr.value.val;
        }

        /**
         * Write the first value in the range.
         */
        @property V front(V v)
        {
            assert(!empty, "Attempting to write front of an empty range of " ~ HashMap.stringof);
            _begin.ptr.value.val = v;
            return v;
        }

        /**
         * Get the key of the front element
         */
        @property K key()
        {
            assert(!empty, "Attempting to read the key of an empty range of " ~ HashMap.stringof);
            return _begin.ptr.value.key;
        }

        /**
         * Get the last value in the range
         */
        @property V back()
        {
            assert(!empty, "Attempting to read back of an empty range of " ~ HashMap.stringof);
            return _end.prev.ptr.value.val;
        }

        /**
         * Write the last value in the range.
         */
        @property V back(V v)
        {
            assert(!empty, "Attempting to write back of an empty range of " ~ HashMap.stringof);
            _end.prev.ptr.value.val = v;
            return v;
        }

        /**
         * Get the key of the last element
         */
        @property K backKey()
        {
            assert(!empty, "Attempting to read the back key of an empty range of " ~ HashMap.stringof);
            return _end.prev.ptr.value.key;
        }

        /**
         * Move the front of the range ahead one element
         */
        void popFront()
        {
            assert(!empty, "Attempting to popFront() an empty range of " ~ HashMap.stringof);
            _begin = _begin.next;
        }

        /**
         * Move the back of the range to the previous element
         */
        void popBack()
        {
            assert(!empty, "Attempting to popBack() an empty range of " ~ HashMap.stringof);
            _end = _end.prev;
        }
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        V[K] data = [1:1, 2:2, 3:3, 4:4, 5:5];
        hm.set(data);
        auto r = hm[];
        assert(rangeEqual(r, data));
        assert(r.front == hm[r.key]);
        assert(r.back == hm[r.backKey]);
        r.popFront();
        r.popBack();
        assert(r.front == hm[r.key]);
        assert(r.back == hm[r.backKey]);

        r.front = 10;
        r.back = 11;
        data[r.key] = 10;
        data[r.backKey] = 11;
        assert(hm[r.key] == 10);
        assert(hm[r.backKey] == 11);

        auto b = r.begin;
        assert(!b.empty);
        assert(b.front == 10);
        auto e = r.end;
        assert(e.empty);

        assert(hm == data);
    }


    /**
     * Determine if a cursor belongs to the hashmap
     */
    bool belongs(cursor c)
    {
        // rely on the implementation to tell us
        return _hash.belongs(c.position);
    }

    /**
     * Determine if a range belongs to the hashmap
     */
    bool belongs(range r)
    {
        return _hash.belongs(r._begin) && _hash.belongs(r._end);
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        auto cu = hm.elemAt(3);
        assert(cu.front == 3);
        assert(hm.belongs(cu));
        auto r = hm[hm.begin..cu];
        assert(hm.belongs(r));

        auto hm2 = hm.dup;
        assert(!hm2.belongs(cu));
        assert(!hm2.belongs(r));
    }

    /**
     * Iterate over the values of the HashMap, telling it which ones to
     * remove.
     */
    final int purge(scope int delegate(ref bool doPurge, ref V v) dg)
    {
        int _dg(ref bool doPurge, ref K k, ref V v)
        {
            return dg(doPurge, v);
        }
        return _apply(&_dg);
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        foreach(ref p, i; &hm.purge)
        {
            p = (i & 1);
        }

        assert(hm == cast(V[K])[2:2, 4:4]);
    }

    /**
     * Iterate over the key/value pairs of the HashMap, telling it which ones
     * to remove.
     */
    final int keypurge(scope int delegate(ref bool doPurge, ref K k, ref V v) dg)
    {
        return _apply(dg);
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[0:1, 1:2, 2:3, 3:4, 4:5]);
        foreach(ref p, k, i; &hm.keypurge)
        {
            p = (k & 1);
        }

        assert(hm == cast(V[K])[0:1, 2:3, 4:5]);
    }


    private class KeyIterator : Iterator!(K)
    {
        @property final uint length() const
        {
            return this.outer.length;
        }

        final int opApply(scope int delegate(ref K) dg)
        {
            int _dg(ref bool doPurge, ref K k, ref V v)
            {
                return dg(k);
            }
            return _apply(&_dg);
        }
    }

    private int _apply(scope int delegate(ref bool doPurge, ref K k, ref V v) dg)
    {
        Impl.position it = _hash.begin;
        bool doPurge;
        int dgret = 0;
        Impl.position _end = _hash.end; // cache end so it isn't always being generated
        while(!dgret && it !is _end)
        {
            //
            // don't allow user to change key
            //
            K tmpkey = it.ptr.value.key;
            doPurge = false;
            if((dgret = dg(doPurge, tmpkey, it.ptr.value.val)) != 0)
                break;
            if(doPurge)
                it = _hash.remove(it);
            else
                it = it.next;
        }
        return dgret;
    }

    /**
     * iterate over the collection's key/value pairs
     */
    int opApply(scope int delegate(ref K k, ref V v) dg)
    {
        int _dg(ref bool doPurge, ref K k, ref V v)
        {
            return dg(k, v);
        }

        return _apply(&_dg);
    }

    /**
     * iterate over the collection's values
     */
    int opApply(scope int delegate(ref V v) dg)
    {
        int _dg(ref bool doPurge, ref K k, ref V v)
        {
            return dg(v);
        }
        return _apply(&_dg);
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[0:1, 1:2, 2:3, 3:4, 4:5]);
        uint idx = 0;
        foreach(i; hm)
        {
            assert(!std.algorithm.find(hm[], i).empty);
            ++idx;
        }
        assert(idx == hm.length);
        idx = 0;
        foreach(k, i; hm)
        {
            auto cu = hm.elemAt(k);
            assert(cu.front == i);
            assert(cu.key == k);
            ++idx;
        }
        assert(idx == hm.length);
    }


    /**
     * Instantiate the hash map
     */
    this()
    {
        // create the key iterator
        _keys = new KeyIterator;
        // setup the hash with defaults
        _hash.setup();
    }

    //
    // private constructor for dup
    //
    private this(ref Impl dupFrom)
    {
        // setup the hash with defaults
        _hash.setup();
        dupFrom.copyTo(_hash);
        _keys = new KeyIterator;
    }

    /**
     * Clear the collection of all elements
     */
    HashMap clear()
    {
        _hash.clear();
        return this;
    }

    /**
     * returns number of elements in the collection
     */
    @property uint length() const
    {
        return _hash.count;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        assert(hm.length == 5);
        hm.clear();
        assert(hm.length == 0);
    }

    /**
     * returns a cursor to the first element in the collection.
     */
    @property cursor begin()
    {
        cursor it;
        it.position = _hash.begin;
        return it;
    }

    /**
     * returns a cursor that points just past the last element in the
     * collection.
     */
    @property cursor end()
    {
        cursor it;
        it.position = _hash.end;
        it._empty = true;
        return it;
    }

    /**
     * remove the element pointed at by the given cursor, returning an
     * cursor that points to the next element in the collection.
     *
     * if the cursor is empty, it does not remove any elements, but returns a
     * cursor that points to the next element.
     *
     * Runs on average in O(1) time.
     */
    cursor remove(cursor it)
    {
        assert(belongs(it), "Error, attempting to remove invalid cursor from " ~ HashMap.stringof);
        if(!it.empty)
        {
            it.position = _hash.remove(it.position);
        }
        it._empty = (it.position == _hash.end);
        return it;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        hm.remove(hm.elemAt(3));
        assert(hm == cast(V[K])[1:1, 2:2, 4:4, 5:5]);
    }


    /**
     * remove all the elements in the given range.
     */
    cursor remove(range r)
    {
        assert(belongs(r), "Error, attempting to remove invalid cursor from " ~ HashMap.stringof);
        auto b = r.begin;
        auto e = r.end;
        while(b != e)
        {
            b = remove(b);
        }
        return b;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        auto r = hm[hm.elemAt(3)..hm.end];
        V[K] resultAA = [1:1, 2:2, 3:3, 4:4, 5:5];
        for(auto r2 = r; !r2.empty; r2.popFront())
            resultAA.remove(r2.key);
        hm.remove(r);
        assert(hm == resultAA);
    }

    /**
     * get a slice of all the elements in this hashmap.
     */
    range opSlice()
    {
        range result;
        result._begin = _hash.begin;
        result._end = _hash.end;
        return result;
    }

    /**
     * get a slice of the elements between the two cursors.
     *
     * This function only works if either b is the first element in the hashmap
     * or e is the end element.  The rationale is that we want to ensure that
     * opSlice returns quickly, and not knowing the implementation, we cannot
     * know if determining the order of two cursors is an O(n) operation.
     */
    range opSlice(cursor b, cursor e)
    {
        // for hashmap, we only support ranges that begin on the first cursor,
        // or end on the last cursor.
        // TODO: switch this back when compiler is more sane
        //if((b == begin && belongs(e)) || (e == end && belongs(b)))
        if((begin == b && belongs(e)) || (end == e && belongs(b)))
        {
            range result;
            result._begin = b.position;
            result._end = e.position;
            return result;
        }
        throw new Exception("invalid slice parameters to " ~ HashMap.stringof);
    }

    static if (doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        assert(rangeEqual(hm[], cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]));
        auto cu = hm.elemAt(3);
        auto r = hm[hm.begin..cu];
        V[K] firsthalf = makeAA(r);
        auto r2 = hm[cu..hm.end];
        V[K] secondhalf = makeAA(r2);
        assert(firsthalf.length + secondhalf.length == hm.length);
        foreach(k, v; firsthalf)
        {
            assert(k !in secondhalf);
        }
        bool exceptioncaught = false;
        try
        {
            hm[cu..cu];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(exceptioncaught);
    }

    /**
     * find the instance of a key in the collection.  Returns end if the key
     * is not present.
     *
     * Runs in average O(1) time.
     */
    cursor elemAt(K k)
    {
        cursor it;
        element tmp;
        tmp.key = k;
        it.position = _hash.find(tmp);
        if(it.position == _hash.end)
            it._empty = true;
        return it;
    }

    /**
     * Removes the element that has the given key.  Returns true if the
     * element was present and was removed.
     *
     * Runs on average in O(1) time.
     */
    HashMap remove(K key)
    {
        bool ignored;
        return remove(key, ignored);
    }

    /**
     * Removes the element that has the given key.  Returns true if the
     * element was present and was removed.
     *
     * Runs on average in O(1) time.
     */
    HashMap remove(K key, out bool wasRemoved)
    {
        cursor it = elemAt(key);
        if((wasRemoved = !it.empty) is true)
        {
            remove(it);
        }
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        bool wasRemoved;
        hm.remove(1, wasRemoved);
        assert(hm == cast(V[K])[2:2, 3:3, 4:4, 5:5]);
        assert(wasRemoved);
        hm.remove(10, wasRemoved);
        assert(hm == cast(V[K])[2:2, 3:3, 4:4, 5:5]);
        assert(!wasRemoved);
        hm.remove(4);
        assert(hm == cast(V[K])[2:2, 3:3, 5:5]);
    }

    /**
     * Returns the value that is stored at the element which has the given
     * key.  Throws an exception if the key is not in the collection.
     *
     * Runs on average in O(1) time.
     */
    V opIndex(K key)
    {
        cursor it = elemAt(key);
        if(it.empty)
            throw new Exception("Index out of range");
        return it.front;
    }

    /**
     * assign the given value to the element with the given key.  If the key
     * does not exist, adds the key and value to the collection.
     *
     * Runs on average in O(1) time.
     */
    V opIndexAssign(V value, K key)
    {
        set(key, value);
        return value;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm[1] = 5;
        assert(hm.length == 1);
        assert(hm[1] == 5);
        hm[2] = 6;
        assert(hm.length == 2);
        assert(hm[2] == 6);
        assert(hm[1] == 5);
        hm[1] = 3;
        assert(hm.length == 2);
        assert(hm[2] == 6);
        assert(hm[1] == 3);
    }

    /**
     * Set a key/value pair.  If the key/value pair doesn't already exist, it
     * is added.
     */
    HashMap set(K key, V value)
    {
        bool ignored;
        return set(key, value, ignored);
    }

    /**
     * Set a key/value pair.  If the key/value pair doesn't already exist, it
     * is added, and the wasAdded parameter is set to true.
     */
    HashMap set(K key, V value, out bool wasAdded)
    {
        element elem;
        elem.key = key;
        elem.val = value;
        wasAdded = _hash.add(elem);
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        bool wasAdded;
        hm.set(1, 5, wasAdded);
        assert(hm.length == 1);
        assert(hm[1] == 5);
        assert(wasAdded);
        hm.set(2, 6);
        assert(hm.length == 2);
        assert(hm[2] == 6);
        assert(hm[1] == 5);
        hm.set(1, 3, wasAdded);
        assert(hm.length == 2);
        assert(hm[2] == 6);
        assert(hm[1] == 3);
        assert(!wasAdded);
    }

    /**
     * Set all the values from the iterator in the map.  If any elements did
     * not previously exist, they are added.
     */
    HashMap set(KeyedIterator!(K, V) source)
    {
        uint ignored;
        return set(source, ignored);
    }

    /**
     * Set all the values from the iterator in the map.  If any elements did
     * not previously exist, they are added.  numAdded is set to the number of
     * elements that were added in this operation.
     */
    HashMap set(KeyedIterator!(K, V) source, out uint numAdded)
    {
        uint origlength = length;
        bool ignored;
        foreach(k, v; source)
        {
            set(k, v, ignored);
        }
        numAdded = length - origlength;
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        auto hm2 = new HashMap;
        uint numAdded;
        hm2.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        hm.set(hm2);
        assert(hm2 == hm);
        hm2[6] = 6;
        hm.set(hm2, numAdded);
        assert(hm == hm2);
        assert(numAdded == 1);
    }

    /**
     * Remove all keys from the map which are in subset.
     */
    HashMap remove(Iterator!(K) subset)
    {
        foreach(k; subset)
            remove(k);
        return this;
    }

    /**
     * Remove all keys from the map which are in subset.  numRemoved is set to
     * the number of keys that were actually removed.
     */
    HashMap remove(Iterator!(K) subset, out uint numRemoved)
    {
        uint origlength = length;
        remove(subset);
        numRemoved = origlength - length;
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[0:0, 1:1, 2:2, 3:3, 4:4, 5:5]);
        auto ai = new ArrayIterator!K(cast(K[])[0, 2, 4, 6, 8]);
        uint numRemoved;
        hm.remove(ai, numRemoved);
        assert(hm == cast(V[K])[1:1, 3:3, 5:5]);
        assert(numRemoved == 3);
        ai = new ArrayIterator!K(cast(K[])[1, 3]);
        hm.remove(ai);
        assert(hm == cast(V[K])[5:5]);
    }

    HashMap intersect(Iterator!(K) subset)
    {
        uint ignored;
        return intersect(subset, ignored);
    }

    /**
     * This function only keeps elements that are found in subset.
     */
    HashMap intersect(Iterator!(K) subset, out uint numRemoved)
    {
        //
        // this one is a bit trickier than removing.  We want to find each
        // Hash element, then move it to a new table.  However, we do not own
        // the implementation and cannot make assumptions about the
        // implementation.  So we defer the intersection to the hash
        // implementation.
        //
        // If we didn't care about runtime, this could be done with:
        //
        // remove((new HashSet!(K)).add(this.keys).remove(subset));
        //

        //
        // need to create a wrapper iterator to pass to the implementation,
        // one that wraps each key in the subset as an element
        //
        // scope allocates on the stack.
        //
        scope w = new TransformIterator!(element, K)(subset, function void(ref K k, ref element e) { e.key = k;});

        numRemoved = _hash.intersect(w);
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[0:0, 1:1, 2:2, 3:3, 4:4, 5:5]);
        auto ai = new ArrayIterator!K(cast(K[])[0, 2, 4, 6, 8]);
        uint numRemoved;
        hm.intersect(ai, numRemoved);
        assert(hm == cast(V[K])[0:0, 2:2, 4:4]);
        assert(numRemoved == 3);
        ai = new ArrayIterator!K(cast(K[])[0, 4]);
        hm.intersect(ai);
        assert(hm == cast(V[K])[0:0, 4:4]);
    }

    /**
     * Returns true if the given key is in the collection.
     *
     * Runs on average in O(1) time.
     */
    bool containsKey(K key)
    {
        return !elemAt(key).empty;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        assert(hm.containsKey(3));
        hm.remove(3);
        assert(!hm.containsKey(3));
    }

    /**
     * return an iterator that can be used to read all the keys
     */
    Iterator!(K) keys()
    {
        return _keys;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        auto arr = toArray(hm.keys);
        std.algorithm.sort(arr);
        assert(arr == cast(K[])[1, 2, 3, 4, 5]);
    }

    /**
     * Make a shallow copy of the hash map.
     */
    HashMap dup()
    {
        return new HashMap(_hash);
    }

    /**
     * Compare this HashMap with another Map
     *
     * Returns 0 if o is not a Map object, is null, or the HashMap does not
     * contain the same key/value pairs as the given map.
     * Returns 1 if exactly the key/value pairs contained in the given map are
     * in this HashMap.
     */
    bool opEquals(Object o)
    {
        //
        // try casting to map, otherwise, don't compare
        //
        auto m = cast(Map!(K, V))o;
        if(m !is null && m.length == length)
        {
            foreach(K k, V v; m)
            {
                auto cu = elemAt(k);
                if(cu.empty || cu.front != v)
                    return false;
            }
            return true;
        }

        return false;
    }

    /**
     * Compare this HashMap with an AA.
     *
     * Returns false if o is not a Map object, is null, or the HashMap does not
     * contain the same key/value pairs as the given map.
     * Returns true if exactly the key/value pairs contained in the given map
     * are in this HashMap.
     */
    bool opEquals(V[K] other)
    {
        if(other.length == length)
        {
            foreach(K k, V v; other)
            {
                auto cu = elemAt(k);
                if(cu.empty || cu.front != v)
                    return false;
            }
            return true;
        }
        return false;
    }

    /**
     * Set all the elements from the given associative array in the map.  Any
     * key that already exists will be overridden.
     *
     * returns this.
     */
    HashMap set(V[K] source)
    {
        foreach(K k, V v; source)
            this[k] = v;
        return this;
    }

    /**
     * Set all the elements from the given associative array in the map.  Any
     * key that already exists will be overridden.
     *
     * sets numAdded to the number of key value pairs that were added.
     *
     * returns this.
     */
    HashMap set(V[K] source, out uint numAdded)
    {
        uint origLength = length;
        set(source);
        numAdded = length - origLength;
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        uint numAdded;
        hm.set(cast(V[K])[1:1, 2:2, 3:3], numAdded);
        assert(hm == cast(V[K])[1:1, 2:2, 3:3]);
        assert(numAdded == 3);
        hm.set(cast(V[K])[2:2, 3:3, 4:4, 5:5], numAdded);
        assert(hm == cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        assert(numAdded == 2);
    }

    /**
     * Remove all the given keys from the map.
     *
     * return this.
     */
    HashMap remove(K[] subset)
    {
        foreach(k; subset)
            remove(k);
        return this;
    }

    /**
     * Remove all the given keys from the map.
     *
     * return this.
     *
     * numRemoved is set to the number of elements removed.
     */
    HashMap remove(K[] subset, out uint numRemoved)
    {
        uint origLength = length;
        remove(subset);
        numRemoved = origLength - length;
        return this;
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        uint numRemoved;
        hm.set(cast(V[K])[1:1, 2:2, 3:3, 4:4, 5:5]);
        hm.remove(cast(K[])[2, 4, 5]);
        assert(hm == cast(V[K])[1:1, 3:3]);
        hm.remove(cast(K[])[2, 3], numRemoved);
        assert(hm == cast(V[K])[1:1]);
        assert(numRemoved == 1);
    }

    /**
     * Remove all the keys that are not in the given array.
     *
     * returns this.
     */
    HashMap intersect(K[] subset)
    {
        scope iter = new ArrayIterator!(K)(subset);
        return intersect(iter);
    }

    /**
     * Remove all the keys that are not in the given array.
     *
     * sets numRemoved to the number of elements removed.
     *
     * returns this.
     */
    HashMap intersect(K[] subset, out uint numRemoved)
    {
        scope iter = new ArrayIterator!(K)(subset);
        return intersect(iter, numRemoved);
    }

    static if(doUnittest) unittest
    {
        auto hm = new HashMap;
        hm.set(cast(V[K])[0:0, 1:1, 2:2, 3:3, 4:4, 5:5]);
        uint numRemoved;
        hm.intersect(cast(K[])[0, 2, 4, 6, 8], numRemoved);
        assert(hm == cast(V[K])[0:0, 2:2, 4:4]);
        assert(numRemoved == 3);
        hm.intersect(cast(K[])[0, 4]);
        assert(hm == cast(V[K])[0:0, 4:4]);
    }

}

unittest
{
    // declare the HashMaps that should be tested.  Note that we don't care
    // about the value type because all interesting parts of the hash map
    // have to deal with the key.

    HashMap!(ubyte, uint)  hm1;
    HashMap!(byte, uint)   hm2;
    HashMap!(ushort, uint) hm3;
    HashMap!(short, uint)  hm4;
    HashMap!(uint, uint)   hm5;
    HashMap!(int, uint)    hm6;
    HashMap!(ulong, uint)  hm7;
    HashMap!(long, uint)   hm8;
}
