/**
 * Several simple math functions.
 *
 * They are rather dedicated to the X86_64 architecture but implemented for
 * X86 too, even if parameters loading is less adequate and slower under this
 * architecture.
 */
module iz.math;

import
    std.traits, std.complex;

/**
 * When the conditional version identifer "ensure_sseRoundingMode" is
 * set then the current rounding mode is reset to the default value.
 */
version(ensure_sseRoundingMode) static this()
{
    roundToNearest;
}

/**
 * Saves the rounding mode used in iz.math
 * (always the 13th and 14th bit of SSE MXCSR).
 *
 * Returns:
 *      The current rounding mode, as a read-only integer value.
 */
const(int) saveIzRoundingMode() @trusted pure nothrow
{
    version(X86) asm pure nothrow
    {
        naked;
        sub     ESP, 4;
        stmxcsr dword ptr [ESP-4];
        mov     EAX, dword ptr [ESP-4];
        add     ESP, 4;
        ret;
    }
    else version(X86_64) asm pure nothrow
    {
        naked;
        sub     RSP, 4;
        stmxcsr dword ptr [RSP-4];
        mov     EAX, dword ptr [RSP-4];
        add     RSP, 4;
        ret;
    }
    else static assert(0, "unsupported architecture");
}

/**
 * Restores the rounding mode used in iz.math (MXCSR).
 *
 * iz.math provides the functions to set all the possible modes and this function
 * should only be used to restore a value saved by the roundToXXX functions.
 * When used freely, this function will only work when the 13th and the 14th bit
 * modify the current MXCSR register.
 */
void setIzRoundingMode(int value) @trusted pure nothrow
{
    int curr;
    asm pure nothrow
    {
        stmxcsr curr;
    }
    import iz.sugar: maskBit;
    curr = maskBit!13(curr);
    curr = maskBit!14(curr);
    curr |= value;
    asm pure nothrow
    {
        ldmxcsr curr;
    }
}

/**
 * Resets the default rounding mode.
 *
 * After the call, floor() and ceil() are conform to the specifications.
 *
 * Returns:
 *   The previous rounding mode, which can be restored with setIzRoundingMode().
 */
const(int) roundToNearest() @trusted pure nothrow
{
    int result = saveIzRoundingMode;
    import iz.sugar: maskBit;
    int newMode = result;
    newMode = maskBit!13(newMode);
    newMode = maskBit!14(newMode);
    setIzRoundingMode(newMode);
    return result;
}

/**
 * Sets round() to behave like floor().
 *
 * After the call, floor() and ceil() are not anymore reliable.
 *
 * Returns:
 *   The previous rounding mode, which can be restored with setIzRoundingMode().
 */
const(int) roundToPositive() @trusted pure nothrow
{
    int result = saveIzRoundingMode;
    import iz.sugar: maskBit;
    int newMode = result;
    newMode = maskBit!13(newMode);
    newMode |= 1 << 14;
    setIzRoundingMode(newMode);
    return result;
}

/**
 * Sets round() to behave like ceil().
 *
 * After the call, floor() and ceil() are not anymore reliable.
 *
 * Returns:
 *   The previous rounding mode, which can be restored with setIzRoundingMode().
 */
const(int) roundToNegative() @trusted pure nothrow
{
    int result = saveIzRoundingMode;
    import iz.sugar: maskBit;
    int newMode = result;
    newMode = maskBit!14(newMode);
    newMode |= 1 << 13;
    setIzRoundingMode(newMode);
    return result;
}

/**
 * Sets round() to behave like trunc().
 *
 * After the call, floor() and ceil() are not anymore reliable.
 *
 * Returns:
 *      The previous rounding mode, which can be restored with setIzRoundingMode().
 */
const(int) roundToZero() @trusted pure nothrow
{
    int result = saveIzRoundingMode;
    int newMode = result;
    newMode |= 1 << 13;
    newMode |= 1 << 14;
    setIzRoundingMode(newMode);
    return result;
}
///
@safe pure nothrow unittest
{
    auto sav = roundToNearest;
    assert(round(0.4) == 0);
    auto dnc0 = roundToZero;
    assert(round(0.8) == 0);
    assert(round(-0.8) == 0);
    auto dnc1 = roundToNegative;
    assert(round(1.8) == 1);
    assert(round(-0.8) == -1);
    auto dnc2 = roundToPositive;
    assert(round(1.8) == 2);
    assert(round(-0.8) == 0);
    setIzRoundingMode(sav);
}

/**
 * Converts a floating point value to an integer.
 *
 * This function requires the SSE2 instruction set and it can't be inlined.
 *
 * Params:
 *      value = Either a float or a double.
 *
 * Returns:
 *      An integer equal to the nearest integral value.
 */
extern(C) int round(T)(T value) @trusted pure nothrow
{
    version(X86_64)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            cvtss2si EAX, XMM0;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            cvtsd2si EAX, XMM0;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else version(X86)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movss XMM0, value;
            cvtss2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movsd XMM0, value;
            cvtsd2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static assert(0, "unsupported FP type");          
    }
    else static assert(0, "unsupported architecture");
}
///
@safe pure nothrow unittest
{
    assert(round(0.2f) == 0);
    assert(round(0.8f) == 1);
    assert(round(-0.2f) == 0);
    assert(round(-0.8f) == -1);
}

/**
 * Converts a floating point value to an integer.
 *
 * This function requires the SSE2 instruction set and it can't be inlined.
 *
 * Params:
 *      value = Either a float or a double.
 *
 * Returns:
 *      The largest integral value that is not greater than $(D_PARAM value).
 */
int floor(T)(T value) @trusted pure nothrow
if (isFloatingPoint!T)
{
    const T offs = -0.5;
    return round(value + offs);
}
///
@safe pure nothrow unittest
{
    assert(floor(0.2f) == 0);
    assert(floor(0.8f) == 0);
    assert(floor(-0.2f) == -1);
    assert(floor(-0.8f) == -1);
}

/**
 * Converts a floating point value to an integer.
 *
 * This function requires the SSE2 instruction set and it can't be inlined.
 *
 * Params:
 *      value = Either a float or a double.
 *
 * Returns:
 *      The smallest integral value that is not less than $(D_PARAM value).
 */
int ceil(T)(T value) @trusted pure nothrow
if (isFloatingPoint!T)
{
    const T offs = 0.5;
    return round(value + offs);
}
///
@safe pure nothrow unittest
{
    assert(ceil(0.2f) == 1);
    assert(ceil(0.8f) == 1);
    assert(ceil(-0.2f) == 0);
    assert(ceil(-0.8f) == 0);
}

/**
 * Converts a floating point value to an integer.
 *
 * This function requires the SSE2 instruction set and it can't be inlined.
 *
 * Params:
 *      value = Either a float or a double.
 *
 * Returns:
 *       An integral value equal to the $(D_PARAM value) nearest integral toward 0.
 */
extern(C) int trunc(T)(T value) @trusted pure nothrow
{
    version(X86_64)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            cvttss2si EAX, XMM0;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            cvttsd2si EAX, XMM0;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else version(X86)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movss XMM0, value;
            cvttss2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movsd XMM0, value;
            cvttsd2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static assert(0, "unsupported FP type");          
    }
    else static assert(0, "unsupported architecture");
}
///
@safe pure nothrow unittest
{
    assert(trunc(0.2f) == 0);
    assert(trunc(0.8f) == 0);
    assert(trunc(-0.2f) == 0);
    assert(trunc(-8.8f) == -8);
}

/**
 * Converts a floating point value to an integer.
 *
 * This function relies on the D behavior when casting a floating point value
 * to an integer. It uses SSE2 on X86_64 and the FPU on X86 but it can always be 
 * inlined.
 *
 * Params:
 *      value = Either a float or a double.
 *
 * Returns:
 *      An integral value equal to the $(D_PARAM value) nearest integral toward 0.
 */
int dtrunc(T)(T value) @trusted pure nothrow
{
    static if (is(T==float) || is(T==double))
        return cast(int) value;
    else
        static assert(0, "unsupported FP type");
}
///
@safe pure nothrow unittest
{
    assert(dtrunc(0.2f) == 0);
    assert(dtrunc(0.8f) == 0);
    assert(dtrunc(-0.2f) == 0);
    assert(dtrunc(-8.8f) == -8);
}

/**
 * Computes the hypothenus of two FP numbers.
 *
 * This function requires the SSE2 instruction set and it can't be inlined.
 *
 * Params:
 *      x = Either a float or a double.
 *      y = Either a float or a double.
 *
 * Returns:
 *      A floating point value of type T.
 */
extern(C) T hypot(T)(T x, T y) pure @trusted nothrow
{
    version(X86_64)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            mulps   XMM0, XMM0;
            mulps   XMM1, XMM1;
            addps   XMM0, XMM1;
            sqrtps  XMM0, XMM0;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            mulpd   XMM0, XMM0;
            mulpd   XMM1, XMM1;
            addpd   XMM0, XMM1;
            sqrtpd  XMM0, XMM0;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else version(X86)
    {
        static if (is(T==float)) asm pure nothrow
        {
            naked;
            push    EBP;
            mov     EBP, ESP;
            sub     ESP, 4;
            movss   XMM0, x;
            movss   XMM1, y;
            mulps   XMM0, XMM0;
            mulps   XMM1, XMM1;
            addps   XMM0, XMM1;
            sqrtps  XMM0, XMM0;
            movss   dword ptr [ESP-4], XMM0;
            fld     dword ptr [ESP-4];
            add     ESP, 4;
            mov     ESP, EBP;
            pop     EBP;
            ret;
        }
        else static if (is(T==double)) asm pure nothrow
        {
            naked;
            push    EBP;
            mov     EBP, ESP;
            sub     ESP, 8;
            movsd   XMM0, x;
            movsd   XMM1, y;
            mulpd   XMM0, XMM0;
            mulpd   XMM1, XMM1;
            addpd   XMM0, XMM1;
            sqrtpd  XMM0, XMM0;
            movsd   qword ptr [ESP-8], XMM0;
            fld     qword ptr [ESP-8];
            add     ESP, 8;
            mov     ESP, EBP;
            pop     EBP;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else static assert(0, "unsupported architecture");
}
///
pure @safe nothrow unittest
{
    assert(hypot(3.0,4.0) == 5.0);
    assert(hypot(3.0f,4.0f) == 5.0f);
}

/**
 * Returns the magnitude of a complex number.
 *
 * Convenience function that calls hypot() either with a clfloat, a cdouble or
 * a std.complex.Complex.
 */
auto magn(T)(T t) pure @trusted nothrow
if (is(T==cfloat) || is(T==cdouble) || is(T==Complex!float) || is(T==Complex!double))
{
    return hypot(t.re, t.im);
}
///
nothrow pure @safe unittest
{
    assert(magn(cdouble(3.0+4.0i)) == 5.0);
    assert(magn(cfloat(3.0f+4.0fi)) == 5.0f);
    assert(magn(complex(3.0f,4.0f)) == 5.0f);
    assert(magn(complex(3.0,4.0)) == 5.0);
}

