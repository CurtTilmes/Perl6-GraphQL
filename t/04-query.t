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
Q<<{
  "data": {
    "name": "Fred"
  }
}>>,
#----------------------------------------------------------------------
'More fields',
Q<<
{
    name
    id
    birthday
}
>>, 
Q<<{
  "data": {
    "name": "Fred",
    "id": "7",
    "birthday": "Friday"
  }
}>>,
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
Q<<{
  "data": {
    "callme": "Fred",
    "id": "7",
    "mybday": "Friday",
    "orcallme": "Fred"
  }
}>>,
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
Q<<{
  "data": {
    "name": "Fred",
    "id": "7",
    "callme": "Fred",
    "mybday": "Friday",
    "birthday": "Friday"
  }
}>>,
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
Q<<{
  "data": {
    "name": "Fred",
    "id": "7",
    "callme": "Fred",
    "mybday": "Friday",
    "birthday": "Friday"
  }
}>>,
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
Q<<{
  "data": {
    "__type": {
      "name": "User",
      "kind": "OBJECT",
      "description": null
    }
  }
}>>,
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
Q<<{
  "data": {
    "__type": {
      "name": "Int",
      "kind": "SCALAR",
      "description": null
    }
  }
}>>,
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
Q<<{
  "data": {
    "__type": {
      "name": "String",
      "kind": "SCALAR",
      "description": null
    }
  }
}>>,
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
Q<<{
  "data": {
    "__type": {
      "name": "Boolean",
      "kind": "SCALAR",
      "description": null
    }
  }
}>>,
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
Q<<{
  "data": {
    "__type": {
      "name": "Float",
      "kind": "SCALAR",
      "description": null
    }
  }
}>>,

;

for @testcases -> $description, $query, $expected
{
    is $schema.execute($query).to-json, $expected, $description;
}

done-testing;
