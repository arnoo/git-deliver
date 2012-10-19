#!/bin/bash

#
#   Copyright 2012 Arnaud Betremieux <arno@arnoo.net>
#
#   The program in this file is free software: you can redistribute it
#   and/or modify it under the terms of the GNU General Public License
#   as published by the Free Software Foundation, either version 3 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

REPO_ROOT=`git rev-parse --git-dir 2> /dev/null` # for some reason, --show-toplevel returns nothing
if [[ $? -gt 0 ]]; then
	echo "ERROR : not a git repo" >&2
	exit 1
fi
if [[ $REPO_ROOT = ".git" ]]; then
	REPO_ROOT=`pwd`
else
	REPO_ROOT=${REPO_ROOT%/.git}
fi

GIT_DELIVER_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$GIT_DELIVER_PATH/lib/shflags"

#TODO: gaffe a bien >&2 ce qui doit l'être
#TODO: option deliver juste en rsync ? pour shared hosting / FTP ?

function confirm_or_exit
	{
	if [[ "$1" = "" ]]; then
	    local MSG="Continue ?"
	else
	    local MSG=$1
	fi
	read -p "$MSG (y/n) " -n 1 REPLY
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
	}

function print_help
	{
	echo "git deliver <REMOTE> <VERSION>"
	echo "git deliver --init [hooks]"
	echo "git deliver --init-remote <REMOTE>"
	echo "git deliver --list-hooks"
	echo "git deliver --status"
	echo "git deliver --fetch-log [REMOTE]"
	echo "git deliver --log [REMOTE]"
	exit 1
	}

function log
	{
	local REMOTE="$1"
	if [[ "$REMOTE" = "" ]]; then
		for R in `git remote`; do
			log $R
		done
	else
		LOG="$REPO_ROOT/.deliver/logs/$REMOTE"
		if [[ -f "$LOG" ]]; then
			cat "$REPO_ROOT/.deliver/logs/$REMOTE"
		else
			echo "No delivery log for remote $REMOTE"
		fi
	fi
	}

function fetch_log
	{
	local REMOTE="$1"
	if [[ "$REMOTE" = "" ]]; then
		for R in `git remote`; do
			fetch_log "$R"
		done
	else
		remote_info "$REMOTE"
		rsync "$REMOTE_URL/deliver_log" "$REPO_ROOT/.deliver/logs/$REMOTE"
	fi
	}

function repo_status
	{
	local REMOTE=$1
	if [[ "$REMOTE" = "." ]]; then
		if [[ -d "$REPO_ROOT/.deliver" ]]; then
		echo "Repository initialized"
		fi
	elif [[ $REMOTE -eq '' ]]; then
		for R in `git remote`; do
			repo_status $R
		done
	else
		remote_info $REMOTE
		$EXEC_REMOTE #TODO
	fi
	}

function list_hooks
	{
	for HOOK_PATH in $GIT_DELIVER_PATH/hooks/*; do
		HOOK=`basename "$HOOK_PATH"`
		if [[ "$HOOK" != "core" ]] && [[ -f "$HOOK_PATH/info" ]]; then
			source "$HOOK_PATH/info"
			echo "$HOOK : $DESCRIPTION [$DEPENDENCIES]"
		fi
	done
	}

function check_hook
	{
	local HOOK=$1
	if [[ -d "$GIT_DELIVER_PATH/hooks/$HOOK" ]]; then
		local DEPENDENCIES=""
		local DESCRIPTION="ERROR"
		local INFO_PATH="$GIT_DELIVER_PATH/hooks/$HOOK/info"
		if [[ ! -f "$INFO_PATH" ]]; then
			echo "ERROR : Info file for hook $HOOK not found" >&2
			exit 1
		fi
		source "$INFO_PATH"
		if [[ "$DESCRIPTION" = "ERROR" ]] || [[ "$DESCRIPTION" = "" ]]; then
			echo "ERROR : Missing description for hook $HOOK" >&2
			exit 1
		fi
		local OLDIFS=$IFS
		IFS=',' read -ra DEPENDENCIES <<< "$DEPENDENCIES"
		for DEP in "${DEPENDENCIES[@]}"; do
			check_hook "$DEP"
		done
	else
		echo "ERROR : could not find hook $HOOK" >&2
		exit
	fi
	}


# Copies the files for hook $1 to the repo's .deliver/hooks directory
function init_hook
	{
	local HOOK=$1
	local HOOK_SCRIPT
	#TODO: interdire init si deja init sauf flag specifique (et dans ce cas cp -i)
	for HOOK_STAGE_DIR in "$GIT_DELIVER_PATH/hooks/$HOOK"/*; do
		[ -d $HOOK_STAGE_DIR ] || continue
		local HOOK_STAGE=`basename $HOOK_STAGE_DIR`
		for HOOK_SCRIPT_FILE in "$HOOK_STAGE_DIR"/*; do
			local HOOK_SCRIPT_NAME=`basename $HOOK_SCRIPT_FILE`
			local HOOK_SEQNUM=`echo $HOOK_SCRIPT_NAME | grep -o '^[0-9]\+'`
			local HOOK_LABEL=${HOOK_SCRIPT_NAME:$((${#HOOK_SEQNUM}+1))}
			cp -f $HOOK_SCRIPT_FILE "$REPO_ROOT"/.deliver/hooks/$HOOK_STAGE/$HOOK_SEQNUM-$HOOK_LABEL
		done
	done
        source "$GIT_DELIVER_PATH/hooks/$HOOK"/info
        #TODO: init_hook de chaque DEPENDENCIES
	}

function init
	{
	local HOOKS=$1
	IFS=',' read -ra HOOKS <<< "$HOOKS"
	for HOOK_DIR in "${HOOKS[@]}"; do
		local HOOK=`basename $HOOK_DIR`
		check_hook $HOOK
        done
	mkdir -p "$REPO_ROOT/.deliver/hooks"
	for HOOK in init-remote check post-checkout post-symlink rollback; do
		mkdir "$REPO_ROOT/.deliver/hooks/$HOOK"
	done
	echo "Setting up core hooks" >&2
	init_hook core
	for HOOK_DIR in "${HOOKS[@]}"; do
		local HOOK=`basename $HOOK_DIR`
		echo "Setting up $HOOK hooks" >&2
		init_hook $HOOK
	done
	#TODO: git hook sur fetch pour maj log livraison depuis log remote
	}

function run_hooks
	{
	local STAGE=$1
	echo "Running hooks for stage $STAGE" >&2
	for HOOK in hooks/$STAGE/*.sh; do
		echo -n "$STAGE/$HOOK" >&2
		source $HOOK;
		local HOOK_RESULT=$?
		if [[ $HOOK_RESULT -gt 0 ]]; then
			echo "" >&2
			echo "Hook returned with status $HOOK_RESULT" >&2
			rollback $STAGE
			exit
		else
			echo "	[OK]"
		fi
	done
	}

function remote_info
	{
	local REMOTE=$1
	local INIT=$2
	local INIT_URL=$3
	local REMOTE_INFO
	REMOTE_INFO=`git remote -v | grep '^'"$REMOTE"'$' | grep '(push)'`
	if [[ $? -gt 0 ]] && $INIT; then
		confirm_or_exit "Remote $REMOTE not found. Create it ?"
		echo ""
		if [[ $INIT_URL = "" ]]; then
			read -p "URL for remote :" INIT_URL
		fi
		git remote add $REMOTE $INIT_URL
		if [[ ! $IN_INIT ]]; then
			init_remote
		fi
	fi

	REMOTE_URL=`echo "$REMOTE_INFO" | cut -f 2 | cut -d\  -f 1`
	REMOTE_SERVER=`echo "$REMOTE_URL" | cut -d: -f 1`
	REMOTE_PATH=`echo "$REMOTE_URL" | cut -d: -f 2`

	if [[ $REMOTE_PATH -eq "" ]]; then
		REMOTE_PATH=$REMOTE_SERVER;
		REMOTE_SERVER=""
		EXEC_REMOTE=""
	else
		EXEC_REMOTE="ssh $REMOTE_SERVER"
	fi
	}

function init_remote
	{
	if [[ $3 != "" ]] || [[ $1 = "" ]]; then
		print_help
		exit 1
	fi
	IN_INIT=true
	local REMOTE=$1
	remote_info $REMOTE true $2
	#TODO: check that remote URL does not already exist
	echo "$REPO_ROOT"
	scp -r "$REPO_ROOT/.git" "$REMOTE_URL"
	exit
	$EXEC_REMOTE git config --bool core.bare true
	$EXEC_REMOTE mkdir delivered
	run_hooks "init-remote"
	IN_INIT=""
	}

function deliver
	{
	if [[ $3 != "" ]] || [[ $1 = "" ]] || [[ $2 = "" ]]; then
		print_help
		exit 1
	fi
	local REMOTE=$1
	local VERSION=$2
	if [[ ! -d "$REPO_ROOT"/.deliver ]]; then
		confirm_or_exit ".deliver not found in git directory. Run init ?"
		init
	fi

	if [[ `$EXEC_REMOTE ls $REMOTE_PATH/hooks $REMOTE_PATH/refs 2> /dev/null | wc -l` -lt 2 ]]; then
		echo "ERROR : Remote does not look like a bare git repo" >&2
		exit 1
	fi
	run_hooks "check"

	local VERSION_SHA=`git rev-parse $VERSION 2> /dev/null`
	local VERSION_EXISTS= [[ $? -gt 0 ]];

	local PREVIOUS_VERSION_SHA=`git rev-parse delivered-$REMOTE`
	if [[ $? -gt 0 ]]; then
		echo "No version delivered yet on $REMOTE" >&2
	else
		echo -n "Current version on $REMOTE is " >&2
		git name-rev $REMOTE >&2
	fi

	if [[ ! $VERSION_EXISTS ]]; then
		confirm_or_exit "Ref $VERSION not found. Tag current HEAD ?" >&2
		VERSION_SHA=`git rev-parse HEAD`
		echo "Tagging current HEAD" >&2
		git tag $VERSION
		echo "Pushing tag to origin" >&2
		git push origin $VERSION
	elif [[ $PREVIOUS_VERSION_SHA -eq $VERSION_SHA ]]; then
		confirm_or_exit "Tag or branch delivered-$REMOTE found. This would indicate that this version ($VERSION) has already been delivered to $REMOTE. Proceed anyway ?"
	fi

	# make sure the remote has all the commits leading to the version to be delivered
	git push $REMOTE $VERSION

	# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked. A shallow clone with depth one would do, but it would use more disk space because we wouldn't be able to share the files with the bare repo through hard links (git clone does that by default).
	$EXEC_REMOTE git clone --reference $REMOTE_PATH -b $VERSION $REMOTE_PATH $REMOTE_PATH/delivered/$VERSION

	run_hooks "post-checkout"
	$EXEC_REMOTE ln -sf $REMOTE_PATH/$VERSION $REMOTE_PATH/current
	run_hooks "post-symlink"
	$MSG="" #TODO: possibilité de message de livraison. Par défaut, log livraison
	git tag -m "$MSG" delivered-$REMOTE-`date +'%F_%R'` $VERSION
	}

function rollback
	{
	local STAGE=$1
	}

DEFINE_boolean 'init' false 'Initialize this repository' 'i'
DEFINE_boolean 'init-remote' false 'Initialize a remote' 'r'
DEFINE_boolean 'list-hooks' false 'List hooks available for init' 'l'
DEFINE_boolean 'status' false 'Query repository and remotes status' 's'
DEFINE_boolean 'rollback' false 'TODO' 'b'

# parse the command-line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

if [[ $FLAGS_init -eq $FLAGS_TRUE ]]; then
	init $*
elif [[ $FLAGS_init_remote -eq $FLAGS_TRUE ]]; then
	init_remote $*
elif [[ $FLAGS_list_hooks -eq $FLAGS_TRUE ]]; then
	list_hooks $*
elif [[ $FLAGS_status -eq $FLAGS_TRUE ]]; then
	repo_status $*
else
	deliver $*
fi
