@echo off
echo ---------------------------------------
echo compiling library...
dmd ..\tests\unittester.d^
 "../import/iz/testing.d"^
 "../import/iz/memory.d"^
 "../import/iz/types.d"^
 "../import/iz/logicver.d"^
 "../import/iz/classes.d"^
 "../import/iz/enumset.d"^
 "../import/iz/observer.d"^
 "../import/iz/streams.d"^
 "../import/iz/containers.d"^
 "../import/iz/properties.d"^
 "../import/iz/referencable.d"^
 "../import/iz/rtti.d"^
 "../import/iz/strings.d"^
 "../import/iz/serializer.d"^
 "../import/iz/sugar.d"^
 "../import/iz/math.d"^
 -unittest -debug -w -wi -of"iz-tester.exe" -I"../import"
echo ---------------------------------------
iz-tester.exe
echo ---------------------------------------
rm ./iz-tester.obj
rm ./iz-tester.exe
echo on
pause
