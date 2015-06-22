#!/bin/bash

#
#   Copyright 2012-2015 Arnaud Betremieux <arno@arnoo.net>
#
#   This file is a part of Git-deliver.
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

set -o nounset

USECOLOR=true;
if [[ -t 1 ]]; then
	if [[ ! "$OSTYPE" == "msys" ]]; then
		nb=`tput colors 2>&1`
		if [[ -n "$nb" ]] && [[ $nb -lt 8 ]]; then
			USECOLOR=false;
		fi
	fi
else
	USECOLOR=false;
fi


function echo_green
	{
	local msg="$1"
	[[ $USECOLOR == true ]] && { if [[ $OSTYPE == "msys" ]]; then echo -ne "\E[32m"; else tput setaf 2; fi }
	echo "$msg"
	[[ $USECOLOR == true ]] && { if [[ $OSTYPE == "msys" ]]; then echo -ne "\033[0m"; else tput sgr0; fi }
	}

function echo_red
	{
	local msg="$1"
	[[ $USECOLOR == true ]] && { if [[ $OSTYPE == "msys" ]]; then echo -ne "\E[31m"; else tput setaf 1; fi }
	echo "$msg"
	[[ $USECOLOR == true ]] && { if [[ $OSTYPE == "msys" ]]; then echo -ne "\033[0m"; else tput sgr0; fi }
	}

function exit_with_error
	{
	local code=$1
	local msg="$2"
	echo_red "$msg" >&2
	exit $code
	}

REPO_ROOT=`git rev-parse --git-dir 2> /dev/null` # for some reason, --show-toplevel returns nothing

if [[ $? -gt 0 ]]; then
	exit_with_error 1 "ERROR : not a git repo"
fi
if [[ "$REPO_ROOT" = ".git" ]]; then
	REPO_ROOT=`pwd`
else
	REPO_ROOT="${REPO_ROOT%/.git}"
fi

function path2unix
	{
	local source_path="$1"
	if [[ "${source_path:0:1}" = "/" ]]; then
		echo $source_path
		return
	fi
	local drive_letter=$(echo "${source_path:0:1}" | tr '[A-Z]' '[a-z]')
	echo "/$drive_letter${source_path:2}"
	}

if [[ "$OSTYPE" == "msys" ]]; then
	REPO_ROOT=`path2unix "$REPO_ROOT"`
fi

PRG="$BASH_SOURCE"

while [ -h "$PRG" ] ; do
	ls=`ls -ld "$PRG"`
	link=`expr "$ls" : '.*-> \(.*\)$'`
	if expr "$link" : '/.*' > /dev/null; then
		PRG="$link"
	else
		PRG=`dirname "$PRG"`"/$link"
	fi
done

GIT_DELIVER_PATH=$(dirname "$PRG")

function confirm_or_exit
	{
	local msg="$1"
	local question=""
	[[ $# -gt 1 ]] && question=$2
	local exit_if_batch=true
	[[ $# -gt 2 ]] && exit_if_batch=$3

	echo "$msg" >&2
	if [[ $FLAGS_batch == true ]]; then
		if [[ $exit_if_batch == true ]]; then
			exit 2
		else
			return
		fi
	fi
	if [[ "$question" = "" ]]; then
		question="Continue ?"
	fi
	read -p "$question (y/n) " -n 1 reply >&2
	if [[ ! $reply = "Y" ]] && [[ ! $reply = "y" ]]; then
		exit 1
	fi
	}

function exit_if_error
	{
	if [[ $? -gt 0 ]]; then
		local code=$1
		local msg="$2"
		exit_with_error $code "$msg"
	fi
	}

function exit_with_help
	{
	[[ $# -gt 0 ]] && local code=$1

	echo "Usage : "
	echo "	git deliver <REMOTE> <VERSION>"
	echo "	git deliver --rollback <REMOTE> [DELIVERY]"
	echo "	git deliver --gc <REMOTE>"
	echo "	git deliver --init [PRESETS]"
	echo "	git deliver --init-remote [--shared=...] <REMOTE_NAME> <REMOTE_URL>"
	echo "	git deliver --list-presets"
	echo "	git deliver --status [REMOTE]"

	if [[ -n ${code+defined} ]]; then
		exit $code
	else
		exit 1;
	fi
	}

function indent
	{
	local level=$1
	local prefix=""
	for (( i=0; $i < $level; i=$i+1 )); do
		prefix="$prefix	 "
	done
	sed -e "s/^/$prefix/"
	}

function remote_status
	{
	local remote
	local short=0
	[[ $# -gt 1 ]] && short="$2"
	[[ $# -gt 0 ]] && remote="$1"
	if [[ ! -n ${remote+defined} ]]; then
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
		remote_info "$remote"
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
				echo "Not a Git-deliver remote" | indent $short
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

				if [[ "$short" != "1" ]]; then
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

				local short_sha=\${dir_resolved:22:6}
				local latest_sha
				cd "$REMOTE_PATH/delivered/\$dir"
				latest_sha=\`git --git-dir=.git log --pretty=format:%H -n 1 2>&1\`
				if [[ \$? -gt 0 ]]; then
					delivery_info="Unknown"
					return=4
				else
										if [[ \`git log -n 1 --pretty=format:%B --skip=1\` = "git-deliver local-build commit" ]]; then
											local previous_sha=\`git log --pretty=format:%H -n 1 --skip=2 2>&1\`
										else
											local previous_sha=\`git log --pretty=format:%H -n 1 --skip=1 2>&1\`
										fi
					local branch=\`git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>&1\`
					if [[ "\$branch" = "_delivered" ]] && [[ \${previous_sha:0:6} = \$short_sha ]]; then
						local version=\$previous_sha
						local delivery_info=\`git show --pretty=format:'delivered %aD%nby %aN <%aE>' _delivered 2>&1 | head -n 2\`
						return=3
					else
						local version=\$latest_sha
						local delivery_info="* not delivered with git-deliver *"
						return=4
					fi

					local tags=\`git show-ref --tags -d | grep ^\$version | sed -e 's,.* refs/tags/,,' -e 's/\^{}//g' | grep -v '^delivered-' | tr "\\n" ","	| sed -e 's/,/, /g' -e 's/, $//g'\`

					if [[ "\$tags" = "" ]]; then
						echo "\$version" | indent 1
					else
						echo "\$version (\$tags)" | indent 1
					fi

					git diff-index HEAD --quiet --exit-code 
					if [[ \$? -gt "0" ]]; then
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
				echo "No version currently delivered" | indent $short
			else
				echo "\$curinfo"
			fi
			first_delivery=false

			if [[ "$short" != "1" ]]; then
				version_info "previous"
				version_info "preprevious"
				curver=\`{ cd "$REMOTE_PATH/delivered/current" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				prever=\`{ cd "$REMOTE_PATH/delivered/previous" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				preprever=\`{ cd "$REMOTE_PATH/delivered/preprevious" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
				for rep in "$REMOTE_PATH/delivered/"*; do
					if [ ! -L "\$rep" ]; then
						rep=\`{ cd "\$rep" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`
						if	 [ "\$rep" != "\$curver" ] &&
							 [ "\$rep" != "\$prever" ] &&
							 [ "\$rep" != "\$preprever" ]; then
							version_info "\$rep"
						fi
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
	for preset_path in "$GIT_DELIVER_PATH"/presets/*; do
		local preset=`basename "$preset_path"`
		if [[ -f "$preset_path/info" ]]; then
			local DEPENDECIES;
			local DESCRIPTION;
			source "$preset_path/info"
			echo "$preset : $DESCRIPTION [$DEPENDENCIES]"
		fi
	done
	}

function check_preset
	{
	local preset="$1"
	if [[ -d "$GIT_DELIVER_PATH/presets/$preset" ]]; then
		local DEPENDENCIES=""
		local DESCRIPTION="ERROR"
		local info_path="$GIT_DELIVER_PATH/presets/$preset/info"
		if [[ ! -f "$info_path" ]]; then
			exit_with_error 21 "ERROR : Info file for preset $preset not found."
		fi
		source "$info_path"
		if [[ "$DESCRIPTION" = "ERROR" ]] || [[ "$DESCRIPTION" = "" ]]; then
			exit_with_error 20 "ERROR : Missing description for preset $PRESET"
		fi
		local oldifs=$IFS
		if [[ "$DEPENDENCIES" != "" ]]; then
			IFS=',' read -ra dependencies <<< "$DEPENDENCIES"
			for dep in "${dependencies[@]}"; do
				check_preset "$dep"
			done
		fi
	else
		exit_with_error 19 "ERROR : could not find preset $preset"
	fi
	}

# Copies the files for preset $1 to the repo's .deliver/scripts directory
function init_preset
	{
	local preset="$1"
	if echo "$INIT_PRESETS" | grep ",$preset," > /dev/null; then
		return
	fi
	[ -d "$GIT_DELIVER_PATH"/presets/"$preset" ] || exit_with_error 10 "Preset not found : $preset"
	[ -d "$GIT_DELIVER_PATH"/presets/"$preset"/dependencies ] && cp -ri "$GIT_DELIVER_PATH"/presets/"$preset"/dependencies "$REPO_ROOT"/.deliver/scripts/dependencies/"$preset"
	for preset_stage_dir in "$GIT_DELIVER_PATH/presets/$preset"/*; do
		[ -d "$preset_stage_dir" ] || continue
		local preset_stage=`basename "$preset_stage_dir"`
		[ "$preset_stage" = "dependencies" ] && continue
		for script_file in "$preset_stage_dir"/*; do
			local script_name=`basename "$script_file"`
			local script_seqnum=${script_name%%-*}
			local script_label="${script_name:$((${#script_seqnum}+1))}"
			cp -i "$script_file" "$REPO_ROOT"/.deliver/scripts/$preset_stage/"$script_seqnum-$preset-$script_label"
		done
	done
	INIT_PRESETS="$INIT_PRESETS$preset,"
	local DEPENDENCIES=""
	local DESCRIPTION=""
	source "$GIT_DELIVER_PATH/presets/$preset"/info
	if [[ -n ${DEPENDENCIES+defined} ]] && [[ "$DEPENDENCIES" != "" ]]; then
		IFS=',' read -ra dependencies <<< "$DEPENDENCIES"
		for dep in "${dependencies[@]}"; do
			init_preset "$dep"
		done
	fi
	}

function init
	{
	[[ $# -gt 0 ]] && local presets="$1"

	if [[ -n ${presets+defined} ]]; then
		IFS=',' read -ra presets <<< "$presets"
		for preset_dir in "${presets[@]}"; do
			local preset=`basename "$preset_dir"`
			check_preset $preset
			done
	fi
	mkdir -p "$REPO_ROOT/.deliver/scripts"
	for stage in dependencies init-remote local-build pre-delivery post-checkout pre-symlink post-symlink rollback-pre-symlink rollback-post-symlink; do
		mkdir -p "$REPO_ROOT/.deliver/scripts/$stage"
		echo -e "Put your $stage Bash scripts in this folder with a .sh extension.\n\nSee https://github.com/arnoo/git-deliver for help." >> "$REPO_ROOT/.deliver/scripts/$stage/README"
	done
	echo "Setting up core preset" >&2
	INIT_PRESETS=","
	init_preset core
	if [[ -n ${presets+defined} ]]; then
		for preset_dir in "${presets[@]}"; do
			local preset=`basename "$preset_dir"`
			echo "Setting up $preset preset" >&2
			init_preset $preset
		done
	fi
	}

function run_stage_scripts
	{
	if test -n "$(find "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE" -maxdepth 1 -name '*.sh' -print 2> /dev/null)"
		then
		echo "Running scripts for stage $DELIVERY_STAGE" >&2
		for SCRIPT_PATH in "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE"/*.sh; do
			local script=`basename "$SCRIPT_PATH"`
			CURRENT_STAGE_SCRIPT="$script"
			echo "$DELIVERY_STAGE/$script" | indent 1 >&2 
			local shell
			if [[ "${script: -10}" = ".remote.sh" ]]; then
				shell='run_remote bash'
			else
				shell='bash'
			fi
			local script_result
			{ $shell | indent 2 >&2; script_result=${PIPESTATUS[0]}; } <<-EOS
				export GIT_DELIVER_PATH="$GIT_DELIVER_PATH"
				export REPO_ROOT="$REPO_ROOT"
				export DELIVERY_DATE="${DELIVERY_DATE:-}"
				export DELIVERY_PATH="${DELIVERY_PATH:-}"
				export VERSION="${VERSION:-}"
				export VERSION_SHA="${VERSION_SHA:-}"
				export PREVIOUS_VERSION_SHA="${PREVIOUS_VERSION_SHA:-}"
				export REMOTE_SERVER="$REMOTE_SERVER"
				export REMOTE_PATH="$REMOTE_PATH"
				export REMOTE="$REMOTE"
				export LAST_STAGE_REACHED="${LAST_STAGE_REACHED:-}"
				export IS_ROLLBACK="$IS_ROLLBACK"
				export FAILED_SCRIPT="${FAILED_SCRIPT:-}"
				export FAILED_SCRIPT_EXIT_STATUS="${FAILED_SCRIPT_EXIT_STATUS:-}"
				export DELIVER_GIT_SSH="${GIT_SSH:-}"
				unset GIT_SSH
				
				function run_remote
					{
					local command="\$*"
					if [[ "$REMOTE_SERVER" = "" ]]; then
						bash -c "\$command"
					else
						"${GIT_SSH:-}" "$REMOTE_SERVER" "\$command"
					fi
					}
				
				export -f run_remote
				
				`cat "$SCRIPT_PATH"`
			EOS
			if [[ $script_result -gt 0 ]]; then
				echo_red "Script returned with status $script_result" | indent 1 >&2
				if [[ "$DELIVERY_STAGE" != "rollback-pre-symlink" ]] && [[ "$DELIVERY_STAGE" != "rollback-post-symlink" ]] && [[ "$DELIVERY_STAGE" != "init-remote" ]]; then
					LAST_STAGE_REACHED="$DELIVERY_STAGE"
					FAILED_SCRIPT="$CURRENT_STAGE_SCRIPT"
					FAILED_SCRIPT_EXIT_STATUS="$script_result"
					rollback
					exit 3
				elif [[ "$DELIVERY_STAGE" == "init-remote" ]]; then
					echo_red "A script failed during init-remote, manual intervention is likely necessary"
					exit 30 
				else
					echo_red "A script failed during rollback, manual intervention is likely necessary"
					echo_red "Delivery log : $LOG_TEMPFILE"
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

function ssh_cleanup
	{
	# Call the ssh wrapper with only our PID as argument to kill the master SSH connection
	"$GIT_SSH"
	rm -f "$GIT_SSH"
	}

function ssh_init
	{
	local remote=$1
	export GIT_SSH="/tmp/git_deliver_ssh_wrapper_$$_$remote.sh"
	[[ -e "$GIT_SSH" ]] && return # init has already been done for this remote
	echo -e "#!/bin/bash\n\n\"$GIT_DELIVER_PATH\"/deliver_ssh_wrapper.sh $$_$remote \"\$@\"" > "$GIT_SSH"
	chmod +x "$GIT_SSH"
	trap ssh_cleanup EXIT
	}

function remote_info
	{
	local remote="$1"
	[[ $# -gt 1 ]] && local init="$2"
	[[ $# -gt 2 ]] && local init_url="$3"

	if echo "$remote" | grep -vE '^[A-Za-z0-9\./_-]+$'; then
		echo "Not a valid remote name : $remote"
		exit_with_help 22
	fi

	git remote -v | grep '^'"$remote"'	' | grep '(push)' &> /dev/null
	if [[ $? -gt 0 ]]; then
		if [[ -n ${init+defined} ]]; then
			if [[ ! -n ${init_url+defined} ]]; then
				confirm_or_exit "Remote $remote not found." "Create it ?"
				echo ""
				read -p "URL for remote :" INIT_URL
			fi
			git remote add "$remote" "$init_url"
			exit_if_error 8 "Error adding remote in local Git config"
			if [[ ! -n ${IN_INIT+defined} ]] || [[ ! $IN_INIT ]]; then
				init_remote "$remote" "$init_url"
			fi
		else
			exit_with_error 29 "Remote $remote not found."
		fi
	fi

	REMOTE_URL=`git config --get "remote.$remote.url"`
	if echo "$REMOTE_URL" | grep "://" > /dev/null; then
		REMOTE_PROTO=`echo "$REMOTE_URL" | cut -d: -f 1`
		REMOTE_PROTO=`echo "${REMOTE_PROTO}" | tr '[A-Z]' '[a-z]'`
		REMOTE_SERVER=`echo "$REMOTE_URL" | cut -d/ -f 3`
				REMOTE_PATH=`echo "$REMOTE_URL" | cut -d/ -f 4-`
				if [[ "${REMOTE_PATH:0:1}" != "~" ]]; then
					REMOTE_PATH="/$REMOTE_PATH"
				fi
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
				REMOTE_PATH="$REMOTE_URL"
	fi
	REMOTE_PATH=`echo "$REMOTE_PATH" | sed 's#//#/#g'`
	if [[ "$REMOTE_PROTO" == "ssh" ]]; then 
		ssh_init $remote
	fi
		if [[ "${REMOTE_PATH:0:1}" = "~" ]]; then
			local home_part=${REMOTE_PATH%%[ /]*}
			REMOTE_PATH=`run_remote "echo $home_part"`${REMOTE_PATH:${#home_part}}
		fi
	if [[ "$REMOTE_PROTO" == "local" ]] && [[ "${REMOTE_PATH:0:1}" != "/" ]]; then 
			REMOTE_PATH="$REPO_ROOT/$REMOTE_PATH"
		fi
	}

function run
	{
	local command="$*"
	echo "running $command" >> "$LOG_TEMPFILE"
	bash -c "$command"
	}

function run_remote
	{
	local command="cd /tmp && { $* ; }"
	if [[ -n ${REMOTE_SERVER+defined} ]] && [[ "$REMOTE_SERVER" != "" ]]; then
		if [[ -n ${LOG_TEMPFILE+defined} ]]; then
			echo "running "$GIT_SSH" \"$REMOTE_SERVER\" \"$command\"" >> "$LOG_TEMPFILE"
		fi
		"$GIT_SSH" "$REMOTE_SERVER" "$command"
	else
		if [[ -n ${LOG_TEMPFILE+defined} ]]; then
			echo "running bash -c \"$command\"" >> "$LOG_TEMPFILE"
		fi
		bash -c "$command"
	fi
	}

function init_remote
	{
	if [[ $# -gt 3 ]]; then
		exit_with_help
	fi
	IN_INIT=true
	INIT_URL=""
	[[ $# -gt 1 ]] && INIT_URL="$2"
	REMOTE="$1"
	remote_info "$REMOTE" true "$INIT_URL"
	
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		exit_with_error 17 "Git-deliver can only work with ssh or 'local' remotes"
	fi
	
	run_remote "{ test -d \"$REMOTE_PATH\"/refs && test -d \"$REMOTE_PATH\"/delivered ; } &> /dev/null"
	if [[ $? = 0 ]]; then
		exit_with_error 18 "This remote looks like it has already been setup for git-deliver."
	fi
	

	NEED_INIT=true
	run_remote "test -e \"$REMOTE_PATH\" &> /dev/null"
	if [[ $? = 0 ]]; then
		run_remote "test -d \"$REMOTE_PATH\" &> /dev/null"
		if [[ $? -gt 0 ]]; then
			exit_with_error 10 "ERROR: Remote path points to a file"
		else
			if [[ `run_remote "ls -1 \"$REMOTE_PATH\" | wc -l | tr -d ' '"` != "0" ]]; then
				git fetch "$REMOTE" &> /dev/null
				if [[ $? -gt 0 ]]; then
					exit_with_error 9 "ERROR : Remote directory is not empty and does not look like a valid Git remote for this repo"
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
				git init --shared=$FLAGS_shared --bare \"$REMOTE_PATH\" && \
				git config --bool receive.autogc false"
		exit_if_error 10 "Error initializing repository on remote"
	fi

	create_delivered_dir_if_needed

	DELIVERY_STAGE="init-remote"
	run_stage_scripts
	echo_green "Remote is ready to receive deliveries"
	IN_INIT=""
	}

function create_delivered_dir_if_needed
	{
	run_remote "if [[ ! -d \"$REMOTE_PATH\"/delivered ]]; then
					mkdir \"$REMOTE_PATH\"/delivered || exit 1
					ls -ld \"$REMOTE_PATH/objects\" | cut -c 6 | grep 'w' ;
					if [[ \$? = 0 ]]; then
						chgrp \`ls -gd \"$REMOTE_PATH/objects\" | awk '{print \$3}'\` \"$REMOTE_PATH/delivered\" && \
						chmod g+w \"$REMOTE_PATH/delivered\" ;
					fi ;
				fi"
	exit_if_error 11 "Error creating 'delivered' directory in remote root"
	}

function remote_gc
	{
	if [[ $# -gt 1 ]] || [[ $# -lt 1 ]]; then
		exit_with_help
	fi
	local remote="$1"
	remote_info "$remote"
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		exit_with_error 17 "$remote is not a Git-deliver remote"
	fi
	LOG_TEMPFILE=`make_temp_file`
	local gc_script="
		CURVER=\`{ cd \"$REMOTE_PATH/delivered/current\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\` ;
		PREVER=\`{ cd \"$REMOTE_PATH/delivered/previous\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`;
		PREPREVER=\`{ cd \"$REMOTE_PATH/delivered/preprevious\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\`;
		DELETED=0 ;
		FREED_BYTES=0 ;
		STATUS=0 ;
		for rep in \"$REMOTE_PATH/delivered/\"* ; do
			if [ ! -L \"\$rep\" ]; then
							rep=\`{ cd \"\$rep\" && pwd -P && cd - > /dev/null ; } 2> /dev/null\` ;
				if [ \"\$rep\" != \"\$CURVER\" ] &&
								 [ \"\$rep\" != \"\$PREVER\" ] &&
								 [ \"\$rep\" != \"\$PREPREVER\" ]; then
									echo \"Removing \$rep\" ;
					if ( du --version 2>/dev/null | grep -q GNU\  ) ; then
						FREED_BYTES_NEW=\`du -sb \"\$rep\" | cut -f1\` ;
					else
						FREED_BYTES_NEW=\`du -s \"\$rep\" | awk '{printf \"%d\", \$1/512}'\` ;
					fi ;
					rm -rf \"\$rep\" && \
					DELETED=\$((\$DELETED + 1)) && \
				 		FREED_BYTES=\$((\$FREED_BYTES + \$FREED_BYTES_NEW)) || \
					STATUS=27 ;
				fi ;
			fi ;
		done ;
		if [[ \$FREED_BYTES = 0 ]]; then
			HUMAN_FREED_BYTES=\"0 B\" ;
		else
			HUMAN_FREED_BYTES=\`echo \$FREED_BYTES | awk '{x = \$0;
									 split(\"B KB MB GB TB PB\", type);
									 for(i=5;y < 1;i--)
									 y = x / (2^(10*i));
									 print y \" \" type[i+2];
									 }'\` ;
		fi ;
		echo \"\$DELETED version(s) removed, \$HUMAN_FREED_BYTES freed\" ;
		cd \"$REMOTE_PATH\"/delivered && git gc --auto ;
		exit \$STATUS"
	run_remote "$gc_script"
	local status=$?
	rm -f "$LOG_TEMPFILE"
	exit $status
	}

function make_temp_file
	{
	local tempdir
	local tempfile
	if [[ -n ${TMPDIR+defined} ]] && [[ "$TMPDIR" != "" ]]; then
		tempdir="$TMPDIR"
	else
		tempdir="/tmp"
	fi
	which mktemp &> /dev/null
	if [[ $? = 0 ]]; then
		mktemp "$tempdir/git-deliver-XXXXXXXXXX"
	else
		tempfile="$tempdir"/git-deliver-$$.$RANDOM
		touch "$tempfile"
		echo "$tempfile"
	fi
	}

function get_branch_for_version
	{
	# branches containing version
	local eligible_branches=`git branch -a --contains $1 | grep -v '(no branch)' | tr -d '^ *' | tr -d '^ ' | sed 's/^remotes\///'`

	# if version is a branch, picks it
	local branch=`echo "$eligible_branches" | grep "^$1$" | head -n 1`

	# else, tries currently checked-out branch if eligible
	local current_branch=`git rev-parse --symbolic-full-name --abbrev-ref HEAD`
	if [[ "$branch" == "" ]]; then
		branch=`echo "$eligible_branches" | grep "^$current_branch$" | head -n 1`
	fi

	# else, tries master if eligible
	if [[ "$branch" == "" ]]; then
		branch=`echo "$eligible_branches" | grep "^master$" | head -n 1`
	fi

	# else, picks first eligible branch
	if [[ "$branch" == "" ]]; then
		branch=`echo "$eligible_branches" | head -n 1`
	fi

	echo "$branch"
	}

function deliver
	{
	if [[ $# -gt 2 ]] || [[ $# -lt 1 ]]; then
		exit_with_help
	fi
	REMOTE="$1"

	if [[ $IS_ROLLBACK == false ]] && [[ $# -lt 2 ]]; then
		exit_with_help
	fi
	[[ $# -gt 1 ]] && VERSION="$2"

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

	if [[ -n ${VERSION+defined} ]];	then
		if [[ $IS_ROLLBACK == "false" ]]; then
			echo -en "Delivery of ref \"$VERSION\" to" >> "$LOG_TEMPFILE"
		else
			echo -en "Rollback to \"$VERSION\" on" >> "$LOG_TEMPFILE"
		fi
	else
		echo -en "Rollback to previous version on" >> "$LOG_TEMPFILE"
	fi

	echo -e " remote \"$REMOTE\"\n\n" >> "$LOG_TEMPFILE"

	if [[ ! -d "$REPO_ROOT/.deliver" ]]; then
		confirm_or_exit ".deliver not found." "Run init ?"
		init
	fi

	remote_info "$REMOTE"
	
	if [[ "$REMOTE_PROTO" != "ssh" ]] && [[ "$REMOTE_PROTO" != "local" ]]; then
		exit_with_error 17 "Git-deliver can only work with ssh or 'local' remotes"
	fi

	check_git_version_and_ssh_connectivity "$REMOTE"

	local remote_dir_list=`run_remote "cd \"$REMOTE_PATH\" 2> /dev/null && ls -1 2> /dev/null"`
	if [[ "$remote_dir_list" = "" ]]; then
		init_remote "$REMOTE"
	else
		local remote_dir_git_count=`echo "$remote_dir_list" | grep "^objects\|refs$" | wc -l | tr -d ' '`
		if [[ "$remote_dir_git_count" -lt "2" ]]; then
			exit_with_error 1 "ERROR : Remote does not look like a bare git repo"
		fi
	fi

	# If this projet has init-remote scripts, check that the remote has been init. Otherwise, we don't really care, as it's just a matter of creating the 'delivered' directory

	if [[ -e "$REPO_ROOT"/.deliver/scripts/init-remote ]] && test -n "$(find "$REPO_ROOT/.deliver/scripts/init-remote" -maxdepth 1 -name '*.sh' -print)"; then
		run_remote "test -d \"$REMOTE_PATH\"/delivered"
		if [[ $? -gt 0 ]]; then
			exit_with_error 22 "ERROR : Remote has not been init"
		fi
	fi

	if [[ $IS_ROLLBACK == false	]]; then
		VERSION_SHA=`git rev-parse --revs-only $VERSION 2> /dev/null`

		if [[ "$VERSION_SHA" = "" ]]; then
			confirm_or_exit "Ref $VERSION not found." "Tag current HEAD ?"
			VERSION_SHA=`git rev-parse HEAD`
			echo "Tagging current HEAD" >&2
			git tag $VERSION
			local tag_to_push=$VERSION
		fi
	fi

	local rstatus
	rstatus=`remote_status "$REMOTE" 1`

	local rstatus_code=$?
	if [[ $rstatus_code -lt 3 ]]; then
		echo "No version delivered yet on $REMOTE" >&2
		if [[ $IS_ROLLBACK == true ]]; then
			exit_with_error 24 "Cannot rollback"
		fi
	else
		local version_line=`echo "$rstatus" | head -n +2 | tail -n 1`
		PREVIOUS_VERSION_SHA="${version_line:3:43}"
		echo "Current version on $REMOTE:"
		echo "$rstatus" >&2
	fi

	DELIVERY_DATE=`( date --version 2>/dev/null | grep -q GNU\  && date +'%F_%H-%M-%S%N' ) || ( which gdate &>/dev/null && gdate +'%F_%H-%M-%S%N' ) || ( which python &> /dev/null && python -c 'import datetime; print datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S%f")' ) || ( date +'%F_%H-%M-%S' )`
	DELIVERY_DATE=${DELIVERY_DATE:0:21}

	local delivered_by_name=`git config --get user.name`
	local delivered_by_email=`git config --get user.email`

	run_remote "mv --version 2>/dev/null | grep -q GNU\  || which python &> /dev/null"
	if [[ $? -ne 0 ]]; then
				confirm_or_exit "Warning: remote has neither GNU mv nor Python installed. Delivery will not be atomic : for a very short time, the 'current' symlink will not exist." "" false
	fi

	trap delivery_sigint_handler SIGINT

	if [[ $IS_ROLLBACK == true ]]; then
		local rollback_to_version;
		if [[ -n ${VERSION+defined} ]]; then
			rollback_to_version="$VERSION"
		else
			rollback_to_version="previous"
		fi
		DELIVERY_PATH=`run_remote "cd \"$REMOTE_PATH/delivered/$rollback_to_version\" && pwd -P" 2>&1`
		if [[ $? -gt 0 ]]; then
			if [[ -n ${VERSION+defined} ]]; then
				exit_with_error 25 "Delivery $VERSION not found on remote. Use 'git deliver --status <REMOTE>' to list available previous deliveries."
			else
				exit_with_error 25 "No previous version found; cannot rollback"
			fi
		fi
		local delivery_infos
		delivery_infos=`run_remote "cd \"$DELIVERY_PATH\" && git log -n 1 --skip=1 --pretty=format:%H && echo "" && git show --pretty=format:'%aD by %aN <%aE>' _delivered | head -n 1" 2>&1`
		exit_if_error 26 "Error getting information on version to rollback to."
		VERSION_SHA=`echo "$delivery_infos" | head -n 1`
		local rollback_target_info=`echo "$delivery_infos" | tail -n 1`
		DELIVERY_BASENAME=`basename "$DELIVERY_PATH"`
		SYMLINK_MSG="Rolling back the 'current' symlink to the delivery $DELIVERY_BASENAME ($VERSION_SHA), delivered $rollback_target_info"
	else
		local human_version="${VERSION_SHA:0:6}"
		if [[ $VERSION != $VERSION_SHA ]]; then
			human_version="$human_version"_"${VERSION/\//_}"
		fi
		DELIVERY_BASENAME="$DELIVERY_DATE"_"$human_version"
		DELIVERY_PATH="$REMOTE_PATH/delivered/$DELIVERY_BASENAME"

		local branch=`get_branch_for_version $VERSION`
		if [[ "$branch" == "" ]]; then
			exit_with_error 16 "No branch found for ref $VERSION, commit must belong to a branch to be deliverable"
		fi

				DELIVERY_STAGE="local-build"
				LBVERSION="$VERSION"
				if test -n "$(find "$REPO_ROOT/.deliver/scripts/$DELIVERY_STAGE" -maxdepth 1 -name '*.sh' -print 2> /dev/null)"; then
					local lbclone="$REPO_ROOT/.deliver/tmp/lbclone"
                                        if [[ -d "$lbclone/.git" ]]; then
                                            run "cd \"$lbclone\" && git fetch origin && git reset --hard origin/$branch; cd -" 2>&1 | indent 1
                                        else
                                            run "git clone --recursive \"$REPO_ROOT\" \"$lbclone\"" 2>&1 | indent 1
                                        fi
					exit_if_error 32 "Cannot create local-build clone"
					cd "$lbclone" 
					run "git checkout \"$VERSION\"" 2>&1 | indent 1
					exit_if_error 33 "Cannot checkout in local-build clone"
                                        run "cd \"$lbclone\" && git submodule update --init --recursive; cd -" 2>&1 | indent 1
					exit_if_error 34 "Cannot update submodules in local-build clone"
					cd "$lbclone"
					run_stage_scripts
					run "git commit -am \"git-deliver local-build commit\"" 2>&1 | indent 1
					[[ $? -eq 0 ]] && LBVERSION=`git log --pretty=format:%H -n 1`
					cd "$REPO_ROOT"
				fi

		DELIVERY_STAGE="pre-delivery"
		run_stage_scripts

		echo "Pushing necessary commits to remote"
		local delivery_branch=`echo $branch | cut -d"/" -f2`
		[[ $FLAGS_force == true ]] && local force="--force" || local force=""
		run "git push $force \"$REMOTE\" $branch:$delivery_branch" 2>&1 | indent 1
		if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
			exit 14 ;
		fi

		local tags=$(git show-ref --tags -d | grep "^$VERSION_SHA" | cut -d" " -f2 | sed -e 's,refs/tags/,,g' | grep -v ^delivered-)
		if [[ "$tags" != "" ]]; then
			run "git push $force \"$REMOTE\" tag $tags"
			exit_if_error 13
		fi

		create_delivered_dir_if_needed

		# Checkout the files in a new directory. We actually do a full clone of the remote's bare repository in a new directory for each delivery. Using a working copy instead of just the files allows the status of the files to be checked easily. The git objects are shared with the base repository.

		echo "Creating new delivery clone"
		run_remote "git clone --shared --no-checkout \"$REMOTE_PATH\" \"$DELIVERY_PATH\" && echo '../../../../objects' > \"$DELIVERY_PATH\"/.git/objects/info/alternates"
		if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
			exit_with_error 5 "Error cloning repo to delivered folder on remote" ;
		fi

		echo "Checking out files..." | indent 1
		run_remote "cd \"$DELIVERY_PATH\" && git branch _delivered $VERSION_SHA" 2>&1 | indent 1
		if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
			exit_with_error 15 "Error creating tracking branch on remote clone" ;
		fi

				if [[ "$LBVERSION" != "$VERSION" ]]; then
					echo "Pushing local build files to delivery clone"
					run "cd \"$lbclone\" && git push $force \"$REMOTE_SERVER\":\"$DELIVERY_PATH\" $LBVERSION:_delivered ; cd \"$REPO_ROOT\"" 2>&1
				fi
		
		run_remote "cd \"$DELIVERY_PATH\" && git checkout _delivered" 2>&1 | indent 1
		if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
			exit_with_error 6 "Error checking out remote clone"
		fi
		
		run_remote "cd \"$DELIVERY_PATH\" && git submodule update --init --recursive" 2>&1 | indent 1
		if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
			exit_with_error 7 "Error initializing submodules"
		fi

		DELIVERY_STAGE="post-checkout"
		run_stage_scripts

		# Commit after the post-checkouts have run and might have changed a few things (added production database passwords for instance).
		# This guarantees the integrity of our delivery from then on. The commit can also be signed to authenticate the delivery.

		run_remote "cd \"$DELIVERY_PATH\" && GIT_COMMITTER_NAME=\"$delivered_by_name\" GIT_COMMITTER_EMAIL=\"$delivered_by_email\" git commit --author \"$delivered_by_name <$delivered_by_email>\" --allow-empty -a -m \"Git-deliver automated commit\""

		run_remote "ls -ld \"$REMOTE_PATH/objects\" | cut -c 6 | grep 'w' && chgrp -R \`ls -gd \"$REMOTE_PATH/objects\" | awk '{print \$3}'\` \"$DELIVERY_PATH\" && chmod -R g+w \"$DELIVERY_PATH\""


		SYMLINK_MSG="Switching the 'current' symlink to the newly delivered version."
		# Using a symlink makes our delivery atomic.
	fi

	DELIVERY_STAGE="pre-symlink"
	run_stage_scripts

	echo "$SYMLINK_MSG"

	run_remote "test -L \"$REMOTE_PATH/delivered/preprevious\" && { rm -f \"$REMOTE_PATH/delivered/prepreprevious\"; mv \"$REMOTE_PATH/delivered/preprevious\"	\"$REMOTE_PATH/delivered/prepreprevious\"	|| exit 5 ; } ; \
			test -L \"$REMOTE_PATH/delivered/previous\" && { mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/preprevious\" || exit 4 ; } ; \
			test -L \"$REMOTE_PATH/delivered/current\" && { cp -d \"$REMOTE_PATH/delivered/current\"	\"$REMOTE_PATH/delivered/previous\" || exit 3 ; } ; \
			cd \"$REMOTE_PATH\"/delivered ; \
			if ( mv --version 2>/dev/null | grep -q GNU\  ) ; then \
				{ ln -sfn \"$DELIVERY_BASENAME\" \"new\" || exit 2 ; } && { mv -Tf \"$REMOTE_PATH/delivered/new\" \"$REMOTE_PATH/delivered/current\" || exit 1 ; } ; \
			elif ( which python &> /dev/null ) ; then \
				{ ln -sfn \"$DELIVERY_BASENAME\" \"new\" || exit 2 ; } && { python -c 'import os; os.rename(\"$REMOTE_PATH/delivered/new\",\"$REMOTE_PATH/delivered/current\");' || exit 1 ; } ; \
			else \
				ln -sfn \"$DELIVERY_BASENAME\" \"current\" || exit 2 ; \
			fi ; \
			exit 0"

	SYMLINK_SWITCH_STATUS=$?

	if [[ $SYMLINK_SWITCH_STATUS -gt 0 ]]; then
		echo "Error switching symlinks"
		rollback "pre-symlink"
	fi

	DELIVERY_STAGE="post-symlink"
	run_stage_scripts

	run_remote "test -L \"$REMOTE_PATH/delivered/prepreprevious\" && rm \"$REMOTE_PATH/delivered/prepreprevious\""

	if [[ $FLAGS_batch == false ]]; then
		local geditor=`git var GIT_EDITOR`
		if [[ "$geditor" = "" ]]; then
			geditor="vi"
		fi
		bash -c "$geditor \"$LOG_TEMPFILE\""
	fi

	# TAG the delivered version
	local tag_name="delivered-$REMOTE-$DELIVERY_DATE"
	echo "Tagging delivery commit"
	git tag -F "$LOG_TEMPFILE" "$tag_name" "$VERSION_SHA"	2>&1 | indent 1
	run "git push \"$REMOTE\" refs/tags/\"$tag_name\"" 2>&1 | indent 1
	rm -f "$LOG_TEMPFILE"
	local tag_to_push_msg=""
	if [[ -n ${tag_to_push+defined} ]] && [[ "$tag_to_push" != "" ]]; then
		tag_to_push_msg=" and tag $tag_to_push (git push origin $tag_to_push ?)"
	fi
	echo_green "Delivery complete."
	echo "You might want to publish tag $tag_name (git push origin $tag_name ?)${tag_to_push_msg:-}"
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
		exit_with_error 23 "Delivery aborted during rollback, manual intervention is likely necessary\nDelivery log : $LOG_TEMPFILE"
	fi
}

function check_git_version_and_ssh_connectivity
	{
	local remote_git_version
	remote_git_version=`run_remote "git --version 2> /dev/null"`
	local code=$?

	if [[ $code = 127 ]]; then
		exit_with_error 11 "ERROR: Git needs to be installed and in \$PATH on the remote"
	elif [[ $code = 255 ]]; then
		exit_with_error 28 "ERROR: Could not open SSH connection"
	fi
	}

function rollback
	{
	echo "Rolling back"
	DELIVERY_STAGE="rollback-pre-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
	
	if [[ -n ${SYMLINK_SWITCH_STATUS+defined} ]] && [[ $SYMLINK_SWITCH_STATUS -lt 5 ]]; then
			local symlink_rollback
			if [[ $SYMLINK_SWITCH_STATUS = 0 ]]; then
				symlink_rollback="if test -L \"$REMOTE_PATH/delivered/previous\"; then \
											if ( mv --version 2>/dev/null | grep -q GNU\  ) ; then \
											mv -Tf \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\"; \
										elif ( which python &> /dev/null ) ; then \
											python -c 'import os; os.rename(\"$REMOTE_PATH/delivered/previous\",\"$REMOTE_PATH/delivered/current\");'; \
										else \
											rm -f	\"$REMOTE_PATH/delivered/current\" && mv \"$REMOTE_PATH/delivered/previous\" \"$REMOTE_PATH/delivered/current\" ; \
										fi ; \
									 else rm -f \"$REMOTE_PATH/delivered/current\"; fi"
			elif [[ $SYMLINK_SWITCH_STATUS = 1 ]]; then
				symlink_rollback="rm -f \"$REMOTE_PATH/delivered/new\""
			fi
			if [[ $SYMLINK_SWITCH_STATUS -lt 3 ]]; then
				symlink_rollback="$symlink_rollback ; rm -f \"$REMOTE_PATH/delivered/previous\"; test -L \"$REMOTE_PATH/delivered/preprevious\" && mv \"$REMOTE_PATH/delivered/preprevious\"	\"$REMOTE_PATH/delivered/previous\""
			fi
			symlink_rollback="$symlink_rollback ; test -L \"$REMOTE_PATH/delivered/prepreprevious\" && mv \"$REMOTE_PATH/delivered/prepreprevious\"	\"$REMOTE_PATH/delivered/preprevious\""

			run_remote "$symlink_rollback"
	fi

	DELIVERY_STAGE="rollback-post-symlink"
	run_stage_scripts "$DELIVERY_STAGE"
	}

function validate_command
	{
	if [[ "$COMMAND" -ne "" ]]; then
		echo_red "Unknown option : $COMMAND"
		exit_with_help
	fi
	COMMAND="$OPTARG"
	}

function validate_option
	{
	if [[ $OPTIND = 2 ]]; then
		echo_red "Unknown command : $OPTARG"
		exit_with_help
	fi
	}

FLAGS_batch=false
FLAGS_force=false
FLAGS_shared="false"
IS_ROLLBACK=false

COMMAND=""
FN=""

optspec=":h-:"
while getopts "$optspec" optchar; do
	case "${optchar}" in
		-)
			case "${OPTARG}" in
				help)
					exit_with_help
					;;
				batch)
					FLAGS_batch=true
					;;
				color)
					USECOLOR=true
					;;
				force)
					FLAGS_force=true
					;;
				nocolor)
					USECOLOR=false
					;;
				shared)
					validate_option
					if [[ "$COMMAND" -ne "--init" ]]; then
						exit_with_error 27 "Uknown option '--shared' for command $COMMAND"
					fi
					FLAGS_shared="false"
					;;
				shared=*)
					validate_option
					if [[ "$COMMAND" -ne "--init" ]]; then
						exit_with_error 27 "Uknown option '--shared' for command $COMMAND"
					fi
					FLAGS_shared=${OPTARG#*=}
					;;
				# COMMANDS
				source)
					validate_command
					return
					;;
				init)
					validate_command
					FN="init"
					;;
				init-remote)
					validate_command
					FN="init_remote"
					;;
				list-presets)
					validate_command
					FN="list_presets"
					;;
				status)
					validate_command
					FN="remote_status"
					;;
				gc)
					validate_command
					FN="remote_gc"
					;;
				rollback)
					validate_command
					IS_ROLLBACK=true
					FN="deliver"
					;;
				*)
					if [[ $OPTIND -gt 1 ]]; then
						echo_red "Unknown option : $OPTARG"
					else
						echo_red "Unknown command : $OPTARG"
					fi
					exit_with_help
					;;
			esac;;
		h)
			exit_with_help
			;;
	esac
done

shift "$((OPTIND - 1))"

if [[ "$FN" = "" ]]; then
	deliver "$@"
else
	$FN "$@"
fi

