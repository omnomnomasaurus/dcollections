/*********************************************************
   Copyright: (C) 2008 by Steven Schveighoffer.
              All rights reserved

   License: $(LICENSE)

**********************************************************/
module dcollections.ArrayList;
public import dcollections.model.List,
       dcollections.model.Keyed;

/***
 * This class is a wrapper around an array which provides the necessary
 * implemenation to implement the List interface
 *
 * Adding or removing any element invalidates all cursors.
 *
 * This class serves as the gateway between builtin arrays and dcollection
 * classes.  You can construct an ArrayList with a builtin array serving as
 * the storage, and you can access the ArrayList as an array with the asArray
 * function.  Neither of these make copies of the array, so you can continue
 * to use the array in both forms.
 */
class ArrayList(V) : List!(V), Keyed!(uint, V)
{
    private V[] _array;
    private uint _mutation;
    //
    // A note about the parent and ancestor.  The parent is the array list
    // that this was a slice of.  The ancestor is the highest parent in the
    // lineage.  If a slice is added to, it now creates its own array, and
    // becomes its own ancestor.  It is no longer in the lineage.  However, we
    // do not set _parent to null, because it is needed for any slices that
    // were subslices of the slice.  Those should not be invalidated, and they
    // need to have a chain to their ancestor.  So if you add data to a slice,
    // it becomes an empty link in the original lineage chain.
    //
    private ArrayList!(V) _parent;
    private ArrayList!(V) _ancestor;

    private class Purger : PurgeKeyedIterator!(uint, V)
    {
        final int opApply(int delegate(ref bool doRemove, ref V value) dg)
        {
            return _apply(dg, _begin, _end);
        }

        final int opApply(int delegate(ref bool doRemove, ref uint key, ref V value) dg)
        {
            return _apply(dg, _begin, _end);
        }
    }

    private Purger _purger;

    /**
     * The array cursor is exactly like a pointer into the array.  The only
     * difference between an ArrayList cursor and a pointer is that the
     * ArrayList cursor provides the value property which is common
     * throughout the collection package.
     *
     * All operations on the cursor are O(1)
     */
    struct cursor
    {
        private V *ptr;
        
        /**
         * get the value pointed to
         */
        V value()
        {
            return *ptr;
        }

        /**
         * set the value pointed to
         */
        V value(V v)
        {
            return (*ptr = v);
        }

        /**
         * increment this cursor, returns what the cursor was before
         * incrementing.
         */
        cursor opPostInc()
        {
            cursor tmp = *this;
            ptr++;
            return tmp;
        }

        /**
         * decrement this cursor, returns what the cursor was before
         * decrementing.
         */
        cursor opPostDec()
        {
            cursor tmp = *this;
            ptr--;
            return tmp;
        }

        /**
         * increment the cursor by the given amount.
         */
        cursor opAddAssign(int inc)
        {
            ptr += inc;
            return *this;
        }

        /**
         * decrement the cursor by the given amount.
         */
        cursor opSubAssign(int inc)
        {
            ptr -= inc;
            return *this;
        }

        /**
         * return a cursor that is inc elements beyond this cursor.
         */
        cursor opAdd(int inc)
        {
            cursor result = *this;
            result.ptr += inc;
            return result;
        }

        /**
         * return a cursor that is inc elements before this cursor.
         */
        cursor opSub(int inc)
        {
            cursor result = *this;
            result.ptr -= inc;
            return result;
        }

        /**
         * return the number of elements between this cursor and the given
         * cursor.  If it points to a later element, the result is negative.
         */
        int opSub(cursor it)
        {
            return ptr - it.ptr;
        }

        /**
         * compare two cursors.
         */
        int opCmp(cursor it)
        {
            if(ptr < it.ptr)
                return -1;
            if(ptr > it.ptr)
                return 1;
            return 0;
        }

        /**
         * compare two cursors for equality.
         */
        bool opEquals(cursor it)
        {
            return ptr is it.ptr;
        }
    }

    /**
     * create a new empty ArrayList
     */
    this()
    {
        _purger = new Purger();
        _ancestor = this;
        _parent = null;
    }

    /**
     * Use an array as the backing storage.  This does not duplicate the
     * array.  Use new ArrayList(storage.dup) to make a distinct copy.
     */
    this(V[] storage)
    {
        this();
        _array = storage;
    }

    private this(ArrayList!(V) parent, cursor s, cursor e)
    {
        _parent = parent;
        _ancestor = parent._ancestor;
        _mutation = parent._mutation;
        checkMutation();
        uint ib = s - parent._begin;
        uint ie = e - s;
        _array = parent._array[ib..ie];
    }

    /**
     * clear the container of all values
     */
    ArrayList!(V) clear()
    {
        if(isAncestor)
        {
            _array = null;
            _mutation++;
        }
        else
        {
            remove(_begin, _end);
        }
        return this;
    }

    /**
     * returns true because this supports length
     */
    bool supportsLength()
    {
        return true;
    }

    /**
     * return the number of elements in the collection
     */
    uint length()
    {
        checkMutation();
        return _array.length;
    }

    /**
     * return a cursor that points to the first element in the list.
     */
    final cursor begin()
    {
        checkMutation();
        return _begin;
    }

    private cursor _begin()
    {
        cursor it;
        it.ptr = _array.ptr;
        return it;
    }

    /**
     * return a cursor that points to just beyond the last element in the
     * list.
     */
    final cursor end()
    {
        checkMutation();
        return _end;
    }

    private cursor _end()
    {
        cursor it;
        it.ptr = _array.ptr + _array.length;
        return it;
    }


    private int _apply(int delegate(ref bool, ref uint, ref V) dg, cursor start, cursor last)
    {
        return _apply(dg, start, last, _begin);
    }

    private int _apply(int delegate(ref bool, ref uint, ref V) dg, cursor start, cursor last, cursor reference)
    {
        if(isAncestor)
        {
            cursor i = start;
            cursor nextGood = start;
            cursor endref = _end;

            int dgret;
            bool doRemove;

            //
            // loop before removal
            //
            for(; dgret == 0 && i < last; i++, nextGood++)
            {
                doRemove = false;
                uint key = i - reference;
                if((dgret = dg(doRemove, key, *i.ptr)) == 0)
                {
                    if(doRemove)
                    {
                        //
                        // first removal
                        //
                        _mutation++;
                        i++;
                        break;
                    }
                }
            }

            //
            // loop after first removal
            //
            if(nextGood != i)
            {
                for(; i < endref; i++, nextGood++)
                {
                    doRemove = false;
                    uint key = i - reference;
                    if(i >= last || dgret != 0 || (dgret = dg(doRemove, key, *i.ptr)) != 0)
                    {
                        //
                        // not calling dg any more
                        //
                        nextGood.value = i.value;
                    }
                    else if(doRemove)
                    {
                        //
                        // dg requested a removal
                        //
                        nextGood--;
                    }
                    else
                    {
                        //
                        // dg did not request a removal
                        //
                        nextGood.value = i.value;
                    }
                }
            }

            //
            // shorten the length
            //
            if(nextGood != endref)
            {
                _array.length = nextGood - _begin;
                return endref - nextGood;
            }
            return dgret;
        }
        else
        {
            //
            // use the ancestor to perform the apply, then adjust the array
            // accordingly.
            //
            checkMutation();
            auto p = nextParent;
            auto origLength = p._array.length;
            p._apply(dg, start, last, _begin);
            auto numRemoved = origLength - p._array.length;
            if(numRemoved > 0)
            {
                _array = _array[0..$-numRemoved];
                _mutation = _ancestor._mutation;
            }
        }
    }

    private int _apply(int delegate(ref bool, ref V) dg, cursor start, cursor last)
    {
        int _dg(ref bool b, ref uint k, ref V v)
        {
            return dg(b, v);
        }
        return _apply(&_dg, start, last);
    }

    private void checkMutation()
    {
        if(_mutation != _ancestor._mutation)
            throw new Exception("underlying ArrayList changed");
    }

    final bool isAncestor()
    {
        return _ancestor is this;
    }

    //
    // Get the next parent in the lineage.  Skip over any parents that do not
    // share our ancestor, they are not part of the lineage any more.
    //
    private ArrayList!(V) nextParent()
    {
        auto retval = _parent;
        while(retval._ancestor !is _ancestor)
            retval = retval._parent;
        return retval;
    }

    /**
     * remove all the elements from start to last, not including the element
     * pointed to by last.  Returns a valid cursor that points to the
     * element last pointed to.
     *
     * Runs in O(n) time.
     */
    final cursor remove(cursor start, cursor last)
    {
        if(isAncestor)
        {
            int check(ref bool b, ref V)
            {
                b = true;
                return 0;
            }
            _apply(&check, start, last);
        }
        else
        {
            checkMutation();
            nextParent.remove(start, last);
            _array = _array[0..($ - (last - start))];
            _mutation = _ancestor._mutation;
        }
        return start;
    }

    /**
     * remove the element pointed to by elem.  Equivalent to remove(elem, elem
     * + 1).
     *
     * Runs in O(n) time
     */
    final cursor remove(cursor elem)
    {
        return remove(elem, elem + 1);
    }

    /**
     * remove an element with the specific value.  This is an O(n)
     * operation.  If the collection has duplicate instances, the first
     * element that matches is removed.
     *
     * returns this.
     *
     * Sets wasRemoved to true if the element existed and was removed.
     */
    ArrayList!(V) remove(V v, ref bool wasRemoved)
    {
        auto it = find(v);
        if(it == _end)
            wasRemoved = false;
        else
        {
            remove(it);
            wasRemoved = true;
        }
        return this;
    }

    /**
     * remove an element with the specific value.  This is an O(n)
     * operation.  If the collection has duplicate instances, the first
     * element that matches is removed.
     *
     * returns this.
     */
    final ArrayList!(V) remove(V v)
    {
        bool ignored;
        return remove(v, ignored);
    }

    /**
     * same as find(v), but start at given position.
     */
    final cursor find(cursor it, V v)
    {
        return _find(it, _end, v);
    }

    // same as find(v), but search only a given range at given position.
    private cursor _find(cursor it, cursor last,  V v)
    {
        checkMutation();
        while(it < last && it.value != v)
            it++;
        return it;
    }

    /**
     * find the first occurrence of an element in the list.  Runs in O(n)
     * time.
     */
    final cursor find(V v)
    {
        return _find(_begin, _end, v);
    }

    /**
     * returns true if the collection contains the value.  Runs in O(n) time.
     */
    final bool contains(V v)
    {
        return find(v) < _end;
    }

    /**
     * remove the element at the given index.  Runs in O(n) time.
     */
    final ArrayList!(V) removeAt(uint key, ref bool wasRemoved)
    {
        if(key > length)
        {
            wasRemoved = false;
        }
        else
        {
            remove(_begin + key);
            wasRemoved = true;
        }
        return this;
    }

    /**
     * remove the element at the given index.  Runs in O(n) time.
     */
    final ArrayList!(V) removeAt(uint key)
    {
        bool ignored;
        return removeAt(key, ignored);
    }

    /**
     * get the value at the given index.
     */
    final V opIndex(uint key)
    {
        checkMutation();
        return _array[key];
    }

    /**
     * set the value at the given index.
     */
    final V opIndexAssign(V value, uint key)
    {
        checkMutation();
        //
        // does not change mutation because 
        return _array[key] = value;
    }

    /**
     * set the value at the given index
     */
    ArrayList!(V) set(uint key, V value, ref bool wasAdded)
    {
        this[key] = value;
        wasAdded = false;
        return this;
    }

    /**
     * set the value at the given index
     */
    ArrayList!(V) set(uint key, V value)
    {
        this[key] = value;
        return this;
    }

    /**
     * iterate over the collection
     */
    final int opApply(int delegate(ref V value) dg)
    {
        int retval;
        cursor endref = end; // call checkmutation
        for(cursor i = _begin; i != endref; i++)
        {
            if((retval = dg(*i.ptr)) != 0)
                break;
        }
        return retval;
    }

    /**
     * iterate over the collection with key and value
     */
    final int opApply(int delegate(ref uint key, ref V value) dg)
    {
        int retval = 0;
        auto reference = begin; // call checkmutation
        auto endref = _end;
        for(cursor i = reference; i != endref; i++)
        {
            uint key = i - reference;
            if((retval = dg(key, *i.ptr)) != 0)
                break;
        }
        return retval;
    }

    /**
     * gives an object that can be used to purge the list that provides index
     * information as well as value information.
     */
    final PurgeKeyedIterator!(uint, V) purger()
    {
        return _purger;
    }

    /**
     * returns true if the given index is valid
     *
     * Runs in O(1) time
     */
    final bool containsKey(uint key)
    {
        return key < length;
    }

    /**
     * add the given value to the end of the list.  Always returns true.
     */
    final ArrayList!(V) add(V v, ref bool wasAdded)
    {
        //
        // append to this array.  Reset the ancestor to this, because now we
        // are dealing with a new array.
        //
        if(isAncestor)
        {
            _array ~= v;
            _mutation++;
        }
        else
        {
            _ancestor = this;
            //
            // ensure that we don't just do an append.
            //
            _array = _array ~ v;

            //
            // no need to change the mutation, we are a new ancestor.
            //
        }

        // always succeeds
        wasAdded = true;
        return this;
    }

    /**
     * add the given value to the end of the list.
     */
    final ArrayList!(V) add(V v)
    {
        bool ignored;
        return add(v, ignored);
    }

    /**
     * adds all elements from the given iterator to the end of the list.
     */
    final ArrayList!(V) add(Iterator!(V) coll)
    {
        uint ignored;
        return add(coll, ignored);
    }

    /**
     * adds all elements from the given iterator to the end of the list.
     */
    final ArrayList!(V) add(Iterator!(V) coll, ref uint numAdded)
    {
        auto al = cast(ArrayList!(V))coll;
        if(al)
        {
            //
            // optimized case
            //
            return add(al._array, numAdded);
        }

        //
        // generic case
        //
        checkMutation();
        if(coll.supportsLength)
        {
            numAdded = coll.length;
            if(numAdded > 0)
            {
                int i = _array.length;
                if(isAncestor)
                {
                    _array.length = _array.length + numAdded;
                }
                else
                {
                    _ancestor = this;
                    auto new_array = new V[_array.length + numAdded];
                    new_array[0.._array.length] = _array[];

                }
                foreach(v; coll)
                    _array [i++] = v;
                _mutation++;
            }
        }
        else
        {
            auto origlength = _array.length;
            bool firstdone = false;
            foreach(v; coll)
            {
                if(!firstdone)
                {
                    //
                    // trick to get firstdone set to true, because wasAdded is
                    // always set to true.
                    //
                    add(v, firstdone);
                }
                else
                    _array ~= v;
            }
            numAdded = _array.length - origlength;
        }
        return this;
    }


    /**
     * appends the array to the end of the list
     */
    final ArrayList!(V) add(V[] array)
    {
        uint ignored;
        return add(array, ignored);
    }

    /**
     * appends the array to the end of the list
     */
    final ArrayList!(V) add(V[] array, ref uint numAdded)
    {
        checkMutation();
        numAdded = array.length;
        if(array.length)
        {
            if(isAncestor)
            {
                _array ~= array;
                _mutation++;
            }
            else
            {
                _ancestor = this;
                _array = _array ~ array;
            }
        }
        return this;
    }

    /**
     * append another list to the end of this list
     */
    final ArrayList!(V) opCatAssign(List!(V) rhs)
    {
        return add(rhs);
    }

    /**
     * append an array to the end of this list
     */
    final ArrayList!(V) opCatAssign(V[] array)
    {
        return add(array);
    }

    /**
     * returns a concatenation of the array list and another list.
     */
    final ArrayList!(V) opCat(List!(V) rhs)
    {
        return dup.add(rhs);
    }

    /**
     * returns a concatenation of the array list and an array.
     */
    final ArrayList!(V) opCat(V[] array)
    {
        checkMutation();
        return new ArrayList!(V)(_array ~ array);
    }

    /**
     * returns a concatenation of the array list and an array.
     */
    final ArrayList!(V) opCat_r(V[] array)
    {
        checkMutation();
        return new ArrayList!(V)(array ~ _array);
    }

    /**
     * returns the number of instances of the given element value
     *
     * Runs in O(n) time.
     */
    final uint count(V v)
    {
        uint instances = 0;
        foreach(x; this)
            if(v == x)
                instances++;
        return instances;
    }

    /**
     * removes all the instances of the given element value
     *
     * Runs in O(n) time.
     */
    final ArrayList!(V) removeAll(V v, ref uint numRemoved)
    {
        auto origLength = length;
        foreach(ref b, x; _purger)
        {
            b = (x == v);
        }
        numRemoved = length - origLength;
        return this;
    }

    /**
     * removes all the instances of the given element value
     *
     * Runs in O(n) time.
     */
    final ArrayList!(V) removeAll(V v)
    {
        uint ignored;
        return removeAll(v, ignored);
    }

    /**
     * Returns a slice of an array list.  A slice can be used to view
     * elements, remove elements, but cannot be used to add elements.
     *
     * The returned slice begins at index b and ends at, but does not include,
     * index e.
     */
    final ArrayList!(V) opSlice(uint b, uint e)
    {
        return opSlice(_begin + b, _begin + e);
    }

    /**
     * Slice an array given the cursors
     */
    final ArrayList!(V) opSlice(cursor b, cursor e)
    {
        if(e > end || b < _begin) // call checkMutation once
            throw new Exception("slice values out of range");

        //
        // make an array list that is a slice of this array list
        //
        return new ArrayList!(V)(this, b, e);
    }

    /**
     * Returns a copy of an array list
     */
    final ArrayList!(V) dup()
    {
        return new ArrayList!(V)(_array.dup);
    }

    /**
     * get the array that this array represents.  This is NOT a copy of the
     * data, so modifying elements of this array will modify elements of the
     * original ArrayList.  Appending elements from this array will not affect
     * the original array list just like appending to an array will not affect
     * the original.
     */
    final V[] asArray()
    {
        return _array;
    }
}
