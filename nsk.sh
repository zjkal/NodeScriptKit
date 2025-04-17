#!/bin/bash
MENU_URL="$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/NodeSeekDev/NodeScriptKit/releases/latest)"
MENU_VERSION="${MENU_URL##*/}"
if [ "$MENU_VERSION" != "$(cat /etc/nsk/version)" ] ; then
    echo "检测到有新版本可以更新，是否升级？[y/N]"
    read -r ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        bash <(curl -Ls https://raw.githubusercontent.com/NodeSeekDev/NodeScriptKit/refs/heads/main/install.sh)
    else
        echo "已取消升级"
    fi
fi
nskCore -config /etc/nsk/config.toml
