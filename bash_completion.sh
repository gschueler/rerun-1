
#
# rerun command completion script.
#  **rerun** is a simple, small modular automation
#  framework based on Bash, the POSIX shell.
#
# Installation
# -------------
#
# #. Download or git clone from [rerun](http://github.com/rerun/rerun).
# #. Source this file from your .bashrc.
#
# Usage
# -----
#
# The contained completion support provides for:
#
# * Module listing:
#       `rerun [tab][tab]`
# * Command listing for specified module:
#       `rerun module:[tab][tab]`
# * Option listing for specified module:command:
#       `rerun module: command[tab][tab]`
# * Arguments for specified option:
#       `rerun module: command --file[tab][tab]`
#
# @author: <a href="mailto:alex@dtosolutions.com">alex@dtosolutions.com</a>

[ -n "${RERUN_MODULES}" -a -d "${RERUN_MODULES}" ] || {
    export RERUN_MODULES=$(pwd)/modules
}

#
# Shell functions to support the command completion
#

# list:member - check if item is contained in list
list:member()
{
    local  item="$1" list="$2"
    for member in $(eval echo $list)
    do
	    [ "${item}" = "${member}" ] && return 0
    done
    return 1	
}

# list:subtract - subtract list2 members from list1
list:subtract() 
{
    local list1="$1" list2="$2" retlist=""
    for item in $(eval echo $list1)
    do
	    list:member $item "$list2" || retlist="$retlist $item"
    done
    echo $retlist    
}


# rerun:modules - list all rerun modules
rerun:modules()
{
    local  modules=""
    for mod in $RERUN_MODULES/*
    do 
	    [ -f "$mod/metadata" ] && modules="$modules $(basename $mod)"
    done
    echo $modules
}


# rerun:module:list - list all the commands for the module
rerun:module:commands()
{
    local  module=$1 commands=""
    for hdlr in $RERUN_MODULES/$module/commands/*/metadata; do
	[ -f $hdlr ] && {
	    cmd_name=$(basename $(dirname $hdlr))
	    commands="$commands $cmd_name"	
	}
    done    
    echo $commands
}

# rerun:command:options - List all the registered options for the command
rerun:command:options() 
{
    local module=$1 command=$2 prefix=$3 options=""
    for opt in $RERUN_MODULES/$module/commands/$command/*.option; do
	[ -f $opt ] && {
		name=$(basename ${opt})
		options="$options ${prefix}${name%%.option}"
	}
    done
    echo $options
}

# rerun:option:default - get the default for the specified option
rerun:option:default()
{
    local module=$1 command=$2 opt=$3 
    [ -f $RERUN_MODULES/$module/commands/$command/${opt##*-}.option ] && {
        awk -F= '/^DEFAULT/ {print $2}' $RERUN_MODULES/$module/commands/$command/${opt##*-}.option
	}
}

# rerun:option:has-argument - check if option takes an argument
rerun:option:has-argument()
{
    local module=$1 command=$2 opt=$3
    [ -f $RERUN_MODULES/$module/commands/$command/${opt##*-}.option ] && {
        args=$(awk -F= '/^ARGUMENTS/ {print $2}' $RERUN_MODULES/$module/commands/$command/${opt##*-}.option)
        [ "$args" = "true" ] && return 0 
    }
    return 1
}

# rerun:options:remaining - list remaining options
rerun:options:remaining() 
{
    local argline=$1 options=$2 used="" 
    for arg in $argline; do
        [[ "$arg" == -* ]] && used="$used ${arg}"
    done
    list:subtract "$options" "$used"
}

rerun:parse:module() 
{
    local cmdline=$@
    local module
    local regex="[ ]+--module[ ]([[:alnum:]]+)[ ]*"
    if [[ "$cmdline" =~ $regex ]]
    then
        module=${BASH_REMATCH[1]}
    fi
    echo $module
}

#
# _rerun - program completion for the `rerun` command.
#
_rerun() {
    [ -z "${RERUN_MODULES}" -o ! \( -d "${RERUN_MODULES}" \) ] && { 
        return 0 ; 
    }
    local cur prev cntx_module cntx_command cntx_options options
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
 
    eval set $COMP_LINE
    shift; # shift once to drop the "rerun" from the argument string

    # Define regex pattern to parse command line input
    #   module:command --optionA arg --optionB arg ...
	regex='([^:]+)([:]?[ ]?)([A-Za-z0-9_-]*)([ ]*)(.*)'
	if [[ "$@" =~ $regex ]]
	then
        # module context
        [ -d "$RERUN_MODULES/${BASH_REMATCH[1]}" ] && cntx_module=${BASH_REMATCH[1]};
        [ "${BASH_REMATCH[2]}" == ': ' ] && shift ;# eat the extra space char
        # command context
	    [ -d "$RERUN_MODULES/$cntx_module/commands/${BASH_REMATCH[3]/ /}" ] && {
	    	cntx_command=${BASH_REMATCH[3]/ /}
        }
        # BASH_REMATCH[4] contains the whitespace between command and options
        # option context
        cntx_options=${BASH_REMATCH[5]};  
	fi

    # Shift over to the command options
    shift;

    # Complete commands given the user shell input. 

    # Just the rerun command was typed. List modules
    [ -z "$cntx_module" ]  && {
        local modules=$(rerun:modules $RERUN_MODULES)
        COMPREPLY=( $(compgen -W "$modules" -S ':' -o nospace -- ${cur}) )
        return 0
    }    
    
    # Module specified: List module's commands
    [ -n "$cntx_module" -a -z "$cntx_command" ] && {
        local commands=$(rerun:module:commands ${cntx_module})
        COMPREPLY=( $(compgen -W "$commands" -- ${cur}) )
        return 0
    }
    
    # Command specified. List command's options
    options=$(rerun:command:options ${cntx_module} ${cntx_command} "--")
    if [ -n "$cntx_command" -a -z "$cntx_options"  ]; then
        COMPREPLY=( $(compgen -W "$options" -- "${cur}") )
        return 0 
    fi

    # Option(s) specified. Show possible arguments or remaining option choices.
    if [ -n "$cntx_options"  ]; then
        if [[ $prev == -* ]]; then
            # check if current option takes an argument ...
            if rerun:option:has-argument ${cntx_module} ${cntx_command} ${prev}; then
                # ... and has a default value
                local default=$(rerun:option:default ${cntx_module} ${cntx_command} ${prev})
                if [ -n "$default" ]; then
                    # print the default value
                    COMPREPLY=( $(compgen -W "$default" -- ${cur}) )
                    return 0
                else
                    # ... or wants option specific completion
                    case "$prev" in
                        --file*|--out*|--xml|--template)
                            # file completion
                	        COMPREPLY=( $(compgen -o filenames -A file -- ${cur}) )  ;;
                        --*dir*|--logs*)
                            # directory completion
                	        COMPREPLY=( $(compgen -o dirnames -A directory -- ${cur}) ) ;;
                        --module)
                            # module completion
                            modules=$(rerun:modules)

                            COMPREPLY=( $(compgen -W "$modules" -- ${cur}) ) ;;
                        --command)
                            # command completion
                            module=$(rerun:parse:module ${COMP_WORDS[*]} )
                            [ -n "$module" ] && {
                                commands=$(rerun:module:commands ${module})
                                COMPREPLY=( $(compgen -W "$commands" -- ${cur}) ) 
                            }
                            ;;
                    esac
                    return 0
            	fi
            fi
        else
        	# Show the remaining/unused option choices
            remaining=$(rerun:options:remaining "$cntx_options" "$options")
            COMPREPLY=( $(compgen -W "$remaining" -- ${cur}) )

	    fi
	    return 0
    fi
}
# register the _rerun completion function
complete -F _rerun rerun

#
# This is Free Software distributed under the Apache 2 license.
: