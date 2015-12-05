/**
 * iz streams, standard streams implementation with several extention related
 * to D ranges.
 */
module iz.streams;

import
    core.exception;
import
    std.string, std.range, std.traits, std.conv;
import
    iz.types, iz.memory;

version(unittest) import std.stdio;

/// stream creation mode 'There': open only if exists.
immutable int cmThere    = 0;
/// stream creation mode 'NotThere': create only if not exists.
immutable int cmNotThere = 1;
/// stream creation mode 'Always': create if not exists otherwise open.
immutable int cmAlways   = 2;

version (Windows) 
{
    import core.sys.windows.windows, std.windows.syserror, std.c.windows.windows;

    private immutable READ_WRITE =  GENERIC_READ | GENERIC_WRITE;
    private immutable FILE_SHARE_ALL = FILE_SHARE_READ | FILE_SHARE_WRITE;

    extern(Windows) export BOOL SetEndOfFile(in HANDLE hFile);

    extern(Windows) export HANDLE CreateNamedPipeA(
       LPCTSTR lpName,
       DWORD dwOpenMode,
       DWORD dwPipeMode,
       DWORD nMaxInstances,
       DWORD nOutBufferSize,
       DWORD nInBufferSize,
       DWORD nDefaultTimeOut,
       LPSECURITY_ATTRIBUTES lpSecurityAttributes
    );

    alias StreamHandle = HANDLE;

    private immutable int skBeg = FILE_BEGIN;
    private immutable int skCur = FILE_CURRENT;
    private immutable int skEnd = FILE_END;

    /// defines the FileStream share modes.
    immutable int shNone = 0;
    /// ditto
    immutable int shRead = FILE_SHARE_READ;
    /// ditto
    immutable int shWrite= FILE_SHARE_WRITE;
    /// ditto
    immutable int shAll  = shWrite | shRead;

    /// defines the FileStream access modes.
    immutable uint acRead = GENERIC_READ;
    /// ditto
    immutable uint acWrite= GENERIC_WRITE;
    /// ditto
    immutable uint acAll  = acRead | acWrite;

    /// returns true if aHandle is valid.
    bool isHandleValid(StreamHandle aHandle)
    {
        return (aHandle != INVALID_HANDLE_VALUE);
    }

    /// translates a cmXX to a platform specific option.
    int cmToSystem(int aCreationMode)
    {
        switch(aCreationMode)
        {
            case cmThere: return OPEN_EXISTING;
            case cmNotThere: return CREATE_NEW;
            case cmAlways: return OPEN_ALWAYS;
            default: return OPEN_ALWAYS;
        }
    }

}
version (Posix) 
{
    import core.sys.posix.fcntl, core.sys.posix.unistd;
    import core.sys.posix.stdio;

    public alias StreamHandle = int;

    // Stream seek modes, used as platform-specific constants in SeekMode.
    private immutable int skBeg = 0;//SEEK_SET;
    private immutable int skCur = 1;//SEEK_CUR;
    private immutable int skEnd = 2;//SEEK_END;

    /// share modes. (does not allow execution)
    immutable int shNone = octal!600;
    immutable int shRead = octal!644;
    immutable int shWrite= octal!622;
    immutable int shAll  = octal!666;

    /// access modes.
    immutable uint acRead = O_RDONLY;
    immutable uint acWrite= O_WRONLY;
    immutable uint acAll  = O_RDWR;

    /// pipe direction
    immutable uint pdIn  = 0;
    immutable uint pdOut = 0;
    immutable uint pdAll = 0;

    /// returns true if aHandle is valid.
    bool isHandleValid(StreamHandle aHandle)
    {
        return (aHandle > -1);
    }

    /// translates a cmXX to a platform specific option.
    int cmToSystem(int aCreationMode)
    {
        switch(aCreationMode)
        {
            case cmThere: return 0;
            case cmNotThere: return O_CREAT | O_EXCL;
            case cmAlways: return O_CREAT;
            default: return O_CREAT;
        }
    }
}

/**
 * Enumerates the Stream seek modes.
 *
 * Bugs:
 *      https://issues.dlang.org/show_bug.cgi?id=13975
 */
enum SeekMode 
{
    beg = skBeg, /// seek from the beginning. 
    cur = skCur, /// seek from the current position.
    end = skEnd  /// seek from the ending.
}

/**
 * An implementer can save to and load from a Stream.
 */
interface StreamPersist
{
    /// Saves something in aStream
    void saveToStream(Stream stream);
    /// Loads something from aStream. aStream initial position is preserved.
    void loadFromStream(Stream stream);
}

/**
 * An implementer can save to and load from a file with a UTF8 file name.
 */
interface FilePersist8
{
    /// Saves something to aFilename.
    void saveToFile(in char[] aFilename);
    /// Loads something to aFilename.
    void loadFromFile(in char[] aFilename);
    /// Returns the filename passed as argument in saveToFile or loadFromFile.
    string filename();
}

/// Generates all the typed write() and read() of a Stream implementation.
string genReadWriteVar()
{
    import std.ascii: toUpper;
    string result;
    char[] type;
    foreach(T; BasicTypes)
    {
        type = T.stringof.dup;
        type[0] = toUpper(type[0]);
        result ~= "alias read" ~ type ~ "= readVariable!" ~ T.stringof ~  ';';
        result ~= "alias write" ~ type ~ "= writeVariable!" ~ T.stringof ~  ';';
    }
    return result;
}

/**
 * Defines the members of a Stream.
 */
interface Stream
{
    /**
     * Reads from the Stream.
     * Params:
     *      buffer = A pointer to the target.
     *      count = The number of bytes to read.
     * Returns:
     *      The count of bytes that's been read.
     */
    size_t read(Ptr buffer, size_t count);

    /**
     * Reads a typed variable.
     *
     * Typed readers are generated for each type in iz.types.BasicTypes
     * and they are named readInt, readChar, etc.
     *
     * Params:
     *      T = The type of the variable to read.
     *
     * Returns:
     *      A variable of type T. This value can be undefined if the stream
     *      position does not allow to read a T.
     */
    final T readVariable(T)()
    {
        T result;
        read(&result, T.sizeof);
        return result;
    }

    /**
     * Writes the content of a buffer.
     *
     * Params:
     *      buffer = A pointer to the buffer to write.
     *      count = The size of the buffer.
     * Returns:
     *      the count of bytes that's been written.
     */
    size_t write(Ptr buffer, size_t count);

    /**
     * Writes a typed value.
     *
     * Typed writers are generated for each type in iz.types.BasicTypes
     * and they are named writeInt, writeChar, etc.
     *
     * Params:
     *      T = The type of the variable to read.
     *      value = the T to write.
     *
     * Returns:
     *      the count of bytes that's been written (either T.sizeof or 0).
     */
    final size_t writeVariable(T)(T value)
    {
        return write(&value, T.sizeof);
    }

    /**
     * Sets the stream position.
     *
     * Params:
     *      offset = The offset from the start position.
     *      mode = The start position. Either the Stream.position if
     *      $(D mode == SeekMode.skCur), 0 if $(D mode == SeekMode.skBeg) or
     *      Stream.size if $(D mode == SeekMode.skCur).
     * Returns:
     *      the new position.
     */
    long seek(long offset, SeekMode mode);
    /// ditto
    int seek(int offset, SeekMode mode);

    /**
     * Sets or gets the stream size.
     */
    @property long size();
    /// ditto
    @property void size(long value);
    /// ditto
    @property void size(int value);

    /**
     * Sets or gets the stream position.
     */
    @property long position();
    /// ditto
    @property void position(long value);
    /// ditto
    @property void position(int value);

    /**
     * Resets the stream size to 0.
     */
    void clear();

    /// Support for the concatenation operator.
    final void opOpAssign(string op)(Stream rhs)
    {
        static if(op == "~")
        {
            Stream lhs = this;
            auto immutable stored = rhs.position;

            lhs.seek(0, SeekMode.end);
            rhs.seek(0, SeekMode.beg);

            size_t read;
            size_t buff_sz = 4096;
            auto buff = getMem(buff_sz);
            scope(exit)
            {
                rhs.position = stored;
                freeMem(buff);
            }

            while(true)
            {
                read = rhs.read(buff, buff_sz);
                if (read == 0) return;
                lhs.write(buff, read);
            }
        }
        else static assert(0, "Stream.opOpAssign not implemented for " ~ op);
    }

    mixin(genReadWriteVar);
}

/**
 * Helper designed to construct a new StreamRange allocated on the C heap.
 *
 * Params:
 *      ST = The Stream descendant for which the range will be created.
 *      T = The range element type.
 * Returns:
 *      A pointer to a StreamRange that has to be free manually with $(D destruct()).
 */
auto streamRange(T, ST)(ST st)
if (is(ST : Stream))
{
    return construct!(StreamRange!(ST,T))(st);
} 
 
/** 
 * Input, forward and bidirectional range for an Stream.
 *
 * Params:
 *      ST = The Stream descendant for which the range will be created.
 *      T = The range element type.
 */
struct StreamRange(ST, T)
if (is(ST : Stream))
{
    private:
    
        ulong _fpos, _bpos;
        ST _str;
    
    public:
        
        /// initializes a StreamRange with a Stream instance.
        this(ST stream)
        {
            _str = stream;
            _bpos = stream.size - T.sizeof;
        }
        
        /// InputRange primitive.
        @property T front()
        {
            T result;
            _str.position = _fpos;
            _str.read(&result, T.sizeof);
            _str.position = _fpos;
            return result;
        }
        
        /// Bidirectional primitive.
        @property T back()
        {
            T result;
            _str.position = _bpos;
            _str.read(&result, T.sizeof);
            _str.position = _bpos;
            return result;        
        }
        
        /// InputRange primitive.
        @safe void popFront()
        {
            _fpos += T.sizeof;
        }
        
        /// Bidirectional primitive.
        @safe void popBack()
        {
            _bpos -= T.sizeof; 
        }
        
        /// InputRange & BidirectionalRange primitive.
        @property bool empty()
        {
            return (_fpos == _str.size) || (_fpos + T.sizeof > _str.size)
                    || (_bpos == 0) || (_bpos - T.sizeof < 0); 
        }
        
        /// ForwardRange primitive.
        typeof(this) save()
        {
            typeof(this) result = typeof(this)(_str);
            result._fpos = _fpos; 
            result._bpos = _bpos; 
            return result; 
        }
} 

unittest
{
    uint i;
    MemoryStream str = construct!MemoryStream;
    scope(exit) destruct(str);
    
    ushort[] src1 = [0,1,2,3,4,5,6,7,8,9];
    str.write(src1.ptr, src1.length * ushort.sizeof); 
    auto rng1 = construct!(StreamRange!(MemoryStream,ushort))(str);
    scope(exit) destruct(rng1);
    
    // foreach processes a copy of rng.
    // http://forum.dlang.org/thread/jp16ni$fug$1@digitalmars.com
    foreach(ushort v; *rng1)
    {
        assert(v == src1[i]);
        ++i;
    }
    assert(rng1._fpos == 0);
    
    // bidir
    foreach_reverse(ushort v; *rng1)
    {
        --i;
        assert(v == src1[i]);        
    }
    assert(rng1._fpos == 0);    
    
    i = 0;
    while(!rng1.empty)
    {
        assert(rng1.front == src1[i]);
        ++i;
        rng1.popFront;
    }
    assert(rng1.empty);
     
    // other type + streamRange type inference
    str.clear;
    long[] src2 = [10,11,12,13,14,15,16,17,18,19];
    str.write(src2.ptr, src2.length * long.sizeof);
    auto rng2 = streamRange!long(str);
    scope(exit) destruct(rng2);
    foreach(long v; *rng2)
    {
        assert(v == src2[i - 10]);
        ++i;
    }
    
    // test empty with a non full element at the tail
    ubyte tail = 98;
    str.position = str.size;
    str.write(&tail,1);
    auto rng3 = streamRange!long(str);
    scope(exit) destruct(rng3);
    while(!rng3.empty) rng3.popFront;
    str.position = rng3._fpos;
    tail = 0;
    str.read(&tail,1);
    assert(tail == 98);
    
    
    writeln("StreamRange passed the tests (InputRange)");   
}
 

/**
 * Copies the content of a Stream to another one.
 *
 * The position in the source is preserved.
 *
 * Params:
 *      source = The Stream instance whose content will be copied.
 *      target = The Stream instance whose content will be replaced.
 */
void copyStream(Stream source, Stream target)
{
    auto immutable oldpos = source.position; 
    auto buffsz = 4096;
    auto buff = getMem(buffsz);
    if (!buff) throw new OutOfMemoryError();
    
    scope(exit)
    {
        source.position = oldpos;
        freeMem(buff);
    }
    
    source.position = 0;
    target.size = source.size;
    target.position = 0;
    
    while(source.position != source.size)
    {
        auto cnt = source.read(buff, buffsz);
        target.write(buff, cnt);
    }
}

unittest
{
    ubyte[] _a = [0x11,0x22,0x33,0x44];
    ubyte[] _b = [0x55,0x66,0x77,0x88];
    auto a = construct!MemoryStream;
    auto b = construct!MemoryStream;
    a.write(_a.ptr, 4);
    b.write(_b.ptr, 4);
    a ~= b;
    a.position = 0;
    ulong g;
    a.read(&g,8);
    assert(a.size == 8);
    version(LittleEndian) assert(g == 0x8877665544332211);
    version(BigEndian) assert(g == 0x1122334455667788);
    a.destruct;
    b.destruct;
}


/**
 * Writes an input range to a stream.
 *
 * A failure can be verified by testing if the range is empty after the call.
 *
 * Params:
 *      target = A Stream instance.
 *      r = An input range.
 */
void writeRange(R)(Stream target, R r)
if (isInputRange!R)
{
    alias T = ElementType!R;
    size_t c = void;
    T t;
    while (!r.empty)
    {
        t = r.front;
        c = target.write(&t, T.sizeof);
        if (!c) break;
        r.popFront;        
    }
}

unittest
{
    auto rng = iota(0u,100u);
    auto rng1 = rng.save;
    MemoryStream str = construct!MemoryStream;
    scope(exit) str.destruct;
    str.writeRange(rng);
    assert(str.size == 100 * 4);
    auto rng2 = streamRange!uint(str);
    while (!rng2.empty)
    {
        assert(rng2.front == rng1.front);
        rng1.popFront;
        rng2.popFront;
    }
} 


/**
 * Writes an unidimensional array in a stream.
 *
 * By default writes the array length as a ulong and then always the array content.
 * While writeRange() already allows to write an array, there is no clue about
 * its length. Additionally this function is more efficient.
 *
 * Params:
 *      WriteLength = When set to true (the default), the array length is written.
 *      str = The Stream where data are written.
 *      t = The array to write.
 */
void writeArray(bool WriteLength = true, T)(Stream str, auto ref T t)
if (isArray!T && !isMultiDimensionalArray!T)
{
    static if (WriteLength) str.writeUlong(t.length);
    str.write(t.ptr, t.length * typeof(T.init[0]).sizeof);
}

/**
 * Reads an unidimensional array from a stream.
 *
 * By default reads the array length as a ulong and then always the array content.
 * Params:
 *      ReadLength = When set to true (the default), the array length is read.
 *      Otherwise the data are read according to the current array length.
 *      str = The Stream where data are read.
 *      t = The array to write.
 */
void readArray(bool ReadLength = true, T)(Stream str, auto ref T t)
if (isArray!T && !isMultiDimensionalArray!T)
{
    static if (ReadLength)
        t.length = str.readUlong;
    str.read(t.ptr, t.length * typeof(T.init[0]).sizeof);
}

unittest
{
    auto src = "0123456789".dup;
    MemoryStream str = construct!MemoryStream;
    str.writeArray(src);
    assert(str.size == ulong.sizeof + src.length);
    str.position = 0;
    src = "azertyuiop".dup;
    str.readArray(src);
    assert(src == "0123456789");

    str.clear;
    str.writeArray!false(src);
    assert(str.size == src.length);
    str.position = 0;
    src = "az".dup;
    str.readArray!false(src);
    assert(src == "01");

    destruct(str);
}

/**
 * Base Stream for a descendant that uses the operating system API.
 *
 * This class is not directly usable.
 */
class SystemStream: Stream, StreamPersist
{
    private
    {
        StreamHandle _handle;
    }
    public
    {
        /// see the Stream interface.
        size_t read(Ptr buffer, size_t count)
        {
            if (!_handle.isHandleValid) return 0;
            version(Windows)
            {
                uint cnt = cast(uint) count;
                LARGE_INTEGER Li;
                Li.QuadPart = count;
                ReadFile(_handle, buffer, Li.LowPart, &cnt, null);
                return cnt;
            }
            version(Posix)
            {
                return core.sys.posix.unistd.read(_handle, buffer, count);
            }
        }

        /// see the Stream interface.
        size_t write(Ptr buffer, size_t count)
        {
            if (!_handle.isHandleValid) return 0;
            version(Windows)
            {
                uint cnt = cast(uint) count;
                LARGE_INTEGER Li;
                Li.QuadPart = count;
                WriteFile(_handle, buffer, Li.LowPart, &cnt, null);
                return cnt;
            }
            version(Posix)
            {
                return core.sys.posix.unistd.write(_handle, buffer, count);
            }
        }

        /// see the Stream interface.
        long seek(long offset, SeekMode mode)
        {
            if (!_handle.isHandleValid) return 0;
            version(Windows)
            {
                LARGE_INTEGER Li;
                Li.QuadPart = offset;
                Li.LowPart = SetFilePointer(_handle, Li.LowPart, &Li.HighPart, mode);
                return Li.QuadPart;
            }
            version(Posix)
            {
                return core.sys.posix.unistd.lseek64(_handle, offset, mode);
            }
        }

        /// ditto
        int seek(int offset, SeekMode mode)
        {
            return cast(int) seek(cast(long)offset, mode);
        }

        /// see the Stream interface.
        @property long size()
        {
            if (!_handle.isHandleValid) return 0;

            long saved = seek(0, SeekMode.cur);
            long result = seek(0, SeekMode.end);
            seek(saved, SeekMode.beg);

            return result;
        }

        /// ditto
        @property void size(long value)
        {
            if (!_handle.isHandleValid) return;
            if (size == value) return;

            version(Windows)
            {
                LARGE_INTEGER Li;
                Li.QuadPart = value;
                SetFilePointer(_handle, Li.LowPart, &Li.HighPart, FILE_BEGIN);
                SetEndOfFile(_handle);
            }
            version(Posix)
            {
                ftruncate(_handle, value);
            }
        }

        /// ditto
        @property void size(int value)
        {
            if (!_handle.isHandleValid) return;
            version(Windows)
            {
                SetFilePointer(_handle, value, null, FILE_BEGIN);
                SetEndOfFile(_handle);
            }
            version(Posix)
            {
                ftruncate(_handle, value);
            }
        }

        /// see the Stream interface.
        @property long position()
        {
            return seek(0, SeekMode.cur);
        }

        /// ditto
        @property void position(long value)
        {
            immutable long sz = size;
            if (value >  sz) value = sz;
            seek(value, SeekMode.beg);
        }

        /// ditto
        @property void position(int value)
        {
            seek(value, SeekMode.beg);
        }

        /**
         * Exposes the handle for additional system stream operations.
         */
        @property const(StreamHandle) handle(){return _handle;}

        /// see the Stream interface.
        void clear()
        {
            size(0);
            position(0);
        }

        /// see the Stream interface.
        void saveToStream(Stream stream)
        {
            copyStream(this, stream);
        }

        /// see the Stream interface.
        void loadFromStream(Stream stream)
        {
            copyStream(stream, this);
        }
    }
}

/**
 * System stream specialized into reading and writing files, including huge ones
 * (up to 2^64 bytes). Several constructors are avalaible with predefined options. 
 */
class FileStream: SystemStream
{
    private
    {
        string _filename;
    }
    public
    {
        /**
         * Constructs the stream and call openPermissive().
         */
        this(in char[] aFilename, int creationMode = cmAlways)
        {
            openPermissive(aFilename, creationMode);
        }

        /**
         * Constructs the stream and call open().
         */
        this(in char[] aFilename, int access, int share, int creationMode)
        {
            open(aFilename, access, share, creationMode);
        }

        ~this()
        {
            closeFile;
        }

        /**
         * Opens a file for the current user. By default the file is always created or opened.
         */
        bool openStrict(in char[] aFilename, int creationMode = cmAlways)
        {
            version(Windows)
            {
                _handle = CreateFileA(aFilename.toStringz, READ_WRITE, shNone,
                    (SECURITY_ATTRIBUTES*).init, cmToSystem(creationMode),
                    FILE_ATTRIBUTE_NORMAL, HANDLE.init);
            }
            version(Posix)
            {
                _handle = core.sys.posix.fcntl.open(aFilename.toStringz,
                    O_RDWR | cmToSystem(creationMode), shNone);
            }

            if (!_handle.isHandleValid)
            {
                throw new Exception(format("stream exception: cannot create or open '%s'", aFilename));
            }
            _filename = aFilename.dup;
            return _handle.isHandleValid;
        }

        /**
         * Opens a shared file. By default the file is always created or opened.
         */
        bool openPermissive(in char[] aFilename, int creationMode = cmAlways)
        {
            version(Windows)
            {
                _handle = CreateFileA(aFilename.toStringz, READ_WRITE, shAll,
                    (SECURITY_ATTRIBUTES*).init, cmToSystem(creationMode), FILE_ATTRIBUTE_NORMAL, HANDLE.init);
            }
            version(Posix)
            {
                _handle = core.sys.posix.fcntl.open(aFilename.toStringz,
                    O_RDWR | cmToSystem(creationMode), shAll);
            }

            if (!_handle.isHandleValid)
            {
                throw new Exception(format("stream exception: cannot create or open '%s'", aFilename));
            }
            _filename = aFilename.dup;
            return _handle.isHandleValid;
        }

        /**
         * The fully parametric open version. Do not throw. Under POSIX, access can
         * be already OR-ed with other, unrelated flags (e.g: O_NOFOLLOW or O_NONBLOCK).
         */
        bool open(in char[] aFilename, int access, int share, int creationMode)
        {
            version(Windows)
            {
                _handle = CreateFileA(aFilename.toStringz, access, share,
                    (SECURITY_ATTRIBUTES*).init, cmToSystem(creationMode),
                    FILE_ATTRIBUTE_NORMAL, HANDLE.init);
            }
            version(Posix)
            {
                _handle = core.sys.posix.fcntl.open(aFilename.toStringz,
                    access | cmToSystem(creationMode), share);
            }
            _filename = aFilename.dup;
            return _handle.isHandleValid;
        }

        /**
         * Closes the file and flushes any pending changes to the disk.
         * After the call, handle is not valid anymore.
         */
        void closeFile()
        {
            version(Windows)
            {
                if (_handle.isHandleValid) CloseHandle(_handle);
                _handle = INVALID_HANDLE_VALUE;
            }
            version(Posix)
            {
                if (_handle.isHandleValid) core.sys.posix.unistd.close(_handle);
                _handle = -1;
            }
            _filename = "";
        }
        
        /**
         * Exposes the filename.
         */
        @property string filename(){return _filename;}
    }
}

/**
 * Implements a stream of contiguous, GC-free, heap-memory.
 * Its maximal theoretical size is 2^31 bytes (x86) or 2^63 bytes (x86_64).
 * Its practical size limit is damped by the amount of remaining DRAM.
 * This limit is itself reduced by the memory fragmentation.
 *
 * MemoryStream is also enhanced by implementing the interfaces StreamPersist
 * and FilePersist8. They allow to save the content either to another stream or
 * to a file and to load the content either from another Stream or from a file.
 */
class MemoryStream: Stream, StreamPersist, FilePersist8
{
    private
    {
        size_t _size;
        Ptr _memory;
        
        size_t _position;
        string _filename;
        
        struct Ubytes{size_t length; void* ptr;}
        Ubytes fBytes;
        
        void freeNonGc(ref Ptr ptr)
        {
            import core.memory : GC;
            if (!ptr) return;
            if (GC.addrOf(ptr)) return;
            freeMem(ptr);
        }
    }
    public
    {
        ///
        this()
        {
            _memory = getMem(16);
            if (!_memory) throw new OutOfMemoryError();
        }
        
        /**
         * Constructs a MemoryStream and write the input argument.
         * Params:
         * a = either an array, an input range, a variable with a basic type
         * or a stream. Even if the argument is written, the position remains
         * at 0. 
         */
        this(A)(A a)
        {
            _memory = getMem(16);
            if (!_memory) throw new OutOfMemoryError();
            
            import std.traits: isArray;
            static if (isArray!A)
                write(a.ptr, a.length * (ElementType!A).sizeof);
            else static if (isInputRange!A)
                this.writeRange(a);
            else static if (isFixedSize!A)
                write(&a, A.sizeof); 
            else static if (is(A : Stream))
                copyStream(a, this);
            else static assert(0, "unsupported MemoryStream __ctor argument");
                
            position = 0;  
        }
        
        ~this()
        {
            freeNonGc(_memory);
        }
        
// read & write ---------------------------------------------------------------+

        /// see the Stream interface.
        size_t read(Ptr buffer, size_t count)
        {
            if (count + _position > _size) count = _size - _position;
            moveMem(buffer, _memory + _position, count);
            _position += count;
            return count;
        }

        /// see the Stream interface.
        size_t write(Ptr buffer, size_t count)
        {
            if (_position + count > _size) size(_position + count);
            moveMem(_memory + _position, buffer, count);
            _position += count;
            return count;
        }

// -----------------------------------------------------------------------------     
// seek -----------------------------------------------------------------------+

        /// see the Stream interface.
        long seek(long offset, SeekMode mode)
        {
            with(SeekMode) final switch(mode) 
            {
                case beg:
                    _position = cast(typeof(_position)) offset;
                    if (_position > _size) _position = _size;
                    return _position;       
                case cur:
                    _position += offset;
                    if (_position > _size) _position = _size;
                    return _position;   
                case end:
                    return _size;
            }
        }
        
        /// ditto
        int seek(int offset, SeekMode mode)
        {
            long longOffs = offset;
            return cast(int) seek(longOffs, mode);
        }
        
// -----------------------------------------------------------------------------        
// size -----------------------------------------------------------------------+

        /// see the Stream interface.
        @property long size()
        {
            return _size;
        }
        
        /// ditto
        @property void size(int value)
        {
            if (_size == value) return;
            if (value == 0)
            {
                clear;
                return;
            }
            _memory = reallocMem(_memory, value);
            if (!_memory) throw new OutOfMemoryError();
            else _size = value;            
        }
        
        /// ditto
        @property void size(long value)
        {
            static if (size_t.sizeof == 4)
            {
                if (value > 2^^31)
                    throw new Exception("cannot allocate more than 2^31 bytes");
            }
            size(cast(int) value);
        }
        
// -----------------------------------------------------------------------------  
// position -------------------------------------------------------------------+
        
        /// see the Stream interface.
        @property long position()
        {
            return _position;
        }
        
        /// ditto
        @property void position(long value)
        {
            seek(value, SeekMode.beg);
        }
        
        /// ditto
        @property void position(int value)
        {
            seek(value, SeekMode.beg);
        }
        
// -----------------------------------------------------------------------------    
// misc -----------------------------------------------------------------------+

        /// see the Stream interface.
        void clear()
        {
            _memory = reallocMem(_memory, 16);
            if (!_memory) throw new OutOfMemoryError();
            _size = 0;
            _position = 0;
        }

        /**
         * Sets the stream memory to aPtr and assumes it represents a chunk
         * of size aSize. After the call, the stream position is reset to 0.
         * If freeCurrent is true then the current memory is freed.
         * Returns the previous memory, only usefull when freeCurrent is set
         * to false.
         */
        final Ptr setMemory(Ptr aPtr, size_t aSize, bool freeCurrent = true)
        {
            Ptr result = _memory;
            if (!aPtr) return result;
            if (freeCurrent) freeNonGc(_memory);
            _position = 0;
            _size = aSize;
            _memory = aPtr; 
            return result;
        }
        
        /**
         * Read-only access to the memory chunk.
         */
        @property final const(Ptr) memory()
        {
            return _memory;
        }

        /**
         * Returns the stream content as a read-only ubyte array.
         */
        const(ubyte[]) ubytes()
        {
            fBytes.length = _size;
            fBytes.ptr = _memory;
            return * cast(ubyte[] *) &fBytes;
        }
        
// -----------------------------------------------------------------------------     
// StreamPersist --------------------------------------------------------------+
    
        /// see the StreamPersist interface.
        void saveToStream(Stream stream)
        {
            if (cast(MemoryStream) stream)
            {
                auto target = cast(MemoryStream) stream;
                auto immutable oldpos = target.position;
                scope(exit) target.position = oldpos;
                
                position = 0;
                stream.size = size;
                stream.position = 0;
                
                size_t sz = cast(size_t) size;
                size_t buffsz = 8192;
                immutable size_t blocks = sz / buffsz;
                size_t tail = sz - blocks * buffsz;
                
                size_t pos;
                foreach(immutable i; 0 .. blocks)
                {
                    moveMem(target._memory + pos, _memory + pos, buffsz);
                    pos += buffsz;
                }
                if (tail) moveMem(target._memory + pos, _memory + pos, tail);   
            }
            else
            {
                this.copyStream(stream);
            }
        }
        
        /// see the StreamPersist interface.
        void loadFromStream(Stream stream)
        {
            if (auto source = cast(MemoryStream) stream) 
                source.saveToStream(this);
            else
                copyStream(stream, this);
        }
        
// -----------------------------------------------------------------------------
// izFilePersist8 -------------------------------------------------------------+
        
        /// see the izFilePersist8 interface.
        void saveToFile(in char[] aFilename)
        {
            version(Windows)
            {
                auto hdl = CreateFileA( aFilename.toStringz, GENERIC_WRITE, 0,
                    (SECURITY_ATTRIBUTES*).init, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, HANDLE.init);
                
                if (hdl == INVALID_HANDLE_VALUE)
                    throw new Exception(format("stream exception: cannot create or overwrite '%s'", aFilename));
                
                scope(exit) CloseHandle(hdl); 
                uint numRead;
                SetFilePointer(hdl, 0, null, FILE_BEGIN);
                WriteFile(hdl, _memory, cast(uint)_size, &numRead, null);
                
                if (numRead != _size)
                    throw new Exception(format("stream exception: '%s' is corrupted", aFilename));
            }
            version(Posix)
            {
                auto hdl = open( aFilename.toStringz, O_CREAT | O_TRUNC | O_WRONLY, octal!666);
                if (hdl <= -1)
                    throw new Exception(format("stream exception: cannot create or overwrite '%s'", aFilename));

                scope(exit) core.sys.posix.unistd.close(hdl);
                auto immutable numRead = core.sys.posix.unistd.write(hdl, _memory, _size);
                ftruncate64(hdl, _size);

                if (numRead != _size)
                    throw new Exception(format("stream exception: '%s' is corrupted", aFilename));
            }
            _filename = aFilename.idup;
        }
        
        /// see the izFilePersist8 interface.
        void loadFromFile(in char[] aFilename)      
        {
            version(Windows)
            {
                auto hdl = CreateFileA(aFilename.toStringz, GENERIC_READ, 0,
                    (SECURITY_ATTRIBUTES*).init, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, HANDLE.init);
                        
                if (hdl == INVALID_HANDLE_VALUE)
                    throw new Exception(format("stream exception: cannot open '%s'", aFilename));
                    
                uint numRead;
                scope(exit) CloseHandle(hdl);
                size( SetFilePointer(hdl, 0, null, FILE_END));
                SetFilePointer(hdl, 0, null, FILE_BEGIN);
                ReadFile(hdl, _memory, cast(uint)_size, &numRead, null);
                position = 0;
                
                if (numRead != _size)
                    throw new Exception(format("stream exception: '%s' is not correctly loaded", aFilename));
            }
            version(Posix)
            {
                auto hdl = open(aFilename.toStringz, O_CREAT | O_RDONLY, octal!666);

                if (hdl <= -1)
                    throw new Exception(format("stream exception: cannot open '%s'", aFilename));

                scope(exit) core.sys.posix.unistd.close(hdl);
                size(core.sys.posix.unistd.lseek64(hdl, 0, SEEK_END));
                core.sys.posix.unistd.lseek64(hdl, 0, SEEK_SET);
                auto numRead = core.sys.posix.unistd.read(hdl, _memory, _size);
                position = 0;

                if (numRead != _size)
                    throw new Exception(format("stream exception: '%s' is not correctly loaded", aFilename));
            }
            _filename = aFilename.idup;
        }   
        
        /// see the izFilePersist8 interface.
        @property string filename()
        {
            return _filename;
        }
// ---- 
    }
}

unittest
{
    // MemoryStream.setMemory
    Ptr mem = getMem(4096);
    auto str = construct!MemoryStream;
    scope(exit) destruct(str);
    //
    str.size = 128;
    str.position = 128;
    str.setMemory(mem, 4096);
    assert(str.memory == mem);
    assert(str.size == 4096);
    assert(str.position == 0);
    //
    auto arr = [0,1,2,3,4,5,6,7,8,9];
    str.setMemory(arr.ptr, arr.length * arr[0].sizeof, false);
    assert(str.memory == arr.ptr);
    assert(str.size == arr.length * arr[0].sizeof);
    assert(str.position == 0);
    str.position = arr[0].sizeof * 3;
    typeof(arr[0]) value;
    str.read(&value, value.sizeof);
    assert(value == arr[3]);    
}

unittest
{
    // Stream.opOpAssign!("~")
    auto str1 = construct!MemoryStream;
    auto str2 = construct!MemoryStream;
    scope(exit) destruct(str1, str2);
    //
    auto dat1 = "1234";
    auto dat2 = "5678";
    str1.write(cast(void*) dat1.ptr, dat1.length);
    str2.write(cast(void*) dat2.ptr, dat2.length);
    str2.position = 0;
    str1 ~= str2;
    assert(str2.position == 0);
    assert(str1.size == dat1.length + dat2.length); 
    auto dat3 = new char[](8);
    str1.position = 0;
    str1.read(cast(void*) dat3.ptr, dat3.length);
    assert(dat3 == "12345678");     
}

unittest
{
    /*auto sz = 0x1_FFFF_FFFFUL;
    auto huge = construct!FileStream("huge.bin");
    scope(exit)
    {
        huge.destruct;
        std.stdio.remove("huge.bin");
    }
    huge.size = sz;
    huge.position = 0;
    assert(huge.size == sz);*/
}

unittest
{
    import std.digest.md: md5Of;

    void test(T, A...)(A a)
    {
        uint len = 25_000;
        auto str = construct!T(a);
        scope (exit)  str.destruct;
        for (int i = 0; i < len; i++)
        {
            str.write(&i, i.sizeof);
            assert(str.position == (i + 1) * i.sizeof);
        }
        str.position = 0;
        assert(str.size == len * 4);
        while(str.position < str.size)
        {
            int g;
            auto c = str.read(&g, g.sizeof);
            assert(g == (str.position - 1) / g.sizeof );
        }
        str.clear;
        assert(str.size == 0);
        assert(str.position == 0);
        for (int i = 0; i < len; i++)
        {
            str.write(&i, i.sizeof);
            assert(str.position == (i + 1) * i.sizeof);
        }
        str.position = 0;

        static if (is(T == FileStream))
        {
            auto strcpy = construct!T("filestream2.txt");
        }
        else auto strcpy = construct!T(A);
        scope (exit) strcpy.destruct;
        strcpy.size = 100_000;
        assert(str.size == len * 4);
        strcpy.loadFromStream(str);
        assert(str.size == len * 4);
        assert(strcpy.size == str.size);
        strcpy.position = 0;
        str.position = 0;
        for (int i = 0; i < len; i++)
        {
            auto r0 = str.readInt;
            auto r1 = strcpy.readInt;
            assert(r0 == r1);
        }
        strcpy.position = 0;
        str.position = 0;
        assert(strcpy.size == len * 4);

        str.write("truncate the data".dup.ptr, 17);
        str.position = 0;
        strcpy.position = 0;
        ubyte[] food0, food1;
        food0.length = cast(size_t) str.size;
        food1.length = cast(size_t) strcpy.size;
        str.read(food0.ptr, food0.length);
        strcpy.read(food1.ptr,food1.length);
        ubyte[16] md5_0 = md5Of(food0);
        ubyte[16] md5_1 = md5Of(food1);
        assert(md5_0 != md5_1);

        static if (is(T == MemoryStream))
        {
            str.saveToFile("memstream.txt");
            str.clear;
            str.loadFromFile("memstream.txt");
            assert(str.size == strcpy.size);
            std.stdio.remove("memstream.txt");
        }

        str.position = 0;
        strcpy.position = 0;
        strcpy.saveToStream(str);
        str.position = 0;
        strcpy.position = 0;
        food0.length = cast(size_t) str.size;
        food1.length = cast(size_t) strcpy.size;
        str.read(food0.ptr,food0.length);
        strcpy.read(food1.ptr,food1.length);
        md5_0 = md5Of(food0);
        md5_1 = md5Of(food1);
        assert(md5_0 == md5_1);

        static if (is(T == MemoryStream))
        {
          str.clear;
          for(ubyte i = 0; i < 100; i++) str.write(&i, 1);
          for(ubyte i = 0; i < 100; i++) assert( str.ubytes[i] == i );
        }

        static if (is(T == FileStream))
        {
            str.closeFile;
            strcpy.closeFile;
            std.stdio.remove("filestream1.txt");
            std.stdio.remove("filestream2.txt");
        }

        writeln( T.stringof ~ " passed the tests");
    }
    test!MemoryStream;
    test!FileStream("filestream1.txt");
}

unittest
{
    // test ctor with input range
    import std.conv;
    uint a;
    int[2] b = [1,2];
    auto s1 = new MemoryStream(a);
    assert(s1.size == a.sizeof);
    auto s2 = new MemoryStream(b);
    assert(s2.size == b.sizeof);
    auto s3 = new MemoryStream(iota(0,2));
    auto s4 = new MemoryStream(s3);
}

