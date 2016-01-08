/**
 * Memory managment utilities.
 */
module iz.memory;

import
    std.traits, std.c.stdlib, std.c.string;
import
    iz.types;

version(unittest) import std.stdio;

/**
 * Like malloc() but for @safe context.
 */
Ptr getMem(size_t size) nothrow @trusted @nogc
{
    auto result = malloc(size);
    assert(result, "Out of memory");
    return result;
}

/**
 * Like realloc() but for @safe context.
 */
Ptr reallocMem(ref Ptr src, size_t newSize) nothrow @trusted @nogc
{
    auto result = realloc(src, newSize);
    assert(result, "Out of memory");
    return result;
}

/**
 * Like memmove() but for @safe context.
 * dst and src can overlap.
 *
 * Params:
 *      dst = The data source.
 *      src = The data destination.
 *      count = The count of byte to move from src to dst.
 */
void moveMem(ref Ptr dst, ref Ptr src, size_t count) nothrow @trusted @nogc
{
    import std.c.string : memmove;
    dst = memmove(dst, src, count);
}

/**
 * Like memmove() but for @safe context.
 * dst and src can overlap.
 *
 * Params:
 *      dst = The data source.
 *      src = The data destination.
 *      count = The count of byte to meove from src to dst.
 * Returns:
 *      the pointer to the destination, (same as dst).
 */
Ptr moveMem(Ptr dst, Ptr src, size_t count) nothrow @trusted @nogc
{
    import std.c.string : memmove;
    return memmove(dst, src, count);
}

/**
 * Frees a manually allocated pointer to a basic type. 
 * Like free() but for @safe context.
 *
 * Params:
 *      src = The pointer to free.
 */
void freeMem(T)(auto ref T src) nothrow @trusted @nogc
if (isPointer!T && isBasicType!(pointerTarget!T))
{
    if (src) free(cast(void*)src);
    src = null;
}

/**  
 * Returns a new, GC-free, class instance.
 *
 * Params:
 *      CT = A class type.
 *      a = Variadic parameters passed to the constructor.
 */
CT construct(CT, A...)(A a) @trusted
if (is(CT == class))
{
    auto size = typeid(CT).init.length;
    auto memory = getMem(size);
    memory[0 .. size] = typeid(CT).init[];
    static if (__traits(hasMember, CT, "__ctor"))
        (cast(CT) (memory)).__ctor(a);
    import core.memory: GC;
    GC.addRange(memory, size, typeid(CT));
    return cast(CT) memory;
}

/**
 * Returns a new, GC-free, class instance.
 *
 * This overload is designed to create factories and like the default
 * Object.factory method, it only calls, if possible, the default constructor.
 *
 * Params:
 *      tic = The TypeInfo_Class of the Object to create.
 */
Object construct(TypeInfo_Class tic) @trusted
{
    auto size = tic.init.length;
    auto memory = getMem(size);
    memory[0 .. size] = tic.init[];
    Object result = cast(Object) memory;
    if (tic.defaultConstructor)
        tic.defaultConstructor(result);
    import core.memory: GC;
    GC.addRange(memory, size, tic);
    return result;
}

/**  
 * Returns a new, GC-free, pointer to a struct.
 *
 * Params:
 *      ST = A struct type.
 *      a = Variadic parameters passed to the constructor.
 */
ST* construct(ST, A...)(A a) @trusted
if(is(ST==struct) || is(ST==union))
{
    import std.conv : emplace;
    auto size = ST.sizeof;
    auto memory = getMem(size)[0 .. size];
    import core.memory: GC;
    GC.addRange(memory.ptr, size, typeid(ST));
    return emplace!(ST, A)(memory, a);
}
       
/** 
 * Destructs a class or a struct that's been previously
 * constructed with $(D construct()).
 *
 * The function calls the destructor and, when passed as reference,
 * set the the instance to null.
 *
 * Params:
 *      T = A class type or a struct type, likely to be infered.
 *      instance = A $(D T) instance.
 */
void destruct(T)(auto ref T instance)
if (is(T == class) || (isPointer!T && is(PointerTarget!T == struct))
    || (isPointer!T && is(PointerTarget!T == union)))
{
    if (!instance) return;
    import core.memory: GC;
    GC.removeRange(&instance);
    destroy(instance);
    freeMem(cast(void*)instance);
    instance = null;
}

/**
 * Destructs the object from where an interface has been extracted.
 *
 * The function retrieve the Object and call the other $(D destruct)
 * overload. When passed as reference, the instance is null after the
 * call.
 *
 * Params:
 *      I = An interface type, likely to be infered.
 *      instance = A $(D I) instance.
 */
void destruct(I)(auto ref I instance)
if (is(I == interface))
{
    if (Object obj = cast(Object) instance)
        obj.destruct;
    instance = null;
}

/**
 * Returns a pointer to a new, GC-free, basic variable.
 * Any variable allocated using this function must be manually freed with freeMem.
 *
 * Params:
 *      T = The type of the pointer to return.
 *      preFill = Optional, boolean indicating if the result has to be initialized.
 */
T * newPtr(T, bool preFill = false)() @trusted @nogc
if (isBasicType!T)
{
    static if(!preFill)
        return cast(T*) getMem(T.sizeof);
    else
    {
        auto result = cast(T*) getMem(T.sizeof);
        *result = T.init;
        return result; 
    }
}

/** 
 * Frees and invalidates a list of classes instances or struct pointers. 
 * $(D destruct()) is called for each item.
 *
 * Params:
 *      objs = Variadic list of Object instances.
 */
static void destruct(Objs...)(auto ref Objs objs)
{
    foreach(ref obj; objs)
        obj.destruct;
} 

unittest
{
    import core.memory: GC;

    auto a = construct!Object;
    a.destruct;
    assert(!a);
    a.destruct;
    assert(!a);
    a.destruct;

    auto b = construct!Object;
    auto c = construct!Object;
    destruct(a,b,c);
    assert(!a);
    assert(!b);
    assert(!c);
    destruct(a,b,c);
    assert(!a);
    assert(!b);
    assert(!c);

    Object foo = construct!Object;
    Object bar = new Object;
    assert( GC.addrOf(cast(void*)foo) == null );
    assert( GC.addrOf(cast(void*)bar) != null );
    foo.destruct;
    bar.destroy;
    
    struct Foo{size_t a,b,c;}
    Foo * foos = construct!Foo(1,2,3);
    Foo * bars = new Foo(4,5,6);
    assert(foos.a == 1);
    assert(foos.b == 2);
    assert(foos.c == 3);
    assert( GC.addrOf(cast(void*)foos) == null );
    assert( GC.addrOf(cast(void*)bars) != null );   
    foos.destruct;
    bars.destroy;
    assert(!foos);
    foos.destruct;
    assert(!foos);

    union Uni{bool b; ulong ul;}
    Uni * uni0 = construct!Uni();
    Uni * uni1 = new Uni();
    assert( GC.addrOf(cast(void*)uni0) == null );
    assert( GC.addrOf(cast(void*)uni1) != null );
    uni0.destruct;
    uni1.destroy;
    assert(!uni0);
    uni0.destruct;
    assert(!uni0);

    writeln("construct/destruct passed the tests");
}

unittest
{
    import core.memory: GC;
    import std.math: isNaN;
    
    auto f = newPtr!(float,true);
    assert(isNaN(*f));
    auto ui = newPtr!int;
    auto i = newPtr!uint;
    auto l = new ulong;
    
    assert(ui);
    assert(i);
    assert(f);
    
    assert(GC.addrOf(f) == null);
    assert(GC.addrOf(i) == null);
    assert(GC.addrOf(ui) == null);
    assert(GC.addrOf(l) != null);
    
    *i = 8u;
    assert(*i == 8u);
    
    freeMem(ui);
    freeMem(i);
    freeMem(f);
    
    assert(ui == null);
    assert(i == null);
    assert(f == null);
    
    auto ptr = getMem(16);
    assert(ptr);
    assert(GC.addrOf(ptr) == null);
    ptr.freeMem;
    assert(!ptr);

    writeln("newPtr passed the tests");
}

unittest
{
    class A{string text; this(){text = "A";}}
    class B{string text; this(){text = "B";}}
    class C{int[] array; this(){array = [1,2,3];}}
    TypeInfo_Class[3] tics = [typeid(A),typeid(B),typeid(C)];

    A a = cast(A) construct(tics[0]);
    assert(a.text == "A");
    B b = cast(B) construct(tics[1]);
    assert(b.text == "B");
    C c = cast(C) construct(tics[2]);
    assert(c.array == [1,2,3]);
}

