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

_DEST_PATH='/opt/refstack'
_DREPO='https://raw.githubusercontent.com/dlux/InstallScripts/master'
_OREPO='http://git.openstack.org/openstack'
_PASSWORD='secure123'
_PORT='8000'
_PROTOCOL='http'
_VIRTUAL_ENV=False
_CLIENT=False

_CALLER_USER=$(who -m | awk '{print $1;}')
_CALLER_USER=${_CALLER_USER:-'ubuntu'}
#_FQDN="$(hostname)"
#[[ -n "$(hostname -d)" ]] && _FQDN="${_FQDN}.$(hostname -d)"
_FQDN=localhost

[[ ! -f common_functions ]] && curl -O "${_DREPO}"/common_functions
[[ ! -f common_packages ]] && curl -O "${_DREPO}"/common_packages

source common_packages

# ======================= Processes installation options =====================
while [[ ${1} ]]; do
    case "${1}" in
        --client|-c)
            _CLIENT=True
            ;;
        --password|-p)
            [[ -z "${2}" || "${2}" == -* ]] && PrintError "Missing password." || _PASSWORD="${2}"
            shift
            ;;
        --ssl|-s)
            _PROTOCOL='https'
            PrintError "ssl under development"
            ;;
        --virtual|-v)
            _VIRTUAL_ENV=True
            PrintError "Install on venv under development"
            ;;
        --help|-h)
            PrintHelp "Install refstack server " $(basename "$0") \
                      "    --client | -c   Install refstack client. Deafault is False.
    --password | -p   Password to be used on the DB.
    --virtual  | -v   Refstack server will be installed on a venv vs system wide."
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

[[ ! -f install_devtools.sh ]] && curl -O ${_DREPO}/install_devtools.sh; chmod +x install_devtools.sh;
./install_devtools.sh

InstallNodejs '6'

# ================================== Setup Database ==========================
InstallMysql "${_PASSWORD}"
HardeningaptMysql "${_PASSWORD}"

mysql -uroot -p"${_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE refstack;
CREATE USER 'refstack'@'localhost' IDENTIFIED BY '$_PASSWORD';
GRANT ALL PRIVILEGES ON refstack . * TO 'refstack'@'localhost';
FLUSH PRIVILEGES;

MYSQL_SCRIPT

# ================================== Install Refstack Client =================
if [ _CLIENT == True ]; then
    echo "INSTALLING REFSTACK CLIENT"
    REF_CLIENT="${_DEST_PATH}-client"
    [[ ! -d "$REF_CLIENT" ]] && git clone ${_OREPO}/refstack-client $REF_CLIENT
    pushd $REF_CLIENT
    ./setup_env
    chown -R $_CALLER_USER $REF_CLIENT
    popd
fi
# ================================== Install nginx for SSL ===================
# InstallNginx

# ================================== Install Refstack ========================
echo "INSTALLING REFSTACK SERVER: API AND UI"
[[ ! -d "$_DEST_PATH" ]] && git clone ${_OREPO}/refstack $_DEST_PATH
pushd $_DEST_PATH

[[ $_PROTOCOL -eq 'http' ]] && pip install gunicorn
pip install .
pip install pymysql

npm install
sudo -HE -u $_CALLER_USER bash -c 'npm install'

# Handle UI configuration
echo "{\"refstackApiUrl\": \"${_PROTOCOL}://${_FQDN}:${_PORT}/v1\"}" > 'refstack-ui/app/config.json'

# Handle API configuration
cfg_file='etc/refstack.conf'
cat <<EOF > "${cfg_file}"
[DEFAULT]
debug = True
verbose = True
ui_url = ${_PROTOCOL}://${_FQDN}:${_PORT}

[api]
api_url = ${_PROTOCOL}://${_FQDN}:${_PORT}
app_dev_mode = True

[database]
connection = mysql+pymysql://refstack:${_PASSWORD}@localhost/refstack

[osid]
#openstack_openid_endpoint = https://172.17.42.1:8443/accounts/openid2

EOF

# DB SYNC
refstack-manage --config-file $cfg_file upgrade --revision head
# Verify upgrade actually happened
msg="After sync DB, version is still displayed as None."
[[ ! -z $(refstack-manage --config-file $cfg_file version | grep -i none) ]] && PrintError $msg

echo "Generate HTML templates from docs"
python tools/convert-docs.py -o refstack-ui/app/components/about/templates doc/source/*.rst

echo "Starting Refstack Server. Run daemon on refstack-svr screen session."
echo "refstack-api --env REFSTACK_OSLO_CONFIG=etc/refstack.conf"
# Run on deatached screen session
screen -dmS refstack-screen bash -c 'sudo refstack-api --env REFSTACK_OSLO_CONFIG=etc/refstack.conf'

# Cleanup _proxy from apt if added - first coincedence
UnsetProxy $_ORIGINAL_PROXY
popd
echo "Finished Installation Script"
