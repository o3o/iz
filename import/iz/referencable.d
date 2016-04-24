/**
 * Look up table system for storing and retrieving references
 * from an unique identifier.
 */
module iz.referencable;

package string typeString(T)()
{
    return typeid(T).toString;
}

version(unittest)
{
    class TestModuleScope{}
}

unittest
{
    class Foo{}
    assert( typeString!int == "int");
    assert( typeString!TestModuleScope == __MODULE__ ~ ".TestModuleScope" );
}

/**
 * interface for a class reference.
 */
interface Referenced
{
    /// the ID, as set when added as reference.
    string refID();
    /// the type, as registered in the ReferenceMan ( typeString!typeof(this) )
    string refType();
}

/**
 * Associates an pointer (a reference) to an unique ID (ulong).
 */
private alias itemsById = void*[char[]];

/**
 * itemsById for a type (identified by a string).
 */
private alias refStore = itemsById[string];


/**
 * The Referencable manager associates variables of a particular type to
 * an unique identifier.
 *
 * This manager is mostly used by iz.classes and iz.serializer.
 * For example, in a setting file, it allows to store the unique identifier
 * associated to a class instance, rather than storing all its properties, as
 * the instance settings may be saved elsewhere.
 * This also allow to serialize fat pointers, such as delegates.
 */
static struct ReferenceMan
{

private:

    static __gshared refStore fStore;

public:

// Helpers --------------------------------------------------------------------+

    /**
     * Indicates if a type is referenced.
     *
     * Params:
     *      RT = The type to test.
     *
     * Returns:
     *      True if the type is referenced otherwise false.
     */
    static bool isTypeStored(RT)()
    {
        return ((typeString!RT in fStore) !is null);
    }

    /**
     * Indicates if a variable is referenced.
     *
     * Params:
     *      RT = a referencable type. Optional, likely to be infered.
     *      aReference = a pointer to a RT.
     *
     * Returns:
     *      True if the variable is referenced otherwise false.
     */
    static bool isReferenced(RT)(RT* aReference)
    {
        return (referenceID!RT(aReference) != "");
    }

    /**
     * Support for the in operator.
     * Evaluates to true if the variable is referenced otherwise false.
     */
    static bool opBinaryRight(string op : "in", RT)(RT* aReference)
    {
        return (referenceID!RT(aReference) != "");
    }

    /**
     * Empties the references and the types.
     */
    static void reset()
    {
        fStore = fStore.init;
    }
// -----------------------------------------------------------------------------
// Add stuff ------------------------------------------------------------------+

    /**
     * Stores a type. This is a convenience function since
     * storeReference() automatically stores a type when needed.
     *
     * Params:
     *      RT = A type to reference.
     */
    static void storeType(RT)()
    {
        fStore[typeString!RT][""] = null;
    }

    /**
     * Proposes an unique ID for a reference. This is a convenience function
     * that will not return the same values for each software session.
     *
     * Params:
     *      RT = A referencable type. Optional, likely to be infered.
     *      aReference = A pointer to a RT.
     *
     * Returns:
     *      The unique string used to identify the reference.
     */
    static string getIDProposal(RT)(RT* aReference)
    {
        // already stored ? returns current ID
        const string ID = referenceID(aReference);
        if (ID != "") return ID;

        // not stored ? returns 1
        if (!isTypeStored)
        {
            storeType!RT;
            return "entry_1";
        }

        // try to get an available ID in the existing range
        foreach(immutable i; 0 .. fStore[typeString!RT].length)
        {
            import std.string: format;
            if (fStore[typeString!RT][i] == null)
                return format("entry_%d", i);
        }

        // otherwise returns the next ID after the current range.
        foreach(immutable i; 0 .. ulong.max)
        {
            import std.string: format;
            if (i > fStore[typeString!RT].length)
                return format("entry_%d", i);
        }

        assert(0, "ReferenceMan is full for this type");
    }

    /**
     * Tries to store a reference.
     *
     * Params:
     *      RT = the type of the reference.
     *      aReference = a pointer to a RT. Optional, likely to be infered.
     *      anID = the unique identifier for this reference.
     *
     * Returns:
     *      true if the reference is added otherwise false.
     */
    static bool storeReference(RT)(RT* aReference, in char[] anID)
    {
        if (anID == "") return false;
        // what's already there ?
        const RT* curr = reference!RT(anID);
        if (curr == aReference) return true;
        if (curr != null) return false;
        //
        fStore[typeString!RT][anID] = aReference;
        return true;
    }
// -----------------------------------------------------------------------------
// Remove stuff ---------------------------------------------------------------+

    /**
     * Tries to remove the reference matching to an ID.
     *
     * Params:
     *      RT = The type of the reference to remove.
     *      anID = The string that identifies the reference to remove.
     *
     * Returns:
     *      The reference if it's found otherwise null.
     */
    static RT* removeReference(RT)(in char[] anID)
    {
        auto result = reference!RT(anID);
        if (result) fStore[typeString!RT][anID] = null;
        return result;
    }

    /**
     * Removes a reference.
     *
     * Params:
     *      RT = The type of the reference to remove. Optional, likely to be infered.
     *      aReference = The pointer to the RT to be removed.
     */
    static void removeReference(RT)(RT* aReference)
    {
        if (auto id = referenceID!RT(aReference))
            fStore[typeString!RT][id] = null;
    }

// -----------------------------------------------------------------------------
// Query stuff ----------------------------------------------------------------+

    /**
     * Indicates if a variable is referenced.
     *
     * Params:
     *      RT = The type of the reference. Optional, likely to be infered.
     *      aReference = A pointer to a RT.
     *
     * Returns:
     *      A non empty string if the variable is referenced.
     */
    static const(char)[] referenceID(RT)(RT* aReference)
    {
        if (!isTypeStored!RT) return "";
        foreach (k; fStore[typeString!RT].keys)
        {
            if (fStore[typeString!RT][k] == aReference)
                return k;
        }
        return "";
    }

    /**
     * Retrieves a reference.
     *
     * Params:
     *      RT = The type of the reference to retrieve.
     *      anID = The unique identifier of the reference to retrieve.
     *
     * Returns:
     *      Null if the operation fails otherwise a pointer to a RT.
     */
    static RT* reference(RT)(in char[] anID)
    {
        if (anID == "") return null;
        if (!isTypeStored!RT) return null;
        return cast(RT*) fStore[typeString!RT].get(anID, null);
    }
// -----------------------------------------------------------------------------        

}

unittest
{
    import iz.memory: construct, destructEach;
    
    alias delegate1 = ubyte delegate(long param);
    alias delegate2 = short delegate(uint param);
    class Foo{int aMember;}

    assert( !ReferenceMan.isTypeStored!delegate1 );
    assert( !ReferenceMan.isTypeStored!delegate2 );
    assert( !ReferenceMan.isTypeStored!Foo );

    ReferenceMan.storeType!delegate1;
    ReferenceMan.storeType!delegate2;
    ReferenceMan.storeType!Foo;

    assert( ReferenceMan.isTypeStored!delegate1 );
    assert( ReferenceMan.isTypeStored!delegate2 );
    assert( ReferenceMan.isTypeStored!Foo );

    auto f1 = construct!Foo;
    auto f2 = construct!Foo;
    auto f3 = construct!Foo;
    scope(exit) destructEach(f1,f2,f3);

    assert( !ReferenceMan.isReferenced(&f1) );
    assert( !ReferenceMan.isReferenced(&f2) );
    assert( !ReferenceMan.isReferenced(&f3) );

    assert( ReferenceMan.referenceID(&f1) == "");
    assert( ReferenceMan.referenceID(&f2) == "");
    assert( ReferenceMan.referenceID(&f3) == "");

    ReferenceMan.storeReference( &f1, "a.f1" );
    ReferenceMan.storeReference( &f2, "a.f2" );
    ReferenceMan.storeReference( &f3, "a.f3" );

    assert( ReferenceMan.reference!Foo("a.f1") == &f1);
    assert( ReferenceMan.reference!Foo("a.f2") == &f2);
    assert( ReferenceMan.reference!Foo("a.f3") == &f3);

    assert( ReferenceMan.referenceID(&f1) == "a.f1");
    assert( ReferenceMan.referenceID(&f2) == "a.f2");
    assert( ReferenceMan.referenceID(&f3) == "a.f3");

    assert( ReferenceMan.isReferenced(&f1) );
    assert( ReferenceMan.isReferenced(&f2) );
    assert( ReferenceMan.isReferenced(&f3) );
    assert( &f3 in ReferenceMan );

    ReferenceMan.removeReference(&f1);
    ReferenceMan.removeReference(&f2);
    ReferenceMan.removeReference!Foo("a.f3");

    assert( !ReferenceMan.isReferenced(&f1) );
    assert( !ReferenceMan.isReferenced(&f2) );
    assert( !ReferenceMan.isReferenced(&f3) );

    ReferenceMan.removeReference!Foo("a.f1");
    ReferenceMan.removeReference(&f2);
    ReferenceMan.removeReference!Foo("a.f3");
    
    ReferenceMan.reset;
    assert( !ReferenceMan.isTypeStored!Foo );
    
    ReferenceMan.storeReference( &f1, "a.f1" );
    assert( ReferenceMan.isTypeStored!Foo );
}

