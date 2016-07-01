/**
 * Memory managment utilities.
 */
module iz.memory;

import
    std.traits;
import
    iz.types;
version(DigitalMars)
    { import core.stdc.stdlib, core.stdc.string; }
else
    { import std.c.stdlib, std.c.string; }

/**
 * Like malloc() but for @safe context.
 */
Ptr getMem(size_t size) nothrow @trusted @nogc
in
{
    assert(size);
}
out(result)
{
    assert(result, "Out of memory");
}
body
{
    auto result = malloc(size);
    return result;
}

/**
 * Like realloc() but for @safe context.
 */
Ptr reallocMem(ref Ptr src, size_t newSize) nothrow @trusted @nogc
in
{
    assert(newSize);
    assert(src);
}
body
{
    src = realloc(src, newSize);
    assert(src, "Out of memory");
    return src;
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
in
{
    if (count)
    {
        assert(dst);
        assert(src);
    }
}
body
{
    return memmove(dst, src, count);
}

/**
 * Like memmove() but for @safe context.
 * dst and src can't overlap.
 *
 * Params:
 *      dst = The data source.
 *      src = The data destination.
 *      count = The count of byte to meove from src to dst.
 * Returns:
 *      the pointer to the destination, (same as dst).
 */
Ptr copyMem(Ptr dst, Ptr src, size_t count) nothrow @trusted @nogc
in
{
    if (count)
    {
        assert(dst);
        assert(src);
        assert(dst + count <= src || dst >= src + count);
    }
}
body
{
    return memcpy(dst, src, count);
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
    static if (ParameterStorageClassTuple!freeMem[0] ==
        ParameterStorageClass.ref_) src = null;
}

/**
 * This enum must be used as an UDA to mark a variable of a type that looks
 * like GC-managed but that is actually not GC-managed.
 */
enum NoGc;

/**
 * When this enum is used as UDA on aggregate types whose instances are
 * created with construct() a compile time message indicates if a GC range
 * will be added for the members.
 */
enum TellRangeAdded;

/**
 * When this enum is used as UDA on aggregate types whose instances are
 * created with construct() they won't be initialized, i.e the
 * static layout representing the initial value of the members is not copied.
 *
 * For example it can be used on a struct that has a `@disable this()` and
 * when the others constructor are suposed to do the initialization job.
 */
enum NoInit;

/**
 * Indicates if an aggregate contains members that might be
 * collected by the garbage collector. This is used in `construct`
 * to determine if the content of a manually allocated aggregate must
 * be declared to the GC.
 */
template MustAddGcRange(T = void)
if (is(T==struct) || is(T==union) || is(T==class))
{
    bool check()
    {
        bool result = false;
        import std.meta: aliasSeqOf;
        import std.range: iota;

        static if (is(T == class))
        {
            foreach(BT; BaseClassesTuple!T)
            {
                static if (MustAddGcRange!BT)
                    result = true;
                if (result)
                    return result;
            }
        }

        foreach(i;  aliasSeqOf!(iota(0, T.tupleof.length)))
        {
            alias MT = typeof(T.tupleof[i]);
            static if (isDynamicArray!MT && !hasUDA!(T.tupleof[i], NoGc))
                result = true;
            static if (isPointer!MT && !hasUDA!(T.tupleof[i], NoGc))
                result = true;
            static if (is(MT == class) && !hasUDA!(T.tupleof[i], NoGc))
                result = true;
            static if (is(MT == struct) && !is(MT == T) && !hasUDA!(T.tupleof[i], NoGc))
            //TODO-cconstruct, replace with a OpOrEqu once issue 16107 fixed
                result = result | MustAddGcRange!MT;
            static if (is(MT == union) && !is(MT == T) && !hasUDA!(T.tupleof[i], NoGc))
                result = result | MustAddGcRange!MT;
            if (result)
                break;
        }
        return result;
    }
    enum MustAddGcRange = check();

    static if (hasUDA!(T, TellRangeAdded))
    {
        static if (MustAddGcRange)
            pragma(msg, "a GC range will be added for any new " ~ T.stringof);
        else
            pragma(msg, "a GC range wont be added for any new " ~ T.stringof);
    }

}
///
unittest
{
    // 'a' will be managed with expand/Shrink
    class Foo{@NoGc int[] a; @NoGc void* b;}
    static assert(!MustAddGcRange!Foo);
    // 'a' will be managed with '.length' so druntime.
    class Bar{int[] a; @NoGc void* b;}
    // b's annotation is canceled by a type.
    static assert(MustAddGcRange!Bar);
    // Baz base is not @NoGc
    class Baz: Bar{@NoGc void* c;}
    static assert(MustAddGcRange!Baz);
}

/**
 * Returns a new, GC-free, class instance.
 *
 * Params:
 *      CT = A class type.
 *      a = Variadic parameters passed to the constructor.
 */
CT construct(CT, A...)(A a) @trusted
if (is(CT == class) && !isAbstractClass!CT)
{
    auto size = typeid(CT).init.length;
    auto memory = getMem(size);
    static if (!hasUDA!(CT, NoInit))
        memory[0 .. size] = typeid(CT).init[];
    static if (__traits(hasMember, CT, "__ctor"))
        (cast(CT) (memory)).__ctor(a);
    static if (MustAddGcRange!CT)
    {
        import core.memory: GC;
        GC.addRange(memory, size, typeid(CT));
    }
    return cast(CT) memory;
}

/**
 * Returns a new, GC-free, class instance.
 *
 * This overload is designed to create factories and like the default
 * Object.factory method, it only calls, if possible, the default constructor.
 * The factory() function implemented in this iz.memory is based on this
 * construct() overload.
 *
 * Params:
 *      tic = The TypeInfo_Class of the Object to create.
 */
Object construct(TypeInfo_Class tic) @trusted
{
    if (tic.m_flags & 64)
        return null;
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
    auto size = ST.sizeof;
    auto memory = getMem(size);
    static if (!hasUDA!(ST, NoInit))
    {
        __gshared static ST init = ST.init;
        void* atInit = &init;
        memory[0..size] = atInit[0..size];
    }
    static if (A.length)
    {
        static if (__traits(hasMember, ST, "__ctor"))
            (cast(ST*) (memory)).__ctor(a);
        else
            static assert (0, "cannot construct without a user defined ctor");
    }
    static if (MustAddGcRange!ST)
    {
        import core.memory: GC;
        GC.addRange(memory, size, typeid(ST));
    }
    return cast(ST*) memory;
}

/**
 * Destructs a struct or a union that's been previously constructed
 * with $(D construct()).
 *
 * The function calls the destructor and, when passed as reference,
 * set the the instance to null.
 *
 * Params:
 *      T = A union or a struct type, likely to be infered.
 *      instance = A $(D T) instance.
 */
void destruct(T)(auto ref T* instance)
{
    if (!instance)
        return;
    static if (hasElaborateDestructor!T)
        instance.__dtor;
    freeMem(cast(void*)instance);
    static if ((ParameterStorageClassTuple!destruct)[0] ==
        ParameterStorageClass.ref_) instance = null;
}

/**
 * Destructs a class that's been previously constructed with $(D construct()).
 *
 * The function calls the destructor and, when passed as reference,
 * set the the instance to null.
 *
 * Params:
 *      assumeNoCtor = When no __ctor is found this avoids a to search one
 *      in the sub classes.
 *      T = A class type, likely to be infered.
 *      instance = A $(D T) instance.
 */
void destruct(bool assumeNoCtor = false, T)(auto ref T instance)
if (is(T == class) && T.stringof != Object.stringof)
{
    if (instance)
    {
        static if (__traits(hasMember, T, "__dtor") || assumeNoCtor)
        {
            static if (__traits(hasMember, T, "__dtor"))
                instance.__dtor;
            static if ((ParameterStorageClassTuple!destruct)[0] ==
                ParameterStorageClass.ref_) instance = null;
            freeMem(cast(void*)instance);
        }
        else // dtor might be in an ancestor
        {
            destruct(cast(Object) instance);
        }
    }
}

/**
 * Destructs a class that's been previously constructed with $(D construct()).
 *
 * This overload is never @nogc. It should be used for classes that are downcasted
 * to a base type, where a __ctor is not yet implemented.
 *
 * Params:
 *      T = A class type, likely to be infered.
 *      instance = A $(D T) instance.
 */
void destruct(T)(auto ref T instance)
if (is(T == class) && T.stringof == Object.stringof)
{
    // the content of this overload can't be in the previous because when the
    // static type is not known (e.g after cast from interface to Object) dispose()
    // can't be @nogc since the dtor is a delegate determined at runtime.
    if (instance)
    {
        TypeInfo_Class tic = cast(TypeInfo_Class) typeid(instance);

        void* dtorPtr = tic.destructor;
        while (!dtorPtr && tic.base)
        {
            tic = tic.base;
            dtorPtr = tic.destructor;
        }
        if (dtorPtr)
        {
            void delegate() dtor;
            dtor.funcptr = cast(void function()) dtorPtr;
            dtor.ptr = cast(void*) instance;
            dtor();
        }
        freeMem(cast(void*)instance);
        static if ((ParameterStorageClassTuple!destruct)[0] ==
            ParameterStorageClass.ref_) instance = null;
    }
}

/**
 * Destructs an interface implemented in an Object that's been previously
 * constructed with $(D construct()).
 *
 * This overload is never @nogc.
 *
 * Params:
 *      T = A class type, likely to be infered.
 *      instance = A $(D T) instance.
 */
void destruct(T)(auto ref T instance)
if (is(T == interface))
{
    if (instance)
    {
        version(Windows)
        {
            import core.sys.windows.unknwn: IUnknown;
            static assert(!is(T: IUnknown), "COM interfaces can't be destroyed in "
                ~ __PRETTY_FUNCTION__);
        }
        static if (__traits(allMembers, T).length)
        {
            bool allCpp()
            {
                bool result = true;
                foreach (member; __traits(allMembers, T))
                    foreach (ov; __traits(getOverloads, T, member))
                        static if (functionLinkage!ov != "C++")
                {
                    result = false;
                    break;
                }
                return result;
            }
            static assert(!allCpp, "C++ interfaces can't be destroyed in "
                ~ __PRETTY_FUNCTION__);
        }
        destruct(cast(Object) instance);
        static if ((ParameterStorageClassTuple!destruct)[0] ==
            ParameterStorageClass.ref_) instance = null;
    }
}

/**
 * Returns a pointer to a new, GC-free, basic variable.
 * Any variable allocated using this function must be manually freed with freeMem.
 *
 * Params:
 *      T = The type of the pointer to return.
 *      preFill = Optional, boolean indicating if the result has to be initialized.
 */
T* newPtr(T, bool preFill = false)()
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
void destructEach(Objs...)(auto ref Objs objs)
if (Objs.length > 1)
{
    foreach(ref obj; objs)
        destruct(obj);
}

private __gshared TypeInfo_Class[string] registeredClasses;

/**
 * Register a class type that can be created dynamically, using its name.
 *
 * Class registration should only be done in module constructors. This allow
 * the registration to be thread safe since module constructors are executed
 * in the main thread.
 *
 * Params:
 *      T = A class.
 *      name = The name used to register the class.
 *      By default the `T.stringof` is used.
 */
void registerFactoryClass(T)(string name = "")
if (is(T == class) && !isAbstractClass!T)
{
    if (!name.length)
        name = T.stringof;
    registeredClasses[name] = typeid(T);
}

/**
 * Calls registerClass() for each template argument.
 */
void registerFactoryClasses(A...)()
{
    foreach(T; A)
        registerFactoryClass!T();
}

/**
 * Constructs a class instance using a gc-free factory.
 * The usage is similar to Object.factory() except that by default
 * registered classes don't take the module in account.
 *
 * Params:
 *      className = the class name, as registered in registerFactoryClass().
 * Throws:
 *      An Exception if the class is not registered.
 */
Object factory(string className)
{
    TypeInfo_Class* tic = className in registeredClasses;
    if (!tic)
        throw construct!Exception("factory exception, unregistered class");
    return
        construct(*tic);
}

unittest
{
    import core.memory: GC;

    interface I{}
    class AI: I{}

    auto a = construct!Object;
    a.destruct;
    assert(!a);
    a.destruct;
    assert(!a);
    a.destruct;

    auto b = construct!Object;
    auto c = construct!Object;
    destructEach(a,b,c);
    assert(!a);
    assert(!b);
    assert(!c);
    destructEach(a,b,c);
    assert(!a);
    assert(!b);
    assert(!c);

    Object foo = construct!Object;
    Object bar = new Object;
    assert( GC.addrOf(cast(void*)foo) == null );
    assert( GC.addrOf(cast(void*)bar) != null );
    foo.destruct;
    bar.destroy;

    struct Foo
    {
        this(size_t a,size_t b,size_t c)
        {
            this.a = a;
            this.b = b;
            this.c = c;
        }
        size_t a,b,c;
    }

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

    auto ai = construct!AI;
    auto i = cast(I) ai;
    destruct(i);
    assert(i is null);

    abstract class Abst {}
    Object ab = construct(typeid(Abst));
    assert(ab is null);
}

@nogc unittest
{
    class Foo {@nogc this(int a){} @nogc~this(){}}
    Foo foo = construct!Foo(0);
    destruct(foo);
    assert(foo is null);

    static struct Bar {}
    Bar* bar = construct!Bar;
    destruct(bar);
    assert(bar is null);

    static struct Baz {int i; this(int,int) @nogc {}}
    Baz* baz = construct!Baz(0,0);
    destruct(baz);
    assert(baz is null);
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
}

unittest
{
    class A{string text; this(){text = "A";}}
    class B{string text; this(){text = "B";}}
    class C{int[] array; this(){array = [1,2,3];}}
    enum TypeInfo_Class[3] tics = [typeid(A),typeid(B),typeid(C)];

    A a = cast(A) construct(tics[0]);
    assert(a.text == "A");
    B b = cast(B) construct(tics[1]);
    assert(b.text == "B");
    C c = cast(C) construct(tics[2]);
    assert(c.array == [1,2,3]);
}

unittest
{
    class A{string text; this(){text = "A";}}
    class B{string text; this(){text = "B";}}
    class C{int[] array; this(){array = [1,2,3];}}
    registerFactoryClass!A;
    registerFactoryClass!B;
    registerFactoryClass!C;

    A a = cast(A) factory("A");
    assert(a.text == "A");
    B b = cast(B) factory("B");
    assert(b.text == "B");
    C c = cast(C) factory("C");
    assert(c.array == [1,2,3]);

    import std.exception: assertThrown;
    assertThrown(factory("D"));
}

@nogc unittest
{
    void* src = getMem(32);
    void* dst = getMem(32);
    (cast (ubyte*)src)[0..32] = 8;
    copyMem(dst, src, 32);
    foreach(immutable i; 0 .. 32)
        assert((cast (ubyte*)src)[i] == (cast (ubyte*)dst)[i]);
    (cast (ubyte*)src)[0..32] = 7;
    src = reallocMem(src, 32 + 16);
    ubyte* ovl = (cast (ubyte*)src) + 16;
    moveMem(cast(void*)ovl, cast(void*)src, 32);
    assert((cast (ubyte*)ovl)[31] == 7);
}

@nogc unittest
{
    @NoInit static struct Foo {uint a = 1;}
    Foo* foo = construct!Foo;
    assert(foo.a != 1);
    @NoInit static class Bar {uint a = 1;}
    Bar bar = construct!Bar;
    assert(bar.a != 1);
}

