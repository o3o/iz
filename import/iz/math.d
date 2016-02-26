module iz.math;

import
    std.traits;

/**
 * Saves the rounding mode used in iz.math (MXCSR).
 *
 * Returns:
 *      The current rounding mode, as a read-only integer value.
 */
const(int) saveIzRoundingMode()
{
    int v;
    asm
    {
        stmxcsr v;
    }
    return v;
}

/**
 * Restores the rounding mode used in iz.math (MXCSR).
 *
 * iz.math provides the functions to set all the possible modes and this function
 * should only be used to restore a value saved by the roundToXXX functions.
 * When used freely, this function will only work when the 13th and the 14th bit
 * modify the current MXCSR register.
 */
void setIzRoundingMode(int value)
{
    int curr;
    asm
    {
        stmxcsr curr;
    }
    import iz.sugar: maskBit;
    curr = maskBit!13(curr);
    curr = maskBit!14(curr);
    curr |= value;
    asm
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
const(int) roundToNearest()
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
const(int) roundToPositive()
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
const(int) roundToNegative()
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
const(int) roundToZero()
{
    int result = saveIzRoundingMode;
    int newMode = result;
    newMode |= 1 << 13;
    newMode |= 1 << 14;
    setIzRoundingMode(newMode);
    return result;
}


unittest
{
    auto sav = roundToNearest;
    assert(round(0.4) == 0);
    roundToZero;
    assert(round(0.8) == 0);
    assert(round(-0.8) == 0);
    roundToNegative;
    assert(round(1.8) == 1);
    assert(round(-0.8) == -1);
    roundToPositive;
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
extern(C) int round(T)(T value)
{
    version(X86_64)
    {
        static if (is(T==float)) asm
        {
            naked;
            cvtss2si EAX, XMM0;
            ret;
        }
        else static if (is(T==double)) asm
        {
            naked;
            cvtsd2si EAX, XMM0;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else version(X86)
    {
        static if (is(T==float)) asm
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movlps XMM0, value;
            cvtss2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static if (is(T==double)) asm
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movlps XMM0, value;
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
unittest
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
int floor(T)(T value)
if (isFloatingPoint!T)
{
    const T offs = -0.5;
    return round(value + offs);
}
///
unittest
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
int ceil(T)(T value)
if (isFloatingPoint!T)
{
    const T offs = 0.5;
    return round(value + offs);
}
///
unittest
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
 *      An integral value equal to the integral part of $(D_PARAM value).
 */
extern(C) int trunc(T)(T value)
{
    version(X86_64)
    {
        static if (is(T==float)) asm
        {
            naked;
            cvttss2si EAX, XMM0;
            ret;
        }
        else static if (is(T==double)) asm
        {
            naked;
            cvttsd2si EAX, XMM0;
            ret;
        }
        else static assert(0, "unsupported FP type");
    }
    else version(X86)
    {
        static if (is(T==float)) asm
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movlps XMM0, value;
            cvttss2si EAX, XMM0;
            mov ESP, EBP;
            pop EBP;
            ret;
        }
        else static if (is(T==double)) asm
        {
            naked;
            push EBP;
            mov EBP, ESP;
            movlps XMM0, value;
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
unittest
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
 *      An integral value equal to the integral part of $(D_PARAM value).
 */
int dtrunc(T)(T value)
{
    static if (is(T==float) || is(T==double))
        return cast(int) value;
    else
        static assert(0, "unsupported FP type");
}
///
unittest
{
    assert(dtrunc(0.2f) == 0);
    assert(dtrunc(0.8f) == 0);
    assert(dtrunc(-0.2f) == 0);
    assert(dtrunc(-8.8f) == -8);
}
