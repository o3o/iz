module valgrinder;

import
    std.stdio, std.path, std.file, std.algorithm, std.range, std.array;
import
    iz.classes;

int main(string[] args)
{
    chdir(__FILE_FULL_PATH__.dirName);
    size_t failedCount;
    foreach(de; dirEntries("/home/basile/Dev/dproj/iz/tests/leaks/", "*.d",
        SpanMode.depth))
            failedCount += !de.name.test();
    return failedCount != 0;
}

size_t test(string filename)
{
    string target = __FILE_FULL_PATH__.dirName ~ "/" ~ filename.baseName.stripExtension;
    bool result;

    try
    {
        // compiles the test
        Process dmd = new Process;
        dmd.executable = "dmd";
        dmd.parameters = filename ~ " ../lib/iz.a " ~ "-I../import/";
        dmd.execute;

        if (dmd.exitStatus != 0)
            return false;

        // run trough valgrind
        Process valgrind = new Process;
        valgrind.executable = "valgrind";
        valgrind.parameters = "--leak-check=yes " ~ target;
        valgrind.usePipes = true;
        valgrind.errorToOutput = true;
        valgrind.execute;

        string[] lines = valgrind.output.byLineCopy.array;

        // https://github.com/dlang/druntime/pull/1557
        result = !lines.dup.filter!
        (
            a => a.canFind("definitely lost: 88 bytes") ||
                 a.canFind("definitely lost: 0 bytes")
        ).empty;

        if (!result)
        {
            stderr.writeln("leak detected in ", filename);
            lines.each!writeln;
        }
    }
    catch(Exception e)
    {
        return false;
    }

    return result;
}

