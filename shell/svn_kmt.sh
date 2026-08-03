#!/bin/sh
#
# ============================================================================
#
#  SVN Keep MTime
#
#  File:
#      svn_kmt.sh
#
#  Purpose:
#      SVN client wrapper. designed to preserve file modification time (`mtime`)
#      information during SVN operations.
#
#
#  Version:
#      0.6.8
#
# ============================================================================


##############################################################################
# Configuration
##############################################################################

SVN_KMT_VERSION="0.6.8"

FILE_MTIME_PROP="file:mtime"

SVN=""

PLATFORM=""


##############################################################################
# Utility
##############################################################################

log()
{
    ret=$?

    [ -z "$SVN_KMT_DEBUG" ] || echo "[-] $*" >&2

    return $ret
}

full_path_name()
{
    if [ $# = 0 ]; then
        return 1
    fi

    str="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" || return 1

    echo "$str"

    return 0
}

##############################################################################
# Platform
##############################################################################

detect_platform()
{
    case "$(uname -s)" in

        Linux*)
            PLATFORM="linux"
            ;;

        Darwin*)
            PLATFORM="macos"
            ;;

        *)
            echo "Unsupported platform"
            return 1
            ;;

    esac
}

##############################################################################
# Original SVN Detection
##############################################################################

find_command()
{
    bn="${1}"

    path=$(command -v "$bn" 2>/dev/null)

    if [ -x "$path" ]; then
        echo "$path"
    fi
}

kmt_is_installed()
{
    svn=$(find_command svn) || return 1
    svn_kmt=$(dirname "$svn")/svn_kmt.sh
    svn_kmt_org=$(dirname "$svn")/svn_kmt_org

    if [ -L "$svn" ] && [ "$(readlink "$svn")" = "$svn_kmt" ] && [ -x "$svn_kmt" ] && [ -x "$svn_kmt_org" ]; then
        return 0
    fi

    return 1
}

kmt_has_been_uninstalled()
{
    svn=$(find_command svn) || return 1
    svn_kmt=$(dirname "$svn")/svn_kmt.sh
    svn_kmt_org=$(dirname "$svn")/svn_kmt_org

    if [ -L "$svn" ] && [ "$(readlink "$svn")" = "$svn_kmt" ]; then
        log "Linked with $svn -> $svn_kmt not removed completely"
        return 1
    fi

    if [ -f "$svn_kmt" ]; then
        log "svn_kmt.sh not removed completely"
        return 1
    fi

    if [ -f "$svn_kmt_org" ]; then
        log "svn_kmt_org not removed completely"
        return 1
    fi

    return 0
}

detect_original_svn()
{
    if ! SVN=$(find_command svn); then
        echo "Original svn executable not found."
        return 1
    fi

    kmt_is_installed && SVN=$(dirname "$SVN")/svn_kmt_org

    return 0
}

kmt_install()
{
    if [ "$(basename "$0")" != "svn_kmt.sh" ]; then
        printf "Please run the command as follows:
        ./svn_kmt.sh kmt-install
"
        return 1
    fi

    kmt_is_installed && echo "SVN Keep MTime is already installed." && return 1

    [ -z "$SVN" ] && echo "svn not found" && return 1

    svn="$(dirname "$SVN")/svn"
    svn_kmt="$(dirname "$svn")/svn_kmt.sh"
    svn_kmt_org="$(dirname "$svn")/svn_kmt_org"

    ! cp_from=$(full_path_name "$0") && echo "Invalid installation script file" && return 1

    if [ ! -f "$svn_kmt" ]; then
        if [ "$1" = "--link" ]; then
            if ! ln -s "$cp_from" "$svn_kmt"; then    #link mode
                echo "Link $svn_kmt -> $cp_from failed!"
                return 1
            else
                echo "Linked $svn_kmt -> $cp_from successfully."
            fi
        else
            if ! cp "$cp_from" "$svn_kmt"; then
                echo "Copy $cp_from to $svn_kmt failed!"
                return 1
            else
                echo "Copied $cp_from to $svn_kmt successfully."
            fi

            if ! chmod +x "$svn_kmt"; then
                echo "Add executable permission to $svn_kmt failed!"
                rm -f "$svn_kmt" || echo "Rollback: remove $svn_kmt failed."
                return 1
            else
                echo "Added executable permission to $svn_kmt successfully."
            fi
        fi
    fi

    if ! mv "$svn" "$svn_kmt_org"; then
        echo "Move $svn to $svn_kmt_org failed!"
        rm -f "$svn_kmt" || echo "Rollback: remove $svn_kmt failed."
        return 1
    else
        echo "Moved $svn to $svn_kmt_org successfully."
    fi

    if ! ln -s "$svn_kmt" "$svn"; then
        echo "Link $svn -> $svn_kmt failed!"

        mv "$svn_kmt_org" "$svn" || echo "Rollback: Restore $svn_kmt_org to $svn failed."

        rm -f "$svn_kmt" || echo "Rollback: remove $svn_kmt failed."

        return 1
    else
        echo "Linked $svn -> $svn_kmt successfully."
    fi

    echo "SVN Keep MTime has been installed successfully."

    return 0
}

kmt_uninstall()
{
    if [ "$(basename "$0")" != "svn" ]; then
        printf "Please run the command as follows:
        svn kmt-uninstall
"
        return 1
    fi

    kmt_has_been_uninstalled && echo "SVN Keep MTime is not installed yet." && return 1

    svn="$(dirname "$SVN")/svn"
    [ -z "$svn" ] && echo "svn not found" && return 1

    svn_kmt="$(dirname "$svn")/svn_kmt.sh"
    svn_kmt_org="$(dirname "$svn")/svn_kmt_org"

    if ! rm "$svn"; then
        echo "Remove $svn failed!" && return 1
    else
        echo "Removed $svn successfully."
    fi

    if ! mv "$svn_kmt_org" "$svn"; then
        echo "Move $svn_kmt_org to $svn failed!"
        ln -s "svn_kmt" "$svn" && echo "Rollback: re-linked $svn to $svn_kmt successfully." || echo "Rollback: re-link $svn to $svn_kmt failed!"
        return 1
    else
        echo "Moved $svn_kmt_org to $svn successfully."
    fi

    rm -f "$svn_kmt" && echo "Removed $svn_kmt successfully" || echo "Warning: remove $svn_kmt failed, ignore it"

    echo "SVN Keep MTime has been uninstalled successfully."

    return 0
}

kmt_upgrade()
{
    if [ "$(basename "$0")" != "svn_kmt.sh" ]; then
        printf "Please run the command as follows:
        ./svn_kmt.sh kmt-upgrade
"
        return 1
    fi

    if kmt_is_installed; then
        echo "SVN Keep MTime is already installed, uninstall it ..."

        if ! svn kmt-uninstall; then
            echo "Upgrade failed."
            return 1
        fi

        detect_original_svn
        if [ -z "$SVN" ]; then
            echo "Original svn executable not found."
            return 1
        fi

        ! kmt_install "$@" && echo "Upgrade failed." && return 1

        echo "SVN Keep MTime has been upgraded successfully."

        return 0

    else
        echo "SVN Keep MTime is not installed, installing now."
        kmt_install && return 0 || return 1
    fi
}

##############################################################################
# SVN API
##############################################################################

svn_call()
{
    log "$SVN $*"

    case "$1" in
        update|up|checkout|co|revert|switch)
            LC_MESSAGES=C "$SVN" --config-option config:miscellany:use-commit-times=yes "$@"
            ;;
        *)
            LC_MESSAGES=C "$SVN" "$@"
            ;;
    esac
}


svn_prop_get()
{
    svn_call propget \
        "$FILE_MTIME_PROP" \
        "$1" 2>/dev/null
}


svn_prop_set()
{
    svn_call propset \
        "$FILE_MTIME_PROP" \
        "$2" \
        "$1"
}


##############################################################################
# Time Functions
##############################################################################

is_timestamp()
{
    echo "$1" | grep -Eq '^[0-9]+$'
}

format_timestamp()
{
    ts=$1
    case "$PLATFORM" in

        linux)

            date -d @"$ts" +"%Y-%m-%d %H:%M:%S"
            ;;


        macos)

            date -r "$ts" "+%Y-%m-%d %H:%M:%S"

            ;;

        *)

            return 1
            ;;

    esac
}

get_file_mtime()
{
    file="$1"

    case "$PLATFORM" in

        linux)

            if ! stat -c %Y "$file"; then
                echo "file: '$file'"
                return 1
            fi
            ;;


        macos)

            if ! stat -f %m "$file"; then
                echo "file: '$file'"
                return 1
            fi
            ;;

        *)

            return 1
            ;;

    esac

    return 0
}

set_file_mtime()
{
    file="$1"
    timestamp="$2"

    is_timestamp "$timestamp" || return 1

    case "$PLATFORM" in

        linux)

            touch -m -d "@$timestamp" "$file" || return 1

            ;;

        macos)

            touch -m \
                -t "$(date -r "$timestamp" "+%Y%m%d%H%M.%S")" \
                "$file" || return 1

            ;;

        *)

            return 1
            ;;

    esac
}


##############################################################################
# Working Copy Functions
##############################################################################

get_versioned_timestamp() {
    path="${1:-.}"

    dt=$(svn_call info --xml "$path" 2>/dev/null |
        sed -n 's:.*<date>\(.*\)</date>.*:\1:p' |
        head -n1)

    [ -z "$dt" ] && return 0

    case "$PLATFORM" in
        linux)
            date -u -d "$dt" +%s
            ;;
        macos)
            dt="${dt%%.*}Z"
            date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$dt" +%s
            ;;
    esac
}

get_files_2_commit()
{
    if ! str=$(svn_call status "$@"); then
        echo "$str"
        log "Failed to get SVN status."
        return 1
    fi

    [ -n "$str" ] && while IFS= read -r line
    do
        flag=$(echo "$line" | cut -c 1-2)
        case "$flag" in
            \?*|X*|D*)
                continue
                ;;
            *)
                log "$rest"
                ;;
        esac

        file=$(echo "$line" | sed 's/^\w* *//')

        if [ ! -e "$file" ]; then
            file=$(echo "$line" | cut -c 9-)
            if [ ! -e "$file" ]; then
                echo "Invalid working file: '$file'"
                log "Invalid line: '$line'"
                return 1
            fi
        fi

        echo "$file"

    done << EOF
$str
EOF

    return 0
}

get_versioned_files_list()
{
    if [ $# -eq 0 ]
    then
        set -- .
    fi

    for dir in "$@";
    do
        # svn ls -R returns paths relative to the given directory

        if ! str=$(svn_call ls -R "$dir"); then
            echo "$str"
            log "Get versioned files list failed"
            return 1
        fi

        [ -n "$str" ] && while IFS= read -r rest
            do
#                file=$(echo "$rest" | sed 's/^ *//')
                file=$rest

                [ -f "$dir" ] && file=$dir || file="$dir/$file"

                if [ -f "$file" ]; then
                    echo "$file"
                elif [ ! -d "$file" ]; then
                    echo "Invalid file: '$file', rest: '$rest'"
                    return 1
                fi
            done << EOF
$str
EOF
    done
    return 0
}


# function complete_file_mtime

# return values

# for commit mode
# 0 -- commit successful
# 1 -- commit failed
#
# for the others mode
# 0 -- exit by user
# 1 -- more command by user

complete_file_mtime()
{
    if [ $# = 0 ]; then
        echo "Invalid mode"
        return 1
    fi

    cmd=$1

    shift

    if [ $# = 0 ]
    then
        set -- .
    fi

    while [ -n "$cmd" ]
    do
        echo ""

        case $cmd in
            scan)
                echo "Scanning SVN files..."
                ;;
            show_commit)
                echo "Showing files to commit..."
                ;;
            show_completed)
                echo "Showing completed files..."
                ;;
            show_working_copy)
                echo "Showing working copy files..."
                ;;
            show_error)
                echo "Showing error files..."
                ;;
            commit)
                echo "Committing file:mtime metadata..."
                ;;
            *)
                echo "Invalid command $cmd"
                return 1
              ;;

        esac

        checked_count=0
        already_set_count=0
        to_commit_count=0
        error_count=0
        working_copy_count=0

        if ! str=$(get_versioned_files_list "$@"); then
            echo "$str"
            return 1
        fi

        [ -n "$str" ] && while IFS= read -r file
        do
            log "file: $file"

            if [ -f "$file" ]; then

                checked_count=$(expr "${checked_count}" + 1)

                if ! file_ts=$(get_file_mtime "$file"); then
                    echo "$file_ts"
                    return 1
                fi

                [ -z "$file_ts" ] && echo "get_file_mtime failed: $file" && error_count=$(expr "${error_count}" + 1) && continue

                prop_ts=$(svn_prop_get "$file")
                if [ -n "$prop_ts" ] && [ "$file_ts" = "$prop_ts" ]; then

                    [ "$cmd" = "show_completed" ] && echo "Completed $(format_timestamp "$file_ts") $file"

                    already_set_count=$(expr "${already_set_count}" + 1)

                    continue
                fi

                version_ts=$(get_versioned_timestamp "$file")
                if [ -z "$version_ts" ]; then
                    [ "$cmd" = "show_error" ] && echo "Error $(format_timestamp "$file_ts") $file"
                    log "get_versioned_timestamp failed: $file"
                    error_count=$(expr "${error_count}" + 1)
                    continue
                fi

                if [ "$file_ts" -ge "$version_ts" ]; then
                    [ "$cmd" = "show_working_copy" ] && echo "Working Copy $(format_timestamp "$file_ts") $file"

                    working_copy_count=$(expr "${working_copy_count}" + 1)

                else
                    to_commit_count=$(expr "${to_commit_count}" + 1)

                    [ "$cmd" = "show_commit" ] && echo "To Commit $(format_timestamp "$file_ts") $file"

                    if [ "$cmd" = 'commit' ]; then

                        echo "Committing mtime $(format_timestamp "$file_ts") $file"

                        save_a_file_mtime "$file" "$file_ts" || return 1

                    fi
                fi
            else
                if [ ! -d "$file" ]; then
                    echo "Invalid file '$file'"
                    return 1
                fi
            fi

        done << EOF
$str
EOF

        if [ "$cmd" = 'commit' ]; then

            [ "$to_commit_count" = 0 ] && echo "No files to commit" && return 0

            if svn_call commit "$@" -m 'complete file mtime'; then
                echo "Committed ${to_commit_count} files successfully."
                return 0
            fi

            echo "Commit failed"
        fi

        if show_result_and_get_command "$checked_count" "$already_set_count" "$working_copy_count" "$error_count" "$to_commit_count"; then
            return 0
        fi

        if [ -z "$cmd" ]; then
            echo "Invalid command: $cmd"
        fi

    done

    return 0
}

show_result_and_get_command()
{
    checked_count=$1
    already_set_count=$2
    working_copy_count=$3
    error_count=$4
    to_commit_count=$5

    skip_count=$(expr "${already_set_count}" + "${working_copy_count}" + "${error_count}")

    cat << EOF
    Done.
    Checked:   $checked_count
    Skip       $skip_count (Completed: $already_set_count, Working Copy: $working_copy_count, Error: $error_count)
    To Commit: $to_commit_count
EOF

    if [ "$checked_count" = "0" ]; then
        log "no files"
        return 0
    fi

    cat << EOF

Select an operation:

    1   -- Commit file:mtime metadata ($to_commit_count)
    2   -- Rescan
    3   -- Show files to commit ($to_commit_count)
    4   -- Show completed files ($already_set_count)
    5   -- Show working copy files ($working_copy_count)
    6   -- Show error files ($error_count)

  Other -- Exit

EOF
    read -r key

    cmd=

    case $key in

        1)
            cmd=commit
        ;;

        2)
            cmd=scan
        ;;

        3)
            cmd=show_commit
        ;;

        4)
            cmd=show_completed
        ;;

        5)
            cmd=show_working_copy
        ;;

        6)
            cmd=show_error
        ;;

        *)
            return 0
        ;;

    esac

    return 1
}

##############################################################################
# Save File Mtime
##############################################################################

save_a_file_mtime()
{
    file=$1

    [ -z "$file" ] && return 1

    file_ts=$2

    [ -z "$file_ts" ] && return 1

#    [ -n "$file" ] && echo "test false" && return 1 #for test

    old=$(svn_prop_get "$file")

    if [ -n "$old" ]; then
        if [ "$old" = "$file_ts" ]
        then
            log "same mtime: $file"
            return 0
        fi

        if [ "$old" -gt "$file_ts" ]; then
            echo "Error: The old property mtime is later than current working copy $old, $file_ts"
            return 1
        fi
    fi

    if ! svn_prop_set \
        "$file" \
        "$file_ts" \
        >/dev/null  ; then
          log "Set mtime $(format_timestamp "$file_ts") $file failed!"
          return 1
    fi

    log "Set mtime $(format_timestamp "$file_ts") $file successfully."

    return 0
}

save_file_mtime()
{
    opt_key=
    has_dir=0

    for p in "$@";
    do
        case "$p" in
            -*)
                opt_key=$p
                #Skip option key
                continue
            ;;

            *)
                if [ "$opt_key" = '-m' ]; then
                  #Skip comment content
                  opt_key=
                  continue
                else
                    if [ -n "$opt_key" ] && [ ! -e "$p" ]; then
                        #It is mostly a option value, skip it
                        opt_key=
                        continue
                    fi
                    opt_key=
                fi
            ;;
        esac

        has_dir=1

        if ! str="$(get_files_2_commit "$p")"; then
            echo "$str"
            log "Failed to get files list to commit"
            return 1
        fi
#        log "str: '$str'"
        [ -n "$str" ] && while IFS= read -r file
        do
            [ -z "$file" ] && continue

            if ! file_ts=$(get_file_mtime "$file"); then
                log "$file_ts"
                log "'$file'"
                return 1
            fi

            [ -z "$file_ts" ] && echo "Get mtime failed $file" && return 1

            if ! save_a_file_mtime "$file" "$file_ts"; then
                echo "Set mtime $(format_timestamp "$file_ts") $file failed!"
                log "line: '$file'"
                return 1
            fi
        done << EOF
$str
EOF
    done

    if [ $has_dir = 0 ]; then
        if [ "$#" -gt 1 ]; then     #prevert death loop
            save_file_mtime "." || return 1
        fi
    fi

    return 0
}

##############################################################################
# Restore File Mtime
##############################################################################
restore_a_file_mtime()
{
    file=$1
    prop_ts=$2

    [ -z "$file" ] && return 1

    [ -z "$prop_ts" ] && return 1

    if ! set_file_mtime "$file" "$prop_ts"; then
        log "Failed to restore mtime $(format_timestamp "$prop_ts") $file"
    else
        log "Restored mtime $(format_timestamp "$prop_ts") $file successfully"
    fi

    return $ret
}

restore_file_mtime()
{
    log "restore file mtime"
    checked_count=0
    restore_count=0
    failed_count=0
    if ! str=$(get_versioned_files_list "$@"); then
        echo "$str"
        return 1
    fi

    [ -n "$str" ] && while read -r file
    do
        checked_count=$(expr "${checked_count}" + 1)

        if ! file_ts=$(get_file_mtime "$file"); then
            echo "$file_ts"
            return 1
        fi

        prop_ts=$(svn_prop_get "$file")

        if [ -z "$prop_ts" ]; then
            log "no property to restore"
            continue
        elif [ "$file_ts" = "$prop_ts" ]; then
            log "already restored $file"
            continue
        fi

        if restore_a_file_mtime "$file" "$prop_ts"; then
            echo "Restored mtime $(format_timestamp "$prop_ts") $file"
            restore_count=$(expr "${restore_count}" + 1)
        else
            echo "Restore Failed $(format_timestamp "$prop_ts") $file"
            failed_count=$(expr "${failed_count}" + 1)
        fi

    done << EOF
$str
EOF

    echo "Restore completed. Checked: $checked_count, Successful: $restore_count, Failed: ${failed_count}"

    return 0
}


##############################################################################
# Command Handler
##############################################################################


on_read()
{
#    while IFS= read -r line
#    while read -r flag rest
    while IFS= read -r line
    do
        flag=$(echo "$line" | cut -d ' ' -f 1)
        rest=$(echo "$line" | sed 's/^[^ ]*//')

        case "$flag" in
#           GU   --??
            A|AA|AU|U|UU|Restored|Reverted|Sending|Adding)

                file=$(echo "$rest" | sed "s/^ *//")

                log "flag: '$flag', rest: '$rest', file: '$file'"

                if [ ! -e "$file" ]; then
                    case "$flag" in
                        Restored|Reverted)
                            file=$(echo "$file" | sed "s/^'//; s/'$//")
                            ;;

                        Sending|Adding)
                            file=$(echo "$line" | cut -c 16-)
                            ;;

                        A|AA|AU|U|UU):
                            file=$(echo "$line" | cut -c 6-)
                            ;;

                    esac

                    if [ ! -e "$file" ]; then
                        echo "File not exists: '$file'"
                        log "line: '$line'"
                        return 1
                    fi
                fi

                if ! prop_ts=$(svn_prop_get "$file"); then
                    if [ "$flag" = "Sending" ] || [ "$flag" = "Adding" ]; then
                        echo "$prop_ts"
                        log "Get file:mtime failed '$file'"
                        return 1
                    else
                        continue
                    fi
                fi

                log "Process timestamp $prop_ts '$file'"

                ! is_timestamp "$prop_ts" && echo "Invalid timestamp $prop_ts '$file'" && return 1

                if [ "$flag" != "Sending" ] && [ "$flag" != "Adding" ]; then
                    restore_a_file_mtime "$file" "$prop_ts" || return 1
                fi

                rest="$(format_timestamp "$prop_ts") $rest"
                echo "$flag $rest"
                ;;
            *)

                echo "$line"
                ;;
        esac

    done

    return 0
}

command_handler()
{
    cmd=$1

    log "$cmd start"

    if [ "$cmd" = "commit" ]; then
        shift

        ! str=$(save_file_mtime "$@") && echo "$str" && return 1

        ! str=$(svn_call "$cmd" "$@") && echo "$str" && return 1

    else
        ! str=$(svn_call "$@") && echo "$str" && return 1
    fi

    [ -z "$str" ] && return 0

    on_read << EOF
$str
EOF

    ret=$?

    log "$cmd completed $ret"

    return $ret
}


##############################################################################
# Extension Command
##############################################################################

complete_file_mtime_handler()
{
    for p in "$@"; do
        [ ! -e "$p" ] && echo "$p is not a valid directory or file" && return 1
    done

    if ! str=$(get_files_2_commit "$@"); then
        echo "$str"
        return 1
    fi

    has_uncommitted=0
    [ -n "$str" ] && while read -r file
    do
        if [ -f "$file" ]; then
            echo "Uncommitted changes detected: $file"
            has_uncommitted=1
        fi
    done << EOF
$str
EOF

    if [ $has_uncommitted = 1 ]; then
        echo "Please commit your changes before running kmt_complete."
        return 1
    fi

    complete_file_mtime "scan" "$@" && return 0 || return 1

}

restore_file_mtime_handler()
{
    for p in "$@"; do
        [ ! -e "$p" ] && echo "$p is not a valid directory or file" && return 1
    done

    restore_file_mtime "$@" && return 0 || return 1

}

##############################################################################
# Version
##############################################################################

show_version()
{
    echo "SVN Keep MTime"
    echo "version ${SVN_KMT_VERSION}"
}

##############################################################################
# Dispatcher
##############################################################################

dispatch()
{
    if [ $# -eq 0 ]
    then
        svn_call "$@"
        return $?
    fi

    cmd="$1"

    case "$cmd" in

        ci|commit)

            shift

            command_handler commit "$@"

            ;;


        up|update)

            shift

            command_handler update "$@"

            ;;

        revert)

            shift

            command_handler revert "$@"

            ;;

        co|checkout)

            shift

            command_handler checkout "$@"

            ;;

        kmt_complete)

            shift

            complete_file_mtime_handler "$@"

            ;;

        kmt_restore)

            shift

            restore_file_mtime_handler "$@"

            ;;

        kmt-version)

            show_version

            ;;

        kmt-install)

            shift

            kmt_install "$@"

            ;;

        kmt-uninstall)

            shift

            kmt_uninstall

            ;;

        kmt-upgrade)

            shift

            kmt_upgrade "$@"

            ;;

        *)

            svn_call "$@"

            ;;

    esac

}

##############################################################################
# Main
##############################################################################

main()
{
    [ "$(basename "$0")" = "svn_kmt.sh" ] && SVN_KMT_DEBUG=1

    detect_platform || return 1

    detect_original_svn || return 1

    dispatch "$@"
}

main "$@"
