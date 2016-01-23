/**
 * High-level iz classes.
 */
module iz.classes;

import
    std.traits, std.string, std.algorithm, std.array, std.range;
import
    iz.types, iz.memory, iz.containers, iz.streams, iz.properties,
    iz.serializer, iz.referencable, iz.observer;

version(unittest) import std.stdio;

/**
 * The PublishedObjectArray class template allows to serialize an array of
 * PropertyPublisher.
 *
 * A Serializer is not able to directly handle object arrays but this class
 * does the task automatically by managing the internal list of publications.
 *
 * The life-time of the objects is automatically handled by the internal container.
 *
 * Params:
 *      ItemClass = The common items type. It must be a PropertyPublisher descendant.
 */
class PublishedObjectArray(ItemClass): PropertyPublisher
if(is(ItemClass : PropertyPublisher))
{

    mixin PropertyPublisherImpl;

private:

    size_t _firstItemsDescrIndex;

protected:

    static immutable string _fmtName = "item<%d>";
    ItemClass[] _items;

public:

    ///
    this()
    {
        collectPublications!(PublishedObjectArray!ItemClass);
    }

    ~this()
    {
        clear;
    }

    /**
     * Instantiates and returns a new item.
     * Params:
     *      a = The variadic arguments passed to the item $(D __ctor).
     */
    ItemClass addItem(A...)(A a)
    in
    {
        assert(_items.length <= uint.max);
    }
    body
    {
        _items ~= construct!ItemClass(a);

        PropDescriptor!Object* descr = construct!(PropDescriptor!Object);
        descr.define(cast(Object*)&_items[$-1], format(_fmtName,_items.length-1), this);
        _items[$-1].declarator = this;
        _publishedDescriptors ~= descr;

        return _items[$-1];
    }

    /**
     * Removes and destroys an item from the internal container.
     * Params:
     *      t = Either the item to delete or its index.
     */
    final void deleteItem(T)(T t)
    if (isIntegral!T || is(Unqual!T == ItemClass))
    {
        ptrdiff_t index;
        static if(is(Unqual!T == ItemClass))
            index = _items.countUntil(t);
        else index = cast(ptrdiff_t)t;

        if (_items.count == 0 || index > _items.count-1 || index < 0)
            return;

        auto itm = _items[index];
        destruct(itm);
        _items = _items.remove(index);

        if (auto descr = publication!uint(format(_fmtName,index)))
        {
            // find index: a descendant may add descriptors in its this()
            auto descrIndex = countUntil(_publishedDescriptors, descr);
            assert(descrIndex != -1);
            _publishedDescriptors = _publishedDescriptors.remove(descrIndex);
            destruct(descr);
        }
    }

    /**
     * Sets or gets the item count.
     *
     * Items are automatically created or destroyed when changing this property.
     * Note that to change the length of $(D items()) is a noop, the only way to
     * add and remove items is to use $(D count()), $(D addItem()) or $(D deleteItem()).
     */
    @Get final uint count()
    {
        return cast(uint) _items.length;
    }

    /// ditto
    @Set final void count(uint aValue)
    {
        if (_items.length > aValue)
            while (_items.length != aValue) deleteItem(_items.length-1);
        else if (_items.length < aValue)
            while (_items.length != aValue) addItem;
    }

    /**
     * Provides an access to the items.
     */
    final ItemClass[] items()
    {
        return _items;
    }

    /**
     * Clears the internal container and destroys the items.
     */
    void clear()
    {
        foreach_reverse(immutable i; 0 .. _items.count)
            deleteItem(i);
    }

    /// Support for accessing an indexed item with $(D []).
    ItemClass opIndex(size_t i)
    in
    {
        assert(i < _items.length);
    }
    body
    {
        return _items[i];
    }

    /// Support for iterating the items with $(D foreach()).
    int opApply(int delegate(ItemClass) dg)
    {
        int result = 0;
        foreach(immutable i; 0 .. _items.length)
        {
            result = dg(_items[i]);
            if (result) break;
        }
        return result;
    }

    /// Support for iterating the items with $(D foreach_reverse()).
    int opApplyReverse(int delegate(ItemClass) dg)
    {
        int result = 0;
        foreach_reverse(immutable i; 0 .. _items.length)
        {
            result = dg(_items[i]);
            if (result) break;
        }
        return result;
    }

    /// Same as $(D items()).
    ItemClass[] opSlice()
    {
        return _items;
    }

    /// Same as $(D items()) but with bounds.
    ItemClass[] opSlice(size_t lo, size_t hi)
    in
    {
        assert(lo <= hi);
        assert(hi < _items.length);
    }
    body
    {
        return _items[lo .. hi];
    }
}
///
unittest
{
    class Item : PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        @SetGet uint _a, _b, _c;
        // a default ctor is needed.
        this(){collectPublications!Item;}
        this(uint a, uint b, uint c)
        {
            _a = a; _b = b; _c = c;
            collectPublications!Item;
        }
    }

    auto itemArray = construct!(PublishedObjectArray!Item);
    itemArray.addItem(1, 2, 3);
    itemArray.addItem(4, 5, 6);
    // serializes the object array to a file
    version(none) publisherToFile(itemArray, "backup.txt");
    destruct(itemArray);
}

unittest
{
    class Item : PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        @SetGet uint _a, _b, _c;
        this(){collectPublications!Item;}
        void setProps(uint a, uint b, uint c)
        {_a = a; _b = b; _c = c;}
    }

    alias ItemCollection = PublishedObjectArray!Item;

    auto col = construct!ItemCollection;
    auto str = construct!MemoryStream;
    auto ser = construct!Serializer;
    scope(exit) destruct(col, ser, str);

    Item itm = col.addItem();
    itm.setProps(0u,1u,2u);
    itm = col.addItem;
    itm.setProps(3u,4u,5u);
    itm = col.addItem;
    itm.setProps(6u,7u,8u);

    auto collaccess = col.items;
    collaccess.length = 0;
    assert(col.items.length == 3);

    ser.publisherToStream(col, str, SerializationFormat.iztxt);
    str.position = 0;
    col.clear;
    assert(col.items.count == 0);

    ser.streamToPublisher(str, col, SerializationFormat.iztxt);
    assert(col._publishedDescriptors.count == 4); // 3 + count descr
    col.deleteItem(0);
    assert(col._publishedDescriptors.count == 3); // 2 + count descr
    assert(col.items.count == 2);
    assert(col[0]._c == 5u);
    assert(col[1]._c == 8u);
    col.items[1]._c = 7u;

    auto todelete = col.items[0];
    col.deleteItem(todelete);
    assert(col.items.count == 1);
    col.count = 0;
    assert(col.items.count == 0);

    writeln("PublishedObjectArray(T) passed the tests");
}


/**
 * The PublishedAA class template allows to serialize an associative array.
 *
 * A Serializer is not able to directly handle $(I AA)s but this class
 * does the task automatically by splitting keys and values in two arrays.
 *
 * This class template can only be instantiated if the $(I AA) key and value
 * type is basic (see iz.types.BasicTypes).
 *
 * Params:
 *      AA = The type of the associative array.
 */
final class PublishedAA(AA): PropertyPublisher
if(isAssociativeArray!AA && isSerializable!(KeyType!AA) &&
    isSerializable!(ValueType!AA))
{

    mixin PropertyPublisherImpl;

protected:

    AA* _source;
    KeyType!AA[] _keys;
    ValueType!AA[] _content;

    uint _setCount = 0, _getCount = 0;

    void doSet()
    {
        if (_setCount++ % 2 == 0 && _setCount > 0)
            toAA(*_source);
    }

    void doGet()
    {
        if (_getCount++ %  2 == 0)
            fromAA(*_source);
    }

    @Set void keys(KeyType!AA[] value)
    {
        _keys = value;
        if (_source) doSet;
    }

    @Get KeyType!AA[] keys()
    {
        if (_source) doGet;
        return _keys;
    }

    @Set void values(ValueType!AA[] value)
    {
        _content = value;
        if (_source) doSet;
    }

    @Get ValueType!AA[] values()
    {
        if (_source) doGet;
        return _content;
    }

public:

    ///
    this()
    {
        collectPublications!(PublishedAA!AA);
    }

    /**
     * Constructs a new instance and sets a reference to the source $(I AA).
     * Using this constructor, $(D toAA()) and $(D fromAA()) don't need
     * to be called manually.
     *
     * Params:
     *      aa = A pointer to the associative array that will be stored and restored.
     */
    this(AA* aa)
    {
        _source = aa;
        collectPublications!(PublishedAA!AA);
    }

    /**
     * Copies the content of an associative array to the internal containers.
     *
     * Typically called before serializing and if the instance is created
     * using the default constructor.
     *
     * Params:
     *      aa = The associative array to get.
     */
    void fromAA(ref AA aa)
    {
        Appender!(KeyType!AA[]) keyApp;
        Appender!(ValueType!AA[]) valApp;

        keyApp.reserve(aa.length);
        valApp.reserve(aa.length);

        foreach(kv; aa.byKeyValue)
        {
            keyApp.put(kv.key);
            valApp.put(kv.value);
        }

        _keys = keyApp.data;
        _content = valApp.data;
    }

    /**
     * Resets then fills an associative array using the internal containers.
     *
     * Typically called after serializing and if the instance is created
     * using the default constructor.
     *
     * Params:
     *      aa = The associative array to set.
     */
    void toAA(ref AA aa)
    {
        aa = aa.init;
        foreach(immutable i; 0 .. _keys.length)
            aa[_keys[i]] = _content[i];
    }
}
///
unittest
{
    uint[char] aa = ['c' : 0u, 'x' : 12u];
    auto serializableAA = construct!(PublishedAA!(uint[char]));
    serializableAA.fromAA(aa);
    aa = aa.init;
    version(none) publisherToFile(serializableAA, "backup.txt");
    version(none) fileToPublisher("backup.txt", serializableAA);
    serializableAA.toAA(aa);
    assert(aa == ['c' : 0u, 'x' : 12u]);
}

unittest
{
    alias AAT = uint[float];
    alias AAC = PublishedAA!AAT;

    uint[float] a = [0.1f: 1u, 0.2f : 2u];
    AAC aac = construct!AAC;
    Serializer ser = construct!Serializer;
    MemoryStream str = construct!MemoryStream;

    aac.fromAA(a);
    ser.publisherToStream(aac, str);
    str.position = 0;
    a = a.init;
    ser.streamToPublisher(str, aac);
    aac.toAA(a);
    assert(a == [0.1f: 1u, 0.2f : 2u]);


    str.clear;
    AAC aac2 = construct!AAC(&a);

    ser.publisherToStream(aac2, str);
    str.position = 0;
    a = a.init;
    ser.streamToPublisher(str, aac2);
    assert(a == [0.1f: 1u, 0.2f : 2u]);

    writeln("PublishedAA(T) passed the tests");
}


/**
 * The Published2dArray class template allows to serialize 2-dimensional arrays.
 *
 * A Serializer is not able to directly handle them but this class
 * does the task automatically by merging the array and storing an additional
 * property for the dimensions.
 *
 * This class template can only be instantiated if $(I T) is a basic type.
 * (see iz.types.BasicTypes).
 *
 * Params:
 *      T = The array element type.
 */
final class Published2dArray(T): PropertyPublisher
if (isSerSimpleType!T)
{

    mixin PropertyPublisherImpl;

protected:

    uint[] _dimensions;
    T[] _content;
    T[][]* _source;

    uint _setCount = 0, _getCount = 0;

    void doSet()
    {
        if (_setCount++ % 2 == 0 && _setCount > 0)
            toArray(*_source);
    }

    void doGet()
    {
        if (_getCount++ %  2 == 0)
            fromArray(*_source);
    }

    @Get uint[] dimensions()
    {
        if (_source) doGet;
        return _dimensions;
    }

    @Set void dimensions(uint[] value)
    {
        _dimensions = value;
        if (_source) doSet;
    }

    @Get T[] content()
    {
        if (_source) doGet;
        return _content;
    }

    @Set void content(T[] value)
    {
        _content = value;
        if (_source) doSet;
    }

public:

    ///
    this()
    {
        collectPublications!(Published2dArray!T);
    }

    /**
     * Constructs a new instance and sets a reference to the source array.
     * Using this constructor, $(D toArray()) and $(D fromArray()) don't need
     * to be called manually.
     *
     * Params:
     *      array = A pointer to the array that will be stored and restored.
     */
    this(T[][]* array)
    {
        _source = array;
        collectPublications!(Published2dArray!T);
    }

    /**
     * Copies the content of the array to the internal container.
     *
     * Typically called before serializing and if the instance is created
     * using the default constructor.
     *
     * Params:
     *      array = The array to get.
     */
    void fromArray(ref T[][] array)
    out
    {
        import std.algorithm.iteration: reduce;
        assert(_dimensions.reduce!((a,b) => a + b) <= uint.max);
    }
    body
    {
        _dimensions = _dimensions.init;
        _content = _content.init;
        foreach(immutable i; 0 .. array.length)
        {
            _dimensions ~= cast(uint)array[i].length;
            _content ~= array[i];
        }
    }

    /**
     * Resets then fills the array using the internal data.
     *
     * Typically called after serializing and if the instance is created
     * using the default constructor.
     *
     * Params:
     *      array = The array to set.
     */
    void toArray(ref T[][] array)
    {
        array = array.init;
        array.length = _dimensions.length;
        uint start;
        foreach(i,len; _dimensions)
        {
            array[i].length = len;
            array[i] = _content[start .. start + len];
            start += len;
        }
    }
}
///
unittest
{
    alias Publisher = Published2dArray!uint;
    Publisher pub = construct!Publisher;

    auto array = [[0u,1u],[2u,3u,4u],[5u,6u,7u,8u]];
    pub.fromArray(array);
    version (none) publisherToFile(pub, "backup.txt");
    version (none) fileToPublisher("backup.txt", pub);
    pub.toArray(array);
    assert(array == [[0u,1u],[2u,3u,4u],[5u,6u,7u,8u]]);
}

unittest
{
    alias Publisher = Published2dArray!uint;
    uint[][]src = [[0u,1u],[2u,3u,4u],[5u,6u,7u,8u]];

    Serializer ser = construct!Serializer;
    MemoryStream str = construct!MemoryStream;
    scope(exit) destruct(ser, str);

    Publisher pub0 = construct!Publisher;
    uint[][] array = src.dup;
    pub0.fromArray(array);
    assert(pub0._content == [0u,1u,2u,3u,4u,5u,6u,7u,8u]);
    assert(pub0._dimensions == [2,3,4]);
    ser.publisherToStream(pub0, str);
    array = array.init;
    str.position = 0;
    ser.streamToPublisher(str, pub0);
    pub0.toArray(array);
    assert(array == src);

    str.clear;
    Publisher pub1 = construct!Publisher(&array);
    ser.publisherToStream(pub1, str);
    assert(pub1._content == [0u,1u,2u,3u,4u,5u,6u,7u,8u]);
    assert(pub1._dimensions == [2,3,4]);
    array = array.init;
    str.position = 0;
    ser.streamToPublisher(str, pub1);
    assert(array == src);

    destruct(pub0, pub1);

    writeln("Published2dArray(T) passed the tests");
}



/// Enumerates the possible notifications sent to a ComponentObserver
enum ComponentNotification
{
    /**
     * The Component parameter of the notifySubject() is now owned.
     * The owner that also matches the caller can be retrieved using
     * the .owner() property of the parameter.
     */
    added,
    /**
     * The Component parameter of the notifySubject() is about to be destroyed,
     * after what any of its reference that's been escaped will be danling.
     * The parameter may match the emitter itself or one of its owned Component.
     */
    free,
    /**
     * The Component parameter of the notifySubject() is about to be serialized.
     */
    serialize,
    /**
     * The Component parameter of the notifySubject() is about to be deserialized.
     */
    deserialize,
}

/**
 * Defines the interface a class that wants to observe a Component has to implement.
 * There is a single method: subjectNotification(ComponentNotification n, Component c)
 */
alias ComponentObserver = EnumBasedObserver!(ComponentNotification, Component);
// matching emitter
private alias ComponentSubject = CustomSubject!(ComponentNotification, Component);

/**
 * Component is a high-level class that proposes an automatic memory
 * managment model based on ownership. It also verifies the requirements to
 * make its instances referencable and serializable.
 *
 * Ownership:
 * A Component can be created with iz.memory.construct. As constructor parameter
 * another Component can be specified. It's in charge for freeing this "owned"
 * instance. Components that's not owned have to be freed manually. A reference
 * to an owned object can be escaped. To be notified of its destruction, it's
 * possible to observe the component or its owner by adding an observer to the
 * componentSubject.
 *
 * Referencable:
 * Each Component instance that's properly named is automatically registered
 * in the ReferenceMan, as a void reference. This allows some powerfull features
 * such as the Object property editor or the Serializer to inspect, store, retrieve
 * a Component between two sessions.
 *
 * Serializable:
 * A Component implements the PropertyPublisher interface. Each field annotated
 * with @SetGet and each setter/getter pair annotated with @Set and @Get
 * is automatically published and is usable by a PropertyBinder, by a Serializer
 * or by any other system based on the PropDescriptor system.
 */
class Component: PropertyPublisher
{

    mixin PropertyPublisherImpl;

private:

    Component _owner;
    DynamicList!Component _owned;
    ComponentSubject _compSubj;

    final void addOwned(Component o)
    {
        if (!o) return;
        _owned.add(o);
        foreach(obs; _compSubj.observers)
            obs.subjectNotification(ComponentNotification.added, this);
    }

protected:

    char[] _name;

public:

    ///
    this()
    {
        collectPublications!Component;
        _compSubj = construct!ComponentSubject;
        _owned = construct!(DynamicList!Component);
    }

    /**
     * Constructs a new instance whose life-time will be managed.
     * Params:
     *      owner = The Component that owns the new instance.
     */
    static C create(C = typeof(this))(Component owner)
    if (is(C : Component))
    {
        C c = construct!C;
        c._owner = owner;
        if (owner) owner.addOwned(c);
        return c;
    }

    /**
     * Destructs this and all the owned instances.
     */
    ~this()
    {
        ReferenceMan.removeReference(cast(Component*)this);
        foreach_reverse(o; _owned)
        {
            // observers can invalidate any escaped reference to a owned
            foreach(obs; _compSubj.observers)
                obs.subjectNotification(ComponentNotification.free, o);
            destruct(o);
        }
        // observers can invalidate any escaped reference to this instance
        foreach(obs; _compSubj.observers)
            obs.subjectNotification(ComponentNotification.free, this);
        //
        destruct(_compSubj);
        destruct(_owned);
    }

    /// Returns this instance onwer.
    final const(Component) owner() {return _owner;}

    /// Returns the subject allowing ComponentObservers to observe this instance.
    final ComponentSubject componentSubject() {return _compSubj;}

    // name things ------------------------------------------------------------+

    /// Returns true if a string is available as an unique Component name.
    final bool nameAvailable(in char[] value)
    {
        if (_owner !is null && _owner._owned.first)
        {
            foreach(o; _owner._owned)
                if (o.name == value) return false;
        }
        return true;
    }

    /// Suggests an unique Component name according to base.
    final char[] getUniqueName(in char[] base)
    {
        import std.conv: to;
        size_t i;
        char[] result = base.dup;
        while (!nameAvailable(result))
        {
            result = base ~ '_' ~ to!(char[])(i++);
            if (i == size_t.max)
                return result.init;
        }
        return result;
    }

    /**
     * Defines the name of this Component.
     *
     * The name must be an unique value in the owner Component tree.
     * This value is a published property.
     * This value is stored as an ID in the ReferenceMan with the void type.
     */
    final @Set name(const(char)[] value)
    {
        if (_name == value) return;
        ReferenceMan.removeReference(cast(Component*)this);
        if (nameAvailable(value)) _name = value.dup;
        else _name = getUniqueName(value);
        ReferenceMan.storeReference(cast(Component*)this, qualifiedName);
    }
    /// ditto
    final @Get char[] name() {return _name;}

    /**
     * Returns the fully qualified name of this component in the owner
     * Component tree.
     */
    final char[] qualifiedName()
    {
        char[][] result;
        result ~= _name;
        Component c = _owner;
        while (c)
        {
            result ~= c.name;
            c = c._owner;
        }
        return result.retro.join(".");
    }
    // ----
}

unittest
{

    auto root = Component.create(null);
    root.name = "root";
    assert(root.owner is null);
    assert(root.name == "root");
    assert(root.qualifiedName == "root");

    auto owned1 = Component.create!Component(root);
    owned1.name = "component1".dup;
    assert(owned1.owner is root);
    assert(owned1.name == "component1");
    assert(owned1.qualifiedName == "root.component1");

    auto owned11 = Component.create!Component(owned1);
    owned11.name = "component1";
    assert(owned11.owner is owned1);
    assert(owned11.name == "component1");
    assert(owned11.qualifiedName == "root.component1.component1");

    auto owned12 = Component.create!Component(owned1);
    owned12.name = "component1";
    assert(owned12.name == "component1_0");
    assert(owned12.qualifiedName == "root.component1.component1_0");

    root.destruct;
    // owned1, owned11 & owned12 are dangling but that's expected.
    // Component instances are designed to be created and declared inside
    // other Components. Escaped refs can be set to null using the Observer system.
}

unittest
{
    auto c = Component.create!Component(null);
    c.name = "a";
    assert(ReferenceMan.referenceID(cast(Component*)c) == "a");
}

