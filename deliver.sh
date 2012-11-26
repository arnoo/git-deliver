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

#TODO: modeline vim
#TODO: gaffe a bien >&2 ce qui doit l'être
#TODO: option deliver juste en rsync ? pour shared hosting / FTP ?
#TODO: git rev-parse --parseopt to process command line flags ?
#TODO: supporter git config remotes.mygroup 'remote1 remote2' [ group multiple remotes ]
#TODO: fonction run qui logge toutes les commandes !
#TODO: version GPL ? cf GIT
#TODO: option ou remote n'est pas bare ? et dans ce cas on livre par simple push ?

function confirm_or_exit
	{
	if [[ $FLAGS_batch -eq $FLAGS_TRUE ]]; then
		exit 2
	fi
	if [[ "$1" = "" ]]; then
	    local MSG="Continue ?"
	else
	    local MSG=$1
	fi
	read -p "$MSG (y/n) " -n 1 REPLY >&2
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
	}

function exit_if_error
	{
	[[ $? -eq 0 ]] || exit $1
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
			echo "No delivery log for remote $REMOTE" #TODO: NO, we'll use the tags and their messages as our log (therefore git fetch fetches logs from origin !)
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
		run_remote "git status --git-dir \"$REMOTE_PATH/delivered/current\""
	fi
	}

function list_hooks
	{
	for HOOK_PATH in $GIT_DELIVER_PATH/hooks/*; do
		HOOK=`basename "$HOOK_PATH"`
		if [[ -f "$HOOK_PATH/info" ]]; then
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
			echo "ERROR : Info file for hook $HOOK not found." >&2
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
	[ -d "$GIT_DELIVER_PATH/hooks/$HOOK/dependencies" ] && cp -r "$GIT_DELIVER_PATH/hooks/$HOOK/dependencies" "$REPO_ROOT/.deliver/hooks/dependencies/$HOOK"
	local HOOK_SCRIPT
	#TODO: interdire init si deja init sauf flag specifique (et dans ce cas cp -i)
	for HOOK_STAGE_DIR in "$GIT_DELIVER_PATH/hooks/$HOOK"/*; do
		[ -d $HOOK_STAGE_DIR ] || continue
		local HOOK_STAGE=`basename $HOOK_STAGE_DIR`
		[ "$HOOK_STAGE" = "dependencies" ] && continue
		for HOOK_SCRIPT_FILE in "$HOOK_STAGE_DIR"/*; do
			local HOOK_SCRIPT_NAME=`basename $HOOK_SCRIPT_FILE`
			local HOOK_SEQNUM=`echo $HOOK_SCRIPT_NAME | grep -o '^[0-9]\+'` #TODO: refaire avec =~ et ${BASH_REMATCH[4]}
			local HOOK_LABEL=${HOOK_SCRIPT_NAME:$((${#HOOK_SEQNUM}+1))}
			cp -f $HOOK_SCRIPT_FILE "$REPO_ROOT"/.deliver/hooks/$HOOK_STAGE/"$HOOK_SEQNUM-$HOOK-$HOOK_LABEL"
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
		local HOOK=`basename "$HOOK_DIR"`
		check_hook $HOOK
        done
	mkdir -p "$REPO_ROOT/.deliver/hooks"
	for HOOK in dependencies init-remote pre-delivery post-checkout post-symlink rollback; do
		mkdir "$REPO_ROOT/.deliver/hooks/$HOOK"
	done
	echo "Setting up core hooks" >&2
	init_hook core
	for HOOK_DIR in "${HOOKS[@]}"; do
		local HOOK=`basename $HOOK_DIR`
		echo "Setting up $HOOK hooks" >&2
		init_hook $HOOK
	done
	}

function run_hooks
	{
	local STAGE=$1
	if test -n "$(find "$REPO_ROOT/.deliver/hooks/$STAGE" -maxdepth 1 -name '*.sh' -print -quit)"
		then
		echo "Running hooks for stage $STAGE" >&2
		for HOOK_PATH in "$REPO_ROOT/.deliver/hooks/$STAGE"/*.sh; do
			HOOK=`basename "$HOOK_PATH"`
			echo "  Running hook $STAGE/$HOOK" >&2
			export -f run_remote
			bash <<EOS
export GIT_DELIVER_PATH="$GIT_DELIVER_PATH"
export REPO_ROOT="$REPO_ROOT"
export DELIVERY_DATE="$DELIVERY_DATE"
export DELIVERY_PATH="$DELIVERY_PATH"
export VERSION="$VERSION"
export VERSION_SHA="$VERSION_SHA"
export PREVIOUS_VERSION_SHA="$PREVIOUS_VERSION_SHA"
export REMOTE="$REMOTE"
source "$HOOK_PATH";
EOS
			local HOOK_RESULT=$?
			if [[ $HOOK_RESULT -gt 0 ]]; then
				echo "" >&2
				echo "  Hook returned with status $HOOK_RESULT" >&2
				rollback $STAGE
				exit
			fi
		done
	else
		echo "No hooks for stage $STAGE" >&2
	fi
	}

function remote_info
	{
	local REMOTE=$1
	local INIT=$2
	local INIT_URL=$3
	local REMOTE_INFO
	REMOTE_INFO=`git remote -v | grep '^'"$REMOTE"'	' | grep '(push)'`
	if [[ $? -gt 0 ]] && $INIT; then
		echo "Remote $REMOTE not found." >&2
		confirm_or_exit "Create it ?"
		echo ""
		if [[ $INIT_URL = "" ]]; then
			read -p "URL for remote :" INIT_URL
		fi
		git remote add "$REMOTE" "$INIT_URL"
		if [[ ! $IN_INIT ]]; then
			init_remote $REMOTE $INIT_URL
		fi
	fi

	REMOTE_URL=`git config --get "remote.$REMOTE.url"`
	REMOTE_SERVER=`echo "$REMOTE_URL" | cut -d: -f 1`
	REMOTE_PATH=`echo "$REMOTE_URL" | cut -d: -f 2`

	if [[ "$REMOTE_PATH" = "$REMOTE_URL" ]]; then
		REMOTE_PATH="$REMOTE_SERVER";
		REMOTE_SERVER=""
	fi
	}

function run
	{
	COMMAND="$*"
	LOG="$LOG\nrunning $COMMAND"
	$COMMAND
	}

function run_remote
	{
	COMMAND="$*"
	if [[ "$REMOTE_SERVER" = "" ]]; then
		bash -c "$COMMAND"
	else
		ssh "$REMOTE_SERVER" "$COMMAND"  #TODO: cd $DELIVERY_PATH && (ne marche pas pour avant checkout... ajouter un test et dans ce cas quel rep sinon ? )
	fi
	}

function init_remote
	{
	if [[ $3 != "" ]] || [[ $1 = "" ]]; then
		print_help
		exit 1
	fi
	IN_INIT=true
	INIT_URL=$2
	local REMOTE=$1
	remote_info $REMOTE true $INIT_URL
	#TODO: check that remote URL does not already exist
	echo "$REPO_ROOT"
	scp -r "$REPO_ROOT/.git" "$REMOTE_URL"
	exit
	run_remote "git config --bool core.bare true && \
		    git config --bool receive.autogc false && \
		    mkdir delivered"
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
	if [[ ! -d "$REPO_ROOT/.deliver" ]]; then
		echo ".deliver not found."
		confirm_or_exit "Run init ?"
		init
	fi

	remote_info $REMOTE
	if [[ `run_remote "ls -1d \"$REMOTE_PATH/hooks\" \"$REMOTE_PATH/refs\" 2> /dev/null | wc -l"` -lt "2" ]]; then
		echo "ERROR : Remote does not look like a bare git repo" >&2
		exit 1
	fi
	VERSION_SHA=`git rev-parse --revs-only $VERSION 2> /dev/null`

	if [[ "$VERSION_SHA" = "" ]]; then
		echo "Ref $VERSION not found." >&2
		confirm_or_exit "Tag current HEAD ?"
		VERSION_SHA=`git rev-parse HEAD`
		echo "Tagging current HEAD" >&2
		git tag $VERSION
		echo "Pushing tag to origin" >&2
		git push origin $VERSION
	fi

	PREVIOUS_VERSION_SHA=`git rev-parse --revs-only "delivered-$REMOTE"`
	if [[ "$PREVIOUS_VERSION_SHA" = "" ]]; then
		echo "No version delivered yet on $REMOTE" >&2
	else
		echo -n "Current version on $REMOTE is " >&2
		git name-rev $REMOTE >&2
	fi

	DELIVERY_DATE=`date +'%F_%H-%M-%S'`
	DELIVERY_PATH="$REMOTE_PATH/delivered/$VERSION"_"$DELIVERY_DATE"

	while run_remote "test -d \"$DELIVERY_PATH\""; do
		if [[ "$DELIVERY_DATE" =~ ^(.*)_([0-9]+)$ ]]; then
			DELIVERY_DATE=${BASH_REMATCH[1]}$(( ${BASH_REMATCH[2]} + 1 ))
			DELIVERY_PATH="$REMOTE_PATH/delivered/$VERSION"_"$DELIVERY_DATE"
		else
			DELIVERY_DATE="$DELIVERY_DATE"_2
			DELIVERY_PATH="$REMOTE_PATH/delivered/$VERSION"_"$DELIVERY_DATE"
		fi
	done

	run_hooks "pre-delivery"

	# Make sure the remote has all the commits leading to the version to be delivered
	run "git push $REMOTE $VERSION"

	# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked easily. A shallow clone with depth one would do, but it would use more disk space because we wouldn't be able to share the files with the bare repo through hard links (git clone does that by default when cloning on the same filesystem).

	run_remote "git clone --reference $REMOTE_PATH -b $VERSION $REMOTE_PATH \"$DELIVERY_PATH\""

	exit_if_error 5

	run_remote "cd \"$DELIVERY_PATH\" && git checkout -b '_delivered'"

	exit_if_error 6

	run_hooks "post-checkout"

	# Commit after the post-checkouts have run and might have changed a few things (added production database passwords for instance).
	# This guarantees the integrity of our delivery from then on. The commit can also be signed to authenticate the delivery.

	local DELIVERED_BY_NAME=`git config --get user.name`
	local DELIVERED_BY_EMAIL=`git config --get user.email`
	run_remote "cd \"$DELIVERY_PATH\" && git commit --author \"$DELIVERED_BY_NAME <$DELIVERED_BY_EMAIL>\" -a -m \"\""
	#TODO: sign commit if user has a GPG key

	# Switch the symlink to the newly delivered version. This makes our delivery atomic.

	#TODO: demande confirmation avant switch, avec possibilité de voir le diff complet depuis dernière livraison via $PAGER + possibilité de checker ce diff avec le diff entre les mêmes versions sur un autre environnement

	run_remote "test -L \"$REMOTE_PATH/delivered/preprevious\" && rm \"$REMOTE_PATH/delivered/preprevious\" && \
		    test -L \"$REMOTE_PATH/delivered/previous\"    && mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/preprevious\" && \
		    test -L \"$REMOTE_PATH/delivered/current\"     && mv \"$REMOTE_PATH/delivered/current\"  \"$REMOTE_PATH/delivered/previous\" && \
		    cd $REMOTE_PATH/delivered && ln -sfn \""`basename "$DELIVERY_PATH"`"\" \"current\""
	#TODO: check for each link that everything went well and be able to rollback

	run_hooks "post-symlink"

	# TAG the delivered version here and on the origin remote

	local MSG="" #TODO: possibilité de message de livraison. Par défaut, log livraison
	local TAG_NAME="delivered-$REMOTE-$DELIVERY_DATE"
	run "git tag -m \"$MSG\" \"$TAG_NAME\" \"$VERSION\""
	run "git push origin \"$TAG_NAME\""
	}

function rollback
	{
	local STAGE=$1
	}

DEFINE_boolean 'batch' false 'Batch mode : never ask for anything, die if any information is missing' 'b'
DEFINE_boolean 'init' false 'Initialize this repository'
DEFINE_boolean 'init-remote' false 'Initialize a remote'
DEFINE_boolean 'list-hooks' false 'List hooks available for init'
DEFINE_boolean 'status' false 'Query repository and remotes status'
DEFINE_boolean 'rollback' false 'TODO'
DEFINE_boolean 'log' false 'TODO'
DEFINE_boolean 'fetch-log' false 'TODO'

# parse the command-line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

if [[ $FLAGS_init -eq $FLAGS_TRUE ]]; then
	init $*
elif [[ $FLAGS_init_remote -eq $FLAGS_TRUE ]]; then
	init_remote $*
elif [[ $FLAGS_list_hooks -eq $FLAGS_TRUE ]]; then
	list_hooks $*
elif [[ $FLAGS_fetch_log -eq $FLAGS_TRUE ]]; then
	fetch_log $*
elif [[ $FLAGS_log -eq $FLAGS_TRUE ]]; then
	log $*
elif [[ $FLAGS_status -eq $FLAGS_TRUE ]]; then
	repo_status $*
else
	deliver $*
fi
