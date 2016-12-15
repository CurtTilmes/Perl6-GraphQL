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

input UserInput {
  name: String
  birthday: String
  status: Boolean
}

type Changes {
  adduser(newuser: UserInput): ID
  updateuser(id: ID, userinput: UserInput): User
}

schema {
  query: Root
  mutation: Changes
}
'), 'Build Schema';

class User
{
    has $.id is rw;
    has $.name is rw;
    has $.birthday is rw;
    has $.status is rw;
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
    },
    Changes =>
    {
        adduser => sub (:%newuser)
        {
            push @users, User.new(id => @users.elems, |%newuser);
            return @users.elems - 1;
        },
        updateuser => sub (Int :$id, :%userinput)
        {
            for %userinput.kv -> $k, $v
            {
                @users[$id]."$k"() = $v;
            }

            @users[$id]
        }
    }
});

my @testcases = 
'Get user 3',

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
'Update user 3',

'mutation { updateuser(id: 3, userinput: { name: "Fred" }) { id, name } }',

{},

{
    data => {
        updateuser => Hash::Ordered.new(
            'id', 3,
            'name', 'Fred'
        )
    }
},

#----------------------------------------------------------------------
'Get changed user 3',

'{ user(id: 3) { id, name } }',

{},

{
    data => {
        user => Hash::Ordered.new(
            'id', 3,
            'name', 'Fred'
        )
    }
},

#----------------------------------------------------------------------
'Update user 3, change multiple fields',

'mutation { updateuser(id: 3, 
    userinput: { name: "Fred", birthday: "Saturday", status: false })
    { id, birthday, status, name }
}',

{},

{
    data => {
        updateuser => Hash::Ordered.new(
            'id', 3,
            'birthday', 'Saturday',
            'status', False,
            'name', 'Fred'
        )
    }
},

#----------------------------------------------------------------------
'Change user 2 with variable for userinput',

'mutation ($updateuser: UserInput) {
     updateuser(id: 2, userinput: $updateuser)
         { id, birthday, status, name }
}',

{
    updateuser => {
        name => 'John',
        birthday => 'Sunday'
    }
},

{
    data => {
        updateuser => Hash::Ordered.new(
            'id', 2,
            'birthday', 'Sunday',
            'status', True,
            'name', 'John'
        )
    }
},

#----------------------------------------------------------------------
'Insert a new user',

'mutation ($newuser: UserInput) {
    adduser(newuser: $newuser)
}',

{
    newuser => {
        name => 'Thurston',
        birthday => 'Tuesday',
        status => 'false'
    }
},

{
    data => {
        adduser => 5
    }
},

#----------------------------------------------------------------------
'Check to see if new user present',

'{ user(id: 5) { id, birthday, status, name } }',

{},

{
    data => {
        user => Hash::Ordered.new(
            'id', 5,
            'birthday', 'Tuesday',
            'status', False,
            'name', 'Thurston'
        )
    }
},

;

for @testcases -> $description, $query, %variables, %expected
{
    ok my $document = $schema.document($query),
    "parse $description";

    ok my $ret = $schema.execute(:$document, :%variables),
    "execute $description";

#   is-deeply $ret, %expected;

    is to-json($ret), to-json(%expected), "compare $description";
}

done-testing;
