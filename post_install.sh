#!/bin/bash

# ============================================================================
# Script installs and configure a refstack server (UI and API):
# See: https://docs.openstack.org/refstack/latest/refstack.html
# ============================================================================

# Comment the following line to stop debugging this script
set -o xtrace
# Comment the following like to stop script on failure (Fail fast)
# set -e

#=================================================
# GLOBAL DEFINITION
#=================================================
_PASSWORD='secure123'
_DEST_PATH='/opt/refstack'
_DREPO='https://raw.githubusercontent.com/dlux/InstallScripts/master'
_OREPO='http://git.openstack.org/openstack'

[[ ! -f common_functions ]] && curl -O "${_DREPO}"/common_functions
[[ ! -f common_packages ]] && curl -O "${_DREPO}"/common_packages

source common_packages

# ======================= Processes installation options =====================
while [[ ${1} ]]; do
    case "${1}" in
        --password|-p)
            [[ -z "${2}" || "${2}" == -* ]] && PrintError "Missing password." || _PASSWORD="${2}"
            shift
            ;;
        --help|-h)
            PrintHelp "Install refstack server " $(basename "$0") \
                      "     --password | -p   Password to be used on the DB."
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

[[ ! -f install_devtools.sh ]] && curl -O ${_DREPO}/install_devtools.sh; chmod +x install_devtools.sh;
[[ -z "${_ORIGINAL_PROXY}" ]] && ./install_devtools.sh || ./install_devtools.sh -x $_ORIGINAL_PROXY

InstallMysql "${_PASSWORD}"

InstallNodejs '8'

# ====================================== Setup Database ======================
mysql -uroot -p"${_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE refstack;
CREATE USER 'refstack'@'localhost' IDENTIFIED BY '$_PASSWORD';
GRANT ALL PRIVILEGES ON refstack . * TO 'refstack'@'localhost';
FLUSH PRIVILEGES;

MYSQL_SCRIPT

# ====================================== Setup Refstack ======================
caller_user=$(who -m | awk '{print $1;}')
caller_user=${caller_user:-'ubuntu'}
fqdn="$(hostname)"
[[ -n "$(hostname -d)" ]] && fqdn="${fqdn}.$(hostname -d)"
#fqdn='localhost'

# Install refstack client - Shorter task
echo "INSTALLING REFSTACK CLIENT"
REF_CLIENT="${_DEST_PATH}-client"
[[ ! -d "$REF_CLIENT" ]] && git clone ${_OREPO}/refstack-client $REF_CLIENT
chown -R $caller_user $REF_CLIENT
pushd $REF_CLIENT
sudo -HE -u $caller_user bash -c "./setup_env"
popd

echo "INSTALLING REFSTACK SERVER, API AND UI"
[[ ! -d "$_DEST_PATH" ]] && git clone ${_OREPO}/refstack $_DEST_PATH
chown -R $caller_user $_DEST_PATH
pushd $_DEST_PATH
sudo -HE -u $caller_user bash -c 'virtualenv .venv --system-site-package; source .venv/bin/activate; pip install .; pip install pymysql; pip install gunicorn;'
sudo -HE -u $caller_user bash -c 'npm install'

CFG_FILE='etc/refstack.conf'
sudo -HE -u $caller_user bash -c "cp etc/refstack.conf.sample $CFG_FILE"
sed -i "s/#connection = <None>/connection = mysql+pymysql\:\/\/refstack\:$_PASSWORD\@localhost\/refstack/g" $CFG_FILE
sed -i "/ui_url/a ui_url = http://$fqdn:8000" $CFG_FILE
sed -i "/api_url/a api_url = http://$fqdn:8000" $CFG_FILE
sed -i "/app_dev_mode/a app_dev_mode = true" $CFG_FILE
sed -i "/debug = false/a debug = true" $CFG_FILE

CFG_FILE='refstack-ui/app/config.json'
sudo -HE -u $caller_user bash -c "cp ${CFG_FILE}.sample ${CFG_FILE}"
sed -i "s/refstack.openstack.org/$fqdn:8000/g" ${CFG_FILE}

# DB SYNC IF VERSION IS None
source .venv/bin/activate
if [[ ! -z $(refstack-manage --config-file $CFG_FILE version | grep -i none) ]]; then
    refstack-manage --config-file $CFG_FILE upgrade --revision head
    # Verify upgrade actually happened
    msg="After sync DB, version is still displayed as None."
    [[ ! -z $(refstack-manage --config-file $CFG_FILE version | grep -i none) ]] && PrintError $msg
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
