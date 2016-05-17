@echo off
echo compiling lib...
dmd^
 "..\import\iz\memory.d"^
 "..\import\iz\types.d"^
 "..\import\iz\logicver.d"^
 "..\import\iz\math.d"^
 "..\import\iz\classes.d"^
 "..\import\iz\enumset.d"^
 "..\import\iz\observer.d"^
 "..\import\iz\streams.d"^
 "..\import\iz\containers.d"^
 "..\import\iz\properties.d"^
 "..\import\iz\referencable.d"^
 "..\import\iz\rtti.d"^
 "..\import\iz\serializer.d"^
 "..\import\iz\strings.d"^
 "..\import\iz\sugar.d"^
 -lib -O -release -inline -boundscheck=off -of"..\lib\iz.lib" -I"..\import"
echo ...lib compiled
@echo on
pause
