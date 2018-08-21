# mahai, 20180815
# ini shell module - implementating 'presume' variable initialization

# Idea of a 'Presume' Mechanism:
# ==============================
#
# A client shell script needs to initialize variables.  The default
# presumptions are hard coded into the script ('ini-map').
# Presumptions may be passed as command line arguments ('ini-cli'),
# read from the environment ('ini-env') or from a file
# ('ini-file'). Other sources may be named, yet these four form the
# basic set of generally available presume-sources.
#
# A module provides a presume-mechanism, if its operations do not
# impose any order on the initialization process.  The client script
# should be able to establish its own precedence among the sources.
#
# The 'ini.sh' Implementation of Presume
# ======================================
#
# 'ini.sh' is a shell script module, to be sourced.  Its operations
# are functions, that do not manipulate global state.  The interface
# for client scripts is with shell commands, options and appropriate
# documentation.  The 'ini.sh' module supports 'ini-map', 'ini-cli',
# 'ini-env' and 'ini-file'.
#
# The recommended use of ini.sh is to override variables with the
# following precedence:
# 1) ini-map
# 2) ini-cli (unrestricted)
# 3) ini-env (prevented from prefix)
# 4) configuration file (filters envprefix and dotadaptconf)
# To keep this fallthrough mechanism working, following logic is in place:
# - cli args can redirect env and conf 
# - env can redirect conf
# To prevent the higher presumptions:
# at 2), do not pass on cli args;
# at 3), do not provide env variables or override envprefix='';
# at 4), do not provide [presumed] conf file section or override dotadaptconf=''; 


function help() {
    cat <<EOF
Usage:  presume [<op>] [<opt>]... 
		[--map=<name>,--cli=<count>,--env=<prefix>,--file=<fname>]...
		[--<varname>=<value>]... [--] [<varname>]...

This command imlements a variable initialization mechanism. 
	
Operations <op>:
	help
		Print help.
	list
		Print a list of variable definitions to be evaluated.
	vars
		Print a list of variable names.
	map
		Print a list of array definitions like 'a[k]=v' to be
		evaluated. 
	table
		Print a table. Rows are variables and chronologically
		sorted. Columns are 'source', 'key', 'value'.  EOF }
	test
		Run validation tests.
		
Option <opt>:
	-e EV, --env-prefix-var=EV
       		Specify EV as the client scripts's variable name for 
		the environment prefix. Defaults to 'envprefix'
	-f FV, --filename-var=FV
	   	Specify FV as the client script's variable name for
		the ini-file filename. Defaults to 'inifile'.
Sources:
	--map=<name>
		Assume the variable <name> to be a globally defined
		associated array holding initializations.
	--cli=<count>
		apply the <count> number of subsequent command line
		overrides. 
	--env=<prefix>
		Use environment variables initializations. Each known
		<varname> will be prefixed with <prefix>.
	--file=<fname>
		Use initializations from file <fname>.

Command line overrides --<varname>=<value> are key/value pairs to be
considered by the --cli source.  Variable names <varname> are
positional parameters, to which the output will be restricted.
		
EOF
    if [[ "${FUNCNAME[0]}" == "help" ]]; then
	local thisfile="${BASH_SOURCE[0]}"
	if [ -n "$thisfile" ]; then
	    sed -n '3,/^[[:blank:]]*$/ s/^# //p' "$thisfile"
	fi
    fi
}

function presume() {
    [[ $# -eq 0 ]] && set -- "fail"
    # local errexit
    # [[ ! $- =~ e ]] && { errexit=notpreenabled; set -e; }
    case "$1" in
	-h | --help | help )
	    help | less
	    ;;
	list | vars | map | table | test )
	    presume_op "$@"	    
	    ;;
	fail )
	    help | head -n 9
	    return 1
	    ;;
	* )
	    echo "Unknown operation '$1'."
	    presume fail
	    ;;
    esac
    # [[ -n errexit ]] && set +e
}


function presume_op() {
    local op=$1
    shift

    local exargsShort
    local exargsLong
    
    # Set default values, and determine options overriding them
    {

	presume_defs() {
	    # key longopt shortopt arg default
	    echo EPV env-prefix-var e : "envprefix"
	    echo FV filename-var f : "inifile"
	}
	
	presume_option() {
	    local array=$1
	    local key=$2
	    local longopt=$3
	    local shortopt=$4
	    local arg=$5
	    local default=$6
	    shift 6
	    [ "$1" != - ] && { >&2 echo "Option mismatch in {FUNCNAME[0]}': "`printf "'%s' " "$@"`; return 1; }
	    shift
	    local o=`getopt -q -o "$shortopt$arg" -l "$longopt$arg" -- "$@"`
	    o="${o%%" -- "*}"
	    eval "set -- $o"
	    [ $# -lt 2 ] && return
	    declare -g "$array"'['"$key"']='"${2:-$default}"
	    exargsShort+=",$shortopt$arg"
	    exargsLong+=",$longopt$arg"
	}

	local -A opts
	while read -r line; do presume_option opts $line - "$@"; done < <(presume_defs)
	
	for k in "${!opts[@]}";do
	    echo declare "$k='${opts[$k]}'"
	    declare "$k=${opts[$k]}"
	done
    }

    # determine the sequence of ini sources to be processed
    {
	presume_sources() {
	    local array=$1
	    local longopts=$2
	    shift 2
	    [ "$1" != - ] && { >&2 echo "Source mismatch in {FUNCNAME[0]}': "`printf "'%s' " "$@"`; return 1; }
	    shift
	    local s=`getopt -q -o '' -l "$longopts" -- "$@"`
	    s="${s%%" -- "*}"
	    eval "set -- $s"
	    while [ $# -gt 0 ]; do
		[ $# -lt 2 ] && return
		if [[ "$1" == --* ]]; then
		    echo "ini-source: $1='$2'"
		    echo eval "$array"'+=( '"$1" "'$2'"' )'
		    eval "$array"'+=( '"$1" "'$2'"' )'
		fi
		shift 2
	    done
	}

	local longopts='map:,cli:,env:,file:'
	exargsLong+=",$longopts"
	local -a srcs
	presume_sources srcs "$longopts" - "$@"
    }

    # TODO do something with this sequence
    for i in "${srcs[@]}";do
	echo ":$i"
    done
    echo ----


    # identify cli overrides
    {
	function presume_cliInput() {
	    local array=$1
	    local shortopts=$2
	    local longopts=$3
	    shift 3
	    [ "$1" != - ] && { >&2 echo "Source mismatch in {FUNCNAME[0]}': "`printf "'%s' " "$@"`; return 1; }
	    shift
	    local o
	    while [ $# -gt 0 ]; do
		o="$1"
		shift
		[ "$1" == -- ] && break
		if [[ "$1" == --* ]]; then
		    o="${1:2}"
		    [[ "$1" =~ --[^=]* ]] && o="${o%%=*}"
		    [[ "$longopts" =~ ,"${o}"[:,] ]] && continue
		else 
		   continue
		fi
		echo ":$o"
		echo eval "$array"'+=( ['"$o"']="" )'
		eval "$array"'+=( ['"$o"']="" )'
		exargsLong+=",$o"
	    done
	    
	}
	local -A iniCli
	local -a varList
 	presume_cliInput iniCli $exargsShort $exargsLong - "$@"
    }
    for i in "${iniCli[@]}";do
	echo "iniCli: $i"
    done


	
    
}
