use v6;

use lib 'lib';
use GraphQL;

use Test;

ok my $schema = GraphQL::Schema.new('
type User {
  id: ID
  name: String
  birthday: String
  status: Boolean
}

type Root {
  allusers(start: ID = 0, count: ID = 1): [User]
  user(id: ID): User
}

schema {
  query: Root
}
'), 'Build Schema';

class User
{
    has $.id;
    has $.name;
    has $.birthday;
    has $.status;
}

my @users =
    User.new(id => 0,
             name => 'Gilligan',
             birthday => 'Friday',
             status => True),
    User.new(id => 1,
             name => 'Skipper',
             birthday => 'Monday',
             status => False),
    User.new(id => 2,
             name => 'Professor',
             birthday => 'Tuesday',
             status => True),
    User.new(id => 3,
             name => 'Ginger',
             birthday => 'Wednesday',
             status => True),
    User.new(id => 4,
             name => 'Mary Anne',
             birthday => 'Thursday',
             status => True);

$schema.resolvers(
{
    Root =>
    {
        allusers =>
            sub (Int :$start, Int :$count)
            {
                @users[$start ..^ $start+$count]
            },
        user =>
            sub (Int :$id)
            {
                @users[$id]
            }
    }
});

my @testcases = 
'Query for user 3',

'{ user(id: 3) { id, name } }',

{},

Q<<{
  "data": {
    "user": {
      "id": "3",
      "name": "Ginger"
    }
  }
}>>,

#----------------------------------------------------------------------
'Query for first user in allusers',

'{ allusers { id name } }',

{},

Q<<{
  "data": {
    "allusers": [
      {
        "id": "0",
        "name": "Gilligan"
      }
    ]
  }
}>>,

#----------------------------------------------------------------------
'Query for 2 users starting with user 3',

'{ allusers(start: 3, count: 2) { name status } }',

{},

Q<<{
  "data": {
    "allusers": [
      {
        "name": "Ginger",
        "status": true
      },
      {
        "name": "Mary Anne",
        "status": true
      }
    ]
  }
}>>,

#----------------------------------------------------------------------
'Query for single user with variable',

'query ($x: ID) { user(id: $x) { id, name } }',

{ x => 3 },

Q<<{
  "data": {
    "user": {
      "id": "3",
      "name": "Ginger"
    }
  }
}>>,

#----------------------------------------------------------------------
'Query for another user with variable',

'query ($x: ID) { user(id: $x) { id, name } }',

{ x => 4 },

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,

#----------------------------------------------------------------------
'Query for multiple users with multiple variables',

'query ($start: Int, $count: Int)
 { allusers(start: $start, count: $count) { name status } }',

{ start => 1, count => 4 },

Q<<{
  "data": {
    "allusers": [
      {
        "name": "Skipper",
        "status": false
      },
      {
        "name": "Professor",
        "status": true
      },
      {
        "name": "Ginger",
        "status": true
      },
      {
        "name": "Mary Anne",
        "status": true
      }
    ]
  }
}>>,

#----------------------------------------------------------------------
'@skip directive if false',

'query { user(id: 4) { id, name @skip(if: false)} }',

{},

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,

#----------------------------------------------------------------------
'@skip directive if true',

'query { user(id: 4) { id, name @skip(if: true)} }',

{},

Q<<{
  "data": {
    "user": {
      "id": "4"
    }
  }
}>>,

#----------------------------------------------------------------------
'@skip directive if variable false',

'query ($x: Boolean) { user(id: 4) { id, name @skip(if: $x)} }',

{ x => False },

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,

#----------------------------------------------------------------------
'@include directive if variable true',

'query ($x: Boolean) { user(id: 4) { id, name @include(if: $x)} }',

{x => True},

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,

#----------------------------------------------------------------------
'@include directive if false',

'query { user(id: 4) { id, name @include(if: false)} }',

{},

Q<<{
  "data": {
    "user": {
      "id": "4"
    }
  }
}>>,

#----------------------------------------------------------------------
'@include directive if true',

'query { user(id: 4) { id, name @include(if: true)} }',

{},

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,

#----------------------------------------------------------------------
'@include directive if variable false',

'query ($x: Boolean) { user(id: 4) { id, name @include(if: $x)} }',

{ x => False },

Q<<{
  "data": {
    "user": {
      "id": "4"
    }
  }
}>>,

#----------------------------------------------------------------------
'@include directive if variable true',

'query ($x: Boolean) { user(id: 4) { id, name @include(if: $x)} }',

{x => True},

Q<<{
  "data": {
    "user": {
      "id": "4",
      "name": "Mary Anne"
    }
  }
}>>,
;

for @testcases -> $description, $query, %variables, $expected
{
    ok my $document = $schema.document($query), "parse $description";

    ok my $ret = $schema.execute(:$document, :%variables),
    "execute $description";

    is $ret.to-json, $expected, "compare $description";
}

done-testing;
