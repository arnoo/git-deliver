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

#TODO: vim modeline
#TODO: check everywhere that we display/log sha1 and not just ref (for clarity)
#TODO: check that git is installed on remote before we do anything
#TODO: --single-branch in clone ?
#TODO: remove pushes to anything other than the delivery remote (too unexpected, replace by warning that delivered ref is not on origin ?)

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
	[[ $? -eq 0 ]] || { echo $2 && exit $1; }
	}

function print_help
	{
	echo "git deliver <REMOTE> <VERSION>"
	echo "git deliver --gc <REMOTE>"
	echo "git deliver --init [PRESETS]"
	echo "git deliver --init-remote <REMOTE_NAME> <REMOTE_URL>"
	echo "git deliver --list-presets"
	echo "git deliver --status [REMOTE]"
	exit 1
	}

function remote_status
	{
	local REMOTE=$1
	if [[ "$REMOTE" = '' ]]; then
		for R in `git remote`; do
			echo ""
			echo "Remote $R :"
			remote_status "$R"
		done
	else
		remote_info $REMOTE
		run_remote "bash" <<EOS
			if [[ ! -d "$REMOTE_PATH"/delivered/current ]]; then
				echo "    Not a git-deliver remote"
				exit 1
			fi
			CURRENT_DIR=\`readlink "$REMOTE_PATH"/delivered/current\`
			cd "$REMOTE_PATH"/delivered/current 2> /dev/null
			if [[ \$? -gt 0 ]]; then
				echo "    No delivered version"
				exit 2
			fi
			CURRENT_SHORTSHA1=\${CURRENT_DIR:19:6}
			LATEST_SHA=\`git log --pretty=format:%H -n 1\`
			PREVIOUS_SHA=\`git log --pretty=format:%H -n 2 | tail -n 1\`
			CURRENT_BRANCH=\`git rev-parse --abbrev-ref HEAD\`
			
			COMMENT=""
			
			if [[ "\$CURRENT_BRANCH" = "_delivered" ]] && [[ \${PREVIOUS_SHA:0:6} = \$CURRENT_SHORTSHA1 ]]; then
				VERSION=\$PREVIOUS_SHA
				COMMENT="delivered "\`git log -n 1 --pretty=format:'%aD by %aN <%aE>' \$PREVIOUS_SHA\`
				RETURN=3
			else
				VERSION=\$LATEST_SHA
				COMMENT="not delivered with git-deliver"
				RETURN=4
			fi
			
			TAGS=\`git show-ref --tags -d | grep ^\$VERSION | sed -e 's,.* refs/tags/,,' -e 's/\^{}//'\ | grep -v '^delivered_' | tr "\\n" ", "\`

			if [[ \`git diff-index HEAD | wc -l\` != "0" ]]; then
				COMMENT="\$COMMENT, with uncommitted changes"
			fi
			echo "    \$VERSION [\$TAGS] (\$COMMENT)"
			exit \$RETURN
EOS
	return $?
	fi
	}

function list_presets
	{
	for PRESET_PATH in $GIT_DELIVER_PATH/presets/*; do
		PRESET=`basename "$PRESET_PATH"`
		if [[ -f "$PRESET_PATH/info" ]]; then
			source "$PRESET_PATH/info"
			echo "$PRESET : $DESCRIPTION [$DEPENDENCIES]"
		fi
	done
	}

function check_preset
	{
	local PRESET=$1
	if [[ -d "$GIT_DELIVER_PATH/presets/$PRESET" ]]; then
		local DEPENDENCIES=""
		local DESCRIPTION="ERROR"
		local INFO_PATH="$GIT_DELIVER_PATH/presets/$PRESET/info"
		if [[ ! -f "$INFO_PATH" ]]; then
			echo "ERROR : Info file for preset $PRESET not found." >&2
			exit 1
		fi
		source "$INFO_PATH"
		if [[ "$DESCRIPTION" = "ERROR" ]] || [[ "$DESCRIPTION" = "" ]]; then
			echo "ERROR : Missing description for preset $PRESET" >&2
			exit 1
		fi
		local OLDIFS=$IFS
		IFS=',' read -ra DEPENDENCIES <<< "$DEPENDENCIES"
		for DEP in "${DEPENDENCIES[@]}"; do
			check_preset "$DEP"
		done
	else
		echo "ERROR : could not find preset $PRESET" >&2
		exit
	fi
	}

# Copies the files for preset $1 to the repo's .deliver/scripts directory
function init_preset
	{
	local PRESET=$1
	[ -d "$GIT_DELIVER_PATH/presets/$PRESET/dependencies" ] && cp -r "$GIT_DELIVER_PATH/presets/$PRESET/dependencies" "$REPO_ROOT/.deliver/scripts/dependencies/$PRESET"
	local PRESET_SCRIPT
	#TODO: forbid double init unless specific flag passed (and then use cp -i)
	for PRESET_STAGE_DIR in "$GIT_DELIVER_PATH/presets/$PRESET"/*; do
		[ -d $PRESET_STAGE_DIR ] || continue
		local PRESET_STAGE=`basename $PRESET_STAGE_DIR`
		[ "$PRESET_STAGE" = "dependencies" ] && continue
		for SCRIPT_FILE in "$PRESET_STAGE_DIR"/*; do
			local SCRIPT_NAME=`basename $SCRIPT_FILE`
			local SCRIPT_SEQNUM=`echo $SCRIPT_NAME | grep -o '^[0-9]\+'` #TODO: rewrite using =~ and ${BASH_REMATCH[4]}
			local SCRIPT_LABEL=${SCRIPT_NAME:$((${#SCRIPT_SEQNUM}+1))}
			cp -f $SCRIPT_FILE "$REPO_ROOT"/.deliver/scripts/$PRESET_STAGE/"$SCRIPT_SEQNUM-$PRESET-$SCRIPT_LABEL"
		done
	done
        source "$GIT_DELIVER_PATH/presets/$PRESET"/info
        #TODO: init_preset for all DEPENDENCIES
	}

function init
	{
	local PRESETS=$1
	IFS=',' read -ra PRESETS <<< "$PRESETS"
	for PRESET_DIR in "${PRESETS[@]}"; do
		local PRESET=`basename "$PRESET_DIR"`
		check_preset $PRESET
        done
	mkdir -p "$REPO_ROOT/.deliver/scripts"
	for PRESET in dependencies init-remote pre-delivery post-checkout post-symlink rollback-pre-symlink rollback-post-symlink; do
		mkdir "$REPO_ROOT/.deliver/scripts/$PRESET"
	done
	echo "Setting up core preset" >&2
	init_preset core
	for PRESET_DIR in "${PRESETS[@]}"; do
		local PRESET=`basename $PRESET_DIR`
		echo "Setting up $PRESET preset" >&2
		init_preset $PRESET
	done
	}

function run_scripts
	{
	local STAGE=$1
	local ROLLBACK_LAST_STAGE=$2

	if test -n "$(find "$REPO_ROOT/.deliver/scripts/$STAGE" -maxdepth 1 -name '*.sh' -print -quit)"
		then
		echo "Running scripts for stage $STAGE" >&2
		for SCRIPT_PATH in "$REPO_ROOT/.deliver/scripts/$STAGE"/*.sh; do
			SCRIPT=`basename "$SCRIPT_PATH"`
			echo "  Running script $STAGE/$SCRIPT" >&2
			[[ $ROLLBACK_LAST_STAGE = "" ]] || LAST_STAGE_REACHED=$ROLLBACK_LAST_STAGE
			bash <<EOS
export GIT_DELIVER_PATH="$GIT_DELIVER_PATH"
export REPO_ROOT="$REPO_ROOT"
export DELIVERY_DATE="$DELIVERY_DATE"
export DELIVERY_PATH="$DELIVERY_PATH"
export VERSION="$VERSION"
export VERSION_SHA="$VERSION_SHA"
export PREVIOUS_VERSION_SHA="$PREVIOUS_VERSION_SHA"
export REMOTE_SERVER="$REMOTE_SERVER"
export REMOTE_PATH="$REMOTE_PATH"
export REMOTE="$REMOTE"

function run_remote
	{
	COMMAND="\$*"
	if [[ "$REMOTE_SERVER" = "" ]]; then
		bash -c "\$COMMAND"
	else
		ssh "$REMOTE_SERVER" "\$COMMAND"
	fi
	}

export -f run_remote

source "$SCRIPT_PATH";
EOS
			local SCRIPT_RESULT=$?
			if [[ $SCRIPT_RESULT -gt 0 ]]; then
				echo "" >&2
				echo "  Script returned with status $SCRIPT_RESULT" >&2
				if [[ $ROLLBACK_LAST_STAGE = "" ]]; then
					rollback $STAGE
				else
					echo "A script failed during rollback, manual intervention is likely necessary"
				fi
				exit
			fi
		done
	else
		echo "No scripts for stage $STAGE" >&2
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
		if [[ $INIT_URL = "" ]]; then
			echo "Remote $REMOTE not found." >&2
			confirm_or_exit "Create it ?"
			echo ""
			read -p "URL for remote :" INIT_URL
		fi
		git remote add "$REMOTE" "$INIT_URL"
		exit_if_error 8 "Error adding remote in local Git config"
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
	echo "running $COMMAND" >> "$LOG_TEMPFILE"
	bash -c "$COMMAND"
	}

function run_remote
	{
	COMMAND="$*"
	if [[ "$REMOTE_SERVER" = "" ]]; then
		if [[ "$LOG_TEMPFILE" != "" ]]; then
			echo "running bash -c \"$COMMAND\"" >> "$LOG_TEMPFILE"
		fi
		bash -c "$COMMAND"
	else
		if [[ "$LOG_TEMPFILE" != "" ]]; then
			echo "running ssh \"$REMOTE_SERVER\" \"$COMMAND\"" >> "$LOG_TEMPFILE"
		fi
		ssh "$REMOTE_SERVER" "cd /tmp && $COMMAND"
	fi
	}

function init_remote
	{
	if [[ $4 != "" ]]; then
		print_help
		exit 1
	fi
	IN_INIT=true
	INIT_URL=$2
	local REMOTE=$1
	remote_info $REMOTE true $INIT_URL
	NEED_GIT_FILES=true
	run_remote "test -e \"$REMOTE_PATH\" 2>&1 > /dev/null"
	if [[ $? = 0 ]]; then
		run_remote "test -d \"$REMOTE_PATH\" 2>&1 > /dev/null"
		if [[ $? -gt 0 ]]; then
			echo "ERROR: Remote path points to a file"
			exit 10
		else
			if [[ `run_remote "ls -1 \"$REMOTE_PATH\" | wc -l"` != "0" ]]; then
				git fetch $REMOTE 2>&1 > /dev/null
				if [[ $? -gt 0 ]]; then
					echo "ERROR : Remote directory is not empty and does not look like a valid Git remote for this repo"
					exit 9
				else
					NEED_GIT_FILES=false
				fi
			fi
		fi
	else
		run_remote "mkdir \"$REMOTE_PATH\" 2>&1 > /dev/null"
		exit_if_error 12 "Error creating root directory on remote"
	fi
	if $NEED_GIT_FILES; then
		scp -r "$REPO_ROOT"/.git/* "$REMOTE_URL/"
		exit_if_error 10 "Error copying Git files"
		run_remote "cd \"$REMOTE_PATH\" && \
			    git config --bool core.bare true && \
			    git config --bool receive.autogc false"
	fi
	run_remote "mkdir \"$REMOTE_PATH\"/delivered"
	exit_if_error 11 "Error creating 'delivered' directory in remote root"
	run_scripts "init-remote"
	IN_INIT=""
	}

function remote_gc
	{
	if [[ $2 != "" ]] || [[ $1 = "" ]]; then
		print_help
		exit 1
	fi
	local REMOTE=$1
	remote_info $REMOTE
	LOG_TEMPFILE=`mktemp`
	local GC_SCRIPT="
		CURVER=\`readlink \"$REMOTE_PATH/delivered/current\"\`;
		PREVER=\`readlink \"$REMOTE_PATH/delivered/previous\"\`;
		PREPREVER=\`readlink \"$REMOTE_PATH/delivered/preprevious\"\`;
		for rep in \"$REMOTE_PATH/delivered/\"*; do
			if [ ! -L \"\$rep\" ] &&
			   [ \"\$rep\" != \"$REMOTE_PATH/delivered/\$CURVER\" ] &&
			   [ \"\$rep\" != \"$REMOTE_PATH/delivered/\$PREVER\" ] &&
			   [ \"\$rep\" != \"$REMOTE_PATH/delivered/\$PREPREVER\" ]; then
				echo \"Removing \$rep\"
				rm -rf \"\$rep\"
			fi;
		done"
	#TODO : INdicate how many folders were deleted and how much space was freed
	run_remote "$GC_SCRIPT"
	rm -f "$LOG_TEMPFILE"
	}

function deliver
	{
	if [[ $3 != "" ]] || [[ $1 = "" ]] || [[ $2 = "" ]]; then
		print_help
		exit 1
	fi
	local REMOTE=$1
	local VERSION=$2

	LOG_TEMPFILE=`mktemp`
	echo -e "Delivery of ref \"$VERSION\" to remote \"$REMOTE\"\n\n" > "$LOG_TEMPFILE"
	echo -e "Delivery log:\n" >> "$LOG_TEMPFILE"

	if [[ ! -d "$REPO_ROOT/.deliver" ]]; then
		echo ".deliver not found."
		confirm_or_exit "Run init ?"
		init
	fi

	remote_info $REMOTE

	check_git_version $REMOTE

	if [[ `run_remote "ls -1d \"$REMOTE_PATH/branches\" \"$REMOTE_PATH/refs\" 2> /dev/null | wc -l"` -lt "2" ]]; then
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

	local RSTATUS=`remote_status $REMOTE`
	RSTATUS_CODE=$?
	if [[ $RSTATUS_CODE -lt 1 ]]; then
		echo "No version delivered yet on $REMOTE" >&2
	else
		PREVIOUS_VERSION_SHA=${RSTATUS:0:40}
		echo -n "Current version on $REMOTE is $RSTATUS" >&2
	fi

	DELIVERY_DATE=`date +'%F_%H-%M-%S'`
	HUMAN_VERSION="${VERSION_SHA:0:6}"
	if [[ $VERSION != $VERSION_SHA ]]; then
		HUMAN_VERSION="$HUMAN_VERSION"_"$VERSION"
	fi
	DELIVERY_PATH="$REMOTE_PATH/delivered/$DELIVERY_DATE"_"$HUMAN_VERSION"

	while run_remote "test -d \"$DELIVERY_PATH\""; do
		if [[ "$DELIVERY_DATE" =~ ^(.*)_([0-9]+)$ ]]; then
			DELIVERY_DATE=${BASH_REMATCH[1]}$(( ${BASH_REMATCH[2]} + 1 ))
			DELIVERY_PATH="$REMOTE_PATH/delivered/$DELIVERY_DATE"_"$HUMAN_VERSION"
		else
			DELIVERY_DATE="$DELIVERY_DATE"_2
			DELIVERY_PATH="$REMOTE_PATH/delivered/$DELIVERY_DATE"_"$HUMAN_VERSION"
		fi
	done

	run_scripts "pre-delivery"

	# Make sure the remote has all the commits leading to the version to be delivered
	if [[ -e "$REPO_ROOT"/.git/refs/tags/"$VERSION" ]]; then
		run "git push $REMOTE tag $VERSION"
		exit_if_error 13
	fi
	run "git push $REMOTE $VERSION"
	exit_if_error 14

	# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked easily. The git objects are shared with the base repository.

	run_remote "git clone --reference \"$REMOTE_PATH\" --no-checkout \"$REMOTE_PATH\" \"$DELIVERY_PATH\""

	exit_if_error 5 "Error cloning repo to delivered folder on remote"
	
	run_remote "cd \"$DELIVERY_PATH\" && git checkout -b '_delivered' $VERSION"

	exit_if_error 6 "Error checking out remote clone"
	
	run_remote "cd \"$DELIVERY_PATH\" && git submodule update --init --recursive"
	
	exit_if_error 7 "Error initializing submodules"

	run_scripts "post-checkout"

	# Commit after the post-checkouts have run and might have changed a few things (added production database passwords for instance).
	# This guarantees the integrity of our delivery from then on. The commit can also be signed to authenticate the delivery.

	local DELIVERED_BY_NAME=`git config --get user.name`
	local DELIVERED_BY_EMAIL=`git config --get user.email`
	run_remote "cd \"$DELIVERY_PATH\" && git commit --author \"$DELIVERED_BY_NAME <$DELIVERED_BY_EMAIL>\" --allow-empty -a -m \"git-deliver automated commit\""

	echo "Switching the 'current' symlink to the newly delivered version."
	# Using a symlink makes our delivery atomic.

	#TODO: ask for confirmation before switch, with an option to see the complete diff through $PAGER since the last delivery + option to check this diff against the ones generated by running the same update on other environements

	run_remote "test -L \"$REMOTE_PATH/delivered/preprevious\" && rm \"$REMOTE_PATH/delivered/preprevious\" ; \
		    test -L \"$REMOTE_PATH/delivered/previous\"    && mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/preprevious\" ; \
		    test -L \"$REMOTE_PATH/delivered/current\"     && cp -d \"$REMOTE_PATH/delivered/current\"  \"$REMOTE_PATH/delivered/previous\" ; \
		    cd $REMOTE_PATH/delivered && ln -sfn \""`basename "$DELIVERY_PATH"`"\" \"new\" && mv -Tf \"$REMOTE_PATH/delivered/new\" \"$REMOTE_PATH/delivered/current\""
	#TODO: check for each link that everything went well and be able to rollback accordingly

	run_scripts "post-symlink"

	# TAG the delivered version here and on the origin remote

	if [[ $FLAGS_batch -ne $FLAGS_TRUE ]]; then
		$EDITOR "$LOG_TEMPFILE"
	fi
	local TAG_NAME="delivered-$REMOTE-$DELIVERY_DATE"
	local GPG_OPT
	if ( gpg -K | grep "$DELIVERED_BY_EMAIL" ) || git config --get user.signingkey; then
		GPG_OPT=" -s"
		#TODO: Also sign the post-delivery commit (more critical than the tag)
	fi
	git tag $GPG_OPT -F "$LOG_TEMPFILE" "$TAG_NAME" "$VERSION"
	rm -f "$LOG_TEMPFILE"
	run git push origin "$TAG_NAME"
	}

function check_git_version
	{
	REMOTE_GIT_VERSION=`run_remote "git --version" 2>&1 > /dev/null`
	
	if [[ $? = 127 ]]; then
		echo "ERROR: Git needs to be installed and in \$PATH on the remote"
		exit 11
	else
		echo -n ""
		#TODO: check remote Git version and exit if too old
	fi
	}

function rollback
	{
	local LAST_STAGE=$1
	echo "Rolling back"
	run_scripts "rollback-pre-symlink" "$LAST_STAGE"
	
	if [[ $LAST_STAGE = "post-symlink" ]]; then
		run_remote "rm \"$REMOTE_PATH/delivered/current\" && mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\" &&  mv \"$REMOTE_PATH/delivered/preprevious\" \"$REMOTE_PATH/delivered/previous\""
	fi

	run_scripts "rollback-post-symlink" "$LAST_STAGE"
	}

DEFINE_boolean 'source' false 'Used for tests : define functions but don''t do anything.'
DEFINE_boolean 'batch' false 'Batch mode : never ask for anything, die if any information is missing' 'b'
DEFINE_boolean 'init' false 'Initialize this repository'
DEFINE_boolean 'init-remote' false 'Initialize a remote'
DEFINE_boolean 'list-presets' false 'List presets available for init'
DEFINE_boolean 'status' false 'Query repository and remotes status'
DEFINE_boolean 'gc' false 'Garbage collection : remove all delivered version on remote except last 3'
DEFINE_boolean 'rollback' false 'Initiate a rollback'

# parse the command-line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

if [[ $FLAGS_init -eq $FLAGS_TRUE ]]; then
	init $*
elif [[ $FLAGS_init_remote -eq $FLAGS_TRUE ]]; then
	init_remote $*
elif [[ $FLAGS_list_presets -eq $FLAGS_TRUE ]]; then
	list_presets $*
elif [[ $FLAGS_status -eq $FLAGS_TRUE ]]; then
	remote_status $*
elif [[ $FLAGS_gc -eq $FLAGS_TRUE ]]; then
	remote_gc $*
elif [[ $FLAGS_source -ne $FLAGS_TRUE ]]; then
	deliver $*
fi
