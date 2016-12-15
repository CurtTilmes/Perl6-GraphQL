use JSON::Fast;
my %ESCAPE = (
    '"'  => '"',
    '\\' => '\\',
    '/'  => '/',
    'b'  => "\b",
    'f'  => "\f",
    'n'  => "\n",
    'r'  => "\r",
    't'  => "\t"
);

my $s = Q<this\u263athat  mine \" \/ \n foo \\ more >;

say "Before: [$s]";

    $s.subst-mutate(/\\(<[\"\\\/bfnrt]>)/,
                    { %ESCAPE{$0} }, :g);

    $s.subst-mutate(/\\u(<xdigit> ** 4)/, 
                    { chr($0.Str.parse-base(16)) }, :g);
 
say "After: [$s]";

