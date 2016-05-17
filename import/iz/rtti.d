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
    _char, _wchar, _dchar, /*_string, _wstring, _dstring,*/
    _object, _struct, _enum,
    _callable,
}

private static immutable RtTypeArr =
[
    RtType._invalid,
    RtType._bool, RtType._byte, RtType._ubyte, RtType._short, RtType._ushort,
    RtType._int, RtType._uint, RtType._long, RtType._ulong,
    RtType._float, RtType._double, RtType._real,
    RtType._char, RtType._wchar, RtType._dchar, /*RtType._string, RtType._wstring, RtType._dstring,*/
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
    char, wchar, dchar, /*string, wstring, dstring*/
    Object, GenericStruct, GenericEnum,
    GenericCallable
);

private alias BasicRtTypes = AliasSeq!(
    void,
    bool, byte, ubyte, short, ushort, int, uint, long, ulong,
    float, double, real,
    char, wchar, dchar/*, string, wstring, dstring*/
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
 * Runtime information for the callable types.
 */
struct CallablePtrInfo
{
    /// If hasContext then it's a delegate, otherwise a function or static function.
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
 * Runtime information for a struct that has the traits of a PropertyPublisher.
 *
 * Publishing structs have the ability to be used as any class
 * that implements the PropertyPublisher interface.
 */
struct StructPubInfo
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
    CallablePtrInfo callablePtrInfo;
    ClassInfo classInfo;
    EnumInfo enumInfo;
    StructPubInfo structPubInfo;
}

/**
 * Runtime type information
 */
struct Rtti
{
    /// Constructs a Rtti with a type and the info for this type.
    this(T)(RtType type, ubyte dim, auto ref T t)
    {
        this.type = type;
        this.dimension = dim;
        static if (is(T == CallablePtrInfo))
            infos.callablePtrInfo = t;
        else static if (is(T == ClassInfo))
            infos.classInfo = t;
        else static if (is(T == EnumInfo))
            infos.enumInfo = t;
        else static if (is(T == StructPubInfo))
            infos.structPubInfo = t;
        else static assert(0, "second argument of Rtti ctor must be a Info");
    }

    /// Constructs a Rtti with a (basic) type.
    this(RtType rtType, ubyte dim)
    in
    {
        import std.conv: to;
        assert(rtType >= RtType._invalid &&rtType <= RtType._dchar,
            "this ctor must only be used with basic types");
    }
    body
    {
        this.type = rtType;
        this.dimension = dim;
    }

    /// The runtime type
    RtType type;

    /// Type is an array
    ubyte dimension;

    /**
     * The information for this type.
     */
    Infos infos;

    /// Returns the information valid when type is equal to RtT._callable.
    const(CallablePtrInfo)* callablePtrInfo() const
    {
        return &infos.callablePtrInfo;
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
    const(StructPubInfo)* structInfo() const
    {
        return &infos.structPubInfo;
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
        alias TT = A;
    else
        alias TT = B[0];

    if (Rtti* result = TT.stringof in _name2meta)
        return result;

    enum err = "unsupported type \"" ~ TT.stringof ~ ": ";

    enum dim = dimensionCount!TT;
    static assert(dim <= ubyte.max);
    static if (dim > 0)
        alias T = Unqual!(ArrayElementType!TT);
    else
        alias T = TT;

    static if (staticIndexOf!(Unqual!T, BasicRtTypes) != -1)
    {
        RtType i = RtTypeArr[staticIndexOf!(Unqual!T, BasicRtTypes)];
        Rtti result = Rtti(i, dim);
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
            Rtti result = Rtti(RtType._enum, dim, EnumInfo(T.stringof, members, values));
        }
        else static assert(0, err ~ "only enum whose type is convertible to int are supported");
    }
    else static if (is(PointerTarget!T == function) || is(T == delegate))
    {
        alias R = ReturnType!T;
        alias P = Parameters!T;

        const(Rtti*)[] pr;
        foreach(Prm; P) pr ~= getRtti!Prm;

        Rtti result = Rtti(RtType._callable, dim, CallablePtrInfo(is(T == delegate),
            cast(Rtti*)getRtti!R, pr));
    }
    else static if (is(T == class))
    {
        enum ctor = cast(Object function()) defaultConstructor!T;
        auto init = typeid(T).initializer[];
        Rtti result = Rtti(RtType._object, dim, ClassInfo(T.stringof, ctor, init));
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

        Rtti result = Rtti(RtType._struct, dim, StructPubInfo(T.stringof));

        const(StructPubInfo)* mi = result.structInfo;
        mi.publicationFromName.funcptr = &__traits(getMember, T, "publicationFromName");
        mi.publicationFromIndex.funcptr = &__traits(getMember, T, "publicationFromIndex");
        mi.publicationCount.funcptr = &__traits(getMember, T, "publicationCount");
    }
    else static assert(0, err ~ "not handled at all");

    _name2meta[TT.stringof] = result;
    return TT.stringof in _name2meta;
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
    enum Option {o1 = 2, o2, o3}
    Option[][] opts = [[Option.o1, Option.o2],[Option.o1, Option.o2]];
    assert(getRtti(opts[0]) is getRtti(opts[1]));
}

unittest
{
    void bar();
    // only func ptr are interesting to serialize
    static assert(!is(typeof(getRtti(bar))));
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
        assert(inf.dimension == dimensionCount!T);
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
    assert(dgi.callablePtrInfo.hasContext);
    assert(dgi.callablePtrInfo.returnType.type == RtType._uint);
    assert(dgi.callablePtrInfo.parameters.length == 1);
    assert(dgi.callablePtrInfo.parameters[0].type == RtType._uint);

    const(Rtti)* fgi = getRtti(foo.b);
    assert(fgi.type == RtType._callable);
    assert(!fgi.callablePtrInfo.hasContext);
    assert(fgi.callablePtrInfo.returnType.type == RtType._char); // _string
    assert(fgi.callablePtrInfo.parameters.length == 2);
    assert(fgi.callablePtrInfo.parameters[0].type == RtType._ulong);
    assert(fgi.callablePtrInfo.parameters[1].type == RtType._char);
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

