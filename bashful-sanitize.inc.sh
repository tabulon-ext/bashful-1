#!/bin/bash

# Bashful is copyright 2009-2016 Dejay Clayton, all rights reserved:
#     https://github.com/dejayc/bashful
# Bashful is licensed under the 2-Clause BSD License:
#     http://opensource.org/licenses/BSD-2-Clause

# Declare the module name.
declare BASHFUL_MODULE='sanitize'

# Verify execution context and module dependencies, and register the module.
{
    declare BASHFUL_MODULE_VAR="BASHFUL_LOADED_${BASHFUL_MODULE}"
    [[ -z "${!BASHFUL_MODULE_VAR-}" ]] || return 0

    # Ensure the module is sourced, not executed, generating an error
    # otherwise.
    [[ "${BASH_ARGV}" != '' ]] || {
        echo "ERROR: ${BASH_SOURCE[0]##*/} must be sourced, not executed"
        exit 1
    } >&2

    # Register the module.
    declare "${BASHFUL_MODULE_VAR}"="${BASHFUL_MODULE}"
}

# Preliminary security precautions, to sanitize the environment a little.
# Note that this code must be 'sourced' and not executed.
{
    # Examine and preserve the value of POSIXLY_CORRECT, if necessary.
    if [ -n "${POSIXLY_CORRECT+is_set}" ]
    then
        BASHFUL_POSIXLY_CORRECT="${POSIXLY_CORRECT}"
    fi

    # Set POSIXLY_CORRECT, in order to ignore functions and aliases named the
    # same as builtin commands.
    POSIXLY_CORRECT=1

    # Unset any functions named the same as bash built-ins.
    builtin unset -f \
        'alias' 'bg' 'bind' 'break' 'builtin' 'caller' 'cd' 'command' \
        'compgen' 'complete' 'compopt' 'continue' 'declare' 'dirs' 'disown' \
        'echo' 'enable' 'eval' 'exec' 'exit' 'export' 'false' 'fc' 'fg' \
        'getopts' 'hash' 'help' 'history' 'jobs' 'kill' 'let' 'local' \
        'logout' 'mapfile' 'popd' 'printf' 'pushd' 'pwd' 'read' 'readarray' \
        'readonly' 'return' 'set' 'shift' 'shopt' 'source' 'suspend' 'test' \
        'times' 'trap' 'true' 'type' 'typeset' 'ulimit' 'umask' 'unalias' \
        'unset' 'wait'

    # Generate errors if unset variables are referenced.
    set -u

    # Disable expansion of shell aliases.
    shopt -qu expand_aliases

    # These functions may only be unset when POSIXLY_CORRECT is not set to 1.
    unset POSIXLY_CORRECT
    unset -f '.' ':' '['

    # Restore the value of POSIXLY_CORRECT, if necessary.
    if [ -n "${BASHFUL_POSIXLY_CORRECT+is_set}" ]
    then
        POSIXLY_CORRECT="${BASHFUL_POSIXLY_CORRECT}"
        unset BASHFUL_POSIXLY_CORRECT
    fi
}
