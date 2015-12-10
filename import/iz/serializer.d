/**
 * The iz serialization system.
 */
module iz.serializer;

import
    std.range, std.typetuple, std.conv, std.traits;
import
    iz.memory, iz.containers, iz.strings;

public
{
    import iz.types, iz.properties, iz.referencable, iz.streams;
}

version(unittest) import std.stdio;

// Serializable types validator & misc. ---------------------------------------+

/**
 * Makes a reference serializable.
 *
 * The reference must be stored in the ReferenceMan.
 *
 * A "referenced variable" is typically something that is assigned
 * at the run-time but not owned by the entity that want to keep track of it,
 * or that is serialized by another entity.
 *
 * Note that this class is not needed to serialize a reference to an object or to
 * a delegate, since those reference types are automatically handled by the serializer.
 */
// class inherited from the old serialization system, not really needed anymore.
class SerializableReference: PropertyPublisher
{

    mixin PropertyPublisherImpl;

protected:

    ubyte _cnt;
    char[] _id, _tp;
    void delegate(Object) _onRestored;

    void doSet()
    {
        _cnt++;
        if (_cnt == 2)
        {
            _cnt = 0;
            if (_onRestored)
                _onRestored(this);
        }
    }

    @Get char[] type()
    {
        return _tp;
    }

    @Set void type(char[] value)
    {
        _tp = value;
        doSet;
    }

    @Get char[] identifier()
    {
         return _id;
    }

    @Set void identifier(char[] value)
    {
        _id = value;
        doSet;
    }

public:

    ///
    this() {collectPublications!SerializableReference;}

    /**
     * Sets the internal fields according to a referenced.
     *
     * Usually called before the serialization.
     */
    void storeReference(RT)(RT* reference)
    {
        _tp = (typeString!RT).dup;
        _id = ReferenceMan.referenceID!RT(reference).dup;
    }

    /**
     * Returns the reference according to the internal fields.
     *
     * Usually called after the deserialization of after the
     * the reference owner is notified by onRestored().
     */
    RT* restoreReference(RT)()
    {
        return ReferenceMan.reference!RT(_id);
    }

    /**
     * Defines the event called when the the identifier string and the
     * type string are restored, so that the reference owner can
     * retrieve the matching reference in the ReferenceMan.
     */
    void onRestored(void delegate(Object) value)
    {
        _onRestored = value;
    }
    /// ditto
    void delegate(Object) onRestored()
    {
        return _onRestored;
    }
}

/**
 * Enumerates the types automatically handled by a Serializer.
 */
enum SerializableType
{
    // must match iz.types.RuntimeType
    _invalid= 0,
    _bool   = 0x01, _byte, _ubyte, _short, _ushort, _int, _uint, _long, _ulong,
    _float  = 0x10, _double,
    _char   = 0x20, _wchar, _dchar, _string, _wstring,
    _object = 0x30,
    _stream = 0x38,
    _delegate = 0x50, _function
}

private struct InvalidSerType{}

// must match iz.types.RuntimeType
private alias SerializableTypes = AliasSeq!(
    InvalidSerType, 
    bool, byte, ubyte, short, ushort, int, uint, long, ulong,
    float, double,
    char, wchar, dchar, string, wstring,
    Object,
    Stream,
    GenericDelegate, GenericFunction,
);

private static immutable string[SerializableType] type2text;
private static immutable SerializableType[string] text2type;
private static immutable size_t[SerializableType] type2size;

static this()
{
    foreach(i, t; EnumMembers!SerializableType)
    {
        type2text[t] = SerializableTypes[i].stringof;
        text2type[SerializableTypes[i].stringof] = t;
        type2size[t] = SerializableTypes[i].sizeof;
    }
    // the txt format doesnt support a type representation with spaces.
    type2text[SerializableType._delegate] = "GenericDelegate";
    text2type["GenericDelegate"] = SerializableType._delegate;
    type2text[SerializableType._function] = "GenericFunction";
    text2type["GenericFunction"] = SerializableType._function;
}

package bool isSerObjectType(T)()
{
    static if (is(T : Stream)) return false;
    else static if (is(T : Object)) return true;
    else return false;
}

package bool isSerObjectType(SerializableType type)
{
    with(SerializableType) return type == _object;
}

package bool isSerSimpleType(T)()
{
    static if (isArray!T && !isNarrowString!T) return false;
    else static if (is(T : GenericDelegate)) return false;
    else static if (isSerObjectType!T) return false;
    else static if (staticIndexOf!(T, SerializableTypes) == -1) return false;
    else static if (is(T : Stream)) return false;
    else return true;
}

package bool isSerArrayType(T)()
{
    static if (!isArray!T) return false;
    else static if (isMultiDimensionalArray!T) return false;
    else static if (true)
    {
        alias TT = typeof(T.init[0]);
        static if (isSomeFunction!TT) return false;
        else static if (isNarrowString!TT) return true;
        else static if (isSerObjectType!TT) return true;
        else static if (staticIndexOf!(TT, SerializableTypes) == -1) return false;
        else return true;
    }
    else return true;
}

/// Returns true if the template parameter is a serializable type.
bool isSerializable(T)()
{
    static if (isSerSimpleType!T) return true;
    else static if (isSerArrayType!T) return true;
    else static if (is(T : Stream)) return true;
    else static if (isSerObjectType!T) return true;
    else static if (is(T==delegate)) return true;
    else static if (is(T==function)) return true;
    else return false;
}

unittest
{
    struct S{}
    struct V{uint _value; alias _value this;}
    struct VS{V _value; alias _value this;}
    static assert( isSerializable!ubyte );
    static assert( isSerializable!double );
    static assert( isSerializable!(ushort[]) );
    static assert( isSerializable!Object );
    static assert( !isSerializable!S );
    static assert( !isSerializable!VS );
    static assert( isSerializable!MemoryStream);
    static assert( isSerializable!GenericDelegate);
}

private string getElemStringOf(T)()
if (isArray!T)
{
    // Not ElementType: on string and wstring it always returns  dchar.
    return typeof(T.init[0]).stringof;
}

unittest
{
    static assert( getElemStringOf!(int[]) == int.stringof );
    static assert( getElemStringOf!(int[1]) == int.stringof );
    static assert( getElemStringOf!(int[0]) != "azertyui" );
}

private string getSerializableTypeString(T)()
{
    static if (isArray!T) return getElemStringOf!T;
    else static if (isSerSimpleType!T) return T.stringof;
    else static if (is(T:Object)) return Object.stringof;
    assert(0, "failed to get the string for a serializable type");
}
// -----------------------------------------------------------------------------

// Intermediate Serialization Tree --------------------------------------------+

/// Represents a serializable property without genericity.
struct SerNodeInfo
{
    /// the type of the property
    SerializableType type;
    /// a pointer to a PropDescriptor
    Ptr     descriptor;
    /// the raw value
    ubyte[] value;
    /// the name of the property
    string  name;
    /// the property level in the IST
    uint    level;
    /// indicates if the property is an array
    bool    isArray;
    /// indicates if any error occured during processing
    bool    isDamaged;
    /// hint to rebuild the IST
    bool    isLastChild;
}

/// IST node
class IstNode
{

    mixin TreeItem;

private:

    SerNodeInfo _info;
    IstNode[string] _cache;
    bool _cached;

    void updateCache()
    {
        _cached = true;
        _cache = _cache.init;
        auto thisChain = identifiersChain();
        foreach(IstNode node; children)
        {
            _cache[thisChain ~ "." ~ node.info.name] = node;
        }
    }

public:

    ~this()
    {
        deleteChildren;
    }

    /**
     * Returns a new unmanaged IstNode.
     */
    IstNode addNewChildren()
    {
        _cached = false;
        auto result = construct!IstNode;
        addChild(result);
        return result;
    }

    /**
     * Sets the infomations describing the property associated
     * to this IST node.
     */
    void setDescriptor(T)(PropDescriptor!T* descriptor)
    {
        if (descriptor)
            setNodeInfo!T(&_info, descriptor);
    }

    /**
     * Returns a pointer to the information describing the property
     * associated to this IST node.
     */
    SerNodeInfo* info()
    {
        return &_info;
    }

    /**
     * Returns the parents identifier chain.
     */
    string parentIdentifiersChain()
    {
        if (!level) return "";
        //
        import std.algorithm: joiner;
        string[] items;
        IstNode curr = cast(IstNode) parent;
        while (curr)
        {
            items ~= curr.info.name;
            curr = cast(IstNode) curr.parent;
        }
        return items.retro.join(".");
    }

    /**
     * Returns the identifier chain.
     */
    string identifiersChain()
    {
        if (!level) return info.name;
        else return parentIdentifiersChain ~ "." ~ info.name;
    }

    /**
     * Returns the child node whose info.name matches to name.
     */
    IstNode findChildren(in char[] name)
    {
        if (!_cached) updateCache;
        if (auto r = name in _cache)
            return *r;
        else
            return null;
    }

}
//----

// Value as text to ubyte[] converters ----------------------------------------+

private __gshared static char[] invalidText = "invalid".dup;

/// Converts the raw data contained in a SerNodeInfo to its string representation.
char[] value2text(const SerNodeInfo* nodeInfo)
{
    char[] v2t_1(T)(){return to!string(*cast(T*)nodeInfo.value.ptr).dup;}
    char[] v2t_2(T)(){return to!string(cast(T[])nodeInfo.value[]).dup;}
    char[] v2t(T)(){if (!nodeInfo.isArray) return v2t_1!T; else return v2t_2!T;}
    //
    with (SerializableType) final switch(nodeInfo.type)
    {
        case _invalid:  return invalidText;
        case _object:   return cast(char[])(nodeInfo.value);
        case _bool:     return v2t!bool;
        case _ubyte:    return v2t!ubyte;
        case _byte:     return v2t!byte;
        case _ushort:   return v2t!ushort;
        case _short:    return v2t!short;
        case _uint:     return v2t!uint;
        case _int:      return v2t!int;
        case _ulong:    return v2t!ulong;
        case _long:     return v2t!long;
        case _float:    return v2t!float;
        case _double:   return v2t!double;
        case _char:     return v2t!char;
        case _wchar:    return v2t!wchar;
        case _string:   return v2t!string;
        case _wstring:  return v2t!wstring;
        case _dchar:    return v2t!dchar;
        case _stream:   return to!(char[])(nodeInfo.value[]);
        case _delegate: return v2t_2!char;
        case _function: return v2t_2!char;
    }
}

/// Converts the literal representation to a ubyte array according to type.
ubyte[] text2value(char[] text, const SerNodeInfo* nodeInfo)
{
    ubyte[] t2v_1(T)(){
        auto res = new ubyte[](type2size[nodeInfo.type]);
        *cast(T*) res.ptr = to!T(text);
        return res;
    }
    ubyte[] t2v_2(T)(){
        auto v = to!(T[])(text);
        auto res = new ubyte[](v.length * type2size[nodeInfo.type]);
        moveMem(res.ptr, v.ptr, res.length);
        return res;
    }
    ubyte[] t2v(T)(){
        if (!nodeInfo.isArray) return t2v_1!T; else return t2v_2!T;
    }
    //    
    with(SerializableType) final switch(nodeInfo.type)
    {
        case _invalid:  return cast(ubyte[])invalidText;
        case _bool:     return t2v!bool;
        case _ubyte:    return t2v!ubyte;
        case _byte:     return t2v!byte;
        case _ushort:   return t2v!ushort;
        case _short:    return t2v!short;
        case _uint:     return t2v!uint;
        case _int:      return t2v!int;
        case _ulong:    return t2v!ulong;
        case _long:     return t2v!long;
        case _float:    return t2v!float;
        case _double:   return t2v!double;
        case _char:     return t2v!char;
        case _wchar:    return t2v_2!wchar;
        case _dchar:    return t2v!dchar;
        case _string:   return t2v!string;
        case _wstring:  return t2v!wstring;
        case _stream:   return t2v_2!ubyte;
        case _object, _delegate, _function: return cast(ubyte[]) text;
    }
}
//----

// Descriptor to node & node to descriptor ------------------------------------+

/// Restores the raw value contained in a SerNodeInfo using the associated setter.
void nodeInfo2Declarator(const SerNodeInfo* nodeInfo)
{
    void toDecl1(T)()  {
        auto descr = cast(PropDescriptor!T *) nodeInfo.descriptor;
        descr.set( *cast(T*) nodeInfo.value.ptr );
    }
    void toDecl2(T)() {
        auto descr = cast(PropDescriptor!(T[]) *) nodeInfo.descriptor;
        descr.set(cast(T[]) nodeInfo.value[]);
    }
    void toDecl(T)() {
        (!nodeInfo.isArray) ? toDecl1!T : toDecl2!T;
    }
    //
    with (SerializableType) final switch(nodeInfo.type)
    {
        case _invalid, _object: break;
        case _bool:     toDecl!bool; break;
        case _byte:     toDecl!byte; break;
        case _ubyte:    toDecl!ubyte; break;
        case _short:    toDecl!short; break;
        case _ushort:   toDecl!ushort; break;
        case _int:      toDecl!int; break;
        case _uint:     toDecl!uint; break;
        case _long:     toDecl!long; break;
        case _ulong:    toDecl!ulong; break;
        case _float:    toDecl!float; break;
        case _double:   toDecl!double; break;
        case _char:     toDecl!char; break;
        case _wchar:    toDecl!wchar; break;
        case _dchar:    toDecl!dchar; break;
        case _string:   toDecl!string; break;
        case _wstring:  toDecl!wstring; break;
        case _stream:
            MemoryStream str = construct!MemoryStream;
            scope(exit) destruct(str);
            str.write(cast(ubyte*)nodeInfo.value.ptr, nodeInfo.value.length);
            str.position = 0;
            auto descr = cast(PropDescriptor!Stream*) nodeInfo.descriptor;
            descr.set(str);
            break;
        case _delegate, _function:
            char[] refId = cast(char[]) nodeInfo.value[];
            void* refvoid = ReferenceMan.reference!(void)(refId);
            void setFromRef(T)()
            {
                auto stuff = *cast(T*) refvoid;
                auto descr = cast(PropDescriptor!T*) nodeInfo.descriptor;
                descr.set(stuff);
            }
            if (nodeInfo.type == _delegate) setFromRef!GenericDelegate;
            else setFromRef!GenericFunction;
            break;
    }
}

/// Fills an SerNodeInfo according to an PropDescriptor
void setNodeInfo(T)(SerNodeInfo* nodeInfo, PropDescriptor!T* descriptor)
{
    scope(failure) nodeInfo.isDamaged = true;

    // simple, fixed-length (or convertible to), types
    static if (isSerSimpleType!T)
    {
        nodeInfo.type = text2type[T.stringof];
        nodeInfo.isArray = false;
        nodeInfo.value.length = type2size[nodeInfo.type];
        nodeInfo.descriptor = cast(Ptr) descriptor;
        nodeInfo.name = descriptor.name.dup;
        *cast(T*) nodeInfo.value.ptr = descriptor.get();
        //
        return;
    }

    // arrays types
    else static if (isSerArrayType!T)
    {
        nodeInfo.type = text2type[getElemStringOf!T];
        T value = descriptor.get();
        nodeInfo.value.length = value.length * type2size[nodeInfo.type];
        moveMem (nodeInfo.value.ptr, cast(void*) value.ptr, nodeInfo.value.length);
        //
        nodeInfo.isArray = true;
        nodeInfo.descriptor = cast(Ptr) descriptor;
        nodeInfo.name = descriptor.name.dup;
        //
        return;
    }

    // Serializable or Object
    else static if (isSerObjectType!T)
    {
        Object obj;
        char[] value;

        obj = cast(Object) descriptor.get();
        value = className(obj).dup;
        nodeInfo.type = text2type[typeof(obj).stringof];

        nodeInfo.isArray = false;
        nodeInfo.descriptor = cast(Ptr) descriptor;
        nodeInfo.name = descriptor.name.dup;
        nodeInfo.value.length = value.length;
        moveMem(nodeInfo.value.ptr, value.ptr, nodeInfo.value.length);
        //
        return;
    }

    // stream
    else static if (is(T : Stream))
    {
        nodeInfo.type = text2type[T.stringof];
        nodeInfo.isArray = false;
        nodeInfo.descriptor = cast(Ptr) descriptor;
        nodeInfo.name = descriptor.name.dup;
        //
        Stream value = descriptor.get();
        value.position = 0;
        nodeInfo.value.length = cast(uint) value.size;
        value.read(nodeInfo.value.ptr, cast(uint) value.size);
        //
        return;   
    }

    // delegate & function
    else static if (is(T == GenericDelegate) || is(T == GenericFunction))
    {
        nodeInfo.type = text2type[T.stringof];
        nodeInfo.isArray = false;
        nodeInfo.descriptor = cast(Ptr) descriptor;
        nodeInfo.name = descriptor.name.dup;
        //
        nodeInfo.value = cast(ubyte[]) descriptor.referenceID;
    }
}
//----

// Serialization formats ------------------------------------------------------+

/// Enumerates the possible serialization format
enum SerializationFormat : ubyte
{
    /// native binary format
    izbin,
    /// native text format
    iztxt,
    /// JSON chunks
    json
}

/// Propotype of a function that writes an IstNode representation to a Stream.
alias SerializationWriter = void function(IstNode istNode, Stream stream);

/// Propotype of a function that reads an IstNode representation from a Stream.
alias SerializationReader = void function(Stream stream, IstNode istNode);

// JSON format ----------------------------------------------------------------+
private void writeJSON(IstNode istNode, Stream stream)
{
    import std.json: JSONValue, toJSON;
    version(assert) const bool pretty = true; else const bool pretty = false;
    //    
    auto level  = JSONValue(istNode.level);
    auto type   = JSONValue(istNode.info.type);
    auto name   = JSONValue(istNode.info.name.idup);
    auto isarray= JSONValue(cast(ubyte)istNode.info.isArray);
    auto value  = JSONValue(value2text(istNode.info).idup);
    auto prop   = JSONValue(["level": level, "type": type, "name": name,
        "isarray": isarray, "value": value]);
    auto txt = toJSON(&prop, pretty).dup;
    //
    stream.write(txt.ptr, txt.length);   
}

private void readJSON(Stream stream, IstNode istNode)
{
    import std.json: JSONValue, parseJSON, JSON_TYPE;
    // cache property
    size_t cnt, len;
    char c;
    bool skip;
    auto immutable stored = stream.position;
    while (true)
    {
        if (stream.position == stream.size)
            break;
        ++len;
        stream.read(&c, 1);
        if (c == '\\')
            continue;
        if (c == '"') 
            skip = !skip;
        if (!skip)
        {
            cnt += (c == '{');
            cnt -= (c == '}');
        }
        if (cnt == 0)
            break;   
    }
    stream.position = stored;
    char[] cache;
    cache.length = len;
    stream.read(cache.ptr, cache.length);
    //
    const JSONValue prop = parseJSON(cache);
    
    const(JSONValue)* level = "level" in prop;
    if (level && level.type == JSON_TYPE.INTEGER)
        istNode.info.level = cast(uint) level.integer;
    else 
        istNode.info.isDamaged = true;
        
    const(JSONValue)* type = "type" in prop;
    if (type && type.type == JSON_TYPE.INTEGER)
        istNode.info.type = cast(SerializableType) type.integer;
    else 
        istNode.info.isDamaged = true;
        
    const(JSONValue)* name = "name" in prop;
    if (name && name.type == JSON_TYPE.STRING)
        istNode.info.name = name.str.dup;
    else 
        istNode.info.isDamaged = true;
        
    const JSONValue* isarray = "isarray" in prop;
    if (isarray && isarray.type == JSON_TYPE.INTEGER)
        istNode.info.isArray = cast(bool) isarray.integer;
    else 
        istNode.info.isDamaged = true;
        
    const(JSONValue)* value = "value" in prop;
    if (value && value.type == JSON_TYPE.STRING)
        istNode.info.value = text2value(value.str.dup, istNode.info);
    else
        istNode.info.isDamaged = true;
}
// ----

// Text format ----------------------------------------------------------------+
private void writeText(IstNode istNode, Stream stream)
{
    // indentation
    foreach(i; 0 .. istNode.level) stream.writeChar('\t');
    // type
    char[] type = type2text[istNode.info.type].dup;
    stream.write(type.ptr, type.length);
    // array
    char[2] arr = "[]";
    if (istNode.info.isArray) stream.write(arr.ptr, arr.length);
    stream.writeChar(' ');
    // name
    char[] name = istNode.info.name.dup;
    stream.write(name.ptr, name.length);
    // name value separators
    char[] name_value = " = \"".dup;
    stream.write(name_value.ptr, name_value.length);
    // value
    char[] value = value2text(istNode.info);
    with (SerializableType) if (istNode.info.type >= _char &&
        istNode.info.type <= _dchar && istNode.info.isArray)
    {
        value = escape(value, [['\n','n'],['"','"']]);
    }
    stream.write(value.ptr, value.length);
    char[] eol = "\"\n".dup;
    stream.write(eol.ptr, eol.length);
}

private void readText(Stream stream, IstNode istNode)
{
    char[] identifier;  
    // cache the property
    char[] propText;
    char old, curr;
    auto immutable initPos = stream.position;
    while(true)
    {
        // end of stream (error)
        if (stream.position == stream.size && old != '"')
        {
            // last char considered as " will miss in the prop value
            // and convertion may throw or suceeds with a wrong value.
            istNode.info.isDamaged = true;
            break;
        }
        old = curr;
        curr = stream.readChar;
        // regular end of property
        if (old == '"' && curr == '\n')
        {
            stream.position = stream.position - 1;
            break;
        }
        // end of stream without new line
        else if (old == '"' && stream.position == stream.size)
            break;
    }
    auto immutable endPos = stream.position;
    propText.length = cast(ptrdiff_t)(endPos - initPos);
    stream.position = initPos;
    stream.read(propText.ptr, propText.length);
    stream.position = endPos + 1;
    // level
    auto isLevelIndicator = (dchar c) => (c == ' ' || c == '\t');
    identifier = nextWord(propText, isLevelIndicator);
    istNode.info.level = cast(uint) identifier.length;
    // type
    identifier = nextWord(propText);
    if (identifier.length > 2)
        istNode.info.isArray = (identifier[$-2 .. $] == "[]");
    if (istNode.info.isArray)
        identifier = identifier[0 .. $-2];
    istNode.info.type = text2type[identifier];
    // name
    istNode.info.name = nextWord(propText).idup;
    // name value separator
    identifier = nextWord(propText);
    if (identifier != "=") istNode.info.isDamaged = true;
    // value
    skipWordUntil(propText, '"');
    identifier = propText[1..$-1];
    with (SerializableType) if (istNode.info.type >= _char &&
        istNode.info.type <= _dchar && istNode.info.isArray)
    {
        identifier = unEscape(identifier, [['\n','n'],['"','"']]);
    }
    istNode.info.value = text2value(identifier, istNode.info);
}
//----

// Binary format --------------------------------------------------------------+
version(BigEndian) private ubyte[] swapBE(const ref ubyte[] input, size_t div)
{
    if (div == 1) return input.dup;
    auto result = new ubyte[](input.length);
    switch(div) {
        default: break;
        case 2: foreach(immutable i; 0 .. input.length / div) {
            result[i*2+0] = input[i*2+1];
            result[i*2+1] = input[i*2+0];
        } break;
        case 4: foreach(immutable i; 0 .. input.length / div) {
            result[i*4+0] = input[i*4+3];
            result[i*4+1] = input[i*4+2];
            result[i*4+2] = input[i*4+1];
            result[i*4+3] = input[i*4+0];
        } break;           
        case 8: foreach(immutable i; 0 .. input.length / div) {
            result[i*8+0] = input[i*8+7];
            result[i*8+1] = input[i*8+6];
            result[i*8+2] = input[i*8+5];
            result[i*8+3] = input[i*8+4];
            result[i*8+4] = input[i*8+3];
            result[i*8+5] = input[i*8+2];
            result[i*8+6] = input[i*8+1];
            result[i*8+7] = input[i*8+0];
        } break;
    }
    return result;
}

private void writeBin(IstNode istNode, Stream stream)
{
    ubyte[] data;
    uint datalength;
    //header
    stream.writeUbyte(0x99);
    // level
    stream.writeUint(cast(uint) istNode.level);
    // type
    stream.writeUbyte(cast(ubyte) istNode.info.type);
    // as array
    stream.writeBool(istNode.info.isArray);
    // name length then name
    data = cast(ubyte[]) istNode.info.name;
    datalength = cast(uint) data.length;
    stream.writeUint(datalength);
    stream.write(data.ptr, datalength);
    // value length then value
    version(LittleEndian)
    {
        datalength = cast(uint) istNode.info.value.length;
        stream.writeUint(datalength);
        stream.write(istNode.info.value.ptr, datalength);
    }
    else
    {
        data = swapBE(istNode.info.value, type2size[istNode.info.type]);
        datalength = cast(uint) data.length;
        stream.writeUint(datalength);
        stream.write(data.ptr, datalength);
    }
    //footer
    stream.writeUbyte(0xA0);
}  

private void readBin(Stream stream, IstNode istNode)
{
    ubyte bin;
    ubyte[] data;
    uint datalength;
    uint beg, end;
    // cache property
    do stream.read(&bin, bin.sizeof);
        while (bin != 0x99 && stream.position != stream.size);
    beg = cast(uint) stream.position;
    do stream.read(&bin, bin.sizeof);
        while (bin != 0xA0 && stream.position != stream.size);
    end = cast(uint) stream.position;
    if (end <= beg) return;
    stream.position = beg;
    data.length = end - beg;
    stream.read(data.ptr, data.length);
    // level
    datalength = *cast(uint*) data.ptr;
    istNode.info.level = datalength;
    // type and array
    istNode.info.type = cast(SerializableType) data[4];
    istNode.info.isArray = cast(bool) data[5];      
    // name length then name;
    datalength = *cast(uint*) (data.ptr + 6);
    istNode.info.name = cast(string) data[10.. 10 + datalength].idup;
    beg =  10 +  datalength;      
    // value length then value
    version(LittleEndian)
    {
        datalength = *cast(uint*) (data.ptr + beg);
        istNode.info.value = data[beg + 4 .. beg + 4 + datalength];
    }
    else
    {
        datalength = *cast(uint*) (data.ptr + beg);
        data = data[beg + 4 .. beg + 4 + datalength];
        istNode.info.value = swapBE(data, type2size[istNode.info.type]);
    } 
}  
//----

/// The serialization format used when not specified.
alias defaultFormat = SerializationFormat.iztxt;

private SerializationWriter writeFormat(SerializationFormat format)
{
    with(SerializationFormat) final switch(format)
    {
        case izbin: return &writeBin;
        case iztxt: return &writeText;
        case json:  return &writeJSON;
    }
}

private SerializationReader readFormat(SerializationFormat format)
{
    with(SerializationFormat) final switch(format)
    {
        case izbin: return &readBin;
        case iztxt: return &readText;
        case json:  return &readJSON;
    }
}
//----

// Main Serializer class ------------------------------------------------------+

/**
 * Prototype of the event triggered when a serializer misses a property descriptor.
 * Params:
 *      node = The information used to determine the descriptor to return.
 *      descriptor = What the serializer want. If set to null then node is not restored.
 *      stop = the callee can set this value to true to stop the restoration
 *      process. According to the serialization context, this value can be noop.
 */
alias WantDescriptorEvent = void delegate(IstNode node, ref Ptr descriptor, out bool stop);

/**
 * Prototype of the event called when a serializer failed to get an object to deserialize.
 * Params:
 *      node = The information the callee uses to set the parameter serializable.
 *      obj = The Object the callee has to return.
 *      fromReference = When set to true, the serializer tries to find the Object
 *      using the ReferenceMan.
 */
alias WantObjectEvent = void delegate(IstNode node, ref Object obj, out bool fromRefererence);


//TODO-cfeature: Serializer error handling (using isDamaged + format readers errors).

/**
 * The Serializer class is specialized to store and restore the members of
 * an Object.
 *
 * PropertyPublisher:
 * A Serializer serializes trees of classes that implements the
 * PropertyPublisher interface. Their publications define what is saved or
 * restored. Object descriptors leading to an owned Object define the structure.
 * Basics types and array of basic types are handled. Special cases exist to
 * manage Stream properties, delegates or objects that are stored in the ReferenceMan.
 * It's even possible to handle more complex types by using or writing custom
 * PropertyPublishers, such as those defined in iz.classes.
 *
 * Ownership:
 * Sub objects can be fully serialized or not. This is determined by the ownership.
 * A sub object is considered as owned when its member 'declarator' matches to
 * to the member 'declarator' of the descriptor that returns this sub object.
 * When not owned, the sub object publications are not stored, instead, the
 * serializer writes its unique identifier, as found in the ReferenceMan.
 * When deserializing, the opposite process happens: the serializer tries to
 * restore the reference using the ReferenceMan. Ownership is automatically set
 * by the $(D PropertyPubliserImpl) analyzers.
 *
 * Representation:
 * The serializer uses an intermediate serialization tree (IST) that ensures a 
 * certain flexibilty against a traditional single-shot sequential serialization.
 * As expected for a serializer, object trees can be stored or restored by
 * a simple and single call to $(D publisherToStream()) in pair with
 * $(D streamToPublisher()) but the IST also allows to convert a Stream or
 * to find and restores a specific property.
 *
 * Errors:
 * Two events ($(D onWantDescriptor) and  $(D onWantObject)) allow to handle
 * the errors that could be encountered when restoring.
 * They permit a PropertyPublisher to be modified without any risk of deserialization
 * failure. Data saved from an older version can be recovered by deserializing in
 * a temporary property and converted to a new type. They can also be skipped,
 * without stopping the whole processing. Missing objects can be created when
 * The serializer ask for, since in this case, the original Object type and the
 * original variable names are passed as hint.
 */
class Serializer
{

private:

    /// the IST root
    IstNode _rootNode;
    /// the current parent node, always represents a PropertyPublisher
    IstNode _parentNode;
    /// the last created node 
    IstNode _previousNode; 
    /// the PropertyPublisher linked to _rootNode
    Object  _rootPublisher;

    Object  _declarator;

    WantDescriptorEvent _onWantDescriptor;
    WantObjectEvent _onWantObject;

    SerializationFormat _format;
    
    Stream _stream;
    PropDescriptor!Object _rootDescr;

    bool _mustWrite;
    bool _mustRead;

    void addIstNodeForDescriptor(T)(PropDescriptor!T * descriptor)
    if (isSerializable!T && !isSerObjectType!T)
    in
    {
        assert(descriptor);
        assert(descriptor.name.length);
    }
    body
    {
        IstNode propNode = _parentNode.addNewChildren;
        propNode.setDescriptor(descriptor);

        if (_mustWrite)
            writeFormat(_format)(propNode, _stream);


        _previousNode = propNode;
    }

    bool restoreFromEvent(IstNode node, out bool stop)
    {
        if (!_onWantDescriptor) 
            return false;
        bool done;
        _onWantDescriptor(node, node.info.descriptor, stop);
        done = (node.info.descriptor != null);
        if (done) 
        {
            nodeInfo2Declarator(node.info);
            return true;
        }
        else if (isSerObjectType(node.info.type))
            return true;
        return false;
    }

    bool descriptorMatchesNode(T)(PropDescriptor!T* descr, IstNode node)
    if (isSerializable!T)
    {   
        if (!descr) return false;
        if (!node.info.name.length) return false;
        if (descr.name != node.info.name) return false;
        static if (isArray!T) if (!node.info.isArray) return false;
        if (getSerializableTypeString!T != type2text[node.info.type]) return false;
        return true;
    }

    void addPropertyPublisher(PropDescriptor!Object* objDescr)
    {
        PropertyPublisher publisher;
        publisher = cast(PropertyPublisher) objDescr.get();

        // write/Set object node
        if (!_parentNode) _parentNode = _rootNode;
        else _parentNode = _parentNode.addNewChildren;
        _parentNode.setDescriptor(objDescr);
        if (_mustWrite)
            writeFormat(_format)(_parentNode, _stream);

        // reference: if not a PropDescriptorCollection
        if(!publisher)
            return;

        // reference: current collector is not owned at all
        if (_parentNode !is _rootNode && publisher.declarator is null)
            return;

        // reference: current collector is not owned by the declarator
        if (_parentNode !is _rootNode && objDescr.declarator !is publisher.declarator)
            return;

        // not a reference: current collector is owned (it has initialized the target),
        // so write its members
        foreach(immutable i; 0 .. publisher.publicationCount)
        {
            auto descr = cast(GenericDescriptor*) publisher.publicationFromIndex(i);
            const RuntimeTypeInfo rtti = publisher.publicationType(i);
            //
            void addValueProp(T)()
            {
                if (!rtti.array) addIstNodeForDescriptor(descr.typedAs!T);
                else addIstNodeForDescriptor(descr.typedAs!(T[]));
            }
            with(RuntimeType) final switch(rtti.type)
            {
                case _void, _struct, _real: assert(0);
                case _bool:   addValueProp!bool; break;
                case _byte:   addValueProp!byte; break;
                case _ubyte:  addValueProp!ubyte; break;
                case _short:  addValueProp!short; break;
                case _ushort: addValueProp!ushort; break;
                case _int:    addValueProp!int; break;
                case _uint:   addValueProp!uint; break;
                case _long:   addValueProp!long; break;
                case _ulong:  addValueProp!ulong; break;
                case _float:  addValueProp!float; break;
                case _double: addValueProp!double; break;
                case _char:   addValueProp!char; break;
                case _wchar:  addValueProp!wchar; break;
                case _dchar:  addValueProp!dchar; break;
                case _string: addValueProp!string; break;
                case _wstring:addValueProp!wstring; break;
                case _object:
                    auto _oldParentNode = _parentNode;
                    addPropertyPublisher(descr.typedAs!Object);
                    _parentNode = _oldParentNode;
                    break;
                case _stream:
                    addIstNodeForDescriptor(descr.typedAs!Stream);
                    break;
                case _delegate:
                    addIstNodeForDescriptor(descr.typedAs!GenericDelegate);
                    break;
                case _function:
                    addIstNodeForDescriptor(descr.typedAs!GenericFunction);
                    break;
            }
        }
    }

public:

    ///
    this()
    {
        _rootNode = construct!IstNode;
    }
    ///
    ~this()
    {
        _rootNode.deleteChildren;
        destruct(_rootNode);
    }

//---- serialization ----------------------------------------------------------+

    /** 
     * Saves the IST to a Stream.
     *
     * Params:
     *      outputStream = The stream where te data are written.
     *      format = The data format.
     */
    void istToStream(Stream outputStream, SerializationFormat format = defaultFormat)
    {
        _format = format;
        _stream = outputStream;
        _mustWrite = true;
        //
        void writeNodesFrom(IstNode parent)
        {
            writeFormat(_format)(parent, _stream); 
            foreach(node; parent.children)
            {
                auto child = cast(IstNode) node;
                if (isSerObjectType(child.info.type))
                    writeNodesFrom(child);
                else writeFormat(_format)(child, _stream); 
            }
        }
        writeNodesFrom(_rootNode);
        //
        _mustWrite = false;
        _stream = null;
    }

    /**
     * Builds the IST from a PropertyPublisher and stores each publication
     * of the publisher in a stream.
     *
     * Storage is performed just after a publication is detected.
     *
     * Params:
     *      root = Either a PropertyPublisher or an object that's been mixed
     *      with the PropertyPublisherImpl template.
     *      outputStream = The stream where the data are written.
     *      format = The serialized data format.
     */
    void publisherToStream(Object root, Stream outputStream,
        SerializationFormat format = defaultFormat)
    {
        _format = format;
        _stream = outputStream;
        _mustWrite = true; 
        _rootNode.deleteChildren;
        _previousNode = null;
        _parentNode = null;
        PropDescriptor!Object rootDescr = PropDescriptor!Object(&root, "root");
        addPropertyPublisher(&rootDescr);
        _mustWrite = false;
        _stream = null;
    }

    /**
     * Builds the IST from a PropertyPublisher.
     */
    void publisherToIst(Object root)
    {
        _mustWrite = false;
        _rootNode.deleteChildren;
        _previousNode = null;
        _parentNode = null;
        PropDescriptor!Object rootDescr = PropDescriptor!Object(cast(Object*)&root, "root");
        addPropertyPublisher(&rootDescr);
        _mustWrite = false;
        _stream = null;
    }

//------------------------------------------------------------------------------
//---- deserialization --------------------------------------------------------+

    /**
     * Restores the IST to a PropertyPublisher.
     *
     * Can be called after $(D streamToIst), which builds the IST without defining
     * the $(D PropDescriptor) that match to each node. The descriptors are
     * dynamically set using the publications of the root. If the procedure doesn't
     * detect the descriptor that matches to an IST node, and if assigned,
     * then the events $(D onWantObject) and $(D onWantDescriptor) are called.
     *
     * Params:
     *      root = The Object from where the restoreation starts. It has to be
     *      a PropPublisher.
     */
    void istToPublisher(Object root)
    {
        void restoreFrom(IstNode node, PropertyPublisher target)
        {
            if (!target) return;
            foreach(child; node.children)
            {
                bool done;
                IstNode childNode = cast(IstNode) child;
                if (void* t0 = target.publicationFromName(childNode.info.name))
                {
                    PropDescriptor!int* t1 = cast(PropDescriptor!int*)t0;
                    if (t1.rtti.array == childNode.info.isArray && 
                    t1.rtti.type == childNode.info.type)
                    {
                        childNode.info.descriptor = t1;
                        nodeInfo2Declarator(childNode.info);
                        if (isSerObjectType(childNode.info.type))
                        {
                            auto t2 = cast(PropDescriptor!Object*) t1;
                            Object o = t2.get();
                            bool fromRef;
                            if (!o && _onWantObject)
                                _onWantObject(childNode, o, fromRef);

                            if (fromRef || !o)
                            {
                                Object* po = ReferenceMan.reference!(Object)(childNode.identifiersChain);
                                if (po)
                                {
                                    t2.set(*po);
                                    done = true;
                                }
                            }
                            else
                            {
                                auto t3 = cast(PropertyPublisher) o;
                                if (t3)
                                {
                                    restoreFrom(childNode, t3);
                                    done = true;
                                }
                            }

                        }
                        else done = true;
                    }
                }
                if (!done)
                {
                    bool noop;
                    restoreFromEvent(childNode, noop);
                }
            }
        }
        if (auto pub = cast(PropertyPublisher) root)
            restoreFrom(_rootNode, pub);
    }

    /**
     * Builds the IST from a Stream and restores from root.
     *
     * This method actually call successively $(D streamToIst()) then
     * $(D istToPublisher()).
     *
     * Params:
     *      inputStream: The Stream that contains the data previously serialized.
     *      root = The Object from where the restoreation starts. It has to be
     *      a PropPublisher.
     */
    void streamToPublisher(Stream inputStream, Object root,
        SerializationFormat format = defaultFormat)
    {
        streamToIst(inputStream, format);
        istToPublisher(root);
    }

    /**
     * Builds the IST from a stream.
     *
     * After the call the IST nodes are not yet linked to their PropDescriptor.
     * The deserialization process can be achieved manually, using $(D findNode())
     * in pair with $(D restoreProperty()) or automatically, using $(D istToPublisher()).
     * This function can also be used to convert from a format to another.
     *
     * Params:
     *      inputStream = The stream containing the serialized data.
     *      format = The format of the serialized data.
     */
    void streamToIst(Stream inputStream, SerializationFormat format = defaultFormat)
    {
        IstNode[] unorderNodes;
        IstNode[] parents;
        _rootNode.deleteChildren;
        _mustRead = false;
        _stream = inputStream;
        _format = format;
        
        unorderNodes ~= _rootNode;
        while(inputStream.position < inputStream.size)
        {     
            readFormat(_format)(_stream, unorderNodes[$-1]);
            unorderNodes ~= construct!IstNode;
        }
        destruct(unorderNodes[$-1]);
        unorderNodes.length -= 1;
        
        if (unorderNodes.length > 1)
        foreach(immutable i; 1 .. unorderNodes.length)
        {
            unorderNodes[i-1].info.isLastChild = 
              unorderNodes[i].info.level < unorderNodes[i-1].info.level ||
              (isSerObjectType(unorderNodes[i-1].info.type) && unorderNodes[i-1].info.level ==
                unorderNodes[i].info.level);
        }
        
        parents ~= _rootNode;
        foreach(immutable i; 1 .. unorderNodes.length)
        {
            auto node = unorderNodes[i];
            parents[$-1].addChild(node);

            // !!! object wihtout props !!! (e.g reference)
            
            if (node.info.isLastChild && !isSerObjectType(node.info.type))
                parents.length -= 1;
             
            if (isSerObjectType(node.info.type)  && !node.info.isLastChild )
                parents ~= node;
        }  
        //
        _stream = null;  
    }

    /**
     * Finds the tree node matching to a name chain.
     *
     * Params:
     *      cache = Set to true to activate the internal IST node caching.
     *      This should only be set to true when performing many queries.
     *      descriptorName = The name chain that identifies the node.
     * Returns:
     *      A reference to the node that matches to the property or nulll.
     */ 
    IstNode findNode(bool cache = false)(in char[] descriptorName)
    {
        if (_rootNode.info.name == descriptorName)
            return _rootNode;
        IstNode scanNode(IstNode parent, in char[] namePipe)
        {
            static if (cache)
            {
                if (auto r = parent.findChildren(descriptorName))
                    return r;
                else foreach(node; parent.children)
                {
                    if (auto r = scanNode(node, descriptorName))
                        return r;
                }
                return null;
            }
            else
            {
                IstNode result;
                foreach(node; parent.children)
                {
                    auto child = cast(IstNode) node;
                    if (namePipe ~ "." ~ child.info.name == descriptorName)
                        return child;
                    if (child.childrenCount)
                        result = scanNode(child, namePipe ~ "." ~ child.info.name);
                    if (result)
                        return result;
                }
                return result;
            }
        }
        return scanNode(_rootNode, _rootNode.info.name);
    }

    /**
     * Restores the IST from an arbitrary tree node.
     *
     * The process is lead by the nodeInfo associated to the node.
     * If the descriptor is not defined then wantDescriptorEvent is called.
     * It means that this method can be used to deserialize to an arbitrary descriptor,
     * for example after a call to streamToIst().
     *
     * Params:
     *      node = The IST node from where the restoration starts.
     *      It can be determined by a call to $(D findNode()).
     *      recursive = When set to true the restoration is recursive.
     */  
    void nodeToPublisher(IstNode node, bool recursive = false)
    {
        bool restore(IstNode current)
        {
            bool result = true;
            if (current.info.descriptor && current.info.name ==
                (cast(PropDescriptor!byte*)current.info.descriptor).name)
                    nodeInfo2Declarator(current.info);
            else
            {
                bool stop;
                result = restoreFromEvent(current, stop);
                result &= !stop;
            }
            return result;    
        }
        bool restoreLoop(IstNode current)
        {
            if (!restore(current)) return false;
            foreach(child; current.children)
            {
                auto childNode = cast(IstNode) child;
                if (!restore(childNode)) return false;
                if (isSerObjectType(childNode.info.type) & recursive)
                    if (!restoreLoop(childNode)) return false;
            }
            return true;
        }
        restoreLoop(node);
    }

    /**
     * Restores the property associated to an IST node using the setter of the
     * PropDescriptor passed as parameter.
     *
     * Params:
     *      node = An IstNode. Can be determined by a call to findNode()
     *      descriptor = The PropDescriptor whose setter is used to restore the node data.
     *      if not specified then the onWantDescriptor event may be called.
     */
    void nodeToProperty(T)(IstNode node, PropDescriptor!T* descriptor = null)
    {
        if (descriptorMatchesNode!T(descriptor, node))
        {
            node.info.descriptor = descriptor;
            nodeInfo2Declarator(node.info);
        }
        else
        {
            bool noop;
            restoreFromEvent(node, noop);
        }
    }

//------------------------------------------------------------------------------
//---- miscellaneous properties -----------------------------------------------+

    /// The IST can be modified, build, cleaned from the root node
    @property IstNode serializationTree(){return _rootNode;}

    /// Event called when the serializer misses a property descriptor.
    @property WantDescriptorEvent onWantDescriptor(){return _onWantDescriptor;}

    /// ditto
    @property void onWantDescriptor(WantDescriptorEvent value){_onWantDescriptor = value;}

    /// Event called when the serializer misses a PropDescriptor!Object
    @property WantObjectEvent onWantObject(){return _onWantObject;}

    /// ditto
    @property void onWantObject(WantObjectEvent value){_onWantObject = value;}

//------------------------------------------------------------------------------

}
///
unittest
{
    // defines two serializable classes
    class B: PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        @SetGet uint data1 = 1, data2 = 2;
        this(){collectPublications!B;}
        void reset(){data1 = 0; data2 = 0;}
    }
    class A: PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        @SetGet B sub1, sub2;
        this()
        {
            sub1 = construct!B;
            sub2 = construct!B;
            // sub1 and sub2 are fully serialized because they already exist
            // when the analyzers run, otherwise they would be considered as
            // reference and their members would not be serialized.
            collectPublications!A;
        }
        ~this(){destruct(sub1, sub2);}
    }

    MemoryStream stream = construct!MemoryStream;
    Serializer serializer = construct!Serializer;
    A a = construct!A;
    // serializes
    serializer.publisherToStream(a, stream);
    // reset the fields
    a.sub1.reset;
    a.sub2.reset;
    stream.position = 0;
    // deserializes
    serializer.streamToPublisher(stream, a);
    // check the restored values
    assert(a.sub1.data1 == 1);
    assert(a.sub2.data1 == 1);
    assert(a.sub1.data2 == 2);
    assert(a.sub2.data2 == 2);
}

//----

// Miscellaneous helpers ------------------------------------------------------+
/**
 * Serializes a PropertyPublisher to a file.
 *
 * This helper function works in pair with fileToPublisher().
 * It is typically used to save configuration files, session backups, etc.
 *
 * Params:
 *      pub = The PropertyPublisher to save.
 *      filename = The target file, always created or overwritten.
 *      format = Optional, the serialization format, by default iztext.
 */
void publisherToFile(Object pub, in char[] filename,
    SerializationFormat format = defaultFormat)
{
    MemoryStream str = construct!MemoryStream;
    Serializer ser = construct!Serializer;
    scope(exit) destruct(str, ser);
    //
    ser.publisherToStream(pub, str, format);
    str.saveToFile(filename);
}

/**
 * Deserializes a file to a PropertyPublisher.
 *
 * This helper function works in pair with publisherToFile().
 * It is typically used to load configuration files, session backups, etc.
 *
 * Params:
 *      filename = The source file.
 *      pub = The target PropertyPublisher.
 *      format = optional, the serialization format, by default iztext.
 */
void fileToPublisher(in char[] filename, Object pub,
    SerializationFormat format = defaultFormat)
{
    MemoryStream str = construct!MemoryStream;
    Serializer ser = construct!Serializer;
    scope(exit) destruct(str, ser);
    //
    str.loadFromFile(filename);
    ser.streamToPublisher(str, pub, format);
}
//----

version(unittest)
{
    unittest
    {
        char[] text;
        ubyte[] value;
        SerNodeInfo inf;
        //
        value = [13];
        text = "13".dup;
        inf.type = SerializableType._byte;
        inf.value = value ;
        inf.isArray = false;
        assert(value2text(&inf) == text);
        assert(text2value(text, &inf) == value);
        //
        value = [13,14];
        text = "[13, 14]".dup;
        inf.type = SerializableType._byte ;
        inf.value = value ;
        inf.isArray = true;
        assert(value2text(&inf) == text);
        assert(text2value(text, &inf) == value);
        //  
        void testType(T)(T t)
        {
            char[] asText;
            T v = t;
            SerNodeInfo info;
            PropDescriptor!T descr;
            //
            descr.define(&v, "property");
            setNodeInfo!T(&info, &descr);
            //
            asText = to!string(v).dup;
            assert(value2text(&info) == asText, T.stringof);
            static if (!isArray!T) 
                assert(*cast(T*)(text2value(asText, &info)).ptr == v, T.stringof);
            static if (isArray!T) 
                assert(cast(ubyte[])text2value(asText, &info)==cast(ubyte[])v,T.stringof);
        }

        struct ImpConv{uint _field; alias _field this;}
        auto ic = ImpConv(8);

        testType('c');
        testType("azertyuiop".dup);
        testType!uint(ic); 
        testType(cast(byte)8);      testType(cast(byte[])[8,8]);
        testType(cast(ubyte)8);     testType(cast(ubyte[])[8,8]);
        testType(cast(short)8);     testType(cast(short[])[8,8]);
        testType(cast(ushort)8);    testType(cast(ushort[])[8,8]);
        testType(cast(int)8);       testType(cast(int[])[8,8]);
        testType(cast(uint)8);      testType(cast(uint[])[8,8]);
        testType(cast(long)8);      testType(cast(long[])[8,8]);
        testType(cast(ulong)8);     testType(cast(ulong[])[8,8]);
        testType(cast(float).8f);   testType(cast(float[])[.8f,.8f]);
        testType(cast(double).8);   testType(cast(double[])[.8,.8]);
        
        writeln("Serializer passed the text-value conversions test");
    }

    unittest 
    {
        foreach(fmt;EnumMembers!SerializationFormat)
            testByFormat!fmt();
        //testByFormat!(SerializationFormat.iztxt)();
        //testByFormat!(SerializationFormat.izbin)();
        //testByFormat!(SerializationFormat.json)();
    }
    
    class Referenced1 {}
    
    class ReferencedUser: PropertyPublisher
    {
        mixin PropertyPublisherImpl;

        SerializableReference fSerRef;
        Referenced1 * fRef;

        void doRestore(Object sender)
        {
            fRef = fSerRef.restoreReference!Referenced1;
        }
    
        this()
        {
            fSerRef = construct!SerializableReference;
            fSerRef.onRestored = &doRestore;
            collectPublications!ReferencedUser;
        }

        ~this() {destruct(fSerRef);}

        @Get SerializableReference theReference()
        {
            fSerRef.storeReference!Referenced1(fRef);
            return fSerRef;
        }
        @Set void theReference(SerializableReference value)
        {
            // when a sub publisher is owned the setter is a noop.
            // actually the serializer use the descriptor getter
            // to knwo where the members of the sub pub. are located.
        }
    }
    
    class ClassA: ClassB
    {
        private:
            ClassB _aB1, _aB2;
            PropDescriptor!Object aB1descr, aB2descr;
        public:
            this() {

                assert(!this.publicationFromName("aB1"));
                assert(!this.publicationFromName("aB2"));

                _aB1 = construct!ClassB;
                _aB2 = construct!ClassB;
                aB1descr.define(cast(Object*)&_aB1, "aB1", this);
                aB2descr.define(cast(Object*)&_aB2, "aB2", this);

                // add publications by hand.
                _publishedDescriptors ~= cast(void*) &aB1descr;
                _publishedDescriptors ~= cast(void*) &aB2descr;

                // without the scanners ownership must be set manually
                setTargetObjectOwner(&aB1descr, this);
                setTargetObjectOwner(&aB2descr, this);
                assert(targetObjectOwnedBy(&aB1descr, this));
                assert(targetObjectOwnedBy(&aB2descr, this));
            }
            ~this() {
                destruct(_aB1, _aB2);
            }
            override void reset() {
                super.reset;
                _aB1.reset;
                _aB2.reset;
            }
    }
    
    class ClassB : PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        private:
            @SetGet int[]  anIntArray;
            @SetGet float  aFloat;
            @SetGet char[] someChars;
        public:
            this() {
                collectPublications!ClassB;
                anIntArray = [0, 1, 2, 3];
                aFloat = 0.123456f;
                someChars = "azertyuiop".dup;
            }
            void reset() {
                anIntArray = anIntArray.init;
                aFloat = 0.0f;
                someChars = someChars.init;
            }
    }

    // by format only use the system based on manual declarations
    void testByFormat(SerializationFormat format)()
    {
        MemoryStream str  = construct!MemoryStream;
        Serializer ser    = construct!Serializer;
        ClassB b = construct!ClassB;
        ClassA a = construct!ClassA;
        scope(exit) destruct(str, ser, b, a);

        // basic sequential store/restore ---+
        ser.publisherToStream(b,str,format);
        b.reset;
        assert(b.anIntArray == []);
        assert(b.aFloat == 0.0f);
        assert(b.someChars == "");
        str.position = 0;
        ser.streamToPublisher(str,b,format);
        assert(b.anIntArray == [0, 1, 2, 3]);
        assert(b.aFloat == 0.123456f);
        assert(b.someChars == "azertyuiop");
        //----

        // arbitrarily find a prop ---+
        assert(ser.findNode("root.anIntArray"));
        assert(ser.findNode("root.aFloat"));
        assert(ser.findNode("root.someChars"));
        assert(!ser.findNode("root."));
        assert(!ser.findNode("aFloat"));
        assert(!ser.findNode("root.someChar"));
        assert(!ser.findNode(""));
        //----
        
        // restore elsewhere than in the declarator ---+
        float outside;
        auto node = ser.findNode("root.aFloat");
        auto aFloatDescr = PropDescriptor!float(&outside, "aFloat");
        ser.nodeToProperty(node, &aFloatDescr);
        assert(outside == 0.123456f);
        //----

        // nested declarations with super.declarations ---+
        str.clear;
        ser.publisherToStream(a,str,format);
        a.reset;
        assert(a.anIntArray == []);
        assert(a.aFloat == 0.0f);
        assert(a.someChars == "");
        assert(a._aB1.anIntArray == []);
        assert(a._aB1.aFloat == 0.0f);
        assert(a._aB1.someChars == "");
        assert(a._aB2.anIntArray == []);
        assert(a._aB2.aFloat == 0.0f);
        assert(a._aB2.someChars == "");
        str.position = 0;

        ser.streamToPublisher(str,a,format);
        assert(a.anIntArray == [0, 1, 2, 3]);
        assert(a.aFloat ==  0.123456f);
        assert(a.someChars == "azertyuiop");
        assert(a._aB1.anIntArray == [0, 1, 2, 3]);
        assert(a._aB1.aFloat ==  0.123456f);
        assert(a._aB1.someChars == "azertyuiop");
        assert(a._aB2.anIntArray == [0, 1, 2, 3]);
        assert(a._aB2.aFloat ==  0.123456f);
        assert(a._aB2.someChars == "azertyuiop");
        //----

        // store & restore a serializable reference ---+
        auto ref1 = construct!(Referenced1);
        auto ref2 = construct!Referenced1;
        auto usrr = construct!ReferencedUser;
        scope(exit) destruct(ref1, ref2, usrr);
        
        assert( ReferenceMan.storeReference!Referenced1(&ref1, "referenced.ref1"));
        assert( ReferenceMan.storeReference!Referenced1(&ref2, "referenced.ref2"));
        assert( ReferenceMan.referenceID!Referenced1(&ref1) == "referenced.ref1");
        assert( ReferenceMan.referenceID!Referenced1(&ref2) == "referenced.ref2");

        str.clear;
        usrr.fRef = &ref1;
        ser.publisherToStream(usrr, str, format);

        usrr.fRef = &ref2;
        assert(*usrr.fRef is ref2);
        str.position = 0;
        ser.streamToPublisher(str, usrr, format);
        assert(*usrr.fRef is ref1);

        usrr.fRef = null;
        assert(usrr.fRef is null);
        str.position = 0;
        ser.streamToPublisher(str, usrr, format);
        assert(*usrr.fRef is ref1);

        str.clear;
        usrr.fRef = null;
        ser.publisherToStream(usrr, str, format);
        usrr.fRef = &ref2;
        assert(*usrr.fRef is ref2);
        str.position = 0;
        ser.streamToPublisher(str, usrr, format);
        assert(usrr.fRef is null);
        //----

        // auto store, stream to ist, restores manually ---+
        str.clear;  
        ser.publisherToStream(b,str,format);
        b.reset;
        assert(b.anIntArray == []);
        assert(b.aFloat == 0.0f);
        assert(b.someChars == "");
        str.position = 0;
        ser.streamToIst(str,format);

        auto node_anIntArray = ser.findNode("root.anIntArray");
        if(node_anIntArray) ser.nodeToProperty(node_anIntArray,
             b.publication!(int[])("anIntArray"));
        else assert(0);
        auto node_aFloat = ser.findNode("root.aFloat");
        if(node_aFloat) ser.nodeToProperty(node_aFloat,
            b.publication!float("aFloat"));
        else assert(0);  
        auto node_someChars = ser.findNode("root.someChars");
        if(node_someChars) ser.nodeToProperty(node_someChars,
            b.publication!(char[])("someChars"));
        else assert(0);
        assert(b.anIntArray == [0, 1, 2, 3]);
        assert(b.aFloat == 0.123456f);
        assert(b.someChars == "azertyuiop");
        //----

        // decomposed de/serialization phases with event ---+ 
        void wantDescr(IstNode node, ref Ptr matchingDescriptor, out bool stop)
        {
            immutable string chain = node.parentIdentifiersChain;
            if (chain == "root")
                matchingDescriptor = a.publicationFromName(node.info.name);
            else if (chain == "root.aB1")
                matchingDescriptor = a._aB1.publicationFromName(node.info.name);
            else if (chain == "root.aB2")
                matchingDescriptor = a._aB2.publicationFromName(node.info.name);
        }

        str.clear;
        ser.publisherToIst(a);
        ser.istToStream(str,format);
        a.reset;    
        assert(a.anIntArray == []);
        assert(a.aFloat == 0.0f);
        assert(a.someChars == "");
        assert(a._aB1.anIntArray == []);
        assert(a._aB1.aFloat == 0.0f);
        assert(a._aB1.someChars == "");
        assert(a._aB2.anIntArray == []);
        assert(a._aB2.aFloat == 0.0f);
        assert(a._aB2.someChars == "");
        str.position = 0;
        ser.onWantDescriptor = &wantDescr;
        ser.streamToIst(str,format);
        auto nd = ser.findNode("root");
        assert(nd);
        ser.nodeToPublisher(nd, true);
        assert(a.anIntArray == [0, 1, 2, 3]);
        assert(a.aFloat ==  0.123456f);
        assert(a.someChars == "azertyuiop");
        assert(a._aB1.anIntArray == [0, 1, 2, 3]);
        assert(a._aB1.aFloat ==  0.123456f);
        assert(a._aB1.someChars == "azertyuiop");
        assert(a._aB2.anIntArray == [0, 1, 2, 3]);
        assert(a._aB2.aFloat ==  0.123456f);
        assert(a._aB2.someChars == "azertyuiop");
        ser.onWantDescriptor = null;
        // ----

        // struct serialized as basicType ---+

        import iz.enumset: EnumSet, Set8;
        enum A {a0,a1,a2}
        alias SetofA = EnumSet!(A,Set8);

        class Bar: PropertyPublisher
        {
            mixin PropertyPublisherImpl;

            private: 
                SetofA _set;
                PropDescriptor!SetofA setDescr;
            public:
                this()
                {
                    setDescr.define(&_set,"set");
                    with(A) _set = SetofA(a1,a2);
                    collectPublications!Bar;
                }
                // struct can only be serialized using a representation
                // whose type is iteself serializable
                @Set set(ubyte value){_set = value;}
                @Get ubyte set(){return _set.container;}
        }

        str.clear;
        auto bar = construct!Bar;
        scope(exit) bar.destruct;
        
        ser.publisherToStream(bar, str, format);
        bar._set = [];
        str.position = 0;
        ser.streamToPublisher(str, bar, format);
        assert( bar._set == SetofA(A.a1,A.a2), to!string(bar.set));
        // ----

        writeln("Serializer passed the ", format, " format test");
    }

    // test fields renamed between two versions ---+
    class Source: PropertyPublisher
    {
        @GetSet private uint _a = 78;
        @GetSet private char[] _b = "foobar".dup;
        mixin PropertyPublisherImpl;
        this(){collectPublications!Source;}
    }

    class Target: PropertyPublisher
    {
        @GetSet private int _c;
        @GetSet private ubyte[] _d;
        mixin PropertyPublisherImpl;
        this(){collectPublications!Target;}
    }

    unittest
    {
        Source source = construct!Source;
        Target target = construct!Target;
        Serializer ser = construct!Serializer;
        MemoryStream str = construct!MemoryStream;
        scope(exit) destruct(source, ser, str, target);

        ser.publisherToStream(source, str);
        str.position = 0;

        void error(IstNode node, ref Ptr matchingDescriptor, out bool stop)
        {
            if (node.info.name == "a")
                matchingDescriptor = target.publication!(int)("c");
            else if (node.info.name == "b")
                matchingDescriptor = target.publication!(ubyte[])("d");
            stop = false;
        }
        ser.onWantDescriptor = &error;
        ser.streamToPublisher(str, target);
        assert(target._c == 78);
        assert(cast(char[])target._d == "foobar");
    }
    //----

    // test the RuntimeTypeInfo-based serialization ----+

    class SubPublisher: PropertyPublisher
    {
        // fully serialized (initializer is MainPub)
        mixin PropertyPublisherImpl;
        @SetGet char[] _someChars = "awhyes".dup;
        this(){collectPublicationsFromFields!SubPublisher;}
    }
    class RefPublisher: PropertyPublisher
    {
        // only ref is serialized (initializer is not MainPub)
        mixin PropertyPublisherImpl;
        this(){collectPublicationsFromFields!RefPublisher;}
        @SetGet uint _a;
    }
    class MainPublisher: PropertyPublisher
    {
        mixin PropertyPublisherImpl;

        // target when _subPublisher wont be found
        SubPublisher _anotherSubPubliser;

        // the sources for the references
        void delegate(uint) _delegateSource;
        RefPublisher _refPublisherSource;
        string dgTest;

        @SetGet ubyte _a = 12;
        @SetGet byte _b = 21;
        @SetGet byte _c = 31;
        @SetGet dchar[] _t = "line1\"inside dq\"\nline2\nline3"d.dup;
        @SetGet void delegate(uint) _delegate;
        MemoryStream _stream;

        @SetGet RefPublisher _refPublisher; //initially null, so it's a ref.
        @SetGet SubPublisher _subPublisher; //initially assigned so 'this' is the owner.

        this()
        {
            _refPublisherSource = construct!RefPublisher; // not published
            _subPublisher = construct!SubPublisher;
            _anotherSubPubliser = construct!SubPublisher;
            _stream = construct!MemoryStream;
            _stream.writeUbyte(0XFE);
            _stream.writeUbyte(0XFD);
            _stream.writeUbyte(0XFC);
            _stream.writeUbyte(0XFB);
            _stream.writeUbyte(0XFA);
            _stream.writeUbyte(0XF0);

            // collect publications before ref are assigned
            collectPublications!MainPublisher;

            _delegateSource = &delegatetarget;
            _delegate = _delegateSource;
            _refPublisher = _refPublisherSource; // e.g assingation during runtime

            assert(_refPublisher.declarator !is this);
            assert(_refPublisher.declarator is null);

            auto dDescr = publication!GenericDelegate("delegate", false);
            assert(dDescr);

            auto strDesc = publicationFromName("stream");
            assert(strDesc);

            ReferenceMan.storeReference(cast(Object*)&_refPublisherSource,
                "root.refPublisher");
            ReferenceMan.storeReference(cast(void*)&_delegateSource,
                "mainpub.at.delegatetarget");
            dDescr.referenceID = "mainpub.at.delegatetarget";
        }
        ~this()
        {
            destruct(_refPublisherSource);
            destruct(_anotherSubPubliser);
            destruct(_stream);
        }
        void delegatetarget(uint param){dgTest = "awyesss";}
        void reset()
        {
            _a = 0; _b = 0; _c = 0; _t = _t.init;
            _subPublisher.destruct;
            _subPublisher = null; // wont be found anymore during deser.
            _anotherSubPubliser._someChars = "".dup;
            _delegate = null;
            _refPublisher = null;
            _stream.size = 0;
        }
        @Get Stream stream()
        {
            return _stream;
        }
        @Set stream(Stream str)
        {
            str.position = 0;
            _stream.loadFromStream(str);
            _stream.position = 0;
        }
    }

    unittest
    {
        MainPublisher c = construct!MainPublisher;
        Serializer ser = construct!Serializer;
        MemoryStream str = construct!MemoryStream;
        scope(exit) destruct(c, ser, str);

        void objectNotFound(IstNode node, ref Object serializable, out bool fromReference)
        {
            if (node.info.name == "subPublisher")
            {
                serializable = c._anotherSubPubliser;
            }
            if (node.info.name == "refPublisher")
                fromReference = true;
        }

        ser.onWantObject = &objectNotFound;
        ser.publisherToStream(c, str);
        //str.saveToFile(r"test.txt");

        c.reset;
        str.position = 0;
        ser.streamToPublisher(str, c);

        assert(c._a == 12);
        assert(c._b == 21);
        assert(c._c == 31);
        assert(c._t == "line1\"inside dq\"\nline2\nline3");
        assert(c._refPublisher is c._refPublisherSource);
        assert(c._anotherSubPubliser._someChars == "awhyes");
        assert(c._delegate);
        c._delegate(123);
        assert(c.dgTest == "awyesss");
        assert(c._stream.readUbyte == 0xFE);
        assert(c._stream.readUbyte == 0xFD);
        assert(c._stream.readUbyte == 0xFC);
        assert(c._stream.readUbyte == 0xFB);
        assert(c._stream.readUbyte == 0xFA);
        assert(c._stream.readUbyte == 0xF0);
    }
    //----

    // test generic Reference restoring ---+
    class HasGenRef: PropertyPublisher
    {
        // the source, usually comes from outside
        Object source;
        // what's gonna be assigned
        Object target;
        mixin PropertyPublisherImpl;
        this()
        {
            collectPublications!HasGenRef;
            source = construct!Object;
            ReferenceMan.storeReference!void(cast(void*)source,"thiswillwork");
            target = source;
        }
        ~this()
        {
            destruct(source);
        }

        @Get const(char)[] objectReference()
        {
            // get ID from what's currently assigned
            return ReferenceMan.referenceID!void(cast(void*)target);
        }

        @Set objectReference(char[] value)
        {
            // ID -> Reference -> assign the variable
            target = cast(Object) ReferenceMan.reference!void(value);
        }
    }

    unittest
    {
        MemoryStream str = construct!MemoryStream;
        Serializer ser = construct!Serializer;
        HasGenRef obj = construct!HasGenRef;
        scope(exit) destruct(ser, str, obj);

        ser.publisherToStream(obj, str);
        str.position = 0;
        obj.target = null;

        ser.streamToPublisher(str, obj);
        assert(obj.target == obj.source);
    }
    //----
}

