module iz.properties;

import
    std.traits;
import
    iz.memory, iz.types, iz.containers;

version(unittest) import std.stdio;

/**
 * Describes the accessibility of a property.
 */
enum PropAccess
{
    /// denotes an error.
    none,
    /// read-only.
    ro,
    /// write-only.
    wo,
    /// read & write.
    rw
}   

/**
 * Describes a property declared in an aggregate.
 *
 * A property is described by a name, a setter and a getter. Severals constructors
 * allow to define the descriptor using a setter, a getter but also a pointer to
 * the targeted field.
 *
 * Addional information includes an iz.types.RunTimeTpeInfo structure matching to
 * the instance specialization.
 */
struct PropDescriptor(T)
{
    public
    {
        /// setter proptotype
        alias PropSetter = void delegate(T value);
        /// getter prototype
        alias PropGetter = T delegate();
        /// alternative setter prototype.
        alias PropSetterConst = void delegate(const T value);
    }
    private
    {
        PropSetter _setter;
        PropGetter _getter;
        Object _declarator;
        RuntimeTypeInfo _rtti;

        string _referenceID;

        T* _setPtr;
        T* _getPtr;

        PropAccess _access;

        string _name;

        void cleanup()
        {
            _setPtr = null;
            _getPtr = null; 
            _setter = null;
            _getter = null;
            _declarator = null;
            _access = PropAccess.none;
            _name = _name.init;
        }

        void updateAccess()
        {
            if ((_setter is null) && (_getter !is null))
                _access = PropAccess.ro;
            else if ((_setter !is null) && (_getter is null))
                _access = PropAccess.wo;
            else if ((_setter !is null) && (_getter !is null))
                _access = PropAccess.rw;
            else _access = PropAccess.none;
        }

        // pseudo setter internally used when a T is directly written.
        void internalSetter(T value)
        {
            alias TT = Unqual!T;
            const T current = getter()();
            if (value != current) *(cast(TT*)_setPtr) = value;
        }

        // pseudo getter internally used when a T is directly read
        T internalGetter()
        {
            return *_getPtr;
        }
    }
    public
    {

// constructors ---------------------------------------------------------------+
        /**
         * Constructs a property descriptor from a PropSetter and a PropGetter.
         */  
        this(PropSetter aSetter, PropGetter aGetter, string aName = "")
        in
        {
            assert(aSetter);
            assert(aGetter);
        }
        body
        {
            define(aSetter, aGetter, aName);
        }

        /**
         * Constructs a property descriptor from a PropSetterConst and a PropGetter.
         */  
        this(PropSetterConst aSetter, PropGetter aGetter, string aName = "")
        in
        {
            assert(aSetter);
            assert(aGetter);
        }
        body
        {
            define(cast(PropSetter)aSetter, aGetter,aName);
        }

        /**
         * Constructs a property descriptor from a PropSetter and as getter
         * a pointer to a variable.
         */
        this(PropSetter aSetter, T* aSourceData, string aName = "")
        in
        {
            assert(aSetter);
            assert(aSourceData);
        }
        body
        {
            define(aSetter, aSourceData, aName);
        }

        /**
         * Constructs a property descriptor from a pointer to a variable used as
         * a setter and getter.
         */
        this(T* aData, string aName = "")
        in
        {
            assert(aData); 
        }
        body
        {
            define(aData, aName);
        }
// ---- 
// define all the members -----------------------------------------------------+

        /**
         * Defines a property descriptor from a PropSetter and a PropGetter.
         */
        void define(PropSetter aSetter, PropGetter aGetter, string aName = "")
        {
            cleanup;
            _rtti = runtimeTypeInfo!T;
            setter(aSetter);
            getter(aGetter);
            if (aName != "") {name(aName);}
            _declarator = cast(Object) aSetter.ptr;
        }

        /**
         * Defines a property descriptor from a PropSetter and as getter
         * a pointer to a variable.
         */
        void define(PropSetter aSetter, T* aSourceData, string aName = "")
        {
            cleanup;
            _rtti = runtimeTypeInfo!T; 
            setter(aSetter);
            setDirectSource(aSourceData);
            if (aName != "") {name(aName);}
            _declarator = cast(Object) aSetter.ptr;
        }
        /**
         * Defines a property descriptor from a pointer to a variable used as
         * a setter and getter.
         */
        void define(T* aData, string aName = "", Object aDeclarator = null)
        {
            cleanup;
            _rtti = runtimeTypeInfo!T;
            setDirectSource(aData);
            setDirectTarget(aData);
            if (aName != "") {name(aName);}
            _declarator = aDeclarator;
        }
// ----
// setter ---------------------------------------------------------------------+

        /**
         * Sets the property setter using a standard method.
         */
        @property void setter(PropSetter value)
        {
            _setter = value;
            _declarator = cast(Object) value.ptr;
            updateAccess;
        }
        /// ditto
        @property PropSetter setter(){return _setter;}
        /**
         * Sets the property setter using a pointer to a variable
         */
        void setDirectTarget(T* location)
        {
            _setPtr = location;
            _setter = &internalSetter;
            updateAccess;
        }
        /**
         * Sets the property value
         */
        void set(T value) {_setter(value);}

// ---- 
// getter ---------------------------------------------------------------------+

        /** 
         * Sets the property getter using a standard method.
         */
        @property void getter(PropGetter value)
        {
            _getter = value;
            _declarator = cast(Object) value.ptr;
            updateAccess;
        }
        /// ditto
        @property PropGetter getter(){return _getter;}
        /** 
         * Sets the property getter using a pointer to a variable
         */
        void setDirectSource(T* value)
        {
            _getPtr = value;
            _getter = &internalGetter;
            updateAccess;
        }
        /**
         * Gets the property value
         */
        T get(){return _getter();}

// ----     
// misc -----------------------------------------------------------------------+

        /** 
         * Information about the property accessibility
         */
        @property const(PropAccess) access()
        {
            return _access;
        }
        /** 
         * Defines the string used to identify the property
         */
        @property void name(string value)
        {
            _name = value;
        }
        /// ditto
        @property string name()
        {
            return _name;
        }
        /**
         * The object that declares this property.
         * When really needed, this value is set automatically.
         */
        @property void declarator(Object value)
        {
            _declarator = value;
        }
        /// ditto
        @property Object declarator(){return _declarator;}
        /**
         * Returns the RuntimeTypeInfo struct for the property type.
         */
        @property const(RuntimeTypeInfo) rtti(){return _rtti;}
        /**
         * Defines the reference that matches the property value.
         * This is only used as a helper when the property value is
         * a fat pointer (e.g a delegate) and to serialiaze.
         */
        @property string referenceID(){return _referenceID;}
        /// ditto
        @property referenceID(string value){_referenceID = value;}
// ----        

    }
}


unittest
{
    class A
    {
        private int fi;
        @property int i(){return fi;}
        @property void i(in int aValue){fi = aValue;}
    }
    struct Si{uint f,r,e;}
    class B
    {
        private Si fi;
        @property Si i(){return fi;}
        @property void i(const Si aValue){fi = aValue;}
    }

    auto a = construct!A;
    auto descrAi = PropDescriptor!int(&a.i,&a.i,"I");
    descrAi.setter()(5);
    assert(a.i == 5);
    assert(a.i == descrAi.getter()());
    assert(descrAi.declarator is a);

    auto refval = Si(1,2,333);
    auto b = construct!B;
    auto descrBi = PropDescriptor!Si(&b.i,&b.i,"I");
    descrBi.setter()(refval);
    assert(b.i.e == 333);
    assert(b.i.e == descrBi.getter()().e);

    destruct(a,b);
    writeln("PropDescriptor(T) passed the tests");
}

unittest
{
    // the key that allows "safe" cast using iz.types.RunTimeTypeInfo
    static assert((PropDescriptor!(int)).sizeof == (PropDescriptor!(ubyte[])).sizeof);
    static assert((PropDescriptor!(string)).sizeof == (PropDescriptor!(ubyte[][][][])).sizeof);
}

/// designed to annotate a detectable property setter.
enum Set;
/// designed to annotate a detectable property getter. 
enum Get;
/// designed to annotate a detectable "direct" field.
enum SetGet;
/// ditto
alias GetSet = SetGet;
/// designed to make undetectable a property collected in a ancestor.
enum HideSet;
/// ditto
enum HideGet;

/**
 * When mixed in an agregate this generates a property. 
 * This property is detectable by a PropertyPublisher.
 *
 * Params:
 *      T = The type of the property.
 *      propName = The name of the property.
 *      propField = The identifier that matches the target field.
 *
 * Returns:
 *      A sring to mixin.
 */
string genPropFromField(T, string propName, string propField)()
{
    return
    "@Set void " ~ propName ~ "(" ~ T.stringof ~ " aValue)" ~
    "{ " ~ propField ~ " = aValue;} " ~
    "@Get " ~ T.stringof ~ " " ~ propName ~
    "(){ return " ~ propField ~ ";}" ;
}

private string genStandardPropDescriptors()
{
    string result;
    foreach(T; BasicTypes)
    {
        result ~= ("public alias " ~ T.stringof ~ "Prop = PropDescriptor!(" ~
            T.stringof ~ ")" ~ "; ");
    }
    return result;
}

/// Property descriptors for the types defined in the iz.types.BasicTypes aliases.
mixin(genStandardPropDescriptors);


/**
 * The PropertyPublisher interface allows a class to publish a collection
 * of properties described using the PropDescriptor format.
 *
 * The methods don't have to be implemented by hand as it's automatically done 
 * when the PropertyPusblisherImpl template is mixed in a class.
 */
interface PropertyPublisher
{
    /**
     * Returns the count of descriptor this class publishes.
     */
    size_t publicationCount();
    /**
     * Returns a pointer to a descriptor according to its name.
     * Similar to the publication() function template excepted that the
     * result type has not to be specified.
     */
    void* publicationFromName(string name);
    /**
     * Returns a pointer the index-th descriptor.
     * Index must be within the [0 .. publicationCount] range.
     */
    void* publicationFromIndex(size_t index);
    /**
     * Returns the RTTI for the descriptor at index.
     * Index must be within the [0 .. publicationCount] range.
     * This allows to cast the results of publicationFromName() or publicationFromIndex().
     */
    const(RuntimeTypeInfo) publicationType(size_t index);
    /**
     * Pointer to the object that has created the descriptor leading to this
     * PropertyPublisher instance.
     */
    Object declarator(); //acquirer
    void declarator(Object value);
}

/**
 * Returns true if the argument is a property publisher.
 */
bool isPropertyPublisher(T)()
{
    bool result = true;
    static if (is(T : PropertyPublisher))
        return result;
    else
    {
        foreach(interfaceFun;__traits(allMembers, PropertyPublisher))
        static if (!__traits(hasMember, T, interfaceFun))
        {
            result = false;
            break;
        }
        return result;
    }
}

///ditto
bool isPropertyPublisher(Object o)
{
    return (cast(PropertyPublisher) o) !is null;
}

unittest
{
    struct Foo{mixin PropertyPublisherImpl;}
    class Bar{mixin PropertyPublisherImpl;}
    class Baz: PropertyPublisher {mixin PropertyPublisherImpl;}
    static assert(isPropertyPublisher!Foo);
    static assert(isPropertyPublisher!Bar);
    static assert(isPropertyPublisher!Baz);
    auto baz = new Baz;
    assert( baz.isPropertyPublisher);
}

/**
 * Default implementation of a PropertyPublisher.
 *
 * When mixed in an aggregate type, two analyzers can be used to create
 * automatically the PropDescriptors that match the setter and getter pairs
 * anotated with @Set and @Get or that match the fields annotated with @SetGet.
 *
 * The analyzers are usually called in this(). The template has to be mixed in
 * each class generation that introduces new annotated properties.
 *
 * The analyzers, propCollectorGetPairs() and propCollectorGetFields(), are
 * function templates that must be instantiated with the type they have
 * to scan (typeof(this)). The two analyzers can be called with a
 * third function template: collectPublications().
 */
mixin template PropertyPublisherImpl()
{
    /**
     * Contains the list of PropDesrcriptors created by the analyzers.
     * The access to this should be accessed directly but using the functions
     * publication(), publicationFromName() and publicationFromIndex().
     */
    static if (!__traits(hasMember, typeof(this), "_publishedDescriptors"))
    protected void*[] _publishedDescriptors;

    static if (!__traits(hasMember, typeof(this), "_declarator"))
    protected Object _declarator;

// virtual methods or PropDescriptorCollection methods
//
// static if: the template injects some virtual methods that don't need
// to be overriden
// oror Base: because it looks like the interface makes the members
// detectable even if not yet implemented.

    import std.traits: BaseClassesTuple;
    alias ToT = typeof(this);
    // descendant already implements the interface
    enum BaseHas = is(BaseClassesTuple!ToT[0] : PropertyPublisher);
    enum HasItf = is(ToT : PropertyPublisher);
    // interface must be implemented from this generation, even if methods detected
    enum Base = HasItf & (!BaseHas);

    /// see PropertyPublisher
    static if (!__traits(hasMember, ToT, "declarator") || Base)
    public Object declarator() {return _declarator;}

    /// ditto
    static if (!__traits(hasMember, ToT, "declarator") || Base)
    public void declarator(Object value) {_declarator = value;}

    /// see PropertyPublisher
    static if (!__traits(hasMember, ToT, "publicationCount") || Base)
    public size_t publicationCount() {return _publishedDescriptors.length;}

    /// see PropertyPublisher
    static if (!__traits(hasMember, ToT, "publicationFromName") || Base)
    protected void* publicationFromName(string name)
    {return publication!size_t(name);}

    /// see PropertyPublisher
    static if (!__traits(hasMember, ToT, "publicationFromIndex") || Base)
    protected void* publicationFromIndex(size_t index)
    {return _publishedDescriptors[index];}

    /// see PropertyPublisher
    static if (!__traits(hasMember, ToT, "publicationType") || Base)
    protected const(RuntimeTypeInfo) publicationType(size_t index)
    {return (cast(PropDescriptor!int*) _publishedDescriptors[index]).rtti;}

// templates: no problem with overrides, instantiated according to class This or That

    /**
     * Returns a pointer to a descriptor according to its name.
     * Params:
     *      T = The type of the property.
     *      name = The identifier used for the setter and the getter.
     *      createIfMissing = When set to true, the result is never null.
     * Returns:
     *      Null if the operation fails otherwise a pointer to a PropDescriptor!T.
     */
    protected PropDescriptor!T * publication(T)(string name, bool createIfMissing = false)
    {
        PropDescriptor!T * descr;

        foreach(immutable i; 0 .. _publishedDescriptors.length)
        {
            auto maybe = cast(PropDescriptor!T *) _publishedDescriptors[i];
            if (maybe.name != name) continue;
            descr = maybe; break;
        }

        if (createIfMissing && !descr)
        {
            descr = new PropDescriptor!T;
            descr.name = name;
            _publishedDescriptors ~= descr;
        }
        return descr;
    }

    /**
     * Performs all the possible analysis.
     */
    protected void collectPublications(T)()
    {
        collectPublicationsFromPairs!T;
        collectPublicationsFromFields!T;
    }

    /**
     * Creates the properties descriptors for each field annotated with @SetGet.
     *
     * If the field identifier starts with '_', 'f' or 'F' then the descriptor
     * .name member excludes this prefix, otherwise the descriptor .name is
     * identical.
     */
    protected void collectPublicationsFromFields(T)()
    {
        import iz.types: ScopedReachability;
        import std.traits: isCallable, isDelegate, isFunctionPointer;

        bool isFieldPrefix(char c)
        {return c == '_' || c == 'f' || c == 'F';}
        enum getStuff = q{__traits(getMember, T, member)};

        mixin ScopedReachability;
        foreach(member; __traits(allMembers, T))
        static if (isMemberReachable!(T, member))
        static if (!isCallable!(mixin(getStuff)) || isDelegate!(mixin(getStuff))
            || isFunctionPointer!(mixin(getStuff)))
        {
            foreach(attribute; __traits(getAttributes, __traits(getMember, this, member)))
            static if (is(attribute == SetGet)) 
            {
                alias Type = typeof(__traits(getMember, this, member));
                auto propPtr = &__traits(getMember, this, member);
                static if (isFieldPrefix(member[0]))
                auto propName = member[1..$];
                else auto propName = member;
                auto descriptor = publication!Type(propName, true);
                descriptor.define(propPtr, propName);
                //
                static if (is(T : Object)) descriptor.declarator = cast(Object)this;
                static if (is(Type : Object))
                {
                    auto o = *cast(Object*) propPtr;
                    PropertyPublisher pub = cast(PropertyPublisher) o;
                    // RAII: if it's initialized then it's mine
                    if (pub) pub.declarator = this;
                }
                //
                version(none) writeln(attribute.stringof, " : ", member);
                break;
            }
        }
    }
    
    /**
     * Creates the property descriptors for the setter/getter pairs 
     * annotated with @Set/@Get.
     *
     * In a class hierarchy, an overriden accessor replaces the ancestor's one.
     * If a setter is annoted with @HideSet or a getter with @HideGet then
     * the descriptor created when the ancestor was scanned is removed from the
     * publications.
     */
    protected void collectPublicationsFromPairs(T)()
    {
        import iz.types: ScopedReachability, runtimeTypeInfo;
        import std.traits: isCallable, Parameters, ReturnType;
        import std.meta: AliasSeq, staticIndexOf;
        import std.algorithm.mutation: remove;
        import std.algorithm.searching: countUntil;

        mixin ScopedReachability;
        foreach(member; __traits(allMembers, T))
        static if (isMemberReachable!(T, member))
        foreach(overload; __traits(getOverloads, T, member))
        {
            alias Attributes = AliasSeq!(__traits(getAttributes, overload));
            enum getterAttrib = staticIndexOf!(Get, Attributes) != -1;
            enum setterAttrib = staticIndexOf!(Set, Attributes) != -1;
            enum ungetAttrib = staticIndexOf!(HideGet, Attributes) != -1;
            enum unsetAttrib = staticIndexOf!(HideSet, Attributes) != -1;
            // define the getter
            static if (getterAttrib && !ungetAttrib && isCallable!overload)
            {
                alias Type = ReturnType!overload;
                alias DescriptorType = PropDescriptor!Type;
                auto descriptor = publication!(Type)(member, true);
                auto dg = &overload;
                version(assert) if (descriptor.setter) assert (
                    // note: rtti unqalifies the type
                    runtimeTypeInfo!Type == descriptor.rtti,
                    "setter and getter types mismatch");
                descriptor.define(descriptor.setter, dg, member);
                //
                static if (is(T : Object)) descriptor.declarator = cast(Object)this;
                static if (is(Type : Object))
                {
                    auto o = cast(Object) dg();
                    PropertyPublisher pub = cast(PropertyPublisher) o;
                    // RAII: if it's initialized then it's mine
                    if (pub) pub.declarator = this;
                }
                //   
                version(none) writeln(attribute.stringof, " < ", member);
            }
            // define the setter
            else static if (setterAttrib && !unsetAttrib && isCallable!overload)
            {
                alias Type = Parameters!overload;
                version(assert) static assert(Type.length == 1,
                    "setter must only have one parameter");
                alias DescriptorType = PropDescriptor!Type;
                auto descriptor = publication!(Parameters!overload)(member, true);
                auto dg = &overload;
                version(assert) if (descriptor.getter) assert (
                    runtimeTypeInfo!Type == descriptor.rtti,
                    "setter and getter type mismatch");
                descriptor.define(dg, descriptor.getter, member);
                //
                version(none) writeln(attribute.stringof, " > ", member);
            }
            // hide from this descendant
            else static if ((ungetAttrib | unsetAttrib) && isCallable!overload)
            {
                auto descr = publication!size_t(member, false);
                if (descr)
                {
                    auto index = countUntil(_publishedDescriptors, descr);
                    assert(index != -1);
                    _publishedDescriptors = remove(_publishedDescriptors, index);
                }
            }
        }
    }
}

unittest
{
    // test basic PropertyPublisher features: get descriptors, use them.
    class Foo: PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        this(A...)(A a)
        {
            collectPublicationsFromFields!Foo;
            collectPublicationsFromPairs!Foo;
        }

        @SetGet private uint _anUint;
        @SetGet private static char[] _manyChars;
        private uint _a, _b;
        private char[] _c;

        @Get uint propA(){return _a;}
        @Set void propA(uint aValue){_a = aValue;}

        @Get uint propB(){return _b;}
        @Set void propB(uint aValue){_b = aValue;}

        @Get char[] propC(){return _c;}
        @Set void propC(char[] aValue){_c = aValue;}

        void use()
        {
            assert(propA == 0);
            auto aDescriptor = publication!uint("propA");
            aDescriptor.setter()(1234_5678);
            assert(propA == 1234_5678);

            assert(propB == 0);
            auto bDescriptor = publication!uint("propB");
            bDescriptor.setter()(8765_4321);
            assert(propB == 8765_4321);

            assert(!propC.length);
            auto cDescriptor = publication!(char[])("propC");
            cDescriptor.setter()("Too Strange To Be Good".dup);
            assert(propC == "Too Strange To Be Good");
            propC = "Too Good To Be Strange".dup;
            assert( publication!(char[])("propC").getter()() == "Too Good To Be Strange");

            assert(_anUint == 0);
            auto anUintDescriptor = publication!uint("anUint");
            anUintDescriptor.setter()(1234_5678);
            assert(_anUint == 1234_5678);

            assert(_manyChars == null);
            auto manyCharsDescriptor = publication!(char[])("manyChars");
            manyCharsDescriptor.setter()("BimBamBom".dup);
            assert(_manyChars == "BimBamBom");
            _manyChars = "BomBamBim".dup;
            assert(manyCharsDescriptor.getter()() == "BomBamBim");
        }
    }
    Foo foo = construct!Foo;
    foo.use;
    foo.destruct;

    writeln("PropertyPublisher passed the tests (basic)");
}

unittest
{
    class Bar
    {
        size_t _field;
        string info;
        mixin PropertyPublisherImpl;
        this()
        {
            collectPublicationsFromPairs!Bar;
        }
        @Set void field(size_t aValue)
        {
            info ~= "Bar";
        }
        @Get size_t field()
        {
            info = "less derived";
            return _field;
        }
    }
    class Baz : Bar
    {
        @Set override void field(size_t aValue)
        {
            super.field(aValue);
            info ~= "Baz";
        }
        @Get override size_t field()
        {
            info = "most derived";
            return _field;
        }
    }

    // test that the most derived override is used as setter or getter
    Baz baz = construct!Baz;
    assert(baz.publicationCount == 1);
    auto prop = baz.publication!size_t("field");
    prop.set(0);
    assert(baz.info == "BarBaz");
    assert(baz.publicationCount == 1);
    auto a = prop.get;
    assert(baz.info == "most derived");
    baz.destruct;
}

unittest
{
    alias Delegate = void delegate(uint a);
    class Cat
    {
        mixin PropertyPublisherImpl;
        @SetGet Delegate _meaow;
        this(){collectPublications!Cat;}
    }

    class Fly
    {
        mixin PropertyPublisherImpl;
        @GetSet string _bzzz(){return "bzzz";}
        this(){collectPublications!Fly;}
    }

    // test that a delegate is detected as a field
    Cat cat = new Cat;
    assert(cat.publicationCount == 1);
    auto descr = cast(PropDescriptor!uint*) cat.publicationFromIndex(0);
    assert(descr);
    assert(descr.rtti.type == RuntimeType._delegate);
    // test that a plain function is not detected as field
    Fly fly = new Fly;
    assert(fly.publicationCount == 0);
}

unittest
{
    class Bee
    {
        mixin PropertyPublisherImpl;
        this(){collectPublicationsFromPairs!Bee;}
        @Set void delegate(uint) setter;
        @Get int delegate() getter;
    }
    // test that delegates as fields are not detected as set/get pairs
    Bee bee = new Bee;
    assert(bee.publicationCount == 0);
}

unittest
{
    class B0
    {
        mixin PropertyPublisherImpl;
        this(){collectPublications!B0;}
        @SetGet int _a;
    }
    class B1: B0
    {
        mixin PropertyPublisherImpl;
        this(){collectPublications!B1;}
        @Set void b(int value){}
        @Get int b(){return 0;}
        @SetGet int _c;
    }
    // test that all props are detected in the inheritence list
    auto b1 = new B1;
    assert(b1.publicationCount == 3);
}

unittest
{
    class B0
    {
        mixin PropertyPublisherImpl;
        this(){collectPublications!B0;}
        @Set void b(int value){}
        @Get int b(){return 0;}
    }
    class B1: B0
    {
        mixin PropertyPublisherImpl;
        this(){collectPublications!B1;}
        @HideGet override int b(){return super.b();}
    }
    // test that a prop marked with @HideSet/Get is not published anymore
    auto b0 = new B0;
    assert(b0.publicationCount == 1);
    auto b1 = new B1;
    assert(b1.publicationCount == 0);
}

unittest
{
    struct Bug
    {
        mixin PropertyPublisherImpl;
        this(uint value){collectPublications!Bug;}
        @SetGet uint _a;
    }
    // test that the 'static if things' related to 'interface inheritence'
    // dont interfere when mixed in struct
    Bug bug = Bug(0);
    assert(bug.publicationCount == 1);
}

unittest
{
    // test safety, multiple setter types
    enum decl = q{
        class Bug
        {
            mixin PropertyPublisherImpl;
            this(){collectPublications!Bug;}
            @Set void b(int value, uint ouch){}
            @Get int b(){return 0;}
        }
    };
    static assert( !__traits(compiles, mixin(decl)));
}

unittest
{
    // test safety, setter & getter types mismatch
    version(assert)
    {
        bool test;
        class Bug
        {
            mixin PropertyPublisherImpl;
            this(){collectPublications!Bug;}
            @Set void b(string value){}
            @Get int b(){return 0;}
        }
        try auto b = new Bug;
        catch(Error e) test = true;
        assert(test);
    }
}

unittest
{
    // test initial collector/declarator/ownership
    class B: PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        this(){collectPublications!B;}
    }
    class A: PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        B _owned2;
        this()
        {
            _owned1 = new B;
            _owned2 = new B;
            collectPublications!A;
        }
        @SetGet uint _a;
        // ownership is set in getFields
        @SetGet B _owned1;
        // ownership is set in getPairs
        @Get B owned2(){return _owned2;}
        @Set void owned2(B value){}
        // ownership is not set because value initially is null
        @SetGet B _notowned;
    }
    auto a1 = new A;
    auto a2 = new A;
    a1._notowned = a2._owned1;
    //
    assert(a1._owned1.declarator is a1);
    assert(a1._owned2.declarator is a1);
    assert(a1._notowned.declarator is a2);
}

/**
 * Helper union that avoid to cast a generic PropDescriptor.
 *
 * iz.properties often declares a "generic" PropDescriptor as a PropDescriptor!int
 * but such a descriptor as to be casted later according to its rtti value.
 */
union PropDescriptorUnion
{
    PropDescriptor!bool*    boolProp;
    PropDescriptor!byte*    byteProp;
    PropDescriptor!ubyte*   ubyteProp;
    PropDescriptor!short*   shortProp;
    PropDescriptor!ushort*  ushortProp;
    PropDescriptor!int*     intProp;
    PropDescriptor!uint*    uintProp;
    PropDescriptor!long*    longProp;
    PropDescriptor!ulong*   ulongProp;
    PropDescriptor!float*   floatProp;
    PropDescriptor!double*  doubleProp;
    PropDescriptor!double*  realProp;
    PropDescriptor!char*    charProp;
    PropDescriptor!wchar*   wcharProp;
    PropDescriptor!dchar*   dcharProp;
    PropDescriptor!Object*  objectProp;
    PropDescriptor!GenericDelegate* delegateProp;
    PropDescriptor!GenericFunction* functionProp;
    //
    PropDescriptor!bool[]*    aboolProp;
    PropDescriptor!byte[]*    abyteProp;
    PropDescriptor!ubyte[]*   aubyteProp;
    PropDescriptor!short[]*   ashortProp;
    PropDescriptor!ushort[]*  aushortProp;
    PropDescriptor!int[]*     aintProp;
    PropDescriptor!uint[]*    auintProp;
    PropDescriptor!long[]*    alongProp;
    PropDescriptor!ulong[]*   aulongProp;
    PropDescriptor!float[]*   afloatProp;
    PropDescriptor!double[]*  adoubleProp;
    PropDescriptor!double[]*  arealProp;
    PropDescriptor!char[]*    acharProp;
    PropDescriptor!wchar[]*   awcharProp;
    PropDescriptor!dchar[]*   adcharProp;
}
/// ditto
struct AnyPropDescriptor
{
    auto type() {return any.byteProp.rtti.type;}
    PropDescriptorUnion any;
    alias any this;
}

unittest
{
    byte a;
    ubyte b;
    PropDescriptor!byte pda = PropDescriptor!byte(&a, "a");
    PropDescriptor!ubyte pdb = PropDescriptor!ubyte(&b, "b");

    PropDescriptorUnion u = {ubyteProp : &pdb};
    assert(u.byteProp.rtti.type == RuntimeType._ubyte);

    AnyPropDescriptor apd = AnyPropDescriptor(u);
}

/**
 * Returns true if an Object owns a published sub PropertyPublisher.
 *
 * The serializer and the binders use this to determine if a sub object has
 * to be fully copied / serialized or rather the reference (without members).
 *
 * Params:
 *      t = Either a class or a struct mixed with PropertyPublisherImpl or
 *          a PropertyPublisher.
 *      descriptor = A pointer to the sub object accessor.
 */
bool isObjectOwned(T)(T t, PropDescriptor!Object* descriptor)
if (isPropertyPublisher!T)
{
    auto o = cast(PropertyPublisher) descriptor.get();
    if (o)
        return o.declarator !is t.declarator;
    else
        return false;
}

unittest
{
    class Foo(bool Nested) : PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        this()
        {
            static if (Nested) _full = new Foo!false;
            collectPublications!Foo;
        }

        @SetGet Foo!false _asref;
        static if (Nested)
        @SetGet Foo!false _full;
    }
    auto foo = new Foo!true;
    assert(isObjectOwned(foo, foo.publication!Object("full")));
    assert(!isObjectOwned(foo, foo.publication!Object("asref")));
}

/**
 * Binds two property publishers.
 *
 * After the call, each property published in target that has a matching property
 * in source has the same value as the source.
 *
 * Params:
 *      recursive = Indicates if the process is recursive.
 *      source = The aggregate from where the properties values are copied. Either
 *          a class or a struct that's mixed with PropertyPublisherImpl
 *          or a PropertyPublisher.
 *      target = The aggregate where the propertues values are copied.
 *          As for the Target type, same requirment as the source.
 */
void bindPublications(bool recursive = false, Source, Target)(Source source, Target target)
if (isPropertyPublisher!Source && isPropertyPublisher!Target)
{
    PropDescriptor!int* sourceProp, targetProp;
    foreach(immutable i; 0 .. source.publicationCount)
    {
        sourceProp = cast(PropDescriptor!int*) source.publicationFromIndex(i);
        targetProp = cast(PropDescriptor!int*) target.publicationFromName(sourceProp.name);

        if (!targetProp) continue;
        if (sourceProp.rtti != targetProp.rtti) continue;

        if (sourceProp.rtti.type != RuntimeType._object)
        {
            // note: ABI magic, this works whatever is the property type
            // but it would be safer to cast properly the PropDescriptor according to its rtti
            if (!sourceProp.rtti.array)
                targetProp.set(sourceProp.get);
            else
                (cast(PropDescriptor!(int[])*)targetProp)
                    .set((cast(PropDescriptor!(int[])*)sourceProp).get);
        }
        else
        {
            // reference
            if (sourceProp.declarator !is source.declarator
                && targetProp.declarator !is target.declarator)
                    targetProp.set(sourceProp.get);
            // sub object
            else static if (recursive)
            {
                bindPublications!true(
                    (cast(PropDescriptor!Object*) sourceProp).get(),
                    (cast(PropDescriptor!Object*) targetProp).get()
                );
                continue;
            }
        }
    }
}

/// ditto
void bindPublications(bool recursive = false)(Object from, Object to)
{
    auto source = cast(PropertyPublisher) from;
    auto target = cast(PropertyPublisher) to;
    if (source && target) bindPublications!true(source, target);
}

unittest
{
    class Foo(bool Nested) : PropertyPublisher
    {
        mixin PropertyPublisherImpl;
        this()
        {
            static if (Nested)
                _sub = new Foo!false;
            collectPublications!Foo;
        }
        @SetGet uint _a;
        @SetGet ulong _b;
        @SetGet string _c;

        static if (Nested)
        {
            @SetGet Foo!false _sub;
        }
    }

    Foo!true source = new Foo!true;
    Foo!true target = new Foo!true;
    source._a = 8; source._b = ulong.max; source._c = "123";
    source._sub._a = 8; source._sub._b = ulong.max; source._sub._c = "123";
    bindPublications!true(source, target);

    assert(target._a == source._a);
    assert(target._b == source._b);
    assert(target._c == source._c);
    assert(target._sub._a == source._sub._a);
    assert(target._sub._b == source._sub._b);
    assert(target._sub._c == source._sub._c);
}

/**
 * A PropertyBinder synchronizes the value of several variables between themselves.
 *
 * The access to the variables is done via the PropDescriptor format, hence
 * a PropertyBinder stores a list of PropDescriptor with the same types.
 *
 * Params:
 *      T = The type of the properties.
 *      RttiCheck = When set to true, an additional run-time check is performed.
 */
class PropertyBinder(T, bool RttiCheck = false)
{

private:

    DynamicList!(PropDescriptor!T*) _itemsToDestruct;
    DynamicList!(PropDescriptor!T*) _items;
    PropDescriptor!T *_source;

public:

    ///
    this()
    {
        _items = construct!(DynamicList!(PropDescriptor!T*));
        _itemsToDestruct = construct!(DynamicList!(PropDescriptor!T*));
    }

    ~this()
    {
        foreach(immutable i; 0 .. _itemsToDestruct.count)
        {
            auto descr = _itemsToDestruct[i];
            if (descr) destruct(descr);
        }
        _items.destruct;
        _itemsToDestruct.destruct;
    }

    /**
     * Adds a property to the list.
     * If the binder is not local then aProp should neither be a local descriptor,
     * otherwise the descritpor reference will become invalid.
     *
     * Params:
     *      aProp = A PropDescriptor of type T.
     *      isSource = Optional boolean indicating if the descriptor is used as
     *          master property.
     *
     * Returns:
     *      The index of the descriptor in the binding list.
     */
    ptrdiff_t addBinding(ref PropDescriptor!T prop, bool isSource = false)
    {
        static if (RttiCheck)
        {
            if (runtimeTypeInfo!T != aProp.rtti)
                return -1;
        }
        if (isSource) _source = &prop;
        return _items.add(&prop);
    }

    /**
     * Adds a new property to the list.
     * The life-time of the new descriptor is handled internally.
     *
     * Returns:
     *      A new PropDescriptor of type T.
     */
    PropDescriptor!T * newBinding()
    {
        auto result = construct!(PropDescriptor!T);
        _items.add(result);
        _itemsToDestruct.add(result);
        return result;
    }

    /**
     * Removes the aIndex-nth property from the list.
     * The item is freed if it has been allocated by newBinding.
     * source might be invalidated if it matches the item.
     *
     * Params:
     *      index = The index of the descriptor to remove.
     */
    void removeBinding(size_t index)
    {
        auto itm = _items.extract(index);
        if (_source && itm == _source) _source = null;
        if (_itemsToDestruct.remove(itm)) destruct(itm);
    }

    /**
     * Triggers the setter of each property.
     * This method is usually called at the end of a setter method
     * (in the master/source setter).
     *
     * Params:
     *      value = the new value to send to binding.
     */
    void change(T value)
    {
        foreach(item; _items)
        {
            if (item.access == PropAccess.none) continue;
            if (item.access == PropAccess.ro) continue;
            item.set(value);
        }
    }

    /**
     * Calls change() using the value of source.
     */
    void updateFromSource()
    {
        if (!_source) return;
        change(_source.getter()());
    }

    /**
     * Sets the property used as source in updateFromSource().
     * Params:
     *      src = The property to be used as source.
     */
    @property void source(ref PropDescriptor!T src)
    {_source = &src;}

    /**
     * Returns the property used as source in _updateFromSource().
     */
    @property PropDescriptor!T * source()
    {return _source;}

    /**
     * Provides an access to the property descriptors for additional List operations.
     * Note that the items whose life-time is managed should not be modified.
     */
    @property List!(PropDescriptor!T *) items()
    {return _items;}
}

unittest
{
    alias intprops = PropertyBinder!int;
    alias floatprops = PropertyBinder!float;

    class Foo
    {
        private
        {
            int fA;
            float fB;
            intprops fASlaves;
            floatprops fBSlaves;
        }
        public
        {
            this()
            {
                fASlaves = construct!intprops;
                fBSlaves = construct!floatprops;
            }
            ~this()
            {
                fASlaves.destruct;
                fBSlaves.destruct;
            }
            void A(int value)
            {
                if (fA == value) return;
                fA = value;
                fASlaves.change(fA);
            }
            int A(){return fA;}

            void B(float value)
            {
                if (fB == value) return;
                fB = value;
                fBSlaves.change(fB);
            }
            float B(){return fB;}

            void addABinding(ref intProp aProp)
            {
                fASlaves.addBinding(aProp);
            }

            void addBBinding(ref floatProp aProp)
            {
                fBSlaves.addBinding(aProp);
            }
        }
    }

    class FooSync
    {
        private
        {
            int fA;
            float fB;
        }
        public
        {
            void A(int value){fA = value;}
            int A(){return fA;}
            void B(float value){fB = value;}
            float B(){return fB;}
        }
    }

    class Bar
    {
        public int A;
        public float B;
    }

    // 1 master, 2 slaves
    auto a0 = construct!Foo;
    auto a1 = construct!FooSync;
    auto a2 = construct!FooSync;
    auto a3 = construct!Bar;

    auto prp1 = intProp(&a1.A,&a1.A);
    a0.addABinding(prp1);

    auto prp2 = intProp(&a2.A,&a2.A);
    a0.addABinding(prp2);

    intProp prp3 = intProp(&a3.A);
    a0.addABinding(prp3);

    auto prpf1 = floatProp(&a1.B,&a1.B);
    auto prpf2 = floatProp(&a2.B,&a2.B);
    auto prpf3 = floatProp(&a3.B);
    a0.addBBinding(prpf1);
    a0.addBBinding(prpf2);
    a0.addBBinding(prpf3);

    a0.A = 2;
    assert( a1.A == a0.A);
    a1.A = 3;
    assert( a1.A != a0.A);
    a0.A = 4;
    assert( a2.A == a0.A);
    a0.A = 5;
    assert( a3.A == a0.A);

    a0.B = 2.5;
    assert( a1.B == a0.B);
    a1.B = 3.5;
    assert( a1.B != a0.B);
    a0.B = 4.5;
    assert( a2.B == a0.B);
    a0.B = 5.5;
    assert( a3.B == a0.B);

    // interdependent bindings
    auto m0 = construct!Foo;
    auto m1 = construct!Foo;
    auto m2 = construct!Foo;

    intProp mprp0 = intProp(&m0.A, &m0.A);
    intProp mprp1 = intProp(&m1.A, &m1.A);
    intProp mprp2 = intProp(&m2.A, &m2.A);

    m0.addABinding(mprp1);
    m0.addABinding(mprp2);

    m1.addABinding(mprp0);
    m1.addABinding(mprp2);

    m2.addABinding(mprp0);
    m2.addABinding(mprp1);

    m0.A = 2;
    assert( m1.A == m0.A);
    assert( m2.A == m0.A);
    m1.A = 3;
    assert( m0.A == m1.A);
    assert( m2.A == m1.A);
    m2.A = 4;
    assert( m1.A == m2.A);
    assert( m0.A == m2.A);

    a0.destruct;
    a1.destruct;
    a2.destruct;
    a3.destruct;
    m0.destruct;
    m1.destruct;
    m2.destruct;

    writeln("PropertyBinder(T) passed the tests");
}

unittest
{
    auto strSync = construct!(PropertyBinder!int);

    class A
    {
        private int fStr;
        public @property str(int aValue){fStr = aValue;}
        public @property int str(){return fStr;}
    }

    auto a0 = construct!A;
    auto a1 = construct!A;
    auto a2 = construct!A;

    auto propa0str = strSync.newBinding;
    propa0str.define(&a0.str,&a0.str);
    auto propa1str = strSync.newBinding;
    propa1str.define(&a1.str,&a1.str);
    auto propa2str = strSync.newBinding;
    propa2str.define(&a2.str,&a2.str);

    strSync.change(8);

    assert(a0.str == 8);
    assert(a1.str == 8);
    assert(a2.str == 8);

    a0.destruct;
    a1.destruct;
    a2.destruct;
    strSync.destruct;

    writeln("PropertyBinder(T) passed the newBinding() test");
}

