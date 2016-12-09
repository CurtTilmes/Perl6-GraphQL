use v6;

use lib 'lib';
use GraphQL;
use JSON::Fast;

use Test;

my $schema = GraphQL::Schema.new('
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
'Try some aliases',
Q<<
{
    callme: name
    id
    mybday: birthday
    orcallme: name
}
>>, 
{
    data => Hash::Ordered.new(
        'callme', 'Fred',
        'id', 7,
        'mybday', 'Friday',
        'orcallme', 'Fred'
    )
},
#----------------------------------------------------------------------
'Fragment',
Q<<
query {

    name
    id
    ... morestuff
    birthday
}
fragment morestuff on User {
    callme: name
    mybday: birthday
}
>>, 
{
    data => Hash::Ordered.new(
        'name', 'Fred',
        'id', 7,
        'callme', 'Fred',
        'mybday', 'Friday',
        'birthday', 'Friday'
    )
},
#----------------------------------------------------------------------
'inline Fragment',
Q<<
query foo {

    name
    id
    ... {
        callme: name
        mybday: birthday
    }
    birthday
}
>>, 
{
    data => Hash::Ordered.new(
        'name', 'Fred',
        'id', 7,
        'callme', 'Fred',
        'mybday', 'Friday',
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
#----------------------------------------------------------------------
'Introspection __type(Float)',
Q<<
{
    __type(name: "Float") {
        name
        kind
        description
    }
}
>>,
{
    data => {
        __type => Hash::Ordered.new(
            'name', 'Float',
            'kind', 'SCALAR',
            'description', Nil
        )
    }
},
;

for @testcases -> $description, $query, $expected
{
    is to-json(graphql-execute(:$schema,:document($schema.document($query)))),
       to-json($expected), $description;
}

done-testing;
