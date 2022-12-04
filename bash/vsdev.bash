# Dev Script that opens your project in VS Code
# Written by HoloPanio (https://github.com/HoloPanio)

DEV_FOLDER='/home/holopanio/projects/'
function vsdev () {
    INPUT=$(ls $DEV_FOLDER | fzf --reverse)
    if [[ ${#INPUT} -ne 0 ]]; then
        INPUT2=$DEV_FOLDER$INPUT;
        cd $INPUT2
        code $INPUT2
        echo -e '\e[37m======================================\e[39m\n\n    Opening project \e[36m'$INPUT'\e[39m\n\n\e[37m======================================'
        #code
    fi
}
