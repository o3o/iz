/**
 * The iz Runtime type informations.
 *
 *
 */
module iz.rtti;

import
    std.format, std.traits, std.meta;
import
    iz.types, iz.properties, iz.enumset;

private __gshared string[ushort] _index2name;
private __gshared ushort[string] _name2index;
private __gshared Rtti[string] _name2rtti;

/**
 * Enumerates the type constructors
 */
enum TypeCtor
{
    _const,
    _immutable,
    _inout,
    _shared
}

/// Set of TypeCtor.
alias TypeCtors = EnumSet!(TypeCtor, Set8);

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
    _funptr,
}

/**
 * Enumerates the special struct type recognized by the Rtti
 */
enum StructType: ubyte
{
    _none,      /// no special traits.
    _publisher, /// the struct has the traits of a PropertyPublisher.
    _binary,    /// the struct can write and read itself to/from ubyte[].
    _text,      /// the struct can write and read itself to/from char[].
}

private static immutable RtTypeArr =
[
    RtType._invalid,
    RtType._bool, RtType._byte, RtType._ubyte, RtType._short, RtType._ushort,
    RtType._int, RtType._uint, RtType._long, RtType._ulong,
    RtType._float, RtType._double, RtType._real,
    RtType._char, RtType._wchar, RtType._dchar, /*RtType._string, RtType._wstring, RtType._dstring,*/
    RtType._object, RtType._struct, RtType._enum,
    RtType._funptr,
];

private struct GenericStruct{}
private struct GenericEnum{}
private struct GenericFunPtr{}

private alias GenericRtTypes = AliasSeq!(
    void,
    bool, byte, ubyte, short, ushort, int, uint, long, ulong,
    float, double, real,
    char, wchar, dchar, /*string, wstring, dstring*/
    Object, GenericStruct, GenericEnum,
    GenericFunPtr
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
        const rtti = getRtti!T;
        _index2name[i] = T.stringof;
        _name2index[T.stringof] = i;
    }
}

/**
 * Indicates the size of a variable according to its RtType
 *
 * Returns:
 *      `0` is returned if the size is unknown otherwise the equivalent
 *      of the .sizeof property.
 */
ubyte size(RtType type)
{
    with(RtType) switch (type)
    {
        case _bool: case _byte: case _ubyte: case _char: return 1;
        case _short: case _ushort: case _wchar: return 2;
        case _int: case _uint: case _dchar: case _float: return 4;
        case _long: case _ulong: case _double: return 8;
        default: return 0;
    }
}
///
unittest
{
    struct St {} St st;
    assert(st.getRtti.type.size == 0);
    bool bo;
    assert(bo.getRtti.type.size == 1);
    ushort us;
    assert(us.getRtti.type.size == 2);
    uint ui;
    assert(ui.getRtti.type.size == 4);
    long lo;
    assert(lo.getRtti.type.size == 8);
}

private mixin template setContext()
{
    void setContext(void* context) const
    {
        foreach(member; __traits(allMembers, typeof(this)))
            static if (is(typeof(__traits(getMember, typeof(this), member)) == delegate))
                __traits(getMember, typeof(this), member).ptr = context;
    }
}

/**
 * Runtime information for the points to functions.
 */
struct FunPtrInfo
{
    /// If hasContext then it's a delegate, otherwise a pointer to a function.
    bool hasContext;
    /// Indicates the return type.
    const Rtti* returnType;
    /// Contains the Rtti of each parameters.
    const Rtti*[] parameters;
    /// Indicates the size
    ubyte size() const
    {
        if (hasContext) return size_t.sizeof * 2;
        else return size_t.sizeof;
    }
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
    /// Indicates the type of the values.
    const(Rtti)* valueType;
}

/**
 * Runtime information for a struct that can be saved and reloaded from an array
 * of bytes.
 */
struct BinTraits
{
    /// Returns a delegate to the struct's restoreFromBytes() method.
    void delegate(ubyte[]) loadFromBytes;

    /// Returns a delegate to the struct's saveToBytes() method.
    ubyte[] delegate() saveToBytes;

    /// Sets the delegates context.
    mixin setContext;
}

/**
 * Runtime information for a struct that can be saved and reloaded from a string
 */
struct TextTraits
{
    /// Returns a delegate to the struct's restoreFromText() method.
    void delegate(const(char)[]) loadFromText;

    /// Returns a delegate to the struct's saveToText() method.
    const(char)[] delegate() saveToText;

    /// Sets the delegates context.
    mixin setContext;
}

/**
 * Runtime information for a struct that has the traits of a PropertyPublisher.
 *
 * Publishing structs have the ability to be used as any class
 * that implements the PropertyPublisher interface.
 */
struct PubTraits
{
    /// Returns a delegate to the struct's publicationFromName() method.
    GenericDescriptor* delegate(string) publicationFromName;

    /// Returns a delegate to the struct's publicationFromIndex() method.
    GenericDescriptor* delegate(size_t) publicationFromIndex;

    /// Returns a delegate to the struct's publicationCount() method.
    size_t delegate() publicationCount;

    /// Sets the delegates context.
    mixin setContext;
}

private union StructTraits
{
    BinTraits binTraits;
    TextTraits textTraits;
    PubTraits pubTraits;
}

/**
 * Runtime information for the struct.
 */
struct StructInfo
{
    /// Constructs the info for a "noname" struct
    this(string identifier, StructType type)
    {
        this.identifier = identifier;
        structType = type;
    }

    /// Constructs the info for a specual struct.
    this(T)(string identifier, StructType type, T t)
    {
        this.identifier = identifier;
        structType = type;
        static if (is(T == PubTraits))
            structInfo.publisherInfo = t;
        else static if (is(T == TextTraits))
            structInfo.textInfo = t;
        else static if (is(T == BinTraits))
            structInfo.binaryInfo = t;
        else static assert(0, "third argument of Rtti ctor must be an Info");
    }

    /// Indicates the struct type identifier.
    string identifier;

    /// Indicates the special struct type.
    StructType structType;

    /// The information for the structure.
    StructTraits structSpecialInfo;

    /// Returns the struct information when structType is equal to StructType._binary
    const(BinTraits)* binTraits() const
    {
        return &structSpecialInfo.binTraits;
    }

    /// Returns the struct information when structType is equal to StructType._text
    const(TextTraits)* textTraits() const
    {
        return &structSpecialInfo.textTraits;
    }

    /// Returns the struct information when structType is equal to StructType._publisher
    const(PubTraits)* pubTraits() const
    {
        return &structSpecialInfo.pubTraits;
    }
}

private union Infos
{
    FunPtrInfo funptrInfo;
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
    this(T)(RtType type, ubyte dim, TypeCtors typeCtors, auto ref T t)
    {
        this.type = type;
        this.dimension = dim;
        this.typeCtors = typeCtors;
        static if (is(T == FunPtrInfo))
            infos.funptrInfo = t;
        else static if (is(T == ClassInfo))
            infos.classInfo = t;
        else static if (is(T == EnumInfo))
            infos.enumInfo = t;
        else static if (is(T == StructInfo))
            infos.structInfo = t;
        else static assert(0, "last argument of Rtti ctor must be an Info");
    }

    /// Constructs a Rtti with a (basic) type.
    this(RtType rtType, ubyte dim, TypeCtors typeCtors)
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
        this.typeCtors = typeCtors;
    }

    /// The runtime type
    RtType type;

    /// Type is an array
    ubyte dimension;

    /// Attributes for this type
    TypeCtors typeCtors;

    /**
     * The information for this type.
     */
    Infos infos;

    /// Returns the information valid when type is equal to RtT._callable.
    const(FunPtrInfo)* funptrInfo() const
    {
        return &infos.funptrInfo;
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
 * Returns the Rtti for the type that has its .stringof property
 * equal to `typeString`.
 */
const(Rtti)* getRtti(const(char)[] typeString)
{
    return typeString in _name2rtti;
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

    if (Rtti* result = TT.stringof in _name2rtti)
        return result;

    enum err = "unsupported type \"" ~ TT.stringof ~ ": ";

    enum dim = dimensionCount!TT;
    static assert(dim <= ubyte.max);
    static if (dim > 0)
        alias T = Unqual!(ArrayElementType!TT);
    else
        alias T = TT;

    TypeCtors typeCtors;
    static if (is(T==const)) typeCtors += TypeCtor._const;
    static if (is(T==immutable)) typeCtors += TypeCtor._immutable;
    static if (is(T==inout)) typeCtors += TypeCtor._inout;
    static if (is(T==shared)) typeCtors += TypeCtor._shared;

    static if (staticIndexOf!(Unqual!T, BasicRtTypes) != -1)
    {
        RtType i = RtTypeArr[staticIndexOf!(Unqual!T, BasicRtTypes)];
        const Rtti result = Rtti(i, dim, typeCtors);
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
                static assert(!is(e == enum), err ~ "nested enums are not supported");
            }
            const Rtti result = Rtti(RtType._enum, dim, typeCtors,
                EnumInfo(T.stringof, members, values, getRtti!(OriginalType!T)));
        }
        else static assert(0, err ~ "only enum whose type is convertible to int are supported");
    }
    else static if (is(PointerTarget!T == function) || is(T == delegate))
    {
        alias R = ReturnType!T;
        alias P = Parameters!T;

        const(Rtti*)[] pr;
        foreach(Prm; P)
            pr ~= getRtti!Prm;
        const Rtti result = Rtti(RtType._funptr, dim, typeCtors, FunPtrInfo(is(T == delegate),
            cast(Rtti*)getRtti!R, pr));
    }
    else static if (is(T == class))
    {
        enum ctor = cast(Object function()) defaultConstructor!T;
        auto init = typeid(T).initializer[];
        const Rtti result = Rtti(RtType._object, dim, typeCtors, ClassInfo(T.stringof, ctor, init));
    }
    else static if (is(T == struct) && __traits(hasMember, T, "publicationFromName"))
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

        const Rtti result = Rtti(RtType._struct, dim, typeCtors, StructInfo(T.stringof, StructType._publisher));

        const(StructInfo)* si = result.structInfo;
        si.pubTraits.publicationFromName.funcptr = &__traits(getMember, T, "publicationFromName");
        si.pubTraits.publicationFromIndex.funcptr = &__traits(getMember, T, "publicationFromIndex");
        si.pubTraits.publicationCount.funcptr = &__traits(getMember, T, "publicationCount");
    }
    else static if (is(T == struct) && __traits(hasMember, T, "saveToBytes"))
    {
        static if (!__traits(hasMember, T, "saveToBytes") ||
            !is(typeof(&__traits(getMember, T, "saveToBytes")) == ubyte[] function()))
            static assert(0, "no valid saveToBytes member");

        static if (!__traits(hasMember, T, "loadFromBytes") ||
            !is(typeof(&__traits(getMember, T, "loadFromBytes")) == void function(ubyte[])))
            static assert(0, "no valid loadFromBytes member");

        const Rtti result = Rtti(RtType._struct, dim, typeCtors, StructInfo(T.stringof, StructType._binary));
        const(StructInfo)* si = result.structInfo;
        si.binTraits.saveToBytes.funcptr = &__traits(getMember, T, "saveToBytes");
        si.binTraits.loadFromBytes.funcptr = &__traits(getMember, T, "loadFromBytes");
    }
    else static if (is(T == struct) && __traits(hasMember, T, "saveToText"))
    {
        static if (!__traits(hasMember, T, "saveToText") ||
            !is(typeof(&__traits(getMember, T, "saveToText")) == const(char)[] function()))
            static assert(0, "no valid saveToText member");

        static if (!__traits(hasMember, T, "loadFromText") ||
            !is(typeof(&__traits(getMember, T, "loadFromText")) == void function(const(char)[])))
            static assert(0, "no valid loadFromText member");

        const Rtti result = Rtti(RtType._struct, dim, typeCtors, StructInfo(T.stringof, StructType._text));
        const(StructInfo)* si = result.structInfo;
        si.textTraits.saveToText.funcptr = &__traits(getMember, T, "saveToText");
        si.textTraits.loadFromText.funcptr = &__traits(getMember, T, "loadFromText");
    }
    else static if (is(T == struct))
    {
        const Rtti result = Rtti(RtType._struct, dim, typeCtors, StructInfo(T.stringof, StructType._none));
    }
    else
    {
        typeCtors = 0;
        version(none) static assert(0, err ~ "not handled at all");
        else const Rtti result = Rtti(RtType._invalid, 0, typeCtors);
    }

    _name2rtti[TT.stringof] = result;
    return TT.stringof in _name2rtti;
}
///
unittest
{
    import std.stdio;
    enum Option: ubyte {o1 = 2, o2, o3}
    Option option1, option2;
    // first call will register
    const(Rtti)* rtti1 = getRtti(option1);
    const(Rtti)* rtti2 = getRtti(option2);
    // variables of same type point to the same info.
    assert(rtti1 is rtti2);
    // get the Rtti without the static type.
    const(Rtti)* rtti3 = getRtti("Option");
    assert(rtti3 is rtti1);
    assert(rtti3.enumInfo.identifier == "Option");
    assert(rtti3.enumInfo.members == ["o1", "o2", "o3"]);
    assert(rtti3.enumInfo.values == [2, 3, 4]);
    assert(rtti3.enumInfo.valueType is getRtti!ubyte);
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
    //static assert(!is(typeof(getRtti(bar))));
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
    assert(dgi.type == RtType._funptr);
    assert(dgi.funptrInfo.hasContext);
    assert(dgi.funptrInfo.returnType.type == RtType._uint);
    assert(dgi.funptrInfo.parameters.length == 1);
    assert(dgi.funptrInfo.parameters[0].type == RtType._uint);
    assert(dgi.funptrInfo.size == size_t.sizeof * 2);

    const(Rtti)* fgi = getRtti(foo.b);
    assert(fgi.type == RtType._funptr);
    assert(!fgi.funptrInfo.hasContext);
    assert(fgi.funptrInfo.returnType.type == RtType._char); // _string
    assert(fgi.funptrInfo.parameters.length == 2);
    assert(fgi.funptrInfo.parameters[0].type == RtType._ulong);
    assert(fgi.funptrInfo.parameters[1].type == RtType._char);
    assert(fgi.funptrInfo.size == size_t.sizeof);
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
    assert(rtti.structInfo.structType == StructType._publisher);
    assert(rtti.structInfo.identifier == "Bar");
    rtti.structInfo.pubTraits.setContext(cast(void*) &bar);
    assert(rtti.structInfo.pubTraits.publicationCount == &bar.publicationCount);
    assert(rtti.structInfo.pubTraits.publicationFromIndex == &bar.publicationFromIndex);
    assert(rtti.structInfo.pubTraits.publicationFromName == &bar.publicationFromName);
    // coverage
    assert(rtti.structInfo.pubTraits.publicationCount() == bar.publicationCount);
    assert(rtti.structInfo.pubTraits.publicationFromIndex(0) == bar.publicationFromIndex(0));
    assert(rtti.structInfo.pubTraits.publicationFromName("") == bar.publicationFromName(""));
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

unittest
{
    struct Hop
    {
        const(char)[] saveToText(){return "hop";}
        void loadFromText(const(char)[] value){}
    }
    Hop hop;
    const(Rtti)* rtti = getRtti(hop);
    assert(rtti.type == RtType._struct);
    assert(rtti.structInfo.structType == StructType._text);
    assert(rtti.structInfo.identifier == "Hop");
    rtti.structInfo.textTraits.setContext(cast(void*) &hop);
    assert(rtti.structInfo.textTraits.saveToText == &hop.saveToText);
    assert(rtti.structInfo.textTraits.loadFromText == &hop.loadFromText);
    // coverage
    assert(rtti.structInfo.textTraits.saveToText() == "hop");
    rtti.structInfo.textTraits.loadFromText("hop");
}

unittest
{
    struct Boo
    {
        ubyte[] saveToBytes(){return [0x0];}
        void loadFromBytes(ubyte[] value){}
    }
    Boo boo;
    const(Rtti)* rtti = getRtti(boo);
    assert(rtti.type == RtType._struct);
    assert(rtti.structInfo.structType == StructType._binary);
    assert(rtti.structInfo.identifier == "Boo");
    rtti.structInfo.binTraits.setContext(cast(void*) &boo);
    assert(rtti.structInfo.binTraits.saveToBytes == &boo.saveToBytes);
    assert(rtti.structInfo.binTraits.loadFromBytes == &boo.loadFromBytes);
    // coverage
    assert(rtti.structInfo.binTraits.saveToBytes() == [0x0]);
    rtti.structInfo.binTraits.loadFromBytes([0x0]);
}

unittest
{
    shared(int) si;
    assert(TypeCtor._shared in si.getRtti.typeCtors);
    const(int) ci;
    assert(TypeCtor._const in ci.getRtti.typeCtors);
    immutable(int) ii;
    assert(TypeCtor._immutable in ii.getRtti.typeCtors);
    const(shared(int)) sii;
    assert(TypeCtor._const in sii.getRtti.typeCtors);
    assert(TypeCtor._shared in sii.getRtti.typeCtors);
}

unittest
{
    struct Gap
    {
        static void foo(ref const(int)){}
        static void baz(ref const(int)){}
        static void bar(out shared(int)){}
    }
    auto fti0 = getRtti(&Gap.foo);
    assert(TypeCtor._const in fti0.funptrInfo.parameters[0].typeCtors);
    auto fti1 = getRtti(&Gap.bar);
    assert(TypeCtor._shared in fti1.funptrInfo.parameters[0].typeCtors);
    auto fti2 = getRtti(&Gap.baz);
    assert(fti0 is fti2);
}

unittest
{
    assert(getRtti!(const(int)) !is getRtti!(int));
}

