#!/bin/bash

echo ---------------------------------------
echo compiling library...
dmd -main -unittest -debug -w -wi "../import/iz/memory.d" "../import/iz/types.d" "../import/iz/logicver.d" "../import/iz/classes.d" "../import/iz/enumset.d" "../import/iz/observer.d" "../import/iz/streams.d" "../import/iz/containers.d" "../import/iz/properties.d" "../import/iz/referencable.d" "../import/iz/strings.d" "../import/iz/serializer.d" "../import/iz/sugar.d" "../import/iz/math.d" -of"iz-tester" -I"../import"
echo ---------------------------------------
./iz-tester
echo ---------------------------------------
rm ./iz-tester.o
rm ./iz-tester
