use v6;

use GraphQL;
use GraphQL::Types;
use GraphQL::Server;

class User
{
    has ID $.id is rw;
    has Str $.name is rw;
    has Str $.birthday is rw;
    has Bool $.status is rw;
}

my @users =
    User.new(id => "0",
             name => 'Gilligan',
             birthday => 'Friday',
             status => True),
    User.new(id => "1",
             name => 'Skipper',
             birthday => 'Monday',
             status => False),
    User.new(id => "2",
             name => 'Professor',
             birthday => 'Tuesday',
             status => True),
    User.new(id => "3",
             name => 'Ginger',
             birthday => 'Wednesday',
             status => True),
    User.new(id => "4",
             name => 'Mary Anne',
             birthday => 'Thursday',
             status => True);

class UserInput is GraphQL::InputObjectClass
{
    has Str $.name;
    has Str $.birthday;
    has Bool $.status;
}

class Query
{
    method user(ID :$id --> User)
    {
        @users[$id.Int] // Nil
    }

    method listusers(Int :$start, Int :$count --> Array[User])
    {
        Array[User].new(
            ($start ..^ $start+$count).map({ Query.user(:id($_)) })
        );
    }
}

class Mutation
{
    method adduser(UserInput :$newuser --> ID)
    {
        push @users, User.new(id => @users.elems,
                              name => $newuser.name,
                              birthday => $newuser.birthday,
                              status => $newuser.status);
        return @users.elems - 1;
    }

    method updateuser(ID :$id, UserInput :$userinput --> User)
    {
        for <name birthday status> -> $field
        {
            if $userinput."$field"().defined
            {
                @users[$id]."$field"() = $userinput."$field"();
            }
        }
        return Query.user(:$id);
    }
}

my $schema = GraphQL::Schema.new(User, UserInput, Query, Mutation);

GraphQL-Server($schema);
