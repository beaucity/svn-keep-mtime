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
#      0.7.1
#
#
# ============================================================================


##############################################################################
# Configuration
##############################################################################

SVN_KMT_VERSION="0.7.1"

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
    svn_kmt=$(dirname "$svn")/svn_kmt
    svn_kmt_org=$(dirname "$svn")/svn_kmt_org

    if [ -L "$svn" ] && [ "$(readlink "$svn")" = "$svn_kmt" ] && [ -x "$svn_kmt" ] && [ -x "$svn_kmt_org" ]; then
        return 0
    fi

    return 1
}

kmt_has_been_uninstalled()
{
    svn=$(find_command svn) || return 1
    svn_kmt=$(dirname "$svn")/svn_kmt
    svn_kmt_org=$(dirname "$svn")/svn_kmt_org

    if [ -L "$svn" ] && [ "$(readlink "$svn")" = "$svn_kmt" ]; then
        log "Linked with $svn -> $svn_kmt not removed completely"
        return 1
    fi

    if [ -f "$svn_kmt" ]; then
        log "svn_kmt not removed completely"
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
    kmt_is_installed && echo "SVN Keep MTime is already installed." && return 1

    [ -z "$SVN" ] && echo "svn not found" && return 1

    svn="$(dirname "$SVN")/svn"
    svn_kmt="$(dirname "$svn")/svn_kmt"
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
    kmt_has_been_uninstalled && echo "SVN Keep MTime is not installed yet." && return 1

    svn="$(dirname "$SVN")/svn"
    [ -z "$svn" ] && echo "svn not found" && return 1

    svn_kmt="$(dirname "$svn")/svn_kmt"
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
        #don't use option use-commit-times=yes anymore, in some build of svn(eg. 1.7.14 (r1542130)), it will update the file mtime as commit time when just
        #file:mtime metadata has changed, this may case the time conflicting check failure.
#            LC_MESSAGES=C "$SVN" --config-option config:miscellany:use-commit-times=yes "$@"
            LC_MESSAGES=C "$SVN" "$@"
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
            "\?*"|X*|D*|C*|" C"|"Su"|"  "w2)
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
                echo "$line"
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

        [ -n "$str" ] && while IFS= read -r line
            do
                file=$line

                if [ -f "$dir" ]; then
                    file=$dir
                else
                    [ "$dir" != "."  ] && file="$dir/$file"
                fi

                if [ -e "$file" ]; then
                    echo "$file"
                else
                    #maybe deleted, ignore it
                    log "file not exists: '$file', line: '$line'"
                    continue
                fi

            done << EOF
$str
EOF
    done
    return 0
}


kmt_main()
{
    if [ $# = 0 ]; then
        echo "Invalid command"
        return 1
    fi

    cmd=$1

    shift

    checked_count=0
    completed_count=0
    to_commit_count=0
    to_restore_count=0
    effected_count=0
    conflict_count=0
    nometa_copy_count=0

    if [ "$cmd" = "commit" ] || [ "$cmd" = "restore" ]; then
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
            echo "Please commit your changes before running kmt-complete."
            return 1
        fi
    fi

    case $cmd in
        scan)
            echo "Scanning file mtime status of versioned files..."
            ;;
        show_commit)
            echo "Listing files to complete metadata..."
            ;;
        show_restore)
            echo "Listing files to restore..."
            ;;
        show_completed)
            echo "Listing completed files..."
            ;;
        show_working_copy)
            echo "Listing working copy files without metadata..."
            ;;
        show_conflict)
            echo "Listing conflicting files..."
            ;;
        commit)
            echo "Committing file:mtime metadata..."
            ;;
        restore)
            echo "Restoring file:mtime metadata..."
            ;;
        resolve_conflict)
            echo "Resolve mtime conflicting ..."
            ;;
        *)
            echo "Invalid command $cmd"
            return 1
          ;;

    esac

    if ! str=$(get_versioned_files_list "$@"); then
        echo "$str"
        return 1
    fi

    [ -n "$str" ] && while IFS= read -r file
    do
        log "file: $file"

        if [ -e "$file" ]; then

            checked_count=$(expr "${checked_count}" + 1)

            if ! file_ts=$(get_file_mtime "$file"); then
                echo "$file_ts"
                return 1
            fi

            [ -z "$file_ts" ] && echo "Get file mtime failed: '$file'" && return 1

            ! prop_ts=$(svn_prop_get "$file") && prop_ts=

            if [ -n "$prop_ts" ]; then
                [ "$cmd" = "show_working_copy" ] || [ "$cmd" = "commit" ] || [ "$cmd" = "show_commit" ] && continue

                if [ "$file_ts" = "$prop_ts" ]; then
                    [ "$cmd" = "show_completed" ] && echo "Completed $(format_timestamp "$file_ts") $file"
                    completed_count=$(expr "${completed_count}" + 1)
                    continue
                fi

                if [ "$file_ts" -gt "$prop_ts" ]; then
                    if [ "$cmd" = "restore" ]; then
                        ! restore_a_file_mtime "$file" "$prop_ts" && echo "Restore failed $(format_timestamp "$prop_ts") '$file'" && return 1
                        echo "Restoring mtime $(format_timestamp "$prop_ts") '$file'"
                        effected_count=$(expr "${effected_count}" + 1)
                    else
                        [ "$cmd" = "show_restore" ] && echo "To Restore $(format_timestamp "$file_ts") $file"
                        to_restore_count=$(expr "${to_restore_count}" + 1)
                    fi
                else
                    if [ "$cmd" = "resolve_conflict" ]; then
                        ! str=$(save_a_file_mtime "$file" "$file_ts") && echo "$str" && return 1
                        echo "Resolve conflicting mtime $(format_timestamp "$prop_ts") replace with $(format_timestamp "$file_ts") '$file'"
                        effected_count=$(expr "${effected_count}" + 1)
                    else
                        conflict_count=$(expr "${conflict_count}" + 1)
                        [ "$cmd" = "show_conflict" ] && echo "Conflict mtime repos: $(format_timestamp "$prop_ts") local: $(format_timestamp "$file_ts") $file"
                    fi
                fi
            else
                [ "$cmd" = "show_completed" ] || [ "$cmd" = "restore" ] || [ "$cmd" = "show_restore" ] ||
                 [ "$cmd" = "show_conflict" ] || [ "$cmd" = "resolve_conflict" ] && continue

                version_ts=$(get_versioned_timestamp "$file")
                if [ -z "$version_ts" ]; then
                    log "get_versioned_timestamp failed: $file"
                    continue
                fi

                if [ "$file_ts" -ge "$version_ts" ]; then
                    [ "$cmd" = "show_working_copy" ] && echo "Working Copy $(format_timestamp "$file_ts") $file"
                    nometa_copy_count=$(expr "${nometa_copy_count}" + 1)
                else
                    if [ "$cmd" = 'commit' ]; then
                        ! save_a_file_mtime "$file" "$file_ts" && echo "Commit mtime failed $(format_timestamp "$file_ts") '$file'" &&  return 1
                        echo "Committing mtime $(format_timestamp "$file_ts") '$file'"
                        effected_count=$(expr "${effected_count}" + 1)
                    else
                        [ "$cmd" = "show_commit" ] && echo "To Commit $(format_timestamp "$file_ts") $file"
                        to_commit_count=$(expr "${to_commit_count}" + 1)
                    fi
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

    if [ "$cmd" = "scan" ]; then
        cat << EOF

Summary

    Checked:      $checked_count versioned files

    To complete:  $to_commit_count files should commit metadata with local file mtime
    Completed:    $completed_count files with file:mtime metadata

    To restore:   $to_restore_count files should restore local file mtime with metadata
    No metadata:  $nometa_copy_count working files can not restore local file mtime because of no metadata

    Conflict:     $conflict_count files which the local file mtime is conflicting with the metadata in the repos
EOF
    elif [ "$cmd" = 'commit' ]; then
        if [ "$effected_count" = 0 ]; then
            echo "No files to commit."
        else
            if svn_call commit "$@" -m "Completed file mtime for $effected_count files"; then
                echo "Committed ${effected_count} files successfully."
                completed_count=$(expr "${completed_count}" + "${effected_count}")
            else
                echo "Commit failed."
                return 1
            fi
        fi
    elif [ "$cmd" = 'resolve_conflict' ]; then
        if [ "$effected_count" = 0 ]; then
            echo "No files to resolve."
        else
            if svn_call commit "$@" -m "Resolved file mtime for $effected_count files"; then
                echo "Resolved ${effected_count} files successfully."
                completed_count=$(expr "${completed_count}" + "${effected_count}")
            else
                echo "Commit failed."
                return 1
            fi
        fi
    elif [ "$cmd" = 'restore' ]; then
        if [ "$effected_count" = 0 ]; then
            echo "No files restored."
        else
            echo "Restored ${effected_count} files successfully."
            completed_count=$(expr "${completed_count}" + "${effected_count}")
        fi
    else
        echo "Done."
    fi

    return 0
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

    now_ts=$(date +%s)
    if [ "$file_ts" -gt "$now_ts" ]; then
        echo "The file mtime can not be committed, because it is in the future. $(format_timestamp "$file_ts") $file"
        return 2
    fi

    ! str=$(svn_call status "$file") && echo "Get status failed. $file" && return 1
    [ -n "$str" ] && echo "$str" | grep -e "^C.*$str" && log "Has conflict $file" && return 0

#    [ -n "$file" ] && echo "tests false" && return 1 #for tests

    prop_ts=$(svn_prop_get "$file")

    if [ -n "$prop_ts" ]; then
        if [ "$prop_ts" = "$file_ts" ]
        then
            log "same mtime: $file"
            return 0
        fi

        if [ "$prop_ts" -gt "$file_ts" ]; then
            if [ -n "$str" ] && echo "$str" | grep -e "^M.*$file"; then
                echo "The file mtime can not be committed, because of the content has been modified but mtime is before than the existing metadata $(format_timestamp "$prop_ts"). $(format_timestamp "$file_ts") $file"
                return 2
            fi
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

            if ! str=$(save_a_file_mtime "$file" "$file_ts"); then
                echo "$str"
                log "Set mtime $(format_timestamp "$file_ts") $file failed!"
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

##############################################################################
# Command Handler
##############################################################################


on_read()
{
    while IFS= read -r line
    do
        flag=$(echo "$line" | grep -o '^ *[^ ]*')

        case "$flag" in
#           GU   --??
            A|AA|AU|" U"|U|UU|Restored|Reverted|Sending|Adding)

                case "$flag" in
                    Restored|Reverted)
                        p1=$(echo "$line" | sed -E 's/^([^ ]* *).*/\1/')
                        file=$(echo "$line" | sed "s/[^ ]* *//;s/^'//;s/'$//")
                        ;;

                    Sending|Adding)
                        p1=$(echo "$line" | cut -c 1-15)
                        file=$(echo "$line" | cut -c 16-)
                        ;;

                    A|AA|AU|U|" U"|UU):
                        p1=$(echo "$line" | cut -c 1-5)
                        file=$(echo "$line" | cut -c 6-)
                        ;;
                esac

                if [ ! -e "$file" ]; then
                    p1=$(echo "$line" | sed -E 's/^([^ ]* *).*/\1/')
                    file=$(echo "$line" | sed -E 's/^[^ ]* *//')
                    if [ ! -e "$file" ]; then
                        echo "$line"
                        echo "File not exists: '$file'"
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

                if [ -z "$prop_ts" ]; then
                    echo "$line"
                    continue
                fi

                ! is_timestamp "$prop_ts" && echo "Invalid timestamp $prop_ts '$file'" && return 1

                if [ "$flag" != "Sending" ] && [ "$flag" != "Adding" ]; then
                    if [ "$flag" = " U" ]; then
                        #the mtime was been completed
                        if ! file_ts=$(get_file_mtime "$file"); then
                            echo "$file_ts"
                            return 1
                        fi

                        log "prop: $(format_timestamp "$prop_ts"), local: $(format_timestamp "$file_ts")  $file"

                        if [ "$prop_ts" -gt "$file_ts" ]; then
                            #the file:mtime metadata completed may wrong, the local is the right one maybe
                            echo "${p1}Conflicting mtime $(format_timestamp "$prop_ts") with local $(format_timestamp "$file_ts")  $file"
                            log "Conflicting mtime  $(format_timestamp "$prop_ts")"
                            continue
                        fi
                    fi

                    restore_a_file_mtime "$file" "$prop_ts" || return 1

                    if [ "$flag" = "Restored" ] || [ "$flag" = "Reverted" ]; then
                        file="'$file'"
                    fi
                fi

                echo "${p1}$(format_timestamp "$prop_ts") $file"

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

kmt_main_handler()
{
    show_version

    while true
    do
        cat << EOF

Select an operation:

    1   -- Scan the file:mtime status
    2   -- List the completed files $completed_count
    3   -- List the files need to complete metadata $to_commit_count
    4   -- List the files need to restore mtime $to_restore_count
    5   -- List the working copy files without file:mtime metadata $nometa_copy_count
    6   -- List the files which the file mtime is conflicting with repos $conflict_count

    7   -- Complete file:mtime metadata ( with local file mtime ) $to_commit_count
    8   -- Restore local file mtime ( with the metadata in repos ) $to_restore_count
    9   -- Resolve mtime conflicting files ( try use local file mtime ) $conflict_count

  Other -- Exit

EOF
        read -r key

        case $key in

            1)
                cmd=scan    ;;

            2)
                cmd=show_completed  ;;

            3)
                cmd=show_commit ;;

            4)
                cmd=show_restore ;;

            5)
                cmd=show_working_copy ;;

            6)
                cmd=show_conflict ;;

            7)
                cmd=commit ;;

            8)
                cmd=restore ;;

            9)
                cmd=resolve_conflict ;;

            *)
                return 0 ;;

        esac

        echo ""



        ! kmt_main "$cmd" "$@" && return 1

    done

    return 0
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

    bn=$(basename "$0")
    case $cmd in
        "kmt-install"|"install"|"kmt-upgrade"|"upgrade")

            if [ "$bn" != "svn_kmt.sh" ]; then
                echo "Please run the command as follows:
    ./svn_kmt.sh $*
"
                return 1
            fi

        ;;
        "kmt-version") ;;
        *)
            if [ "$bn" = "svn_kmt.sh" ]; then
                if ! kmt_is_installed; then
                    echo "The SVN Keep MTime should be installed firstly,
please run the command as follows to install it:
    ./svn_kmt.sh kmt-install
"
                else
                    echo "Please run the command as follows:
    svn $*
"
                fi
                return 1
            fi
        ;;
    esac

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

        kmt|kmt-main)
            shift

            kmt_main_handler "$@"

            ;;

        kmt-complete)

            shift

            kmt_main "commit" "$@"

            ;;

        kmt-restore)

            shift

            kmt_main "restore" "$@"

            ;;

        kmt-version)

            show_version

            ;;

        kmt-install|install)

            shift

            kmt_install "$@"

            ;;

        kmt-uninstall)

            shift

            kmt_uninstall

            ;;

        kmt-upgrade|upgrade)

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
    [ "$(basename "$0")" = "svn_kmt" ] && [ -L "$(find_command "svn_kmt")" ] && SVN_KMT_DEBUG=1

    detect_platform || return 1

    detect_original_svn || return 1

    dispatch "$@"
}

main "$@"
