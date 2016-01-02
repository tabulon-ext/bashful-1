#!/bin/bash

# Bashful is copyright 2009-2016 Dejay Clayton, all rights reserved:
#     https://github.com/dejayc/bashful
# Bashful is licensed under the 2-Clause BSD License:
#     http://opensource.org/licenses/BSD-2-Clause

# Declare the module name and dependencies.
declare BASHFUL_MODULE='seq'
declare BASHFUL_MODULE_DEPENDENCIES='list'

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

    # Register the module and dependencies.
    declare "${BASHFUL_MODULE_VAR}"="${BASHFUL_MODULE}"
    declare "BASHFUL_DEPS_${BASHFUL_MODULE}"="${BASHFUL_MODULE_DEPENDENCIES}"
}

# NOTE: Any occurrence of '&&:' and '||:' that appears following a command is
# designed to prevent that command from terminating the script when a non-zero
# status is returned while 'set -e' is active.  This is especially necessary
# with the 'let' command, which if used to assign '0' to a variable, is
# treated as a failure.  '&&:' preserves the $? status of a command.  '||:'
# discards the status, which is useful when the last command of a function
# returns a non-zero status, but should not cause the function to be
# considered as a failure.


# function intSeq:
#
# Returns a separated list of non-negative integers, based on one or more
# input sequences of integers or integer ranges passed in as arguments.
#
# -n optionally preserves null items.
#
# -s optionally specifies an output separator.  Defaults to ' '.
#
# -u optionally generates only unique numbers, discarding duplicate numbers
#    from the output.
#
# Each number generated by an integer range will be padded with zeroes, if
# the number has less characters than any zero-padded numbers used to specify
# the integer range.  For example, integer range 10-08 will generate 10 09 08,
# while integer range 10-8 will generate 10 9 8.
#
# Examples:
#
# $ intSeq 2 4 6 10-08
# 2 4 6 10 09 08
#
# $ intSeq -u 5-8 10-6
# 5 6 7 8 10 9
#
# $ intSeq -s ':' 1-5
# 1:2:3:4:5
#
# $ intSeq -s ',' '1' '2' '' '4' '5' '  ' '6'
# 1,2,4,5,6
#
# $ intSeq -s ',' -n '1' '2' '' '4' '5' '  ' '6'
# 1,2,,4,5,,6
#
# $ intSeq -s ',' -n -u '1' '2' '' '4' '5' '  ' '6'
# 1,2,,4,5,6
function intSeq()
{
    local SEP=' '
    declare -i PRESERVE_NULL_ITEMS=0
    local FLAG_PRESERVE_NULL_ITEMS=''
    local FLAG_UNIQUE=''

    # Parse function options.
    declare -i OPTIND
    local OPT=''

    while getopts ':ns:u' OPT
    do
        case "${OPT}" in
        n)
            let PRESERVE_NULL_ITEMS=1
            FLAG_PRESERVE_NULL_ITEMS="-${OPT}"
            ;;
        s)
            SEP="${OPTARG}"
            ;;
        u)
            FLAG_UNIQUE="-${OPT}"
            ;;
        *)
            return 2
        esac
    done
    shift $(( OPTIND - 1 ))
    # Done parsing function options.

    declare -a RESULTS=()

    # The following variable just makes regexes easier to read.
    local WS='[[:space:]]*'

    while [ $# -gt 0 ]
    do
        local ARG="${1}"
        shift

        # Handle empty sequences appropriately.
        [[ "${ARG}" =~ [^[:space:]] ]] || {

            [[ ${PRESERVE_NULL_ITEMS} -ne 0 ]] && RESULTS[${#RESULTS[@]}]=''
            continue
        }

        [[ "${ARG}" =~ ^${WS}([0-9]+)${WS}$ ]] || \
        [[ "${ARG}" =~ ^${WS}([0-9]+)${WS}-${WS}([0-9]+)${WS}$ ]] || \
            return 1

        local FROM_STR="${BASH_REMATCH[1]-}"
        local TO_STR="${BASH_REMATCH[2]-}"
        [[ -n "${TO_STR}" ]] || TO_STR="${FROM_STR}"

        # Record the length of the existing numbers, to later
        # determine if they are padded with zeroes.
        declare -i FROML=${#FROM_STR}
        declare -i TOL=${#TO_STR}

        # Convert numbers to proper decimal integers to remove leading
        # zeroes.
        declare -i FROM=10#"${FROM_STR}"
        declare -i TO=10#"${TO_STR}"

        # Determine if either of the numbers are padded with zeroes,
        # and if so, figure out how many digits of padding should be
        # used for each number in the sequence.
        declare -i L=0
        [[ ${FROML} -eq ${#FROM} ]] || let L=${FROML}
        [[ ${TOL} -eq ${#TO} ]] || { [[ ${TOL} -gt ${L} ]] && \
            let L=${TOL}; }

        # Generate the sequence.
        declare -i INC=1
        [[ ${FROM} -le ${TO} ]] || let INC=-1
        let TO+=INC ||:

        while [ ${FROM} -ne ${TO} ]
        do
            local RESULT
            printf -v RESULT "%0${L}d" "${FROM}"
            RESULTS[${#RESULTS[@]}]="${RESULT}"
            let FROM+=INC ||:
        done
    done

    # Generate the final output.
    translatedList \
        ${FLAG_UNIQUE} ${FLAG_PRESERVE_NULL_ITEMS} -s "${SEP}" "${RESULTS[@]-}"
}

# function nameValueSeq:
#
# Returns a separated list of name/value pairs, with each pair separated from
# the next by the specified pair separator, and each name separated from its
# value by the specified value separator.  Each argument passed into the
# function will be interpreted as a name/value pair to be separated into a
# name and value, according to the first occurrence of the specified value
# delimiter.  The name and/or value, if they contain text or numeric sequences,
# will be permuted into multiple resulting name/value pairs.
#
# -b optionally bypasses the permuting of any text or numeric sequences that
#    may exist in the names of name/value pairs.
#
# -B optionally bypasses the permuting of any text or numeric sequences that
#    may exist in the values of name/value pairs.
#
# -d optionally specifies one or more value delimiter characters.  The first
#    occurrence of an input delimiter within a name/value pair will be used to
#    split the name and value.  All subsequent occurrences will be considered
#    part of the value.  Defaults to '='.  An error is returned if null, or if
#    it contains '[', ']', or '-' characters.
#
# -q optionally escapes each item being output, in a way that protects spaces,
#    quotes, and other special characters from being misinterpreted by the
#    shell.  Useful for assigning the output of this function to an array,
#    via the following construct:
#
#    declare -a ARRAY="( `nameValueSeq -q "${INPUT_ARRAY[@]}"` )"
#
#    Note that while this option can be used simultaneously with an output
#    separator specified via -S, such usage is not guaranteed to be parsable,
#    depending upon the value of the separator.
#
# -r optionally removes name/value pairs containing null values.  By default,
#    such pairs are preserved.
#
# -R optionally removes name/value pairs containing null names.  By default,
#    such pairs are preserved.
#
# -s optionally specifies a value separator for separating each name from
#    value.  Defaults to '='.
#
# -S optionally specified a pair separator for separating each name/value
#    pair from the next.  Defaults to ';'.
#
# -t optionally trims whitespace from values.
#
# -T optionally trims whitespace from names.
#
# -u optionally outputs only unique name/value pairs, discarding duplicates
#    from the output.
#
# -v optionally treats arguments without an input delimiter as a value with a
#    null name.  By default, such entries are treated as a name with a null
#    value.
#
# Examples:
#
# $ nameValueSeq 'a=1' 'b=2' 'c=3'
# a=1;b=2;c=3
#
# $ nameValueSeq '=1' 'b=' 'c=3'
# =1;b=;c=3
#
# $ nameValueSeq '[,]=1' 'b=[,]' 'c=3'
# =1;=1;b=;b=;c=3
#
# $ nameValueSeq -r '=1' 'b=' 'c=3'
# =1;c=3
#
# $ nameValueSeq -r '[,]=1' 'b=[,]' 'c=3'
# =1;c=3
#
# $ nameValueSeq -R '=1' 'b=' 'c=3'
# b=;c=3
#
# $ nameValueSeq -R '[,]=1' 'b=[,]' 'c=3'
# b=;c=3
#
# $ nameValueSeq 'a=1' 'b'
# a=1;b=
#
# $ nameValueSeq -v 'a=1' 'b'
# a=1;=b
#
# $ nameValueSeq -s ':' 'a=1' 'b=2' 'c=3'
# a:1;b:2;c:3
#
# $ nameValueSeq -S ',' 'a=1' 'b=2' 'c=3'
# a=1,b=2,c=3
#
# $ nameValueSeq -u 'a=1' 'b=2' 'a=2' 'b=2'
# a=1;b=2;a=2
#
# $ nameValueSeq -t 'a= 1 ' 'b=2 ' 'c= 3'
# a=1;b=2;a=2
#
# $ nameValueSeq -T ' a =1' 'b =2' ' c=3'
# a=1;b=2;a=2
#
# $ nameValueSeq -d ':' 'url:http://example.com:80' 'val:start:stop'
# url=http://example.com:80;val=start:stop
#
# $ nameValueSeq -S ' ' '[a,b]=[1,2]' '[c,d]=[3,4]'
# a=1 a=2 b=1 b=2 c=3 c=4 d=3 d=4
#
# $ nameValueSeq -S ' ' -b '[a,b]=[1,2]' '[c,d]=[3,4]'
# [a,b]=1 [a,b]=2 [c,d]=3 [c,d]=4
#
# $ nameValueSeq -S ' ' -B '[a,b]=[1,2]' '[c,d]=[3,4]'
# a=[1,2] b=[1,2] c=[3,4] d=[3,4]
#
# $ nameValueSeq -S ' ' -b -B '[a,b]=[1,2]' '[c,d]=[3,4]'
# [a,b]=[1,2] [c,d]=[3,4]
#
# $ nameValueSeq -S ' ' -q "My Name=[No one,Doesn't matter]"
# My\ Name=No\ one My\ Name=Doesn\'t\ matter
function nameValueSeq()
{
    local DELIM='='
    local PAIR_SEP=';'
    local SEP='='
    declare -i BYPASS_NAME_SEQUENCES=0
    declare -i BYPASS_VALUE_SEQUENCES=0
    declare -i REMOVE_NULL_NAMES=0
    declare -i REMOVE_NULL_VALUES=0
    declare -i SINGLE_IS_VALUE=0
    declare -i TRIM_NAMES=0
    declare -i TRIM_VALUES=0
    local FLAG_PRESERVE_NULL_NAMES='-N'
    local FLAG_PRESERVE_NULL_VALUES='-N'
    local FLAG_QUOTED=''
    local FLAG_UNIQUE=''

    # Parse function options.
    declare -i OPTIND
    local OPT=''

    while getopts ":bBd:qrRs:S:tTuv" OPT
    do
        case "${OPT}" in
        b)
            let BYPASS_NAME_SEQUENCES=1
            ;;
        B)
            let BYPASS_VALUE_SEQUENCES=1
            ;;
        d)
            DELIM="${OPTARG}"
            [[ -z "${DELIM}" || "${DELIM}" =~ [][-] ]] && return 1
            ;;
        q)
            FLAG_QUOTED="-${OPT}"
            ;;
        r)
            let REMOVE_NULL_VALUES=1
            FLAG_PRESERVE_NULL_VALUES=''
            ;;
        R)
            let REMOVE_NULL_NAMES=1
            FLAG_PRESERVE_NULL_NAMES=''
            ;;
        s)
            SEP="${OPTARG}"
            ;;
        S)
            PAIR_SEP="${OPTARG}"
            ;;
        t)
            let TRIM_VALUES=1
            ;;
        T)
            let TRIM_NAMES=1
            ;;
        u)
            FLAG_UNIQUE="-${OPT}"
            ;;
        v)
            let SINGLE_IS_VALUE=1
            ;;
        *)
            return 2
        esac
    done
    shift $(( OPTIND - 1 ))
    # Done parsing function options.

    # It's safe to use '[' as a split indicator, because we use it as the
    # opening delimiter for sequences in this function; as such, permuted
    # strings will never have '[' in their resulting permutation output.
    local SPLIT='['

    declare -a RESULTS=()

    declare -i TRIM_TRAIL_NL=0
    [[ "${DELIM}" =~ $'\n' ]] || let TRIM_TRAIL_NL=1

    while [ $# -gt 0 ]
    do
        local PAIR_STR="${1}"
        shift

        local PAIR_LIST
        PAIR_LIST="$( splitList -d "${DELIM}" "${PAIR_STR}" )" || return

        unset PAIR
        declare -a PAIR=() # Compatibility fix.
        declare -a PAIR="( ${PAIR_LIST} )" || return
        declare -i PAIR_LEN=${#PAIR[@]-}

        local NAME=''
        local VALUE=''

        case ${PAIR_LEN} in
        1)
            if [ ${SINGLE_IS_VALUE} -ne 0 ]
            then
                VALUE="${PAIR[0]}"
            else
                NAME="${PAIR[0]}"
            fi
            ;;
        2)
            NAME="${PAIR[0]}"
            VALUE="${PAIR[1]}"
            ;;
        *)
            NAME="${PAIR[0]}"
            VALUE="${PAIR_STR:$(( ${#NAME} + 1 ))}"
            ;;
        esac

        [[ ${TRIM_NAMES} -ne 0 ]] && {

            NAME="${NAME#"${NAME%%[![:space:]]*}"}"
            NAME="${NAME%"${NAME##*[![:space:]]}"}"
        }

        [[ -n "${NAME}" || ${REMOVE_NULL_NAMES} -eq 0 ]] || continue

        [[ ${TRIM_VALUES} -ne 0 ]] && {

            VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"
            VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"
        }

        [[ -n "${VALUE}" || ${REMOVE_NULL_VALUES} -eq 0 ]] || continue

        [[ ${BYPASS_NAME_SEQUENCES} -ne 0 ]] && \
        [[ ${BYPASS_VALUE_SEQUENCES} -ne 0 ]] && {

            RESULTS[${#RESULTS[@]}]="${NAME}${SEP}${VALUE}"
            continue
        }

        unset NAMES
        declare -a NAMES=()

        [[ ${BYPASS_NAME_SEQUENCES} -ne 0 ]] || {

            # Permute the name if it contains sequence delimiters.
            [[ "${NAME}" =~ [][-] ]] && {

                # Appending a non-whitespace character, such as '_', to a
                # captured string allows any trailing newlines to be retained,
                # whereas otherwise they would be trimmed.  Then, remove '_'
                # from the string.
                NAME="$( \
permutedSeq ${FLAG_PRESERVE_NULL_NAMES} -s "${SPLIT}" "${NAME}" \
    && echo '_' )" || return
                NAME="${NAME%_}"

                if [ -n "${NAME}" ]
                then
                    NAME="$( splitList -d "${SPLIT}" "${NAME}" )" \
                        || return
                    declare -a NAMES="( ${NAME} )" || return
                else
                    [[ ${REMOVE_NULL_NAMES} -eq 0 ]] || continue
                fi
            }
        }

        declare -i NAMES_LEN=${#NAMES[@]}
        [[ ${NAMES_LEN} -gt 0 ]] || {

            NAMES=( "${NAME}" )
            let NAMES_LEN=1
        }

        unset VALUES
        declare -a VALUES=()

        [[ ${BYPASS_VALUE_SEQUENCES} -ne 0 ]] || {

            # Permute the value if it contains sequence delimiters.
            [[ "${VALUE}" =~ [][-] ]] && {

                # Appending a non-whitespace character, such as '_', to a
                # captured string allows any trailing newlines to be retained,
                # whereas otherwise they would be trimmed.  Then, remove '_'
                # from the string.
                VALUE="$( \
permutedSeq ${FLAG_PRESERVE_NULL_VALUES} -s "${SPLIT}" "${VALUE}" \
    && echo '_' )" || return
                VALUE="${VALUE%_}"

                if [ -n "${VALUE}" ]
                then
                    VALUE="$( splitList -d "${SPLIT}" "${VALUE}" )" \
                        || return
                    declare -a VALUES="( ${VALUE} )" || return
                else
                    [[ ${REMOVE_NULL_VALUES} -eq 0 ]] || continue
                fi
            }
        }

        declare -i VALUES_LEN=${#VALUES[@]}
        [[ ${VALUES_LEN} -gt 0 ]] || {

            VALUES=( "${VALUE}" )
            let VALUES_LEN=1
        }

        declare -i I=0
        while [ ${I} -lt ${NAMES_LEN} ]
        do
            declare -i J=0
            while [ ${J} -lt ${VALUES_LEN} ]
            do
                RESULTS[${#RESULTS[@]}]="${NAMES[I]}${SEP}${VALUES[J]}"
                let J+=1
            done
            let I+=1
        done
    done

    translatedList ${FLAG_QUOTED} ${FLAG_UNIQUE} -s "${PAIR_SEP}" \
        "${RESULTS[@]-}"
}

# function permutedSeq:
#
# Returns a separated list of strings representing permutations of static text
# mingled with non-negative integer sequences or static text sequences.  The
# function reads each argument passed to it, and parses them by looking for
# embedded sequences within them.
#
# -d optionally specifies one or more text delimeter characters to separate
#    values within a text sequence.  Defaults to ','.  An error is returned if
#    null, or if it contains any character also contained by the starting or
#    ending delimiters.
#
# -m optionally specifies one or more characters to serve as delimiters that
#    mark the start of a sequence.  Defaults to '['.  An error is returned if
#    null, or if it contains '-' or any character also contained by the ending
#    or text delimiters.
#
# -M optionally specifies one or more characters to serve as delimiters that
#    mark the end of a sequence.  Defaults to ']'.  An error is returned if
#    null, or if it contains '-' or any character also contained by the
#    starting or text delimiters.
#
# -n optionally preserves null values within permutations.  By default, null
#    values are discarded.
#
# -N optionally preserves separators that appear between null values and any
#    adjacent null or non-null value.  By default, separators adjacent to null
#    values are discarded.
#
# -p optionally preserves null values within permutations, and preserves
#    entirely null permutations within the output.  By default, null values
#    are discarded.
#
# -q optionally escapes each item being output, in a way that protects spaces,
#    quotes, and other special characters from being misinterpreted by the
#    shell.  Useful for assigning the output of this function to an array,
#    via the following construct:
#
#    declare -a ARRAY="( `permutedSeq -q "${INPUT_ARRAY[@]}"` )"
#
#    Note that while this option can be used simultaneously with an output
#    separator specified via -s, such usage is not guaranteed to be parsable,
#    depending upon the value of the separator.
#
# -s optionally specifies an output separator for each permutation.  Defaults
#    to ' '.
#
# -u optionally generates only unique permutations, removing duplicates from
#    the results.
#
# Sequences are delimited by the characters specified as the opening and
# closing delimiters, which may not appear elsewhere within the text.
#
# Integer sequences are zero or more integers or integer ranges, separated by
# commas.  An integer range is two integers separated by a dash '-'.
#
# To specify a text sequence that contains characters that would otherwise
# be interpreted as integer sequences, specify a non-comma text delimiter:
#
# $ permutedSeq -d ';' -s "\n" 'School is open from [8-9;10-11] [am;pm]'
# School is open from 8-9 am
# School is open from 8-9 pm
# School is open from 10-11 am
# School is open from 10-11 pm
#
# Examples:
#
# $ permutedSeq -s "\n" 'Trains depart at [1,09-10][am,pm]'
# Trains depart at 1am
# Trains depart at 1pm
# Trains depart at 09am
# Trains depart at 09pm
# Trains depart at 10am
# Trains depart at 10pm
#
# $ permutedSeq -m '<' -M '>' '<1,2,1><8,9>'
# 18 19 28 29 18 19
#
# $ permutedSeq -u -m '<' -M '>' '<1,2,1><8,9>'
# 18 19 28 29
#
# $ permutedSeq -s ',' '[sub,,super][script,,sonic]'
# subscript,subsonic,superscript,supersonic
#
# $ permutedSeq -s ',' -n '[sub,,super][script,,sonic]'
# subscript,sub,subsonic,script,sonic,superscript,super,supersonic
#
# $ permutedSeq -s ',' -N '[sub,,super][script,,sonic]'
# subscript,sub,subsonic,script,,sonic,superscript,super,supersonic
#
# $ permutedSeq -s ';' '[Hello,Goodbye], [world,you]' '[Regards,Thanks]'
# Hello, world;Hello, you;Goodbye, world;Goodbye, you;Regards;Thanks
#
# $ permutedSeq -q '[Hi,Bye] [there,you]'
# Hi\ there Hi\ you Bye\ there Bye\ you
#
# $ permutedSeq -s ':' -N '[,,]'
# :
function permutedSeq()
{
    local OPEN_DELIM='['
    local CLOSE_DELIM=']'
    local TEXT_DELIM=','
    local PERM_SEP=' '
    declare -i PRESERVE_NULL_ITEMS=0
    declare -i PRESERVE_NULL_PERMS=0
    local FLAG_PRESERVE_NULL_ITEMS=''
    local FLAG_PRESERVE_NULL_PERMS=''
    local FLAG_PRESERVE_NULL_SEPS=''
    local FLAG_QUOTED=''
    local FLAG_UNIQUE=''

    # Parse function options.
    declare -i OPTIND
    local OPT=''

    while getopts ':d:m:M:nNpqs:u' OPT
    do
        case "${OPT}" in
        d)
            TEXT_DELIM="${OPTARG}"
            [[ -n "${TEXT_DELIM}" ]] || return 1
            ;;
        m)
            OPEN_DELIM="${OPTARG}"
            [[ -n "${OPEN_DELIM}" ]] || return 1
            ;;
        M)
            CLOSE_DELIM="${OPTARG}"
            [[ -n "${CLOSE_DELIM}" ]] || return 1
            ;;
        n)
            let PRESERVE_NULL_ITEMS=1
            ;;
        N)
            let PRESERVE_NULL_ITEMS=1
            let PRESERVE_NULL_PERMS=1
            FLAG_PRESERVE_NULL_PERMS='-p'
            ;;
        p)
            let PRESERVE_NULL_ITEMS=1
            FLAG_PRESERVE_NULL_SEPS='-N'
            ;;
        q)
            FLAG_QUOTED="-${OPT}"
            ;;
        s)
            PERM_SEP="${OPTARG}"
            ;;
        u)
            FLAG_UNIQUE="-${OPT}"
            ;;
        *)
            return 2
        esac
    done
    shift $(( OPTIND - 1 ))
    # Done parsing function options.

    # Verify that delimiters do not conflict with each other.
    [[ "${TEXT_DELIM}" == "${TEXT_DELIM%%["${OPEN_DELIM}"]*}" && \
       "${TEXT_DELIM}" == "${TEXT_DELIM%%["${CLOSE_DELIM}"]*}" && \
       "${OPEN_DELIM}" == "${OPEN_DELIM%%["${CLOSE_DELIM}"]*}" ]] || return 1

    # Verify that opening and closing delimiters do not contain '-'.
    [[ "${OPEN_DELIM}" =~ - || "${CLOSE_DELIM}" =~ - ]] && return 1

    [[ ${PRESERVE_NULL_ITEMS} -eq 0 ]] || FLAG_PRESERVE_NULL_ITEMS='-n'

    local PERM_SPLIT="${OPEN_DELIM:0:1}"
    local PERM_SETS=''

    while [ $# -gt 0 ]
    do
        local REMAINING="${1}"
        shift

        local NONSEQUENCE=''
        local SEQUENCE=''

        unset PERM_SET
        declare -a PERM_SET=()

        while :
        do
            # Find the next leading segment of non-sequence text.
            NONSEQUENCE="${REMAINING%%["${OPEN_DELIM}""${CLOSE_DELIM}"]*}"

            # Advance the remaining text past the non-sequence text, to the
            # start of the next sequence, if one exists.
            REMAINING="${REMAINING:$(( ${#NONSEQUENCE} ))}"

            # If the non-sequence text exists, save it to the set of permuters.
            [[ -n "${NONSEQUENCE}" ]] && \
                PERM_SET[${#PERM_SET[@]}]="${NONSEQUENCE}"

            # Exit the loop if no text remains to be analyzed.
            [[ -n "${REMAINING}" ]] || break;

            # Define the current sequence as the text remaining to be analyzed,
            # trimmed so that it doesn't contain any text past, or including,
            # the next appearing closing delimiter.
            SEQUENCE="${REMAINING%%["${CLOSE_DELIM}"]*}"

            # Error: No closing delimiter.
            [[ "${SEQUENCE}" != "${REMAINING}" ]] || return 1

            declare -i SEQUENCE_LEN=${#SEQUENCE}

            # Trim the opening delimeter from the current sequence.
            SEQUENCE="${SEQUENCE#["${OPEN_DELIM}"]}"

            # Error: No opening delimiter.
            [[ ${#SEQUENCE} -ne ${SEQUENCE_LEN} ]] || return 1

            # Advance the remaining text past the sequence text.
            REMAINING="${REMAINING:$(( ${SEQUENCE_LEN} + 1 ))}"

            # Skip empty sequences if necessary.
            [[ "${SEQUENCE}" != '' || ${PRESERVE_NULL_PERMS} -ne 0 ]] \
                || continue

            unset SEQ_SET
            declare -a SEQ_SET=()

            # Check for text or integer sequence.
            if [[ "${SEQUENCE}" =~ ^[-0-9,[:space:]]+$ ]]
            then
                SEQUENCE="$( splitList -d ',' "${SEQUENCE}" )" || return
                declare -a SEQ_SET="( ${SEQUENCE} )" || return

                # Appending a non-whitespace character, such as '_', to a
                # captured string allows any trailing newlines to be retained,
                # whereas otherwise they would be trimmed.  Then, remove '_'
                # from the string.
                SEQUENCE="$( \
intSeq ${FLAG_UNIQUE} ${FLAG_PRESERVE_NULL_ITEMS} \
    -s "${PERM_SPLIT}" "${SEQ_SET[@]-}" && echo '_' )" || return
                SEQUENCE="${SEQUENCE%_}"
            else
                SEQUENCE="$( splitList -d "${TEXT_DELIM}" "${SEQUENCE}" )" \
                    || return
                declare -a SEQ_SET="( ${SEQUENCE} )" || return

                # Appending a non-whitespace character, such as '_', to a
                # captured string allows any trailing newlines to be retained,
                # whereas otherwise they would be trimmed.  Then, remove '_'
                # from the string.
                SEQUENCE="$( \
translatedList ${FLAG_UNIQUE} ${FLAG_PRESERVE_NULL_ITEMS} \
    -s "${PERM_SPLIT}" "${SEQ_SET[@]-}" && echo '_' )" || return
                SEQUENCE="${SEQUENCE%_}"
            fi

            # Add the results of the current sequence to the set of permuters.
            PERM_SET[${#PERM_SET[@]}]="${SEQUENCE}"
        done

        local PERM_SET_LIST

        # Generate a permuted set based on the set of permuters.
        #
        # Appending a non-whitespace character, such as '_', to a captured
        # string allows any trailing newlines to be retained, whereas
        # otherwise they would be trimmed.  Then, remove '_' from the string.
        PERM_SET_LIST="$( permutedSet \
            -q ${FLAG_UNIQUE} -d "${PERM_SPLIT}" -i '' -S \
            ${FLAG_PRESERVE_NULL_ITEMS} ${FLAG_PRESERVE_NULL_PERMS} \
            ${FLAG_PRESERVE_NULL_SEPS} "${PERM_SET[@]-}" \
                && echo '_' )" \
            || return
        PERM_SET_LIST="${PERM_SET_LIST%_}"

        printf -v PERM_SETS '%s%s' "${PERM_SETS}" "${PERM_SET_LIST}"
    done

    [[ ${PRESERVE_NULL_PERMS} -ne 0 ]] && FLAG_PRESERVE_NULL_PERMS='-n'

    declare -a SETS="( ${PERM_SETS} )" || return

    translatedList \
        ${FLAG_QUOTED} ${FLAG_PRESERVE_NULL_PERMS} ${FLAG_UNIQUE} \
        -s "${PERM_SEP}" "${SETS[@]-}"
}

# function permutedSet:
#
# Returns a separated list of permuted items.  Each argument passed into the
# function will be split by the input delimiter and turned into a set of
# items.  The set resulting from each argument will be permuted with every
# other set.
#
# By default, null items and null permutations are discarded.
#
# -d optionally specifies one or more input delimiter characters.  Defaults to
#    $IFS.  An error is returned if null.
#
# -i optionally specifies an output separator for each set item.  Defaults to
#    ' '.
#
# -n optionally preserves null values within permutations.  By default, null
#    values are discarded.
#
# -N optionally preserves null separators that appear between null values
#    and any adjacent null or non-null value.  By default, separators
#    adjacent to null values are discarded.
#
# -p optionally preserves null values within permutations, and preserves
#    entirely null permutations within the output.  By default, null values
#    are discarded.
#
# -q optionally escapes each item being output, in a way that protects spaces,
#    quotes, and other special characters from being misinterpreted by the
#    shell.  Useful for assigning the output of this function to an array,
#    via the following construct:
#
#    declare -a ARRAY="( `permutedSet -q "${INPUT_ARRAY[@]}"` )"
#
#    Note that while this option can be used simultaneously with an output
#    separator specified via -s, such usage is not guaranteed to be parsable,
#    depending upon the value of the separator.
#
# -s optionally specifies an output separator for each permutation.  Defaults
#    to ' '.
#
# -S optionally appends an output separator at the end of the output.  By
#    default, no output separator appears at the end of the output.
#
# -u optionally generates only unique permutations, discarding duplicates from
#    the output.
#
# Examples:
#
# $ permutedSet '1 2' 'a b'
# 1 a 1 b 2 a 2 b
#
# $ permutedSet -d ',' '1,2' 'a,b'
# 1 a 1 b 2 a 2 b
#
# $ permutedSet -i ':' -s ',' '1 2' 'a b'
# 1:a,1:b,2:a,2:b
#
# $ permutedSet -i ':' -s ',' -S '1 2' 'a b'
# 1:a,1:b,2:a,2:b,
#
# $ permutedSet -d ',' -s ',' '1,,2' 'a,,b'
# 1 a,1 b,2 a,2 b
#
# $ permutedSet -d ',' -s ',' -n '1,,2' 'a,,b'
# 1 a,1,1 b,a,b,2 a,2,2 b
#
# $ permutedSet -d ',' -s ',' -p '1,,2' 'a,,b'
# 1 a,1,1 b,a,,b,2 a,2,2 b
#
# $ permutedSet -d ',' -s ',' -N -p '1,,2' 'a,,b'
# 1 a,1 ,1 b, a, , b,2 a,2 ,2 b
#
# $ permutedSet -d ',' -s ',' -n 'a big' 'bad,,' 'wolf'
# a big bad wolf,a big wolf
#
# $ permutedSet -d ',' -n -q 'a big' 'bad,,' 'wolf'
# a\ big\ bad\ wolf a\ big\ wolf
#
# $ permutedSet -d ',' -s ',' -n -q 'a big' 'bad,,' 'wolf'
# a\ big\ bad\ wolf,a\ big\ wolf
#
# $ permutedSet -d ',' -i '' -s ',' -u '1,,2,,1' 'a,,b,,a'
# 1a,1b,2a,2b
#
# $ permutedSet -d ',' -i '' -s ',' -u -n '1,,2,,1' 'a,,b,,a'
# 1a,1,1b,a,b,2a,2,2b
#
# $ permutedSet -d ',' -i '' -s ',' -u -p '1,,2,,1' 'a,,b,,a'
# 1a,1,1b,a,,b,2a,2,2b
function permutedSet()
{
    local DELIM=' '
    local ITEM_SEP=' '
    local PERM_SEP=' '
    local NULL_PERM=''
    declare -i IS_UNIQUE=0
    declare -i PRESERVE_NULL_ITEMS=0
    declare -i PRESERVE_NULL_PERMS=0
    declare -i PRESERVE_NULL_SEPS=0
    local FLAG_PRESERVE_NULL_ITEMS=''
    local FLAG_PRESERVE_NULL_PERMS=''
    local FLAG_QUOTED=''
    local FLAG_TRAILING_SEP=''
    local FLAG_UNIQUE=''

    # Parse function options.
    declare -i OPTIND
    local OPT=''

    while getopts ':d:i:nNpqs:Su' OPT
    do
        case "${OPT}" in
        d)
            DELIM="${OPTARG}"
            [[ -n "${DELIM}" ]] || return 1
            ;;
        i)
            ITEM_SEP="${OPTARG}"
            ;;
        n)
            let PRESERVE_NULL_ITEMS=1
            ;;
        N)
            let PRESERVE_NULL_ITEMS=1
            let PRESERVE_NULL_SEPS=1
            ;;
        p)
            let PRESERVE_NULL_ITEMS=1
            let PRESERVE_NULL_PERMS=1
            FLAG_PRESERVE_NULL_PERMS='-n'
            ;;
        q)
            FLAG_QUOTED="-${OPT}"
            ;;
        s)
            PERM_SEP="${OPTARG}"
            ;;
        S)
            FLAG_TRAILING_SEP="-${OPT}"
            ;;
        u)
            let IS_UNIQUE=1
            FLAG_UNIQUE="-${OPT}"
            ;;
        *)
            return 2
        esac
    done
    shift $(( OPTIND - 1 ))
    # Done parsing function options.

    [[ ${PRESERVE_NULL_ITEMS} -eq 0 ]] || FLAG_PRESERVE_NULL_ITEMS='-n'

    declare -a RESULTS=()

    # Parse all incoming parameters into sets, processing them according to
    # the optional flags specified.
    while [ $# -gt 0 ]
    do
        local ARG="${1}"
        shift
        unset SET
        declare -a SET=( '' )
        declare -i SET_LEN=1

        [[ -n "${ARG}" ]] && {

            ARG="$( splitList -d "${DELIM}" "${ARG}" )" || return

            declare -a SET="( ${ARG} )" || return
            let SET_LEN=${#SET[@]-}

            [[ ${SET_LEN} -gt 0 || ${PRESERVE_NULL_ITEMS} -ne 0 ]] || continue
        }

        let RESULTS_LEN=${#RESULTS[@]-}

        # If the previous results set is empty, no previous set has been found
        # to permute.  Thus, assign the current set to the results set, and
        # skip to processing the next set.
        [[ ${RESULTS_LEN} -gt 0 ]] || {

            RESULTS=( "${SET[@]-}" )
            continue
        }

        # If preserving separators for null items, update the value that
        # represents what a completely null permutation would look like, for
        # future comparison.
        [[ ${PRESERVE_NULL_SEPS} -eq 0 ]] || {

            NULL_PERM="${NULL_PERM}${ITEM_SEP}"
        }

        declare -a NEXT_RESULTS=()
        declare -i I=0

        while [ ${I} -lt ${RESULTS_LEN} ]
        do
            local RESULT="${RESULTS[I]}"
            let I+=1

            [[ -n "${RESULT}" || ${PRESERVE_NULL_ITEMS} -ne 0 ]] || continue

            declare -i J=0

            while [ ${J} -lt ${SET_LEN} ]
            do
                local ITEM="${SET[J]}"
                let J+=1

                [[ -n "${ITEM}" || ${PRESERVE_NULL_ITEMS} -ne 0 ]] || continue

                local PERM

                if [ ${PRESERVE_NULL_SEPS} -ne 0 ]
                then
                    PERM="${RESULT}${ITEM_SEP}${ITEM}"
                else
                    if [ -n "${RESULT}" ]
                    then
                        if [ -n "${ITEM}" ]
                        then
                            PERM="${RESULT}${ITEM_SEP}${ITEM}"
                        else
                            PERM="${RESULT}"
                        fi
                    else
                        PERM="${ITEM}"
                    fi
                fi

                NEXT_RESULTS[${#NEXT_RESULTS[@]}]="${PERM}"
            done
        done
        RESULTS=( "${NEXT_RESULTS[@]-}" )
    done

    # Remove completely null permutations, unless they are to be preserved.
    [[ ${PRESERVE_NULL_PERMS} -ne 0 ]] || {

        let RESULTS_LEN=${#RESULTS[@]-}
        declare -i I=0

        while [ ${I} -lt ${RESULTS_LEN} ]
        do
            [[ "${RESULTS[I]}" != "${NULL_PERM}" ]] || unset RESULTS[I]
            let I+=1
        done
    }

    translatedList \
        ${FLAG_QUOTED} ${FLAG_UNIQUE} ${FLAG_PRESERVE_NULL_PERMS} \
        ${FLAG_TRAILING_SEP} -s "${PERM_SEP}" "${RESULTS[@]-}"
}
