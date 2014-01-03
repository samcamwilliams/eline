eline
=====

eline is a status line for i3, written in Erlang. It provides a framework for the simple addition of 'homebrew' items to the bar that execute arbitary Erlang code. It outputs JSON that i3 can render and supports colour.

I have been using it as my only status line for roughly a year and it seems to perform well. The ease and speed of creating new bar items makes it better than the other options available for me, but your milage may vary.

## Usage ##

Configure each of the records in the list returned by stat() to your taste, then replace the status\_command in your i3 config as follows to execute eline.erl as a script. Line breaks are added to the output so that it can be printed to a file/STDOUT and checked for errors.

## Future Work ##
* Split each item into it's own directory - perhaps allowing a list of custom modules as command line options?
* Decouple the workings of the bar items from the inner workings of the system.
* Write tests.
* Document the API (and record definition).
