/**
 * Several templates, alias, traits or functions related to types.
 */
module iz.types;

import
    std.traits, std.meta;
import
    iz.streams;

version(unittest) import std.stdio;

/// pointer.
alias Ptr = void*;


/** 
 * BasicTypes elements verify isBasicType().
 */
alias BasicTypes = AliasSeq!( 
    bool, byte, ubyte, short, ushort, int, uint, long, ulong, 
    float, double, real, 
    char, wchar, dchar
);
///
static unittest
{
    foreach(T; BasicTypes)
        assert( isBasicType!T, T.stringof);
}

    
/**
 * Returns true if T is a fixed-length data.
 */
bool isFixedSize(T)()
{
    return (
        staticIndexOf!(T,BasicTypes) != -1) ||
        (is(T==struct) & (__traits(isPOD, T))
    );
}

unittest
{
    class Foo{}
    struct Bar{byte a,b,c,d,e,f;}
    alias myInt = int;
    assert(isFixedSize!myInt);
    assert(!isFixedSize!Foo);
    assert(isFixedSize!Bar);
}

/// Common type for all the delagate kinds, when seen as a struct (ptr & funcptr).
alias GenericDelegate = void delegate();

/// Common type for all the function kinds.
alias GenericFunction = void function();


/**
 * Returns the dynamic class name of an Object or an interface.
 * Params:
 *      assumeDemangled = Must only be set to false if the class is declared in a unittest.
 *      t = Either an interface or a class instance.
 */
string className(bool assumeDemangled = true, T)(T t)
if (is(T == class) || is(T == interface))
{
    static if (is(T == class)) Object o = t;
    else Object o = cast(Object) t;
    import std.array: split;
    static if (assumeDemangled)
        return (cast(TypeInfo_Class)typeid(o)).name.split('.')[$-1];
    else
    {
        import std.demangle: demangle;
        return (cast(TypeInfo_Class)typeid(o)).name.demangle.split('.')[$-1];
    }
}
///
unittest
{
    static interface I {}
    static class A{}
    static class B: I{}
    static class C{}
    assert(className(new A) == "A");
    assert(className(new B) == "B");
    assert(className(cast(Object)new A) == "A");
    assert(className(cast(Object)new B) == "B");
    assert(className(cast(I) new B) == "B");
    assert(className!(false)(new C) == "C");
}

/**
 * Indicates if the member of a struct or class is accessible for compile time
 * introspection.
 *
 * The template has to be mixed in the scope where the other __traits()
 * operations are performed.
 * A simple function template that uses __traits(getProtection) does not faithfully
 * represent the member accessibility if the function is declared in another module.
 * Another problem is that __traits(getProtection) does not well represent the
 * accessibility of the private members (own members or friend classes /structs).
 */
mixin template ScopedReachability()
{
    bool isMemberReachable(T, string member)()
    if (is(T==class) || is(T==struct))
    {
        return is(typeof(__traits(getMember, T, member)));
    }
}

/**
 * Detects whether type $(D T) is a multi dimensional array.
 *
 * Params:
 *      T = type to be tested
 *
 * Returns:
 *      true if T is a multi dimensional array
 */
template isMultiDimensionalArray(T)
{
    static if (!isArray!T)
        enum isMultiDimensionalArray = false;
    else
    {
        import std.range.primitives: hasLength;
        alias DT = typeof(T.init[0]);
        enum isMultiDimensionalArray = hasLength!DT;
    }
}
///
unittest
{
    static assert(!isMultiDimensionalArray!(string[]) );
    static assert(isMultiDimensionalArray!(int[][]) );
    static assert(!isMultiDimensionalArray!(int[]) );
    static assert(!isMultiDimensionalArray!(int) );
    static assert(!isMultiDimensionalArray!(string) );
    static assert(!isMultiDimensionalArray!(int[][] function()) );
    static assert(!isMultiDimensionalArray!void);
}

/**
 * Indicates the dimension count of an built-in array.
 *
 * Params:
 *      T = type to be tested
 *
 * Returns:
 *      0 iftemplate $(D T) is an not a build-in array, otherwise a number
 *      at leat equal to 1, according to the array dimenssion count.
 */
template dimensionCount(T)
{
    static if (isArray!T)
    {
        static if (isMultiDimensionalArray!T)
        {
            alias DT = typeof(T.init[0]);
            enum dimensionCount = dimensionCount!DT + 1;
        }
        else enum dimensionCount = 1;
    }
    else enum dimensionCount = 0;
}
///
unittest
{
    static assert(dimensionCount!char == 0);
    static assert(dimensionCount!(string[]) == 1);
    static assert(dimensionCount!(int[]) == 1);
    static assert(dimensionCount!(int[][]) == 2);
    static assert(dimensionCount!(int[][][]) == 3);
}

/**
 * Indicates the array element type of an array.
 *
 * Contrary to $(D ElementType), dchar is not returned for narrow strings.
 * The template strips the type lookup goes until the last dimenssion of a
 * multi-dim array.
 *
 * Params:
 *      T = type to be tested.
 *
 * Returns:
 *      T element type.
 */
template ArrayElementType(T)
if (isArray!T)
{
    static if (isArray!(typeof(T.init[0])))
        alias ArrayElementType = ArrayElementType!(typeof(T.init[0]));
    else
        alias ArrayElementType = typeof(T.init[0]);
}
///
unittest
{
    static assert(is(ArrayElementType!(int[][]) == int));
    static assert(is(ArrayElementType!(char[][][][][]) == char));
    static assert(is(ArrayElementType!(wchar[]) == wchar));
}

/**
 * Indicates wether an enum is ordered.
 *
 * Params:
 *      T = enum to be tested.
 *
 * Returns:
 *      true if T members type is integral and if the delta between each member
 *      is one, false otherwise.
 */
template isOrderedEnum(T)
if (is(T == enum))
{
    static if (!isIntegral!(OriginalType!T))
    {
        enum f = false;
        alias isOrderedEnum = f;
    }
    else
    {
        bool checker()
        {
            OriginalType!T previous = T.min;
            foreach(member; EnumMembers!T[1..$])
            {
                if (member != previous + 1)
                    return false;
                previous = member;
            }
            return true;
        }
        alias isOrderedEnum = checker;
    }
}
///
unittest
{
    enum A {a,z,e,r}
    static assert(isOrderedEnum!A);
    enum B: ubyte {a = 2,z,e,r}
    static assert(isOrderedEnum!B);
    assert(isOrderedEnum!B); //!\ forces coverage /!\

    enum C: float {a,z,e,r}
    static assert(!isOrderedEnum!C);
    enum D: uint {a,z = 8,e,r}
    static assert(!isOrderedEnum!D);
    assert(!isOrderedEnum!D); //!\ forces coverage /!\
}

/**
 * Returns a pointer to a class default constructor.
 */
template defaultConstructor(C)
if(is(C==class))
{
    C function() get()
    {
        C function() result;
        static if (__traits(hasMember, C, "__ctor"))
        foreach(overload; __traits(getOverloads, C, "__ctor"))
        {
            static if (is(typeof(overload) == typeof(*result)))
            {
                result = &overload;
                break;
            }
        }
        return result;
    }
    enum defaultConstructor = get;
}

/**
 * Indicates wether a class has a default constructor.
 */
template hasDefaultConstructor(C)
if(is(C==class))
{
    enum hasDefaultConstructor = defaultConstructor!C !is null;
}
///
unittest
{
    class A{}
    class B{this(){}}
    class C{this(int a){}}
    class D{this(){} this(int a){}}

    static assert(!hasDefaultConstructor!A);
    static assert( hasDefaultConstructor!B);
    static assert(!hasDefaultConstructor!C);
    static assert( hasDefaultConstructor!D);
}

