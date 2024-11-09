###
# v1.2 Script for NIC's enumeration, enabling all links, disabling ntp and firewall,
# disabling network manager on interfaces with ice driver,
# list if links are detected and optionally some ice driver operations
#
# usage: ./nic_utility.sh [path_to_driver]
# set DEBUG_COMMANDS environment variable to run your own commands.
###
RED='\e[31m'
GREEN='\e[32m'
RESET='\e[0m'
# if MAC address starts with MAC_PREFIX, change it to random one
MAC_PREFIX="00:00:00:00"
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
ICE_DRIVER_PATH=$1
SCRIPT_NAME=$(basename "$0")
INSTALL_DESTINATION="/usr/bin/$SCRIPT_NAME"

#add commands specific to debug
function run_user_commands {
echo -e "${GREEN}Executing command from DEBUG_COMMANDS:${RESET} $DEBUG_COMMANDS"
eval "$DEBUG_COMMANDS"
}

#install script to /usr/local/bin
function install_script {
cp "$0" "$INSTALL_DESTINATION"
chmod +x "$INSTALL_DESTINATION"
echo -e "${GREEN}Script copied to $INSTALL_DESTINATION${RESET}"

}

#disable NMCLI management of NICs with ice driver
function stop_nmcli_and_useless_services {
systemctl stop firewalld > /dev/null 2>&1
systemctl stop ntp > /dev/null 2>&1

for iface in $INTERFACES; do
        driver=$(readlink -f /sys/class/net/$iface/device/driver | awk -F'/' '{print $NF}')
        if [[ "$driver" == "ice" ]]; then
            echo "Disabling NetworkManager management for interface: $iface (driver: $driver)"
            nmcli dev set "$iface" managed no > /dev/null 2>&1
        fi
done

}

function reload_ice_driver {
if [[ -f $ICE_DRIVER_PATH && "$ICE_DRIVER_PATH" == *".ko" ]]; then
    echo -e "${GREEN}Removing old and inserting new ice driver...${RESET}"
    rmmod irdma > /dev/null 2>&1
    rmmod ice > /dev/null 2>&1
    insmod $ICE_DRIVER_PATH
else
  echo -e "${RED}Driver path does not exist, or is incorrect (no ice.ko file), skipping.${RESET}"
fi
}

#Enabling all interfaces in the system#
function enable_all_interfaces {
echo -e "${GREEN}Enabling all network interfaces in the system...${RESET}"
echo -e "Loading interfaces and IPs list..."
for interface in $INTERFACES; do
    sudo ip link set "$interface" up
done
}

#printing if physical link is detected  or not using ethtool#
function print_links_info {
for iface in $INTERFACES; do
        echo "Interface: $iface"
        ip addr show $iface | grep -e "inet" -e "link/ether"
        ethtool $iface | grep  "Link detected"
        ethtool -i $iface | grep -e "bus" -e "driver" -e "version" | grep -v "expansion"
        echo "------------------------------------------------------"
done
}

function change_wrong_mac_addresses {
for iface in $(ls /sys/class/net/ | grep -Ev "lo|bootnet|br0|vir"); do
octet1=$(printf '%02X' $((RANDOM % 256)))
octet2=$(printf '%02X' $((RANDOM % 256)))
  current_mac=$(cat /sys/class/net/$iface/address)
  if [[ $current_mac == $MAC_PREFIX* ]]; then
    new_mac="00:00:00:00:$octet1:$octet2"
    echo "Changing MAC address of $iface from $current_mac to $new_mac"
    ip link set dev $iface address $new_mac
  fi
done
}

### Main ###
install_script
reload_ice_driver
change_wrong_mac_addresses
stop_nmcli_and_useless_services
enable_all_interfaces
run_user_commands
sleep 0.3
print_links_info
