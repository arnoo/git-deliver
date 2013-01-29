#!/bin/bash

assertTrueEcho()
	{
	$1 || ( echo "$1" && assertTrue false )
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
	git remote add origin "localhost:$ROOT_DIR/test_remote" 
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
	cd $ROOT_DIR
	}

oneTimeTearDown()
	{
	rm -rf "$ROOT_DIR/test_repo"
	rm -rf "$ROOT_DIR/test_remote"
	cd $OLD_PWD
	}

tearDown()
	{
	rm -rf "$ROOT_DIR/test_repo/.deliver"
	cd "$ROOT_DIR/test_repo"
	git remote remove origin 2> /dev/null
	rm -rf "$ROOT_DIR/test_remote"
	cd $ROOT_DIR
	}

testRunRemoteLocal()
	{
	cd $ROOT_DIR
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_PATH="'$ROOT_DIR'" run_remote "ls deliver.sh"' | bash`
	assertEquals "deliver.sh" "$A"
	}

testRunRemoteSsh()
	{
	cd $ROOT_DIR
	A=`echo 'source deliver.sh --source > /dev/null 2>&1 ; REMOTE_SERVER="localhost" run_remote ls "'$ROOT_DIR'/deliver.sh"' | bash`
	assertEquals "$ROOT_DIR/deliver.sh" "$A"
	}

testRemoteInfoNonExistentRemote()
	{
	cd $ROOT_DIR/test_repo
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info nonexistentremote 2>&1' | bash`
	assertEquals "Remote nonexistentremote not found." "$A"
	}

testRemoteInfo()
	{
	initWithOrigin
	cd $ROOT_DIR/test_repo
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 ; remote_info origin ; echo "$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "+++$ROOT_DIR/test_remote" "$A"
	}

testRemoteInfoSsh()
	{
	initWithSshOrigin
	cd $ROOT_DIR/test_repo
	A=`echo 'source ../deliver.sh --source > /dev/null 2>&1 && remote_info origin && echo "$REMOTE_SERVER+++$REMOTE_PATH"' | bash`
	assertEquals "localhost+++$ROOT_DIR/test_remote" "$A"
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
	ls -l "$ROOT_DIR/test_remote"
	local RESULT=`"$ROOT_DIR"/deliver.sh --batch origin non_existent_ref 2>&1`
	assertEquals "Ref non_existent_ref not found." "$RESULT"
	}

testBasicDeliver1()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch origin master 
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
	}

testSshDeliver1()
	{
	initWithSshOrigin
	"$ROOT_DIR"/deliver.sh --batch origin master 
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/delivered ]"
	assertTrueEcho "[ -L $ROOT_DIR/test_remote/delivered/current ]"
	assertTrueEcho "[ -d $ROOT_DIR/test_remote/`readlink $ROOT_DIR/test_remote/delivered/current` ]"
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
