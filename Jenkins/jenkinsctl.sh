#!/bin/bash
ctrlArg=$1
export JENKINS_RUN_PATH="$(dirname $0)"
# If the path is not absolute add it to pwd
if [ "${JENKINS_RUN_PATH:0:1}" == '.' -o "${JENKINS_RUN_PATH}" == './' ]; then
    JENKINS_RUN_PATH="${PWD}${JENKINS_RUN_PATH:1:${#JENKINS_RUN_PATH}}"
fi    
if [ "${ctrlArg}" != 'stop'  -a  "${ctrlArg}" != 'start'  -a  "${ctrlArg}" != 'restart' ]; then
    printf "\n!!!\tUnkown arg entered %s\t!!!\n\n" "${ctrlArg}"
    cat ${JENKINS_RUN_PATH}/ReadMe.txt
    exit 999
fi
${JENKINS_RUN_PATH}/.jenkinsctl_main.sh $*
exit $?
#commentted line
