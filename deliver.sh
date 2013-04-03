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

[[ -t 1 ]] || USECOLOR=false;

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
_flags_warn() { echo "Git-deliver: $@" | sed 's/getopt: //'  >&2; exit_with_help; }

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
	if [[ $? -gt 0 ]]; then
		[[ $USECOLOR == true ]] && echo -ne "\E[31m"
		echo "$2"
		[[ $USECOLOR == true ]] && echo -ne "\033[0m"
		exit $1
	fi
	}

function exit_with_help
	{
	echo "Usage : "
	echo "  git deliver <REMOTE> <VERSION>"
	echo "  git deliver --rollback <REMOTE> [DELIVERY]"
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

function indent
	{
	local level=$1
	local prefix=""
	for (( i=0; $i < $level; i=$i+1 )); do
		prefix="$prefix   "
	done
	sed -e "s/^/$prefix/"
	}

function remote_status
	{
	local REMOTE="$1"
	local SHORT="$2"
	if [[ "$REMOTE" = '' ]]; then
		local first_remote=true
		for R in `git remote`; do
			if $first_remote; then
				first_remote=false
			else
				echo ""
			fi
			echo "Remote $R :"
			remote_status "$R" 1
		done
	else
		remote_info "$REMOTE"
		if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
			echo "Not a Git-deliver remote"
			return 1
		fi

		run_remote "bash" <<-EOS
			function indent
				{
				local level=\$1
				local prefix=""
				for (( i=0; \$i < \$level; i=\$i+1 )); do
					prefix="\$prefix   "
				done
				sed -e "s/^/\$prefix/"
				}

			if [[ ! -d "$REMOTE_PATH"/delivered ]]; then
				echo "Not a Git-deliver remote" | indent 1
				exit 1
			fi

			function version_info () {
				local dir=\`basename "\$1"\`
				local dir_resolved
				dir_resolved=\`cd "$REMOTE_PATH/delivered/\$dir" &> /dev/null && pwd -P && cd - &> /dev/null\` 
				if [[ \$? -gt 0 ]]; then
					return 2
				fi

				dir_resolved=\`basename "\$dir_resolved"\`

				if [[ "$SHORT" != "1" ]]; then
					if ! \$first_delivery; then
						echo ""
					fi
					echo -n "\$dir"
					if [[ "\$dir" = "\$dir_resolved" ]]; then
						echo ""
					else
						echo " (\$dir_resolved)"
					fi
				fi

				local short_sha=\${dir_resolved:20:6}
				local latest_sha
				cd "$REMOTE_PATH/delivered/\$dir"
				latest_sha=\`git --git-dir=.git log --pretty=format:%H -n 1 2>&1\`
				if [[ \$? -gt 0 ]]; then
					delivery_info="Unknown"
					return=4
				else
					local previous_sha=\`git log --pretty=format:%H -n 1 --skip 1 2>&1\`
					local branch=\`git rev-parse --abbrev-ref HEAD 2>&1\`
					if [[ "\$branch" = "_delivered" ]] && [[ \${previous_sha:0:6} = \$short_sha ]]; then
						local version=\$previous_sha
						local delivery_info=\`git show --pretty=format:'delivered %aD%nby %aN <%aE>' _delivered\`
						return=3
					else
						local version=\$latest_sha
						local delivery_info="* not delivered with git-deliver *"
						return=4
					fi

					local tags=\`git show-ref --tags -d | grep ^\$version | sed -e 's,.* refs/tags/,,' -e 's/\^{}//'\ | grep -v '^delivered-' | tr "\\n" ", "\`

					if [[ "\$tags" = "" ]]; then
						echo "\$version" | indent 1
					else
						echo "\$version (\$tags)" | indent 1
					fi

					if [[ \`git diff-index HEAD | wc -l\` != "0" ]]; then
						echo "* plus uncommitted changes *" | indent 1
					fi

				fi

				echo "\$delivery_info" | indent 1
				return \$return
			}

			first_delivery=true
			curinfo=\`version_info "current"\`
			RETURN=\$?
			if [[ \$RETURN -lt 3 ]]; then
				echo "No version currently delivered" | indent 1
			else
				echo "\$curinfo"
			fi
			first_delivery=false

			if [[ "$SHORT" != "1" ]]; then
				version_info "previous"
				version_info "preprevious"
				curver=\`{ cd "$REMOTE_PATH/delivered/current" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				prever=\`{ cd "$REMOTE_PATH/delivered/previous" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				preprever=\`{ cd "$REMOTE_PATH/delivered/preprevious" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				for rep in "$REMOTE_PATH/delivered/"*; do
					if [ ! -L "\$rep" ] &&
					   [ "\$rep" != "\$curver" ] &&
					   [ "\$rep" != "\$prever" ] &&
					   [ "\$rep" != "\$preprever" ]; then
						version_info "\$rep"
					fi
				done
			fi

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
	for STAGE in dependencies init-remote pre-delivery post-checkout pre-symlink post-symlink rollback-pre-symlink rollback-post-symlink; do
		mkdir -p "$REPO_ROOT/.deliver/scripts/$STAGE"
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
	if test -n "$(find "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE" -maxdepth 1 -name '*.sh' -print 2> /dev/null)"
		then
		echo "Running scripts for stage $DELIVERY_STAGE" >&2
		for SCRIPT_PATH in "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE"/*.sh; do
			local SCRIPT=`basename "$SCRIPT_PATH"`
			CURRENT_STAGE_SCRIPT="$SCRIPT"
			echo "$DELIVERY_STAGE/$SCRIPT" | indent 1 >&2 
			if [[ "${SCRIPT: -10}" = ".remote.sh" ]]; then
				SHELL='run_remote bash'
			else
				SHELL='bash'
			fi
			local script_result
			{ $SHELL | indent 2 >&2; script_result=${PIPESTATUS[0]}; } <<-EOS
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
				export IS_ROLLBACK="$IS_ROLLBACK"
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
			if [[ $script_result -gt 0 ]]; then
				[[ $USECOLOR == true ]] && echo -ne "\E[31m"
				echo "Script returned with status $script_result" | indent 1 >&2
				[[ $USECOLOR == true ]] && echo -ne "\033[0m" 
				if [[ "$DELIVERY_STAGE" != "rollback-pre-symlink" ]] && [[ "$DELIVERY_STAGE" != "rollback-post-symlink" ]]; then
					LAST_STAGE_REACHED="$DELIVERY_STAGE"
					FAILED_SCRIPT="$CURRENT_STAGE_SCRIPT"
					FAILED_SCRIPT_EXIT_STATUS="$script_result"
					rollback
				else
					[[ $USECOLOR == true ]] && echo -e "\E[31m"
					echo "A script failed during rollback, manual intervention is likely necessary"
					echo "Delivery log : $LOG_TEMPFILE"
					[[ $USECOLOR == true ]] && echo -ne "\033[0m" 
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
	REMOTE_PATH=`echo "$REMOTE_PATH" | sed 's#//#/#g'`
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
		run_remote "mkdir -p \"$REMOTE_PATH\" &> /dev/null"
		exit_if_error 12 "Error creating root directory on remote"
	fi
	if $NEED_INIT; then
		run_remote "cd \"$REMOTE_PATH\" && \
			    git init --bare \"$REMOTE_PATH\" && \
			    git config --bool receive.autogc false"
		exit_if_error 10 "Error initializing repository on remote"
	fi
	run_remote "mkdir \"$REMOTE_PATH\"/delivered &> /dev/null"
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

	if [[ ! $IS_ROLLBACK ]] && [[ $2 = "" ]]; then
		exit_with_help
	fi
	local VERSION="$2"

	CURRENT_STAGE_SCRIPT=""
	LAST_STAGE_REACHED=""
	LOG_TEMPFILE=`make_temp_file`

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
		RSTATUS=`remote_status "$REMOTE" 1`
		local version_line=`echo "$RSTATUS" | head -n +2 | tail -n 1`
		PREVIOUS_VERSION_SHA="${version_line:3:43}"
		echo "Current version on $REMOTE:"
		echo "$RSTATUS" >&2
	fi

	DELIVERY_DATE=`date +'%F_%H-%M-%S'`

	trap delivery_sigint_handler SIGINT

	if [[ $FLAGS_rollback -eq $FLAGS_TRUE ]]; then
		local ROLLBACK_TO_VERSION="$VERSION"
		if [[ "$VERSION" = "" ]]; then
				ROLLBACK_TO_VERSION="previous"
		fi
		DELIVERY_PATH=`run_remote "cd \"$REMOTE_PATH/delivered/$ROLLBACK_TO_VERSION\" && pwd -P" 2>&1`
		if [[ $? -gt 0 ]]; then
			if [[ "$VERSION" = "" ]]; then
				echo "No previous version found; cannot rollback"
			else
				echo "Delivery $VERSION not found on remote. Use 'git deliver --status <REMOTE>' to list available previous deliveries."
			fi
			exit 25
		fi
		local DELIVERY_INFOS
		DELIVERY_INFOS=`run_remote "cd \"$DELIVERY_PATH\" && git log -n 1 --skip 1 --pretty=format:%H && echo "" && git show --pretty=format:'%aD by %aN <%aE>' _delivered | head -n 1" 2>&1`
		exit_if_error 26 "Error getting information on version to rollback to."
		VERSION_SHA=`echo "$DELIVERY_INFOS" | head -n 1`
		local ROLLBACK_TARGET_INFO=`echo "$DELIVERY_INFOS" | tail -n 1`
		DELIVERY_BASENAME=`basename "$DELIVERY_PATH"`
		echo "Rolling back the 'current' symlink to the delivery $DELIVERY_BASENAME ($VERSION_SHA), delivered $ROLLBACK_TARGET_INFO"
	else
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
		echo "Pushing necessary commits to remote"
		{ run "git push \"$REMOTE\" $BRANCH" 2>&1 || exit 14 ; } | indent 1

		# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked easily. The git objects are shared with the base repository.

		echo "Creating new delivery clone"
		{
			run_remote "git clone --shared --no-checkout \"$REMOTE_PATH\" \"$DELIVERY_PATH\" && echo '../../../../objects' > \"$DELIVERY_PATH\"/.git/objects/info/alternates"

			exit_if_error 5 "Error cloning repo to delivered folder on remote" ;
		} | indent 1


		echo "Checking out files..." | indent 1
		{
			run_remote "cd \"$DELIVERY_PATH\" && { test -e .git/refs/heads/"$BRANCH" || git checkout -b $BRANCH origin/$BRANCH ; }" 2>&1 ;
			exit_if_error 15 "Error creating tracking branch on remote clone" ;
		}| indent 1
		
		{
			run_remote "cd \"$DELIVERY_PATH\" && git checkout -b '_delivered' $VERSION" 2>&1 | indent 1 ;
			exit_if_error 6 "Error checking out remote clone" ;
		}
		
		{
			run_remote "cd \"$DELIVERY_PATH\" && git submodule update --init --recursive" 2>&1 | indent 1 ;
			exit_if_error 7 "Error initializing submodules"
		}

		DELIVERY_STAGE="post-checkout"
		run_stage_scripts

		# Commit after the post-checkouts have run and might have changed a few things (added production database passwords for instance).
		# This guarantees the integrity of our delivery from then on. The commit can also be signed to authenticate the delivery.

		local DELIVERED_BY_NAME=`git config --get user.name`
		local DELIVERED_BY_EMAIL=`git config --get user.email`
		run_remote "cd \"$DELIVERY_PATH\" && GIT_COMMITTER_NAME=\"$DELIVERED_BY_NAME\" GIT_COMMITTER_EMAIL=\"$DELIVERED_BY_EMAIL\" git commit --author \"$DELIVERED_BY_NAME <$DELIVERED_BY_EMAIL>\" --allow-empty -a -m \"Git-deliver automated commit\""

		echo "Switching the 'current' symlink to the newly delivered version."
		# Using a symlink makes our delivery atomic.
	fi

	DELIVERY_STAGE="pre-symlink"
	run_stage_scripts

	run_remote "test -L \"$REMOTE_PATH/delivered/preprevious\" && { mv \"$REMOTE_PATH/delivered/preprevious\"  \"$REMOTE_PATH/delivered/prepreprevious\"  || exit 5 ; } ; \
		    test -L \"$REMOTE_PATH/delivered/previous\" && { mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/preprevious\" || exit 4 ; } ; \
		    test -L \"$REMOTE_PATH/delivered/current\" && { cp -d \"$REMOTE_PATH/delivered/current\"  \"$REMOTE_PATH/delivered/previous\" || exit 3 ; } ; \
		    cd \"$REMOTE_PATH\"/delivered && { ln -sfn \"$DELIVERY_BASENAME\" \"new\" || exit 2 ; } && { mv -Tf \"$REMOTE_PATH/delivered/new\" \"$REMOTE_PATH/delivered/current\" || exit 1 ; } ; \
			exit 0"

	SYMLINK_SWITCH_STATUS=$?

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
		bash -c "$GEDITOR \"$LOG_TEMPFILE\""
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
	echo "Tagging delivery commit"
	git tag $GPG_OPT -F "$LOG_TEMPFILE" "$TAG_NAME" "$VERSION_SHA"  2>&1 | indent 1
	rm -f "$LOG_TEMPFILE"
	if [[ "$TAG_TO_PUSH" != "" ]]; then
		TAG_TO_PUSH_MSG=" and tag $TAG_TO_PUSH (git push origin $TAG_TO_PUSH ?)"
	fi
    [[ $USECOLOR == true ]] && echo -ne "\E[32m"
	echo "Delivery complete."
	[[ $USECOLOR == true ]] && echo -ne "\033[0m"
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
	fi
	}

function rollback
	{
	echo "Rolling back"
	DELIVERY_STAGE="rollback-pre-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
	
	if [[ $SYMLINK_SWITCH_STATUS != "" ]] && [[ $SYMLINK_SWITCH_STATUS -lt 5 ]]; then
			local symlink_rollback
			if [[ $SYMLINK_SWITCH_STATUS = 0 ]]; then
				symlink_rollback="if test -L \"$REMOTE_PATH/delivered/previous\"; then mv -Tf \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\"; else rm -rf \"$REMOTE_PATH/delivered/current\"; fi"
			elif [[ $SYMLINK_SWITCH_STATUS = 1 ]]; then
				symlink_rollback="rm -f \"$REMOTE_PATH/delivered/new\""
			fi
			if [[ $SYMLINK_SWITCH_STATUS -lt 3 ]]; then
				symlink_rollback="$symlink_rollback ; rm -f \"$REMOTE_PATH/delivered/previous\"; test -L \"$REMOTE_PATH/delivered/preprevious\" && mv \"$REMOTE_PATH/delivered/preprevious\"  \"$REMOTE_PATH/delivered/previous\""
			fi
			symlink_rollback="$symlink_rollback ; test -L \"$REMOTE_PATH/delivered/prepreprevious\" && mv \"$REMOTE_PATH/delivered/prepreprevious\"  \"$REMOTE_PATH/delivered/preprevious\""

			run_remote "$symlink_rollback"
	fi

	DELIVERY_STAGE="rollback-post-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
	}


# commands

DEFINE_boolean 'source' false 'Used for tests : define functions but don''t do anything.'
DEFINE_boolean 'init' false 'Initialize this repository'
DEFINE_boolean 'init-remote' false 'Initialize a remote'
DEFINE_boolean 'list-presets' false 'List presets available for init'
DEFINE_boolean 'status' false 'Query repository and remotes status'
DEFINE_boolean 'gc' false 'Garbage collection : remove all delivered version on remote except last 3'
DEFINE_boolean 'rollback' false 'Initiate a rollback'

# real flags

DEFINE_boolean 'batch' false 'Batch mode : never ask for anything, die if any information is missing' 'b'
DEFINE_boolean 'color' false 'Use color even if the output does not seem to go to a terminal'
#TODO:
#DEFINE_boolean 'nocolor' false 'Don''t output color'


# parse the command-line
FLAGS "$@"
eval set -- "${FLAGS_ARGV}"

if [[ $FLAGS_color -eq $FLAGS_TRUE ]]; then
   USECOLOR=true
fi
#if [[ $FLAGS_nocolor -eq $FLAGS_TRUE ]]; then
#   USECOLOR=false
#fi


# extract the command flag and make sure we only have one
matched_cmd=0

if [[ $FLAGS_init -eq $FLAGS_TRUE ]]; then
   fn="init"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
if [[ $FLAGS_init_remote -eq $FLAGS_TRUE ]]; then
   fn="init_remote"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
if [[ $FLAGS_list_presets -eq $FLAGS_TRUE ]]; then
   fn="list_presets"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
if [[ $FLAGS_status -eq $FLAGS_TRUE ]]; then
   fn="remote_status"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
if [[ $FLAGS_gc -eq $FLAGS_TRUE ]]; then
   fn="remote_gc"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
if [[ $FLAGS_rollback -eq $FLAGS_TRUE ]]; then
   IS_ROLLBACK=true
   fn="deliver"
   matched_cmd=$(( $matched_cmd + 1 ))
fi
	
if [[ $matched_cmd = 1 ]]; then
	$fn "$@"
elif [[ $matched_cmd = 0 ]]; then
	if [[ $FLAGS_source -ne $FLAGS_TRUE ]]; then
		deliver "$@"
	fi
elif [[ $matched_cmd -gt 1 ]]; then
	echo "You can't have multiple git-deliver 'command' flags on the same command line"
	exit_with_help
fi

