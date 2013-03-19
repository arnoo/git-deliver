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

#TODO: cleanup remote-info, handle multi-url remotes
#TODO: open a single SSH connection and pipe commands to it instead of opening one per command ?

REPO_ROOT=`git rev-parse --git-dir 2> /dev/null` # for some reason, --show-toplevel returns nothing
if [[ $? -gt 0 ]]; then
	echo "ERROR : not a git repo" >&2
	exit 1
fi
if [[ "$REPO_ROOT" = ".git" ]]; then
	REPO_ROOT=`pwd`
else
	REPO_ROOT="${REPO_ROOT%/.git}"
fi

function path2unix
	{
	local SOURCE_PATH="$1"
	if [[ "${SOURCE_PATH:0:1}" = "/" ]]; then
		echo $SOURCE_PATH
		return
	fi
	local DRIVE_LETTER=$(echo "${SOURCE_PATH:0:1}" | tr '[A-Z]' '[a-z]')
	echo "/$DRIVE_LETTER${SOURCE_PATH:2}"
	}

if [[ "$OSTYPE" == "msys" ]]; then
	REPO_ROOT=`path2unix "$REPO_ROOT"`
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
	    local MSG="$1"
	fi
	read -p "$MSG (y/n) " -n 1 REPLY >&2
	if [[ ! $REPLY = "Y" ]] && [[ ! $REPLY = "y" ]]; then
		exit 1
	fi
	}

function exit_if_error
	{
	[[ $? -eq 0 ]] || { echo $2 && exit $1; }
	}

function exit_with_help
	{
	echo "Usage : "
	echo "  git deliver <REMOTE> <VERSION>"
	echo "  git deliver --rollback <REMOTE>"
	echo "  git deliver --gc <REMOTE>"
	echo "  git deliver --init [PRESETS]"
	echo "  git deliver --init-remote <REMOTE_NAME> <REMOTE_URL>"
	echo "  git deliver --list-presets"
	echo "  git deliver --status [REMOTE]"
	if [[ "$1" = "" ]]; then
		exit 1;
	else
		exit $1
	fi
	}

function remote_status
	{
	local REMOTE="$1"
	if [[ "$REMOTE" = '' ]]; then
		for R in `git remote`; do
			echo ""
			echo "Remote $R :"
			echo -n "  "
			remote_status "$R"
		done
	else
		remote_info "$REMOTE"
		if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
			echo "Not a Git-deliver remote"
			return 1
		fi

		run_remote "bash" <<EOS
			if [[ ! -d "$REMOTE_PATH"/delivered ]]; then
				echo "Not a Git-deliver remote"
				exit 1
			fi
			cd "$REMOTE_PATH"/delivered/current 2> /dev/null
			if [[ \$? -gt 0 ]]; then
				echo "No delivered version"
				exit 2
			fi
			CURRENT_DIR=\`pwd -P\`
			CURRENT_DIR=\`basename "\$CURRENT_DIR"\`
			CURRENT_SHORTSHA1=\${CURRENT_DIR:20:6}
			LATEST_SHA=\`git log --pretty=format:%H -n 1\`
			PREVIOUS_SHA=\`git log --pretty=format:%H -n 2 | tail -n 1\`
			CURRENT_BRANCH=\`git rev-parse --abbrev-ref HEAD\`
			
			COMMENT=""
			
			if [[ "\$CURRENT_BRANCH" = "_delivered" ]] && [[ \${PREVIOUS_SHA:0:6} = \$CURRENT_SHORTSHA1 ]]; then
				VERSION=\$PREVIOUS_SHA
				COMMENT="delivered "\`git show --pretty=format:'%aD by %aN <%aE>' _delivered | head -n 1\`
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
			echo "\$VERSION [\$TAGS] (\$COMMENT)"
			exit \$RETURN
EOS
	return $?
	fi
	}

function list_presets
	{
	for PRESET_PATH in "$GIT_DELIVER_PATH"/presets/*; do
		PRESET=`basename "$PRESET_PATH"`
		if [[ -f "$PRESET_PATH/info" ]]; then
			source "$PRESET_PATH/info"
			echo "$PRESET : $DESCRIPTION [$DEPENDENCIES]"
		fi
	done
	}

function check_preset
	{
	local PRESET="$1"
	if [[ -d "$GIT_DELIVER_PATH/presets/$PRESET" ]]; then
		local DEPENDENCIES=""
		local DESCRIPTION="ERROR"
		local INFO_PATH="$GIT_DELIVER_PATH/presets/$PRESET/info"
		if [[ ! -f "$INFO_PATH" ]]; then
			echo "ERROR : Info file for preset $PRESET not found." >&2
			exit 21
		fi
		source "$INFO_PATH"
		if [[ "$DESCRIPTION" = "ERROR" ]] || [[ "$DESCRIPTION" = "" ]]; then
			echo "ERROR : Missing description for preset $PRESET" >&2
			exit 20
		fi
		local OLDIFS=$IFS
		IFS=',' read -ra DEPENDENCIES <<< "$DEPENDENCIES"
		for DEP in "${DEPENDENCIES[@]}"; do
			check_preset "$DEP"
		done
	else
		echo "ERROR : could not find preset $PRESET" >&2
		exit 19
	fi
	}

# Copies the files for preset $1 to the repo's .deliver/scripts directory
function init_preset
	{
	local PRESET="$1"
	if echo "$INIT_PRESETS" | grep ",$PRESET," > /dev/null; then
		return
	fi
	[ -d "$GIT_DELIVER_PATH"/presets/"$PRESET" ] || { echo "Preset not found : $PRESET" && exit 19; }
	[ -d "$GIT_DELIVER_PATH"/presets/"$PRESET"/dependencies ] && cp -ri "$GIT_DELIVER_PATH"/presets/"$PRESET"/dependencies "$REPO_ROOT"/.deliver/scripts/dependencies/"$PRESET"
	local PRESET_SCRIPT
	for PRESET_STAGE_DIR in "$GIT_DELIVER_PATH/presets/$PRESET"/*; do
		[ -d "$PRESET_STAGE_DIR" ] || continue
		local PRESET_STAGE=`basename "$PRESET_STAGE_DIR"`
		[ "$PRESET_STAGE" = "dependencies" ] && continue
		for SCRIPT_FILE in "$PRESET_STAGE_DIR"/*; do
			local SCRIPT_NAME=`basename "$SCRIPT_FILE"`
			local SCRIPT_SEQNUM=`echo $SCRIPT_NAME | sed -e 's/^\([0-9]\+\).*$/\1/'`
			local SCRIPT_LABEL="${SCRIPT_NAME:$((${#SCRIPT_SEQNUM}+1))}"
			cp -i "$SCRIPT_FILE" "$REPO_ROOT"/.deliver/scripts/$PRESET_STAGE/"$SCRIPT_SEQNUM-$PRESET-$SCRIPT_LABEL"
		done
	done
	INIT_PRESETS="$INIT_PRESETS$PRESET,"
        source "$GIT_DELIVER_PATH/presets/$PRESET"/info
	IFS=',' read -ra DEPENDENCIES <<< "$DEPENDENCIES"
	for DEP in "${DEPENDENCIES[@]}"; do
		init_preset "$DEP"
	done
	}

function init
	{
	local PRESETS="$1"
	IFS=',' read -ra PRESETS <<< "$PRESETS"
	for PRESET_DIR in "${PRESETS[@]}"; do
		local PRESET=`basename "$PRESET_DIR"`
		check_preset $PRESET
        done
	mkdir -p "$REPO_ROOT/.deliver/scripts"
	for STAGE in dependencies init-remote pre-delivery post-checkout post-symlink rollback-pre-symlink rollback-post-symlink; do
		mkdir "$REPO_ROOT/.deliver/scripts/$STAGE"
		echo -e "Put your $STAGE Bash scripts in this folder with a .sh extension.\n\nSee https://github.com/arnoo/git-deliver for help." >> "$REPO_ROOT/.deliver/scripts/$STAGE/README"
	done
	echo "Setting up core preset" >&2
	INIT_PRESETS=","
	init_preset core
	for PRESET_DIR in "${PRESETS[@]}"; do
		local PRESET=`basename "$PRESET_DIR"`
		echo "Setting up $PRESET preset" >&2
		init_preset $PRESET
	done
	}

function run_stage_scripts
	{
	if test -n "$(find "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE" -maxdepth 1 -name '*.sh' -print)"
		then
		echo "Running scripts for stage $DELIVERY_STAGE" >&2
		for SCRIPT_PATH in "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE"/*.sh; do
			local SCRIPT=`basename "$SCRIPT_PATH"`
			CURRENT_STAGE_SCRIPT="$SCRIPT"
			echo "  Running script $DELIVERY_STAGE/$SCRIPT" >&2
			if [[ "${SCRIPT: -10}" = ".remote.sh" ]]; then
				SHELL='run_remote "bash"'
			fi
			$SHELL <<EOS
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
export LAST_STAGE_REACHED="$LAST_STAGE_REACHED"
export FAILED_SCRIPT="$FAILED_SCRIPT"
export FAILED_SCRIPT_EXIT_STATUS="$FAILED_SCRIPT_EXIT_STATUS"

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

`cat "$SCRIPT_PATH"`
EOS
			local SCRIPT_RESULT=$?
			if [[ $SCRIPT_RESULT -gt 0 ]]; then
				echo "" >&2
				echo "  Script returned with status $SCRIPT_RESULT" >&2
				if [[ "$DELIVERY_STAGE" != "rollback-pre-symlink" ]] && [[ "$DELIVERY_STAGE" != "rollback-post-symlink" ]]; then
					LAST_STAGE_REACHED="$DELIVERY_STAGE"
					FAILED_SCRIPT="$CURRENT_STAGE_SCRIPT"
					FAILED_SCRIPT_EXIT_STATUS="$SCRIPT_RESULT"
					rollback
				else
					echo "A script failed during rollback, manual intervention is likely necessary"
					echo "Delivery log : $LOG_TEMPFILE"
					exit 23
				fi
				exit
			fi
			CURRENT_STAGE_SCRIPT=""
		done
	else
		echo "No scripts for stage $DELIVERY_STAGE" >&2
	fi
	}

function remote_info
	{
	local REMOTE="$1"
	local INIT="$2"
	local INIT_URL="$3"

	if echo "$REMOTE" | grep -vE '^[A-Za-z0-9\./_-]+$'; then
		echo "Not a valid remote name : $REMOTE"
		exit_with_help 22
	fi

	local REMOTE_INFO
	REMOTE_INFO=`git remote -v | grep '^'"$REMOTE"'	' | grep '(push)'`
	if [[ $? -gt 0 ]] && $INIT; then
		if [[ "$INIT_URL" = "" ]]; then
			echo "Remote $REMOTE not found." >&2
			confirm_or_exit "Create it ?"
			echo ""
			read -p "URL for remote :" INIT_URL
		fi
		git remote add "$REMOTE" "$INIT_URL"
		exit_if_error 8 "Error adding remote in local Git config"
		if [[ ! $IN_INIT ]]; then
			init_remote "$REMOTE" "$INIT_URL"
		fi
	fi

	REMOTE_URL=`git config --get "remote.$REMOTE.url"`
	if echo "$REMOTE_URL" | grep "://" > /dev/null; then
		REMOTE_PROTO=`echo "$REMOTE_URL" | cut -d: -f 1`
		REMOTE_PROTO=`echo "${REMOTE_PROTO}" | tr '[A-Z]' '[a-z]'`
		REMOTE_SERVER=`echo "$REMOTE_URL" | cut -d/ -f 3`
		REMOTE_PATH="/"`echo "$REMOTE_URL" | cut -d/ -f 4-`
	elif echo "$REMOTE_URL" | grep ':' > /dev/null; then
		if [[ "$OSTYPE" == "msys" ]] && [[ "${REMOTE_URL:1:1}" == ":" ]]; then
			REMOTE_PROTO='local'
			REMOTE_PATH=`path2unix "$REMOTE_URL"`
			REMOTE_SERVER=""
		else
			REMOTE_PROTO='ssh'
			REMOTE_SERVER=`echo "$REMOTE_URL" | cut -d: -f 1`
			REMOTE_PATH=`echo "$REMOTE_URL" | cut -d: -f 2`
		fi
	else
		REMOTE_PROTO='local'
		REMOTE_SERVER=""
		if [[ "${REMOTE_URL:0:1}" = "/" ]]; then
			REMOTE_PATH="$REMOTE_URL"
		else
			REMOTE_PATH="$REPO_ROOT/$REMOTE_URL"
		fi
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
	COMMAND="cd /tmp && { $* ; }"
	if [[ "$REMOTE_SERVER" = "" ]]; then
		if [[ "$LOG_TEMPFILE" != "" ]]; then
			echo "running bash -c \"$COMMAND\"" >> "$LOG_TEMPFILE"
		fi
		bash -c "$COMMAND"
	else
		if [[ "$LOG_TEMPFILE" != "" ]]; then
			echo "running ssh \"$REMOTE_SERVER\" \"$COMMAND\"" >> "$LOG_TEMPFILE"
		fi
		ssh "$REMOTE_SERVER" "$COMMAND"
	fi
	}

function init_remote
	{
	if [[ "$4" != "" ]]; then
		exit_with_help
	fi
	IN_INIT=true
	INIT_URL="$2"
	local REMOTE="$1"
	remote_info "$REMOTE" true "$INIT_URL"
	
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		echo "Git-deliver can only work with SSH or 'local' remotes"
		exit 17
	fi
	
	run_remote "{ test -d \"$REMOTE_PATH\"/refs && test -d \"$REMOTE_PATH\"/delivered ; } &> /dev/null"
	if [[ $? = 0 ]]; then
		echo "This remote looks like it has already been setup for git-deliver."
		exit 18
	fi
	

	NEED_INIT=true
	run_remote "test -e \"$REMOTE_PATH\" &> /dev/null"
	if [[ $? = 0 ]]; then
		run_remote "test -d \"$REMOTE_PATH\" &> /dev/null"
		if [[ $? -gt 0 ]]; then
			echo "ERROR: Remote path points to a file"
			exit 10
		else
			if [[ `run_remote "ls -1 \"$REMOTE_PATH\" | wc -l"` != "0" ]]; then
				git fetch "$REMOTE" &> /dev/null
				if [[ $? -gt 0 ]]; then
					echo "ERROR : Remote directory is not empty and does not look like a valid Git remote for this repo"
					exit 9
				else
					NEED_INIT=false
				fi
			fi
		fi
	else
		run_remote "mkdir \"$REMOTE_PATH\" &> /dev/null"
		exit_if_error 12 "Error creating root directory on remote"
	fi
	if $NEED_INIT; then
		run_remote "cd \"$REMOTE_PATH\" && \
			    git init --bare \"$REMOTE_PATH\" && \
			    git config --bool receive.autogc false"
		exit_if_error 10 "Error initializing repository on remote"
	fi
	run_remote "mkdir \"$REMOTE_PATH\"/delivered"
	exit_if_error 11 "Error creating 'delivered' directory in remote root"
	DELIVERY_STAGE="init-remote"
	run_stage_scripts
	echo "Remote is ready to receive deliveries"
	IN_INIT=""
	}

function remote_gc
	{
	if [[ $2 != "" ]] || [[ $1 = "" ]]; then
		exit_with_help
	fi
	local REMOTE="$1"
	remote_info "$REMOTE"
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		echo "$REMOTE is not a Git-deliver remote"
		exit 17
	fi
	LOG_TEMPFILE=`make_temp_file`
	local GC_SCRIPT="
		CURVER=\`{ cd \"$REMOTE_PATH/delivered/current\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
		PREVER=\`{ cd \"$REMOTE_PATH/delivered/previous\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
		PREPREVER=\`{ cd \"$REMOTE_PATH/delivered/preprevious\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
		DELETED=0
		FREED_BYTES=0
		for rep in \"$REMOTE_PATH/delivered/\"*; do
			if [ ! -L \"\$rep\" ] &&
			   [ \"\$rep\" != \"\$CURVER\" ] &&
			   [ \"\$rep\" != \"\$PREVER\" ] &&
			   [ \"\$rep\" != \"\$PREPREVER\" ]; then
				echo \"Removing \$rep\"
				FREED_BYTES_NEW=\`du -sb \"\$rep\" | cut -f1\`
				rm -rf \"\$rep\" && \
				DELETED=\$((\$DELETED + 1)) && \
			   	FREED_BYTES=\$((\$FREED_BYTES + \$FREED_BYTES_NEW))
			fi
		done
		if [[ \$FREED_BYTES = 0 ]]; then
			HUMAN_FREED_BYTES=\"0 B\"
		else
			HUMAN_FREED_BYTES=\`echo \$FREED_BYTES | awk '{x = \$0;
								     split(\"B KB MB GB TB PB\", type);
								     for(i=5;y < 1;i--)
									 y = x / (2**(10*i));
								     print y \" \" type[i+2];
								     }'\`
		fi
		echo \"\$DELETED version(s) removed, \$HUMAN_FREED_BYTES freed\" "
	run_remote "$GC_SCRIPT"
	rm -f "$LOG_TEMPFILE"
	}

function make_temp_file
	{
	which mktemp &> /dev/null
	if [[ $? = 0 ]]; then
		mktemp
	else
		TEMPDIR="$TMPDIR"
		if [[ "$TEMPDIR" = "" ]]; then
			TEMPDIR="/tmp"
		fi
		TEMPFILE="$TEMPDIR"/git-deliver-$$.$RANDOM
		touch "$TEMPFILE"
		echo "$TEMPFILE"
	fi
	}
	
function deliver
	{
	if [[ $3 != "" ]] || [[ $1 = "" ]]; then
		exit_with_help
	fi
	local REMOTE="$1"

	if [[ $FLAGS_rollback != $FLAGS_TRUE ]]; then
		if [[ $2 = "" ]]; then
			exit_with_help
		fi
		local VERSION="$2"
	fi

	CURRENT_STAGE_SCRIPT=""
	LAST_STAGE_REACHED=""
	LOG_TEMPFILE=`make_temp_file`

	trap delivery_sigint_handler SIGINT

	echo "#" > "$LOG_TEMPFILE"
	echo "# This is the log of your delivery" >> "$LOG_TEMPFILE"
	echo "# It will be added as a note on the delivery tag" >> "$LOG_TEMPFILE"
	echo "# You can customize the note now, before the tag is created" >> "$LOG_TEMPFILE"
	echo "# Lines starting with # will be ignored" >> "$LOG_TEMPFILE"
	echo "#" >> "$LOG_TEMPFILE"
	echo "" >> "$LOG_TEMPFILE"

	echo -e "Delivery of ref \"$VERSION\" to remote \"$REMOTE\"\n\n" >> "$LOG_TEMPFILE"

	if [[ ! -d "$REPO_ROOT/.deliver" ]]; then
		echo ".deliver not found."
		confirm_or_exit "Run init ?"
		init
	fi

	remote_info "$REMOTE"
	
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		echo "Git-deliver can only work with SSH or 'local' remotes"
		exit 17
	fi

	check_git_version "$REMOTE"

	if [[ `run_remote "ls -1d \"$REMOTE_PATH/objects\" \"$REMOTE_PATH/refs\" 2> /dev/null | wc -l"` -lt "2" ]]; then
		echo "ERROR : Remote does not look like a bare git repo" >&2
		exit 1
	fi

	# If this projet has init-remote scripts, check that the remote has been init. Otherwise, we don't really care, as it's just a matter of creating the 'delivered' directory

	if [[ -e "$REPO_ROOT"/.deliver/scripts/init-remote ]] && test -n "$(find "$REPO_ROOT/.deliver/scripts/init-remote" -maxdepth 1 -name '*.sh' -print)"; then
		run_remote "test -d \"$REMOTE_PATH\"/delivered"
		if [[ $? -gt 0 ]]; then
			echo "ERROR : Remote has not been init" >&2
			exit 22
		fi
	fi

	if [[ $FLAGS_rollback != $FLAGS_TRUE ]]; then
		VERSION_SHA=`git rev-parse --revs-only $VERSION 2> /dev/null`

		local TAG_TO_PUSH=""
		if [[ "$VERSION_SHA" = "" ]]; then
			echo "Ref $VERSION not found." >&2
			confirm_or_exit "Tag current HEAD ?"
			VERSION_SHA=`git rev-parse HEAD`
			echo "Tagging current HEAD" >&2
			git tag $VERSION
			TAG_TO_PUSH=$VERSION
		fi
	fi

	remote_status "$REMOTE" &> /dev/null
	RSTATUS_CODE=$?
	if [[ $RSTATUS_CODE -lt 3 ]]; then
		echo "No version delivered yet on $REMOTE" >&2
		if [[ $FLAGS_rollback -eq $FLAGS_TRUE ]]; then
			echo "Cannot rollback"
			exit 24
		fi
	else
		RSTATUS=`remote_status "$REMOTE"`
		PREVIOUS_VERSION_SHA="${RSTATUS:0:40}"
		echo "Current version on $REMOTE is $RSTATUS" >&2
	fi

	if [[ $FLAGS_rollback -eq $FLAGS_TRUE ]]; then
		DELIVERY_PATH=`run_remote "cd $REMOTE_PATH/delivered/previous && pwd -P" 2>&1`
		if [[ $? -gt 0 ]]; then
			echo "No previous version found; cannot rollback"
			exit 25
		fi
		#TODO: Display version and confirm rollback
		echo "Switching the 'current' symlink to the previous version."

		run_remote "cp -d \"$REMOTE_PATH/delivered/current\" \"$REMOTE_PATH/delivered/rolledback\" || exit 3 ; \
			        mv -Tf \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\" || exit 2 ; \
			        mv \"$REMOTE_PATH/delivered/rolledback\" \"$REMOTE_PATH/delivered/previous\" || exit 1 ; \
				exit 0"

		SYMLINK_SWITCH_STATUS=$?
	else
		DELIVERY_DATE=`date +'%F_%H-%M-%S'`
		HUMAN_VERSION="${VERSION_SHA:0:6}"
		if [[ $VERSION != $VERSION_SHA ]]; then
			HUMAN_VERSION="$HUMAN_VERSION"_"$VERSION"
		fi
		DELIVERY_BASENAME="$DELIVERY_DATE"_"$HUMAN_VERSION"
		DELIVERY_PATH="$REMOTE_PATH/delivered/$DELIVERY_BASENAME"

		local BRANCHES=`git branch --contains $VERSION`
		if [[ "$BRANCHES" = "" ]]; then
			echo "ERROR : Can't deliver a commit that does not belong to a local branch"
			exit 16
		fi
		
		local BRANCH=`echo "$BRANCHES" | grep '^* ' | tr -d ' *'`
		if [[ "$BRANCH" = "" ]]; then
			BRANCH=`echo "$BRANCHES" | head -n 1 | tr -d ' '`
		fi

		DELIVERY_STAGE="pre-delivery"
		run_stage_scripts

		if git tag -l | grep '^'"$VERSION"'$' &> /dev/null; then
			run "git push \"$REMOTE\" tag $VERSION"
			exit_if_error 13
		fi
		#TODO: Can we push just what's needed and not the whole branch ?
		run "git push \"$REMOTE\" $BRANCH"
		exit_if_error 14

		# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked easily. The git objects are shared with the base repository.

		run_remote "git clone --reference \"$REMOTE_PATH\" --no-checkout \"$REMOTE_PATH\" \"$DELIVERY_PATH\""

		exit_if_error 5 "Error cloning repo to delivered folder on remote"

		run_remote "cd \"$DELIVERY_PATH\" && { test -e .git/refs/heads/"$BRANCH" || git checkout -b $BRANCH origin/$BRANCH ; }"
		exit_if_error 15 "Error creating tracking branch on remote clone"
		
		run_remote "cd \"$DELIVERY_PATH\" && git checkout -b '_delivered' $VERSION"

		exit_if_error 6 "Error checking out remote clone"
		
		run_remote "cd \"$DELIVERY_PATH\" && git submodule update --init --recursive"
		
		exit_if_error 7 "Error initializing submodules"

		DELIVERY_STAGE="post-checkout"
		run_stage_scripts

		# Commit after the post-checkouts have run and might have changed a few things (added production database passwords for instance).
		# This guarantees the integrity of our delivery from then on. The commit can also be signed to authenticate the delivery.

		local DELIVERED_BY_NAME=`git config --get user.name`
		local DELIVERED_BY_EMAIL=`git config --get user.email`
		run_remote "cd \"$DELIVERY_PATH\" && GIT_COMMITTER_NAME=\"$DELIVERED_BY_NAME\" GIT_COMMITTER_EMAIL=\"$DELIVERED_BY_EMAIL\" git commit --author \"$DELIVERED_BY_NAME <$DELIVERED_BY_EMAIL>\" --allow-empty -a -m \"Git-deliver automated commit\""

		echo "Switching the 'current' symlink to the newly delivered version."
		# Using a symlink makes our delivery atomic.

		#TODO: ask for confirmation before switch, with an option to see the complete diff through $PAGER since the last delivery + option to check this diff against the ones generated by running the same update on other environements

		run_remote "test -L \"$REMOTE_PATH/delivered/preprevious\" && { mv \"$REMOTE_PATH/delivered/preprevious\"  \"$REMOTE_PATH/delivered/prepreprevious\"  || exit 5 ; } ; \
			    test -L \"$REMOTE_PATH/delivered/previous\" && { mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/preprevious\" || exit 4 ; } ; \
			    test -L \"$REMOTE_PATH/delivered/current\" && { cp -d \"$REMOTE_PATH/delivered/current\"  \"$REMOTE_PATH/delivered/previous\" || exit 3 ; } ; \
			    cd \"$REMOTE_PATH\"/delivered && { ln -sfn \"$DELIVERY_BASENAME\" \"new\" || exit 2 ; } && { mv -Tf \"$REMOTE_PATH/delivered/new\" \"$REMOTE_PATH/delivered/current\" || exit 1 ; } ; \
				exit 0"

		SYMLINK_SWITCH_STATUS=$?
	fi

	if [[ $SYMLINK_SWITCH_STATUS -gt 0 ]]; then
		echo "Error switching symlinks"
		rollback "pre-symlink"
	fi

	DELIVERY_STAGE="post-symlink"
	run_stage_scripts

	run_remote "test -L \"$REMOTE_PATH/delivered/prepreprevious\" && rm \"$REMOTE_PATH/delivered/prepreprevious\""

	if [[ $FLAGS_batch -ne $FLAGS_TRUE ]]; then
		local GEDITOR=`git var GIT_EDITOR`
		if [[ "$GEDITOR" = "" ]]; then
		        GEDITOR="vi"
		fi
		$GEDITOR "$LOG_TEMPFILE"
	fi

	# TAG the delivered version here and on the origin remote
	local TAG_NAME="delivered-$REMOTE-$DELIVERY_DATE"
	local GPG_OPT=""
	which gpg &> /dev/null
	if [[ $? = 0 ]] && [[ -d ~/.gnupg ]]; then
		if ( gpg -K | grep "$DELIVERED_BY_EMAIL" ) || git config --get user.signingkey; then
			GPG_OPT=" -s"
		fi
	fi
	git tag $GPG_OPT -F "$LOG_TEMPFILE" "$TAG_NAME" "$VERSION"
	rm -f "$LOG_TEMPFILE"
	if [[ "$TAG_TO_PUSH" != "" ]]; then
		TAG_TO_PUSH_MSG=" and tag $TAG_TO_PUSH (git push origin $TAG_TO_PUSH ?)"
	fi
	echo "Delivery complete."
	echo "You might want to publish tag $TAG_NAME (git push origin $TAG_NAME ?)$TAG_TO_PUSH_MSG"
	}

function delivery_sigint_handler
	{
	echo "Caught SIGINT"
	if [[ "$DELIVERY_STAGE" != "rollback-pre-symlink" ]] && [[ "$DELIVERY_STAGE" != "rollback-post-symlink" ]]; then
		LAST_STAGE_REACHED="$DELIVERY_STAGE"
		FAILED_SCRIPT="$CURRENT_STAGE_SCRIPT"
		FAILED_SCRIPT_EXIT_STATUS=0
		rollback
	else
		echo "Delivery aborted during rollback, manual intervention is likely necessary"
		echo "Delivery log : $LOG_TEMPFILE"
		exit 23
	fi
}

function check_git_version
	{
	REMOTE_GIT_VERSION=`run_remote "git --version 2> /dev/null"`
	
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
	echo "Rolling back"
	DELIVERY_STAGE="rollback-pre-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
	
	if [[ $SYMLINK_SWITCH_STATUS != "" ]]; then
		if [[ $FLAGS_rollback -eq $FLAGS_TRUE ]] && [[ $SYMLINK_SWITCH_STATUS -lt 3 ]]; then
				local SYMLINK_ROLLBACK
				if [[ $SYMLINK_SWITCH_STATUS = 0 ]]; then
					run_remote "cp \"$REMOTE_PATH/delivered/current\" \"$REMOTE_PATH/delivered/rolledback\" \
								mv -Tf \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\" \
								mv \"$REMOTE_PATH/delivered/rolledback\" \"$REMOTE_PATH/delivered/previous\""
				elif [[ $SYMLINK_SWITCH_STATUS = 1 ]]; then
					run_remote "rm  \"$REMOTE_PATH/delivered/rolledback\"; mv -Tf \"$REMOTE_PATH/delivered/current\" \"$REMOTE_PATH/delivered/previous\""
				elif [[ $SYMLINK_SWITCH_STATUS = 2 ]]; then
					run_remote "rm  \"$REMOTE_PATH/delivered/rolledback\""
				fi
		elif [[ $FLAGS_rollback != $FLAGS_TRUE ]] && [[ $SYMLINK_SWITCH_STATUS -lt 5 ]]; then
				local SYMLINK_ROLLBACK
				if [[ $SYMLINK_SWITCH_STATUS = 0 ]]; then
					SYMLINK_ROLLBACK="if test -L \"$REMOTE_PATH/delivered/previous\"; then mv -Tf \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\"; else rm -rf \"$REMOTE_PATH/delivered/current\"; fi"
				elif [[ $SYMLINK_SWITCH_STATUS = 1 ]]; then
					SYMLINK_ROLLBACK="rm -f \"$REMOTE_PATH/delivered/new\""
				fi
				if [[ $SYMLINK_SWITCH_STATUS -lt 3 ]]; then
					SYMLINK_ROLLBACK="$SYMLINK_ROLLBACK ; rm -f \"$REMOTE_PATH/delivered/previous\"; test -L \"$REMOTE_PATH/delivered/preprevious\" && mv \"$REMOTE_PATH/delivered/preprevious\"  \"$REMOTE_PATH/delivered/previous\""
				fi
				SYMLINK_ROLLBACK="$SYMLINK_ROLLBACK ; test -L \"$REMOTE_PATH/delivered/prepreprevious\" && mv \"$REMOTE_PATH/delivered/prepreprevious\"  \"$REMOTE_PATH/delivered/preprevious\""

				run_remote "$SYMLINK_ROLLBACK"
			fi
	fi

	DELIVERY_STAGE="rollback-post-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
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
	init "$@"
elif [[ $FLAGS_init_remote -eq $FLAGS_TRUE ]]; then
	init_remote "$@"
elif [[ $FLAGS_list_presets -eq $FLAGS_TRUE ]]; then
	list_presets "$@"
elif [[ $FLAGS_status -eq $FLAGS_TRUE ]]; then
	remote_status "$@" 
elif [[ $FLAGS_gc -eq $FLAGS_TRUE ]]; then
	remote_gc "$@"
elif [[ $FLAGS_source -ne $FLAGS_TRUE ]]; then
	deliver "$@"
fi
