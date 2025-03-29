#!/bin/bash
set +e

BIN_URL="https://github.com/NodeSeekDev/NskCore/releases/download/v0.0.1/nskCore"
MENU_URL="https://raw.githubusercontent.com/NodeSeekDev/NskCore/refs/heads/main/memu.template.toml"

curl -Lso /usr/bin/nskCore $BIN_URL
chmod u+x /usr/bin/nskCore
mkdir -p /etc/nsk
curl -Lso /etc/nsk/menu.toml $MENU_URL

cat > /usr/bin/nsk <<-EOF
#!/bin/bash
nskCore -local /etc/nsk/menu.toml
EOF
chmod u+x /usr/bin/nsk

echo '`nsk` command is available'
