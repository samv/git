#!/bin/sh
#
# Copyright (c) 2008 Lea Wiemann
#

test_description='perl interface (Git.pm)'
. ./test-lib.sh

perl -MTest::More -e 0 2>/dev/null || {
	say_color skip "Perl Test::More unavailable, skipping test"
	test_done
}

# set up test repository

test_expect_success \
    'set up test repository' \
    'echo "test file 1" > file1 &&
     echo "test file 2" > file2 &&
     mkdir directory1 &&
     echo "in directory1" >> directory1/file &&
     mkdir directory2 &&
     echo "in directory2" >> directory2/file &&
     git add . &&
     git commit -m "first commit" &&

     echo "changed file 1" > file1 &&
     git commit -a -m "second commit" &&

     git config --add color.test.slot1 green &&
     git config --add test.string value &&
     git config --add test.dupstring value1 &&
     git config --add test.dupstring value2 &&
     git config --add test.booltrue true &&
     git config --add test.boolfalse no &&
     git config --add test.boolother other &&
     git config --add test.int 2k
     '

export PERL5LIB="$TEST_DIRECTORY/t9700:$GITPERLLIB:$PERL5LIB"

test_external_without_stderr \
    'Perl API' \
    perl "$TEST_DIRECTORY"/t9700/test.pl

rm -rf .git

test_external_without_stderr \
    'config API' \
    perl "$TEST_DIRECTORY"/t9700/config.t

test_done
