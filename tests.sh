#!/bin/bash

SSH_TEST_USER=$USER
SSH_TEST_HOST="localhost"
SSH_TEST_GROUP=git
SSH_TEST_USER_SAME_GROUP=bob
SSH_TEST_USER_NOT_SAME_GROUP=alice
SSH_TEST_PATH="/tmp/deliver test/"

assertTrueEcho()
	{
	$1 || { echo "$1" ; assertTrue false ; }
	}

initDeliver()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --init --batch $* > /dev/null 2>&1 
	}

initWithOrigin()
	{
	cd "$ROOT_DIR"
	git clone --bare "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote" > /dev/null 2>&1
	cd "$ROOT_DIR/test_repo"
	git remote add origin "$ROOT_DIR/test_remote" 
	initDeliver $*
	}

initWithSshOrigin()
	{
	local shared=""
	if [[ $# = 0 ]]; then
		shared="false"
	else
		shared="$1"
	fi
	shift
	cd "$ROOT_DIR/test_repo"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_TEST_PATH\"/test_remote ; mkdir -p \"$SSH_TEST_PATH\"/test_remote && cd \"$SSH_TEST_PATH\"/test_remote && git init --bare --shared=$shared && chgrp -R $SSH_TEST_GROUP \"$SSH_TEST_PATH\"/test_remote"
	git remote add origin "$SSH_TEST_USER@$SSH_TEST_HOST:$SSH_TEST_PATH/test_remote" 
	initDeliver $*
	}

oneTimeSetUp()
	{
	ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	OLD_PWD=`pwd`

	rm -rf "$ROOT_DIR/test_repo"
	rm -rf "$ROOT_DIR/test_remote"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_remote

	mkdir "$ROOT_DIR/test_repo"
	cd "$ROOT_DIR/test_repo"
	git init
	echo "blah blah" > a
	git add a
	git commit -m "test commit"
	git tag older master
	echo "blblublublu" > x
	git add x
	git commit -m "test commit 2"
	git checkout -b "branch"
	echo "ssss" >> a 
	git commit -am "branch commit 1"
	echo "ssss" >> a 
	git commit -am "branch commit 2"
	git checkout master
	echo "ssss" >> a 
	git commit -am "test commit 3"
	git tag branch_non_head branch^
	git tag branch_head branch
	cd "$ROOT_DIR"
	}

oneTimeTearDown()
	{
	rm -rf "$ROOT_DIR/test_repo"
	rm -rf "$ROOT_DIR/test_remote"
	cd "$OLD_PWD"
	}

tearDown()
	{
	rm -rf "$ROOT_DIR/test_repo/.deliver"
	cd "$ROOT_DIR/test_repo"
	git remote rm origin 2> /dev/null

	rm -rf "$ROOT_DIR/test_remote"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_remote
	cd "$ROOT_DIR"
	}

testPath2Unix()
	{
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; path2unix "c:/a/b/c"' | bash`
	assertEquals "/c/a/b/c" "$A"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; path2unix "C:/A/b/C"' | bash`
	assertEquals "/c/A/b/C" "$A"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; path2unix "/C/A/b/C"' | bash`
	assertEquals "/C/A/b/C" "$A"
	}

testExitIfError()
	{
	A=`echo 'source deliver.sh --source; bash -c "exit 2"; exit_if_error 1 "test"' | bash`
	assertEquals 1 $?
	echo "$A" | grep "test" &> /dev/null
	assertEquals 0 $?
	}

testDefaultcolor()
	{
	A=`echo 'source deliver.sh --source; echo_red "test"' | bash`
	echo "$A" | xxd | grep "1b5b 3331 6d" &> /dev/null
	assertNotSame 0 $?
	echo "$A" | xxd | grep "1b5b 306d" &> /dev/null
	assertNotSame 0 $?
	}

testExplicitcolor()
	{
	A=`echo 'source deliver.sh --color --source; echo_red "test"' | bash`
	echo "$A" | xxd | grep "1b5b 3331 6d" &> /dev/null
	assertEquals 0 $?
	echo "$A" | xxd | grep "1b5b 306d" &> /dev/null
	assertEquals 0 $?
	}

testRunRemoteLocal()
	{
	cd "$ROOT_DIR"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_PATH="'$ROOT_DIR'" run_remote "pwd"' | bash`
	assertEquals "/tmp" "$A"
	}

testRunRemoteSsh()
	{
	cd "$ROOT_DIR"
	A=$(echo 'source deliver.sh --source > /dev/null 2>&1 ; GIT_SSH="ssh" REMOTE_SERVER="'$SSH_TEST_USER@$SSH_TEST_HOST'" run_remote "test \"\$SSH_CONNECTION\" = \"\" || echo -n \"OK\""' | bash)
	assertEquals "OK" "$A"
	}

testRemoteInfoNonExistentRemote()
	{
	cd "$ROOT_DIR"/test_repo
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info nonexistentremote 2>&1' | bash`
	assertEquals "Remote nonexistentremote not found." "$A"
	}

testRemoteInfo()
	{
	initWithOrigin
	cd "$ROOT_DIR"/test_repo
	git remote add unix /path/a/b
	git remote add relative ../path/a/b
	git remote add win c:/path/a/b
	git remote add ssh ssh://user@host/path/a/b
	git remote add git GIT://user@host/path/a/b
	git remote add scp user@host:/path/a/b
	git remote add scp_no_user host:/path/a/b
	git remote add http http://user@host/path/a/b
	git remote add space "/path/a b c"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info unix ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	if [[ "$OSTYPE" == "msys" ]]; then
		assertEquals "local++++++`pwd`/path/a/b" "$A"
	else
		assertEquals "local++++++/path/a/b" "$A"
	fi
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info relative ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "local++++++$ROOT_DIR/test_repo/../path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; OSTYPE="linux" remote_info win ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "ssh+++c+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; OSTYPE="msys" remote_info win ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "local++++++/c/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info ssh ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "ssh+++user@host+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info git ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "git+++user@host+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info scp ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "ssh+++user@host+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info scp_no_user ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "ssh+++host+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info http ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "http+++user@host+++/path/a/b" "$A"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info space ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	if [[ "$OSTYPE" == "msys" ]]; then
		assertEquals "local++++++`pwd`/path/a b c" "$A"
	else
		assertEquals "local++++++/path/a b c" "$A"
	fi
	git remote rm unix
	git remote rm relative
	git remote rm win
	git remote rm ssh
	git remote rm git
	git remote rm scp
	git remote rm scp_no_user
	git remote rm http
	git remote rm space
	}

testRunScripts()
	{
	cd "$ROOT_DIR/test_repo"
	mkdir -p ".deliver/scripts/foo"
	echo "test \"\$SSH_CONNECTION\" = \"\" && echo 'L:OK' ; exit 0" > "$ROOT_DIR/test_repo/.deliver/scripts/foo/01-bar.sh"
	echo "test \"\$SSH_CONNECTION\" = \"\" || echo 'R:OK' ; exit 0" > "$ROOT_DIR/test_repo/.deliver/scripts/foo/02-bar.remote.sh"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; GIT_SSH="ssh" REMOTE_SERVER="'$SSH_TEST_USER@$SSH_TEST_HOST'" REMOTE_PROTO="ssh" DELIVERY_STAGE="foo" run_stage_scripts' | bash 2>&1 | grep OK`
	echo "$A" | grep "L:OK" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "R:OK" &> /dev/null
	assertEquals 0 $?
	}

testHelp1()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh | grep "git deliver <REMOTE> <VERSION>" > /dev/null
	assertEquals 0 $?
	}

testListPresets()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`"$ROOT_DIR"/deliver.sh --list-presets`
	echo "$RESULT" | grep "Core git deliver scripts" > /dev/null
	assertEquals 0 $?
	}

testInit()
	{
	initDeliver
	assertTrueEcho "[ -d .deliver ]"
	assertTrueEcho "[ -d .deliver/scripts ]"
	assertTrueEcho "[ -d .deliver/scripts/pre-delivery ]"
	assertTrueEcho "[ -f .deliver/scripts/pre-delivery/01-core-disk-space.sh ]"
	assertTrueEcho "[ -d .deliver/scripts/init-remote ]"
	assertTrueEcho "[ -d .deliver/scripts/post-checkout ]"
	assertTrueEcho "[ -d .deliver/scripts/post-symlink ]"
	assertTrueEcho "[ -d .deliver/scripts/rollback-pre-symlink ]"
	assertTrueEcho "[ -d .deliver/scripts/rollback-post-symlink ]"
	}

testInitPreset()
	{
	initDeliver php
	assertTrueEcho "[ -f .deliver/scripts/pre-delivery/01-php-syntax-check.sh ]"
	}

testInitBadPreset()
	{
	cd "$ROOT_DIR/test_repo"
	A=`"$ROOT_DIR"/deliver.sh --init --batch foo 2>&1`
	assertEquals 19 $? 
	echo "$A" | grep "could not find preset" > /dev/null 2>&1
	assertEquals 0 $?
	}

testUninitedDir()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`"$ROOT_DIR"/deliver.sh --batch non_existent_remote master 2>&1`
	assertEquals ".deliver not found." "$RESULT"
	}

testUnknownRemote()
	{
	initDeliver
	local RESULT=`"$ROOT_DIR"/deliver.sh --batch non_existent_remote master 2>&1`
	assertEquals "Remote non_existent_remote not found." "$RESULT"
	}

testUnknownRef()
	{
	initWithOrigin
	local RESULT=`"$ROOT_DIR"/deliver.sh --batch origin non_existent_ref 2>&1`
	assertEquals "Ref non_existent_ref not found." "$RESULT"
	}

testInitNonExistingRemoteLocal()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote "$ROOT_DIR"/test_new_remote_dir
		cd "$ROOT_DIR"/test_new_remote_dir
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -d refs ]"
		cd "$ROOT_DIR"/test_repo
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote rm new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_TEST_PATH"/test_new_remote_dir
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d \"$SSH_TEST_PATH\"/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote rm new_remote
	}

testInitNonExistingRemoteSsh2()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d \"$SSH_TEST_PATH\"/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote rm new_remote
	}

testInitNonExistingRemoteSsh3()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d \"$SSH_TEST_PATH\"/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote rm new_remote
	}

testInitAlreadyInitRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d \"$SSH_TEST_PATH\"/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	assertEquals 18 $?
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote rm new_remote
	}

testInitNonSshRemote()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	git remote add git git://user@host/path/a/b
	"$ROOT_DIR"/deliver.sh --init-remote --batch git 2>&1 > /dev/null
	assertEquals 17 $?
	}

testInitNonExistingRemoteDirExisting()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		mkdir "$ROOT_DIR/test_new_remote_dir"
		"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_new_remote_dir
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -d refs ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		cd "$ROOT_DIR"/test_repo
		git remote rm new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteDirExistingSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	SSH_NEW_DIR="$SSH_TEST_PATH/test_new_remote_dir"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir \"$SSH_NEW_DIR\""
	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_NEW_DIR\" && test -d delivered && test -d refs"
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_NEW_DIR\""
	git remote rm new_remote
	}

testInitNonExistingRemoteDirFileExisting()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		touch "$ROOT_DIR/test_new_remote_dir"
		"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote "$ROOT_DIR"/test_new_remote_dir
		assertEquals 10 $?
		assertFalse "[ -d \"$ROOT_DIR\"/test_new_remote_dir/delivered ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote rm new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteDirFileExistingSsh()
	{
	initDeliver

	SSH_NEW_DIR="$SSH_TEST_PATH/test_new_remote_dir"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "touch \"$SSH_NEW_DIR\""

	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "test -d \"$SSH_NEW_DIR/delivered\""
	assertEquals 1 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -f \"$SSH_NEW_DIR\""
	git remote rm new_remote
	}

testInitNonExistingRemoteDirExistingNonEmpty()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		mkdir "$ROOT_DIR/test_new_remote_dir"
		touch "$ROOT_DIR/test_new_remote_dir/file1"
		"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
		assertEquals 9 $?
		assertFalse "[ -d \"$ROOT_DIR\"/test_new_remote_dir/delivered ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote rm new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteDirExistingNonEmptySsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo

	SSH_NEW_DIR="$SSH_TEST_PATH/test_new_remote_dir"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir \"$SSH_NEW_DIR\" && touch \"$SSH_NEW_DIR/file1\""


	"$ROOT_DIR"/deliver.sh --init-remote --batch new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null
	assertEquals 9 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "test -d \"$SSH_NEW_DIR/delivered\""
	assertEquals 1 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_NEW_DIR\""
	git remote rm new_remote
	}

testDeliverNonSshRemote()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	git remote add git git://user@host/path/a/b
	"$ROOT_DIR"/deliver.sh --batch git master 2>&1 > /dev/null
	assertEquals 17 $?
	}

testDeliverInvalidRemoteName()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch +++ master 2>&1 > /dev/null
	assertEquals 22 $?
	}

testBasicDeliverMaster()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
		echo "$A"
		echo "$A" | grep "No version delivered yet on origin" &> /dev/null
		assertEquals 0 $?
		echo "$A" | grep "Running scripts for stage pre-delivery" &> /dev/null
		assertEquals 0 $?
		echo "$A" | grep "No scripts for stage post-checkout" &> /dev/null
		assertEquals 0 $?
		echo "$A" | grep "No scripts for stage post-symlink" &> /dev/null
		assertEquals 0 $?
		echo "$A" | grep "No scripts for stage rollback-pre-symlink" &> /dev/null
		assertNotSame 0 $?
		echo "$A" | grep "No scripts for stage rollback-post-symlink" &> /dev/null
		assertNotSame 0 $?
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink \"$ROOT_DIR\"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse master` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testDeliverNotFastForwardSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin &> /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master &> /dev/null
	git reset master^
	echo "asdsdf" >> a
	git commit -am "new master"
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	assertEquals 14 $?
	echo "$A" | grep "failed to push"
	assertEquals 0 $?
	}

testBasicDeliverMasterSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	echo "$A"
	echo "$A" | grep "No version delivered yet on origin" > /dev/null
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH/test_remote\" && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse master` $SSH_SHA1;
	}

testDeliverMasterSshBadSubmodule()
	{
	initWithSshOrigin
	MASTER=`git rev-parse master`
	git submodule add "$ROOT_DIR"/.git badsub
	sed -i 's/url\s*=.*$/url = \/sdfswds/' .gitmodules
	git commit -am "Submodule with bad URL"
	
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	assertEquals 7 $?

	git config -f .git/config --remove-section submodule.badsub
	git config -f .gitmodules --remove-section submodule.badsub
	rm -rf badsub
	rm -rf .git/modules/badsub

	git reset --hard $MASTER
	}

testDeliverMasterSshDeliveredNotWritable()
	{
	initWithSshOrigin

	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "chmod -w \"$SSH_TEST_PATH\"/test_remote/delivered/"`
	
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	assertEquals 5 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "chmod +w \"$SSH_TEST_PATH\"/test_remote/delivered/"`
	}

testBasicDeliverNonHeadSha1OnMaster()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse master^` 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse master^` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadSha1OnMasterSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse master^` 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse master^` $SSH_SHA1;
	}

testBasicDeliverNonHeadTag()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin older 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse older` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadTagSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin older 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse older` $SSH_SHA1;
	}

testBasicDeliverNonMasterBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin branch 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonMasterBranchSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin branch 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse branch` $SSH_SHA1;
	}

testBasicDeliverNonHeadSha1OtherBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse branch^` 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ delivered ]"
		assertTrueEcho "[ delivered/current ]"
		assertTrueEcho "[ delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch^` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadSha1OtherBranchSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse branch^` 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	assertEquals `git rev-parse branch^` "$SSH_SHA1";

	}

testBasicDeliverNonHeadTagOtherBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin branch_non_head 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ delivered ]"
		assertTrueEcho "[ delivered/current ]"
		assertTrueEcho "[ delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch_non_head` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadTagOtherBranch()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin branch_non_head 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`

	assertEquals `git rev-parse branch_non_head` "$SSH_SHA1";
	}

testBasicDeliverStatus()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
		STATUS=`"$ROOT_DIR"/deliver.sh --status origin 2>&1 | head -n +2 | tail -n 1`
		assertEquals `git rev-parse master` "${STATUS:3:43}"
	else
		echo "Test won't be run (msys)"
	fi
	}

testStatusModifiedOrNot()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
	STATUS=`"$ROOT_DIR"/deliver.sh --status origin`
	echo "$STATUS" | grep "With uncomitted changes" > /dev/null
	assertEquals 1 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "echo 'new_line' >> \"$SSH_TEST_PATH\"/test_remote/delivered/current/a"
	STATUS=`"$ROOT_DIR"/deliver.sh --status origin`
	echo "$STATUS" | grep "With uncomitted changes" > /dev/null
	assertEquals 1 $?
	}

testBasicDeliverStatusSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --init-remote --batch origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
	STATUS=`"$ROOT_DIR"/deliver.sh --status origin | head -n +2 | tail -n 1`
	assertEquals `git rev-parse master` "${STATUS:3:43}"
	}

testStatusNonSshRemote()
	{
	initDeliver
	git remote add git git://user@host/path/a/b
	STATUS=`"$ROOT_DIR"/deliver.sh --status git`
	assertEquals "Not a Git-deliver remote" "$STATUS"
	}

testStatusNonGit()
	{
	initWithSshOrigin
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir -p \"$SSH_TEST_PATH\"/test_remote/delivered && cd \"$SSH_TEST_PATH\"/test_remote/delivered && rm -rf * && mkdir a && ln -s a current"
	local status=`"$ROOT_DIR"/deliver.sh --status origin`
	local expected=`echo -e "current (a)\n   Unknown"`
	assertEquals "$expected" "$status"
	}

testLocalGC()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		cd "$ROOT_DIR"/test_repo
		rm -rf "$ROOT_DIR"/test_remote/delivered/*
		mkdir -p "$ROOT_DIR"/test_remote/delivered/a
		echo "ABCDEFG" >> "$ROOT_DIR"/test_remote/delivered/a/f
		echo "ABCDEFG" >> "$ROOT_DIR"/test_remote/delivered/a/g
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/b
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/c
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/d
		ln -s "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/current
		ln -s "$ROOT_DIR"/test_remote/delivered/b "$ROOT_DIR"/test_remote/delivered/previous
		ln -s "$ROOT_DIR"/test_remote/delivered/c "$ROOT_DIR"/test_remote/delivered/preprevious
		GC=`"$ROOT_DIR"/deliver.sh --gc --batch origin`
		echo "$GC" | grep "1 version(s) removed" > /dev/null
		assertEquals 0 $?
		echo "GC: $GC"
		cd "$ROOT_DIR"/test_remote/delivered
		assertTrueEcho "[ -d a ]"
		assertTrueEcho "[ -d b ]"
		assertTrueEcho "[ -d c ]"
		assertTrueEcho "[ ! -d d ]"
		cd "$ROOT_DIR"/test_repo
		GC=`"$ROOT_DIR"/deliver.sh --gc --batch origin`
		echo "$GC" | grep "0 version(s) removed" > /dev/null
		assertEquals 0 $?
		echo "$GC" | grep '0 B freed' > /dev/null
		assertEquals 0 $?
		echo "GC: $GC"
		cd "$ROOT_DIR"/test_remote/delivered
		assertTrueEcho "[ -d a ]"
		assertTrueEcho "[ -d b ]"
		assertTrueEcho "[ -d c ]"
		assertTrueEcho "[ ! -d d ]"
	else
		echo "Test won't be run (msys)"
	fi
	}

testSshGC()
	{
	initWithSshOrigin
	cd "$ROOT_DIR"/test_repo
	
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir -p \"$SSH_TEST_PATH\"/test_remote/delivered && cd \"$SSH_TEST_PATH\"/test_remote/delivered && rm -rf * && mkdir a && echo \"ABCDEFG\" >> a/f && echo \"ABCDEFG\" >> a/g && cp -r a b && cp -r a c && cp -r a d && ln -s a current && ln -s b previous && ln -s c preprevious"

	GC=`"$ROOT_DIR"/deliver.sh --gc --batch origin`
	echo "$GC" | grep "1 version(s) removed" > /dev/null
	assertEquals 0 $?
	echo "GC: $GC"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test -d a && test -d b && test -d c && test ! -d d"
	assertEquals 0 $?

	GC=`"$ROOT_DIR"/deliver.sh --gc --batch origin`
	echo "$GC" | grep "0 version(s) removed" > /dev/null
	assertEquals 0 $?
	echo "$GC" | grep '0 B freed' > /dev/null
	assertEquals 0 $?
	echo "GC: $GC"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test -d a && test -d b && test -d c && test ! -d d"
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_TEST_PATH\"/test_remote"
	}

testRollbackPreDeliverySsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 1" > "$ROOT_DIR/test_repo/.deliver/scripts/pre-delivery/00-fail.sh"
	echo "echo \"PRE_FAILED_SCRIPT:\$FAILED_SCRIPT\"" > "$ROOT_DIR/test_repo/.deliver/scripts/rollback-pre-symlink/00-info.sh"
	echo "echo \"PRE_FAILED_SCRIPT_EXIT_STATUS:\$FAILED_SCRIPT_EXIT_STATUS\"" >> "$ROOT_DIR/test_repo/.deliver/scripts/rollback-pre-symlink/00-info.sh"
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	echo "$A"
	echo "$A" | grep "Script returned with status 1" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "PRE_FAILED_SCRIPT:00-fail" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "PRE_FAILED_SCRIPT_EXIT_STATUS:1" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage rollback-post-symlink" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage post-checkout" &> /dev/null
	assertNotSame 0 $?
	echo "$A" | grep "Rolling back" &> /dev/null
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "test ! -e \"$SSH_TEST_PATH\"/test_remote/delivered/current"
	assertEquals 0 $?
	}

testRollbackPostCheckoutSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 22" > "$ROOT_DIR/test_repo/.deliver/scripts/post-checkout/00-fail.sh"
	echo "echo \"POST_FAILED_SCRIPT:\$FAILED_SCRIPT\"" > "$ROOT_DIR/test_repo/.deliver/scripts/rollback-post-symlink/00-info.sh"
	echo "echo \"POST_FAILED_SCRIPT_EXIT_STATUS:\$FAILED_SCRIPT_EXIT_STATUS\"" >> "$ROOT_DIR/test_repo/.deliver/scripts/rollback-post-symlink/00-info.sh"
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	echo "$A" | grep "Script returned with status 22" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "POST_FAILED_SCRIPT:00-fail" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "POST_FAILED_SCRIPT_EXIT_STATUS:22" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage rollback-pre-symlink" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "Running scripts for stage post-checkout" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage post-symlink" &> /dev/null
	assertNotSame 0 $?
	echo "$A" | grep "Rolling back" &> /dev/null
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test ! -e current"
	assertEquals 0 $?
	}

testRollbackPostSymlinkNoPreviousSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 22" > "$ROOT_DIR/test_repo/.deliver/scripts/post-symlink/00-fail.sh"
	echo "echo \"POST_FAILED_SCRIPT:\$FAILED_SCRIPT\"" > "$ROOT_DIR/test_repo/.deliver/scripts/rollback-post-symlink/00-info.sh"
	echo "echo \"POST_FAILED_SCRIPT_EXIT_STATUS:\$FAILED_SCRIPT_EXIT_STATUS\"" >> "$ROOT_DIR/test_repo/.deliver/scripts/rollback-post-symlink/00-info.sh"
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	echo "$A"
	echo "$A" | grep "Script returned with status 22" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "POST_FAILED_SCRIPT:00-fail" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "POST_FAILED_SCRIPT_EXIT_STATUS:22" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage rollback-pre-symlink" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "No scripts for stage post-checkout" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "Running scripts for stage post-symlink" &> /dev/null
	assertEquals 0 $?
	echo "$A" | grep "Rolling back" &> /dev/null
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test ! -e current"
	assertEquals 0 $?
	}

testRollbackPostSymlinkWithPreviousSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 22" > "$ROOT_DIR/test_repo/.deliver/scripts/post-symlink/00-fail.sh"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir -p \"$SSH_TEST_PATH\"/test_remote/delivered/a && ln -s \"$SSH_TEST_PATH\"/test_remote/delivered/a \"$SSH_TEST_PATH\"/test_remote/delivered/current && touch \"$SSH_TEST_PATH\"/test_remote/delivered/a/f"

	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test -e current/f && test ! -e previous"
	assertEquals 0 $?
	}

testRollbackPostSymlinkWith2PreviousSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 22" > "$ROOT_DIR/test_repo/.deliver/scripts/post-symlink/00-fail.sh"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "bash" <<-EOS
		mkdir -p "$SSH_TEST_PATH/test_remote/delivered/a"
		ln -s "$SSH_TEST_PATH/test_remote/delivered/a" "$SSH_TEST_PATH/test_remote/delivered/current"
		touch "$SSH_TEST_PATH/test_remote/delivered/a/f"
		mkdir -p "$SSH_TEST_PATH/test_remote/delivered/b"
		ln -s "$SSH_TEST_PATH/test_remote/delivered/b" "$SSH_TEST_PATH/test_remote/delivered/previous"
		touch "$SSH_TEST_PATH/test_remote/delivered/b/g"
	EOS

	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "bash" <<-EOS
		cd "$SSH_TEST_PATH"/test_remote/
		test -e delivered/current/f && \
		test -e delivered/previous/g && \
		test ! -e delivered/preprevious
	EOS

	assertEquals 0 $?
	}

testRollbackPostSymlinkWith3PreviousSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	echo "exit 22" > "$ROOT_DIR/test_repo/.deliver/scripts/post-symlink/00-fail.sh"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "bash" <<-EOS
		mkdir -p "$SSH_TEST_PATH/test_remote/delivered/a"
		ln -s "$SSH_TEST_PATH/test_remote/delivered/a" "$SSH_TEST_PATH/test_remote/delivered/current"
		touch "$SSH_TEST_PATH/test_remote/delivered/a/f"
		mkdir -p "$SSH_TEST_PATH/test_remote/delivered/b"
		ln -s "$SSH_TEST_PATH/test_remote/delivered/b" "$SSH_TEST_PATH/test_remote/delivered/previous"
		touch "$SSH_TEST_PATH/test_remote/delivered/b/g"
		mkdir -p "$SSH_TEST_PATH/test_remote/delivered/c"
		ln -s "$SSH_TEST_PATH/test_remote/delivered/c" "$SSH_TEST_PATH/test_remote/delivered/preprevious"
		touch "$SSH_TEST_PATH/test_remote/delivered/c/h"
	EOS

	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "bash" <<-EOS
		cd "$SSH_TEST_PATH"/test_remote/
		test -e delivered/current/f && \
		test -e delivered/previous/g && \
		test -e delivered/preprevious/h && \
		test ! -e delivered/prepreprevious
	EOS
	assertEquals 0 $?
	}

testFullRollbackNoRemoteSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --rollback &> /dev/null
	assertEquals 1 $?
	}

testFullRollbackNoPreviousSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --rollback --batch origin
	assertEquals 24 $?
	"$ROOT_DIR"/deliver.sh --batch origin master
	"$ROOT_DIR"/deliver.sh --rollback --batch origin
	assertEquals 25 $?
	}

testFullRollbackSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --batch origin master^

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^` "$SSH_SHA1";

	"$ROOT_DIR"/deliver.sh --batch origin master

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master` "$SSH_SHA1";

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/previous/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^` "$SSH_SHA1";

	"$ROOT_DIR"/deliver.sh --rollback --batch origin

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^` "$SSH_SHA1";

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/previous/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master` "$SSH_SHA1";
	}

testFullRollbackNonExistentVersionSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --rollback --batch origin foo
	assertEquals 24 $?
	"$ROOT_DIR"/deliver.sh --batch origin master
	"$ROOT_DIR"/deliver.sh --rollback --batch origin foo
	assertEquals 25 $?
	}

testFullRollbackVersionSsh()
	{
	initWithSshOrigin
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --batch origin master^^
	local ROLLBACK_TO=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered/current && pwd -P"`
	ROLLBACK_TO=`basename "$ROLLBACK_TO"`

	"$ROOT_DIR"/deliver.sh --batch origin master^
	"$ROOT_DIR"/deliver.sh --batch origin master

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master` "$SSH_SHA1";

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/previous/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^` "$SSH_SHA1";

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/preprevious/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^^` "$SSH_SHA1";

	"$ROOT_DIR"/deliver.sh --rollback --batch origin "$ROLLBACK_TO"

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master^^` "$SSH_SHA1";

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/previous/.git log -n 1 --skip=1 --pretty=format:%H"`
	assertEquals `git rev-parse master` "$SSH_SHA1";
	}

testGroupPermissionsNotShared()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch origin master
	assertEquals 0 $?
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "stat -c %A $SSH_TEST_GROUP \"$SSH_TEST_PATH\"/test_remote" | cut -c 6 | grep 'w'
	assertEquals 1 $?
	}

testGroupPermissions()
	{
	initWithSshOrigin "group"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "chgrp $SSH_TEST_GROUP \"$SSH_TEST_PATH\"/test_remote"
	cd "$ROOT_DIR/test_repo"
	git remote add origin_same_group "$SSH_TEST_USER_SAME_GROUP@$SSH_TEST_HOST:$SSH_TEST_PATH/test_remote"
	git remote add origin_not_same_group "$SSH_TEST_USER_NOT_SAME_GROUP@$SSH_TEST_HOST:$SSH_TEST_PATH/test_remote"
	"$ROOT_DIR"/deliver.sh --batch origin master
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin master
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin master
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin_same_group master
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin_not_same_group master
	assertEquals 5 $?
	GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin_not_same_group`
	assertEquals 27 $?
	echo "$GC"
	echo "$GC" | grep "0 version(s) removed" > /dev/null
	assertEquals 0 $?
	GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin_same_group`
	assertEquals 0 $?
	echo "$GC"
	echo "$GC" | grep "1 version(s) removed" > /dev/null
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin master
	assertEquals 0 $?
	"$ROOT_DIR"/deliver.sh --batch origin_same_group master
	assertEquals 0 $?
	GC=`"$ROOT_DIR"/deliver.sh --gc origin`
	assertEquals 0 $?
	echo "$GC"
	echo "$GC" | grep "2 version(s) removed" > /dev/null
	assertEquals 0 $?
	}

. lib/shunit2
