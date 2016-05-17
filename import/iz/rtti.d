module iz.rtti;

import
    std.format, std.traits, std.meta;
import
    iz.types, iz.properties;

private __gshared string[ushort] _index2name;
private __gshared ushort[string] _name2index;
private __gshared Rtti[string] _name2meta;

/**
 * Enumerates the types supported by the Rtti
 */
enum RtType: ubyte
{
    _invalid,
    _bool, _byte, _ubyte, _short, _ushort, _int, _uint, _long, _ulong,
    _float, _double, _real,
    _char, _wchar, _dchar, _string, _wstring, _dstring,
    _object, _struct, _enum,
    _callable,
}

private static immutable RtTypeArr =
[
    RtType._invalid,
    RtType._bool, RtType._byte, RtType._ubyte, RtType._short, RtType._ushort,
    RtType._int, RtType._uint, RtType._long, RtType._ulong,
    RtType._float, RtType._double, RtType._real,
    RtType._char, RtType._wchar, RtType._dchar, RtType._string, RtType._wstring, RtType._dstring,
    RtType._object, RtType._struct, RtType._enum,
    RtType._callable,
];

private struct GenericStruct{}
private struct GenericEnum{}
private struct GenericCallable{}

private alias GenericRtTypes = AliasSeq!(
    void,
    bool, byte, ubyte, short, ushort, int, uint, long, ulong,
    float, double, real,
    char, wchar, dchar, string, wstring, dstring,
    Object, GenericStruct, GenericEnum,
    GenericCallable
);

private alias BasicRtTypes = AliasSeq!(
    void,
    bool, byte, ubyte, short, ushort, int, uint, long, ulong,
    float, double, real,
    char, wchar, dchar, string, wstring, dstring
);

static this()
{
    foreach(i, T; BasicRtTypes)
    {
        auto rtti = getRtti!T;
        _index2name[i] = T.stringof;
        _name2index[T.stringof] = i;
    }
}

/**
 * Runtime information for the basic types.
 */
struct ArrayInfo
{
    /// Indicates if the variable is an array.
    ubyte dimensionCount;
}

/**
 * Runtime information for the callable types.
 */
struct CallableInfo
{
    /// If hasContext then it's a delegate, otherwise a function / static function.
    bool hasContext;
    /// Indicates the return type.
    const Rtti* returnType;
    /// Contains the list of the parameters.
    const Rtti*[] parameters;
}

/**
 * Runtime information for the classes.
 */
struct ClassInfo
{
    /// Indicates the class type identifier.
    string identifier;
    /// Stores the static address of the default __ctor.
    Object function() constructor;
    /// Stores the static initializer.
    const void[] initialLayout;
    /// Indicates wether the class is a iz.Stream
    bool isStream;
}

/**
 * Runtime information for the enums.
 */
struct EnumInfo
{
    /// Indicates the enum type identifier.
    string identifier;
    /// Contains the identifier of each member.
    string[] members;
    /// Contains the value of each member.
    int[] values;
}

/**
 * Runtime information for a struct that's published as a sub-publisher.
 *
 * Publishing structs have the ability to be used as any class
 * that implements the PropertyPublisher interface.
 */
struct StructInfo
{
    /// Indicates the struct type identifier.
    string identifier;

    /// Returns a delegate the struct publicationFromName() method.
    GenericDescriptor* delegate(string name) publicationFromName;

    /// Returns a delegate the struct publicationFromIndex() method.
    GenericDescriptor* delegate(size_t name) publicationFromIndex;

    /// Returns a delegate the struct publicationCount() method.
    size_t delegate() publicationCount;

    /**
     * Sets the context of the three delegates.
     */
    void setContext(void* instance) const
    {
        publicationFromName.ptr = instance;
        publicationFromIndex.ptr = instance;
        publicationCount.ptr = instance;
    }
}

private union Infos
{
    ArrayInfo arrayInfo;
    CallableInfo callableInfo;
    ClassInfo classInfo;
    EnumInfo enumInfo;
    StructInfo structInfo;
}

/**
 * Runtime type information
 */
struct Rtti
{
    /// Constructs a Rtti with a type and the info for this type.
    this(T)(RtType type, auto ref T t)
    {
        this.type = type;
        static if (is(T == ArrayInfo))
            infos.arrayInfo = t;
        else static if (is(T == CallableInfo))
            infos.callableInfo = t;
        else static if (is(T == ClassInfo))
            infos.classInfo = t;
        else static if (is(T == EnumInfo))
            infos.enumInfo = t;
        else static if (is(T == StructInfo))
            infos.structInfo = t;
        else static assert(0, "second argument of Rtti ctor must be a Info");
    }

    /// The runtime type
    RtType type;

    /**
     * The information for this type.
     */
    Infos infos;

    /// Returns the information valid when type is a BasicRtType.
    const(ArrayInfo)* arrayInfo() const
    {
        return &infos.arrayInfo;
    }

    /// Returns the information valid when type is equal to RtT._callable.
    const(CallableInfo)* callableInfo() const
    {
        return &infos.callableInfo;
    }

    /// Returns the information valid when type is equal to RtT._object.
    const(ClassInfo)* classInfo() const
    {
        return &infos.classInfo;
    }

    /// Returns the information valid valid when type is equal to RtT._enum.
    const(EnumInfo)* enumInfo() const
    {
        return &infos.enumInfo;
    }

    /// Returns the information valid when type is equal to RtT._struct.
    const(StructInfo)* structInfo() const
    {
        return &infos.structInfo;
    }
}

/**
 * Registers and returns the Rtti for the type (or the variable)
 * passed as argument.
 */
const(Rtti)* getRtti(A = void, B...)(auto ref B b)
if (B.length < 2)
{
    static if (!B.length)
        alias T = A;
    else
        alias T = B[0];

    if (Rtti* result = T.stringof in _name2meta)
        return result;

    enum err = "unsupported type \"" ~ T.stringof ~ ": ";

    static if (staticIndexOf!(Unqual!T, BasicRtTypes) != -1)
    {
        RtType i = RtTypeArr[staticIndexOf!(Unqual!T, BasicRtTypes)];
        Rtti result = Rtti(i, ArrayInfo(0));
    }
    else static if (isArray!T)
    {
        enum RtType i = RtTypeArr[staticIndexOf!(Unqual!(ArrayElementType!T), BasicRtTypes)];
        static if (i > RtType._invalid)
        {
             Rtti result = Rtti(i, ArrayInfo(dimensionCount!T));
        }
        else static assert(0, err ~ "only basic types are supported in array");
    }
    else static if (is(T == enum))
    {
        static if (isImplicitlyConvertible!(OriginalType!T, int))
        {
            string[] members;
            int[] values;
            foreach(e; __traits(allMembers, T))
            {
                members ~= e;
                values  ~= __traits(getMember, T, e);
            }
            Rtti result = Rtti(RtType._enum, EnumInfo(T.stringof, members, values));
        }
        else static assert(0, err ~ "only enum whose type is convertible to int are supported");
    }
    else static if (is(PointerTarget!T == function) || is(T == delegate))
    {
        alias R = ReturnType!T;
        alias P = Parameters!T;

        const(Rtti*)[] pr;
        foreach(Prm; P) pr ~= getRtti!Prm;

        Rtti result = Rtti(RtType._callable, CallableInfo(is(T == delegate), cast(Rtti*)getRtti!R, pr));
    }
    else static if (is(T == class))
    {
        enum ctor = cast(Object function()) defaultConstructor!T;
        auto init = typeid(T).initializer[];
        Rtti result = Rtti(RtType._object, ClassInfo(T.stringof, ctor, init));
    }
    else static if (is(T == struct))
    {
        static if (!__traits(hasMember, T, "publicationFromName") ||
            !is(typeof(__traits(getMember, T, "publicationFromName")) ==
                typeof(__traits(getMember, PropertyPublisher, "publicationFromName"))))
            static assert(0, "no valid publicationFromName member");

        static if (!__traits(hasMember, T, "publicationFromIndex") ||
            !is(typeof(__traits(getMember, T, "publicationFromIndex")) ==
                typeof(__traits(getMember, PropertyPublisher, "publicationFromIndex"))))
            static assert(0, "no valid publicationFromIndex member");

        static if (!__traits(hasMember, T, "publicationCount") ||
            !is(typeof(__traits(getMember, T, "publicationCount")) ==
                typeof(__traits(getMember, PropertyPublisher, "publicationCount"))))
            static assert(0, "no valid publicationCount member");

        Rtti result = Rtti(RtType._struct, StructInfo(T.stringof));

        const(StructInfo)* mi = result.structInfo;
        mi.publicationFromName.funcptr = &__traits(getMember, T, "publicationFromName");
        mi.publicationFromIndex.funcptr = &__traits(getMember, T, "publicationFromIndex");
        mi.publicationCount.funcptr = &__traits(getMember, T, "publicationCount");
    }
    else static assert(0, err ~ "not handled at all");

    _name2meta[T.stringof] = result;
    return T.stringof in _name2meta;
}
///
unittest
{
    import std.stdio;
    enum Option {o1 = 2, o2, o3}
    Option option1, option2;
    // first call will register
    auto rtti1 = getRtti(option1);
    auto rtti2 = getRtti(option2);
    // variables of same type point to the same info.
    assert(rtti1 is rtti2);
    // useful info when the static type is not known.
    assert(rtti1.enumInfo.identifier == "Option");
    assert(rtti1.enumInfo.members == ["o1", "o2", "o3"]);
    assert(rtti1.enumInfo.values == [2, 3, 4]);
}


unittest
{
    void basicTest(T)()
    {
        const(Rtti)* inf = getRtti!T;
        assert(inf.type == RtTypeArr[staticIndexOf!(T, BasicRtTypes)]);
    }
    foreach(T; BasicRtTypes[1..$])
        basicTest!(T);
}

unittest
{
    void arrayTest(T)()
    {
        const(Rtti)* inf = getRtti!T;
        assert(inf.type == RtTypeArr[staticIndexOf!(Unqual!(ArrayElementType!T), BasicRtTypes)]);
        assert(inf.arrayInfo.dimensionCount == dimensionCount!T);
    }
    foreach(T; BasicRtTypes[1..$])
    {
        arrayTest!(T[]);
        arrayTest!(T[][]);
        arrayTest!(T[][][]);
    }
}

unittest
{
    static struct Foo
    {
        uint delegate(uint) a;
        string function(ulong,char) b;
    }
    Foo foo;
    const(Rtti)* dgi = getRtti(foo.a);
    assert(dgi.type == RtType._callable);
    assert(dgi.callableInfo.hasContext);
    assert(dgi.callableInfo.returnType.type == RtType._uint);
    assert(dgi.callableInfo.parameters.length == 1);
    assert(dgi.callableInfo.parameters[0].type == RtType._uint);

    const(Rtti)* fgi = getRtti(foo.b);
    assert(fgi.type == RtType._callable);
    assert(!fgi.callableInfo.hasContext);
    assert(fgi.callableInfo.returnType.type == RtType._string);
    assert(fgi.callableInfo.parameters.length == 2);
    assert(fgi.callableInfo.parameters[0].type == RtType._ulong);
    assert(fgi.callableInfo.parameters[1].type == RtType._char);
}

unittest
{
    static struct Bar
    {
        size_t publicationCount(){return 0;}
        GenericDescriptor* publicationFromName(string name){return null;}
        GenericDescriptor* publicationFromIndex(size_t index){return null;}
    }
    Bar bar;
    const(Rtti)* rtti = getRtti(bar);
    assert(rtti.type == RtType._struct);
    assert(rtti.structInfo.identifier == "Bar");
    rtti.structInfo.setContext(cast(void*) &bar);
    assert(rtti.structInfo.publicationCount == &bar.publicationCount);
    assert(rtti.structInfo.publicationFromIndex == &bar.publicationFromIndex);
    assert(rtti.structInfo.publicationFromName == &bar.publicationFromName);
    // coverage
    assert(rtti.structInfo.publicationCount() == bar.publicationCount);
    assert(rtti.structInfo.publicationFromIndex(0) == bar.publicationFromIndex(0));
    assert(rtti.structInfo.publicationFromName("") == bar.publicationFromName(""));

}

unittest
{
    class Gaz
    {
        this(){}
    }
    Gaz gaz = new Gaz;
    import std.stdio;
    const(Rtti)* rtti = getRtti(gaz);
    assert(rtti.type == RtType._object);
    assert(rtti.classInfo.identifier == "Gaz");
    assert(rtti.classInfo.constructor == &Gaz.__ctor);
    assert(rtti.classInfo.initialLayout == typeid(Gaz).init);
}

