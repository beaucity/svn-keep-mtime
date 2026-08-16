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
#      0.7.8
#
#
# ============================================================================


##############################################################################
# Configuration
##############################################################################

SVN_KMT_VERSION="0.7.8"

FILE_MTIME_PROP="file:mtime"

SVN=""

PLATFORM=""

SCAN_BACKEND=

TZ_SECONDS=0

##############################################################################
# Utility
##############################################################################

log()
{
    ret=$?

    [ -z "$SVN_KMT_DEBUG" ] && return $ret

    [ -n "$log_ts" ] && tsd=$(time_diff "$(date +%s.%N)" "$log_ts") || tsd=$(date +%s)

    echo "[ + $tsd] $*" >&2

    log_ts=$(date +%s.%N)

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

float_diff() {
    a="$1" b="$2"

    case "$a" in
        *.*) ia="${a%%.*}"; fa=$(printf "%s" "${a#*.}000000" | cut -c 1-6 | sed 's/^0*//') ;;
        *) ia=$a; fa="0" ;;
    esac

    case "$b" in
        *.*) ib="${b%%.*}"; fb=$(printf "%s" "${b#*.}000000" | cut -c 1-6 | sed 's/^0*//') ;;
        *) ib=$b; fb="0" ;;
    esac

    [ "$(echo "$ia" | cut -c 1-1)" = "-" ] && sa='-1' && ia=$(echo "$ia" | cut -c 2-) || sa='1'
    [ "$(echo "$ib" | cut -c 1-1)" = "-" ] && sb='-1' && ib=$(echo "$ib" | cut -c 2-) || sb='1'

    log "$a, $b, $ia, $fa, $ib, $fb"
    ! diff=$(( (sa)*(ia * 1000000 + fa) - (sb)*(ib * 1000000 + fb) )) && echo "exp failed: $a $b $ia $fa $ib $fb" && return 1
    sign=""; [ "$diff" -lt 0 ] && sign="-" && diff=$(( -diff ))
    printf "%s%d.%06d" "$sign" $((diff / 1000000)) $((diff % 1000000))
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

get_url_timestamp() {
    url="$1"
    ! str=$(curl --connect-timeout 2 --max-time 3 -s -I "$url" 2>/dev/null) && return 1

    date_str=$(echo "$str" | grep -i "^Date:" | head -1 | sed 's/^[Dd][Aa][Tt][Ee]: //' | tr -d '\r\n')

    [ -z "$date_str" ] && echo "Request failed. $url" && return 1

    if [ "$PLATFORM" = "macos" ]; then
        clean=$(echo "$date_str" | sed 's/,//')
        ! LC_TIME=C date -j -f "%a %d %b %Y %H:%M:%S %Z" "$clean" +%s >/dev/null && return 1
    else
        ! LC_TIME=C date -d "$date_str" +%s 2>/dev/null && return 1
    fi

    return 0
}

detect_time_offset()
{
    max_offset=60

    dirs=$(select_arg_dirs "$@")
    url=
    while IFS= read -r dir
    do
        url=$(svn_call info "$dir" | grep '^URL:' | grep -oE 'http[s]?://[^/]*')
        [ -n "$url" ] && break
    done<<EOF
$dirs
EOF

    for web_server in "$url" "http://www.baidu.com" "http://www.google.com";
    do
        [ -z "$web_server" ] && continue

        ! server_ts=$(get_url_timestamp "$web_server") && echo "request failed $web_server" && continue

        now_ts=$(date +%s)
        diff=$((now_ts-server_ts))
        sign=$(echo "$diff" | cut -c 1-1 )
        diff=${diff#*-}

        if [ "$diff" -gt "$max_offset" ]; then
            echo "Local machine system time seems incorrect,
are you sure to continue? (y/N)"
            read -r key
            [ "$key" != "y" ] && return 1
        fi

        break
    done

    return 0
}

detect_time_zone()
{
    ! offset_str=$(date +%z) && echo "Get timezone failed." && return 1

    sign=$(echo "$offset_str" | cut -c 1-1)
    hh=$(echo "$offset_str" | cut -c 2-3 | sed 's/^0//' )

    mm=$(echo "$offset_str" | cut -c 4-5 | sed 's/^0//' )

    TZ_SECONDS=$((hh*3600 + mm*60))
    [ "$sign" = "-" ] && TZ_SECONDS=$((-TZ_SECONDS))

    return 0
}

##############################################################################
# Original SVN Detection
##############################################################################

find_command()
{
    ! path=$(command -v "${1}" 2>/dev/null) || [ ! -x "$path" ] && return 1

    echo "$path"

    return 0
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

auto_set_kmt_scan_backend()
{
    if str=$(find_command 'python3') || str=$(find_command 'python') || str=$(find_command 'python2'); then
        SCAN_BACKEND='python'
    elif [ -n "$(find_command 'join')" ] && [ -n "$(find_command 'awk')" ]; then
        SCAN_BACKEND='join'
    else
        SCAN_BACKEND='posix'
    fi
    return 0
}

set_kmt_scan_backend()
{
    p=$1
    SCAN_BACKEND="${p#*=}"
    [ -z "$SCAN_BACKEND" ] && ! auto_set_kmt_scan_backend && return 1

    case "$SCAN_BACKEND" in
        posix|join|python)
            ;;
        auto)
            auto_set_kmt_scan_backend
            ;;
        *)
            echo "Invalid scanning backend $SCAN_BACKEND"
            return 1
            ;;
    esac

    log "SCAN_BACKEND: $SCAN_BACKEND"

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
    svn_call propget "$FILE_MTIME_PROP" "$1@" 2>/dev/null
}

svn_prop_set()
{
    svn_call propset "$FILE_MTIME_PROP" "$2" "$1@"
}

##############################################################################
# Time Functions
##############################################################################

is_timestamp()
{
    echo "$1" | grep -Eq '^[0-9]+$'
}

format_timestamp() {
#    log "ts: $1, tz: $TZ_SECONDS"

    ts=$(($1 + ${2:-"$TZ_SECONDS"}))
    d=$((ts / 86400 + 1))
    s=$((ts % 86400))
    [ "$s" -lt 0 ] && s=$((s + 86400)) && d=$((d - 1))

    y=1970
    while true; do
        leap=0
        [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; } && leap=1
        days=365; [ "$leap" -eq 1 ] && days=366
        [ "$d" -gt "$days" ] || break
        d=$((d - days)); y=$((y + 1))
    done

    m=1
    while true; do
        leap=0
        [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; } && leap=1
        case "$m" in
            1|3|5|7|8|10|12) dm=31 ;;
            4|6|9|11) dm=30 ;;
            2) dm=$((leap ? 29 : 28)) ;;
        esac
        [ "$d" -gt "$dm" ] || break
        d=$((d - dm)); m=$((m + 1))
    done

    printf "%04d-%02d-%02d %02d:%02d:%02d" "$y" "$m" "$d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

get_file_mtime()
{
    file="$1"

    case "$PLATFORM" in

        linux)

            if ! stat -c %Y "$file"; then
                echo "get_file_mtime failed: '$file'"
                return 1
            fi
            ;;


        macos)

            if ! stat -f %m "$file"; then
                echo "get_file_mtime failed: '$file'"
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

get_timestamp()
{
    dt=$1

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

get_versioned_timestamp() {
    path="${1:-.}"

    dt=$(svn_call info --xml "$path@" 2>/dev/null |
        sed -n 's:.*<date>\(.*\)</date>.*:\1:p' |
        head -n1)

    [ -z "$dt" ] && return 1

    log "date: $dt"

    get_timestamp "$dt"
}

get_files_2_commit()
{
    dir=$1

    if ! str=$(svn_call status "$dir"); then
        echo "$str"
        log "Failed to get SVN status."
        return 1
    fi

    ret=0
    [ -n "$str" ] && while IFS= read -r line
    do
        log "$line"
        flag=$(echo "$line" | cut -c 1-2)
        case "$flag" in
            C*|*C)
                echo "$line"
                ret=2
                ;;
            A*|M*|' A'|' M')
                ;;
#            \?*|D*|X*|"Su"|"  ")
#                continue
#                ;;
            *)
                log "$line"
                continue
                ;;
        esac

        if [ "$ret" = 2 ]; then
            continue
        fi

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

    if [ "$ret" = 2 ]; then
        echo "Resolve the conflicts working files above first"
    fi

    return $ret
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

join_scan()
{
    SEP=$1
    shift

    dir=$1

    log "svn scan start... $dir"

    [ "$PLATFORM" = 'linux' ] && stat_cmd="stat -c %n$SEP%Y" || stat_cmd="stat -f "%N$SEP%m""

    ! svn_call info -R "$dir" 2>/dev/null | \
        grep -E "^(Path:|Text Last Updated:|Last Changed Date:)" | \
        awk -v sep="$SEP" -v xml_sep="$SEP" -v tz_offset="$TZ_SECONDS" '
    BEGIN { path = ""; commit_time = "" }
    /^Path:/ {
        if (path != "") {
            print path sep commit_time
        }
        path = substr($0, 7)
        commit_time = ""
    }
    /^Last Changed Date:/ {
        datetime = substr($0, index($0, ":") + 2, 19)
        commit_time = datetime_to_timestamp(datetime)
        if (commit_time != "") {
            commit_time = commit_time
        }
    }
    END {
        if (path != "") {
            print path sep commit_time
        }
    }
    function datetime_to_timestamp(datetime) {
        split(datetime, dt_parts, " ")
        split(dt_parts[1], ymd, "-")
        split(dt_parts[2], hms, ":")
        year = ymd[1] + 0; month = ymd[2] + 0; day = ymd[3] + 0
        hour = hms[1] + 0; minute = hms[2] + 0; second = hms[3] + 0

        days = 0
        for (y = 1970; y < year; y++) {
            if ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)) {
                days += 366
            } else {
                days += 365
            }
        }
        month_days[1] = 31; month_days[2] = 28; month_days[3] = 31
        month_days[4] = 30; month_days[5] = 31; month_days[6] = 30
        month_days[7] = 31; month_days[8] = 31; month_days[9] = 30
        month_days[10] = 31; month_days[11] = 30; month_days[12] = 31
        if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
            month_days[2] = 29
        }
        for (m = 1; m < month; m++) {
            days += month_days[m]
        }
        days += day - 1

        return days * 86400 + hour * 3600 + minute * 60 + second - tz_offset
    }
'  > /tmp/svn_info.$$ && echo "svn info failed" && return 1

    awk -F"$SEP" '{print $1}' /tmp/svn_info.$$ > /tmp/all_paths.$$

    log "svn info ok. $dir"

    if [ -s /tmp/all_paths.$$ ]; then
        cat /tmp/all_paths.$$ |
        while IFS= read -r line; do printf "%s\0" "$line"
        done |
        xargs -0 -P 2 -L 100 $stat_cmd 2>/dev/null > /tmp/stat_results.$$

        log "get mtime ok. $dir"

        sr="/tmp/stat_results.$$"

        ! awk -F"$SEP" -v sep="$SEP" -v fn="$sr" '
            BEGIN {
                while ((getline < fn) > 0) {
                    split($0, parts, sep)
                    stat_time[parts[1]] = parts[2]
#                    print "stat result:" $0
                }
            }
            {
                path = $1
                commit_time = $2
                text_time = (path in stat_time) ? stat_time[path] : ""
                print path sep text_time sep commit_time
            }
        ' /tmp/svn_info.$$ | LC_ALL=C sort > /tmp/version.$$ && echo "svn info failed" && return 1

        log "join mtime, commit_time ok. $dir"

    else
        ! cat /tmp/svn_info.$$ | LC_ALL=C sort > /tmp/version.$$ && echo "svn info failed" && return 1
    fi

    ! svn_call propget "$FILE_MTIME_PROP" -R "$dir" | sed "s/\(.*\) - \(.*\)/\1$SEP\2/" \
        | LC_ALL=C sort > /tmp/props.$$ && echo "svn propget failed" && return 1

    log "get propget ok. $dir"
#    cat /tmp/props.$$ ｜ grep "$SEP$"
#    return 1

    LC_ALL=C join -t "$SEP" -a1 -e '' -o '1.1,1.2,2.2,1.3' \
        /tmp/version.$$ \
        /tmp/props.$$ \
        2>/dev/null

    ret=$?
    if [ "$ret" != 0 ]; then
        #on linux ret:2 means failed, ret:1 means succeed but some rows has not joined
        if [ "$PLATFORM" != 'linux' ] || [ "$ret" = 2 ]; then
            echo "Warning: join version.$$ and props.$$ to file_props.$$ failed: $ret"
            log "version"
            cat /tmp/version.$$

            log "props"
            cat /tmp/props.$$
            return 1
        fi
    fi

    log "join ok. file_props.$$ $dir"
#    return 1
    rm -f /tmp/svn_info.$$ /tmp/all_paths.$$ /tmp/stat_results.$$ /tmp/version.$$ /tmp/file_props.$$

    return 0
}

python_scan()
{
    SEP=$1
    shift

    if [ "$#" != 0 ] && [ -n "$1" ]; then
        work_dir=", '$dir'"
    else
        work_dir=""
    fi

    cmd=$(find_command "python3") || cmd=$(find_command "python")
#    cmd="python"
    "$cmd" -c "
from __future__ import print_function
import os, sys, subprocess
from datetime import datetime

def ts(s):
    dt = datetime.strptime(s[:19], '%Y-%m-%d %H:%M:%S')
    return int(dt.timestamp()) if sys.version_info[0] >= 3 else int((dt - datetime(1970,1,1)).total_seconds())

def check_output(cmd, stderr=None, text=True):
    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    if sys.version_info[0] >= 3 and sys.version_info[1] >= 7:
        # Python 3.7 +
        return   subprocess.check_output(cmd, stderr=stderr, env=env, text=text)
    else:
        output = subprocess.check_output(cmd, stderr=stderr, env=env)
        if text:
            return output.decode('utf-8')

        return output

svn_path = sys.argv[1] if len(sys.argv) > 1 else '.'

paths, commits, cur_path, cur_commit = [], {}, None, None
try:
    out = check_output(['svn_kmt_org', 'info', '-R'$work_dir])
#    if sys.version_info[0] < 3: out = out.decode('utf-8')
    for line in out.splitlines():
        if line.startswith('Path:'):
            if cur_path and cur_commit is not None:
                paths.append(cur_path); commits[cur_path] = cur_commit
            cur_path, cur_commit = line[6:], None
        elif line.startswith('Last Changed Date:'):
            cur_commit = ts(line[18:].strip())
    if cur_path and cur_commit is not None:
        paths.append(cur_path); commits[cur_path] = cur_commit

except Exception as e:
    print('Exception:', e)
    sys.exit(1)

props = {}
try:
    prop_output = check_output(['svn_kmt_org', 'propget', '$FILE_MTIME_PROP', '-R'$work_dir])
    for line in prop_output.splitlines():
        idx = line.rfind(' - ')

        if idx > 0:
            props[line[:idx]] = line[idx+3:]
except Exception as e:
    print('Exception:', e)
    sys.exit(1)

for p in paths:
    try:
        mtime = str(int(os.stat(p).st_mtime))
        prop = props.get(p, '')
        vts = commits.get(p, '')
    except OSError as e:
        print('Exception:', e)
        sys.exit(1)

    print('{}$SEP{}$SEP{}$SEP{}'.format(p, mtime, prop, vts))
" "$@"
    return $?
}

on_file_scan()
{
    file=$1
    file_ts=$2
    prop_ts=$3
    version_ts=$4

    [ "$file" = '.' ] && return 0

    checked_count=$(( checked_count+1 ))

    [ -z "$file_ts" ] && echo "No file mtime provided: '$file'" && return 1

    if [ -n "$prop_ts" ]; then
        if [ "$file_ts" = "$prop_ts" ] || [ -d "$file" ]; then
            [ "$cmd" = "show_completed" ] && echo "Completed $(format_timestamp "$file_ts") $file"
            completed_count=$(( completed_count+1 ))
            return 0
        fi

        if [ "$file_ts" -gt "$prop_ts" ]; then
            if [ "$cmd" = "synchronize" ]; then
                ! sync_a_file_mtime "$file" "$prop_ts" && echo "Synchronize failed $(format_timestamp "$prop_ts") '$file'" && return 1
                echo "Synchronizing mtime $(format_timestamp "$prop_ts") '$file'"
                effected_count=$(( effected_count+1 ))
            else
                [ "$cmd" = "show_synchronizable" ] && echo "Synchronizable $(format_timestamp "$prop_ts") from $(format_timestamp "$file_ts") $file"
                synchronizable_count=$(( synchronizable_count+1 ))
            fi
        else

            if [ "$cmd" = "resolve" ]; then
                ! str=$(save_a_file_mtime "$file" "$file_ts") && echo "$str" && return 1
                echo "Resolve conflicting mtime $(format_timestamp "$prop_ts") replace with $(format_timestamp "$file_ts") '$file'"
                effected_count=$(( effected_count+1 ))
            else
                conflict_count=$(( conflict_count+1 ))
#                log "prop_ts: $prop_ts, file_ts: $file_ts"
                [ "$cmd" = "show_conflict" ] && echo "Conflict mtime repos: $(format_timestamp "$prop_ts") local: $(format_timestamp "$file_ts") $file"
            fi
        fi
    else
        [ -z "$version_ts" ] && echo "No versioned timestamp provided: '$file'" && return 1

        if [ "$file_ts" -ge "$version_ts" ]; then
            [ "$cmd" = "show_unsynchronizable" ] && echo "Unsynchronizable $(format_timestamp "$version_ts") $(format_timestamp "$file_ts") $file"
            unsynchronizable_count=$(( unsynchronizable_count+1 ))
        else
            if [ "$cmd" = 'complete' ]; then
                ! save_a_file_mtime "$file" "$file_ts" && echo "Complete mtime failed $(format_timestamp "$version_ts") $(format_timestamp "$file_ts") '$file'" &&  return 1
                echo "Completing mtime $(format_timestamp "$file_ts") '$file'"
                effected_count=$(( effected_count+1 ))
            else
                [ "$cmd" = "show_completable" ] && echo "Completable $(format_timestamp "$version_ts") $(format_timestamp "$file_ts") $file"
                completable_count=$(( completable_count+1 ))
            fi
        fi
    fi

    return 0
}

fix_len()
{
    str=$1
    len=$2
    printf "% ${len}s" "$str"
}

kmt_command()
{
    if [ $# = 0 ]; then
        echo "Invalid command"
        return 1
    fi

    cmd=$1

    shift

    checked_count=0
    completed_count=0
    completable_count=0
    synchronizable_count=0
    conflict_count=0
    unsynchronizable_count=0

    effected_count=0

    dirs=$(select_arg_dirs "$@")

    while IFS= read -r dir
    do
#        ! str=$(svn_call info "$dir" 2>&1) && echo "$str" && return 1

        ! is_update_to_date "$dir" && echo "The working copy '${dir:-.}' is not update to date." && return 1

        if [ "$cmd" = 'complete' ] || [ "$cmd" = 'restore' ] || [ "$cmd" = 'resolve' ]; then

            if ! str=$(get_files_2_commit "$dir"); then
                echo "$str"
                return 1
            fi

            has_uncommitted=0
            [ -n "$str" ] && while read -r file
            do
                if [ -e "$file" ]; then
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
    done << EOF
$dirs
EOF
    [ "$cmd" = 'sync' ] && cmd='synchronize'

    case $cmd in
        scan)
            dirs_inline=$(echo "$dirs" | tr '\n' ' ' | sed 's/[ \t]*$//')

            echo "Scanning versioned files in directories $dirs_inline..."
            ;;
        show_completed)
            echo "Listing completed files..."
            ;;
        show_completable)
            echo "Listing mtime completable files..."
            ;;
        show_synchronizable)
            echo "Listing mtime synchronizable files..."
            ;;
        show_conflict)
            echo "Listing files with mtime conflicts..."
            ;;
        show_unsynchronizable)
            echo "Listing files unable to synchronize due to file:mtime not completed..."
            ;;
        complete)
            echo "Completing file:mtime from local file mtime..."
            ;;
        synchronize)
            echo "Synchronizing local mtime from repository metadata..."
            ;;
        resolve)
            echo "Resolving mtime conflicts (use local file mtime)..."
            ;;
        *)
            echo "Invalid command $cmd"
            return 1
          ;;

    esac

    start=$(date +%s.%N)

    if [ "$SCAN_BACKEND" = 'python' ] || [ "$SCAN_BACKEND" = 'join' ] ; then

        SEP=$(printf '\x03')
#        SEP='$'

        while IFS= read -r dir
        do
            log "scan dir: $dir"
            if [ "$SCAN_BACKEND" = 'python' ]; then
                ! str=$(python_scan "$SEP" "$dir") && echo "$str" && echo "python scan failed" && return 1
            else
                ! str=$(join_scan "$SEP" "$dir") && echo "$str" && echo "join scan failed" && return 1
            fi

            log "on scanned: $dir"

            [ -n "$str" ] && while IFS="$SEP" read -r file file_ts prop_ts version_ts
            do
                ! on_file_scan "$file" "$file_ts" "$prop_ts" "$version_ts" && return 1
            done << EOF
$str
EOF
            log "scanned result proceed: $dir"

        done << EOF
$dirs
EOF
    else
        ! str=$(get_versioned_files_list "$@") && echo "$str" && return 1

        [ -n "$str" ] && while IFS= read -r file
        do
            version_ts=

            ! file_ts=$(get_file_mtime "$file") && echo "$file_ts" && return 1

            [ -z "$file_ts" ] && echo "Get file mtime failed: '$file'" && return 1

            ! prop_ts=$(svn_prop_get "$file") && prop_ts=

            if [ -z "$prop_ts" ]; then
                ! version_ts=$(get_versioned_timestamp "$file") || [ -z "$version_ts" ] && echo "Get versioned timestamp failed: '$file'" && return 0
            fi

            ! on_file_scan "$file" "$file_ts" "$prop_ts" "$version_ts" && return 1

        done << EOF
$str
EOF
    fi

    end=$(date +%s.%N)
    start=$(echo "$start" | sed 's/0*$//')
    end=$(echo "$end" | sed 's/0*$//')
#    log "diff: $end - $start"
    duration=$(float_diff "$end" "$start")

    echo "Done."
    echo "Elapsed time(s): ${duration} by $SCAN_BACKEND"
    echo ""
    case "$cmd" in
     "scan")
        lc=${#checked_count}
        cat << EOF
Versioned files checked:  $checked_count
      Completed:          $(fix_len "$completed_count" "$lc")
      Completable:        $(fix_len "$completable_count" "$lc")
      Synchronizable:     $(fix_len "$synchronizable_count" "$lc")
      Conflicts:          $(fix_len "$conflict_count" "$lc")
      Unsynchronizable:   $(fix_len "$unsynchronizable_count" "$lc")

EOF
        ;;
    'complete')
        if [ "$effected_count" = 0 ]; then
            echo "No files completed"
        else
            if svn_call commit "$@" -m "Completed file mtime for $effected_count files"; then
                echo "Completed ${effected_count} files successfully."
                completed_count=$(( completed_count+effected_count ))

                ! svn up "$@" && echo "SVN update to date failed"
            else
                echo "Commit failed."
                return 1
            fi
        fi
        ;;
    'synchronize')
        if [ "$effected_count" = 0 ]; then
            echo "No files synchronized"
        else
            echo "Synchronized ${effected_count} files successfully."
            completed_count=$(( completed_count+effected_count ))
        fi
        ;;
    'resolve')
        if [ "$effected_count" = 0 ]; then
            echo "No files resolved"
        else
            if svn_call commit "$@" -m "Resolved file mtime for $effected_count files"; then
                echo "Resolved ${effected_count} files successfully."
                completed_count=$(( completed_count+effected_count ))

                ! svn up "$@" && echo "SVN update to date failed"
            else
                echo "Commit failed."
                return 1
            fi
        fi
        ;;
    'show_completed')
        echo "$completed_count completed files."
        ;;
    'show_completable')
        echo "$completable_count files completable."
        ;;
    'show_synchronizable')
        echo "$synchronizable_count files synchronizable."
        ;;
    'show_unsynchronizable')
        echo "$unsynchronizable_count unsynchronizable files."
        echo '
Unable to synchronize files:
  These files do not have file:mtime metadata in the repository.
  This working copy is not eligible to complete them.
  They should be completed from a working copy that still contains
  the original file modification times.
  Once completed, they become synchronizable.
'
        ;;
    'show_conflict')
        echo "$conflict_count mtime conflicting files."
        ;;
    *)
        ;;

    esac

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

    if [ -f "$file" ]; then
        ! str=$(svn_call status "$file@") && echo "Get status failed. $file" && return 1
        [ -n "$str" ] && echo "$str" | grep -e "^C.*$file" && log "Has conflict $str" && return 0
    fi

#    [ -n "$file" ] && echo "tests false" && return 1 #for tests

    prop_ts=$(svn_prop_get "$file")

    [ -n "$prop_ts" ] && [ "$prop_ts" = "$file_ts" ] && log "same mtime: $file" && return 0

    if [ -n "$str" ] && echo "$str" | grep -e "^M.*$file"; then
        if [ -n "$prop_ts" ] && [ "$file_ts" -lt "$prop_ts" ]; then
            echo "Time conflicts: the file mtime should not earlier than the existing metadata. $(format_timestamp "$prop_ts") > $(format_timestamp "$file_ts") $file"
            return 2
        fi

        vs_ts=$(get_versioned_timestamp "$file")
        if [ -n "$vs_ts" ] && [ "$file_ts" -lt "$vs_ts" ]; then
            echo "Time conflicts: The file mtime should not earlier than the last versioned commit time. $(format_timestamp "$vs_ts") > $(format_timestamp "$file_ts") '$file'"
            return 2
        fi
    fi

    if ! svn_prop_set \
        "$file" \
        "$file_ts" \
        >/dev/null  ; then
          echo "Set mtime $(format_timestamp "$file_ts") $file failed!"
          return 1
    fi

    log "Set mtime $(format_timestamp "$file_ts") $file successfully."

    return 0
}

select_arg_dirs()
{
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
        echo "$p"
    done

    return 0
}

save_file_mtime()
{
    dir=$1
    log "dir: '$dir'"
    if ! str="$(get_files_2_commit "$dir")"; then
        echo "$str"
        log "Failed to get files list to commit"
        return 1
    fi

    [ -n "$str" ] && while IFS= read -r file
    do
        [ -z "$file" ] && continue

        if ! file_ts=$(get_file_mtime "$file"); then
            log "file_ts: $file_ts, file: '$file'"
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

    return 0
}

##############################################################################
# Sync File Mtime
##############################################################################
sync_a_file_mtime()
{
    file=$1
    prop_ts=$2

    [ -z "$file" ] && return 1

    [ -z "$prop_ts" ] && return 1

    if ! set_file_mtime "$file" "$prop_ts"; then
        log "Failed to set mtime $(format_timestamp "$prop_ts") $file"
    else
        log "Synchronized mtime $(format_timestamp "$prop_ts") $file successfully"
    fi

    return $ret
}

##############################################################################
# Command Handler
##############################################################################

svn_hook_line()
{
    line=$1

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
                    return 0
                fi
            fi

            log "Process timestamp $prop_ts '$file'"

            if [ -z "$prop_ts" ]; then
                echo "$line"
                return 0
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
                        return 0
                    fi
                fi

                sync_a_file_mtime "$file" "$prop_ts" || return 1

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

    return 0
}

command_handler()
{
    cmd=$1

    log "$cmd start"

    if [ "$cmd" = 'commit' ]; then
        shift

        dirs=$(select_arg_dirs "$@")

        while IFS= read -r dir
        do
            ! str=$(save_file_mtime "$dir") && echo "$str" && return 1
        done << EOF
$dirs
EOF

        ! str=$(svn_call "$cmd" "$@") && echo "$str" && return 1

    else
        ! str=$(svn_call "$@") && echo "$str" && return 1
    fi

    [ -z "$str" ] && return 0

    while IFS= read -r line
    do
        ! svn_hook_line "$line" && return 1
    done << EOF
$str
EOF

    ret=$?

    log "$cmd completed $ret"

    return $ret
}


##############################################################################
# Extension Command
##############################################################################

kmt_command_handler()
{
    cmd=$1
    shift

    for p in "$@";
    do
        case "$p" in
            --scan-backend=*)
                [ "$1" = "$p" ] && shift
                ! set_kmt_scan_backend "${p#*=}" && return 1
            ;;
        esac
    done

    [ -z "$SCAN_BACKEND" ] && ! auto_set_kmt_scan_backend && return 1

    dirs=$(select_arg_dirs "$@")
    while IFS= read -r dir
    do
        ! str=$(svn_call info "$dir" 2>&1) && echo "$str" && return 1
    done << EOF
$dirs
EOF

    show_version

    echo "Scanning Backend: $SCAN_BACKEND"
    echo "Current Directory: $(pwd)"
    echo ""


    if [ -z "$cmd" ] || [ "$cmd" = "ui" ] || [ "$cmd" = "main" ]; then
        kmt_ui "$@"
    else
        kmt_command "$cmd" "$@"
    fi
}

is_update_to_date()
{
    path="${1:-.}"

    ! schedule=$(svn_call info "$path" 2>/dev/null | grep "^Schedule: ") && echo "Get Schedule failed" && return 1
    schedule="${schedule#*Schedule: }"

    ! [ "$schedule" = "normal" ] && echo "The Schedule is not normal" && return 1

    ! local_rev=$(svn_call info "$path" 2>/dev/null | grep "^Revision: ") && echo "Get local revision failed" && return 1
    local_rev="${local_rev#*Revision: }"

    ! remote_rev=$(svn_call info -r HEAD "$path" 2>/dev/null | grep "^Last Changed Rev: ") && echo "Get remote revision failed" && return 1
    remote_rev="${remote_rev#*Last Changed Rev: }"

    log "local: $local_rev, remote: $remote_rev"

    [ -n "$local_rev" ] && [ -n "$remote_rev" ] && [ "$local_rev" -ge "$remote_rev" ]
}

kmt_ui()
{
    dirs=$(select_arg_dirs "$@")

    dirs_inline=$(echo "$dirs" | tr '\n' ' ' | sed 's/[ \t]*$//')

    while true
    do
          [ -n "$checked_count" ] && files_count="[$checked_count files]" || files_count=

          cat << EOF
Select an operation:

  -- Scan --

    1   -- Scan directories (${dirs_inline:-.}) $files_count

  -- Inspect --

    2   -- List mtime completed files $completed_count
    3   -- List mtime completable files $completable_count
    4   -- List mtime synchronizable files $synchronizable_count
    5   -- List files with mtime conflicts $conflict_count
    6   -- List mtime unsynchronizable files (file:mtime not completed) $unsynchronizable_count

  -- Modify --

    7   -- Complete file:mtime from local file mtime $completable_count
    8   -- Synchronize local mtime from repository metadata $synchronizable_count
    9   -- Resolve mtime conflicts (use local file mtime) $conflict_count

  Other -- Exit

EOF
        read -r key

        case $key in

            1)
                cmd=scan    ;;

            2)
                cmd=show_completed  ;;

            3)
                cmd=show_completable ;;

            4)
                cmd=show_synchronizable ;;

            5)
                cmd=show_conflict ;;

            6)
                cmd=show_unsynchronizable ;;

            7)
                cmd=complete ;;

            8)
                cmd=synchronize ;;

            9)
                cmd=resolve ;;

            *)
                return 0 ;;

        esac

        echo ""

        ! kmt_command "$cmd" "$@" && return 1

    done

    return 0
}

##############################################################################
# Version
##############################################################################

show_version()
{
    echo "SVN Keep MTime. Version: ${SVN_KMT_VERSION}"
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

        kmt|kmt-ui|kmt-main)
            shift

            kmt_command_handler 'ui' "$@"

            ;;

        kmt-scan|kmt-complete|kmt-synchronize|kmt-sync|kmt-resolve)

            shift

            kmt_command_handler "${cmd#*-}" "$@"

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
    [ "$1" = '--kmt-debug' ] && shift && SVN_KMT_DEBUG=1

    detect_platform &&
    detect_time_zone &&
    detect_original_svn &&
    detect_time_offset "$@" || return 1

    dispatch "$@"
}

main "$@"
