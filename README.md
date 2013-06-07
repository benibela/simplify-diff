Simplify diff
=============

Little tool to simplify unified diffs, e.g. to remove lines only containing whitespace changes 

Installation
-------------

My homepages provides standalone [simplify diff binaries](http://www.benibela.de/tools_en.html#simplifydiff) for Windows and Linux.

If you want to compile it, you need Lazarus and my rcmdline unit. Then just open simplifydiff.lpi in Lazarus and  click compile.

 

Usage
------------

It is a commandline program, so you can simply call it with:

    simplifydiff < broken.diff > improved.diff
   
   
`simplifydiff --help` prints more advanced option.



Example
-------------

A too verbose diff like:

    Index: smallUsefulFunctions.cpp
    ===================================================================
    --- smallUsefulFunctions.cpp    (revision 113)
    +++ smallUsefulFunctions.cpp    (working copy)
    @@ -1,6 +1,6 @@
     abc
    -old
    -equal
    -more equal
    -even more equal
    -even even more equal
    +new
    +equal
    +more equal
    +even more equal
    +even even more equal

is simplified to

    Index: smallUsefulFunctions.cpp
    ===================================================================
    --- smallUsefulFunctions.cpp    (revision 113)
    +++ smallUsefulFunctions.cpp    (working copy)
    @@ -1,5 +1,5 @@
     abc
    -old
    +new
     equal
     more equal
     even more equal

