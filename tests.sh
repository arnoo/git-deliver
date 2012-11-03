#!/bin/bash

#TODO: test with chmod that gives us no permissions on some files : symlink, repo...

assertTrueEcho()
	{
	$1 || ( echo "$1" && assertTrue false )
	}

initDeliver()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR"/deliver.sh --batch --init $* 2>&1
	}

initWithOrigin()
	{
	cd "$ROOT_DIR"
	git clone --bare "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote" 
	cd "$ROOT_DIR/test_repo"
	git remote add origin "$ROOT_DIR/test_remote"
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
	#rm -rf "$ROOT_DIR/test_repo"
#	rm -rf "$ROOT_DIR/test_remote"
	cd $OLD_PWD
	}

tearDown()
	{
	rm -rf "$ROOT_DIR/test_repo/.deliver"
#	rm -rf "$ROOT_DIR/test_remote"
	cd $ROOT_DIR
	}

testHelp1()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh | grep "git deliver <REMOTE> <VERSION>" > /dev/null
	assertEquals 0 $?
	}

testListHooks()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`$ROOT_DIR/deliver.sh --list-hooks`
	echo "$RESULT" | grep "Core git deliver hooks" > /dev/null
	assertEquals 0 $?
	}

testInit()
	{
	initDeliver
	assertTrueEcho "[ -d .deliver ]"
	assertTrueEcho "[ -d .deliver/hooks ]"
	assertTrueEcho "[ -d .deliver/hooks/pre-delivery ]"
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-core-disk-space.sh ]"
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-core-mem-free.sh ]"
	assertTrueEcho "[ -d .deliver/hooks/init-remote ]"
	assertTrueEcho "[ -d .deliver/hooks/post-checkout ]"
	assertTrueEcho "[ -d .deliver/hooks/post-symlink ]"
	assertTrueEcho "[ -d .deliver/hooks/rollback ]"
	}

testInitHook()
	{
	initDeliver php
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-php-syntax-check.sh ]"
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

testBasicDeliver1()
	{
	initWithOrigin
	"$ROOT_DIR"/deliver.sh --batch origin master 
	assertTrueEcho "[ -d \"$ROOT_DIR\"/test_remote/delivered ]"
	assertTrueEcho "[ -L \"$ROOT_DIR\"/test_remote/delivered/current ]"
	assertTrueEcho "[ -d \""`readlink "$ROOT_DIR"/test_remote/delivered/current`"\" ]"
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
