iz
==

Introduction
------------
_iz_ is a general purpose library for the D programming language.
It includes [streams, containers, serialization, property binder](http://bbasile.github.io/iz/) and more.

Incompatibility with `destroy()`
--------------------------------

This library experiments manually managed classes lifetime.
Most of the classes declared in _iz_ are not compatible with `new` and `destroy`, instead `construct` and `destruct` must be used.

- `destroy` calls the destructors from the most derived to the base using the dynamic type information of each generation and without considering the static type of the argument (which may be correct).
- `destructs` calls the destructor defined for the static type of the argument unless it is passed after a cast to `Object`. Even in this case, only the most derived destructor gets looked-up using the type information. Once found, the other destructors are called by inheritance (i.e like what does `super()` to constructors).

As a consequence, `destroy` or the GC will segfault if _iz_ classes that do not inherit from `Object` are not accurately handled with `construct` and `destruct`.

Setup
-----

- using [Coedit](https://github.com/BBasile/Coedit): open the file _iz.coedit_ in the _project_ menu, item _open_.
- using DUB, description is included.
- using shell scripts, see the _scripts_ folder.

Info
----
- [![CI Status](https://travis-ci.org/BBasile/iz.svg)](https://travis-ci.org/BBasile/iz)
- warning, unstable API, subject to heavy design changes.
- MIT licensed.
