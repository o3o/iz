## iz

### Introduction

_iz_ is a general purpose library for the D programming language.
It includes [streams, containers, serialization, property binder](http://bbasile.github.io/iz/) and more.

### Runtime incompatibilities

#### (_dont_) Destroy

This library experiments manually managed classes lifetime.
Most of the classes declared in _iz_ are not compatible with `new` and `destroy`, instead `construct` and `destruct` must be used.

- `destroy` calls the destructors from the most derived to the base using the dynamic type information of each generation and without considering the static type of the argument (which may be correct).
- `destruct` calls the destructor defined for the static type of the argument unless it is passed after a cast to `Object`. Even in this case, only the most derived destructor gets looked-up using the type information. Once found, the other destructors are called by inheritance (i.e like what does `super()` to constructors). Destructor inhertance, since not built into the language, is provided with a mixin template.

As a consequence, `destroy` or the GC will segfault, due to a double call to the destructors, if _iz_ classes that do not directly inherit from `Object` (i.e empty inheritance list) are not accurately handled with `construct` and `destruct`.

#### D arrays

Still because of manual memory management, D arrays (e.g `int[] a;`) are not really usable in _iz_.

A D arrays consists of two members. One of them is a pointer that's managed by the garbage collector.
Since the arrays parents, classes or structs, are not known by the GC, during any collection the GC thinks that a D array is an orphan and frees the chunk pointed by the pointer.
By default this library uses an unmanaged array.
In order to use default D arrays two workarounds exist:
- call GC.disable at the beginning of the program.
- use `std.experimental.allocator` functions `makeArray`, `shrinkArray` and `expandArray` with `Mallocator.instance`.

Also any container based on custom allocators will be compatible with _iz_ class system.

### Setup

- using [Coedit](https://github.com/BBasile/Coedit): open the file _iz.coedit_ in the _project_ menu, item _open_.
- using DUB, description is included.
- using shell scripts, see the _scripts_ folder.

### Other
----
- [![CI Status](https://travis-ci.org/BBasile/iz.svg)](https://travis-ci.org/BBasile/iz)
- warning, unstable API, subject to heavy design changes.
- Boost software license 1.0
