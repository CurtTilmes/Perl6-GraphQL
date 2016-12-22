#!/usr/bin/env perl6

use GraphQL;
use GraphQL::Types;
use GraphQL::Server;
use Cache::LRU;

my $usercache = Cache::LRU.new;   # Key = User.id, Value = User

enum State <NOT_FOUND ACTIVE INACTIVE SUSPENDED>;

class Query { ... }
class Mutation { ...}

class User
{
    trusts Mutation;

    has ID $.id is rw;
    has Str $.name is rw;
    has Str $.birthday is rw;
    has Bool $.status is rw;
    has State $.state is rw;
    has Set $!friend-set = ∅;

    method friends(--> Array[User]) is graphql-background
    {
        Array[User].new(await $!friend-set.keys.map({
                                  start Query.user(:id($_))
                              }));
    }

    method random_friend(--> User) is graphql-background
    {
        Query.user(:id($!friend-set.pick));
    }

    method !friend_add(ID :$friend_id --> Bool)
    {
        $!friend-set ∪= $friend_id;
        $usercache.remove($!id);
        return True;
    }

    method !friend_remove(ID :$friend_id --> Bool)
    {
        $!friend-set -= $friend_id;
        $usercache.remove($!id);
        return True;
    }
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
        return unless @users[$id];

        if $usercache.get($id) -> $user
        {
            return $user;
        }

        say "Sleeping for $id";
        sleep 2;

        my $user = @users[$id];

        $usercache.set($id, $user);
    }

    method listusers(ID :$start, Int :$count --> Array[User])
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
        $usercache.remove($id);
        return Query.user(:$id);
    }

    method friend_add(ID :$id, ID :$friend_id --> Bool)
    {
        @users[$id]!User::friend_add(:$friend_id);
    }

    method friend_remove(ID :$id, ID :$friend_id --> Bool)
    {
        @users[$id]!User::friend_remove(:$friend_id);
    }
}

my $schema = GraphQL::Schema.new(State, User, UserInput, Query, Mutation);

GraphQL-Server($schema);
