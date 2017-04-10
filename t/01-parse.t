use v6;

use Test;
use lib 'lib';

use GraphQL::Grammar;

# Every example from http://facebook.github.io/graphql

my @good = Q<<
    {
        user(id: 4) {
            name
        }
    }
>>, Q<<
    mutation {
        likeStory(storyID: 12345) {
            story {
                likeCount
            }
        }
    }
>>, Q<<
    {
        field
    }
>>, Q<<
    {
        id
            firstName
            lastName
    }
>>, Q<<
    {
        me {
            id
                firstName
                lastName
                birthday {
                    month
                        day
            }
            friends {
                name
            }
        }
    }
>>, Q<<
    # `me` could represent the currently logged in viewer.
    {
        me {
            name
        }
    }
>>, Q<<
    # `user` represents one of many users in a graph of data, referred to by a
    # unique identifier.
    {
        user(id: 4) {
            name
        }
    }
>>, Q<<
    {
        user(id: 4) {
            id
            name
            profilePic(size: 100)
        }
    }
>>, Q<<
    {
        user(id: 4) {
            id
            name
            profilePic(width: 100, height: 50)
        }
    }
>>, Q<<
    {
        user(id: 4) {
            id
            name
            smallPic: profilePic(size: 64)
            bigPic: profilePic(size: 1024)
        }
    }
>>, Q<<
    {
        zuck: user(id: 4) {
        id
        name
        }
    }
>>, Q<<
    query noFragments {
        user(id: 4) {
            friends(first: 10) {
                id
                name
                profilePic(size: 50)
            }
            mutualFriends(first: 10) {
                id
                name
                profilePic(size: 50)
            }
        }
    }
>>, Q<<
    query withFragments {
        user(id: 4) {
            friends(first: 10) {
                ...friendFields
            }
            mutualFriends(first: 10) {
                ...friendFields
            }
        }
    }

    fragment friendFields on User {
        id
        name
        profilePic(size: 50)
    }
>>, Q<<
    query withNestedFragments {
        user(id: 4) {
            friends(first: 10) {
                ...friendFields
            }
            mutualFriends(first: 10) {
                ...friendFields
            }
        }
    }

    fragment friendFields on User {
        id
        name
        ...standardProfilePic
    }

    fragment standardProfilePic on User {
        profilePic(size: 50)
    }
>>, Q<<
    query FragmentTyping {
        profiles(handles: ["zuck", "cocacola"]) {
            handle
            ...userFragment
            ...pageFragment
        }
    }

    fragment userFragment on User {
        friends {
            count
        }
    }

    fragment pageFragment on Page {
        likers {
            count
        }
    }
>>, Q<<
    query inlineFragmentTyping {
        profiles(handles: ["zuck", "cocacola"]) {
            handle
            ... on User {
                friends {
                    count
                }
            }
            ... on Page {
                likers {
                    count
                }
            }
        }
    }
>>,Q<<
    query inlineFragmentNoType($expandedInfo: Boolean) {
        user(handle: "zuck") {
            id
            name
            ... @include(if: $expandedInfo) {
                firstName
                lastName
                birthday
            }
        }
    }
>>,Q<<
    {
        field(arg: null)
        field
    }
>>,Q<<
    {
        nearestThing(location: { lon: 12.43, lat: -53.211 })
    }
    {
        nearestThing(location: { lat: -53.211, lon: 12.43 })
    }
>>,Q<<
    query getZuckProfile($devicePicSize: Int) {
        user(id: 4) {
            id
            name
            profilePic(size: $devicePicSize)
        }
    }
>>,Q<<
    {
        name
        age
        picture
    }
>>,Q<<
    {
        age
        name
    }
>>,Q<<
    {
        name
            relationship {
                name
        }
    }
>>,Q<<
    {
        foo
        ...Frag
        qux
    }

    fragment Frag on Query {
        bar
        baz
    }
>>,Q<<
    {
        foo
        ...Ignored
        ...Matching
        bar
    }

    fragment Ignored on UnknownType {
        qux
        baz
    }

    fragment Matching on Query {
        bar
        qux
        foo
    }
>>,Q<<
    {
        foo @skip(if: true)
        bar
        foo
    }
>>,Q<<
    {
        name
        picture(size: 600)
    }
>>,Q<<
    {
        entity {
            name
        }
        phoneNumber
    }
>>,Q<<
    query myQuery($someTest: Boolean) {
        experimentalField @skip(if: $someTest)
    }
>>,Q<<
    query myQuery($someTest: Boolean) {
        experimentalField @include(if: $someTest)
    }
>>,Q<<
    query getMe {
        me
    }
>>,Q<<
    mutation setName {
        setName(name: "Zuck") {
            newName
        }
    }
>>,Q<<
    {
        __type(name: "User") {
            name
            fields {
                name
                type {
                    name
            }
        }
        }
    }
>>,Q<<
    query getDogName {
        dog {
            name
        }
    }

    query getOwnerName {
        dog {
            owner {
                name
            }
        }
    }
>>,Q<<
    {
        dog {
            name
        }
    }
>>,Q<<
    {
        dog {
            ...fragmentOne
            ...fragmentTwo
        }
    }

    fragment fragmentOne on Dog {
        name
    }

    fragment fragmentTwo on Dog {
        owner {
            name
        }
    }
>>,Q<<
    query houseTrainedQuery($atOtherHomes: Boolean = true) {
        dog {
            isHousetrained(atOtherHomes: $atOtherHomes)
        }
    }
>>,Q<<
    query houseTrainedQuery($atOtherHomes: Boolean! = true) {
        dog {
            isHousetrained(atOtherHomes: $atOtherHomes)
        }
    }
>>,Q<<
    query houseTrainedQuery($atOtherHomes: Boolean = "true") {
        dog {
            isHousetrained(atOtherHomes: $atOtherHomes)
        }
    }
>>;

for @good -> $query
{
    ok GraphQL::Grammar.parse($query, rule => 'Document');
}

done-testing;
