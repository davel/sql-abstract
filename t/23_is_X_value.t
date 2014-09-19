use warnings;
use strict;

use Test::More;
use Test::Exception;
use Scalar::Util 'refaddr';
use Storable 'nfreeze';

use SQL::Abstract qw(is_plain_value is_literal_value);

# fallback setting is inheriting starting p5 50853fa9 (run up to 5.17.0)
use constant OVERLOAD_FALLBACK_INHERITS => ( ($] < 5.017) ? 0 : 1 );
use constant STRINGIFIER_CAN_RETURN_IVS => ( ($] < 5.008) ? 0 : 1 );

{
  package # hideee
    SQLATest::SillyBool;

  use overload
    # *DELIBERATELY* unspecified
    #fallback => 1,
    bool => sub { ${$_[0]} },
  ;

  package # hideee
    SQLATest::SillyBool::Subclass;

  our @ISA = 'SQLATest::SillyBool';
}

{
  package # hideee
    SQLATest::SillyInt;

  use overload
    # *DELIBERATELY* unspecified
    #fallback => 1,
    '0+' => sub { ${$_[0]} },
  ;

  package # hideee
    SQLATest::SillyInt::Subclass;

  our @ISA = 'SQLATest::SillyInt';
}

{
  package # hideee
    SQLATest::SillierInt;

  use overload
    fallback => 0,
  ;

  package # hideee
    SQLATest::SillierInt::Subclass;

  use overload
    '0+' => sub { ${$_[0]} },
    '+' => sub { ${$_[0]} + $_[1] },
  ;

  our @ISA = 'SQLATest::SillierInt';
}

{
  package # hideee
    SQLATest::AnalInt;

  use overload
    fallback => 0,
    '0+' => sub { ${$_[0]} },
  ;

  package # hideee
    SQLATest::AnalInt::Subclass;

  use overload
    '0+' => sub { ${$_[0]} },
  ;

  our @ISA = 'SQLATest::AnalInt';
}

{
  package # hidee
    SQLATest::ReasonableInt;

  # make it match JSON::PP::Boolean
  use overload
    '0+' => sub { ${$_[0]} },
    '++' => sub { $_[0] = ${$_[0]} + 1 },
    '--' => sub { $_[0] = ${$_[0]} - 1 },
    fallback => 1,
  ;

  package # hideee
    SQLATest::ReasonableInt::Subclass;

  our @ISA = 'SQLATest::ReasonableInt';
}

{
  package # hidee
    SQLATest::ReasonableString;

  # somewhat like DateTime
  use overload
    'fallback' => 1,
    '""'       => sub { "${$_[0]}" },
    '-'        => sub { ${$_[0]} - $_[1] },
    '+'        => sub { ${$_[0]} + $_[1] },
  ;

  package # hideee
    SQLATest::ReasonableString::Subclass;

  our @ISA = 'SQLATest::ReasonableString';
}

for my $case (
  { class => 'SQLATest::SillyBool',           can_math => 0, should_str => 1 },
  { class => 'SQLATest::SillyBool::Subclass', can_math => 0, should_str => 1 },
  { class => 'SQLATest::SillyInt',            can_math => 0, should_str => 1 },
  { class => 'SQLATest::SillyInt::Subclass',  can_math => 0, should_str => 1 },
  { class => 'SQLATest::SillierInt',          can_math => 0, should_str => 0 },
  { class => 'SQLATest::SillierInt::Subclass',can_math => 1, should_str => (OVERLOAD_FALLBACK_INHERITS ? 0 : 1) },
  { class => 'SQLATest::AnalInt',             can_math => 0, should_str => 0 },
  { class => 'SQLATest::AnalInt::Subclass',   can_math => 0, should_str => (OVERLOAD_FALLBACK_INHERITS ? 0 : 1) },
  { class => 'SQLATest::ReasonableInt',             can_math => 1, should_str => 1 },
  { class => 'SQLATest::ReasonableInt::Subclass',   can_math => 1, should_str => 1 },
  { class => 'SQLATest::ReasonableString',          can_math => 1, should_str => 1 },
  { class => 'SQLATest::ReasonableString::Subclass',can_math => 1, should_str => 1 },
) {

  my $num = bless( \do { my $foo = 42 }, $case->{class} );

  my $can_str = eval { "$num" eq 42 } || 0;

  ok (
    !($can_str xor $case->{should_str}),
    "should_str setting for $case->{class} matches perl behavior",
  ) || diag explain { %$case, can_str => $can_str };

  my $can_math = eval { ($num + 1) == 43 } ? 1 : 0;

  ok (
    !($can_math xor $case->{can_math}),
    "can_math setting for $case->{class} matches perl behavior",
  ) || diag explain { %$case, actual_can_math => $can_math };

  my $can_cmp = eval { my $dum = ($num eq "nope"); 1 } || 0;

  for (1,2) {

    if ($can_str) {

      ok $num, 'bool ctx works';

      if (STRINGIFIER_CAN_RETURN_IVS and $can_cmp) {
        is_deeply(
          is_plain_value $num,
          \$num,
          "stringification detected on $case->{class}",
        ) || diag explain $case;
      }
      else {
        # is_deeply does not do nummify/stringify cmps properly
        # but we can always compare the ice
        ok(
          ( nfreeze( is_plain_value $num ) eq nfreeze( \$num ) ),
          "stringification without cmp capability detected on $case->{class}"
        ) || diag explain $case;
      }

      is (
        refaddr( ${is_plain_value($num)} ),
        refaddr $num,
        "Same reference (blessed object) returned",
      );
    }
    else {
      is( is_plain_value($num), undef, "non-stringifiable $case->{class} object detected" )
        || diag explain $case;
    }

    if ($case->{can_math}) {
      is ($num+1, 43);
    }
  }
}

lives_ok {
  my $num = bless( \do { my $foo = 23 }, 'SQLATest::ReasonableInt' );
  cmp_ok(++$num, '==', 24, 'test overloaded object compares correctly');
  cmp_ok(--$num, 'eq', 23, 'test overloaded object compares correctly');
  is_deeply(
    is_plain_value $num,
    \23,
    'fallback stringification detected'
  );
  cmp_ok(--$num, 'eq', 22, 'test overloaded object compares correctly');
  cmp_ok(++$num, '==', 23, 'test overloaded object compares correctly');
} 'overload testing lives';


is_deeply
  is_plain_value {  -value => [] },
  \[],
  '-value recognized'
;

for ([], {}, \'') {
  is
    is_plain_value $_,
    undef,
    'nonvalues correctly recognized'
  ;
}

for (undef, { -value => undef }) {
  is_deeply
    is_plain_value $_,
    \undef,
    'NULL -value recognized'
  ;
}

is_deeply
  is_literal_value { -ident => 'foo' },
  [ 'foo' ],
  '-ident recognized as literal'
;

is_deeply
  is_literal_value \[ 'sql', 'bind1', [ {} => 'bind2' ] ],
  [ 'sql', 'bind1', [ {} => 'bind2' ] ],
  'literal correctly unpacked'
;


for ([], {}, \'', undef) {
  is
    is_literal_value { -ident => $_ },
    undef,
    'illegal -ident does not trip up detection'
  ;
}

done_testing;
