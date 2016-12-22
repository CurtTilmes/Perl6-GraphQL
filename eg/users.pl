#!/usr/bin/env perl6

use GraphQL;
use GraphQL::Types;
use GraphQL::Server;

enum State <NOT_FOUND ACTIVE INACTIVE SUSPENDED>;

class User
{
    has ID $.id is rw;
    has Str $.name is rw;
    has Str $.birthday is rw;
    has Bool $.status is rw;
    has State $.state is rw;
    has User @.friends is rw;
}

class UserInput is GraphQL::InputObject
{
    has Str $.name;
    has Str $.birthday;
    has Bool $.status;
    has State $.state;
}

my User @users =
    User.new(id => "0",
             name => 'Gilligan',
             birthday => 'Friday',
             status => True,
             state => NOT_FOUND),
    User.new(id => "1",
             name => 'Skipper',
             birthday => 'Monday',
             status => False,
             state => ACTIVE),
    User.new(id => "2",
             name => 'Professor',
             birthday => 'Tuesday',
             status => True,
             state => INACTIVE),
    User.new(id => "3",
             name => 'Ginger',
             birthday => 'Wednesday',
             status => True,
             state => SUSPENDED),
    User.new(id => "4",
             name => 'Mary Anne',
             birthday => 'Thursday',
             status => True,
             state => ACTIVE);

class Query
{
    method user(ID :$id --> User)
        is graphql-background
    {
        sleep 2;
        @users[$id]
    }

    method listusers(Int :$start, Int :$count --> Array[User])
        is graphql-background
    {
        Array[User].new(
            await ($start ..^ $start+$count).map({ start Query.user(:id($_)) })
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
                              status => $newuser.status,
                              state => $newuser.state);
        return @users.elems - 1;
    }

    method updateuser(ID :$id, UserInput :$userinput --> User)
    {
        for <name birthday status state> -> $field
        {
            if $userinput."$field"().defined
            {
                @users[$id]."$field"() = $userinput."$field"();
            }
        }
        return Query.user(:$id);
    }
}

my $schema = GraphQL::Schema.new(State, User, UserInput, Query, Mutation);

GraphQL-Server($schema);
