:; # Polyglot wrapper: a cmd batch file on Windows, a bash script everywhere else.
:; # cmd treats a line starting with ':' as a label and skips it; bash runs ':' as a
:; # no-op, so the exec below is reached only under bash.
:; exec bash "$(dirname "$0")/$1"
@echo off
rem %~dp0 is this file's directory, trailing backslash included.
bash "%~dp0%~1"
