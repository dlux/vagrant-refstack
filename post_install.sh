#!/bin/bash

# ==============================================================================
# Script installs and configure a refstack server (UI and API):
# See: https://github.com/openstack/refstack/blob/master/doc/source/refstack.rst
# ==============================================================================

# Comment the following line to stop debugging this script
set -o xtrace
# Comment the following like to stop script on failure (Fail fast)
# set -e

#=================================================
# GLOBAL DEFINITION
#=================================================
_PASSWORD='secure123'
_DEST_PATH='/opt/refstack'

[[ ! -f common_functions ]] && wget https://raw.githubusercontent.com/dlux/InstallScripts/master/common_functions

source common_functions

# ======================= Processes installation options =====================
while [[ ${1} ]]; do
    case "${1}" in
        --password|-p)
            [[ -z "${2}" || "${2}" == -* ]] && PrintError "Missing password." || _PASSWORD="${2}"
            shift
            ;;
        --help|-h)
            PrintHelp "Install refstack server " $(basename "$0") "     --password | -p   Password to be used on the DB."
            ;;
        *)
            HandleOptions "$@"
            shift
    esac
    shift
done

# ==================================== Install Dependencies ===================

EnsureRoot
SetLocale /root
umask 022

# If proxy is set on the env - expand it
[[ -n $http_proxy ]] && SetProxy $http_proxy

# If proxy passed as parameter - set it on the VENV
[[ -n $_PROXY ]] && source ".PROXY"

[[ ! -f install_devtools.sh ]] && wget https://raw.githubusercontent.com/dlux/InstallScripts/master/install_devtools.sh
chmod +x install_devtools.sh
[[ -z "${_ORIGINAL_PROXY}" ]] && ./install_devtools.sh || ./install_devtools.sh -x $_ORIGINAL_PROXY

apt-get install -y python-setuptools python-mysqldb
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${_PASSWORD}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${_PASSWORD}"
apt-get install -q -y mysql-server

curl -sL https://deb.nodesource.com/setup_4.x | bash -
apt-get install -y nodejs
# ======================================= Setup Database ======================
mysql -uroot -p"${_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE refstack;
CREATE USER 'refstack'@'localhost' IDENTIFIED BY '$_PASSWORD';
GRANT ALL PRIVILEGES ON refstack . * TO 'refstack'@'localhost';
FLUSH PRIVILEGES;

MYSQL_SCRIPT

# ======================================= Setup Refstack ======================
caller_user=$(who -m | awk '{print $1;}')
caller_user=${caller_user:-'ubuntu'}
host="$(hostname)"
domain="$(hostname -d)"
[[ -n "${domain}" ]] && fqdn="$host.$domain" || fqdn="$host"

# Install refstack client - Shorter task
echo "INSTALLING REFSTACK CLIENT"
refclient="$_DEST_PATH-client"
[[ ! -d "$refclient" ]] && git clone http://github.com/openstack/refstack-client $refclient
chown -R $caller_user $refclient
pushd $refclient
sudo -HE -u $caller_user bash -c "./setup_env"
popd

echo "INSTALLING REFSTACK SERVER, API AND UI"
[[ ! -d "$_DEST_PATH" ]] && git clone http://github.com/openstack/refstack $_DEST_PATH
chown -R $caller_user $_DEST_PATH

pushd $_DEST_PATH
sudo -HE -u $caller_user bash -c 'virtualenv .venv --system-site-package; source .venv/bin/activate; pip install .; pip install pymysql; pip install gunicorn'
sudo -HE -u $caller_user bash -c 'npm install'
sudo -HE -u $caller_user bash -c 'cp etc/refstack.conf.sample etc/refstack.conf'
sed -i "s/#connection = <None>/connection = mysql+pymysql\:\/\/refstack\:$_PASSWORD\@localhost\/refstack/g" etc/refstack.conf
sed -i "/ui_url/a ui_url = http://$fqdn:8000" etc/refstack.conf
sed -i "/api_url/a api_url = http://$fqdn:8000" etc/refstack.conf
sed -i "/app_dev_mode/a app_dev_mode = true" etc/refstack.conf
sed -i "/debug = false/a debug = true" etc/refstack.conf
sudo -HE -u $caller_user bash -c 'cp refstack-ui/app/config.json.sample refstack-ui/app/config.json'
sed -i "s/refstack.openstack.org\/api/$fqdn:8000/g" refstack-ui/app/config.json
# DB SYNC IF VERSION IS None
source .venv/bin/activate
if [[ ! -z $(refstack-manage --config-file etc/refstack.conf version | grep -i none) ]];then
    refstack-manage --config-file etc/refstack.conf upgrade --revision head
    # Verify upgrade actually happened
    msg="After sync DB, version is still displayed as None."
    [[ ! -z $(refstack-manage --config-file etc/refstack.conf version | grep -i none) ]] && PrintError $msg
fi

echo "Generate HTML templates from docs"
sudo -HE -u $caller_user bash -c "source .venv/bin/activate; python tools/convert-docs.py -o refstack-ui/app/components/about/templates doc/source/*.rst"

echo "Starting Refstack Server. Run daemon on refstack-svr screen session."
echo "refstack-api --env REFSTACK_OSLO_CONFIG=etc/refstack.conf"

# Run on deatached screen session
sudo -HE -u $caller_user bash -c "screen -dmS refstack-svr bash -c 'source .venv/bin/activate; refstack-api --env REFSTACK_OSLO_CONFIG=etc/refstack.conf;'"

# Cleanup _proxy from apt if added - first coincedence
UnsetProxy $_ORIGINAL_PROXY
popd
echo "Finished Installation Script"
