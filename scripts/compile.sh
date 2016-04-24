echo compiling lib...
dmd -lib -O -release -inline -noboundscheck "../import/iz/memory.d" "../import/iz/types.d" "../import/iz/logicver.d" "../import/iz/classes.d" "../import/iz/enumset.d" "../import/iz/observer.d" "../import/iz/streams.d" "../import/iz/containers.d" "../import/iz/properties.d" "../import/iz/strings.d" "../import/iz/referencable.d" "../import/iz/serializer.d" "../import/iz/sugar.d" "../import/iz/math.d" -of"../lib/iz.a" -I"../import"
echo ...lib compiled
read
