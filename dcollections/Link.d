/*********************************************************
   Copyright: (C) 2008 by Steven Schveighoffer.
              All rights reserved

   License: $(LICENSE)

**********************************************************/
module dcollections.Link;

private import dcollections.DefaultAllocator;

/**
 * Linked-list node that is used in various collection classes.
 */
struct Link(V)
{
    /**
     * convenience alias
     */
    alias Link!(V) *Node;
    Node next;
    Node prev;

    /**
     * the value that is represented by this link node.
     */
    V value;

    /**
     * insert the given node between this node and prev.  This updates all
     * pointers in this, n, and prev.
     *
     * returns this to allow for chaining.
     */
    Node prepend(Node n)
    {
        attach(prev, n);
        attach(n, this);
        return this;
    }

    /**
     * insert the given node between this node and next.  This updates all
     * pointers in this, n, and next.
     *
     * returns this to allow for chaining.
     */
    Node append(Node n)
    {
        attach(n, next);
        attach(this, n);
        return this;
    }

    /**
     * remove this node from the list.  If prev or next is non-null, their
     * pointers are updated.
     *
     * returns this to allow for chaining.
     */
    Node unlink()
    {
        attach(prev, next);
        next = prev = null;
        return this;
    }

    /**
     * link two nodes together.
     */
    static void attach(Node first, Node second)
    {
        if(first)
            first.next = second;
        if(second)
            second.prev = first;
    }

    /**
     * count how many nodes until endNode.
     */
    uint count(Node endNode = null)
    {
        Node x = this;
        uint c = 0;
        while(x !is endNode)
        {
            x = x.next;
            c++;
        }
        return c;
    }

    Node dup(Node delegate(V v) createFunction)
    {
        //
        // create a duplicate of this and all nodes after this.
        //
        auto n = next;
        auto retval = createFunction(value);
        auto cur = retval;
        while(n !is null && n !is this)
        {
            auto x = createFunction(n.value);
            attach(cur, x);
            cur = x;
            n = n.next;
        }
        if(n is this)
        {
            //
            // circular list, complete the circle
            //
            attach(cur, retval);
        }
        return retval;
    }

    Node dup()
    {
        Node _create(V v)
        {
            auto n = new Link!(V);
            n.value = v;
            return n;
        }
        return dup(&_create);
    }
}

/**
 * This struct uses a Link(V) to keep track of a link-list of values.
 *
 * The implementation uses a dummy link node to be the head and tail of the
 * list.  Basically, the list is circular, with the dummy node marking the
 * end/beginning.
 */
struct LinkHead(V, alias Allocator=DefaultAllocator)
{
    /**
     * Convenience alias
     */
    alias Link!(V).Node node;

    /**
     * Convenience alias
     */
    alias Allocator!(Link!(V)) allocator;

    /**
     * The allocator for this link head
     */
    allocator alloc;

    /**
     * The node that denotes the end of the list
     */
    node end; // not a valid node

    /**
     * The number of nodes in the list
     */
    uint count;

    /**
     * we don't use parameters, so alias it to int.
     */
    alias int parameters;

    /**
     * Get the first valid node in the list
     */
    node begin()
    {
        return end.next;
    }

    /**
     * Initialize the list
     */
    void setup(parameters p = 0)
    {
        //end = new node;
        end = allocate();
        node.attach(end, end);
        count = 0;
    }

    /**
     * Remove a node from the list, returning the next node in the list, or
     * end if the node was the last one in the list. O(1) operation.
     */
    node remove(node n)
    {
        count--;
        node retval = n.next;
        n.unlink;
        static if(allocator.freeNeeded)
            alloc.free(n);
        return retval;
    }

    /**
     * Remove all the nodes from first to last.  This is an O(n) operation.
     */
    node remove(node first, node last)
    {
        node.attach(first.prev, last);
        auto n = first;
        while(n !is last)
        {
            auto nx = n.next;
            static if(alloc.freeNeeded)
                alloc.free(n);
            count--;
            n = nx;
        }
        return last;
    }

    /**
     * Insert the given value before the given node.  Use insert(end, v) to
     * add to the end of the list, or to an empty list. O(1) operation.
     */
    node insert(node before, V v)
    {
        count++;
        //return before.prepend(new node(v)).prev;
        return before.prepend(allocate(v)).prev;
    }

    /**
     * Remove all nodes from the list
     */
    void clear()
    {
        node.attach(end, end);
        count = 0;
    }

    void copyTo(ref LinkHead!(V, Allocator) target, bool copyNodes=true)
    {
        target = *this;
        if(copyNodes)
        {
            target.end = end.dup(&target.allocate);
        }
        else
        {
            //
            // set up target like this one
            //
            target.setup();
        }
    }

    private node allocate()
    {
        return alloc.allocate();
    }

    private node allocate(V v)
    {
        auto retval = allocate();
        retval.value = v;
        return retval;
    }
}
