use v6;

use lib 'lib';
use GraphQL;
use Hash::Ordered;
use JSON::Fast;

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

{
    data => {
        user => Hash::Ordered.new(
            'id', 3,
            'name', 'Ginger'
        )
    }
},

#----------------------------------------------------------------------
'Query for first user in allusers',

'{ allusers { id name } }',

{},

{
    data => {
        allusers => [
            Hash::Ordered.new(
                'id', 0,
                'name', 'Gilligan'
            )
        ]
    }
},

#----------------------------------------------------------------------
'Query for 2 users starting with user 3',

'{ allusers(start: 3, count: 2) { name status } }',

{},

{
    data => {
        allusers => [
            Hash::Ordered.new(
                'name', 'Ginger',
                'status', True
            ),
            Hash::Ordered.new(
                'name', 'Mary Anne',
                'status', True
            )
        ]
    }
},

#----------------------------------------------------------------------
'Query for single user with variable',

'query ($x: ID) { user(id: $x) { id, name } }',

{ x => 3 },

{
    data => {
        user => Hash::Ordered.new(
            'id', 3,
            'name', 'Ginger'
        )
    }
},

#----------------------------------------------------------------------
'Query for another user with variable',

'query ($x: ID) { user(id: $x) { id, name } }',

{ x => 4 },

{
    data => {
        user => Hash::Ordered.new(
            'id', 4,
            'name', 'Mary Anne'
        )
    }
},

#----------------------------------------------------------------------
'Query for multiple users with multiple variables',

'query ($start: Int, $count: Int)
 { allusers(start: $start, count: $count) { name status } }',

{ start => 1, count => 4 },

{
    data => {
        allusers => [
            Hash::Ordered.new(
                'name', 'Skipper',
                'status', False
            ),
            Hash::Ordered.new(
                'name', 'Professor',
                'status', True
            ),
            Hash::Ordered.new(
                'name', 'Ginger',
                'status', True
            ),
            Hash::Ordered.new(
                'name', 'Mary Anne',
                'status', True
            )
        ]
    }
},

#----------------------------------------------------------------------
'@skip directive if false',

'query { user(id: 4) { id, name @skip(if: false)} }',

{},

{
    data => {
        user => Hash::Ordered.new(
            'id', 4,
            'name', 'Mary Anne'
        )
    }
},

#----------------------------------------------------------------------
'@skip directive if true',

'query { user(id: 4) { id, name @skip(if: true)} }',

{},

{
    data => {
        user => Hash::Ordered.new(
            'id', 4,
        )
    }
},

#----------------------------------------------------------------------
'@skip directive if variable false',

'query ($x: Boolean) { user(id: 4) { id, name @skip(if: $x)} }',

{ x => 'false' },

{
    data => {
        user => Hash::Ordered.new(
            'id', 4,
            'name', 'Mary Anne'
        )
    }
},

#----------------------------------------------------------------------
'@skip directive if variable true',

'query ($x: Boolean) { user(id: 4) { id, name @skip(if: $x)} }',

{x => 'true'},

{
    data => {
        user => Hash::Ordered.new(
            'id', 4,
        )
    }
},
;

for @testcases -> $description, $query, %variables, %expected
{
    ok my $document = $schema.document($query), "parse $description";

    ok my $ret = $schema.execute(:$document, :%variables),
    "execute $description";

#   is-deeply $ret, %expected;

    is to-json($ret), to-json(%expected),
    "compare $description";
}

done-testing;
