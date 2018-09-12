ABICC 2.3
=========

ABI Compliance Checker (ABICC) — a tool for checking backward binary and source-level compatibility of a C/C++ software library.

Contents
--------

1. [ About      ](#about)
2. [ Install    ](#install)
3. [ Usage      ](#usage)
4. [ Test suite ](#test-suite)

About
-----

The tool analyzes changes in API/ABI (ABI=API+compiler ABI) that may break binary compatibility and/or source compatibility: changes in calling stack, v-table changes, removed symbols, renamed fields, etc.

The tool can create and compare ABI dumps for header files and shared objects of a library. The ABI dump for a library can also be created by the ABI Dumper tool (https://github.com/lvc/abi-dumper) if shared objects include debug-info.

The tool is intended for developers of software libraries and Linux maintainers who are interested in ensuring backward compatibility, i.e. allow old applications to run or to be recompiled with newer library versions.

The tool is a core of the ABI Tracker and Upstream Tracker projects: https://abi-laboratory.pro/tracker/

The tool is developed by Andrey Ponomarenko.

Install
-------

    sudo make install prefix=/usr

###### Requires

* Perl 5
* GCC C++ (3.0 or newer)
* GNU Binutils
* Ctags
* ABI Dumper (1.1 or newer)

###### Platforms

* Linux
* Mac OS X
* Windows

Usage
-----

###### With ABI Dumper

1. Library should be compiled with `-g -Og` GCC options to contain DWARF debug info

2. Create ABI dumps for both library versions using the ABI Dumper (https://github.com/lvc/abi-dumper) tool:

        abi-dumper OLD.so -o ABI-1.dump -lver 1
        abi-dumper NEW.so -o ABI-2.dump -lver 2

3. You can filter public ABI with the help of additional `-public-headers` option of the ABI Dumper tool

4. Compare ABI dumps to create report:

        abi-compliance-checker -l NAME -old ABI-1.dump -new ABI-2.dump

###### Compile headers

    abi-compliance-checker -lib NAME -old OLD.xml -new NEW.xml

`OLD.xml` and `NEW.xml` are XML-descriptors:

    <version>
        1.0
    </version>

    <headers>
        /path/to/headers/
    </headers>

    <libs>
        /path/to/libraries/
    </libs>

###### Adv. usage

For advanced usage, see `doc/index.html` or output of `-help` option.

Test suite
----------

The tool is tested properly in the ABI Tracker and Upstream Tracker projects, by the community and by the internal test suite:

    abi-compliance-checker -test

There are about 100 test cases for C and 200 test cases for C++ API/ABI breaks.
