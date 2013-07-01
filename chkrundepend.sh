#!/bin/bash

#
# V4 版 更改算法，
# 首次运行生成 直接依赖，， 存于以包名为名的文件中
# For checking runtime dependency on StartOS
# chen-qx@live.cn  2013-01 
# License GPL
# Copyright (C) 2013 Dongguan Vali Network Technology Co.,Ltd.
# 
# 4.3 修正数个bug ,
#   重写 dot 文件生成函数，合并转换脚本到此程序内,
#   添加支持命令行选项
# 测试基本正常
# 4.4 日志输出

VER='4.4'
PKGMCMD='/usr/bin/ypkg'


f_usage() {
    cat << EOF

    Usage: 
        eybs [OPTION] ... [PKGNAME] ...


    DESCRIPTION
        eybs is use for checking Run-Time depencencies of package on StartOS.
            It use "file" and "ldd" commands to obtain the information of 
            one package's executable files' dependencies, and show the All,
            Direct, or/and (According to the options) Suggested dependencies.
            It also can generates the dependencies relationship SVG graph.


    Available Options
        
        -s      Check and obtain PKGNAME's Suggested Run-time Dependencies (Default).
        -d      Check and obtain PKGNAME's Direct Run-time Dependencies.
        -a      Check and obtain PKGNAME's All Run-time Dependencies.
        -u      Update PKGNAME's file record of Dependencies.
        -g      Generating PKGNAME's dependencies relationship SVG graph.
        -V      Output Verbose message.
        -v      Output version and exit.
        -h      Display this text and exit.

    Note: The original copy of this script is just for StartOS 5.0 and laters, 
          when use in others, please adjusting the package manager and the 
          command "grep", since some distributions may not supports "-s" option.

EOF
}


PKGLIST=''
SUGOPT=''
NOOPT='YES'
ALLOPT=''
DIROPT=''
PICOPT=''
UPDOPT=''
SHOWDO='NO'


while getopts adghsuvV name
do
    case $name in
        a) ALLOPT='YES'
           NOOPT='NO' ;; 
        d) DIROPT='YES'
           NOOPT='NO' ;; 
        s) SUGOPT='YES';; 
        g) PICOPT='YES'
           NOOPT='NO' ;; 
        u) UPDOPT='YES'
           NOOPT='NO' ;; 
        V) SHOWDO='YES' ;;
        v) echo $VER
            exit 0;;
        h) f_usage 
            exit 0;;
        ?) 
            f_usage >&2
            exit 1;;
    esac
done

if [ "$NOOPT" == "YES" ]; then
    SUGOPT='YES'
fi
unset NOOPT


DIRRTDDIR='direct_rtd_dir' #
LOGDIR='direct_log_dir' #
DOTFILEDIR='direct_dot_dir' #  结果目录
SVGDIR='rtd_svg_dir'
LOGFILE='do.log'
ERRLOG='err.log'


[[ "$SHOWDO" == "YES" ]] && echo "Starting ..."

mkdir ${DIRRTDDIR} ${LOGDIR} 2> /dev/null


if [ $OPTIND -gt 1 ]; then
    shift $((OPTIND - 1))
fi

f_getfilesowner() {
    fOWNLIST=''
    for tmpf in $@
    do
        # fTMPOWN=$(ypkg -S ${tmpf} | tee -a /tmp/eybs.log | sed -n -e '2s@\(.*\)_.*:.*@\1@p')
        fTMPOWN=$(ypkg -S ${tmpf} | sed -n -e '2s@\(.*\)_.*:.*@\1@p')
        if [ "x${fTMPOWN}" != "x" ]; then
            fOWNLIST="${fOWNLIST} ${fTMPOWN}"
        else
            echo "$tmpf check owner error!" >> $LOGDIR/$ERRLOG
        fi
    done
    echo ${fOWNLIST} | sed -e 's@\ \+@\n@g' | sort -u
    exit 0
}

f_getfilesdll() {

    fDLLLIST=''
    tDLLLIST=''
    fFREGEX=$(echo $* | sed -e 's@\ \+@\|@g' -e 's@\[@\\[@g')  # Fuck the "/usr/bin/[" command of coreutils 
    for tmpf in $@
    do 
        fDLLLIST="${fDLLLIST} `ldd "$tmpf" 2> $LOGDIR/$ERRLOG | tee $LOGDIR/tmpfile | grep '=>' | grep -oE '/.* '`"
        grep "not found" $LOGDIR/tmpfile >> $LOGDIR/$ERRLOG
    done
    unset tmpf

    for f in ${fDLLLIST}
    do
        tDLLLIST="$tDLLLIST $(readlink -e $f)"
    done
    # fDLLLIST=$(echo ${tDLLLIST} | sed -e 's@\ \+@\n@g' | sort -u | grep -vxE "$fFREGEX")   # 不允许自身成为依赖
    fDLLLIST=$(echo ${tDLLLIST} | sed -r -e 's@('$fFREGEX')@@g')
    rm $LOGDIR/tmpfile 2>/dev/null
    f_getfilesowner ${fDLLLIST}
}

f_getdirrtd() {

    # just accept 1 argument

    grep -s '^DIRRTD:'   $DIRRTDDIR/$1
    if [ $? -eq 0 ]; then
        #    echo "$1 => get direct dependencies from file" >&2
        return
    fi 

    fPKG_LIST=$($PKGMCMD -l $1 | grep '^F|' | awk '{print $3}')
    fELFLIST=''
    fDIRRTD=''

    for tmpf in $fPKG_LIST
    do
        tmpf_info=$(file $tmpf)
        echo ${tmpf_info} | grep 'Perl'   > /dev/null 2>&1 && fDIRRTD="${fDIRRTD} perl" # FIXME: How to check the interpreter's version ?
        echo ${tmpf_info} | grep 'Python' > /dev/null 2>&1 && fDIRRTD="${fDIRRTD} python" 
        echo ${tmpf_info} | grep 'ELF'    > /dev/null 2>&1 && fELFLIST="${fELFLIST} ${tmpf}"
    done
    fDIRRTD=$(echo $fDIRRTD | sed -e 's@\ \+@\n@g' | sort -u | grep -v "$1")
    fDIRRTD="${fDIRRTD} $(f_getfilesdll $fELFLIST )"   # 得到程序的直接依赖, 可能其中有些依赖是其它依赖的依赖
    fDIRRTD=$(echo $fDIRRTD | sed -e 's@\ \+@\n@g' | sort -u | grep -v "$1")
    echo 'DIRRTD:' $fDIRRTD | tee -a $DIRRTDDIR/$1
}

f_getallrtd () { 
    
    # just accept 1 argument as package name

    grep -s '^ALLRTD:'  $DIRRTDDIR/$1
    if [ $? -eq 0 ]; then
        #   echo "$1 => get all dependencies from file" >&2
        return
    fi

    fDIRRTD=''
    fALLSRTD=''
    fFREGEX='' 

    fDIRRTD=$(f_getdirrtd $1 | awk -F\: '{print $2}')
    fALLSRTD=$fDIRRTD
    
    if [ "x$fDIRRTD" == "x" ]; then
        return
    fi

    #   LOOPCOUNT=0 
    while [ 1 ]
    do 
        ftmpDIRRTD=''

        #   echo -e "\nLevel " ${LOOPCOUNT} ":\n" ${fDIRRTD} >&2
        #   let LOOPCOUNT=$((LOOPCOUNT + 1))

        for tmpf in ${fDIRRTD}          
        do
            tmptmp=$(f_getdirrtd ${tmpf} | awk -F\: '{print $2}')
            #   ftmpDIRRTD=$(echo ${ftmpDIRRTD} ${tmptmp} | sed -e 's@\ \{1,\}@\n@g' | sort -u | grep -vw ${tmpf})
            ftmpDIRRTD="${ftmpDIRRTD} ${tmptmp}"
        done

        fDIRRTD=${ftmpDIRRTD}

        if [ "x${fDIRRTD}" != "x" ]; then 
            fFREGEX=$(echo ${fALLSRTD} $1 | sed -e 's@\ \+@\|@g')
            fDIRRTD=$(echo ${fDIRRTD} | sed -e 's@\ \+@\n@g' | grep -vwE "${fFREGEX}") # | sort -u)  # -w whole word match
            fALLSRTD="${fALLSRTD} ${fDIRRTD}"
        else 
            break
        fi
    done
    echo 'ALLRTD:' $(echo ${fALLSRTD} | sed -e 's@\ \+@\n@g' | sort -u) | tee -a $DIRRTDDIR/$1
}

f_getsugrtd() {

    # Just accpet 1 argument as pkgname

    grep -s '^SUGRTD:' $DIRRTDDIR/$1     # Note: May have to remove "-s" when use non-GNU grep
    if [ $? -eq 0 ]; then
        #    echo "$1 => get direct dependencies from file" >&2
        return
    fi   
    
    touch $DIRRTDDIR/$1  # 无论如何，执行后下边就不用再判断文件是否存在了

    fDUPFLAG=''
    fDIRRTD=$(f_getdirrtd $1 | awk -F\: '{print $2}')
    fSUGRTD=''

    declare -a fdir_arry    # direct RTD's array
    declare -a fall_arry    # All RTD's array
    declare -a flove_arry    # Depends each other
    declare -i findex
    findex=0

    for tmpf in $fDIRRTD
    do
        fall_arry[findex]=$(f_getallrtd $tmpf  | awk -F\: '{print $2}')
        fdir_arry[findex]=$tmpf  # 我日，下边的你依赖我，我依赖你的夫妻包判断要用到
        findex=$((findex + 1))
    done

    declare -i drtdindex
    declare -i loveindex
    drtdindex=0
    loveindex=0

    sed -i -e '/<=>/d' $DIRRTDDIR/$1

    for tmpf in $fDIRRTD
    do
        fDUPFLAG=1
        findex=0
        while [ $findex -lt ${#fall_arry[@]} ]
        do
            if [ $findex -eq $drtdindex ]; then
                findex=$((findex + 1))
                continue
            fi
            echo ${fall_arry[$findex]} | grep $tmpf > /dev/null 2>&1

            fDUPFLAG=$? # 匹配成功，表示此为别人的依赖了，重复依赖

            if [ $fDUPFLAG -eq 0 ]; then
                lovepkg=${fdir_arry[$findex]}
                echo ${fall_arry[$drtdindex]} | grep $lovepkg > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    echo "Warning: packages depends each other:  $tmpf <=> $lovepkg" | tee -a $DIRRTDDIR/$1  >> $LOGDIR/$LOGFILE
                    flove_arry[$loveindex]="$drtdindex $findex"  # 相互依赖的包保留再处理，Fuck them！ 也是记 下标值
                    loveindex=$((loveindex + 1))
                fi
                break 
            fi
            findex=$((findex + 1))
        done 
        if [ $fDUPFLAG -eq 1 ]; then
            fSUGRTD="$fSUGRTD $drtdindex"       # 记录在 fdir_arry 数组中的下标，
        fi
        drtdindex=$((drtdindex + 1))
    done

    # 上一关取出不属于其余依赖包的子依赖的包， 即取出的只有它包含别人
    #
    #   当前得到的 $fSUGRTD 中， 
    #   一次扫描结束, 这里可保证 $fSUGRTD 中的是保存了绝对不被其它依赖所依赖的，哪怕
    #      相互依赖的包也不会有.  只有可能是其余包依赖它们
    #   

    fLOVEPKG=''  # 该变量保存相互依赖的包中最后留下来的包


    if [ ${#flove_arry[@]} -ne 0  ]; then


        echo "Divorce processing ..." >> $LOGDIR/$LOGFILE
        #
        #   处理直接依赖中相互依赖的关系了
        #   夫妻包2选1, “度量”  大者留下
        #

        fLIVE=''        # 夫妻包中暂时通关的. 记 位于 fDIRRTD 中的下标
        fDEAD=''        # 夫妻包中该死去的,  死的不能再生，生的有可能下次PK时死掉

        findex=0
        fFREGEX=''
        loveindex=0

        until [ $loveindex -eq ${#flove_arry[@]} ]
        do
            ltmpindex=$(echo ${flove_arry[$loveindex]} | awk '{print $1}')
            rtmpindex=$(echo ${flove_arry[$loveindex]} | awk '{print $2}')

            echo $fDEAD | grep -q -E "$ltmpindex|$rtmpindex" # 任何一方先死了就不用再往下，另一方必定会与搞死其爱人的碰面（即此2者也是夫妻）
            if [ $? -eq 0 ]; then
                loveindex=$((loveindex + 1))
                continue 
            fi

            fHSB=${fdir_arry[$ltmpindex]}  # 男左女右 husband 
            fWFE=${fdir_arry[$rtmpindex]}  # wife

            fFREGEX=$(echo $fDIRRTD | sed -e 's@'$fHSB'@@g' -e 's@\ \{1,\}@|@g')
            fHSBALLRTD=${fall_arry[$ltmpindex]}     # 夫的所有的依赖
            fHSBCOUNT=$(echo $fHSBALLRTD | grep -o -w -E $fFREGEX | wc -w) # 夫中能消化直接依赖中的数量
            
            fFREGEX=$(echo $fDIRRTD | sed -e 's@'$fWFE'@@g' -e 's@\ \{1,\}@|@g')
            fWFEALLRTD=${fall_arry[$rtmpindex]}     # 妻的所有的依赖
            fWFECOUNT=$(echo $fWFEALLRTD | grep -o -w -E $fFREGEX | wc -w) # 妻中能消化直接依赖中的数量

            fLIVE=$(echo $fLIVE | sed -r -e 's@(^| )('$ltmpindex'|'$rtmpindex')( |$)@@g')

            if [ $fHSBCOUNT -gt $fWFECOUNT ]; then
                fLIVE="$fLIVE $ltmpindex"
                fDEAD="$fDEAD $rtmpindex"
            else
                fLIVE="$fLIVE $rtmpindex"
                fDEAD="$fDEAD $ltmpindex"
            fi
            loveindex=$((loveindex + 1))
        done

        echo "Big & ALive: $fLIVE"  >> $LOGDIR/$LOGFILE

       
        #   还没死的包，还有以下一关，
        #   滤掉属于此前已得到的建议依赖子依赖中的
 
        findex=0
        loveindex=0     #

        for loveindex in $fLIVE
        do
            fLOVEPKG="$fLOVEPKG ${fdir_arry[$loveindex]}"
        done

        if [ "x$fSUGRTD" != "x" ]; then

            for findex in $fSUGRTD ## 检查夫妻包是否有包含在当前已检出的建议包的所有子依赖里, 有就去，无则留
            do
                ftmpDARTD=${fall_arry[$findex]}    # 得到某个建议包的所有依赖 及其 自身
                fFREGEX=$(echo $ftmpDARTD | sed -e 's@\ \+@|@g')

                fLOVEPKG=$(echo $fLOVEPKG | sed -r -e 's@(^| )('$fFREGEX')( |$)@@g')

                findex=$((findex + 1))
            done
        fi
    fi

    ftmpSUGRTD=''
    for findex in $fSUGRTD
    do
        ftmpSUGRTD="$ftmpSUGRTD ${fdir_arry[$findex]}"
    done
    fSUGRTD="$ftmpSUGRTD $fLOVEPKG"

    echo 'SUGRTD:' $(echo ${fSUGRTD}) | tee -a $DIRRTDDIR/$1    #      | sed -e 's@\ \{1,\}@\n@g' | sort -u) | tee -a $DIRRTDDIR/$1
}

f_convertsvg () {

    # Accept just  1 parameter as pkgname

    PKGNAME=$1
    DOTFILE=${PKGNAME}.dot
    SVGFILE=${PKGNAME}.svg

    fDIRRTD=''    # 直接依赖 染色用
    fDUPDIR=''
    fSUGRTD=''
    fFREGEX=''

    mkdir $DOTFILEDIR 2> /dev/null
    echo "" > $DOTFILEDIR/$PKGNAME

    fDIRRTD=$(f_getdirrtd $PKGNAME | awk -F\: '{print $2}')
    fSUGRTD=$(f_getsugrtd $PKGNAME | awk -F\: '{print $2}')

    ftmpDIRRTD=$fDIRRTD
    fALLSRTD="$PKGNAME $fDIRRTD"

    echo 'Collecting dependencies relationship ...' >> $LOGDIR/$LOGFILE
    while [ 1 ]
    do 
        for tmpf in ${ftmpDIRRTD}          
        do
            tmptmp=$(f_getdirrtd ${tmpf} | awk -F\: '{print $2}')
            echo "{ $tmptmp } -> $tmpf" >> $DOTFILEDIR/$PKGNAME
            ftmpDIRRTD="${ftmpDIRRTD} ${tmptmp}"
        done

        if [ "x${ftmpDIRRTD}" != "x" ]; then 
            fFREGEX=$(echo ${fALLSRTD} | sed -e 's@\ \+@|@g')
            ftmpDIRRTD=$(echo ${ftmpDIRRTD} | sed -e 's@\ \+@\n@g' | grep -vwE "${fFREGEX}" | sort -u)  # -w whole word match
            fALLSRTD="${fALLSRTD} ${ftmpDIRRTD}"
        else 
            break
        fi
    done

    #---------------------
    echo "Start converting ..." >> $LOGDIR/$LOGFILE

    
    mkdir $SVGDIR 2> /dev/null

    cp -v $DOTFILEDIR/${PKGNAME}     $SVGDIR/${DOTFILE}

    fFREGEX=$(echo $fSUGRTD | sed -e 's@\ \+@|@g')
    fDIRRTD=$(echo $fDIRRTD | sed -r -e 's@('$fFREGEX')@@g')

    DOTFILEHEAD='digraph "'"$PKGNAME"'" { \n\trankdir=BT \n'
    DOTFILEHEAD="${DOTFILEHEAD}\t\"${PKGNAME}\" [color=blue,style=filled,shape=box]\n"

    if [ -n "$fDIRRTD" ]; then
        for tmpf in $fDIRRTD
        do 
            DOTFILEHEAD="${DOTFILEHEAD}\t\"${tmpf}\" [color=red,style=filled]\n"
        done 
        echo "{ $fDIRRTD } -> $PKGNAME" >> $SVGDIR/$DOTFILE
    fi

    if [ -n "$fSUGRTD" ]; then
        for tmpf in $fSUGRTD
        do 
            DOTFILEHEAD="${DOTFILEHEAD}\t\"${tmpf}\" [color=green,style=filled]\n"
        done
        echo "{ $fSUGRTD } -> $PKGNAME" >> $SVGDIR/$DOTFILE
    fi

    echo "Modifying DOTFILE ..." >> $LOGDIR/$LOGFILE

    sed -i  -r \
            -e 's@^@    @g' \
            -e 's@\{[[:blank:]]*\}[[:blank:]]*->[[:blank:]]@@g' \
            -e 's@(^| )?(([a-zA-Z0-9]+[-+.]{0,2})+)( |$)?@\1"\2"\4@g' \
            -e '1i '"$DOTFILEHEAD" \
            -e '$a}' \
            $SVGDIR/$DOTFILE

    echo "Generating SVG file ..." >> $LOGDIR/$LOGFILE

    dot -Tsvg -o $SVGDIR/$SVGFILE $SVGDIR/$DOTFILE
    REVAL=$?
    if [ $REVAL -eq 0 ]; then
        echo "Success.. $SVGDIR/$SVGFILE" >> $LOGDIR/$LOGFILE

    else
        echo "Error.. $PKGNAME. When generates SVG file" >> $LOGDIR/$LOGFILE
        return $REVAL
    fi
}

#               
#   ==================================
#

ALLRTD=''
DIRRTD='' # 直接依赖， 最直接的
DUPRTD=''
SUGRTD='' # 建议依赖，去掉 DIRRTD 中递归重复 后的
ALLPKGLS=''
FREGEX='' #  规则表达式

[[ "$SHOWDO" == "YES" ]] && echo ": Get pkgs list"
PKGLIST="$@"
if [ "$PKGLIST" != "" ]; then
    [[ "$SHOWDO" == "YES" ]] && echo "Will Check packages: " $PKGLIST  | tee -a $LOGDIR/$LOGFILE
else
    [[ "$SHOWDO" == "YES" ]] && echo "Will check all packages that have been installed" | tee -a $LOGDIR/$LOGFILE
    PKGLIST=$(${PKGMCMD} -L | awk '{print $2}' | sed -n -e 's@.\[0m\(.*\)@\1@gp')
fi

for pkg in $PKGLIST
do
    if [ "$UPDOPT" == "YES" ]; then
        echo "Update file record: $pkg"  >> $LOGDIR/$LOGFILE
        rm $DIRRTDDIR/$pkg  2> $LOGDIR/$ERRLOG
    fi

    echo "Checking: $pkg =>"  >> $LOGDIR/$LOGFILE
    if [ "$SUGOPT" == "YES" ]; then
        [[ "$SHOWDO" == "YES" ]] && echo "Get pkg's suggested Run-time dependencies"
        f_getsugrtd $pkg
    fi

    if [ "$ALLOPT" == "YES" ]; then
        [[ "$SHOWDO" == "YES" ]] && echo "Get pkg's all Run-time dependencies"
        f_getallrtd $pkg
    fi

    if [ "$DIROPT" == "YES" ]; then
        [[ "$SHOWDO" == "YES" ]] && echo "Get pkg's direct Run-time dependencies"
        f_getdirrtd $pkg
    fi

    if [ "$PICOPT" == "YES" ]; then
        [[ "$SHOWDO" == "YES" ]] && echo "Generate pkg's dependencies relationship"
        f_convertsvg $pkg
    fi

    echo "Done" >> $LOGDIR/$LOGFILE
done
[[ "$SHOWDO" == "YES" ]] && echo "Done"
exit 0


