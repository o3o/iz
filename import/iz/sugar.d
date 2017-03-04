/**
 * Several trivial functions and structures
 */
module iz.sugar;

import
    std.traits, std.meta, std.typecons, std.functional;
import
    std.range.primitives: isInputRange, ElementType, ElementEncodingType,
        isBidirectionalRange;

version(unittest) import std.stdio;

/**
 * Void version of the init() type function.
 *
 * Params:
 *      T = the argument type, likely to be infered.
 *      t = a reference to a T.
 */
void reset(T)(ref T t)
{
    t = T.init;
}
///
@safe @nogc nothrow unittest
{
    uint a = 159;
    string b = "bla";
    a.reset;
    assert(a == 0);
    b.reset;
    assert(b == "");
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
auto bruteCast(OT, IT)(auto ref IT it)
{
    return *cast(OT*) &it;
}
///
nothrow pure @nogc unittest
{
    static immutable array = [0u,1u,2u];
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
auto mask(size_t index, MaskKind kind = MaskKind.Byte, T)(const T value)
nothrow @safe pure
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
nothrow @safe @nogc pure unittest
{
    // MaskKind.Byte by default.
    static assert(mask!1(0x12345678) == 0x12340078);
    static assert(mask!(1,MaskKind.Nibble)(0x12345678) == 0x12345608);
}


/// Compile-time $(D mask()) partially specialized for nibble-masking.
auto maskNibble(size_t index, T)(const T value) nothrow @safe pure
{
    // note: aliasing prevents template parameter type deduction,
    // e.g alias maskNibble(size_t index, T) = mask!(index, MaskKind.Nibble, T);
    return mask!(index, MaskKind.Nibble)(value);
}
///
nothrow @safe @nogc pure unittest
{
    static assert(maskNibble!1(0x12345678) == 0x12345608);
}


/// Compile-time $(D mask()) partially specialized for bit-masking.
auto maskBit(size_t index, T)(const T value) nothrow @safe pure
{
    return mask!(index, MaskKind.Bit)(value);
}
///
nothrow @safe @nogc pure unittest
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
auto mask(MaskKind kind = MaskKind.Byte, T)(const T value, size_t index)
nothrow @safe pure
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
nothrow @safe @nogc pure unittest
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
auto maskNibble(T)(const T value, size_t index)
{
    return mask!(MaskKind.Nibble)(value, index);
}
///
nothrow @safe @nogc pure unittest
{
    assert(maskNibble(0x12345678,1) == 0x12345608);
}


/// Run-time $(D mask()) partially specialized for bit-masking.
auto maskBit(T)(const T value, size_t index) nothrow @safe pure
{
    return mask!(MaskKind.Bit)(value, index);
}
///
nothrow @safe pure unittest
{
    assert(maskBit(0b1111,1) == 0b1101);
}

nothrow @safe pure unittest
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
            static if (infinite)
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
    const bool result = uniform!"[]"(min, max) > max - t;
    if (result) fun(a);
    return result;
}
///
@safe unittest
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
 * Pops an input range while a predicate is true.
 * Consumes the input argument.
 *
 * Params:
 *      pred = the predicate.
 *      range = an input range, must be a lvalue.
 */
void popWhile(alias pred, Range)(ref Range range)
if (isInputRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    import std.range.primitives: front, empty, popFront;
    alias f = unaryFun!pred;
    while (!range.empty)
    {
        if (!f(range.front))
            break;
        else
            range.popFront;
    }
}
///
pure @safe unittest
{
    string r0 = "aaaaabcd";
    r0.popWhile!"a == 'a'";
    assert(r0 == "bcd");

    static bool lessTwo(T)(T t)
    {
        return t < 2;
    }
    int[] r1 = [0,1,2,0,1,2];
    r1.popWhile!lessTwo;
    assert(r1 == [2,0,1,2]);

    static bool posLessFive(T)(T t)
    {
        return t < 5 && t > 0;
    }
    int[] r3 = [2,3,4,-1];
    r3.popWhile!posLessFive;
    assert(r3 == [-1]);
    int[] r4 = [2,3,4,5];
    r4.popWhile!posLessFive;
    assert(r4 == [5]);
}

/**
 * Convenience function that calls popWhile() on the input argument 
 * and returns the consumed range to allow function pipelining.
 * In addition this wrapper accepts rvalues.
 */
auto dropWhile(alias pred, Range)(auto ref Range range)
if (isInputRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    popWhile!(pred, Range)(range);
    return range;
}
///
pure @safe unittest
{
    assert("aaaaabcd".dropWhile!"a == 'a'" == "bcd");
}

/**
 * Pops back an input range while a predicate is true.
 * Consumes the input argument.
 *
 * Params:
 *      pred = the predicate.
 *      range = an input range, must be a lvalue.
 */
void popBackWhile(alias pred, Range)(ref Range range)
if (isBidirectionalRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    import std.range.primitives: back, empty, popBack;
    alias f = unaryFun!pred;
    while (!range.empty)
    {
        if (!f(range.back))
            break;
        else
            range.popBack;
    }
}
///
pure @safe unittest
{
    string r0 = "bcdaaaa";
    r0.popBackWhile!"a == 'a'";
    assert(r0 == "bcd");

    static bool lessTwo(T)(T t)
    {
        return t < 2;
    }
    int[] r1 = [0,1,2,2,1,0];
    r1.popBackWhile!lessTwo;
    assert(r1 == [0,1,2,2]);

    static bool posLessFive(T)(T t)
    {
        return t < 5 && t > 0;
    }
    int[] r3 = [-1,2,3,4];
    r3.popBackWhile!posLessFive;
    assert(r3 == [-1]);
    int[] r4 = [5,2,3,4];
    r4.popBackWhile!posLessFive;
    assert(r4 == [5]);
}

/**
 * Convenience function that calls popBackWhile() on the input argument
 * and returns the consumed range to allow function pipelining.
 * In addition this wrapper accepts rvalues.
 */
auto dropBackWhile(alias pred, Range)(auto ref Range range)
if (isBidirectionalRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    popBackWhile!(pred, Range)(range);
    return range;
}
///
pure @safe unittest
{
    assert("abcdefgh".dropBackWhile!"a > 'e'" == "abcde");
}

/**
 * Returns a lazy input range that alterntively returns the state of one of two
 * sub-ranges.
 *
 * Similar to std.range roundRobin() or chain() except that the resulting range
 * is considered as empty when one of the sub range is consumed.
 *
 * Params:
 *      flip = the first input range.
 *      flop = the second input range.
 */
auto flipFlop(R1, R2)(auto ref R1 flip, auto ref R2 flop)
if (isInputRange!R1 && isInputRange!R2 && is(ElementType!R1 == ElementType!R2))
{
    import std.range.primitives: front, empty, popFront;
    struct FlipFlop
    {
        private bool _takeFlop;

        ///
        bool empty()
        {
            return (flip.empty && !_takeFlop) | (_takeFlop && flop.empty);
        }
        ///
        auto front()
        {
            final switch (_takeFlop)
            {
                case false: return flip.front;
                case true:  return flop.front;
            }
        }
        ///
        void popFront()
        {
            _takeFlop = !_takeFlop;
            final switch (_takeFlop)
            {
                case false: return flop.popFront;
                case true:  return flip.popFront;
            }
        }
    }
    FlipFlop ff;
    return ff;
}
///
pure @safe unittest
{
    import std.array: array;
    assert(flipFlop([0,2,4],[1,3,5]).array == [0,1,2,3,4,5]);
    assert(flipFlop([0,2],[1,3,5]).array == [0,1,2,3]);
    assert(flipFlop([0,2,4],[1,3]).array == [0,1,2,3,4]);
    int[] re = [];
    assert(flipFlop([0], re).array == [0]);
    assert(flipFlop(re, re).array == []);
    assert(flipFlop(re, [0]).array == []);
}

/**
 * Returns a lazy input range that takes from the input while a predicate is
 * verified and the input is not empty.
 *
 * Params:
 *      pred = the predicate.
 *      range = an input range, only consumed when passed by reference.
 */
auto takeWhile(alias pred, Range)(auto ref Range range)
if (isInputRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    alias f = unaryFun!pred;
    import std.range.primitives: front, empty, popFront;
    struct Taker
    {
        ///
        bool empty()
        {
            return range.empty || !f(range.front);
        }
        ///
        void popFront()
        {
            range.popFront;
        }
        ///
        auto front()
        {
            return range.front;
        }
    }
    Taker result;
    return result;
}
///
pure @safe unittest
{
    import std.range: array;
    import std.ascii: isDigit;
    auto r = "012A";
    assert(takeWhile!((a) => isDigit(a))(r).array == "012");
    assert(r == "A");
    assert(takeWhile!((a) => isDigit(a))(r).array == "");
    assert(takeWhile!((a) => isDigit(a))("").array == "");
}

/**
 * Returns a lazy input range that takes from the input tail while a
 * predicate is verified and the input is not empty.
 *
 * Params:
 *      pred = the predicate.
 *      range = an bidirectional range, only consumed when passed by reference.
 */
auto takeBackWhile(alias pred, Range)(auto ref Range range)
if (isBidirectionalRange!Range && is(typeof(unaryFun!pred)) && isImplicitlyConvertible!
    (typeof(unaryFun!pred((ElementType!Range).init)), bool))
{
    alias f = unaryFun!pred;
    import std.range.primitives: back, empty, popBack;
    struct Taker
    {
        ///
        bool empty()
        {
            return range.empty || !f(range.back);
        }
        ///
        void popFront()
        {
            range.popBack;
        }
        ///
        auto front()
        {
            return range.back;
        }
    }
    Taker result;
    return result;
}
///
pure @safe unittest
{
    import std.range: array;
    import std.ascii: isDigit;
    auto r = "A123";
    assert(takeBackWhile!((a) => isDigit(a))(r).array == "321");
    assert(r == "A");
    assert(takeBackWhile!((a) => isDigit(a))(r).array == "");
    assert(takeBackWhile!((a) => isDigit(a))("").array == "");
}

/**
 * Indicates how many elements of a range are mutated.
 *
 * Params:
 *      range = An input range. The elements must be mutable and initializable.
 *      Narrow srings are not considered as validate input parameter.
 *
 * Returns:
 *      A number equal to the count of elements that are different from their
 *      initializer.
 */
size_t mutatedCount(Range)(Range range)
if (isInputRange!Range && is(typeof((ElementType!Range).init))
    && isMutable!(ElementType!Range) && !isNarrowString!Range)
{
    import std.range.primitives: front, empty, popFront;

    size_t result = 0;
    const(ElementType!Range) noone = (ElementType!Range).init;
    while (!range.empty)
    {
        result += ubyte(range.front != noone);
        range.popFront;
    }
    return result;
}
///
unittest
{
    int[] i = [0,0,1];
    assert(i.mutatedCount == 1);
    assert(i[0..$-1].mutatedCount == 0);

    string[] s = ["","a"];
    assert(s.mutatedCount == 1);

    dchar[] dc = [dchar.init, 'g'];
    assert(dc.mutatedCount == 1);

    class Foo {}
    Foo[] f = new Foo[](8);
    assert(f.mutatedCount == 0);
    f[0] = new Foo;
    f[1] = new Foo;
    assert(f.mutatedCount == 2);

    // w/char.init leads to decoding invalid UTF8 sequence
    static assert(!is(typeof(mutatedCount!(char[]))));
    static assert(!is(typeof(mutatedCount!(wchar[]))));

    static assert(is(typeof(mutatedCount!(dchar[]))));
}

/**
 * Allows to pass always a parameter as value even if it would be accepted
 * as reference.
 */
auto rValue(T)(auto ref T t)
{
    return t;
}
///
unittest
{
    void foo(T)(ref T t){}
    uint a;
    static assert(is(typeof(foo(a))));
    static assert(!is(typeof(foo(a.rValue))));
}

/**
 * Compares two integral values with additional static checkings.
 *
 * If the comparison mixes signed and unsigned operands then the function tries
 * to widen the unsigned operand to perform a valid comparison, otherwise
 * a DMD-style warning is emitted.
 *
 * Params:
 *      op = The comparison operator, must be either >, < , <= or >=. Equality
 *          is also allowed even if this is always a transparent operation.
 *      lhs = The left operand, an integer.
 *      rhs = The right operand, an integer.
 *
 *  Returns:
 *      A bool, the comparison result.
 */
bool compare(string op, L, R, string fname = __FILE__, int line = __LINE__)
    (auto ref L lhs, auto ref R rhs)
if ((isIntegral!R &&  isIntegral!L) && op == "<" || op == ">" || op == "<=" ||
    op == ">=" || op == "==" || op == "!=")
{
    alias LT = Unqual!L;
    alias RT = Unqual!R;

    // transparent
    static if (is(LT == RT) || op == "==" || op == "!=")
    {
        mixin("return lhs" ~ op ~ "rhs;");
    }
    else
    {
        enum err = fname ~ "(" ~ line.stringof ~ "): ";
        enum wer = "warning, signed and unsigned comparison, the unsigned operand has been widened";

        template Widened(T)
        {
            static if (is(T==ubyte))
                alias Widened = short;
            else static if (is(T==ushort))
                alias Widened = int;
            else static if (is(T==uint))
                alias Widened = long;
        }

        // widen unsigned to bigger signed
        static if (isSigned!LT && !isSigned!RT  && RT.sizeof < 8)
        {
            version(D_Warnings) pragma(msg, err ~ wer);
            Widened!RT widenedRhs = rhs;
            mixin("return lhs" ~ op ~ "widenedRhs;");
        }
        else static if (isSigned!RT && !isSigned!LT  && LT.sizeof < 8)
        {
            version(D_Warnings) pragma(msg, err ~ wer);
            Widened!LT widenedLhs = lhs;
            mixin("return widenedLhs" ~ op ~ "rhs;");
        }
        // not fixable by widening
        else
        {
            pragma(msg, err ~ "warning, comparing a " ~ L.stringof ~ " with a "
                ~ R.stringof ~ " may result into wrong results");
            mixin("return lhs" ~ op ~ "rhs;");
        }
    }
}
///
pure @safe @nogc nothrow unittest
{
    int a = -1; uint b;
    assert(a > b); // wrong result
    assert(compare!">"(a,b) == false); // fixed by operand widening
    assert(b < a); // wrong result
    assert(compare!"<"(b,a) == false); // fixed by operand widening

    long aa = -1; ulong bb;
    assert(aa > bb); // wrong result
    assert(compare!">"(aa,bb) == true); // not statically fixable
    assert(bb < aa); // wrong result
    assert(compare!"<"(bb,aa) == true); // not statically fixable

    assert(compare!"!="(bb,aa) == true); // test for equality is always transparent OP

    immutable long aaa = -1; const ulong bbb;
    assert(compare!">"(aaa,bbb) == true);
}

/**
 * Throws a static exception, suitable for @nogc functions.
 */
@nogc @safe
void throwStaticEx(T, string file = __FILE__, size_t line = __LINE__)()
{
    static const e = new T(file, line);
    throw e;
}

/// ditto
@nogc @safe
void throwStaticEx(string message, string file = __FILE__, size_t line = __LINE__)()
{
    static const e = new Exception(message, file, line);
    throw e;
}

/**
 * Sets the context and the function of a delegate.
 *
 * Params:
 *      T = The type of the delegate.
 *      t = The delegate to set.
 *      context = The context pointer, e.g a pointer to a struct or a class instance.
 *      code = The pointer to the static function.
 */
void setDelegate(T, FT)(ref T t, void* context, FT code)
if (is(T == delegate) && is(FT == typeof(T.funcptr)))
{
    t.ptr = context;
    t.funcptr = code;
}
///
unittest
{
    struct Foo
    {
        bool fun(){return true;}
    }
    Foo foo;
    bool delegate() atFun;
    atFun.setDelegate(&foo, &Foo.fun);
    assert(atFun());
}

/**
 * Sets the context and the function of a new delegate.
 *
 * Params:
 *      T = The type of the delegate.
 *      t = The delegate to set.
 *      context = The context pointer, e.g a pointer to a struct or a class instance.
 *      code = The pointer to the static function.
 *
 * Returns:
 *      A new delegate of type T.
 */
auto getDelegate(FT)(void* context, FT code)
if (is(PointerTarget!FT == function))
{
    import std.array: replace;
    enum type = "alias T = " ~ FT.stringof.replace("function", "delegate") ~ ";";
    mixin(type);
    T t;
    t.ptr = context;
    t.funcptr = code;
    return t;
}
///
unittest
{
    struct Foo
    {
        bool fun(){return true;}
    }
    Foo foo;
    bool delegate() atFun = getDelegate(&foo, &Foo.fun);
    assert(atFun());
}

/**
 * The delegate union is a conveniant way to setup non gc delegates that
 * are compatible with D delegates.
 */
union Delegate(FT)
if (is(PointerTarget!FT == function))
{
    /// Defines the delegate layout as defined in the D ABI
    struct DgMembers
    {
        void* ptr;
        FT funcptr;
    }

    //// The delegates members;
    DgMembers members;
    alias members this;

    import std.array: replace;
    enum type = "alias T = " ~ FT.stringof.replace("function", "delegate") ~ ";";
    mixin(type);

    /// Allows to use this union as a true D delegate.
    T dg;

    /// Helper to call the delegate without accessing $(D dg).
    auto opCall(A...)(A a)
    {
        return dg(a);
    }
}
///
unittest
{
    struct Foo
    {
        bool fun(){return true;}
    }
    Foo foo;
    Delegate!(typeof(&Foo.fun)) atFun;
    atFun.ptr = &foo,
    atFun.funcptr = &Foo.fun,
    assert(atFun());
}

/**
 * Safely cast a value of a type to another, if both have the same size.
 *
 * Unlike $(D bruteCast), the same location si not shared between the
 * source and the target and no pointer is used.
 * This function is inspired by http://www.forwardscattering.org/post/27
 */
template bitCast(T, S)
if (T.sizeof == S.sizeof
    && !is(S == T)
    && !(is(S== float) & (size_t.sizeof == 4))
    && !is(S == class)     && !is(T == class)
    && !is(S == interface) && !is(T == interface))
{
    private union BitCaster
    {
        S ss;
        T tt;
    }

    static assert(BitCaster.sizeof == S.sizeof);

    pragma(inline, true)
    T bitCast(auto ref S s)
    {
        BitCaster bt;
        bt.ss = s;
        return bt.tt;
    }
}
///
@safe pure nothrow unittest
{
    assert(bitCast!int(1.0f) == 0x3f800000);
    version(LittleEndian)
        assert(bitCast!(ubyte[2])(ushort(0x1234)) == [0x34, 0x12]);
    else
        assert(bitCast!(ubyte[2])(ushort(0x1234)) == [0x12, 0x34]);
}

/// ditto
template bitCast(T, S)
if (T.sizeof == S.sizeof && is(S == float)
    && !is(T == class) && !is(T == interface))
{
    T bitCast(S[1] source...) pure
    {
        // S[1]: prevent the source to be loaded in ST(0)
        // and any normalization to happen.
        asm @trusted @nogc pure nothrow
        {
            naked;
            ret;
        }
    }
}

/// Deep iteration mode
enum IdMode
{
    depth,
    breadth
}

/**
 * Iterates a tree-like structure that exposes an input range interface and calls
 * each element with a function.
 *
 * Params:
 *      Fun = The function called for each element. When its return type is bool,
 *          and if it returns true, the iterations are stopped.
 *      member = The name of the member that gives the real Range.
 *      mode = The iteration mode (breadth-first or depth-first).
 *      range = The root element.
 *      a = The variadic parameters passed to Fun (after the element).
 * Returns:
 *      True if the iterations have stopped, false otherwise.
 */
bool deepIterate(alias Fun, string member = "", IdMode mode = IdMode.breadth,
    Range, A...)(Range range, auto ref A a)
{
    static if (!member.length)
    {
        alias Rng = Range;
        alias M = void;
    }
    else
    {
        mixin("alias M = typeof(Range." ~ member ~ ");");
        static assert(__traits(hasMember, Range, member),
            "invalid Range member, Range has no member named '" ~ member ~ "'");
    }
    enum callable = isCallable!M;
    static if (callable)
        alias Rng = ReturnType!M;
    static assert(isInputRange!Rng && is(ElementType!Rng == Range),
        "invalid deepIterate Range");

    static if (is(ReturnType!Fun))
    {
        alias R = ReturnType!Fun;
        enum funIsPred = is(R == bool);
    }
    else enum funIsPred = false;

    bool result;

    enum callWithFront =
    q{
        static if (funIsPred)
            result = Fun(range, a);
        else
            Fun(range, a);
        if (result)
            return true;
    };

    static if (!__traits(hasMember, range, "front"))
    {
        import std.range.primitives: front, empty, popFront;
    }

    static if (mode == IdMode.breadth)
        mixin(callWithFront);

    static if (!member.length)
        alias items = range;
    else static if (callable)
        mixin("auto items = range." ~ member ~ ";");
    else
        mixin("alias items = range." ~ member ~ ";");

    while (!items.empty)
    {
        result = deepIterate!(Fun, member, mode, Range, A)(items.front, a);
        if (result)
            break;
        items.popFront;
    }

    static if (mode == IdMode.depth)
        mixin(callWithFront);

    return result;
}
///
unittest
{
    // creates a tree
    Item root = new Item;
    root.populate;
    root[0].populate;
    root[1].populate;

    int cnt, a;

    // count the population
    deepIterate!((e) => ++cnt)(root);
    assert(cnt == 7);

    // previous content is consumed
    root.populate;
    root[0].populate;
    root[1].populate;

    // the delegate result is used to stop the iteration
    deepIterate!((Item e, ref int p){++p; --cnt; return cnt == 4;})(root, a);
    assert(cnt == 4);
    assert(a == 3);
}

version(unittest) private class Item
{
    alias children this;
    Item[] children;
    void populate()
    {
        children.length = 2;
        children[0] = new Item;
        children[1] = new Item;
        assert(children.length == 2);
    }
}

unittest
{
    import iz.containers: ObjectTreeItem;
    import iz.memory: construct, destruct;
    ObjectTreeItem root = construct!ObjectTreeItem;
    ObjectTreeItem c1 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c2 = root.addNewChild!ObjectTreeItem;
    ObjectTreeItem c1c1 = c1.addNewChild!ObjectTreeItem;
    ObjectTreeItem c1c2 = c1.addNewChild!ObjectTreeItem;
    ObjectTreeItem c2c1 = c2.addNewChild!ObjectTreeItem;
    ObjectTreeItem c2c2 = c2.addNewChild!ObjectTreeItem;

    int cnt, a;
    deepIterate!((e) => ++cnt, "children")(root);
    assert(cnt == 7);

    root.deleteChildren;
    destruct(root);
}

/**
 * Allows to call recursively the function being executed.
 *
 * Params:
 *      a = the parameters expected by the function.
 * Examples:
 *
 * ---
 * long factorial(long a)
 * {
 *     if (a <= 1)
 *         return a;
 *      else
 *          return a * recursion(a-1);
 * }
 * ---
 *
 * Returns:
 *      The same as the function being executed.
 */
auto recursion(string Fun = __FUNCTION__ , A...)(auto ref A a)
{
    import std.typecons: tuple;
    mixin("return " ~ Fun ~ "(" ~ a.stringof ~ "[0..$]);");
}

