# Script that allows you to search and bulk install apt packages easily
# Written by lucemans (https://github.com/lucemans)

function linstall () {
    LUC_INPUT=$(apt-cache search . | awk -F' - ' '{print $1}' | sort | uniq | sort | fzf -m --reverse)
    if [[ ${#LUC_INPUT} -ne 0 ]]; then
        sudo apt install $LUC_INPUT
    fi
}
