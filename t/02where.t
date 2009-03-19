#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use SQL::Abstract::Test import => ['is_same_sql_bind'];

use Data::Dumper;
use SQL::Abstract;

# Make sure to test the examples, since having them break is somewhat
# embarrassing. :-(

my $not_stringifiable = bless {}, 'SQLA::NotStringifiable';

my @handle_tests = (
    {
        where => {
            requestor => 'inna',
            worker => ['nwiger', 'rcwe', 'sfz'],
            status => { '!=', 'completed' }
        },
        order => [],
        stmt => " WHERE ( requestor = ? AND status != ? AND ( ( worker = ? ) OR"
              . " ( worker = ? ) OR ( worker = ? ) ) )",
        bind => [qw/inna completed nwiger rcwe sfz/],
    },

    {
        where  => [
            status => 'completed',
            user   => 'nwiger',
        ],
        stmt => " WHERE ( status = ? OR user = ? )",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            user   => 'nwiger',
            status => 'completed'
        },
        order => [qw/ticket/],
        stmt => " WHERE ( status = ? AND user = ? ) ORDER BY ticket",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            user   => 'nwiger',
            status => { '!=', 'completed' }
        },
        order => [qw/ticket/],
        stmt => " WHERE ( status != ? AND user = ? ) ORDER BY ticket",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'in', [567, 2335, 2] }
        },
        order => [],
        stmt => " WHERE ( reportid IN ( ?, ?, ? ) AND status = ? )",
        bind => [qw/567 2335 2 completed/],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'not in', [567, 2335, 2] }
        },
        order => [],
        stmt => " WHERE ( reportid NOT IN ( ?, ?, ? ) AND status = ? )",
        bind => [qw/567 2335 2 completed/],
    },

    {
        where  => {
            status   => 'completed',
            completion_date => { 'between', ['2002-10-01', '2003-02-06'] },
        },
        order => \'ticket, requestor',
#LDNOTE: modified parentheses
#        stmt => " WHERE ( completion_date BETWEEN ? AND ? AND status = ? ) ORDER BY ticket, requestor",
        stmt => " WHERE ( ( completion_date BETWEEN ? AND ? ) AND status = ? ) ORDER BY ticket, requestor",
        bind => [qw/2002-10-01 2003-02-06 completed/],
    },

    {
        where => [
            {
                user   => 'nwiger',
                status => { 'in', ['pending', 'dispatched'] },
            },
            {
                user   => 'robot',
                status => 'unassigned',
            },
        ],
        order => [],
        stmt => " WHERE ( ( status IN ( ?, ? ) AND user = ? ) OR ( status = ? AND user = ? ) )",
        bind => [qw/pending dispatched nwiger unassigned robot/],
    },

    {
        where => {  
            priority  => [ {'>', 3}, {'<', 1} ],
            requestor => \'is not null',
        },
        order => 'priority',
        stmt => " WHERE ( ( ( priority > ? ) OR ( priority < ? ) ) AND requestor is not null ) ORDER BY priority",
        bind => [qw/3 1/],
    },

    {
        where => {  
            priority  => [ {'>', 3}, {'<', 1} ],
            requestor => { '!=', undef }, 
        },
        order => [qw/a b c d e f g/],
        stmt => " WHERE ( ( ( priority > ? ) OR ( priority < ? ) ) AND requestor IS NOT NULL )"
              . " ORDER BY a, b, c, d, e, f, g",
        bind => [qw/3 1/],
    },

    {
        where => {  
            priority  => { 'between', [1, 3] },
            requestor => { 'like', undef }, 
        },
        order => \'requestor, ticket',
#LDNOTE: modified parentheses
#        stmt => " WHERE ( priority BETWEEN ? AND ? AND requestor IS NULL ) ORDER BY requestor, ticket",
        stmt => " WHERE ( ( priority BETWEEN ? AND ? ) AND requestor IS NULL ) ORDER BY requestor, ticket",
        bind => [qw/1 3/],
    },


    {
        where => {  
            id  => 1,
	    num => {
	     '<=' => 20,
	     '>'  => 10,
	    },
        },
# LDNOTE : modified test below, just parentheses differ
#        stmt => " WHERE ( id = ? AND num <= ? AND num > ? )",
        stmt => " WHERE ( id = ? AND ( num <= ? AND num > ? ) )",
        bind => [qw/1 20 10/],
    },

    {
        where => { foo => {-not_like => [7,8,9]},
                   fum => {'like' => [qw/a b/]},
                   nix => {'between' => [100,200] },
                   nox => {'not between' => [150,160] },
                   wix => {'in' => [qw/zz yy/]},
                   wux => {'not_in'  => [qw/30 40/]}
                 },
# LDNOTE: modified parentheses for BETWEEN (trivial).
# Also modified the logic of "not_like" (severe, same reasons as #14 in 00where.t)
#        stmt => " WHERE ( ( ( foo NOT LIKE ? ) OR ( foo NOT LIKE ? ) OR ( foo NOT LIKE ? ) ) AND ( ( fum LIKE ? ) OR ( fum LIKE ? ) ) AND nix BETWEEN ? AND ? AND nox NOT BETWEEN ? AND ? AND wix IN ( ?, ? ) AND wux NOT IN ( ?, ? ) )",
        stmt => " WHERE ( ( foo NOT LIKE ? AND foo NOT LIKE ? AND foo NOT LIKE ? ) AND ( ( fum LIKE ? ) OR ( fum LIKE ? ) ) AND ( nix BETWEEN ? AND ? ) AND ( nox NOT BETWEEN ? AND ? ) AND wix IN ( ?, ? ) AND wux NOT IN ( ?, ? ) )",
        bind => [7,8,9,'a','b',100,200,150,160,'zz','yy','30','40'],
    },

    {
        where => {
            id  => [],
            bar => {'!=' => []},
        },
        stmt => " WHERE ( 1=1 AND 0=1 )",
        bind => [],
    },


    {
        where => {
            foo => \["IN (?, ?)", 22, 33],
            bar => [-and =>  \["> ?", 44], \["< ?", 55] ],
        },
        stmt => " WHERE ( (bar > ? AND bar < ?) AND foo IN (?, ?) )",
        bind => [44, 55, 22, 33],
    },
   {
       where => { -and => [{}, { 'me.id' => '1'}] },
       stmt => " WHERE ( ( me.id = ? ) )",
       bind => [ 1 ],
   },

   {
       where => { foo => $not_stringifiable, },
       stmt => " WHERE ( foo = ? )",
       bind => [ $not_stringifiable ],
   },

   {
       where => \[ 'foo = ?','bar' ],
       stmt => " WHERE (foo = ?)",
       bind => [ "bar" ],
   },

   {
       where => [ \[ 'foo = ?','bar' ] ],
       stmt => " WHERE (foo = ?)",
       bind => [ "bar" ],
   },
);

# add extra modifier tests, based on 2 outcomes
my $mod_or_and = {
  stmt => 'WHERE ( foo = ? OR bar = ? ) AND baz = ? ',
  bind => [qw/1 2 3/],
};
my $mod_or_or = {
  stmt => 'WHERE ( foo = ? OR bar = ? ) OR baz = ?',
  bind => [qw/1 2 3/],
};
my $mod_and_or = {
  stmt => 'WHERE ( foo = ? AND bar = ? ) OR baz = ?',
  bind => [qw/1 2 3/],
};

push @handle_tests, (
   # test modifiers within hashrefs
   {
      where => { -or => [
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]},
      %$mod_or_or,
   },
   {
      where => { -and => [
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]},
      %$mod_or_and,
   },

   # test modifiers within arrayrefs
   {
      where => [ -or => [
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]],
      %$mod_or_or,
   },
   {
      where => [ -and => [
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]],
      %$mod_or_and,
   },

   # test ambiguous modifiers within hashrefs (op extends to to immediate RHS only)
   {
      where => { -and => [ -or =>
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]},
      %$mod_or_and,
   },
   {
      where => { -or => [ -and =>
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]},
      %$mod_and_or,
   },

   # test ambiguous modifiers within arrayrefs (op extends to to immediate RHS only)
   {
      where => [ -and => [ -or =>
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]],
      %$mod_or_and,
   },
   {
      where => [ -or => [ -and =>
        [ foo => 1, bar => 2 ],
        baz => 3,
      ]],
      %$mod_and_or,
   },
);

plan tests => ( @handle_tests * 2 ) + 1;

for my $case (@handle_tests) {
    local $Data::Dumper::Terse = 1;
    my $sql = SQL::Abstract->new;
    my($stmt, @bind);
    lives_ok (sub { 
      ($stmt, @bind) = $sql->where($case->{where}, $case->{order});
      is_same_sql_bind($stmt, \@bind, $case->{stmt}, $case->{bind})
        || diag "Search term:\n" . Dumper $case->{where};
    });
}

dies_ok {
    my $sql = SQL::Abstract->new;
    $sql->where({ foo => { '>=' => [] }},);
};
