#!/bin/bash

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
	cd "$ROOT_DIR"
	git clone --bare "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote"  > /dev/null 2>&1
	cd "$ROOT_DIR/test_repo"
	git remote add origin "arno@localhost:$ROOT_DIR/test_remote" 
	initDeliver $*
	}

oneTimeSetUp()
	{
	ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	OLD_PWD=`pwd`

	mkdir "$ROOT_DIR/test_repo"
	cd "$ROOT_DIR/test_repo"
	git init
	echo "blah blah" > a
	git add a
	git commit -m "test commit"
	echo "blblublublu" > x
	git add x
	git commit -m "test commit 2"
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
	cd "$ROOT_DIR"
	}

testRunRemoteLocal()
	{
	cd "$ROOT_DIR"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_PATH="'$ROOT_DIR'" run_remote "ls deliver.sh"' | bash`
	assertEquals "deliver.sh" "$A"
	}

testRunRemoteSsh()
	{
	cd "$ROOT_DIR"
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_SERVER="localhost" run_remote ls "'$ROOT_DIR'/deliver.sh"' | bash`
	assertEquals "$ROOT_DIR/deliver.sh" "$A"
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
	git remote add ssh ssh://user@host/path/a/b
	git remote add git GIT://user@host/path/a/b
	git remote add scp user@host:/path/a/b
	git remote add scp_no_user host:/path/a/b
	git remote add http http://user@host/path/a/b
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info origin ; echo "$REMOTE_PROTO+++$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "local++++++$ROOT_DIR/test_remote" "$A"
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
	}

testHelp1()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh | grep "git deliver <REMOTE> <VERSION>" > /dev/null
	assertEquals 0 $?
	}

testListPresets()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`$ROOT_DIR/deliver.sh --list-presets`
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
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonExistingRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote localhost:"$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonExistingRemoteSsh2()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote `whoami`@localhost:"$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	git remote remove new_remote
	}

testInitNonExistingRemoteSsh3()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://`whoami`@localhost"$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	git remote remove new_remote
	}

testInitAlreadyInitRemoteSsh()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://`whoami`@localhost"$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote sSh://`whoami`@localhost"$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertEquals 18 $?
	rm -rf "$ROOT_DIR"/test_new_remote_dir
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
	initDeliver
	cd "$ROOT_DIR"/test_repo
	mkdir "$ROOT_DIR/test_new_remote_dir"
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_new_remote_dir/refs ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	}

testInitNonExistingRemoteDirFileExisting()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	touch "$ROOT_DIR/test_new_remote_dir"
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertEquals 10 $?
	assertFalse "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	}

testInitNonExistingRemoteDirExistingNonEmpty()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	mkdir "$ROOT_DIR/test_new_remote_dir"
	touch "$ROOT_DIR/test_new_remote_dir/file1"
	"$ROOT_DIR"/deliver.sh --batch --init-remote new_remote "$ROOT_DIR"/test_new_remote_dir 2>&1 > /dev/null
	assertEquals 9 $?
	assertFalse "[ -d $ROOT_DIR/test_new_remote_dir/delivered ]"
	rm -rf "$ROOT_DIR"/test_new_remote_dir
	}

testDeliverNonSshRemote()
	{
	initDeliver
	cd "$ROOT_DIR"/test_repo
	git remote add git git://user@host/path/a/b
	"$ROOT_DIR"/deliver.sh --batch git master 2>&1 > /dev/null
	assertEquals 17 $?
	}

testBasicDeliverMaster()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse master` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverNonHeadSha1()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse master^` 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse master^` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverNonHeadTag()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	git tag foo master^
	"$ROOT_DIR"/deliver.sh --batch origin foo 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse master^` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverNonMasterBranch()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	git checkout -b "mybranch"
	echo "ssss" >> a 
	git commit -am "modif"
	"$ROOT_DIR"/deliver.sh --batch origin mybranch 2>&1 > /dev/null
	git checkout master
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse mybranch` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverNonHeadSha1OtherBranch()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	git checkout "mybranch"
	echo "ssss" >> a 
	git commit -am "modif2"
	"$ROOT_DIR"/deliver.sh --batch origin `git rev-parse mybranch^` 2>&1 > /dev/null
	git checkout master
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse mybranch^` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverNonHeadTagOtherBranch()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	git tag foobranch mybranch^
	"$ROOT_DIR"/deliver.sh --batch origin foobranch 2>&1 > /dev/null
	git checkout master
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	assertEquals `git rev-parse mybranch^` `git --git-dir=$ROOT_DIR/test_remote/delivered/current/.git log -n 1 --skip 1 --pretty=format:%H`;
	}

testBasicDeliverStatus()
	{
	initWithOrigin
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

testSshDeliver1()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	"$ROOT_DIR"/deliver.sh --batch origin master 2>&1 > /dev/null
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	}

testSshDeliverTag()
	{
	initWithSshOrigin
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch --init-remote origin > /dev/null
	echo "AAA" > new_file
	git add new_file
	git commit -m "new commit"
	git tag blah
	cd "$ROOT_DIR"/test_repo
	"$ROOT_DIR"/deliver.sh --batch origin blah 2>&1 > /dev/null
	assertTrueEcho "[ -f $ROOT_DIR/test_remote/delivered/current/new_file ]"
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
