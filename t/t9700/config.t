#!/usr/bin/env perl -- -w

use TestUtils;
use Test::More no_plan;
use strict;

use Error qw(:try);

use_ok("Git::Config");

in_empty_repo sub {
	my $git = Git->repository;
	$git->command_oneline("config", "foo.bar", "baz");
	$git->command_oneline("config", "list.value", "one");
	$git->command_oneline("config", "--add", "list.value", "two");
	$git->command_oneline("config", "foo.intval", "12g");
	$git->command_oneline("config", "foo.false.val", "false");
	$git->command_oneline("config", "foo.true.val", "yes");
	open(CONFIG, ">>.git/config") or die $!;
	print CONFIG <<CONF;
[boolean]
   noval
   empty1 =
   empty2 = ""
CONF
	close CONFIG;

	my $conf = Git::Config->new();
	ok($conf, "constructed a new Git::Config");
	isa_ok($conf, "Git::Config", "Git::Config->new()");

	is($conf->config("foo.bar"), "baz", "read single line");
	$conf->config("foo.bar", "frop");
	like($git->command_oneline("config", "foo.bar"), qr/frop/,
		"->config() has immediate effect");
	$conf->autoflush(0);
	is_deeply(
		[$conf->config("list.value")],
		[qw(one two)],
		"read multi-value item",
	);

	eval {
		my $val = $conf->config("list.value");
	};
	like ($@, qr{multiple}i,
	      "produced an error reading a list into a scalar");

	eval {
		$conf->config("list.value" => "single");
	};
	like($@, qr{multiple}i,
	     "produced an error replacing a list with a scalar");

	ok(eval { $conf->config("foo.bar", [ "baz", "frop"]); 1 },
		"no error replacing a scalar with a list");

	like($git->command_oneline("config", "foo.bar"), qr/frop/,
		"->config() no immediate effect with autoflush = 0");

	$conf->flush;

	like($git->command("config", "--get-all", "foo.bar"),
		qr/baz\s*frop/,
		"->flush()");

	$conf->config("x.y$$" => undef);
	my $x = $conf->config("x.y$$");
	ok(!defined $x, "unset items return undef in scalar context");
	my @x = $conf->config("x.y$$");
	ok(@x == 0, "unset items return empty list in list context");

	$conf->config("foo.bar" => undef);
	@x = $conf->config("foo.bar");
	ok(@x == 0, "deleted items appear empty immediately");
	$conf->flush;
	ok(!eval {
		$git->command("config", "--get-all", "foo.bar");
		1;
	}, "deleted items are removed from the config file");

	$conf->type("foo.intval", "integer");
	is($conf->type("foo.intval"), "integer",
	   "->type()");
	is($conf->config("foo.intval"), 12*1024*1024*1024,
	   "integer thaw");
	$conf->config("foo.intval", 1025*1024);
	$conf->type("foo.intval", "string");
	is($conf->config("foo.intval"), "1025k",
	   "integer freeze");

	$conf->type("foo.*.val", "boolean");
	is($conf->type("foo.this.val"), "boolean",
	   "wildcard types");
	is($conf->config("foo.true.val"), 1,
	   "boolean thaw - 'yes'");
	is($conf->config("foo.false.val"), 0,
	   "boolean thaw - 'false'");
	my $unset = $conf->config("foo.bar.val");
	is($unset, undef,
	   "boolean thaw - not present");

	$git->command_oneline("config", "foo.intval", "12g");
	$git->command_oneline("config", "foo.falseval", "false");
	$git->command_oneline("config", "foo.trueval", "on");

	is($conf->config("boolean.noval"), "", "noval: string");
	is($conf->config("boolean.empty1"), "", "empty1: string");
	is($conf->config("boolean.empty2"), "", "empty2: string");

	$conf->type("boolean.*" => "boolean");

	ok($conf->config("boolean.noval"), "noval: boolean");
	ok(!$conf->config("boolean.empty1"), "empty1: boolean");
	ok(!$conf->config("boolean.empty2"), "empty2: boolean");

	SKIP:{
		if (eval {
			$git->command(
				"config", "--global",
				"--get-all", "foo.bar"
			       );
			1;
		}) {
			skip "someone set foo.bar in global config", 1;
		}
		my @foo_bar = $conf->global("foo.bar");
		is_deeply(\@foo_bar, [], "->global() reading only");
	}
};


# Local Variables:
#   mode: cperl
#   cperl-brace-offset: 0
#   cperl-continued-brace-offset: 0
#   cperl-indent-level: 8
#   cperl-label-offset: -8
#   cperl-merge-trailing-else: nil
#   cperl-continued-statement-offset: 8
#   cperl-indent-parens-as-block: t
#   cperl-indent-wrt-brace: nil
# End:
#
# vim: vim:tw=78:sts=0:noet
