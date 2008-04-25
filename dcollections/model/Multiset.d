/*********************************************************
   Copyright: (C) 2008 by Steven Schveighoffer.
              All rights reserved

   License: $(LICENSE)

**********************************************************/
module dcollections.model.Multiset;
public import dcollections.model.Collection,
       dcollections.model.Addable,
       dcollections.model.Multi;

/**
 * A Multiset is a container that allows multiple instances of the same value
 * to be added.
 *
 * It is similar to a list, except there is no requirement for ordering.  That
 * is, elements may not be stored in the order added.
 *
 * Since ordering is not important, the collection can reorder elements on
 * removal or addition to optimize the operations.
 */
interface Multiset(V) : Collection!(V), Addable!(V), Multi!(V)
{
    /**
     * covariant clear (from Collection)
     */
    Multiset!(V) clear();

    /**
     * covariant dup (from Collection)
     */
    Multiset!(V) dup();

    /**
     * Covariant remove (from Collection)
     */
    Multiset!(V) remove(V v);

    /**
     * Covariant remove (from Collection)
     */
    Multiset!(V) remove(V v, ref bool wasRemoved);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(V v);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(V v, ref bool wasAdded);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(Iterator!(V) it);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(Iterator!(V) it, ref uint numAdded);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(V[] array);

    /**
     * Covariant add (from Addable)
     */
    Multiset!(V) add(V[] array, ref uint numAdded);

    /**
     * covariant removeAll (from Multi)
     */
    Multiset!(V) removeAll(V v);

    /**
     * covariant removeAll (from Multi)
     */
    Multiset!(V) removeAll(V v, ref uint numRemoved);
}
