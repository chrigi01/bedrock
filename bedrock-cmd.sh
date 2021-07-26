#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#  script to setup and control a bedrock minecraft server
#  MIT License 
#  Copyright (c) 2020 Christian Giese  
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

show_functions() {
    echo  "$0 start | stop | status | logs "
    echo "$0 backup | restore "
    echo "$0 install | uninstall | update | upgrade "
    echo "$0 service enable | disable "
    echo "$0 edit server.properties "
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

SCRIPT_VERSION=1.0.2
SCRIPT_NAME=bedrock-cmd.sh

USER=mc
SERVICE_NAME=${USER}

BASE_DIR=/opt/mc
SERVER_BASE_DIR=${BASE_DIR}/server
[[ -f ${SERVER_BASE_DIR}/version ]] && SERVER_VERSION=$( cat ${SERVER_BASE_DIR}/version ) || SERVER_VERSION=0 
DATA_BASE_DIR=${SERVER_BASE_DIR}/worlds
DATA_ARCHIVE_DIR=${SERVER_BASE_DIR}/backup

SCRIPT_EXEC=${BASE_DIR}/${SCRIPT_NAME}
SERVICE_DEFINITION=/etc/systemd/system/${SERVICE_NAME}.service
SERVICE_EXEC="/bin/bash ${SCRIPT_EXEC} service run"

PROPERTY_FILE=${SERVER_BASE_DIR}/server.properties

CRON_DIR=/etc/cron.daily/
CRON_FILE=${CRON_DIR}/bedrock-server
CRON_FILE_TMP=${SERVER_BASE_DIR}/cron.tmp

TIMESTAMP=$( date +"%Y-%m-%d_%H:%M:%S" )
TIMESTAMP2=$( date +"%Y-%m-%d_%H%M%S" )
BACKUP_DIR=${DATA_BASE_DIR}/${TIMESTAMP}
BACKUP_NAME=archive
BACKUP_EXT=tgz

LOG_FILE=${BASE_DIR}/bedrock-server.log

UPGRADE_SERVER_FILE=bedrock-server
UPGRADE_URL=https://raw.githubusercontent.com/chrigi01/bedrock/main/currentversion
LATEST_VERSION=$(curl --silent ${UPGRADE_URL} )
INITIAL_VERSION=1.16.200.02
DOWNLOAD_URL=https://minecraft.azureedge.net/bin-linux

UPDATE_URL=https://raw.githubusercontent.com/chrigi01/bedrock/main/bedrock-cmd.sh

MAIN=bedrock-main

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#  helper functions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

do_log() {
local L_SEVERITY=$1
local L_MSG=$2
local L_FUNCTION=
[[ "$3" = "" ]] && L_FUNCTION="${FUNCTION}" || L_FUNCTION="$3"

BLACK="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
ORANGE="\033[33m"
BLUE="\033[35m"


    case ${L_SEVERITY} in
    SUCCESS)
        COLOR=${GREEN}
        ;;
    ERROR)
        COLOR=${RED}
        ;;
    WARN)
        COLOR=${ORANGE}
        ;;
    HEAD)
        COLOR=${BLUE}
        ;;
     "")
        if [[ "${FAILURE}" = "0" ]]
        then 
            COLOR=${GREEN}
            L_MSG=ok
        else
            COLOR=${RED}
            L_MSG=failed
        fi
        ;;
    *)
        COLOR=${BLACK}
        ;;
    esac

L_COLOR_MSG="${COLOR} ${L_FUNCTION}: ${L_MSG} ${BLACK}"
L_LOG_MSG="${TIMESTAMP}-${L_FUNCTION}-${L_SEVERITY}: ${L_MSG}"

    if [[ "${L_SEVERITY}" = "DEBUG" ]]
    then
        echo ${L_LOG_MSG} >> ${LOG_FILE}
    else
        echo -e ${L_COLOR_MSG}
        echo ${L_LOG_MSG} >> ${LOG_FILE}
    fi


}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#  tier 2 functions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

do_set_failure() {
    FAILURE=1
    do_log ERROR "activity failed"
}

do_init_result_message() {
FAILURE=0
}

do_result_message() {
local FUNCTION=$1
    if [ "${FAILURE}" = "0" ]
    then
        do_log HEAD "OK"
    else
        do_log HEAD "FAILED"
    fi;
} 


install_server_software() {
local FUNCTION=install_server_software
local L_VERSION=$1
local L_FILE=${UPGRADE_SERVER_FILE}-${L_VERSION}.zip
local L_URL=${DOWNLOAD_URL}/${L_FILE}
local L_SERVER_TEMP_DIR=${SERVER_BASE_DIR}_temp

	do_log DEBUG "L_URL=${L_URL}"
	do_log DEBUG "SERVER_BASE_DIR=${SERVER_BASE_DIR}"

    if [ -d ${SERVER_BASE_DIR} ]
    then 
          mv ${SERVER_BASE_DIR} ${L_SERVER_TEMP_DIR}
    fi
    mkdir -p ${SERVER_BASE_DIR}

    # download bedrock server software
	cd ${SERVER_BASE_DIR}
	wget ${L_URL} 
	unzip ${L_FILE} > /dev/null 2>&1  
	rm -f ${L_FILE}

    # make server executable
	chmod 750 ${SERVER_BASE_DIR}/bedrock_server

    # create archive directories
    mkdir ${DATA_ARCHIVE_DIR}

    # migrate data 
    if [ -d ${L_SERVER_TEMP_DIR} ]
    then 
       cp ${L_SERVER_TEMP_DIR}/server.properties ${SERVER_BASE_DIR}/server.properties
       cp -TR ${L_SERVER_TEMP_DIR}/worlds/ ${SERVER_BASE_DIR}/worlds/ 	
       rm -rf ${L_SERVER_TEMP_DIR}
    fi    
	do_log
}

do_tar_dir() {
local FUNCTION=do_tar_dir
local L_TAR_NAME=$1
local L_TAR_DIR=$2
local L_ARCHIVE_DIR=$3
local PWD=$( pwd )
    # archive directory to zipped tar file
	do_log DEBUG "archive ${L_TAR_DIR} to ${L_ARCHIVE_DIR}/${L_TAR_NAME}.${BACKUP_EXT}"
	cd  ${L_TAR_DIR}
    tar --exclude=*.${BACKUP_EXT} -czf ${L_TAR_NAME}.${BACKUP_EXT} .
    mv ${L_TAR_NAME}.${BACKUP_EXT} ${L_ARCHIVE_DIR}/
    cd ${PWD}    
	do_log
}

do_untar_to_dir() {
local FUNCTION=do_untar_to_dir
local L_TAR_NAME=$1
local L_TAR_DIR=$2
local L_PWD=$( pwd )

	do_log DEBUG "unarchive ${L_TAR_NAME} to ${L_TAR_DIR}"
	cd  ${L_TAR_DIR}
    tar xzf ${L_TAR_NAME}
    cd ${L_PWD}

	do_log INFO "ok"
}

get_latest_version() {
local FUNCTION=get_latest_version
local L_FILE=${UPGRADE_SERVER_FILE}-${LATEST_VERSION}.zip
local L_URL=${DOWNLOAD_URL}/${L_FILE}

    # make sure new version software can be downloaded
    if wget -q --method=HEAD ${L_URL};
    then
        do_log DEBUG "${L_LATEST_VERSION} is downable URL ${L_URL}"
    else
        do_log ERROR "${L_LATEST_VERSION} is not downable URL ${L_URL}"
        do_log INFO "instead of version ${L_LATEST_VERSION} using version ${SERVER_VERSION}"
        LATEST_VERSION=${SERVER_VERSION}
    fi
    do_log
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#  tier 1 - functions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

do_upgrade_packages() {
local FUNCTION=do_upgrade_packages
	do_log INFO "upgrade necessary ubuntu packages"
    sudo apt-get update
    sudo apt-get -y upgrade
    sudo apt -y install curl
    sudo apt -y install wget
    sudo apt -y install unzip
    sudo apt install net-tools
	do_log 
}

do_pre_install() {
local FUNCTION=do_pre_install    
	do_log
}

do_post_install() {
local FUNCTION=do_post_install
    # create daily backup with cron
    echo "#!/bin/bash" > ${CRON_FILE_TMP}
    sudo cat >> ${CRON_FILE_TMP} << EOF
sudo -H -u ${USER} bash -c '${SCRIPT_EXEC} upgrade' 
EOF
    sudo cp ${CRON_FILE_TMP} ${CRON_FILE}
    rm -f ${CRON_FILE_TMP}
    sudo chmod 755 ${CRON_FILE}
	do_log 
}

do_uninstall() {
local FUNCTION=do_uninstall
local L_TAR_NAME=${TIMESTAMP2}_${SERVER_VERSION}_${SERVICE_NAME}
	# archive all data (bedrock versions, worlds and backups)    
    do_tar_dir ${L_TAR_NAME} ${SERVER_BASE_DIR} ${BASE_DIR}
    	# delete all data (bedrock versions, worlds and backups)    
	rm -rf ${SERVER_BASE_DIR}
	rm -f ${BASE_DIR}/*.log
	sudo rm -f ${CRON_FILE}
	sudo rm -f ${SERVICE_DEFINITION} 
	do_log
}

set_server_version() {
local FUNCTION=set_server_version
local L_VERSION=$1
	do_log DEBUG "${L_VERSION}"
	SERVER_VERSION=${L_VERSION}
    echo ${L_VERSION} > ${SERVER_BASE_DIR}/version 
	do_log DEBUG "ok"
}

do_install() {
local FUNCTION=do_install
local L_VERSION=
[[ "$1" = "" ]] && L_VERSION=${INITIAL_VERSION} || L_VERSION=$1  
	do_log DEBUG ${L_VERSION}
    install_server_software ${L_VERSION}
    set_server_version ${L_VERSION}
	do_log
}

do_update() {
local FUNCTION=do_update
    # backup script
    mv ${SCRIPT_EXEC} ${SCRIPT_EXEC}_${SCRIPT_VERSION}
    # get current script version
    curl ${UPDATE_URL} --output ${SCRIPT_NAME}
    chmod 750 ${SCRIPT_EXEC}
	do_log SUCCESS "update done"	    
}

do_upgrade() {
local FUNCTION=do_upgrade
local L_BACKUP_NAME=${TIMESTAMP2}_${SERVER_VERSION}

    # check the latest version
    get_latest_version
    if [[ "${LATEST_VERSION}" = "${SERVER_VERSION}" ]]
    then
	    do_log SUCCESS "version ${LATEST_VERSION} already installed"
	    do_log SUCCESS "no need to upgrade"	    
    else
	    do_log INFO "new version ${LATEST_VERSION} will be installed"
        # archive previouse version
        do_tar_dir ${L_BACKUP_NAME} ${SERVER_BASE_DIR} ${BASE_DIR}
        # install new version
        do_install ${LATEST_VERSION}
    fi
	do_log
}

do_backup() {
local FUNCTION=do_backup
local L_BACKUP_NAME=${TIMESTAMP2}_${BACKUP_NAME}
    do_tar_dir ${L_BACKUP_NAME}  ${DATA_BASE_DIR} ${DATA_ARCHIVE_DIR}  
	do_log SUCCESS "ok"
}

do_restore() {
local FUNCTION=do_restore
local NUMBER_OF_BACKUPS=$( ls -l  ${DATA_ARCHIVE_DIR}/*.${BACKUP_EXT}  | wc -l ) 
local L_RESTORE_FILE_NAME=""

    if [[ "${NUMBER_OF_BACKUPS}" = "0" ]]
    then
    	do_log INFO "no backups found"
    else 
    	do_log INFO "${NUMBER_OF_BACKUPS} backups found"
        ls  ${DATA_ARCHIVE_DIR}/*.${BACKUP_EXT}  | xargs -n 1 basename
        
        read -p "which backup should be restored: " L_RESTORE_FILE_NAME < /dev/tty	
        
        if [[ "${L_RESTORE_FILE_NAME}" = "" ]]
        then
            do_log ERROR "provided filename is empty"
            do_set_failure
        elif [[ ! -f ${DATA_ARCHIVE_DIR}/${L_RESTORE_FILE_NAME} ]]
        then
            do_log ERROR "provides filename does not exists"
            do_log ERROR "please check ${DATA_BASE_DIR}/${L_RESTORE_FILE_NAME}"
            do_set_failure
        else
            do_log DEBUG "start to restore ${DATA_ARCHIVE_DIR}/${L_RESTORE_FILE_NAME}"        
            rm -rf ${DATA_BASE_DIR}
            mkdir -p ${DATA_BASE_DIR}
            cp ${DATA_ARCHIVE_DIR}/${L_RESTORE_FILE_NAME} ${DATA_BASE_DIR}/
            do_untar_to_dir ${L_RESTORE_FILE_NAME}  ${DATA_BASE_DIR}
        fi
    fi    
	do_log
}

do_start() {
local FUNCTION=do_start
	sudo systemctl start ${SERVICE_NAME}
	do_log 
}

do_stop() {
local FUNCTION=do_stop
	sudo systemctl stop ${SERVICE_NAME}
	do_log 
}

show_status() {
local FUNCTION=show_status
	sudo systemctl status ${SERVICE_NAME}
	netstat -a | grep 19132
	tail -10 ${LOG_FILE}
}

do_create_service() { 
local FUNCTION=do_create_service
SERVICE_FILE_TMP=${SERVER_BASE_DIR}/${SERVICE_NAME}.service_tmp
  
	cat > ${SERVICE_FILE_TMP} <<EOF  
[Unit]
Description=Minecraft Bedrock Server
After=network.target
StartLimitIntervalSec=0
[Service]
Type=simple
Restart=always
RestartSec=1
User=${USER}
ExecStart=${SERVICE_EXEC}
[Install]
WantedBy=multi-user.target
EOF

    sudo cp ${SERVICE_FILE_TMP} ${SERVICE_DEFINITION} 
    rm -f ${SERVICE_FILE_TMP} 
	sudo systemctl daemon-reload 

	do_log 
}

do_destroy_service() {
local FUNCTION=do_destroy_service
	sudo rm -f ${SERVICE_DEFINITION} 
	sudo systemctl daemon-reload 
	do_log 
}

do_run_service() {
local FUNCTION=do_run_service
do_log INFO "SCRIPT_VERSION=${SCRIPT_VERSION}"
do_log INFO "call: $0 $1 $2"
do_log INFO "SERVER_VERSION=${SERVER_VERSION}"
do_log INFO "LATEST_VERSION=${LATEST_VERSION}"

cd ${SERVER_BASE_DIR}
echo SERVER_BASE_DIR ${SERVER_BASE_DIR}
./bedrock_server >> ${LOG_FILE}
}

do_enable_service() {
local FUNCTION=do_enable_service
	sudo systemctl enable ${SERVICE_NAME}
	do_log 
}

do_disable_service() {
local FUNCTION=do_disable_service
	sudo systemctl disable ${SERVICE_NAME}
	do_log 
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# main
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

do_init_result_message
case ${SERVER_VERSION} in
0)
    do_log HEAD "install bedrock server" ${MAIN}
    do_upgrade_packages
    do_install
    do_create_service
    do_enable_service 
    do_upgrade	cron
    do_post_install
    do_start 
	;;	
*)	
    do_log HEAD "$1 $2" ${MAIN} ${SCRIPT_VERSION}
    echo "Version ${SCRIPT_VERSION}"
    case $1 in
    uninstall)
        do_stop 
        do_disable_service 
        do_destroy_service
	    do_uninstall
	    ;;
    update)
	    do_stop
	    do_update
        do_start
	    ;;
    upgrade)
	    do_stop
        do_backup
        do_update
	    do_upgrade
        do_start
	    ;;
    start)
        do_start	
	    ;;
    restart)
	    do_stop
	    do_backup
	    do_start
	    ;;
    stop)
        do_stop	
	    ;;
    status)
 	   show_status	
	    ;;
    logs)
	    less ${LOG_FILE}
	    ;;
    backup)
    	do_stop
    	do_backup
	    do_start
	    ;;
    restore)
	    do_stop
        do_backup
	    do_restore
	    do_start
	    ;;
    edit)
	    case $2 in
	    server.properties)
	        vi ${PROPERTY_FILE}
            ;;
        esac
        ;;
    service)
	    case $2 in
	    run)
	        do_run_service
            ;;
	    enable)
            do_enable_service
		    ;;
    	disable)
	        do_disable_service
    		;;
        *)
	        show_functions
	        ;; 
	    esac
	    ;;
    *)
	    show_functions
	    ;; 
    esac
    ;;
esac
do_result_message $1

exit 0 
