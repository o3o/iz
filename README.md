## iz

### Introduction

_iz_ is a general purpose library for the D programming language.
It includes [streams, containers, a serializer, property binder, Pascal-like sets, Pascal-like properties](http://bbasile.github.io/iz/) and more.

### Runtime incompatibilities

#### (_dont_) Destroy

This library experiments manually managed classes lifetime.
Most of the classes declared in _iz_ are not compatible with `new` and `destroy`, instead [`construct`](http://bbasile.github.io/iz/iz/memory.html#construct) and [`destruct`](http://bbasile.github.io/iz/iz/memory.html#destruct) must be used.

- `destroy` calls the destructors from the most derived to the base using the dynamic type information of each generation and without considering the static type of the argument (which may be correct).
- `destruct` calls the destructor defined for the static type of the argument unless it is passed after a cast to `Object`. Even in this case, only the most derived destructor gets looked-up using the type information. Once found, the other destructors are called by inheritance (i.e like what does `super()` to constructors). This system, since not built into the language, is provided with a [mixin template](http://bbasile.github.io/iz/iz/memory/inheritedDtor.html).

As a consequence, `destroy` or the GC will segfault, due to a double call to the destructors, if _iz_ classes that do not directly inherit from `Object` (i.e non-empty inheritance list) are not accurately handled with `construct` and `destruct`.

#### D arrays

Still because of manual memory management, D arrays (e.g `int[] a;`) are not really usable in _iz_ classes.

A D arrays consists of two members. One of them is a pointer that's managed by the garbage collector.
Since the arrays parents, classes or structs, are not known by the GC, during any collection the GC thinks that a D array is orphan and it frees the chunk pointed by the pointer.
By default this library uses [GC-free arrays](http://bbasile.github.io/iz/iz/containers/Array.html) in its classes and other aggregates.
Any container based on custom allocators will also be compatible with _iz_ class system.

In order to use default D arrays two workarounds exist:
- call `GC.disable` at the beginning of the program.
- use `std.experimental.allocator` functions `makeArray()`, `shrinkArray()` and `expandArray()` with `Mallocator.instance` and never `.length` and `Appender`. Uses local copies in order to work safely with Phobos algorithms.

Note that D arrays are not affected when used as local variables. This is even a case where the GC is useful. 
The lifetime of the aggregates is often known and deterministic so the associated memory can then be considered as polluting the GC heap.

### Build and setup

- using [Coedit](https://github.com/BBasile/Coedit): open the file _iz.coedit_ in the _project_ menu, item _open_, compile, install in the libman.
- using DUB, `dub build --build=release`.
- using shell scripts, see the _scripts_ folder.

### Other

- [![CI Status](https://travis-ci.org/BBasile/iz.svg)](https://travis-ci.org/BBasile/iz)
- warning, unstable API, subject to heavy design changes.
- Boost Software License 1.0
