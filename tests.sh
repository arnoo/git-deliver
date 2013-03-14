#!/bin/bash

SSH_TEST_USER="arno"
SSH_TEST_HOST="localhost"
SSH_TEST_PATH="/tmp"

assertTrueEcho()
	{
	$1 || { echo "$1" ; assertTrue false ; }
	}

initDeliver()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --batch --init $* > /dev/null 2>&1 
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
	cd "$ROOT_DIR/test_repo"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir -p \"$SSH_TEST_PATH\"/test_remote && cd \"$SSH_TEST_PATH\"/test_remote && git init --bare"
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
	git remote remove origin 2> /dev/null
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

testRunRemoteLocal()
	{
	cd "$ROOT_DIR"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_PATH="'$ROOT_DIR'" run_remote "pwd"' | bash`
	assertEquals "/tmp" "$A"
	}

testRunRemoteSsh()
	{
	cd "$ROOT_DIR"
	A=$(echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_SERVER="'$SSH_TEST_USER@$SSH_TEST_HOST'" run_remote "test \"\$SSH_CONNECTION\" = \"\" || echo -n \"OK\""' | bash)
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
	git remote remove unix
	git remote remove relative
	git remote remove win
	git remote remove ssh
	git remote remove git
	git remote remove scp
	git remote remove scp_no_user
	git remote remove http
	git remote remove space
	}

testRunScripts()
	{
	cd "$ROOT_DIR/test_repo"
	mkdir -p ".deliver/scripts/foo"
	echo "echo -n 'L:' ; test \"\$SSH_CONNECTION\" = \"\" && echo -n 'OK' ; exit 0" > "$ROOT_DIR/test_repo/.deliver/scripts/foo/01-bar.sh"
	echo "echo -n ',R:' ; test \"\$SSH_CONNECTION\" = \"\" || echo -n 'OK' ; exit 0" > "$ROOT_DIR/test_repo/.deliver/scripts/foo/02-bar.remote.sh"
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; REMOTE_SERVER="'$SSH_TEST_USER@$SSH_TEST_HOST'" REMOTE_PROTO="ssh" run_scripts foo' | bash`
	assertEquals "L:OK,R:OK" "$A"
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
	assertTrueEcho "[ -f .deliver/scripts/pre-delivery/01-core-mem-free.sh ]"
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
	A=`"$ROOT_DIR"/deliver.sh --batch --init foo 2>&1`
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
		"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir
		cd "$ROOT_DIR"/test_new_remote_dir
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -d refs ]"
		cd "$ROOT_DIR"/test_repo
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote remove new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_TEST_PATH"/test_new_remote_dir
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d "$SSH_TEST_PATH"/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonExistingRemoteSsh2()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d $SSH_TEST_PATH/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonExistingRemoteSsh3()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d $SSH_TEST_PATH/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote remove new_remote
	}

testInitAlreadyInitRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	A=`ssh $SSH_TEST_USER@$SSH_TEST_HOST ls -1d $SSH_TEST_PATH/{test_new_remote_dir,test_new_remote_dir/delivered,test_new_remote_dir/refs} | wc -l`
	assertEquals 3 $A
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://$SSH_TEST_USER@$SSH_TEST_HOST"$SSH_TEST_PATH"/test_new_remote_dir 2>&1 > /dev/null
	assertEquals 18 $?
	ssh $SSH_TEST_USER@$SSH_TEST_HOST rm -rf "$SSH_TEST_PATH"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonSshRemote()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	git remote add git git://user@host/path/a/b
	"$ROOT_DIR"/deliver.sh --batch --init-remote git 2>&1 > /dev/null
	assertEquals 17 $?
	}

testInitNonExistingRemoteDirExisting()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		mkdir "$ROOT_DIR/test_new_remote_dir"
		"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_new_remote_dir
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -d refs ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		cd "$ROOT_DIR"/test_repo
		git remote remove new_remote
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
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_NEW_DIR\" && test -d delivered && test -d refs"
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_NEW_DIR\""
	git remote remove new_remote
	}

testInitNonExistingRemoteDirFileExisting()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		touch "$ROOT_DIR/test_new_remote_dir"
		"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir
		assertEquals 10 $?
		assertFalse "[ -d \"$ROOT_DIR\"/test_new_remote_dir/delivered ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote remove new_remote
	else
		echo "Test won't be run (msys)"
	fi
	}

testInitNonExistingRemoteDirFileExistingSsh()
	{
	initDeliver

	SSH_NEW_DIR="$SSH_TEST_PATH/test_new_remote_dir"
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "touch \"$SSH_NEW_DIR\""

	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "test -d \"$SSH_NEW_DIR/delivered\""
	assertEquals 1 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -f \"$SSH_NEW_DIR\""
	git remote remove new_remote
	}

testInitNonExistingRemoteDirExistingNonEmpty()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initDeliver
		cd "$ROOT_DIR"/test_repo
		mkdir "$ROOT_DIR/test_new_remote_dir"
		touch "$ROOT_DIR/test_new_remote_dir/file1"
		"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
		assertEquals 9 $?
		assertFalse "[ -d \"$ROOT_DIR\"/test_new_remote_dir/delivered ]"
		rm -rf "$ROOT_DIR"/test_new_remote_dir
		git remote remove new_remote
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


	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote $SSH_TEST_USER@$SSH_TEST_HOST:"$SSH_NEW_DIR" 2>&1 > /dev/null
	assertEquals 9 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "test -d \"$SSH_NEW_DIR/delivered\""
	assertEquals 1 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_NEW_DIR\""
	git remote remove new_remote
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
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
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
		assertEquals `git rev-parse master` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverMasterSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	A=`"$ROOT_DIR"/deliver.sh --batch origin master 2>&1`
	echo "$A"
	echo "$A" | grep "No version delivered yet on origin" > /dev/null
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH/test_remote\" && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse master` $SSH_SHA1;
	}

testBasicDeliverNonHeadSha1OnMaster()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse master^` 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse master^` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadSha1OnMasterSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse master^` 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse master^` $SSH_SHA1;
	}

testBasicDeliverNonHeadTag()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin older 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse older` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadTagSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin older 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse older` $SSH_SHA1;
	}

testBasicDeliverNonMasterBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin branch 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ -d delivered ]"
		assertTrueEcho "[ -L delivered/current ]"
		assertTrueEcho "[ -d delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonMasterBranchSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin branch 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	cd "$ROOT_DIR"/test_repo
	assertEquals `git rev-parse branch` $SSH_SHA1;
	}

testBasicDeliverNonHeadSha1OtherBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse branch^` 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ delivered ]"
		assertTrueEcho "[ delivered/current ]"
		assertTrueEcho "[ delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch^` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadSha1OtherBranchSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse branch^` 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	assertEquals `git rev-parse branch^` "$SSH_SHA1";

	}

testBasicDeliverNonHeadTagOtherBranch()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin branch_non_head 2>&1 > /dev/null
		cd "$ROOT_DIR"/test_remote
		assertEquals 0 $?
		assertTrueEcho "[ delivered ]"
		assertTrueEcho "[ delivered/current ]"
		assertTrueEcho "[ delivered/`readlink "$ROOT_DIR"/test_remote/delivered/current` ]"
		cd "$ROOT_DIR"/test_repo
		assertEquals `git rev-parse branch_non_head` `git --git-dir="$ROOT_DIR"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverNonHeadTagOtherBranch()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin branch_non_head 2>&1 > /dev/null

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote && test -d delivered && test -L delivered/current && test -d delivered/\`readlink \"$SSH_TEST_PATH\"/test_remote/delivered/current\`"
	assertEquals 0 $?

	SSH_SHA1=`ssh $SSH_TEST_USER@$SSH_TEST_HOST "git --git-dir=\"$SSH_TEST_PATH\"/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H"`

	assertEquals `git rev-parse branch_non_head` "$SSH_SHA1";
	}

testBasicDeliverStatus()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
		"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
		STATUS=`"$ROOT_DIR"/deliver.sh --status origin`
		assertEquals `git rev-parse master` ${STATUS:0:40} 
	else
		echo "Test won't be run (msys)"
	fi
	}

testBasicDeliverStatusSsh()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
	STATUS=`"$ROOT_DIR"/deliver.sh --status origin`
	assertEquals `git rev-parse master` ${STATUS:0:40} 
	}

testStatusNonSshRemote()
	{
	initDeliver
	git remote add git git://user@host/path/a/b
	STATUS=`"$ROOT_DIR"/deliver.sh --status git`
	assertEquals "Not a Git-deliver remote" "$STATUS"
	}

testLocalGC()
	{
	if [[ "$OSTYPE" != "msys" ]]; then
		initWithOrigin
		cd "$ROOT_DIR"/test_repo
		rm -rf "$ROOT_DIR"/test_remote/delivered/*
		mkdir -p "$ROOT_DIR"/test_remote/delivered/a
		echo "ABCDEFG" >> "$ROOT_DIR"/test_remote/delivered/a/f
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/b
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/c
		cp -r "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/d
		ln -s "$ROOT_DIR"/test_remote/delivered/a "$ROOT_DIR"/test_remote/delivered/current
		ln -s "$ROOT_DIR"/test_remote/delivered/b "$ROOT_DIR"/test_remote/delivered/previous
		ln -s "$ROOT_DIR"/test_remote/delivered/c "$ROOT_DIR"/test_remote/delivered/preprevious
		GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin`
		echo "$GC" | grep "1 version(s) removed" > /dev/null
		assertEquals 0 $?
		echo "GC: $GC"
		cd "$ROOT_DIR"/test_remote/delivered
		assertTrueEcho "[ -d a ]"
		assertTrueEcho "[ -d b ]"
		assertTrueEcho "[ -d c ]"
		assertTrueEcho "[ ! -d d ]"
		cd "$ROOT_DIR"/test_repo
		GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin`
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
	
	ssh $SSH_TEST_USER@$SSH_TEST_HOST "mkdir -p \"$SSH_TEST_PATH\"/test_remote/delivered && cd \"$SSH_TEST_PATH\"/test_remote/delivered && rm -rf * && mkdir a && echo \"ABCDEFG\" >> a/f && cp -r a b && cp -r a c && cp -r a d && ln -s a current && ln -s b previous && ln -s c preprevious"

	GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin`
	echo "$GC" | grep "1 version(s) removed" > /dev/null
	assertEquals 0 $?
	echo "GC: $GC"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test -d a && test -d b && test -d c && test ! -d d"
	assertEquals 0 $?

	GC=`"$ROOT_DIR"/deliver.sh --batch --gc origin`
	echo "$GC" | grep "0 version(s) removed" > /dev/null
	assertEquals 0 $?
	echo "$GC" | grep '0 B freed' > /dev/null
	assertEquals 0 $?
	echo "GC: $GC"

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "cd \"$SSH_TEST_PATH\"/test_remote/delivered && test -d a && test -d b && test -d c && test ! -d d"
	assertEquals 0 $?

	ssh $SSH_TEST_USER@$SSH_TEST_HOST "rm -rf \"$SSH_TEST_PATH\"/test_remote"
	}
	
#test3DeliveriesSameVersion()
#	{
#	initWithOrigin
#	"$ROOT_DIR"/deliver.sh --batch origin master 
#	"$ROOT_DIR"/deliver.sh --batch origin master 
#	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/current ]"
#	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/previous ]"
#	assertFalse "[ -L \"$ROOT_DIR\"/test_remote/delivered/preprevious ]"
#	"$ROOT_DIR"/deliver.sh --batch origin master 
#	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/current ]"
#	assertTrueEcho "[ -d \""`readlink "$ROOT_DIR"/test_remote/delivered/current`"\" ]"
#	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/previous ]"
#	assertTrueEcho "[ -d \""`readlink "$ROOT_DIR"/test_remote/delivered/previous`"\" ]"
#	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/preprevious ]"
#	assertTrueEcho "[ -d \""`readlink "$ROOT_DIR"/test_remote/delivered/preprevious`"\" ]"
#
#	assertNotEquals "`readlink \"$ROOT_DIR\"/test_remote/current`" "`readlink \"$ROOT_DIR\"/test_remote/previous`"
#	assertNotEquals "`readlink \"$ROOT_DIR\"/test_remote/previous`" "`readlink \"$ROOT_DIR\"/test_remote/preprevious`"
#	assertNotEquals "`readlink \"$ROOT_DIR\"/test_remote/current`" "`readlink \"$ROOT_DIR\"/test_remote/preprevious`"
#	}
	
. lib/shunit2
