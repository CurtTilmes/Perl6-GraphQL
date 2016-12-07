use v6;

use lib 'lib';
use GraphQL;
use JSON::Fast;

use Test;

my $schema = build-schema('
type User {
    id: String
    name: String
    birthday: String
}

schema {
    query: User
}
');

$schema.resolvers(
{
    User => {
        id => sub { return 7 },
        name => sub { return 'Fred' },
        birthday => sub { return 'Friday' }
    }
});

my @testcases = 
'Single field',
Q<<
{
    name
}
>>, 
{
    data => {
        name => 'Fred'
    }
},
#----------------------------------------------------------------------
'More fields, yes order matters',
Q<<
{
    name
    id
    birthday
}
>>, 
{
    data => Hash::Ordered.new(
        'name', 'Fred',
        'id', 7,
        'birthday', 'Friday'
    )
},
#----------------------------------------------------------------------
'Introspection __type',
Q<<
{
    __type(name: "User") {
        name
        kind
        description
    }
}
>>,
{
    data => {
        __type => Hash::Ordered.new(
            'name', 'User',
            'kind', 'OBJECT',
            'description', Nil
            )
    }
},
#----------------------------------------------------------------------
'Introspection __type(Int)',
Q<<
{
    __type(name: "Int") {
        name
        kind
        description
    }
}
>>,
{
    data => {
        __type => Hash::Ordered.new(
            'name', 'Int',
            'kind', 'SCALAR',
            'description', Nil
        )
    }
},
#----------------------------------------------------------------------
'Introspection __type(String)',
Q<<
{
    __type(name: "String") {
        name
        kind
        description
    }
}
>>,
{
    data => {
        __type => Hash::Ordered.new(
            'name', 'String',
            'kind', 'SCALAR',
            'description', Nil
        )
    }
},
#----------------------------------------------------------------------
'Introspection __type(Boolean)',
Q<<
{
    __type(name: "Boolean") {
        name
        kind
        description
    }
}
>>,
{
    data => {
        __type => Hash::Ordered.new(
            'name', 'Boolean',
            'kind', 'SCALAR',
            'description', Nil
        )
    }
},
;

for @testcases -> $description, $query, $expected
{
    is to-json(ExecuteRequest(:$schema, :query(parse-query($query)))),
       to-json($expected), $description;
}

done-testing;
