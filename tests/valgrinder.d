module valgrinder;

import
    std.stdio, std.path, std.file, std.algorithm, std.range, std.array;
import
    iz.memory, iz.classes;

immutable string rootDir;

static this()
{
    rootDir = __FILE_FULL_PATH__.dirName;
}

int main(string[] args)
{
    chdir(rootDir);
    size_t failedCount;
    // tests dedicated  to leaks
    foreach(de; dirEntries(rootDir ~ "/leaks/", "*.d", SpanMode.depth))
        failedCount += !de.name.test!false();
    // common libraries unittests
    foreach(de; dirEntries(rootDir ~ "/../import/iz/", "*.d", SpanMode.depth))
        failedCount += !de.name.test!true();
    return failedCount != 0;
}

bool test(bool ut)(string filename)
{
    string target = rootDir ~ "/" ~ filename.baseName.stripExtension;
    bool result;

    try
    {
        // compiles the test
        Process dmd = construct!Process;
        scope(exit) destruct(dmd);
        dmd.executable = "dmd";
        static if (!ut)
            dmd.parameters = filename ~ " ../lib/iz.a" ~ " -I../import/";
        else
            dmd.parameters = filename ~ " ../lib/iz.a" ~ " -I../import/" ~
                " -unittest -main -version=checkleaks";
        dmd.execute;

        if (dmd.exitStatus != 0)
            throw new Exception("failed to compile " ~ filename);

        // run through valgrind
        Process valgrind = construct!Process;
        scope(exit) destruct(valgrind);
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
        stderr.writeln(e.msg);
        return false;
    }

    return result;
}

