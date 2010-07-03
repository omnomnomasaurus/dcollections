/*********************************************************
   Copyright: (C) 2008 by Steven Schveighoffer.
              All rights reserved

   License: $(LICENSE)

**********************************************************/
module dcollections.TreeSet;

public import dcollections.model.Set;
public import dcollections.DefaultFunctions;

private import dcollections.RBTree;

version(unittest)
{
    import std.traits;
    import std.array;
    import std.range;
    import std.contracts;
    import dcollections.Iterators;
    static import std.algorithm;
}

/**
 * Implementation of the Set interface using Red-Black trees.  this allows for
 * O(lg(n)) insertion, removal, and lookup times.  It also creates a sorted
 * set.  V must be comparable.
 *
 * Adding an element does not invalidate any cursors.
 *
 * Removing an element only invalidates the cursors that were pointing at
 * that element.
 *
 * You can replace the Tree implementation with a custom implementation, the
 * implementation must be a struct template which can be instantiated with a
 * single template argument V, and must implement the following members
 * (non-function members can be properties unless otherwise specified):
 *
 * parameters -> must be a struct with at least the following members:
 *   compareFunction -> the compare function to use (should be a
 *                      CompareFunction!(V))
 *   updateFunction -> the update function to use (should be an
 *                     UpdateFunction!(V))
 * 
 * void setup(parameters p) -> initializes the tree with the given parameters.
 *
 * uint count -> count of the elements in the tree
 *
 * node -> must be a struct/class with the following members:
 *   V value -> the value which is pointed to by this position (cannot be a
 *                property)
 *   node next -> the next node in the tree as defined by the compare
 *                function, or end if no other nodes exist.
 *   node prev -> the previous node in the tree as defined by the compare
 *                function.
 *
 * bool add(V v) -> add the given value to the tree according to the order
 * defined by the compare function.  If the element already exists in the
 * tree, the 
 *
 * node begin -> must be a node that points to the very first valid
 * element in the tree, or end if no elements exist.
 *
 * node end -> must be a node that points to just past the very last
 * valid element.
 *
 * node find(V v) -> returns a node that points to the element that
 * contains v, or end if the element doesn't exist.
 *
 * node remove(node p) -> removes the given element from the tree,
 * returns the next valid element or end if p was last in the tree.
 *
 * void clear() -> removes all elements from the tree, sets count to 0.
 */
class TreeSet(V, alias ImplTemp = RBNoUpdatesTree, alias compareFunction = DefaultCompare) : Set!(V)
{
    version(unittest)
    {
        private enum doUnittest = isIntegral!V;

        bool arrayEqual(V[] arr)
        {
            if(length == arr.length)
            {
                foreach(v; arr)
                {
                    if(!contains(v))
                        return false;
                }
                return true;
            }
            return false;
        }
    }
    else
    {
        private enum doUnittest = false;
    }

    /**
     * convenience alias.
     */
    alias ImplTemp!(V, compareFunction) Impl;

    private Impl _tree;

    /**
     * A cursor for elements in the tree
     */
    struct cursor
    {
        private Impl.Node ptr;
        private bool _empty = false;

        /**
         * get the value in this element
         */
        @property V front()
        {
            assert(!_empty, "Attempting to read the value of an empty cursor of " ~ TreeSet.stringof);
            return ptr.value;
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
            assert(!_empty, "Attempting to popFront() an empty cursor of " ~ TreeSet.stringof);
            _empty = true;
            ptr = ptr.next;
        }

        /**
         * length of the cursor range, which is always either 0 or 1.
         */
        @property size_t length()
        {
            return _empty ? 0 : 1;
        }

        /**
         * opIndex costs nothing, and it allows more algorithms to accept
         * cursors.
         */
        @property V opIndex(size_t idx)
        {
            assert(idx < length, "Attempt to access invalid index on cursor");
            return ptr.value;
        }

        /**
         * trivial save implementation to implement forward range
         * functionality.
         */
        @property cursor save()
        {
            return this;
        }

        /**
         * compare two cursors for equality
         */
        bool opEquals(ref const cursor it) const
        {
            return it.ptr is ptr;
        }
        /*
         * TODO: uncomment this when compiler is sane!
         * compare two cursors for equality
         */
        /*bool opEquals(const cursor it) const
        {
            return it.ptr is ptr;
        }*/
    }

    static if(doUnittest) unittest
    {
        
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        auto cu = ts.elemAt(3);
        assert(!cu.empty);
        assert(cu.front == 3);
        cu.popFront();
        assert(cu.empty);
        assert(ts.arrayEqual([1, 2, 3, 4, 5]));
    }


    /**
     * A range that can be used to iterate over the elements in the tree.
     */
    struct range
    {
        private Impl.Node _begin;
        private Impl.Node _end;

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
            c.ptr = _begin;
            c._empty = empty;
            return c;
        }

        /**
         * Get a cursor to the end element in the range
         */
        @property cursor end()
        {
            cursor c;
            c.ptr = _end;
            c._empty = true;
            return c;
        }

        /**
         * Get the first value in the range
         */
        @property V front()
        {
            assert(!empty, "Attempting to read front of an empty range cursor of " ~ TreeSet.stringof);
            return _begin.value;
        }

        /**
         * Get the last value in the range
         */
        @property V back()
        {
            assert(!empty, "Attempting to read the back of an empty range of " ~ TreeSet.stringof);
            return _end.prev.value;
        }

        /**
         * Move the front of the range ahead one element
         */
        void popFront()
        {
            assert(!empty, "Attempting to popFront() an empty range of " ~ TreeSet.stringof);
            _begin = _begin.next;
        }

        /**
         * Move the back of the range to the previous element
         */
        void popBack()
        {
            assert(!empty, "Attempting to popBack() an empty range of " ~ TreeSet.stringof);
            _end = _end.prev;
        }

        /**
         * Implement save as required by forward ranges now.
         */
        @property range save()
        {
            return this;
        }
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        auto r = ts[];
        assert(std.algorithm.equal(r, cast(V[])[1, 2, 3, 4, 5]));
        assert(r.front == ts.begin.front);
        assert(r.back != r.front);
        auto oldfront = r.front;
        auto oldback = r.back;
        r.popFront();
        r.popBack();
        assert(r.front != r.back);
        assert(r.front != oldfront);
        assert(r.back != oldback);

        auto b = r.begin;
        assert(!b.empty);
        assert(b.front == r.front);
        auto e = r.end;
        assert(e.empty);
    }


    /**
     * Determine if a cursor belongs to the collection
     */
    bool belongs(cursor c)
    {
        // rely on the implementation to tell us
        return _tree.belongs(c.ptr);
    }

    /**
     * Determine if a range belongs to the collection
     */
    bool belongs(range r)
    {
        return _tree.belongs(r._begin) && (r.empty || _tree.belongs(r._end));
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        auto cu = ts.elemAt(3);
        assert(cu.front == 3);
        assert(ts.belongs(cu));
        auto r = ts[ts.begin..cu];
        assert(ts.belongs(r));

        auto ts2 = ts.dup();
        assert(!ts2.belongs(cu));
        assert(!ts2.belongs(r));
    }

    /**
     * Iterate through elements of the TreeSet, specifying which ones to
     * remove.
     *
     * Use like this:
     * -------------
     * // remove all odd elements
     * foreach(ref doPurge, v; &treeSet.purge)
     * {
     *   doPurge = ((v % 1) == 1);
     * }
     * -------------
     */
    final int purge(scope int delegate(ref bool doPurge, ref V v) dg)
    {
        auto it = _tree.begin;
        bool doPurge;
        int dgret = 0;
        auto _end = _tree.end; // cache end so it isn't always being generated
        while(it !is _end)
        {
            //
            // don't allow user to change value
            //
            V tmpvalue = it.value;
            doPurge = false;
            if((dgret = dg(doPurge, tmpvalue)) != 0)
                break;
            if(doPurge)
                it = _tree.remove(it);
            else
                it = it.next;
        }
        return dgret;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([0, 1, 2, 3, 4]);
        foreach(ref p, i; &ts.purge)
        {
            p = (i & 1);
        }

        assert(ts.arrayEqual([0, 2, 4]));
    }

    /**
     * iterate over the collection's values
     */
    int opApply(scope int delegate(ref V v) dg)
    {
        int _dg(ref bool doPurge, ref V v)
        {
            return dg(v);
        }
        return purge(&_dg);
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        uint len = 0;
        foreach(i; ts)
        {
            assert(ts.contains(i));
            ++len;
        }
        assert(len == ts.length);
    }

    /**
     * Instantiate the tree set
     */
    this(V[] initialElems...)
    {
        _tree.setup();
        add(initialElems);
    }

    /**
     * Instantiate the tree set with the given initial elements
     */
    this(Iterator!V initialElems)
    {
        _tree.setup();
        add(initialElems);
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet(1, 2, 3, 4, 5);
        auto ts2 = new TreeSet(ts);
        assert(ts == ts2);
    }

    //
    // for dup
    //
    private this(ref Impl dupFrom)
    {
        _tree.setup();
        dupFrom.copyTo(_tree);
    }

    /**
     * Clear the collection of all elements
     */
    TreeSet clear()
    {
        _tree.clear();
        return this;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet(1, 2, 3, 4, 5);
        //ts.add([1, 2, 3, 4, 5]);
        assert(ts.length == 5);
        ts.clear();
        assert(ts.length == 0);
    }

    /**
     * returns number of elements in the collection
     */
    @property uint length() const
    {
        return _tree.count;
    }

    /**
     * returns a cursor to the first element in the collection.
     */
    @property cursor begin()
    {
        cursor it;
        it.ptr = _tree.begin;
        it._empty = (_tree.count == 0);
        return it;
    }

    /**
     * returns a cursor that points just past the last element in the
     * collection.
     */
    @property cursor end()
    {
        cursor it;
        it.ptr = _tree.end;
        it._empty = true;
        return it;
    }

    /**
     * remove the element pointed at by the given cursor, returning an
     * cursor that points to the next element in the collection.
     *
     * Runs in O(lg(n)) time.
     */
    cursor remove(cursor it)
    {
        if(!it.empty)
        {
            it.ptr = _tree.remove(it.ptr);
        }
        it._empty = (it.ptr == _tree.end);
        return it;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        ts.remove(ts.elemAt(3));
        assert(ts.arrayEqual([1, 2, 4, 5]));
    }

    /**
     * remove all the elements in the given range.
     */
    cursor remove(range r)
    {
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
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        auto r = ts[ts.elemAt(3)..ts.end];
        V[5] buf;
        auto remaining = std.algorithm.copy(ts[ts.begin..ts.elemAt(3)], buf[]);
        ts.remove(r);
        assert(ts.arrayEqual(buf[0..buf.length - remaining.length]));
        assert(!ts.contains(3));
    }

    /**
     * get a slice of all the elements in this collection.
     */
    range opSlice()
    {
        range result;
        result._begin = _tree.begin;
        result._end = _tree.end;
        return result;
    }

    /*
     * Create a range without checks to make sure b and e are part of the
     * collection.
     */
    private range _slice(cursor b, cursor e)
    {
        range result;
        result._begin = b.ptr;
        result._end = e.ptr;
        return result;
    }

    /**
     * get a slice of the elements between the two cursors.
     *
     * We rely on the implementation to verify the ordering of the cursors.  It
     * is possible to determine ordering, even for cursors with equal values,
     * in O(lgn) time.
     */
    range opSlice(cursor b, cursor e)
    {
        int order;
        if(_tree.positionCompare(b.ptr, e.ptr, order) && order <= 0)
        {
            // both cursors are part of the tree map and are correctly ordered.
            return _slice(b, e);
        }
        throw new Exception("invalid slice parameters to " ~ TreeSet.stringof);
    }

    /**
     * Create a slice based on values instead of based on cursors.
     *
     * b must be <= e, and b and e must both match elements in the collection.
     * Note that e cannot match end, so in order to get *all* the elements, you
     * must call the opSlice(V, end) version of the function.
     *
     * Note, a valid slice is only returned if both b and e exist in the
     * collection.
     *
     * runs in O(lgn) time.
     */
    range opSlice(V b, V e)
    {
        if(compareFunction(b, e) <= 0)
        {
            auto belem = elemAt(b);
            auto eelem = elemAt(e);
            // note, no reason to check for whether belem and eelem are members
            // of the tree, we just verified that!
            if(!belem.empty && !eelem.empty)
            {
                return _slice(belem, eelem);
            }
        }
        throw new Exception("invalid slice parameters to " ~ TreeSet.stringof);
    }

    /**
     * Slice between a value and a cursor.
     *
     * runs in O(lgn) time.
     */
    range opSlice(V b, cursor e)
    {
        auto belem = elemAt(b);
        if(!belem.empty)
        {
            int order;
            if(_tree.positionCompare(belem.ptr, e.ptr, order) && order <= 0)
            {
                return _slice(belem, e);
            }
        }
        throw new Exception("invalid slice parameters to " ~ TreeSet.stringof);
    }

    /**
     * Slice between a cursor and a value
     *
     * runs in O(lgn) time.
     */
    range opSlice(cursor b, V e)
    {
        auto eelem = elemAt(e);
        if(!eelem.empty)
        {
            int order;
            if(_tree.positionCompare(b.ptr, eelem.ptr, order) && order <= 0)
            {
                return _slice(b, eelem);
            }
        }
        throw new Exception("invalid slice parameters to " ~ TreeSet.stringof);
    }

    static if (doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        auto fr = ts[];
        fr.popFront();
        fr.popFront();
        auto cu = fr.begin;
        auto r = ts[ts.begin..cu];
        auto r2 = ts[cu..ts.end];
        foreach(x; r2)
        {
            assert(std.algorithm.find(r, x).empty);
        }
        assert(walkLength(r) + walkLength(r2) == ts.length);

        bool exceptioncaught = false;
        try
        {
            ts[cu..cu];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(!exceptioncaught);

        // test slicing using improperly ordered cursors
        exceptioncaught = false;
        try
        {
            auto cu2 = cu;
            cu2.popFront();
            ts[cu2..cu];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(exceptioncaught);

        // test slicing using values
        assert(std.algorithm.equal(ts[2..4], cast(V[])[2, 3]));

        assert(std.algorithm.equal(ts[ts.elemAt(2)..4], cast(V[])[2, 3]));
        assert(std.algorithm.equal(ts[2..ts.elemAt(4)], cast(V[])[2, 3]));

        // test slicing using improperly ordered values
        exceptioncaught = false;
        try
        {
            ts[4..2];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(exceptioncaught);

        // test slicing using improperly ordered cursors
        exceptioncaught = false;
        try
        {
            ts[ts.elemAt(4)..2];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(exceptioncaught);

        // test slicing using improperly ordered cursors
        exceptioncaught = false;
        try
        {
            ts[4..ts.elemAt(2)];
        }
        catch(Exception)
        {
            exceptioncaught = true;
        }
        assert(exceptioncaught);

    }

    /**
     * find the instance of a value in the collection.  Returns end if the
     * value is not present.
     *
     * Runs in O(lg(n)) time.
     */
    cursor elemAt(V v)
    {
        cursor it;
        it.ptr = _tree.find(v);
        it._empty = it.ptr is _tree.end;
        return it;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        assert(ts.elemAt(6).empty);
    }


    /**
     * Returns true if the given value exists in the collection.
     *
     * Runs in O(lg(n)) time.
     */
    bool contains(V v)
    {
        return !elemAt(v).empty;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        assert(ts.contains(3));
        ts.remove(3);
        assert(!ts.contains(3));
    }

    /**
     * Removes the element that has the value v.  Returns true if the value
     * was present and was removed.
     *
     * Runs in O(lg(n)) time.
     */
    TreeSet remove(V v)
    {
        remove(elemAt(v));
        return this;
    }

    /**
     * Removes the element that has the value v.  Returns true if the value
     * was present and was removed.
     *
     * Runs in O(lg(n)) time.
     */
    TreeSet remove(V v, out bool wasRemoved)
    {
        auto it = elemAt(v);
        if((wasRemoved = !it.empty) is true)
            remove(it);
        return this;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        bool wasRemoved;
        ts.remove(1, wasRemoved);
        assert(ts.arrayEqual([2, 3, 4, 5]));
        assert(wasRemoved);
        ts.remove(10, wasRemoved);
        assert(ts.arrayEqual([2, 3, 4, 5]));
        assert(!wasRemoved);
        ts.remove(4);
        assert(ts.arrayEqual([2, 3, 5]));
    }

    /**
     * Adds a value to the collection.
     * Returns true.
     *
     * Runs in O(lg(n)) time.
     */
    TreeSet add(V v)
    {
        _tree.add(v);
        return this;
    }

    /**
     * Adds a value to the collection.
     * Returns true.
     *
     * Runs in O(lg(n)) time.
     */
    TreeSet add(V v, out bool wasAdded)
    {
        wasAdded = _tree.add(v);
        return this;
    }

    /**
     * Adds all the values from enumerator to the collection.
     *
     * Runs in O(m lg(n)) time, where m is the number of elements in
     * enumerator.
     */
    TreeSet add(Iterator!(V) it)
    {
        auto tr = cast(TreeSet)it;
        if(tr && !length)
        {
            tr._tree.copyTo(_tree);
        }
        else
        {
            foreach(v; it)
                _tree.add(v);
        }
        return this;
    }

    /**
     * Adds all the values from enumerator to the collection.
     *
     * Runs in O(m lg(n)) time, where m is the number of elements in
     * enumerator.
     */
    TreeSet add(Iterator!(V) it, out uint numAdded)
    {
        uint origlength = length;
        add(it);
        numAdded = length - origlength;
        return this;
    }

    /**
     * Adds all the values from array to the collection.
     *
     * Runs in O(m lg(n)) time, where m is the number of elements in
     * array.
     */
    TreeSet add(V[] array)
    {
        foreach(v; array)
            _tree.add(v);
        return this;
    }

    /**
     * Adds all the values from array to the collection.
     *
     * Runs in O(m lg(n)) time, where m is the number of elements in
     * array.
     */
    TreeSet add(V[] array, out uint numAdded)
    {
        uint origlength = length;
        foreach(v; array)
            _tree.add(v);
        numAdded = length - origlength;
        return this;
    }

    static if(doUnittest) unittest
    {
        // add single element
        bool wasAdded = false;
        auto ts = new TreeSet;
        ts.add(1);
        ts.add(2, wasAdded);
        assert(ts.length == 2);
        assert(ts.arrayEqual([1, 2]));
        assert(wasAdded);

        // add other collection
        uint numAdded = 0;
        // need to add duplicate, adding self is not allowed.
        auto ts2 = ts.dup();
        ts2.add(3);
        ts.add(ts2, numAdded);
        ts.add(ts.dup());
        bool caughtexception = false;
        try
        {
            ts.add(ts);
        }
        catch(Exception)
        {
            caughtexception = true;
        }
        // should always be able to add self
        assert(!caughtexception);

        assert(ts.arrayEqual([1, 2, 3]));
        assert(numAdded == 1);

        // add array
        ts.clear();
        ts.add([1, 2, 3, 4, 5]);
        ts.add([3, 4, 5, 6, 7], numAdded);
        assert(ts.arrayEqual([1, 2, 3, 4, 5, 6, 7]));
        assert(numAdded == 2);
    }

    /**
     * Return a duplicate treeset containing all the elements in this tree
     * set.
     */
    TreeSet dup()
    {
        return new TreeSet(_tree);
    }

    /**
     * Remove all the elements that match in the subset
     */
    TreeSet remove(Iterator!(V) subset)
    {
        foreach(v; subset)
            remove(v);
        return this;
    }

    /**
     * Remove all the elements that match in the subset.  Sets numRemoved to
     * number of elements removed.
     *
     * returns this.
     */
    TreeSet remove(Iterator!(V) subset, out uint numRemoved)
    {
        uint origLength = length;
        remove(subset);
        numRemoved = origLength - length;
        return this;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([0, 1, 2, 3, 4, 5]);
        auto ai = new ArrayIterator!V([0, 2, 4, 6, 8]);
        uint numRemoved;
        ts.remove(ai, numRemoved);
        assert(ts.arrayEqual([1, 3, 5]));
        assert(numRemoved == 3);
        ai = new ArrayIterator!V([1, 3]);
        ts.remove(ai);
        assert(ts.arrayEqual([5]));
    }

    /**
     * Remove all the elements that do NOT match in the subset.
     *
     * returns this.
     */
    TreeSet intersect(Iterator!(V) subset)
    {
        _tree.intersect(subset);
        return this;
    }

    /**
     * Remove all the elements that do NOT match in the subset.  Sets
     * numRemoved to number of elements removed.
     *
     * returns this.
     */
    TreeSet intersect(Iterator!(V) subset, out uint numRemoved)
    {
        numRemoved = _tree.intersect(subset);
        return this;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([0, 1, 2, 3, 4, 5]);
        auto ai = new ArrayIterator!V([0, 2, 4, 6, 8]);
        uint numRemoved;
        ts.intersect(ai, numRemoved);
        assert(ts.arrayEqual([0, 2, 4]));
        assert(numRemoved == 3);
        ai = new ArrayIterator!V([0, 4]);
        ts.intersect(ai);
        assert(ts.arrayEqual([0, 4]));
    }

    /**
     * Compare this set with another set.  Returns true if both sets have the
     * same length and every element in one set exists in the other set.
     *
     * If o is null or not a Set, return 0.
     */
    override bool opEquals(Object o)
    {
        if(o !is null)
        {
            auto s = cast(Set!(V))o;
            if(s !is null && s.length == length)
            {
                auto ts = cast(TreeSet)o;
                auto _end = end;
                if(ts !is null)
                {
                    if(length != ts.length)
                        return false;

                    //
                    // since we know treesets are sorted, compare elements
                    // using cursors.  This makes opEquals O(n) operation,
                    // versus O(n lg(n)) for other set types.
                    //
                    auto c1 = _tree.begin;
                    auto c2 = ts._tree.begin;
                    while(c1 !is _end.ptr)
                    {
                        if(c1.value != c2.value)
                            return false;
                        c1 = c1.next;
                        c2 = c2.next;
                    }
                    return true;
                }
                else
                {
                    foreach(elem; s)
                    {
                        //
                        // less work then calling contains(), which builds end
                        // each time
                        //
                        if(elemAt(elem).empty)
                            return false;
                    }

                    //
                    // equal
                    //
                    return true;
                }
            }
        }
        //
        // no comparison possible.
        //
        return false;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        assert(ts == ts.dup());
    }

    /**
     * get the most convenient element in the set.  This is the element that
     * would be iterated first.  Therefore, calling remove(get()) is
     * guaranteed to be less than an O(n) operation.
     */
    V get()
    {
        return begin.front;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        ts.add([1, 2, 3, 4, 5]);
        assert(!std.algorithm.find([1, 2, 3, 4, 5], ts.get()).empty);
    }

    /**
     * Remove the most convenient element from the set, and return its value.
     * This is equivalent to remove(get()), except that only one lookup is
     * performed.
     */
    V take()
    {
        auto c = begin;
        auto retval = c.front;
        remove(c);
        return retval;
    }

    static if(doUnittest) unittest
    {
        auto ts = new TreeSet;
        V[] aa = [1, 2, 3, 4, 5];
        ts.add(aa);
        auto x = ts.take();
        assert(!std.algorithm.find([1, 2, 3, 4, 5], x).empty);
        // remove x from the original array, and check for equality
        assert(ts.arrayEqual(std.algorithm.partition!((V a) {return a == x;})(aa)));
    }
}

unittest
{
    // declare the Link list types that should be unit tested.
    TreeSet!ubyte  ts1;
    TreeSet!byte   ts2;
    TreeSet!ushort ts3;
    TreeSet!short  ts4;
    TreeSet!uint   ts5;
    TreeSet!int    ts6;
    TreeSet!ulong  ts7;
    TreeSet!long   ts8;

    // ensure that reference types can be used
    TreeSet!(uint*) al9;
    class C {}
    TreeSet!C al10;
}
