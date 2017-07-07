#!/bin/bash

MASTER_NAME=$1
echo $MASTER_NAME

# disable selinux
    sed -i 's/enforcing/disabled/g' /etc/selinux/config
    setenforce permissive

# Shares
SHARE_HOME=/share/home
NFS_ON_MASTER=/share/data
NFS_MOUNT=/share/data
APPS_ON_MASTER=/share/apps
APPS_MOUNT=/share/apps

mkdir -p /share
mkdir -p $SHARE_HOME

# Groups and Users
#
# Arrays of colon-delimited strings for group, user, and share access info
#   Each group input entry consists of name:gid
#   Each user input entry consists of name:uid:gname:fullname:access, where access is either nosudo or sudo.
#     If the access entry is sudo, the user has passwordless sudo access.
#   Each share entry consists of sharename:owner:group:access, where access is the usual octal input to chmod.
#
# The FIRST_USER boolean is used to execute certain sudo-related steps only once if multiple sudo users exist.
HPC_GROUP_INPUT=( "hpc:7007" )
HPC_USER_INPUT=( "hpcmaster:7007:hpc:HPC Master:sudo" "scrock:7008:hpc:SCrockett:sudo" "eeker:7009:hpc:EEker:nosudo" )
HPC_SHARE_INPUT=( "${NFS_MOUNT}:hpcmaster:hpc:1770" "${APPS_MOUNT}:hpcmaster:hpc:0750" )
FIRST_USER="true"

mount_nfs()
{
	yum -y install nfs-utils nfs-utils-lib
	
	echo "${MASTER_NAME}:${SHARE_HOME} ${SHARE_HOME} nfs4 rw,auto,_netdev  0 0" >> /etc/fstab
	mount -a

	mkdir -p ${NFS_MOUNT} ${APPS_MOUNT}

	showmount -e ${MASTER_NAME}
	mount -t nfs ${MASTER_NAME}:${NFS_ON_MASTER} ${NFS_MOUNT}
	mount -t nfs ${MASTER_NAME}:${APPS_ON_MASTER} ${APPS_MOUNT}
	
	echo "${MASTER_NAME}:${NFS_ON_MASTER} ${NFS_MOUNT} nfs defaults,nofail  0 0" >> /etc/fstab
	echo "${MASTER_NAME}:${APPS_ON_MASTER} ${APPS_MOUNT} nfs defaults,nofail  0 0" >> /etc/fstab
	
	mount
}

setup_group()
{
    # Extract fields from entry, and generate the 'groupadd' command to be executed so this group is created...then execute it
	GROUP_ADD_CMD=`echo $GROUP_ENTRY | awk -F: '{printf "groupadd -g %d %s\n", $2, $1}'`
	$GROUP_ADD_CMD
}

setup_user()
{  

    # Extract fields from entry, and fill local variables with these values
	VAR_SET=`echo $USER_ENTRY | awk -F: '{printf "HPC_USER=%s;HPC_UID=%d;HPC_GNAME=%s;HPC_FULLNAME=\"%s\";SUDOFLAG=%s\n", \
		$1, $2, $3, $4, $5}'`
	$VAR_SET
	
    # Don't require sudo password for any user whose access flag is "sudo"; others cannot sudo
	if [ "${SUDOFLAG}" = "sudo" ]; then
		if [ "${FIRST_USER}" = "true" ]; then
			sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers
			FIRST_USER="false"
		fi
		echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
	fi
    
    # Add user
	useradd -c "${HPC_FULLNAME}" -g ${HPC_GNAME} -d ${SHARE_HOME}/${HPC_USER} -s /bin/bash -u ${HPC_UID} ${HPC_USER}
}

setup_shares()
{
    # Extract fields from entry, and fill local variables with these values
	VAR_SET=`echo $USER_ENTRY | awk -F: '{printf "SHARENAME=%s;HPC_USER=%s;HPC_GNAME=%s;PERMS=%s\n", \
		$1, $2, $3, $4}'`
	$VAR_SET

    # modify ownership and permissions

	chown ${HPC_USER}:${HPC_GNAME} ${SHARENAME}
	chmod ${PERMS} ${SHARENAME}
}

mount_nfs
for GROUP_ENTRY in "${HPC_GROUP_INPUT[@]}"; do
	setup_group
done
for USER_ENTRY in "${HPC_USER_INPUT[@]}"; do
	setup_user
done
for SHARE_ENTRY in "${HPC_NFS_SHARES[@]}"; do
	setup_shares
done

exit 0
