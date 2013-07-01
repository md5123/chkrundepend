#!/bin/bash 

#
# For fix runtime dependency of PBS files on StartOS
#
# chen-qx@live.cn  2013-01 
# License GPL
# Copyright (C) 2013 Dongguan Vali Network Technology Co.,Ltd.
#

VER='0.1'

NOCONFIRM=''

# RTDCHKCMD='./chkrundepend_v4.4.sh'
RTDCHKCMD='./chkrundepend.sh'

f_usage () {
    cat << EOF
    Usage: 
        eybs [OPTION] ... [PKGNAME] ...

    DESCRIPTION
        This application is use for check packages's configuration files 
        on StartOS, it is used with chkrundepend_v4.2.sh and ybs.

    Available Options
        -y      Avoiding interact with user.
        -v      Output version and exit.
        -h      Display this text and exit.
EOF
}

while getopts yvh name
do
    case $name in
        y) NOCONFIRM='YES';;
        v) echo $VER
            exit 0;;
        h) f_usage
            exit 0;;
            
        ?) f_usage >&2
            exit 1;;
    esac
done

if [ $OPTIND -gt 1 ]; then
    shift $((OPTIND - 1))
fi

f_getpbsrtd () {
    # 获取 PBS 配置中的RDEPEND 项记录
    # 
    # Only one argument allowed

    fPKGNAME=$1
    fRDEPEND=''
    fPBSFILE=''
    fMULLINE=0 # 值分为多行的情况，以 引号 方式跨行
    fPVD=''

    fPBSFILE=$(ybs -w "$fPKGNAME")
    if [ $? -ne 0 ]; then
        echo $fPBSFILE >&2
        return
    fi

    fPVD=$(. "$fPBSFILE"; echo $PROVIDE)
    echo $fPVD | grep -m 1 -q "$fPKGNAME"        # 拆分包判断，有PROVIDE,并且包名位于其值中
    REVAL=$?

    if [ -z "$fPVD" -o $REVAL -ne 0 ]; then
        fRDEPEND=$(. "$fPBSFILE"; echo $RDEPEND)
        echo $fRDEPEND
        return
    fi

    echo "Warning: \"$fPKGNAME\" is a separate package" >&2

    fRDEPEND=$(sed -n -r -e '/[[:blank:]]*'"$fPKGNAME"'_ins/,/(;|&|^)[[:blank:]]*\}/p' "$fPBSFILE" | cat -e)
    echo $fRDEPEND | grep -q 'RDEPEND'

    [[ $? -ne 0 ]] && echo "" && return

    fRDEPEND=$(echo $fRDEPEND | sed -r -e 's@\\\$[[:blank:]]*@@g' -e 's@\$@ @g')    # 转义过的换行符去掉
    fRDEPEND=${fRDEPEND##*RDEPEND=}
    fRDEPEND=${fRDEPEND##*RDEPEND=}

    QUOTEMARK=${fRDEPEND::1}
    ftmpRDP=${fRDEPEND:1}
    if [ "$QUOTEMARK" == "\'" ]; then           # 值以 ' 开头
        fRDEPEND=${ftmpRDP%%\'*}
    elif [ "$QUOTEMARK" == '"' ]; then           # 值以 " 开头 
        fRDEPEND=${ftmpRDP%%\"*}
    else
        fRDEPEND=${fRDEPEND%% *}
    fi

  echo "$fRDEPEND"
}

echo ": Get pkgs list"
PKGLIST="$@"
if [ "$PKGLIST" != "" ]; then
    echo "Will Check packages: " $PKGLIST 
else
    echo "Will check all packages that have been installed"
    PKGLIST=$(${PKGMCMD} -L | awk '{print $2}' | sed -n -e 's@.\[0m\(.*\)@\1@gp')
fi

for pkg in $PKGLIST 
do 
    echo "$pkg -------"

    fCURRTD=$(f_getpbsrtd "$pkg") 
    if [ $? -ne 0 ]; then
        continue
    fi

    fSUGRTD=$($RTDCHKCMD -s "$pkg" | awk -F":" '{print $2}')

    fALLRTD=$($RTDCHKCMD -a "$pkg" | awk -F":" '{print $2}')

    fFREGEX=$(echo $fSUGRTD | sed -e 's@ @|@g')
    fallDUP=$(echo $fALLRTD | sed -e 's@ @\n@g' | grep -v -x -E "$fFREGEX")     # all 中去掉建议的，剩下来的是 all 中重复的

    fFREGEX=$(echo $fallDUP | sed -e 's@ @|@g')
    fDUPDIR=$(echo $(echo $fCURRTD | sed -e 's@ @\n@g' | grep -o -x -E "$fFREGEX"))     # 当前中位于 all 中重复的，是重复的

    fFREGEX=$(echo $fCURRTD | sed -e 's@ @|@g')
    fLAKRTD=$(echo $(echo $fSUGRTD | sed -e 's@ @\n@g' | grep -v -x -E "$fFREGEX"))     # 当前中位于 all 中重复的，是重复的

    fFREGEX=$(echo $fALLRTD | sed -e 's@ @|@g')
    fUNNEED=$(echo $(echo $fCURRTD | sed -e 's@ @\n@g' | grep -x -v -E "$fFREGEX"))   # 当前 的去掉 所有 的，剩下的就是并不需要的
    
    echo "The current: $fCURRTD"
    echo "The Suggestion: $fSUGRTD"
    echo "Maybe duplicate: $fDUPDIR"
    echo "Maybe absent: $fLAKRTD"
    echo "Maybe Un-needed: $fUNNEED"

done

