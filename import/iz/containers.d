/**
 * Several implementations of standard containers.
 */
module iz.containers;

import
    core.exception, core.stdc.string;
import
    std.exception, std.string, std.traits, std.conv, std.range.primitives;
import
    iz.memory, iz.types, iz.streams;

version(X86_64)
    version(linux) version = Nux64;

/**
 * Parameterized, GC-free, single dimenssion array.
 *
 * Array(T) implements a single-dimension array of uncollected memory.
 * It internally preallocates the memory to minimize the reallocation fingerprints.
 *
 * Its layout differs from built-in D's dynamic arrays and they cannot be cast as T[]
 * however, most of the slicing operations are possible.
 */
struct Array(T)
{
    private
    {
        size_t _length;
        @NoGc Ptr _elems;
        uint _granularity;
        size_t _blockCount;
        bool initDone;

        final void initLazy() @safe @nogc
        {
            if (initDone)
                return;
            _granularity = 4096;
            _elems = getMem(_granularity);
            initDone = true;
        }

        void setLength(size_t value) @nogc
        {
            debug { assert (_granularity != 0); }

            const size_t newBlockCount = ((value * T.sizeof) / _granularity) + 1;
            if (_blockCount != newBlockCount)
            {
                _blockCount = newBlockCount;
                _elems = cast(T*) reallocMem(_elems, _granularity * _blockCount);
            }
            _length = value;
        }
    }
    protected
    {
        void grow() @nogc
        {
            initLazy;
            setLength(_length + 1);
        }

        void shrink() @nogc
        {
            setLength(_length - 1);
        }

        T* rwPtr(size_t index) pure const nothrow @nogc
        {
            return cast(T*) (_elems + index * T.sizeof);
        }
    }
    public
    {
        /// Constructs the array with a list of T.
        this(E...)(E elements) @nogc
        if (is(Unqual!E == T) || is(T == E))
        {
            initLazy;
            setLength(elements.length);
            foreach(i, element; elements)
                *rwPtr(i) = cast(T) element;
        }

        /// Constructs the array with a D array of T.
        this(E)(E[] elements...) @nogc
        if (is(Unqual!E == T) || is(T == E))
        {
            if (elements.length == 0)
                return;
            initLazy;
            setLength(elements.length);
            foreach (i, element; elements)
                *rwPtr(i) = cast(T) element;
        }

        static if (__traits(compiles, to!T(string.init)) && !isSomeChar!T)
        {
            /// Constructs the array with a literal representation.
            this(string representation)
            {
                initLazy;
                setLength(0);

                class RepresentationException: Exception
                {
                    this()
                    {
                        super("invalid array representation");
                    }
                }

                auto fmtRep = strip(representation);

                if (((fmtRep[0] != '[') & (fmtRep[$-1] != ']')) | (fmtRep.length < 2))
                    throw new RepresentationException;

                if (fmtRep == "[]") return;

                size_t i = 1;
                size_t _from = 1;
                while(i != fmtRep.length)
                {
                    if ((fmtRep[i] ==  ']') | (fmtRep[i] ==  ','))
                    {
                        auto valStr = fmtRep[_from..i];
                        if (valStr == "") throw new RepresentationException;
                        try
                        {
                            T _val = to!T(valStr);
                            grow;
                            *rwPtr(_length-1) = _val;
                        }
                        catch
                            throw new RepresentationException;

                        _from = i;
                        _from++;
                    }
                    ++i;
                }
            }
        }

        ~this()
        {
            if (_elems)
                freeMem(_elems);
        }

        /**
         * Indicates the memory allocation block-size.
         */
        uint granurality() const pure nothrow @safe @nogc
        {
            return _granularity;
        }

        /**
         * Sets the memory allocation block-size.
         * value should be set to 16 or 4096 (the default).
         */
        void granularity(uint value) @nogc
        {
            if (_granularity == value) return;
            if (value < T.sizeof)
            {
                value = 16 * T.sizeof;
            }
            else if (value < 16)
            {
                value = 16;
            }
            else while (_granularity % 16 != 0)
            {
                value--;
            }
            _granularity = value;
            setLength(_length);
        }

        /**
         * Indicates how many block the array is made of.
         */
        size_t blockCount() @nogc
        {
            return _blockCount;
        }

        /**
         * Element count.
         */
        size_t length() const pure nothrow @safe @nogc
        {
            return _length;
        }

        /// ditto
        void length(size_t value) @nogc
        {
            if (value == _length) return;
            initLazy;
            setLength(value);
        }

        /**
         * Pointer to the first element.
         * As it's always assigned It cannot be used to determine if the array is empty.
         */
        Ptr ptr() pure nothrow @nogc
        {
            return _elems;
        }

        /**
         * Returns the string representation of the elements.
         */
        string toString() const
        {
            if (_length == 0) return "[]";
            string result =  "[";
            foreach (immutable i; 0 .. _length-1)
            {
                result ~= format("%s, ", *rwPtr(i));
            }
            return result ~= format("%s]",*rwPtr(_length-1));
        }

        /**
         *  Returns a mutable copy of the array.
         */
        Array!T dup() @nogc
        {
            Array!T result;
            result.length = _length;
            moveMem(result._elems, _elems, _length * T.sizeof);
            return result;
        }

        /**
         * Class operators
         */
        bool opEquals(A)(auto ref A array) const pure @nogc @trusted
        if ((is(Unqual!A == Unqual!(Array!T)) || is(Unqual!(ElementEncodingType!A) == T)))
        {
            if (_length != array.length)
                return false;
            else if (_length == 0 && array.length == 0)
                return true;
            static if (is(Unqual!A == Unqual!(Array!T)))
                return _elems[0.._length * T.sizeof] ==
                  array._elems[0..array._length * T.sizeof];
            else
                return _elems[0.._length * T.sizeof] ==
                  array.ptr[0..array.length];
        }

        /// ditto
        T opIndex(size_t i) const pure @nogc
        {
            return *rwPtr(i);
        }

        /// ditto
        void opIndexAssign(T item, size_t i) @nogc
        {
            *rwPtr(i) = item;
        }

        /// ditto
        int opApply(scope int delegate(ref T) @nogc dg)
        {
            int result = 0;
            foreach (immutable i; 0 .. _length)
            {
                result = dg(*rwPtr(i));
                if (result) break;
            }
            return result;
        }

        /// ditto
        int opApplyReverse(scope int delegate(ref T) @nogc dg)
        {
            int result = 0;
            foreach_reverse (immutable i; 0 .. _length)
            {
                result = dg(*rwPtr(i));
                if (result) break;
            }
            return result;
        }

        /// ditto
        size_t opDollar() pure nothrow @safe @nogc
        {
            return _length;
        }

        /// ditto
        void opAssign(E)(E[] elements) @nogc
        if (is(Unqual!E == T) || is(E == T))
        {
            initLazy;
            setLength(elements.length);
            foreach (i, element; elements)
                *rwPtr(i) = cast(T) element;
        }

        /// ditto
        void opOpAssign(string op, E)(E[] elements) @nogc
        if (is(Unqual!E == T) || is(E == T))
        {
            static if (op == "~")
            {
                initLazy;
                auto old = _length;
                setLength(_length + elements.length);
                moveMem( rwPtr(old), elements.ptr , T.sizeof * elements.length);
            }
            else assert(0, "operator not implemented");
        }

        /// ditto
        void opOpAssign(string op)(T aElement) @nogc
        {
            static if (op == "~")
            {
                grow;
                opIndexAssign(aElement, _length-1);
            }
            else assert(0, "operator not implemented");
        }

        /// Returns the array as a D slice.
        T[] opSlice() const pure @nogc
        {
            return opSlice!true(0, _length);
        }

        /// Returns a slice of the array as a D slice.
        T[] opSlice(bool dSlice = true)(size_t lo, size_t hi) const pure @nogc
        {
            static if (dSlice)
            {
                return (cast(T*) _elems)[lo..hi];
            }
            else
            {
                Array!T result;
                size_t len = hi - lo;
                result._elems = _elems + lo * T.sizeof;
                return result;
            }
        }

        /// ditto
        void opSliceAssign(T value) @nogc
        {
            opSliceAssign(value, 0, _length);
        }
        /// ditto
        void opSliceAssign(T value, size_t lo, size_t hi) @nogc
        {
            foreach(immutable i; lo .. hi)
                *rwPtr(i) = value;
        }
    }
}

unittest
{
    // init-index
    Array!size_t a;
    a.length = 2;
    a[0] = 8;
    a[1] = 9;
    assert( a[0] == 8);
    assert( a[1] == 9);
    assert( a[$-1] == 9);

    auto b = Array!int(0,1,2,3,4,5,6);
    assert( b.length == 7);
    assert( b[$-1] == 6);

    auto floatarr = Array!float ([0.0f, 0.1f, 0.2f, 0.3f, 0.4f]);
    assert( floatarr.length == 5);
    assert( floatarr[0] == 0.0f);
    assert( floatarr[1] == 0.1f);
    assert( floatarr[2] == 0.2f);
    assert( floatarr[3] == 0.3f);
    assert( floatarr[4] == 0.4f);

    // copy-cons
    a = Array!size_t("[]");
    assert(a.length == 0);
    assertThrown(a = Array!size_t("["));
    assertThrown(a = Array!size_t("]"));
    assertThrown(a = Array!size_t("[,]"));
    assertThrown(a = Array!size_t("[,"));
    assertThrown(a = Array!size_t("[0,1,]"));
    assertThrown(a = Array!size_t("[,0,1]"));
    assertThrown(a = Array!size_t("[0,1.874f]"));
    a = Array!size_t("[10,11,12,13]");
    assert(a.length == 4);
    assert(a.toString == "[10, 11, 12, 13]");

    // loops
    int i;
    foreach(float aflt; floatarr)
    {
        float v = i * 0.1f;
        assert( aflt == v);
        i++;
    }
    foreach_reverse(float aflt; floatarr)
    {
        i--;
        float v = i * 0.1f;
        assert( aflt == v);
    }

    // opEquals
    auto nativeArr = [111u, 222u, 333u, 444u, 555u];
    auto arrcpy1 = Array!uint(111u, 222u, 333u, 444u, 555u);
    auto arrcpy2 = Array!uint(111u, 222u, 333u, 444u, 555u);
    assert( arrcpy1 == nativeArr );
    assert( arrcpy2 == nativeArr );
    assert( arrcpy1 == arrcpy2 );
    arrcpy2[0] = 0;
    assert( arrcpy1 != arrcpy2 );
    arrcpy1.length = 3;
    assert( nativeArr != arrcpy1 );
    arrcpy1.length = 0;
    arrcpy2.length = 0;
    assert( arrcpy1 == arrcpy2 );

    // opSlice
    Array!float g0 = floatarr[1..4];
    assert( g0[0] ==  floatarr[1]);
    assert( g0[2] ==  floatarr[3]);
    Array!float g1 = floatarr[];
    assert( g1[0] ==  floatarr[0]);
    assert( g1[4] ==  floatarr[4]);

    // opSliceAssign
    g1[] = 0.123456f;
    assert( g1[0] == 0.123456f);
    assert( g1[3] == 0.123456f);
    g1[0..1] = 0.654321f;
    assert( g1[0] == 0.654321f);
    assert( g1[1] == 0.123456f);
    assert( g1[2] == 0.123456f);

/*
    assert( g0[0] ==  floatarr[1]);
    assert( g0[3] ==  floatarr[4]);
    float[] g1 = floatarr[1..4];
    assert( g1[0] ==  floatarr[1]);
    assert( g1[3] ==  floatarr[4]);
    Array!float g2 = floatarr[]; // auto g2: conflict between op.overloads
    assert( g2[0] ==  floatarr[0]);
    assert( g2[4] ==  floatarr[4]);
    float[] g3 = floatarr[];
    assert( g3[0] ==  floatarr[0]);
    assert( g3[4] ==  floatarr[4]);
    assert(g3[$-1] == floatarr[$-1]);
*/

    // concatenation

    // huge
    a.length = 10_000_000;
    a[$-1] = a.length-1;
    assert(a[a.length-1] == a.length-1);
    a.length = 10;
    a.length = 10_000_000;
    a[$-1] = a.length-1;
    assert(a[$-1] == a.length-1);
}

unittest
{
    Array!char a = "123456";
    assert(a.length == 6);
    assert(a == "123456");
}

/**
 * List interface.
 */
interface List(T)
{
    /// support for the array syntax
    T opIndex(ptrdiff_t i);

    /// support for the array syntax
    void opIndexAssign(T item, size_t i);

    /// support for the foreach operator
    int opApply(int delegate(T) dg);

    /// support for the foreach_reverse operator
    int opApplyReverse(int delegate(T) dg);

    /**
     * Allocates, adds to the back, and returns a new item of type T.
     * Items allocated by this function need to be manually freed before the list destruction.
     */
    static if(is (T == class))
    {
        final T addNewItem(A...)(A a)
        {
            T result = construct!T(a);
            add(result);
            return result;
        }
    }
    else static if(is (T == struct))
    {
        final T * addNewItem(A...)(A a)
        {
            T * result = construct!T(a);
            add(result);
            return result;
        }
    }
    else static if(isPointer!T)
    {
        final T addNewItem(A...)(A a)
        {
            T result = newPtr!(PointerTarget!T)(a);
            add(result);
            return result;
        }
    }

    /**
     * Returns the last item.
     * The value returned is never null.
     */
    T last();

    /**
     * Returns the first item.
     * The value returned is never null.
     */
    T first();

    /**
     * Returns the index of anItem if it's found otherwise -1.
     */
    ptrdiff_t find(T item);

    /**
     * Adds an item at the end of list.
     * Returns 0 when the operation is successful otherwise -1.
     */
    ptrdiff_t add(T item);

    /**
     * Adds someItems at the end of list.
     * Returns the index of the last item when the operation is successful otherwise -1.
     */
    ptrdiff_t add(T[] items);

    /**
     * Inserts an item at the beginning of the list.
     * Returns the index of the last item when the operation is successful otherwise -1.
     */
    ptrdiff_t insert(T item);

    /**
     * Inserts anItem before the one standing at position.
     * If position is greater than count than anItem is added to the end of list.
     * Returns the index of the last item when the operation is successful otherwise -1.
     */
    ptrdiff_t insert(size_t position, T item);

    /**
     * Exchanges anItem1 and anItem2 positions.
     */
    void swapItems(T item1, T item2);

    /**
     * Permutes the index1-th item with the index2-th item.
     */
    void swapIndexes(size_t index1, size_t index2);

    /**
     * Tries to removes anItem from the list.
     */
    bool remove(T item);

    /**
     * Tries to extract the index-nth item from the list.
     * Returns the item or null if the removal fails.
     */
    T extract(size_t index);

    /**
     * Removes the items.
     */
    void clear();

    /**
     * Returns the count of linked item.
     * The value returned is always greater than 0.
     */
    size_t count();

    alias opDollar = count;
}

deprecated("Use the more accurate 'ContiguousList' name")
alias StaticList = ContiguousList;

/**
 * An List implementation, fast to be iterated, slow to be reorganized.
 * Encapsulates an Array!T and interfaces it as a List.
 */
class ContiguousList(T): List!T
{
    private
    {
        @NoGc Array!T _items;
    }
    protected
    {
        final Exception listException()
        {
            return new Exception("List exception");
        }
    }
    public
    {
        ///
        this(A...)(A elements)
        {
            _items = Array!T(elements);
        }
        ~this()
        {
            _items.length = 0;
        }

        T opIndex(ptrdiff_t i)
        {
            return _items[i];
        }

        void opIndexAssign(T item, size_t i)
        {
            _items[i] = item;
        }

        int opApply(int delegate(T) dg)
        {
            int result = 0;
            foreach(immutable i; 0 .. _items.length)
            {
                result = dg(_items[i]);
                if (result) break;
            }
            return result;
        }

        int opApplyReverse(int delegate(T) dg)
        {
            int result = 0;
            foreach_reverse(immutable i; 0 .. _items.length)
            {
                result = dg(_items[i]);
                if (result) break;
            }
            return result;
        }

        void opAssign(T[] items)
        {
            _items.opAssign(items);
        }

        T last()
        {
            return _items[$-1];
        }

        T first()
        {
            return _items[0];
        }

        ptrdiff_t find(T item)
        {
            ptrdiff_t result = -1;
            foreach(immutable i; 0 .. _items.length)
            {
                if (_items[i] == item)
                {
                    result = i;
                    break;
                }
            }
            return result;
        }

        /**
         * Adds an item at the end of the list.
         * To be preferred in this List implementation.
         */
        ptrdiff_t add(T item)
        {
            _items.grow;
            _items[$-1] = item;
            return _items.length - 1;
        }

        ptrdiff_t add(T[] items)
        {
            _items ~= items;
            return _items.length - 1;
        }

        /**
         * Inserts an item at the beginning of the list.
         * To be avoided in this List implementation.
         */
        ptrdiff_t insert(T item)
        {
            _items.grow;
            scope(failure) throw listException;
            memmove(_items.ptr + T.sizeof, _items.ptr, (_items.length - 1) * T.sizeof);
            _items[0] = item;
            return 0;
        }

        /**
         * Inserts an item at the beginning of the list.
         * To be avoided in this List implementation.
         */
        ptrdiff_t insert(size_t position, T item)
        {
            if (position == 0) return insert(item);
            else if (position >= _items.length) return add(item);
            else
            {
                _items.grow;
                scope(failure) throw listException;
                memmove(    _items.ptr + T.sizeof * position + 1,
                            _items.ptr + T.sizeof * position,
                            (_items.length - 1 - position) * T.sizeof);
                _items[position] = item;
                return position;
            }
        }

        void swapItems(T item1, T item2)
        in
        {
            assert(item1 != item2);
        }
        body
        {
            auto i1 = find(item1);
            auto i2 = find(item2);

            if (i1 != -1 && i2 != -1)
            {
                _items[i1] = _items[i2];
                _items[i2] = item1;
            }
        }

        void swapIndexes(size_t index1, size_t index2)
        {
            if (index1 == index2) return;
            if ((index1 >= _items.length) | (index2 >= _items.length)) return;

            auto old = _items[index1];
            _items[index1] = _items[index2];
            _items[index2] = old;
        }

        bool remove(T item)
        {
            auto i = find(item);
            auto result = (i != -1);
            if (result)
                extract(i);
            return result;
        }

        T extract(size_t index)
        {
            T result = _items[index];
            if (index == _items.length-1)
            {
                _items.shrink;
            }
            else if (index == 0)
            {
                scope(failure) throw listException;
                memmove(_items.ptr, _items.ptr + T.sizeof, (_items.length - 1) * T.sizeof);
                _items.shrink;
            }
            else
            {
                Ptr fromPtr = _items.ptr + T.sizeof * index;
                scope(failure) throw listException;
                memmove(fromPtr, fromPtr + T.sizeof, (_items.length - index) * T.sizeof);
                _items.shrink;
            }
            return result;
        }

        void clear()
        {
            _items.setLength(0);
        }

        @property size_t count()
        {
            return _items.opDollar();
        }
    }
}

/**
 * Payload for the dynamic list.
 */
private template dlistPayload(T)
{
    private static const prevOffs = 0;
    private static const nextOffs = size_t.sizeof;
    private static const dataOffs = size_t.sizeof + size_t.sizeof;

    @trusted @nogc nothrow private:

    void* newPld(void* aPrevious, void* aNext, T aData)
    {
        auto result = getMem( 2 * size_t.sizeof + T.sizeof);

        if (result)
        {
            *cast(size_t*)  (result + prevOffs) = cast(size_t) aPrevious;
            *cast(size_t*)  (result + nextOffs) = cast(size_t) aNext;
            *cast(T*)       (result + dataOffs) = aData;
        }
        return result;
    }
    void freePld(void* aPayload)
    in
    {
        assert(aPayload);
    }
    body
    {
        freeMem(aPayload);
    }

    void setPrev(void* aPayload, void* aPrevious)
    in
    {
        assert(aPayload);
    }
    body
    {
        *cast(void**) (aPayload + prevOffs) = aPrevious;
    }

    void setNext(void* aPayload, void* aNext)
    in
    {
        assert(aPayload);
    }
    body
    {
        *cast(void**) (aPayload + nextOffs) = aNext;
    }

    void setData(void* aPayload, T aData)
    in
    {
        assert(aPayload);
    }
    body
    {
        *cast(T*) (aPayload + dataOffs) = aData;
    }

    void* getPrev(void* aPayload)
    {
        version(X86) asm @nogc nothrow
        {
            naked;
            mov     EAX, [EAX + prevOffs];
            ret;
        }
        else version(Win64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RCX + prevOffs];
            ret;
        }
        else version(Nux64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RDI + prevOffs];
            ret;
        }
        else return *cast(void**) (aPayload + prevOffs);
    }

    void* getNext(void* aPayload)
    {
        version(X86) asm @nogc nothrow
        {
            naked;
            mov     EAX, [EAX + nextOffs];
            ret;
        }
        else version(Win64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RCX + nextOffs];
            ret;
        }
        else version(Nux64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RDI + nextOffs];
            ret;
        }
        else return *cast(void**) (aPayload + nextOffs);
    }

    T getData(void* aPayload)
    {
        version(X86) asm @nogc nothrow
        {
            naked;
            mov     EAX, [EAX + dataOffs];
            ret;
        }
        else version(Win64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RCX + dataOffs];
            ret;
        }
        else version(Nux64) asm @nogc nothrow
        {
            naked;
            mov     RAX, [RDI + dataOffs];
            ret;
        }
        else return *cast(T*) (aPayload + dataOffs);
    }
}

/**
 * A List implementation, slow to be iterated, fast to be reorganized.
 * This is a standard doubly linked list, with GC-free heap allocations.
 *
 * While using the array syntax for looping should be avoided, foreach()
 * processes with some acceptable performances.
 */
class DynamicList(T): List!T
{
    private
    {
        size_t _count;
        void* _last;
        void* _first;
        alias payload = dlistPayload!T;
    }
    protected
    {
        void* getPayloadFromIx(size_t index) @safe @nogc nothrow
        {
            void* current = _first;
            foreach (immutable i; 0 .. index)
                current = payload.getNext(current);
            return current;
        }

        void* getPayloadFromDt(T item) @trusted
        {
            void* current = _first;
            while(current)
            {
                T _data = payload.getData(current);
                if (_data == item)
                    break;
                current = payload.getNext(current);
            }
            return current;
        }
    }
    public
    {
        ///
        this(A...)(A elements)
        {
            foreach(elem; elements)
                add(elem);
        }

        ~this()
        {
            clear;
        }

        T opIndex(ptrdiff_t i) @safe @nogc nothrow
        {
            void* _pld = getPayloadFromIx(i);
            return payload.getData(_pld);
        }

        void opIndexAssign(T item, size_t i) @safe @nogc nothrow
        {
            void* _pld = getPayloadFromIx(i);
            payload.setData(_pld, item);
        }

        int opApply(int delegate(T) dg) @trusted
        {
            int result = 0;
            void* current = _first;
            while(current)
            {
                result = dg(payload.getData(current));
                if (result) break;
                current = payload.getNext(current);
            }
            return result;
        }

        int opApplyReverse(int delegate(T) dg) @trusted
        {
            int result = 0;
            void* current = _last;
            while(current)
            {
                result = dg(payload.getData(current));
                if (result) break;
                current = payload.getPrev(current);
            }
            return result;
        }

        void opAssign(T[] elems) @trusted @nogc
        {
            clear;
            foreach(elem; elems)
                add(elem);
        }

        T last() @safe @nogc nothrow
        {
            return payload.getData(_last);
        }

        T first() @safe @nogc nothrow
        {
            return payload.getData(_first);
        }

        ptrdiff_t find(T item) @trusted
        {
            void* current = _first;
            ptrdiff_t result = -1;
            while(current)
            {
                result++;
                T _data = payload.getData(current);
                if (_data == item) return result++;
                current = payload.getNext(current);
            }
            return -1;
        }

        ptrdiff_t add(T item) @trusted @nogc
        {
            if (!_first)
                return insert(item);
            else
            {
                void* _pld = payload.newPld(_last, null, item);
                payload.setNext(_last, _pld);
                _last = _pld;
                return _count++;
            }
        }

        ptrdiff_t add(T[] items) @trusted @nogc
        {
            foreach (item; items)
                add(item);
            return _count - 1;
        }

        ptrdiff_t insert(T item) @trusted @nogc
        {
            void* _pld = payload.newPld(null, _first, item);
            if (_first) payload.setPrev(_first, _pld);
            else _last = _pld;
            _first = _pld;
            ++_count;
            return 0;
        }

        ptrdiff_t insert(size_t position, T item) @trusted @nogc
        {
            if (!_first || position == 0)
            {
                return insert(item);
            }
            else if (position >= _count)
            {
                return add(item);
            }
            else
            {
                void* old = getPayloadFromIx(position);
                void* prev = payload.getPrev(old);
                void* _pld = payload.newPld(prev, old, item);
                payload.setPrev(old, _pld);
                payload.setNext(prev, _pld);
                _count++;
                return position;
            }
        }

        void swapItems(T item1, T item2) @trusted
        {
            void* _pld1 = getPayloadFromDt(item1);
            if (_pld1 == null) return;
            void* _pld2 = getPayloadFromDt(item2);
            if (_pld2 == null) return;

            T _data1 = payload.getData(_pld1);
            T _data2 = payload.getData(_pld2);

            payload.setData(_pld1, _data2);
            payload.setData(_pld2, _data1);
        }

        void swapIndexes(size_t index1, size_t index2) @trusted
        {
            void* _pld1 = getPayloadFromIx(index1);
            if (_pld1 == null) return;
            void* _pld2 = getPayloadFromIx(index2);
            if (_pld2 == null) return;

            T _data1 = payload.getData(_pld1);
            T _data2 = payload.getData(_pld2);

            payload.setData(_pld1, _data2);
            payload.setData(_pld2, _data1);
        }

        bool remove(T item) @trusted
        {
            void* _pld = getPayloadFromDt(item);
            if (!_pld) return false;

            void* _prev = payload.getPrev(_pld);
            void* _next = payload.getNext(_pld);
            if (_last == _pld && _prev)
            {
                _last = _prev;
                payload.setNext(_last, null);
                _next = null;
            }
            else if (_first == _pld && _next)
            {
                _first = _next;
                payload.setPrev(_first, null);
                _prev = null;
            }
            else if (_prev && _next)
            {
                if (_prev) payload.setNext(_prev, _next);
                if (_next) payload.setPrev(_next, _prev);
            }
            payload.freePld(_pld);
            if (_last == _first && _last == _pld)
            {
                _last = null;
                _first = null;
            }
            --_count;
            return true;
        }

        T extract(size_t index) @trusted
        {
            T result;
            void* _pld = getPayloadFromIx(index);
            if (!_pld) return result;
            result = payload.getData(_pld);

            void* _prev = payload.getPrev(_pld);
            void* _next = payload.getNext(_pld);
            if (_last == _pld && _prev)
            {
                _last = _prev;
                payload.setNext(_prev, null);
                _next = null;
            }
            else if (_first == _pld && _next)
            {
                _first = _next;
                payload.setPrev(_next, null);
                _prev = null;
            }
            else if (_prev && _next)
            {
                payload.setNext(_prev, _next);
                payload.setPrev(_next, _prev);
            }
            payload.freePld(_pld);
            if (_last == _first && _last == _pld)
            {
                _last = null;
                _first = null;
            }
            --_count;
            return result;
        }

        void clear() @trusted @nogc
        {
            void* current = _first;
            while(current)
            {
                void* _old = current;
                current = payload.getNext(current);
                payload.freePld(_old);
            }
            _count = 0;
            _first = null;
            _last = null;
        }

        size_t count() @trusted @property @nogc
        {
            return _count;
        }

        Range opSlice()
        {
            return Range(_first, _last);
        }

        Range opSlice(size_t lo, size_t hi) @trusted
        {
            return Range(getPayloadFromIx(lo), getPayloadFromIx(hi));
        }

        alias length = count;

        alias put = add;

        struct Range
        {
            private void* _begin;
            private void* _end;

            private this(void* b, void* e)
            {
                _begin = b;
                _end = e;
            }

            /**
             * Returns $(D true) if the range is _empty
             */
            @property bool empty() const
            {
                return _begin is null;
            }

            /**
             * Returns the first element in the range
             */
            @property T front()
            {
                return payload.getData(_begin);
            }

            /**
             * Returns the last element in the range
             */
            @property T back()
            {
                return payload.getData(_end);
            }

            /**
             * pop the front element from the range
             *
             * complexity: amortized $(BIGOH 1)
             */
            void popFront()
            {
                _begin = payload.getNext(_begin);
            }

            /**
             * pop the back element from the range
             *
             * complexity: amortized $(BIGOH 1)
             */
            void popBack()
            {
                _end = payload.getPrev(_end);
            }

            /**
             * Trivial _save implementation, needed for $(D isForwardRange).
             */
            @property Range save()
            {
                return this;
            }

            @property size_t length()
            {
                size_t result;
                auto cur = _begin;
                while(cur)
                {
                    cur = payload.getNext(cur);
                    ++result;
                }
                return result;
            }
        }
    }
}

unittest
{
    struct  S{int a,b; int notPod(){return a;}}
    class   C{int a,b; int notPod(){return a;}}

    void test(alias T )()
    {
        // struct as ptr
        alias SList = T!(S*);
        S[200] arrayOfS;
        SList sList = construct!SList;
        scope(exit) sList.destruct;

        for (auto i = 0; i < arrayOfS.length; i++)
        {
            arrayOfS[i].a = i;
            sList.add( &arrayOfS[i] );
            assert( sList[i] == &arrayOfS[i]);
            assert( sList.count == i + 1);
            assert( sList.find( &arrayOfS[i] ) == i);
        }

        sList.swapIndexes(0,1);
        assert( sList.find(&arrayOfS[0]) == 1 );
        assert( sList.find(&arrayOfS[1]) == 0 );
        sList.swapIndexes(0,1);
        assert( sList.find(&arrayOfS[0]) == 0 );
        assert( sList.find(&arrayOfS[1]) == 1 );
        sList.remove(sList.last);
        assert( sList.count == arrayOfS.length -1 );
        sList.clear;
        assert( sList.count == 0 );
        for (auto i = 0; i < arrayOfS.length; i++)
        {
            sList.add( &arrayOfS[i] );
        }
        sList.extract(50);
        assert( sList.find(&arrayOfS[50]) == -1 );
        sList.insert(50,&arrayOfS[50]);
        assert( sList.find(&arrayOfS[50]) == 50 );
        sList.extract(50);
        sList.insert(&arrayOfS[50]);
        assert( sList.find(&arrayOfS[50]) == 0 );
        sList.clear;
        assert( sList.count == 0 );
        for (auto i = 0; i < arrayOfS.length; i++)
        {
            sList.add( &arrayOfS[i] );
        }

        // class as ref
        alias CList = T!C;
        C[200] arrayOfC;
        CList cList = construct!CList;
        scope(exit) cList.destruct;

        for (auto i = 0; i < arrayOfC.length; i++)
        {
            arrayOfC[i] = construct!C;
            arrayOfC[i].a = i;
            cList.add( arrayOfC[i] );
            assert( cList[i] is arrayOfC[i]);
            assert( cList.count == i + 1);
            assert( cList.find( arrayOfC[i] ) == i);
        }
        cList.swapIndexes(0,1);
        assert( cList.find(arrayOfC[0]) == 1 );
        assert( cList.find(arrayOfC[1]) == 0 );
        cList.swapIndexes(0,1);
        assert( cList.find(arrayOfC[0]) == 0 );
        assert( cList.find(arrayOfC[1]) == 1 );
        cList.remove(cList.last);
        assert( cList.count == arrayOfC.length -1 );
        cList.clear;
        assert( cList.count == 0 );
        for (auto i = 0; i < arrayOfC.length; i++)
        {
            cList.add( arrayOfC[i] );
        }
        cList.extract(50);
        assert( cList.find(arrayOfC[50]) == -1 );
        cList.insert(50,arrayOfC[50]);
        assert( cList.find(arrayOfC[50]) == 50 );
        cList.extract(50);
        cList.insert(arrayOfC[50]);
        assert( cList.find(arrayOfC[50]) == 0 );
        cList.clear;
        assert( cList.count == 0 );
        for (auto i = 0; i < arrayOfC.length; i++)
        {
            cList.add( arrayOfC[i] );
        }

        // cleanup of internally allocated items.
        C itm;
        cList.clear;
        assert(cList.count == 0);
        cList.addNewItem;
        cList.addNewItem;
        assert(cList.count == 2);

        itm = cList.extract(0);
        assert(itm);
        itm.destruct;
        assert(cList.count == 1);
        itm = cList.extract(0);
        assert(itm);
        itm.destruct;
        assert(cList.count == 0);

        cList.add(arrayOfC[0]);
        cList[0] = arrayOfC[1];
        assert(cList.find(arrayOfC[0]) == -1);
        assert(cList.find(arrayOfC[1]) == 0);
        cList.clear;

        cList = arrayOfC[10..20];
        assert(cList.count == 10);
        assert(cList[0] == arrayOfC[10]);
        assert(cList[9] == arrayOfC[19]);

        cList.clear;
        cList.insert(0, arrayOfC[24]);
        assert(cList[0] == arrayOfC[24]);
        cList.insert(123456, arrayOfC[25]);
        assert(cList.count == 2);
        assert(cList[1] == arrayOfC[25]);
        cList.swapItems(arrayOfC[24],arrayOfC[25]);
        assert(cList[0] == arrayOfC[25]);
        assert(cList[1] == arrayOfC[24]);
        cList.swapIndexes(0,1);
        assert(cList[0] == arrayOfC[24]);
        assert(cList[1] == arrayOfC[25]);
        C elem = cList.extract(1);
        assert(elem is arrayOfC[25]);
        assert(cList.count == 1);

        size_t i;
        cList = arrayOfC[0..10];
        foreach(C c; cList)
        {
            assert(c is arrayOfC[i]);
            ++i;
        }
        foreach_reverse(C c; cList)
        {
            --i;
            assert(c is arrayOfC[i]);
        }
        assert(cList.first == arrayOfC[0]);
        assert(cList.last == arrayOfC[9]);

        cList.clear;
        cList.add(arrayOfC[0..10]);
        assert(cList.count == 10);
        assert(cList.first == arrayOfC[0]);
        assert(cList.last == arrayOfC[9]);
    }

    test!(ContiguousList);
    test!(DynamicList);
}


/**
 * TreeItemSiblings is an input range that allows to
 * iterate over the children of a TreeItem.
 */
struct TreeItemChildren(T)
{

private:

    T _front;

public:

    /// See $(D initialize()).
    this(T t)
    {
        initialize(t);
    }

    /// Initializes the range from a parent.
    void initialize(T t)
    {
        _front = t.firstChild;
    }

    ///
    T front()
    {
        return _front;
    }

    ///
    void popFront()
    {
        _front = _front.nextSibling;
    }

    ///
    bool empty()
    {
        return _front is null;
    }

    /**
     * Support for the array syntax.
     * Should be avoided in for() loops.
     */
    T opIndex(ptrdiff_t index)
    in
    {
        assert(_front);
    }
    body
    {
        T result = _front;
        ptrdiff_t cnt = 0;
        while(true)
        {
            if (cnt++ == index || !result)
                return result;
            result = result.nextSibling;
        }
    }

    /// Support the array syntax.
    void opIndexAssign(T item, size_t i)
    in
    {
        assert(_front);
        assert(item);
    }
    body
    {
        auto old = opIndex(i);
        if (!old)
            _front.addSibling(item);
        else
        {
            if (_front.findSibling(item) != -1)
                _front.exchangeSibling(item,old);
            else
            {
                _front.removeSibling(old);
                _front.insertSibling(i,item);
            }
        }
    }
}

/**
 * TreeItemSiblings is an input range that allows to
 * iterate over the siblings of a TreeItem.
 */
struct TreeItemSiblings(T)
{

private:

    T _front;

public:

    /// See $(D initialize()).
    this(T t)
    {
        initialize(t);
    }

    /// Initializes the range from one of the siblings.
    void initialize(T t)
    {
        if (t.parent)
            _front = t.parent.firstChild;
        else
        {
            while (t.prevSibling !is null)
            {
                t = t.prevSibling;
            }
            _front = t;
        }
    }

    ///
    T front()
    {
        return _front;
    }

    ///
    void popFront()
    {
        _front = _front.nextSibling;
    }

    ///
    bool empty()
    {
        return _front is null;
    }

    /**
     * Support for the array syntax.
     * Should be avoided in for loops.
     */
    T opIndex(ptrdiff_t index)
    in
    {
        assert(_front);
    }
    body
    {
        T result = _front;
        ptrdiff_t cnt = 0;
        while(true)
        {
            if (cnt++ == index || !result)
                return result;
            result = result.nextSibling;
        }
    }

    /// Support for the array syntax.
    void opIndexAssign(T item, size_t i)
    in
    {
        assert(_front);
    }
    body
    {
        if (!item)
            _front.removeSibling(i);
        else
        {
            auto old = opIndex(i);
            if (!old)
                _front.addSibling(item);
            else
            {
                if (_front.findSibling(item) != -1)
                    _front.exchangeSibling(item,old);
                else
                {
                    _front.removeSibling(old);
                    _front.insertSibling(i,item);
                }
            }
        }
    }
}

/**
 * The TreeItem mixin turns its implementer into a tree item.
 */
mixin template TreeItem()
{

protected:

    import iz.memory: construct, destruct;

    enum isStruct = is(typeof(this) == struct);
    static if (isStruct)
        alias TreeItemType = typeof(this)*;
    else
        alias TreeItemType = typeof(this);

    TreeItemType _prevSibling, _nextSibling, _firstChild, _parent;
    TreeItemSiblings!TreeItemType _siblings;
    TreeItemChildren!TreeItemType _children;

    import iz.streams: Stream, writeArray;

public:

    /// Returns $(D this) when mixed in a class or $(D &this) in a struct.
    TreeItemType self()
    {
        static if (isStruct)
            return &this;
        else
            return this;
    }

    /**
     * Returns the previous TreeItem.
     */
    TreeItemType prevSibling()
    {
        return _prevSibling;
    }

    /**
     * Returns the next TreeItem.
     */
    TreeItemType nextSibling()
    {
        return _nextSibling;
    }

    /**
     * Returns the parent.
     */
    TreeItemType parent()
    {
        return _parent;
    }

    /**
     * Returns the first child.
     */
    TreeItemType firstChild()
    {
        return _firstChild;
    }

    /**
     * Returns an input range that allows to iterate the siblings.
     * The array syntax is also supported.
     */
    TreeItemSiblings!TreeItemType siblings()
    {
        _siblings.initialize(self);
        return _siblings;
    }

    /**
     * Returns an input range that allows to iterate the children.
     * The array syntax is also supported.
     */
    TreeItemChildren!TreeItemType children()
    {
        _children.initialize(self);
        return _children;
    }

// siblings -------------------------------------------------------------------+

    /**
     * Constructs, adds to the back then returns a new sibling.
     * This method should be prefered over addChild and insertChild
     * if $(D deleteChildren()) is used.
     *
     * When TreeItem is mixed in a class a template parameter that specifies
     * the class type to return must be present, otherwise in both cases the
     * function passes the optional run-time parameters to the constructor.
     */
    static if (is(TreeItemType == class))
    {
        IT addNewSibling(IT,A...)(A a)
        if (is(IT : TreeItemType))
        {
            auto result = construct!IT(a);
            addSibling(result);
            return result;
        }
    }
    else
    {
        TreeItemType addNewSibling(A...)(A a)
        {
            TreeItemType result = construct!(typeof(this))(a);
            addSibling(result);
            return result;
        }
    }

    /**
     * Returns the last item.
     * The value returned is never null.
     */
    TreeItemType lastSibling()
    {
        TreeItemType result;
        result = self;
        while(result.nextSibling)
        {
            result = result.nextSibling;
        }
        return result;
    }

    /**
     * Returns the first item.
     * The value returned is never null.
     */
    TreeItemType firstSibling()
    {
        if (_parent)
            return _parent._firstChild;
        else
        {
            TreeItemType result;
            result = self;
            while(result.prevSibling)
            {
                result = result.prevSibling;
            }
            return result;
        }
    }

    /**
     * Returns the index of sibling if it's found otherwise -1.
     */
    ptrdiff_t findSibling(TreeItemType sibling)
    in
    {
        assert(sibling);
    }
    body
    {
        auto current = self;
        while(current)
        {
            if (current is sibling) break;
            current = current.prevSibling;
        }
        if(!current)
        {
            current = self;
            while(current)
            {
                if (current is sibling) break;
                current = current.nextSibling;
            }
        }
        if (!current) return -1;
        return current.siblingIndex;
    }

    /**
     * Adds an item at the end of list.
     */
    void addSibling(TreeItemType sibling)
    in
    {
        assert(sibling);
    }
    body
    {
        if (sibling.hasSibling)
        {
            if (sibling.prevSibling !is null)
                sibling.prevSibling.removeSibling(sibling);
            else
                sibling.nextSibling.removeSibling(sibling);
        }

        auto oldlast = lastSibling;
        assert(oldlast);
        oldlast._nextSibling = sibling;
        sibling._prevSibling = oldlast;
        sibling._nextSibling = null;
        sibling._parent = parent;
    }

    /**
     * Inserts an item at the beginning of the list.
     */
    void insertSibling(TreeItemType sibling)
    in
    {
        assert(sibling);
    }
    body
    {
        if (sibling.hasSibling)
        {
            if (sibling.prevSibling !is null)
                sibling.prevSibling.removeSibling(sibling);
            else
                sibling.nextSibling.removeSibling(sibling);
        }

        auto oldfirst = firstSibling;
        assert(oldfirst);
        oldfirst._prevSibling = sibling;
        sibling._nextSibling = oldfirst;
        sibling._parent = parent;

        if (parent)
        {
            parent._firstChild = sibling;
        }
    }

    /**
     * Inserts a sibling.
     *
     * Params:
     *      index = The position where to insert.
     *      sibling = the item to insert.
     */
    void insertSibling(size_t index, TreeItemType sibling)
    in
    {
        assert(sibling);
    }
    body
    {
        if (sibling.hasSibling)
        {
            if (sibling.prevSibling !is null)
                sibling.prevSibling.removeSibling(sibling);
            else
                sibling.nextSibling.removeSibling(sibling);
        }

        size_t cnt = siblingCount;
        if (index == 0) insertSibling(sibling);
        else if (index >= cnt) addSibling(sibling);
        else
        {
            size_t result = 1;
            auto old = firstSibling;
            while(old)
            {
                if (result == index)
                {
                    auto item1oldprev = old.prevSibling;
                    auto item1oldnext = old.nextSibling;
                    sibling._prevSibling = old;
                    sibling._nextSibling = item1oldnext;
                    old._nextSibling = sibling;
                    item1oldnext._prevSibling = sibling;
                    sibling._parent = _parent;
                    assert(sibling.siblingIndex == index);

                    return;
                }
                old = old.nextSibling;
                result++;
            }
        }
    }

    /**
     * Exchanges the position of two siblings.
     */
    void exchangeSibling(TreeItemType sibling1, TreeItemType sibling2)
    in
    {
        assert(sibling1);
        assert(sibling2);
        assert(sibling1._parent is sibling2._parent);
    }
    body
    {
        auto item1oldprev = sibling1._prevSibling;
        auto item1oldnext = sibling1._nextSibling;
        auto item2oldprev = sibling2._prevSibling;
        auto item2oldnext = sibling2._nextSibling;
        bool contiguous = item2oldprev == sibling1 || item1oldprev == sibling2;

        if (!contiguous)
        {
            sibling1._prevSibling = item2oldprev;
            sibling1._nextSibling = item2oldnext;
            sibling2._prevSibling = item1oldprev;
            sibling2._nextSibling = item1oldnext;
            if (item1oldprev) item1oldprev._nextSibling = sibling2;
            if (item1oldnext) item1oldnext._prevSibling = sibling2;
            if (item2oldprev) item2oldprev._nextSibling = sibling1;
            if (item2oldnext) item2oldnext._prevSibling = sibling1;
        }
        else
        {
            if (item1oldnext is sibling2)
            {
                sibling1._prevSibling = sibling2;
                sibling1._nextSibling = item2oldnext;
                sibling2._nextSibling = sibling1;
                sibling2._prevSibling = item1oldprev;
            }
            else
            {
                sibling2._prevSibling = sibling1;
                sibling2._nextSibling = item1oldnext;
                sibling1._nextSibling = sibling2;
                sibling1._prevSibling = item2oldprev;
            }
        }

        if (sibling1._parent && sibling1._parent.firstChild is sibling1)
        {
            sibling1._parent._firstChild = sibling2;
        }
        else if (sibling2._parent && sibling2._parent.firstChild is sibling2)
        {
            sibling2._parent._firstChild = sibling1;
        }
    }

    /**
     * Removes an item.
     *
     * Params:
     *      sibling = The item to remove.
     * Returns:
     *      true if the item is a sibling otherwise false.
     */
    bool removeSibling(TreeItemType sibling)
    {
        if (!sibling || sibling.parent && sibling.parent != parent)
            return false;

        TreeItemType oldprev = sibling._prevSibling;
        TreeItemType oldnext = sibling._nextSibling;
        if (oldprev) oldprev._nextSibling = oldnext;
        if (oldnext) oldnext._prevSibling = oldprev;

        if (parent && parent.firstChild is sibling)
        {
            parent._firstChild = oldnext;
        }

        sibling._prevSibling = null;
        sibling._nextSibling = null;
        sibling._parent = null;

        return true;
    }

    /**
     * Removes the nth sibling.
     *
     * Params:
     *      index = the index of the sibling to remove.
     *  Returns:
     *      The item if the index is valid, otherwise null.
     */
    TreeItemType removeSibling(size_t index)
    {
        TreeItemType result = siblings[index];
        if (result)
        {
            TreeItemType oldprev = result._prevSibling;
            TreeItemType oldnext = result._nextSibling;
            if (oldprev) oldprev._nextSibling = oldnext;
            if (oldnext) oldnext._prevSibling = oldprev;

            if (parent && parent.firstChild is result)
            {
                parent._firstChild = result._nextSibling;
            }

            result._prevSibling = null;
            result._nextSibling = null;
            result._parent = null;
        }
        return result;
    }

    /**
     * Returns the count of sibling in the branch.
     * The value returned is always greater than 0.
     */
    size_t siblingCount()
    {
        size_t toFront, toBack;
        auto current = self;
        while(current)
        {
            current = current._prevSibling;
            toFront++;
        }
        current = self;
        while(current)
        {
            current = current._nextSibling;
            toBack++;
        }
        return toFront + toBack -1;
    }

    /**
     * Returns the item position in the list.
     */
    ptrdiff_t siblingIndex()
    {
        ptrdiff_t result = -1;
        TreeItemType current = self;
        while(current)
        {
            current = current._prevSibling;
            result++;
        }
        return result;
    }

    /**
     * Sets the item position in the list.
     * The new position of the previous item is undetermined.
     */
    void siblingIndex(size_t position)
    {
        TreeItemType old = siblings[position];
        if (old !is self)
        {
            TreeItemType prt = _parent;
            removeSibling(self);
            old.insertSibling(position, self);
            _parent = prt;
        }
    }

    /**
     * Indicates if the item has neighboors.
     */
    bool hasSibling()
    {
        return prevSibling !is null || nextSibling !is null;
    }

// -----------------------------------------------------------------------------
// children -------------------------------------------------------------------+

    /**
     * Constructs, adds to the back then returns a new child.
     * This method should be prefered over addChild and insertChild
     * if $(D deleteChildren()) is used.
     *
     * When TreeItem is mixed in a class a template parameter that specifies
     * the class type to return must be present, otherwise in both cases the
     * function passes the optional run-time parameters to the constructor.
     */
    static if (is(TreeItemType == class))
    {
        IT addNewChild(IT,A...)(A a)
        if (is(IT : TreeItemType))
        {
            auto result = construct!IT(a);
            addChild(result);
            return result;
        }
    }
    else
    {
        TreeItemType addNewChild(A...)(A a)
        {
            TreeItemType result = construct!(typeof(this))(a);
            addChild(result);
            return result;
        }
    }

    /**
     * Returns the distance to the root.
     */
    size_t level()
    {
        size_t result;
        auto current = self;
        while(current._parent)
        {
            current = current._parent;
            result++;
        }
        return result;
    }

    /**
     * Returns the root.
     */
    TreeItemType root()
    {
        auto current = self;
        while(current._parent)
            current = current._parent;
        return current;
    }

    /**
     * Returns the children count.
     */
    size_t childrenCount()
    {
        if ( _firstChild is null)
            return 0;
        else
            return _firstChild.siblingCount;
    }

    /**
     * Adds child to the back.
     */
    void addChild(TreeItemType child)
    {
        if (child.parent)
        {
            if (child.parent !is self)
                child.parent.removeChild(child);
            else
                return;
        }
        if (!_firstChild)
        {
            _firstChild = child;
            child._parent = self;
            return;
        }
        else _firstChild.addSibling(child);
    }

    /**
     * Inserts the first child.
     */
    void insertChild(TreeItemType child)
    {
        if (!_firstChild)
        {
            _firstChild = child;
            child._parent = self;
            return;
        }
        else _firstChild.insertSibling(child);
    }

    /**
     * Inserts a child.
     *
     * Params:
     *      index = The position in the children list.
     *      child = The child to insert.
     */
    void insertChild(size_t index, TreeItemType child)
    in
    {
        assert(child);
    }
    body
    {
        if (!_firstChild)
        {
            _firstChild = child;
            child._parent = self;
            return;
        }
        else _firstChild.insertSibling(index, child);
    }

    /**
     * Removes a child from the list.
     *
     * Params:
     *      child = The child to remove.
     * Returns:
     *      true if child is removed.
     */
    bool removeChild(TreeItemType child)
    in
    {
        assert(child);
    }
    body
    {
        ptrdiff_t i = -1;
        if (_firstChild)
        {
            i = firstChild.findSibling(child);
            if (i != -1) removeChild(i);
        }
        return i != -1;
    }

    /**
     * Removes the nth child.
     *
     * Params:
     *      index = The child index.
     * Returns:
     *      The child if index was valid, otherwise null.
     */
    TreeItemType removeChild(size_t index)
    in
    {
        assert(index >= 0);
    }
    body
    {
        TreeItemType result = children[index];
        if (result)
        {
            if (index > 0)
                result.prevSibling.removeSibling(index);
            else
            {
                if (result.siblingCount == 1)
                {
                    result._parent = null;
                    _firstChild = null;
                }
                else
                    result._nextSibling.removeSibling(index);
            }
        }
        return result;
    }

    /**
     * Removes the children, without destructing them.
     * After the call, the links to the items siblings are also reset to null.
     */
    void removeChildren()
    {
        auto current = _firstChild;
        while(current)
        {
            current.removeChildren;

            auto _next = current.nextSibling;
            current._parent = null;
            current._prevSibling = null;
            current._nextSibling = null;
            current = _next;
        }
        _firstChild = null;
    }

    /**
     * Removes and deletes (destroy) the children.
     *
     * This method should be used in pair with $(D addNewChild()) and
     * $(D addNewSiblings()). If $(D add()) or $(D insert()) have been used to
     * build the tree then initial references will be dangling.
     */
    void deleteChildren()
    {
        while(_firstChild)
        {
            auto current = _firstChild;
            _firstChild = current.nextSibling;

            current.deleteChildren;
            current._parent = null;
            current._nextSibling = null;
            current._prevSibling = null;
            static if (is(TreeItemType == interface))
                destruct(cast(Object) current);
            else
                destruct(current);
        }
    }
// -----------------------------------------------------------------------------
// other ----------------------------------------------------------------------+

    /**
     * Converts the node to a string.
     * This is used to represent the whole tree in $(D saveToStream()).
     */
    char[] itemToTextNative()
    {
        import std.format: format;
        char[] result;
        foreach(immutable i; 0 .. level) result ~= '\t';
        result ~= format( "Index: %.4d - NodeType: %s", siblingIndex, typeof(this).stringof);
        return result;
    }

    /**
     * Saves the textual representation of the tree to a Stream.
     *
     * Params:
     *      stream = The Stream where items are written.
     *      itemToText = A custom function to render the items. When not specified,
     *      $(D itemToTextNative()) is used.
     */
    void saveToStream(Stream stream, string function(TreeItemType) itemToText = null)
    {
        char[] txt;
        if (itemToText)
            txt = itemToText(self).dup;
        else
            txt = itemToTextNative ~ "\r\n";
        writeArray!false(stream, txt);
        foreach(c; children)
            c.saveToStream(stream, itemToText);
    }
// -----------------------------------------------------------------------------
}

/**
 * Helper class template that implements TreeItem in a C descendant.
 */
class TreeItemClass(C): C
if (is(C==class))
{
    mixin TreeItem;
}

/// Alias to the most simple TreeItem class type.
alias ObjectTreeItem = TreeItemClass!Object;

/**
 * Helper struct template that implements TreeItem in a struct.
 *
 * Params:
 *      fieldsAndFuncs = The struct declarations, as a string to mix.
 */
struct TreeItemStruct(string fieldsAndFuncs)
{
    mixin(fieldsAndFuncs);
    mixin TreeItem;
}

/// Alias to the most simple TreeItem struct type.
alias StructTreeItem = TreeItemStruct!q{public void* data;};

unittest
{
    ObjectTreeItem[20] ObjectTreeItems;
    ObjectTreeItem root1;

    ObjectTreeItems[0] = construct!ObjectTreeItem;
    root1 = ObjectTreeItems[0];
    for (auto i =1; i < ObjectTreeItems.length; i++)
    {
        ObjectTreeItems[i] = construct!ObjectTreeItem;
        if (i>0) root1.addSibling( ObjectTreeItems[i] );
        assert( ObjectTreeItems[i].siblingIndex == i );
        assert( root1.siblings[i].siblingIndex == i );
        assert( root1.siblings[i] == ObjectTreeItems[i] );
        if (i>0) assert( ObjectTreeItems[i].prevSibling.siblingIndex == i-1 );
        assert(root1.lastSibling.siblingIndex == i);
    }
    assert(root1.siblingCount == ObjectTreeItems.length);

    assert(ObjectTreeItems[1].nextSibling.siblingIndex == 2);
    assert(ObjectTreeItems[1].prevSibling.siblingIndex == 0);

    root1.exchangeSibling(ObjectTreeItems[10],ObjectTreeItems[16]);
    assert(root1.siblingCount == ObjectTreeItems.length);
    assert( ObjectTreeItems[10].siblingIndex == 16);
    assert( ObjectTreeItems[16].siblingIndex == 10);

    root1.exchangeSibling(ObjectTreeItems[10],ObjectTreeItems[16]);
    assert(root1.siblingCount == ObjectTreeItems.length);
    assert( ObjectTreeItems[10].siblingIndex == 10);
    assert( ObjectTreeItems[16].siblingIndex == 16);


    ObjectTreeItems[8].siblingIndex = 4;
    assert( ObjectTreeItems[8].siblingIndex == 4);
    //assert( ObjectTreeItems[4].siblingIndex == 5); // when siblingIndex() calls remove/insert
    //assert( ObjectTreeItems[4].siblingIndex == 8); // when siblingIndex() calls exchangeSibling.

    assert( root1.siblings[16] == ObjectTreeItems[16]);
    assert( root1.siblings[10] == ObjectTreeItems[10]);
    root1.siblings[16] = ObjectTreeItems[10]; // exchg
    assert(root1.siblingCount == ObjectTreeItems.length);
    root1.siblings[16] = ObjectTreeItems[16]; // exchg
    assert(root1.siblingCount == ObjectTreeItems.length);
    assert( ObjectTreeItems[16].siblingIndex == 16);
    assert( ObjectTreeItems[10].siblingIndex == 10);

    auto c = construct!ObjectTreeItem;
    root1.siblings[10] = c;
    root1.siblings[16] = ObjectTreeItems[10];
    assert( ObjectTreeItems[16].siblingIndex == 0);
    assert( ObjectTreeItems[10].siblingIndex == 16);
    assert( c.siblingIndex == 10);

    assert(root1.findSibling(ObjectTreeItems[18]) > -1);
    assert(root1.findSibling(ObjectTreeItems[0]) > -1);

    foreach(item; root1.siblings)
    {
        assert(root1.findSibling(item) == item.siblingIndex);
    }

    root1.removeSibling(19);
    assert(root1.siblingCount == ObjectTreeItems.length -1);
    root1.removeSibling(18);
    assert(root1.siblingCount == ObjectTreeItems.length -2);
    root1.removeSibling(ObjectTreeItems[13]);
    assert(root1.siblingCount == ObjectTreeItems.length -3);
    //root1[0] = null; // exception because root1[0] = root1
    assert(root1.siblingCount == ObjectTreeItems.length -3);
    root1.siblings[1] = null;
    assert(root1.siblingCount == ObjectTreeItems.length -4);

    //
    ObjectTreeItem[20] items1;
    ObjectTreeItem[4][20] items2;
    assert( items1[12] is null);
    assert( items2[12][0] is null);
    assert( items2[18][3] is null);

    ObjectTreeItem root2;
    root2 = construct!ObjectTreeItem;
    assert(root2.level == 0);
    for (auto i=0; i < items1.length; i++)
    {
        items1[i] = construct!ObjectTreeItem;
        root2.addChild(items1[i]);
        assert(root2.childrenCount == 1 + i);
        assert(items1[i].parent is root2);
        assert(items1[i].siblingCount == 1 + i);
        assert(items1[i].level == 1);
        assert(items1[i].siblingIndex == i);
    }
    root2.removeChildren;
    assert(root2.childrenCount == 0);
    for (auto i=0; i < items1.length; i++)
    {
        root2.addChild(items1[i]);
        assert(items1[i].siblingIndex == i);
    }

    for( auto i = 0; i < items2.length; i++)
        for( auto j = 0; j < items2[i].length; j++)
        {
            items2[i][j] = construct!ObjectTreeItem;
            items1[i].addChild(items2[i][j]);
            assert(items2[i][j].level == 2);
            assert(items1[i].childrenCount == 1 + j);
            assert(items2[i][j].siblingCount == 1 + j);
        }

    root2.deleteChildren;
/*
    // this is an expected behavior:

    // original refs are dangling
    assert( items1[12] is null);
    assert( items2[12][0] is null);
    assert( items2[18][3] is null);
    // A.V: 'cause the items are destroyed
    writeln( items1[12].level );
*/

    root2.addNewChild!ObjectTreeItem();
        root2.children[0].addNewChild!ObjectTreeItem();
        root2.children[0].addNewChild!ObjectTreeItem();
        root2.children[0].addNewChild!ObjectTreeItem();
    root2.addNewChild!ObjectTreeItem();
        root2.children[1].addNewChild!ObjectTreeItem();
        root2.children[1].addNewChild!ObjectTreeItem();
        root2.children[1].addNewChild!ObjectTreeItem();
        root2.children[1].addNewChild!ObjectTreeItem();
            root2.children[1].children[3].addNewChild!ObjectTreeItem();
            root2.children[1].children[3].addNewChild!ObjectTreeItem();
            root2.children[1].children[3].addNewChild!ObjectTreeItem();

    assert(root2.childrenCount == 2);
    assert(root2.children[0].childrenCount == 3);
    assert(root2.children[1].childrenCount == 4);
    assert(root2.children[1].children[3].childrenCount == 3);
    assert(root2.children[1].children[3].children[0].level == 3);

    assert(root2.children[1].children[3].children[0].root is root2);
    assert(root2.children[1].children[3].root is root2);

    auto str = construct!MemoryStream;
    root2.saveToStream(str);
    //str.saveToFile("treenodes.txt");
    str.destruct;
    root2.deleteChildren;
}

unittest
{
    ObjectTreeItem root = construct!ObjectTreeItem;
    ObjectTreeItem c0 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c1 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c2 = root.addNewChild!ObjectTreeItem;

    scope(exit) destructEach(root, c0, c1, c2);

    assert(root.childrenCount == 3);
    root.removeChild(c0);
    assert(root.childrenCount == 2);
    root.removeChild(c1);
    assert(root.childrenCount == 1);
    root.removeChild(c2);
    assert(root.childrenCount == 0);
    root.removeChild(c2);
    assert(root.childrenCount == 0);
}

unittest
{
    alias ItemStruct = TreeItemStruct!"uint a;";

    ItemStruct* root = construct!ItemStruct;

    auto c0 = root.addNewChild;
    auto c1 = root.addNewChild;
    auto c2 = root.addNewChild;

    scope(exit) destructEach(root, c0, c1, c2);

    assert(root.childrenCount == 3);
    root.removeChild(0);
    assert(root.childrenCount == 2);
    root.removeChild(0);
    assert(root.childrenCount == 1);
    root.removeChild(0);
    assert(root.childrenCount == 0);

    root.addChild(c0);
    root.addChild(c1);
    root.addChild(c2);
    assert(root.childrenCount == 3);
    root.removeChild(0);
    assert(root.childrenCount == 2);
    root.insertChild(c0);
    assert(root.childrenCount == 3);
    assert(root.children[0] == c0);
    root.removeChild(1);
    assert(c1.parent == null);
    assert(root.childrenCount == 2);
    root.insertChild(1, c1);
    assert(root.childrenCount == 3);
    root.removeChild(1);
    assert(root.childrenCount == 2);
    assert(c1.parent == null);
    root.insertChild(1, c1);
    assert(root.childrenCount == 3);
    assert(root.children[1] == c1);

    assert(root.children[0] == c0);
    assert(root.children[1] == c1);
    assert(root.children[2] == c2);

    c2.exchangeSibling(c0,c1);
    assert(root.firstChild == c1);
    assert(root.children[0] == c1);
    assert(root.children[1] == c0);
    assert(root.children[2] == c2);
    c2.exchangeSibling(c0,c1);
    assert(root.firstChild == c0);
    root.removeChild(c2);
    c0.insertSibling(c2);
    assert(root.firstChild == c2);

    root.removeChildren;
    root.addChild(c0);
    root.addChild(c1);
    root.addChild(c2);
    auto r = root.children;
    assert(r.front == c0);
    r.popFront;
    assert(r.front == c1);
    r.popFront;
    assert(r.front == c2);
    r.popFront;
    assert(r.empty);
}

unittest
{
    ObjectTreeItem root = construct!ObjectTreeItem;
    ObjectTreeItem c0 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c1 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c2 = root.addNewChild!ObjectTreeItem;
    scope(exit) destructEach(root, c0, c1, c2);

    size_t it;
    foreach(ObjectTreeItem child; root.children)
    {
        assert(c0.parent);
        assert(c1.parent);
        assert(c2.parent);
        if (it == 0)
        {
            c1.siblingIndex = c1.siblingCount-1;
            c0.siblingIndex = c0.siblingCount-1;
            c0.siblingIndex = 0;
        }
        else if (it == 1)
        {
            c1.siblingIndex = c1.siblingCount-1;
            c0.siblingIndex = c0.siblingCount-1;
            c0.siblingIndex = 0;
        }
        else if (it == 2)
        {
            c1.siblingIndex = c1.siblingCount-1;
            c0.siblingIndex = c0.siblingCount-1;
            c0.siblingIndex = 0;
        }
        it++;
    }
}

