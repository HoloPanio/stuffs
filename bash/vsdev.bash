# Dev Script that opens your project in VS Code
# Written by lucemans (https://github.com/lucemans)
# Modified by HoloPanio (https://github.com/HoloPanio)

LUC_DEV_FOLDER='/home/holopanio/projects/'
function vsdev () {
    LUC_INPUT=$(ls $LUC_DEV_FOLDER | fzf --reverse)
    if [[ ${#LUC_INPUT} -ne 0 ]]; then
        LUC_INPUT2=$LUC_DEV_FOLDER$LUC_INPUT;
        cd $LUC_INPUT2
        code $LUC_INPUT2
        echo -e '\e[37m======================================\e[39m\n\n    Opening project \e[36m'$LUC_INPUT'\e[39m\n\n\e[37m======================================'
        #code
    fi
}
