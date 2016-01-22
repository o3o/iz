/**
 * Several trivial functions and structures
 */
module iz.sugar;

import
    std.traits, std.typetuple;

version(unittest) import std.stdio;

/**
 * Void version of the init() type function.
 *
 * Params:
 *      T = the argument type, likely to be infered.
 *      t = a reference to a T.
 */
void reset(T)(ref T t) @safe @nogc nothrow
{
    t = T.init;
}
///
unittest
{
    uint a = 159;
    string b = "bla";
    a.reset;
    assert(a == 0);
    b.reset;
    assert(b == "");
}


private bool implicitConvToBool(T)()
{
    return (isIntegral!T || is(T==bool) || is(T==void*));
}


/**
 * Boolean not.
 */
bool not(T)(auto ref T t) @safe @nogc nothrow pure
if (implicitConvToBool!T)
{
    return !t;
}
///
unittest
{
    void* ptr = null;
    assert(not(true) == false);
    assert(not(false) == true);
    assert(not(1) == 0);
    assert(not(0) == 1);
    assert(not(123456) == 0);
    assert(not(ptr));
    assert(1.not == false);
    assert(((1+2)/3).not == false);
    assert(0.not );
    assert(!1.not );
    assert(0.not.not.not );
    assert(!0.not.not.not.not );
}


/**
 * Boolean and.
 */
bool and(T1, T2)(auto ref T1 t1 ,auto ref T2 t2) @safe @nogc nothrow pure
if (implicitConvToBool!T1 && implicitConvToBool!T2)
{
    return t1 && t2;
}
///
unittest
{
    assert(true.and(true));
    assert(!false.and(false));
    assert((1).and(2).and(3).and(4));
    assert(!(0).and(1).and(2).and(3));
}


/**
 * Batch $(D and()) a list of variable.
 * $(D bool).
 *
 * Params:
 *      t = the list of argument, each must be implicitly convertible $(D bool).
 *
 * Returns:
 *      true if all variables are true.
 */
bool and(T...)(auto ref T t) @safe @nogc nothrow pure
{
    bool result = cast(bool)t[0];
    foreach(v; t[1 .. $])
        result = result && v;
    return result;
}
///
unittest
{
    assert(!and(true,3,false));
    assert(and(58,true,true));
}

/**
 * Boolean or.
 */
bool or(T1, T2)(auto ref T1 t1 ,auto ref T2 t2) @safe @nogc nothrow pure
if (implicitConvToBool!T1 && implicitConvToBool!T2)
{
    return t1 || t2;
}
///
unittest
{
    void* ptr = null;
    assert(true.or(false));
    assert(!false.or(false));
    assert((1).or(2).or(3).or(4));
    assert((0).or(1).or(2).or(3));
    assert(!(0).or(false).or(ptr));
}


/**
 * Batch $(D or()) a list of variable.
 * $(D bool).
 *
 * Params:
 *      t = the list of argument, each must be implicitly convertible $(D bool).
 *
 * Returns:
 *      true if one argument is true.
 */
bool or(T...)(auto ref T t) @safe @nogc nothrow pure
{
    bool result = cast(bool)t[0];
    foreach(v; t[1 .. $])
        result = result || v;
    return result;
}
///
unittest
{
    assert(!or(false,false,false));
    assert(or(123,false,true));
}


/**
 * Allows forbidden casts.
 *
 * Params:
 *      OT = The output type.
 *      IT = The input type, optional, likely to be infered.
 *      it = A reference to an IT.
 *
 * Returns:
 *      the same as $(D cast(OT) it), except that it never fails to compile.
 */
auto bruteCast(OT, IT)(auto ref IT it) @nogc nothrow pure
{
    return *cast(OT*) &it;
}
///
unittest
{
    uint[] array = [0u,1u,2u];
    size_t len;
    //len = cast(uint) array; // not allowed.
    len = bruteCast!uint(array);
    assert(len == array.length);
}


/// Enumerates the possible units of a mask.
enum MaskKind {Byte, Nibble, Bit}


/**
 * Masks, at compile-time, a byte, a nibble or a bit in the argument.
 *
 * Params:
 *      index = the position, 0-based, of the element to mask.
 *      kind = the kind of the element to mask.
 *      value = the value mask.
 *
 * Returns:
 *      The input argument with the element masked.
 */
auto mask(size_t index, MaskKind kind = MaskKind.Byte, T)(const T value) nothrow
if (    (kind == MaskKind.Byte && index <= T.sizeof)
    ||  (kind == MaskKind.Nibble && index <= T.sizeof * 2)
    ||  (kind == MaskKind.Bit && index <= T.sizeof * 8))
{
    T _mask;
    static if (kind == MaskKind.Byte)
    {
        _mask = T.min - 1 - (0xFF << index * 8);
    }
    else static if (kind == MaskKind.Nibble)
    {
        _mask = T.min - 1 - (0xF << index * 4);
    }
    else static if (kind == MaskKind.Bit)
    {
        _mask = T.min - 1 - (0x1 << index);
    }
    return value & _mask;
}
///
unittest
{
    // MaskKind.Byte by default.
    static assert(mask!1(0x12345678) == 0x12340078);
    static assert(mask!(1,MaskKind.Nibble)(0x12345678) == 0x12345608);
}


/// Compile-time $(D mask()) partially specialized for nibble-masking.
auto maskNibble(size_t index, T)(const T value) nothrow
{
    // note: aliasing prevents template parameter type deduction,
    // e.g alias maskNibble(size_t index, T) = mask!(index, MaskKind.Nibble, T);
    return mask!(index, MaskKind.Nibble)(value);
}
///
unittest
{
    static assert(maskNibble!1(0x12345678) == 0x12345608);
}


/// Compile-time $(D mask()) partially specialized for bit-masking.
auto maskBit(size_t index, T)(const T value) nothrow
{
    return mask!(index, MaskKind.Bit)(value);
}
///
unittest
{
    static assert(maskBit!1(0b1111) == 0b1101);
}


/**
 * Masks, at run-time, a byte, a nibble or a bit in the argument.
 *
 * Params:
 *      index = the position, 0-based, of the element to mask.
 *      kind = the kind of the element to mask.
 *      value = the value mask.
 *
 * Returns:
 *      The input argument with the element masked.
 */
auto mask(MaskKind kind = MaskKind.Byte, T)(const T value, size_t index) nothrow
{
    static immutable byteMasker =
    [
        0xFFFFFFFFFFFFFF00,
        0xFFFFFFFFFFFF00FF,
        0xFFFFFFFFFF00FFFF,
        0xFFFFFFFF00FFFFFF,
        0xFFFFFF00FFFFFFFF,
        0xFFFF00FFFFFFFFFF,
        0xFF00FFFFFFFFFFFF,
        0x00FFFFFFFFFFFFFF
    ];
    
    static immutable nibbleMasker =
    [
        0xFFFFFFFFFFFFFFF0,
        0xFFFFFFFFFFFFFF0F,
        0xFFFFFFFFFFFFF0FF,
        0xFFFFFFFFFFFF0FFF,
        0xFFFFFFFFFFF0FFFF,
        0xFFFFFFFFFF0FFFFF,
        0xFFFFFFFFF0FFFFFF,
        0xFFFFFFFF0FFFFFFF,
        0xFFFFFFF0FFFFFFFF,
        0xFFFFFF0FFFFFFFFF,
        0xFFFFF0FFFFFFFFFF,
        0xFFFF0FFFFFFFFFFF,
        0xFFF0FFFFFFFFFFFF,
        0xFF0FFFFFFFFFFFFF,
        0xF0FFFFFFFFFFFFFF,
        0x0FFFFFFFFFFFFFFF
    ];
    static if (kind == MaskKind.Byte)
        return value & byteMasker[index];
    else static if (kind == MaskKind.Nibble)
        return value & nibbleMasker[index];
    else
        return value & (0xFFFFFFFFFFFFFFFF - (1UL << index));
}
///
unittest
{
    // MaskKind.Byte by default.
    assert(mask(0x12345678,1) == 0x12340078);
    assert(mask!(MaskKind.Nibble)(0x12345678,1) == 0x12345608);
}

/*
First version: less byte code but more latency do to memory access
This version: no memory access but similar latency due to more byte code.
auto mask(MaskKind kind = MaskKind.Byte, T)(const T value, size_t index) nothrow
{
    static immutable T _max = - 1; 
    static if (kind == MaskKind.Byte)
        return value & (_max - (0xFF << index * 8));
    else static if (kind == MaskKind.Nibble)
        return value & (_max - (0xF << index * 4));
    else
        return value & (_max - (0x1 << index));
}
*/


/// Run-time $(D mask()) partially specialized for nibble-masking.
auto maskNibble(T)(const T value, size_t index) nothrow
{
    return mask!(MaskKind.Nibble)(value, index);
}
///
unittest
{
    assert(maskNibble(0x12345678,1) == 0x12345608);
}


/// Run-time $(D mask()) partially specialized for bit-masking.
auto maskBit(T)(const T value, size_t index) nothrow
{
    return mask!(MaskKind.Bit)(value, index);
}
///
unittest
{
    assert(maskBit(0b1111,1) == 0b1101);
}

unittest
{
    enum v0 = 0x44332211;
    static assert( mask!0(v0) == 0x44332200);
    static assert( mask!1(v0) == 0x44330011);
    static assert( mask!2(v0) == 0x44002211);
    static assert( mask!3(v0) == 0x00332211);

    assert( mask(v0,0) == 0x44332200);
    assert( mask(v0,1) == 0x44330011);
    assert( mask(v0,2) == 0x44002211);
    assert( mask(v0,3) == 0x00332211);

    enum v1 = 0x87654321;
    static assert( mask!(0, MaskKind.Nibble)(v1) == 0x87654320);
    static assert( mask!(1, MaskKind.Nibble)(v1) == 0x87654301);
    static assert( mask!(2, MaskKind.Nibble)(v1) == 0x87654021);
    static assert( mask!(3, MaskKind.Nibble)(v1) == 0x87650321);
    static assert( mask!(7, MaskKind.Nibble)(v1) == 0x07654321);
    
    assert( mask!(MaskKind.Nibble)(v1,0) == 0x87654320);
    assert( mask!(MaskKind.Nibble)(v1,1) == 0x87654301);
    assert( mask!(MaskKind.Nibble)(v1,2) == 0x87654021);
    assert( mask!(MaskKind.Nibble)(v1,3) == 0x87650321);
    assert( mask!(MaskKind.Nibble)(v1,7) == 0x07654321);

    enum v2 = 0b11111111;
    static assert( mask!(0, MaskKind.Bit)(v2) == 0b11111110);
    static assert( mask!(1, MaskKind.Bit)(v2) == 0b11111101);
    static assert( mask!(7, MaskKind.Bit)(v2) == 0b01111111);

    assert( maskBit(v2,0) == 0b11111110);
    assert( maskBit(v2,1) == 0b11111101);
    assert( mask!(MaskKind.Bit)(v2,7) == 0b01111111);
}


/**
 * Alternative to std.range primitives for arrays.
 *
 * The source is never consumed. 
 * The range always verifies isInputRange and isForwardRange. When the source
 * array element type if not a character type or if the template parameter 
 * assumeDecoded is set to true then the range also verifies
 * isForwardRange.
 *
 * When the source is an array of character and if assumeDecoded is set to false 
 * (the default) then the ArrayRange front type is always dchar because of the
 * UTF decoding. The parameter can be set to true if the source is known to
 * contains only SBCs.
 *
 * The template parameter infinite allows to turn the range in an infinite range
 * that loops over the elements.
 */
struct ArrayRange(T, bool assumeDecoded = false, bool infinite = false)
{
    static if (!isSomeChar!T || assumeDecoded || is(T==dchar))
    {
        private T* _front, _back;
        private static if(infinite) T* _first;
        ///
        this(ref T[] stuff) 
        {
            _front = stuff.ptr; 
            _back = _front + stuff.length - 1;
            static if(infinite) _first = _front;
        }      
        ///
        @property bool empty()
        {
            static if (infinite)
                return false;
            else
                return _front > _back;
        }     
        ///
        T front()
        {
            return *_front;
        }   
        ///
        T back()
        {
            return *_back;
        }
        ///
        void popFront()
        { 
            ++_front;
            static if(infinite)
            {
                if (_front > _back)
                    _front = _first;
            }
        }
        ///
        void popBack()
        {
            --_back;
        }
        /// returns a slice of the source, according to front and back.
        T[] array()
        {
            return _front[0 .. _back - _front + 1];
        }
        ///
        typeof(this) save() 
        {
            typeof(this) result;
            result._front = _front;
            result._back = _back;
            return result; 
        }
    } 
    else
    {

    private:

        import std.utf: decode;
        size_t _position, _previous, _len;
        dchar _decoded;
        T* _front;
        bool _decode;

        void readNext()
        {
            _previous = _position;
            auto str = _front[0 .. _len];
            _decoded = decode(str, _position);
        }

    public:

        ///
        this(ref T[] stuff) 
        { 
            _front = stuff.ptr;
            _len = stuff.length;
            _decode = true;
        }
        ///
        @property bool empty()
        {
            return _position >= _len;
        }
        ///
        dchar front()
        {
            if (_decode)
            {
                _decode = false;
                readNext;
            }
            return _decoded;
        }
        ///
        void popFront()
        {
            if (_decode) readNext;
            _decode = true;
        }
        /// returns a slice of the source, according to front and back.
        T[] array()
        {
            return _front[_previous .. _len];
        }   
        ///
        typeof(this) save()
        {
            typeof(this) result;
            result._position   = _position;
            result._previous   = _previous;
            result._len        = _len;
            result._decoded    = _decoded;
            result._front      = _front;
            result._decode     = _decode;
            return result;
        }
    }
}

unittest
{
    auto arr = "bla";
    auto rng = ArrayRange!(immutable(char))(arr);
    assert(rng.array == "bla", rng.array);
    assert(rng.front == 'b');
    rng.popFront;
    assert(rng.front == 'l');
    rng.popFront;
    assert(rng.front == 'a');
    rng.popFront;
    assert(rng.empty);
    assert(arr == "bla");
    //    
    auto t1 = "é_é";
    auto r1 = ArrayRange!(immutable(char))(t1);
    auto r2 = r1.save;
    foreach(i; 0 .. 3) r1.popFront;
    assert(r1.empty);
    r1 = r2;
    assert(r1.front == 'é');
    //
    auto r3 = ArrayRange!(immutable(char),true)(t1);
    foreach(i; 0 .. 5) r3.popFront;
    assert(r3.empty);
}

unittest
{
    ubyte[] src = [1,2,3,4,5];
    ubyte[] arr = src.dup;
    auto rng = ArrayRange!ubyte(arr);
    ubyte cnt = 1;
    while (!rng.empty)
    {
        assert(rng.front == cnt++);
        rng.popFront;
    }
    assert(arr == src);
    auto bck = ArrayRange!ubyte(arr);
    assert(bck.back == 5);
    bck.popBack;
    assert(bck.back == 4);
    assert(bck.array == [1,2,3,4]);
    auto sbk = bck.save;
    bck.popBack;
    sbk.popBack;
    assert(bck.back == sbk.back);
}


/**
 * Calls a function according to a probability
 *
 * Params:
 *      t = The chance to call, in percentage.
 *      fun = The function to call. It must be a void function.
 *      a = The variadic argument passed to fun.
 *
 * Returns:
 *      false if no luck.
 */
bool pickAndCall(T, Fun, A...)(T t, Fun fun, auto ref A a)
if (isNumeric!T && isCallable!Fun && is(ReturnType!Fun == void))
in
{
    static immutable string err = "chance to pick must be in the 0..100 range";
    assert(t <= 100, err);
    assert(t >= 0, err);
}
body
{
    import std.random: uniform;
    static immutable T min = 0;
    static immutable T max = 100;
    bool result = uniform!"[]"(min, max) > max - t;
    if (result) fun(a);
    return result;
}
///
unittest
{
    uint cnt;
    bool test;
    void foo(uint param0, out bool param1) @safe
    {
        cnt += param0;
        param1 = true;
    }
    foreach(immutable i; 0 .. 100)
        pickAndCall!(double)(75.0, &foo, 1, test);
    assert(cnt > 25);
    assert(test);
    cnt = 0;
    test = false;
    foreach(immutable i; 0 .. 100)
        pickAndCall!(byte)(0, &foo, 1, test);
    assert(cnt == 0);
    assert(!test);
}

/**
 * Allows to call a super method that's not in the nearest ancestor.
 * In other words, this bypasses one or several call(s) to super.
 *
 * Params:
 *      C = The ancestor class containing the target method.
 *      method = A string that identifies the method to call.
 *      c = An instance of a C subclass.
 *      a = The parameters passed to the method.
 *
 * Bugs:
 *      Does not work for private and protected methods, see
 *      https://issues.dlang.org/show_bug.cgi?id=15371
 */
template olderSuperCall(C, string method)
{
    auto olderSuperCall(A...)(C c, A a)
    if (is(C==class))
    {
        auto dg = &__traits(getMember, c, method);
        dg.funcptr = &__traits(getMember, C, method);
        return dg(a);
    }
}
///
unittest
{
    class A {string fun() {return "a";}}
    class AA: A {override string fun() {return "a" ~ super.fun;}}
    class AAA: AA {override string fun() {return "a" ~ super.fun;}}
    class AAAA: AAA
    {
        string test1()
        {
            return olderSuperCall!(A, "fun")(this);
        }
        string test2()
        {
            return olderSuperCall!(AA, "fun")(this);
        }
        override string fun()
        {
            // super.super.fun()
            return olderSuperCall!(AA, "fun")(this);
        }
    }
    auto a = new AAAA;
    assert(a.test1 == "a");
    assert(a.test2 == "aa");
    assert(a.fun == "aa");
}

