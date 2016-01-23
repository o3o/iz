/**
 * iz string handling functions, mostly related to lexical scanning
 */
module iz.strings;

import
    std.range, std.traits, std.algorithm.searching;
import
    iz.sugar;

version(unittest) import std.stdio;

// Character-related-structs --------------------------------------------------+

/**
 * CharRange is an helper struct that allows to test
 * if a char is within a full range of characters.
 */
struct CharRange
{
    import std.conv: to;
    private immutable dchar _min, _max;
    
    /**
     * Constructs the char range using a string that contains the range bounds.
     *
     * Params:
     *      s = A string. It neither has to be sorted nor to contain the full range.
     */
    this(S)(S s) pure @safe
    if (isSomeString!S)
    {
        import std.algorithm.sorting: sort;
        auto sorted = sort(to!(dchar[])(s));
        _min = sorted[0];
        _max = sorted[$-1];
    }
    
    /**
     * Constructs the char range using the two chars passed as argument.
     *
     * Params:
     *      cmin: The lower character in the range.
     *      cmax: The upper (inclusive) character in the range.
     */
    this(C)(C cmin, C cmax) pure @safe
    if (isSomeChar!C || isImplicitlyConvertible!(C, dchar))
    {
        auto const maybeMin = to!dchar(cmin);
        auto const maybeMax = to!dchar(cmax);
        if (maybeMin <= maybeMax)
        {
            _min = maybeMin;
            _max = maybeMax;
        }
        else
        {
            _min = maybeMax;
            _max = maybeMin;
        }     
    }
    
    /// Returns the lower char in the range.
    dchar min() pure nothrow @safe @nogc
    {return _min;}
    
    /// Returns the upper char in the range.
    dchar max() pure nothrow @safe @nogc
    {return _max;}

    /**
     * Returns true if a character is within the range.
     *
     * Params:
     *      c = A character or any value convertible to a dchar.
     */
    bool opIn_r(C)(C c) pure nothrow @safe @nogc const 
    {
        static if (isSomeChar!C || isImplicitlyConvertible!(C, dchar))
        {
            return ((c >= _min) & (c <= _max)); 
        }
        else static assert(0, "invalid argument type for CharRange.opIn_r(): " ~ C.stringof);
    }
    
    /**
     * Returns the range representation, as a string.
     * This function fails if the range is not within the 0x0 .. 0x80 range.
     */
    string toString() const pure @safe
    {
        auto r = iota(_min, _max+1);
        string result;
        while (!r.empty)
        {
            result ~= to!char(r.front);
            r.popFront;
        }
        return result;
    }
}
///
pure @safe unittest
{
    auto cs1 = CharRange("ajslkdfjlz");
    assert(cs1.min == 'a');
    assert(cs1.max == 'z');
    assert('b' in cs1);
    
    auto cs2 = CharRange('f', 'a');
    assert(cs2.min == 'a');
    assert(cs2.max == 'f');
    assert('b' in cs2);
    assert('g' !in cs2);
    assert(cs2.toString == "abcdef", cs2.toString);
    
    auto cs3 = CharRange(65, 70);
    assert(cs3.min == 65);
    assert(cs3.max == 70);
    assert(66 in cs3);
    assert(71 !in cs3);
}

/// a CharRange that verify characters for decimal numbers.
static immutable CharRange decimalChars = CharRange('0', '9');
/// a CharRange that verify characters for octal numbers.
static immutable CharRange octalChars = CharRange('0', '7');

/**
 * CharMap is an helper struct that allows to test
 * if a char is within a set of characters.
 */
struct CharMap
{
    private bool[] _map;
    private dchar _min, _max;
    
    private void setMinMax(dchar value) nothrow @safe
    {
        if (value <= _min) _min = value;
        else if (value >= _max) _max = value;
        _map.length = _max + 1 - _min; 
    }

    /**
     * Used in the construction process.
     *
     * Params:
     *      lo = The dchar that defines the range lower bound.
     *      hi = The dchar that defines the range upper bound (inclusive).
     *
     * Examples:
     * ---
     * CharMap cm = CharMap['0'..'9'];
     * ---
     */
    static CharRange opSlice(int index)(dchar lo, dchar hi) pure nothrow @nogc 
    {
        return CharRange(lo, hi);
    }
    
    /**
     * Used in the construction process.
     *
     * Params:
     *      a = A list made of character slices, of single characters or
     *
     * any other values whose type is implicitly convertible to dchar.
     *
     * Examples:
     * ---
     * CharMap cm = CharMap['0'..'9', '.', 'f', 'd', 38, 39];
     * ---
     */
    static CharMap opIndex(A...)(A a) nothrow @safe
    {   
        CharMap result;
        
        // bounds
        foreach(elem; a)
        {
            alias T = typeof(elem);
            static if (isSomeChar!T || isImplicitlyConvertible!(T, dchar))
            {
                result.setMinMax(elem);      
            }
            else static if (is(T == CharRange))
            {
                result.setMinMax(elem._min);
                result.setMinMax(elem._max);    
            }
            else static assert(0, "unsupported opIndex argument type: " ~ T.stringof);
        }
        
        result._map[] = false;   
        foreach(elem; a)
        {    
            alias T = typeof(elem);
            static if (isSomeChar!T || isImplicitlyConvertible!(T, dchar))
                result._map[elem - result._min] = true;   
            else static if (is(T == CharRange))
            {
                foreach(size_t i; elem._min - result._min .. elem._max - result._min + 1)
                    result._map[i] = true;
            }
        }
        return result;
    }
    
    /**
     * Returns true if a character is within the map.
     *
     * Params:
     *      c = A character or any value convertible to a dchar.
     */
    bool opIn_r(C)(C c) pure nothrow @nogc const @safe 
    {
        static if (isSomeChar!C || isImplicitlyConvertible!(C, dchar))
        {
            if (c < _min || c > _max) return false;
            else return _map[c - _min]; 
        }
        else static assert(0, "invalid argument type for CharMap.opIn_r(): " ~ C.stringof);
    }
}
///
@safe unittest
{
    CharMap cm = CharMap['a'..'f', '0'..'9' , 'A'..'F', '_', 9];
    assert('a' in cm);
    assert('b' in cm);
    assert('c' in cm);
    assert('d' in cm);
    assert('e' in cm);
    assert('f' in cm);
    assert('g' !in cm);
    assert('A' in cm);
    assert('B' in cm);
    assert('C' in cm);
    assert('D' in cm);
    assert('E' in cm);
    assert('F' in cm);
    assert('G' !in cm);
    assert('0' in cm);
    assert('4' in cm);
    assert('9' in cm);
    assert('_' in cm);
    assert('%' !in cm);
    assert('\t' in cm);
}

/// A CharMap that includes the hexadecimal characters.
immutable CharMap hexChars = CharMap['a'..'f', 'A'..'F', '0'..'9'];
/// A CharMap that includes the white characters.
immutable CharMap whiteChars = CharMap['\t'..'\r', ' '];

/**
 * Returns a input range to process directly a C-style null terminated string 
 * without converting it to a D string. The front is not decoded.
 * Params:
 *      c = a pointer to a character.
 * Returns:
 *      A InputRange whose elements type matches c target type.
 */
auto nullTerminated(C)(C c)
if (isPointer!C && isSomeChar!(PointerTarget!(C)))
{
    struct NullTerminated(C)
    {
        private C _front;
        ///
        this(C c)
        {
            _front = c;
        }
        ///
        @property bool empty()
        {
            return *_front == 0;
        }
        ///
        auto front()
        {
            return *_front;
        }
        ///
        void popFront()
        {
            ++_front;
        }
        ///
        C save()
        {
            return _front;
        }
    }
    return NullTerminated!C(c);
}
///
unittest
{
    auto text = "ab cd\0";
    auto cString = nullTerminated(text.ptr);
    assert(nextWord(cString) == "ab");
    auto saved = nullTerminated(cString.save);
    assert(nextWord(cString) == "cd");
    assert(nextWord(saved) == "cd");
    assert(cString.empty);
    auto wtext = "ab cd\0"w;
    auto cWideString = nullTerminated(wtext.ptr);
    assert(nextWord(cWideString) == "ab"w);
    assert(nextWord(cWideString) == "cd"w);
    assert(cWideString.empty);
}


// -----------------------------------------------------------------------------
// Generic Scanning functions -------------------------------------------------+
private template CharType(T)
{
    alias CharType = Unqual!(ElementEncodingType!T);
}

/**
 * Tests wether $(D T) is supported in the several scanning functions.
 *
 * T must either be a CharRange, a CharMap, supports std.algorithm.searching.canFind,
 * be a callable of type $(D bool(dchar)) or $(D bool function(dchar)) or be a
 * single dchar.
 */
bool isCharTester(T)()
{
    static if (isInputRange!T && isSomeChar!(ElementType!T))
        return true;
    else static if (is(Unqual!T == CharRange))
        return true;
    else static if (is(Unqual!T == CharMap))
        return true;
    else static if (isAssociativeArray!T && isSomeChar!(KeyType!T))
        return true; 
    else static if (isSomeFunction!T && is(ReturnType!T == bool) &&
        Parameters!T.length == 1 && is(Parameters!T[0] == dchar))
        return true;
    else static if (isSomeChar!T)
        return true;
    else
        return false;
}


/**
 * Returns the next word in the range passed as argument.
 *
 * Params: 
 *      range = A character input range. The range is consumed for each word.
 *      charTester = Defines the valid characters to make a word.
 *
 * Returns:
 *      A string containing the word. If the result length is null then the
 *      range parameter has not been consumed.
 */
auto nextWord(Range, T, bool until = false)(ref Range range, T charTester)
if (isInputRange!Range && isSomeChar!(ElementType!Range) && isCharTester!T)
{
    alias UT = Unqual!T; 
    CharType!Range[] result;
    dchar current = void;

    static if (is(UT == CharRange) || is(UT == CharMap) || isAssociativeArray!T)
    {
        while (true)
        {
            if (range.empty) break;
            current = range.front;
            
            static if (until)
            {
                if (current !in charTester)
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
            else
            {
                if (current in charTester)
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
        }
    }
    else static if (isInputRange!T)
    {
        while (true)
        {
            if (range.empty) break;
            current = range.front;
            
            static if (until)
            {
                if (!canFind(charTester, current))
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
            else
            {
                if (canFind(charTester, current))
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
        }
    }
    else static if (isSomeFunction!UT)
    {
        while (true)
        {
            if (range.empty) break;
            current = range.front;

            static if (until)
            {
                if (!charTester(current))
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
            else
            {
                if (charTester(current))
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
        }
    }
    else static if (isSomeChar!UT)
    {
        while (true)
        {
            if (range.empty) break;
            current = range.front;

            static if (until)
            {
                if (charTester != current)
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
            else
            {
                if (charTester == current)
                {
                    result ~= current;
                    range.popFront;
                }
                else break;
            }
        }
    }
    else static assert(0, "unsupported charTester argument type in nextWord(): " ~ T.stringof);

    return result;
}
///
unittest
{
    auto cs1 = "azertyuiopqsdfghjklmwxcvbn";
    auto cs2 = " \r\n\t";
    auto cs3 = CharRange('a','z');
    bool[dchar] cs4 = ['\r':true, '\n': true, '\t':true, ' ':true ];
    auto src1 = "az er
    ty";
    auto src2 = "az er
    ty";

    auto w1 = nextWord(src1, cs1);
    assert(w1 == "az");
    nextWord(src1, cs2);
    auto w2 = nextWord(src1, cs1);
    assert(w2 == "er");
    nextWord(src1, cs2);
    auto w3 = nextWord(src1, cs1);
    assert(w3 == "ty");
    nextWord(src1, cs2);

    auto w11 = nextWord(src2, cs3);
    assert(w11 == "az");
    nextWord(src2, cs4);
    auto w22 = nextWord(src2, cs3);
    assert(w22 == "er");
    nextWord(src2, cs4);
    import std.ascii: isAlpha;
    auto w33 = nextWord(src2, &isAlpha);
    assert(w33 == "ty");
}


/**
 * Returns the next word in the range passed as argument.
 *
 * Params: 
 *      range = A character input range. The range is consumed for each word.
 *      charTester = Defines the opposite of the valid characters to make a word.
 *
 * Returns:
 *      A string containing the word. If the result length is null then the
 *      range parameter has not been consumed.
 */
auto nextWordUntil(Range, T)(ref Range range, T charTester)
{
    return nextWord!(Range, T, true)(range, charTester);
}
///
unittest
{
    auto src = "azertyuiop
    sdfghjk".dup;
    auto skp = CharRange("\r\n\t".dup);
    auto w = nextWordUntil(src, skp);
    assert(w == "azertyuiop");
}


/**
 * Skips the next word in the range passed as argument.
 *
 * Params:
 *      range = A character input range. The range is consumed for each word.
 *      charTester = Defines the valid characters to make a word.
 */
void skipWord(Range, T, bool until = false)(ref Range range, T charTester)
if (isInputRange!Range && isSomeChar!(ElementType!Range) && isCharTester!T)
{
    alias UT = Unqual!T;
    static if (is(UT == CharRange) || is(UT == CharMap) || isAssociativeArray!T)
    {
        while (true)
        {
            if (range.empty) break;
            static if (until)
            {
                if (range.front !in charTester)
                    range.popFront;
                else break;
            }
            else
            {
                if (range.front in charTester)
                    range.popFront;
                else break;
            }       
        }
    }
    else static if (isInputRange!T)
    {
        while (true)
        {
            if (range.empty) break;
            static if (until)
            {
                if (!canFind(charTester, range.front))
                    range.popFront;
                else break;            
            }
            else
            {
                if (canFind(charTester, range.front))
                    range.popFront;
                else break;
            }
        }
    }
    else static if (isSomeFunction!UT)
    {
        while (true)
        {
            if (range.empty) break;
            static if (until)
            {
                if (!charTester(range.front))
                    range.popFront;
                else break;            
            }
            else
            {                        
                if (charTester(range.front))
                    range.popFront;
                else break;
            }
        }
    }
    else static if (isSomeChar!UT)
    {
        while (true)
        {
            if (range.empty) break;
            static if (until)
            {
                if (charTester != range.front)
                    range.popFront;
                else break;
            }
            else
            {
                if (charTester == range.front)
                    range.popFront;
                else break;
            }
        }
    }
    else static assert(0, "unsupported charTester argument type in skipWord(): " ~ T.stringof);
}
///
unittest
{
    auto src1 = "\t\t\r\ndd";
    auto skp1 = CharRange("\r\n\t");
    skipWord(src1, skp1);
    assert(src1 == "dd");
    import std.ascii: isWhite;
    auto src2 = "\t\t\r\nee";
    skipWord(src2, &isWhite);
    assert(src2 == "ee");
}


/**
 * Skips the next word in the range passed as argument.
 *
 * Params:
 *      range = A character input range. The range is consumed for each word.
 *      charTester = Defines the opposite of the valid characters to make a word.
 */
void skipWordUntil(Range, T)(ref Range range, T charTester)
{
    skipWord!(Range, T, true)(range, charTester);
}
///
unittest
{
    auto src = "dd\r";
    auto skp = CharRange("\r\n\t");
    skipWordUntil(src, skp);
    assert(src == "\r");
}


/**
 * Tries to make a fixed length slice by consuming range.
 *
 * Params:
 *      range = A character input range. The range is consumed for each word.
 *      len = An integral value.
 *
 * Returns:
 *      At the tail a string whose length is less or equal to $(I len), otherwise
 *      always a string of length $(I len).
 */
auto nextSlice(Range, T)(ref Range range, T len)
if (isInputRange!Range && isSomeChar!(ElementType!Range) && isIntegral!T)
{
    CharType!Range[] result;
    size_t cnt;
    while (true)
    {
        if (cnt == len || range.empty)
            break;
        result ~= range.front;
        range.popFront;
        ++cnt;
    }   
    
    return result;
}
///
unittest
{
    auto text0 = "012"; 
    assert(text0.nextSlice(2) == "01");
    auto text1 = "3";
    assert(text1.nextSlice(8) == "3");
    auto text2 = "45";
    assert(text2.nextSlice(0) == "");
    assert(text1.nextSlice(12_34_56) == "");
    auto ut = "é_é";
    assert(ut.nextSlice(3) == "é_é");
}


/**
 * Returns true if a string starts with a particular sub string.
 *
 * Params:
 *      range: A character input range. The range is not consumed.
 *      stuff: the sub string, also works with single chars.
 */
bool canRead(Range, Stuff)(ref Range range, Stuff stuff)
if (isInputRange!Range && isSomeChar!(ElementType!Range)
    && (isSomeChar!Stuff || isSomeString!Stuff))
{
    static if (isSomeString!Range)
    {
        if (range.empty)
            return false;
        else
        {
            static if (isSomeChar!Stuff)
                return range.front == stuff;
            else
            {
                import std.conv: to;
                auto dstuff = to!dstring(stuff);
                auto reader = ArrayRange!(ElementEncodingType!Range)(range);
                auto slice = reader.nextSlice(dstuff.walkLength);
                return dstuff == slice;
            }
        }
    } 
    else
    {
        import std.algorithm.searching: startsWith;
        return startsWith(range, stuff);
    } 
}
///
unittest
{
    auto text0 = "{0}".dup;
    assert(text0.canRead('{'));
    auto text1 = "(* bla *)".dup;
    assert(text1.canRead("(*"));
    assert(text1 == "(* bla *)");
    string text2 = "0x123456";
    assert(!text2.canRead("0b"));
}
//------------------------------------------------------------------------------
// Text scanning utilities ----------------------------------------------------+

/**
 * Returns an input range consisting of the input argument sliced by group of 
 * length len.
 */
auto bySlice(Range)(ref Range range, size_t len)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{
    struct BySlice
    {
        private Range* _range;
        private bool _emptyLine;
        private CharType!Range[] _front;
        ///
        this(ref Range range)
        {
            _range = &range;
            popFront;
        }
        ///
        void popFront()
        {
            _front = nextSlice(*_range, len);
        }
        ///
        auto front()
        {
            return _front;
        }
        ///
        @property bool empty()
        {
            return _front.length == 0;
        }
    }
    return BySlice(range);
}
///
unittest
{
    auto text = "AABBCCDD";
    assert(text.bySlice(2).array == ["AA","BB","CC","DD"]);
    auto str = "AAE";
    assert(str.bySlice(2).array == ["AA","E"]);
}


/**
 * Tries to read immediatly an EOL in range and returns it.
 */
auto readEol(Range)(ref Range range)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{
    CharType!Range[] result;
    if (range.canRead("\r\n")) result = range.nextSlice(2);
    else if (range.canRead('\n')) result = range.nextSlice(1);
    return result;
}
///
unittest
{
    auto text0 = "";
    assert(readEol(text0) == "");
    auto text1 = " ";
    assert(readEol(text1) == "");
    auto text2 = "\n";
    assert(readEol(text2) == "\n");
    auto text3 = "\r\n";
    assert(readEol(text3) == "\r\n");
}


/**
 * Tries to skip immediatly an EOL in range.
 */
void skipEol(Range)(ref Range range)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{
    if (range.canRead("\r\n")) range.nextSlice(2);
    else if (range.canRead('\n')) range.nextSlice(1);        
}
///
unittest
{
    auto text0 = "";
    skipEol(text0);
    assert(text0 == "");
    auto text1 = " ";
    skipEol(text1);
    assert(text1 == " ");
    auto text2 = "\n";
    skipEol(text2);
    assert(text2 == "");
    auto text3 = "\r\na";
    skipEol(text3);
    assert(text3 == "a");
}


/**
 * Returns the next line within range.
 */
auto nextLine(bool keepTerminator = false, Range)(ref Range range)
{
    auto result = nextWordUntil(range, "\r\n");
    static if (keepTerminator) result ~= range.readEol;
    else range.skipEol;
    return result;
}
///
unittest
{
    auto text = "123456\r\n12345\n1234\r\n123\r\n12\r\n1";
    assert(nextLine!false(text) == "123456");
    assert(nextLine!false(text) == "12345");
    assert(nextLine!false(text) == "1234");
    assert(nextLine!false(text) == "123");
    assert(nextLine!false(text) == "12");
    assert(nextLine!false(text) == "1");
    assert(nextLine!false(text) == "");
    assert(nextLine!false(text) == "");
}


/**
 * Returns an input range consisting of each line in the input argument
 */
auto byLine(Range)(ref Range range)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{ 
    struct ByLine
    {
        private Range* _range;
        private bool _emptyLine;
        private CharType!Range[] _front, _strippedfront;
        ///
        this(ref Range range)
        {
            _range = &range;
            popFront;
        }
        ///
        void popFront()
        {
            _front = nextLine!true(*_range);
            import std.string: stripRight;
            _strippedfront = stripRight(_front);
        }
        ///
        auto front()
        {
            return _strippedfront;
        }
        ///
        @property bool empty()
        {
            return _front.length == 0;
        }
    }
    return ByLine(range);
}
///
unittest
{
    auto text = "aw\r\nyess";
    auto range = text.byLine;
    assert(range.front == "aw");
    range.popFront;
    assert(range.front == "yess");
    auto nums = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9";
    import std.algorithm.iteration: reduce;
    assert(nums.byLine.reduce!((a,b) => a ~ b) == "0123456789");
}


/**
 * Returns the lines count within the input range.
 * The input range is not consumed.
 */
size_t lineCount(Range)(Range range)
{
    return range.byLine.array.length;
}
///
unittest
{
    auto text1= "";
    assert(text1.lineCount == 0);
    auto text2 = "\n\r\n";
    assert(text2.lineCount == 2);
    auto text3 = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n\n\n";
    assert(text3.lineCount == 12);
}


/**
 * Returns the next word within range. 
 * Words are spliited using the White characters, which are never included.
 */
auto nextWord(Range)(ref Range range)
{
    skipWord(range, whiteChars);
    return nextWordUntil(range, whiteChars);
}
///
unittest
{
    auto text = " lorem ipsum 123456";
    assert(text.nextWord == "lorem");
    assert(text.nextWord == "ipsum");
    assert(text.nextWord == "123456");
}


/**
 * Returns an input range consisting of each non-blank word in the input argument.
 */
auto byWord(Range)(ref Range range)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{ 
    struct ByWord
    {
        private Range* _range;
        private CharType!Range[] _front;
        ///
        this(ref Range range)
        {
            _range = &range;
            popFront;
        }
        ///
        void popFront()
        {
            _front = nextWord(*_range);
        }
        ///
        auto front()
        {
            return _front;
        }
        ///
        @property bool empty()
        {
            return _front.length == 0;
        }
    }
    return ByWord(range);
}
///
unittest
{
    auto text = "aw yess, this is so cool";
    auto range = text.byWord;
    assert(range.front == "aw");
    range.popFront;
    assert(range.front == "yess,");
    range.popFront;
    assert(range.front == "this");
    auto nums = "0 1 2 3 4 5 6 7 8 9";
    import std.algorithm.iteration: reduce;
    assert(nums.byWord.reduce!((a,b) => a ~ b) == "0123456789");
}


/**
 * Returns the word count within the input range.
 * Words are separatedd by ascii whites. input range is not consumed.
 */
size_t wordCount(Range)(Range range)
{
    return range.byWord.array.length;
}
///
unittest
{
    auto text = "1 2 3 4 5 6 7 8 9 \n 10";
    assert(text.wordCount == 10);
    assert(text == "1 2 3 4 5 6 7 8 9 \n 10");
}


/**
 * Returns the next separated word.
 * Separators are always removed, white characters optionally.
 */
auto nextSeparated(Range, Separators, bool strip = true)(ref Range range, Separators sep)
{
    auto result = nextWordUntil(range, sep);
    if (!range.empty) range.popFront;
    static if (strip)
    {
        skipWord(result, whiteChars);
        result = nextWordUntil(result, whiteChars);
    }
    return result;
}
///
unittest
{
    auto seps = CharMap[',', '\n'];
    auto text = "name, âge \n Douglas, 27 \n Sophia 26";
    assert(text.nextSeparated(seps) == "name");
    assert(text.nextSeparated(seps) == "âge");
    assert(text.nextSeparated(seps) == "Douglas");
    assert(text.nextSeparated(seps) == "27");
}


/**
 * Returns an input range consisting of each separated word in the input argument
 */
auto bySeparated(Range, Separators, bool strip = true)(ref Range range, Separators sep)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
{
    struct BySep
    {
        private Range* _range;
        private CharType!Range[] _front;
        ///
        this(ref Range range)
        {
            _range = &range;
            popFront;
        }
        ///
        void popFront()
        {
            _front = nextSeparated!(Range, Separators, strip)(*_range, sep);
        }
        ///
        auto front()
        {
            return _front;
        }
        ///
        @property bool empty()
        {
            return _front.length == 0;
        }
    }
    return BySep(range);
}
///
unittest
{
    auto text = "name = Douglas \n age =27 \n";
    auto range = text.bySeparated(CharMap['=', '\n']);
    assert(range.front == "name");
    range.popFront;
    assert(range.front == "Douglas");
    range.popFront;
    assert(range.front == "age");
    range.popFront;
    assert(range.front == "27");
    range.popFront;
}


/**
 * Tries to read immediatly a decimal number in range.
 */
auto readDecNumber(Range)(ref Range range)
{
    return range.nextWord(decimalChars);
}
///
unittest
{
    auto text = "0123456 789";
    assert(text.readDecNumber == "0123456");
    text.popFront;
    assert(text.readDecNumber == "789");
    
    string t = "456";
    if (auto num = readDecNumber(t))
        assert (num == "456");
}


/**
 * Tries to read immediatly an hexadecimal number in range.
 */
auto readHexNumber(Range)(ref Range range)
{
    return range.nextWord(hexChars);
}
///
unittest
{
    auto text1 = "1a2B3C o";
    assert(text1.readHexNumber == "1a2B3C");
    assert(text1 == " o");
    auto text2 = "A897F2f2Ff2fF3c6C9c9Cc9cC9c123 o";
    assert(text2.readHexNumber == "A897F2f2Ff2fF3c6C9c9Cc9cC9c123");
    assert(text2 == " o");
}


/**
 * Strips leading white characters.
 */
void stripLeftWhites(Range)(ref Range range)
{
    range.skipWord(whiteChars);
}
///
unittest
{
    auto text = "  \n\r\v bla".dup;
    auto rng = ArrayRange!char(text);
    rng.stripLeftWhites;
    assert(rng.array == "bla");
}


/**
 * Escapes some characters in the input text.
 *
 * Params:
 *      range = The character range to process. The source is not consumed.
 *      pairs = An array of pair. Each pair (char[2]) defines a source and a
 *      target character. The slash is automatically escaped and must not be
 *      included in the array.
 * Returns:
 *      An array of character whose type matches the range element type.
 */
auto escape(Range)(Range range, const char[2][] pairs)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
in
{
    foreach(pair; pairs)
    {
        assert(pair[0] != '\\', "the slash (\\) should not be set as pair");
        assert(pair[1] != '\\', "the slash (\\) should not be set as pair");
    }
}
body
{
    CharType!Range[] result;
    dchar front;
    bool done = void, wasSlash = void;
    while (!range.empty)
    {
        wasSlash = front == '\\';
        front = range.front;
        done = false;
        foreach(pair; pairs) if (front == pair[0] && !wasSlash)
        {
            done = true;
            result ~= `\` ~ pair[1];
            range.popFront;
            break;
        }
        if (front == '\\')
            result ~= front;
        if (!done)
        {
            result ~= front;
            range.popFront;
        }
    }
    return result;
}
///
unittest
{
    assert(`1"`.escape([['"','"']]) == `1\"`);
    assert(`1"1"11"1`.escape([['"','"']]) == `1\"1\"11\"1`);
    assert("\n\"1".escape([['"','"'],['\n','n']]) == `\n\"1`);
    assert(`1\"`.escape([['"','"']]) == `1\\"`);
    assert(`\`.escape([]) == `\\`);
}


/**
 * Un-escapes some characters in the input text.
 *
 * Params:
 *      range = The character range to process. The source is not consumed.
 *      pairs = An array of pair. Each pair (char[2]) defines a target and a
 *      source character. The slash is automatically unescaped and must not be
 *      included in the array.
 * Returns:
 *      An array of character whose type matches the range element type.
 *      Even if invalid, a terminal slash is appended to the result.
 */
auto unEscape(Range)(Range range, const char[2][] pairs)
if (isInputRange!Range && isSomeChar!(ElementType!Range))
in
{
    foreach(pair; pairs)
    {
        assert(pair[0] != '\\', "the slash (\\) should not be set as pair");
        assert(pair[1] != '\\', "the slash (\\) should not be set as pair");
    }
}
body
{
    CharType!Range[] result;
    dchar front = void;
    bool slash;
    while(!range.empty)
    {
        front = range.front;
        if (slash && front == '\\')
        {
            result ~= '\\';
            slash = false;
            range.popFront;
            continue;
        }
        if (front == '\\')
        {
            slash = true;
            range.popFront;
            if (range.empty)
                result ~= '\\';
            continue;
        }
        if (slash)
        {
            foreach(pair; pairs) if (front == pair[1])
            {
                result ~= pair[0];
                slash = false;
                break;
            }
            if (slash) result ~= '\\';
            slash = false;
        }
        else result ~= front;
        range.popFront;
    }
    return result;
}
///
unittest
{
    assert( `1\"`.unEscape([['"','"']]) == `1"`);
    assert(`1\"1\"11\"1`.unEscape([['"','"']]) == `1"1"11"1`);
    assert(`\n\"1`.unEscape([['"','"'],['\n','n']]) == "\n\"1");
    assert(`\\\\`.unEscape([]) == `\\`);
    assert(`\\`.unEscape([]) == `\`);
    assert(`\`.unEscape([]) == `\`);
}

//------------------------------------------------------------------------------

